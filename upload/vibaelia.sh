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
ROOT_MOUNT=/mnt
ARCH=x86_64
KERNEL_FLAVOR=virthardened

source ./vibaelia_storage.sh
source ./vibaelia_bootloader.sh

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

cleanup_chroot_mounts() {
	local mnt="$1" i=
	for i in proc dev; do
		umount "$mnt"/$i
	done
}

install_mounted_root() {
	# generate the fstab
	rm -f "$ROOT_MOUNT"/etc/fstab
	enumerate_fstab "$ROOT_MOUNT" >> "$ROOT_MOUNT"/etc/fstab

	chroot_caps=$(set_grsec chroot_caps 0)
	init_chroot_mounts "$ROOT_MOUNT"

	source vibaelia_utils.sh

	### INSTALL
	apk add $APK_THERE --initdb
	add_apk_repositories "$ROOT_MOUNT/"
	apk update $APK_THERE --quiet --allow-untrusted
	$APK_ADD --allow-untrusted alpine-keys
	apk update $APK_THERE --quiet
	$APK_ADD `cat pkgs.txt`
	[[ -f profile/pkgs.txt ]] && $APK_ADD `cat profile/pkgs.txt`
	### / INSTALL

	### copy stuff from bootstrap install
	# enabled services
	cp -ra /etc/runlevels/* "$ROOT_MOUNT/etc/runlevels"
	cp /etc/inittab /etc/securetty "$ROOT_MOUNT/etc/"
	# we should not try start modloop on sys install
	rm -f "$ROOT_MOUNT"/etc/runlevels/*/modloop
	### / copy stuff

	setup_interfaces "$ROOT_MOUNT/" "profile/interfaces.txt"
	setup_tz "$ROOT_MOUNT/"

	### set up sshd
	# openssh-server is already installed, just need to copy configs into place
	mkdir -p "$ROOT_MOUNT/etc/ssh"
	cp profile/ssh_host_keys/* "$ROOT_MOUNT/etc/ssh"
	cp profile/sshd_config.txt "$ROOT_MOUNT/etc/ssh/sshd_config"

	### set up root account
	./random-passwd-input.sh | $CHROOTED passwd
	mkdir -p "$ROOT_MOUNT/etc/ssh/users/root"
	cp profile/root_authorized_keys.txt "$ROOT_MOUNT/etc/ssh/users/root/authorized_keys"

	### set up user accounts
	local username= userhome= userhomeargs= usershell= userix=0
	while read username userhome usershell; do
		echo "setting up user ${username} with id $((1000 + userix))"
		case "$userhome" in
			"-") userhomeargs="-H" ;;
			*) userhomeargs="-h $userhome" ;;
		esac

        ./random-passwd-input.sh | $CHROOTED adduser -u $((1000 + userix)) $userhomeargs -s $usershell $username users
		mkdir -p "$ROOT_MOUNT/etc/ssh/users/$username"
		cp "profile/users/$username/authorized_keys.txt" "$ROOT_MOUNT/etc/ssh/users/$username/authorized_keys"
		$CHROOTED chown -R "$username:users" "/etc/ssh/users/$username"
		userix=$((userix + 1))
	done < profile/users/users.txt

	chmod -R a=X,u+r "$ROOT_MOUNT"/etc/ssh

	[[ -f profile/vibaelia.sh ]] && ( source ./profile/vibaelia.sh )

	cleanup_chroot_mounts "$ROOT_MOUNT"
	set_grsec chroot_caps $chroot_caps > /dev/null
}

native_disk_install() {
	# we need to do it before storage, because it contains the MBR file
	apk add --quiet syslinux

	setup_storage
	setup_bootloader
	install_mounted_root
	umount_filesystems
}


native_disk_install
