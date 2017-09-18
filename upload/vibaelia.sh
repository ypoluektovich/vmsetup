#!/usr/bin/env sh

set -xe

source early_utils.sh

rc-update --quiet add networking boot
rc-update --quiet add urandom boot
rc-update --quiet add acpid
#rc-update --quiet add cron
#rc-update --quiet add crond

# add apk repositories
add_apk_repositories() {
	local ROOT="$1"
	echo "https://mirror.yandex.ru/mirrors/alpine/edge/main" >> "${ROOT}etc/apk/repositories"
	echo "https://mirror.yandex.ru/mirrors/alpine/edge/community" >> "${ROOT}etc/apk/repositories"
	echo "https://mirror.yandex.ru/mirrors/alpine/edge/testing" >> "${ROOT}etc/apk/repositories"
}
add_apk_repositories "/"
apk update --quiet

# enable busybox ntpd (again, for services)
rc-update add ntpd default
rc-service ntpd start


# SETUP DISK

MBR="/usr/share/syslinux/mbr.bin"
SYSROOT=/mnt
ARCH=x86_64
KERNEL_FLAVOR=virthardened

# wrapper to only show given device
_blkid() {
	blkid | grep "^$1:"
}

# if given device have an UUID display it, otherwise return the device
uuid_or_device() {
	local i=
	for i in $(_blkid "$1"); do
		case "$i" in
			UUID=*) eval $i;;
		esac
	done
	if [ -n "$UUID" ]; then
		echo "UUID=$UUID"
	else
		echo "$1"
	fi
}

# generate an fstab from a given mountpoint. Convert to UUID if possible
enumerate_fstab() {
	local mnt="$1"
	local fs_spec= fs_file= fs_vfstype= fs_mntops= fs_freq= fs_passno=
	[ -z "$mnt" ] && return
	local escaped_mnt=$(echo $mnt | sed -e 's:/*$::' -e 's:/:\\/:g')
	awk "\$2 ~ /^$escaped_mnt(\/|\$)/ {print \$0}" /proc/mounts | \
		sed "s:$mnt:/:g; s: :\t:g" | sed -E 's:/+:/:g' | \
		while read fs_spec fs_file fs_vfstype fs_mntops fs_freq fs_passno; do
			echo -e "$(uuid_or_device $fs_spec)\t${fs_file}\t${fs_vfstype}\t${fs_mntops} ${fs_freq} ${fs_passno}"
		done
}

# echo current grsecurity option and set new
set_grsec() {
	local key="$1" value="$2"
	if ! [ -e /proc/sys/kernel/grsecurity/$key ]; then
		return 0
	fi
	cat /proc/sys/kernel/grsecurity/$key
	echo $value > /proc/sys/kernel/grsecurity/$key
}

init_chroot_mounts() {
	local mnt="$1" i=
	for i in proc dev; do
		mkdir -p "$mnt"/$i
		mount --bind /$i "$mnt"/$i
	done
}

# setup syslinux bootloader
setup_syslinux() {
	local mnt="$1" root="$2" modules="$3" kernel_opts="$4" bootdev="$5"

	sed -e "s:^root=.*:root=$root:" \
		-e "s:^default_kernel_opts=.*:default_kernel_opts=\"$kernel_opts\":" \
		-e "s:^modules=.*:modules=$modules:" \
		/etc/update-extlinux.conf > "$mnt"/etc/update-extlinux.conf

	extlinux --install "$mnt"/boot
}

cleanup_chroot_mounts() {
	local mnt="$1" i=
	for i in proc dev; do
		umount "$mnt"/$i
	done
}

