# Safe sysupgrade platform.sh for FocalCrest GearHub H3.
# Overrides OpenWrt sunxi/base-files/lib/upgrade/platform.sh to guarantee:
#   1. Raw eMMC sectors 0..2047 (factory SPL, U-Boot, 0x88000 env) are NEVER written.
#   2. p1 FAT is NEVER dd-overwritten (uboot24.bin + stage-1 /boot.scr preserved).
#   3. Only p1:/boot/ kernel+DTB and p2 rootfs are updated.

platform_check_image() {
	local diskdev p2_line

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	get_image "$@" | dd of=/tmp/image.bs count=1 bs=512b 2>/dev/null
	get_partitions /tmp/image.bs image
	p2_line="$(awk '$1 == 2 {print}' /tmp/partmap.image)"
	rm -f /tmp/image.bs /tmp/partmap.image

	[ -n "$p2_line" ] || {
		echo "Invalid image: missing partition 2"
		return 1
	}

	return 0
}

platform_copy_config() {
	local partdev

	if export_partdevice partdev 1; then
		mount -t vfat -o rw,noatime "/dev/$partdev" /mnt
		cp -af "$UPGRADE_BACKUP" "/mnt/$BACKUP_FILE"
		sync
		umount /mnt
	fi
}

platform_do_upgrade() {
	local diskdev part1 part2
	local p1_start p1_size p2_start p2_size

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}
	export_partdevice part1 1 || { echo "Missing p1"; return 1; }
	export_partdevice part2 2 || { echo "Missing p2"; return 1; }

	sync

	get_image "$@" | dd of=/tmp/image.bs count=1 bs=512b 2>/dev/null
	get_partitions /tmp/image.bs image
	rm -f /tmp/image.bs

	p1_start="$(awk '$1 == 1 {print $2}' /tmp/partmap.image)"
	p1_size="$(awk '$1 == 1 {print $3}' /tmp/partmap.image)"
	p2_start="$(awk '$1 == 2 {print $2}' /tmp/partmap.image)"
	p2_size="$(awk '$1 == 2 {print $3}' /tmp/partmap.image)"
	rm -f /tmp/partmap.image

	# Update p1:/boot/ in-place (never touch uboot24.bin, /boot.scr, or 0..2047)
	if [ -n "$p1_start" ] && [ -n "$p1_size" ]; then
		get_image "$@" | dd of=/tmp/img-p1.vfat ibs=512 obs=1M skip="$p1_start" count="$p1_size" 2>/dev/null
		mkdir -p /tmp/img-p1 /tmp/emmc-p1
		if mount -t vfat -o ro,loop /tmp/img-p1.vfat /tmp/img-p1; then
			mount -t vfat -o rw,noatime "/dev/$part1" /tmp/emmc-p1
			mkdir -p /tmp/emmc-p1/boot
			cp -af /tmp/img-p1/* /tmp/emmc-p1/boot/ 2>/dev/null || true
			sync
			umount /tmp/emmc-p1
			umount /tmp/img-p1
		fi
		rm -f /tmp/img-p1.vfat
	fi

	# Write p2 rootfs only
	echo "Writing rootfs to /dev/$part2..."
	get_image "$@" | dd of="/dev/$part2" ibs=512 obs=1M skip="$p2_start" count="$p2_size" conv=fsync
	sync
}
