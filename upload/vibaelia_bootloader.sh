setup_bootloader() {
	local root_fs="ext4"
	local initfs_features="ata base ide scsi usb virtio"
	local rootdev=$(uuid_or_device $ROOT_DEVICE)
	local modules=""
	local kernel_opts=""

	initfs_features="$initfs_features $root_fs"

	mkdir -p "$ROOT_MOUNT"/etc/mkinitfs/features.d
	echo "features=\"$initfs_features\"" > "$ROOT_MOUNT"/etc/mkinitfs/mkinitfs.conf

	kernel_opts="$kernel_opts rootfstype=$root_fs"
	modules="sd-mod,usb-storage,${root_fs}"

    mkdir -p /mnt/boot

	sed -e "s:^root=.*:root=$rootdev:" \
		-e "s:^default_kernel_opts=.*:default_kernel_opts=\"$kernel_opts\":" \
		-e "s:^modules=.*:modules=$modules:" \
		/etc/update-extlinux.conf > "$ROOT_MOUNT"/etc/update-extlinux.conf

	extlinux --install "$ROOT_MOUNT"/boot
}