install_mounted_root() {
	local mnt="$SYSROOT"
	shift 1
	local disks="/dev/sda" root_fs=
	local initfs_features="ata base ide scsi usb virtio"
	local rootdev= bootdev= root= modules=
	local kernel_opts=""

	rootdev="/dev/sda1"
	root_fs="ext4"
	initfs_features="$initfs_features $root_fs"

	bootdev=$rootdev

	# generate mkinitfs.conf
	mkdir -p "$mnt"/etc/mkinitfs/features.d
	echo "features=\"$initfs_features\"" > "$mnt"/etc/mkinitfs/mkinitfs.conf

	# generate update-extlinux.conf
	root=$(uuid_or_device $rootdev)
	kernel_opts="$kernel_opts rootfstype=$root_fs"
	modules="sd-mod,usb-storage,${root_fs}"

	# generate the fstab
	rm -f "$mnt"/etc/fstab
	enumerate_fstab "$mnt" >> "$mnt"/etc/fstab

    mkdir -p /mnt/boot
    setup_syslinux "$mnt" "$root" "$modules" "$kernel_opts" "$bootdev"

	chroot_caps=$(set_grsec chroot_caps 0)
	init_chroot_mounts "$mnt"

	source vibaelia_utils.sh

	### INSTALL
    local THERE="--root $mnt"
	apk add $THERE --initdb
	add_apk_repositories "$mnt/"
	apk update $THERE --quiet --allow-untrusted
	$APK_ADD --allow-untrusted alpine-keys
	apk update $THERE --quiet
	$APK_ADD `cat pkgs.txt`
	[[ -f profile/pkgs.txt ]] && $APK_ADD `cat profile/pkgs.txt`
	### / INSTALL

	### copy stuff from bootstrap install
	# enabled services
	cp -ra /etc/runlevels/* "$mnt/etc/runlevels"
	cp /etc/inittab /etc/securetty "$mnt/etc/"
	### / copy stuff

	# we should not try start modloop on sys install
	rm -f "$mnt"/etc/runlevels/*/modloop

	setup_interfaces "$mnt/" "profile/interfaces.txt"
	setup_tz "$mnt/"

	### set up sshd
	# openssh-server is already installed, just need to copy configs into place
	mkdir -p "$mnt/etc/ssh"
	cp profile/ssh_host_keys/* "$mnt/etc/ssh"
	cp profile/sshd_config.txt "$mnt/etc/ssh/sshd_config"

	### set up root account
	./random-passwd-input.sh | $CHROOTED passwd
	mkdir -p "$mnt/etc/ssh/users/root"
	cp profile/root_authorized_keys.txt "$mnt/etc/ssh/users/root/authorized_keys"

	### set up user accounts
	local username= userhome= userhomeargs= usershell= userix=0
	while read username userhome usershell; do
		echo "setting up user ${username} with id $((1000 + userix))"
		case "$userhome" in
			"-") userhomeargs="-H" ;;
			*) userhomeargs="-h $userhome" ;;
		esac

        ./random-passwd-input.sh | $CHROOTED adduser -u $((1000 + userix)) $userhomeargs -s $usershell $username users
		mkdir -p "$mnt/etc/ssh/users/$username"
		cp "profile/users/$username/authorized_keys.txt" "$mnt/etc/ssh/users/$username/authorized_keys"
		$CHROOTED chown -R "$username:users" "/etc/ssh/users/$username"
		userix=$((userix + 1))
	done < profile/users/users.txt

	chmod -R a=X,u+r "$mnt"/etc/ssh

	[[ -f profile/vibaelia.sh ]] && ./profile/vibaelia.sh

	cleanup_chroot_mounts "$mnt"
	set_grsec chroot_caps $chroot_caps > /dev/null
}

native_disk_install() {
	modprobe ext4
	apk add --quiet sfdisk e2fsprogs syslinux

	dd if=/dev/zero of=/dev/sda || true
	
	### setup_partitions /dev/sda ",83,*"
	echo "w" | fdisk /dev/sda >/dev/null
	cat "$MBR" > /dev/sda
	echo "1M,,83,*" | sfdisk --quiet /dev/sda >/dev/null
	# create device nodes if not exist
	mdev -s

	mkfs.ext4 -q -O '^64bit' /dev/sda1

	### setup_root
	local root_dev="/dev/sda1" boot_dev="/dev/sda1"
	local disks="/dev/sda" mkfs_args="-q"
	mkdir -p "$SYSROOT"
	mount -t ext4 /dev/sda1 "$SYSROOT"
	mkdir -p "${SYSROOT}/git"
	mount -t ext4 /dev/sdb "${SYSROOT}/git"

	install_mounted_root

	umount "${SYSROOT}/git"
	umount "$SYSROOT"
}


native_disk_install
