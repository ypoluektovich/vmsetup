source ./vibaelia_storage_utils.sh

prepare_storage_setup() {
	modprobe ext4
	apk add --quiet sfdisk e2fsprogs
}

create_partitions() {
	local partline=""
	local dev="" mbr="" partcnt=0
	while read partline; do
		set -- $partline
		dev="$1"
		shift

		if [[ "$1" == "mbr" ]]; then
			mbr="/usr/share/syslinux/mbr.bin"
			shift
		else
			mbr=""
		fi

		# write the partition table
		echo "w" | fdisk "$dev" >/dev/null

		# make the partitions
		partcnt="$#"
		while [[ "$#" -gt 0 ]]; do
			echo "$1"
			shift
		done | sfdisk --quiet "$dev" >/dev/null

		# write the MBR if needed
		if [[ -n "$mbr" ]]; then
			dd if="$mbr" of="$dev" bs=$(stat -c "%s" "$mbr") count=1 conv=notrunc
		fi

		# list the created partitions
		for ix in $( seq "$partcnt" ); do
			echo "${dev}${ix}"
		done
	done < mkpart.txt
}

create_filesystems() {
	local part=""
	echo "$1" | while read part; do
		# no 64-bit support because syslinux can't into it
		mkfs.ext4 -q -O '^64bit' "$part"
	done
}

ROOT_DEVICE=""
mount_filesystems() {
	local dev="" mpt="" rmpt=""
	while read dev mpt; do
		if [[ "$mpt" == "/" ]]; then
			ROOT_DEVICE="$dev"
		fi
		rmpt="${ROOT_MOUNT}${mpt}"
		mkdir -p "$rmpt"
		echo "$rmpt"
		mount -t ext4 "$dev" "$rmpt"
	done < mount.txt | sort -r > umount.txt
}

umount_filesystems() {
	local mpt=""
	while read mpt; do
		umount "$mpt"
	done < umount.txt
}

setup_storage() {
	prepare_storage_setup

	local parts=""
	parts=$( create_partitions )
	echo "$parts"
	# create device nodes for new partitions
	mdev -s

	create_filesystems "$parts"

	mount_filesystems
}
