#!/bin/sh
# Phase-1 one-shot eMMC installer — run INSIDE RAM-booted OpenWrt initramfs.
# Zero-window anti-brick design:
#   - Sectors 0..2047 (factory SPL, U-Boot, 0x88000 env) are NEVER written.
#   - Existing p1 FAT partition (uboot24.bin + stage-1 /boot.scr) is kept
#     in-place and NEVER reformatted or overwritten with dd.
#   - Only p2 onward is repartitioned and flashed with OpenWrt SquashFS
#     from a standard *-squashfs-sdcard.img[.gz].
set -eu

MMC="${MMC:-/dev/mmcblk0}"
[ -b "$MMC" ] || MMC="/dev/mmcblk1"
[ -b "$MMC" ] || { echo "ERROR: no eMMC block device found" >&2; exit 1; }

SDCARD_IMG="${1:-}"
ZIMAGE="${2:-}"
DTB="${3:-}"
BOOT_SCR="${4:-}"
BACKUP_DIR="${5:-/tmp/stock-backup}"

for f in "$SDCARD_IMG" "$ZIMAGE" "$DTB" "$BOOT_SCR"; do
    [ -n "$f" ] && [ -s "$f" ] || {
        echo "Usage: $0 <squashfs-sdcard.img[.gz]> <zImage> <gearhub.dtb> <boot.scr> [stock-backup-dir]" >&2
        exit 1
    }
done

# Preflight 1: verify factory U-Boot env at 0x88000 is readable
echo "$MMC 0x88000 0x20000" > /etc/fw_env.config
ETHADDR="$(fw_printenv -n ethaddr 2>/dev/null || true)"
[ -n "$ETHADDR" ] || { echo "ERROR: cannot read ethaddr from $MMC @ 0x88000; aborting" >&2; exit 1; }
echo "Preflight OK: $MMC ethaddr=$ETHADDR"

# Preflight 2: verify existing p1 starts >= 2048 and holds uboot24.bin + boot.scr
P1_CUR="$(sfdisk -l -o Start,Sectors "$MMC" | awk -v dev="${MMC}p1" '$1 == dev || $0 ~ dev {print $2, $3}' || true)"
P1_CUR_START="$(sfdisk -d "$MMC" | awk -F'start=|,' -v dev="${MMC}p1" '$0 ~ dev {gsub(/ /,"",$2); print $2}')"
P1_CUR_SIZE="$(sfdisk -d "$MMC" | awk -F'size=|,' -v dev="${MMC}p1" '$0 ~ dev {gsub(/ /,"",$4); print $4}')"
[ -n "$P1_CUR_START" ] && [ "$P1_CUR_START" -ge 2048 ] || {
    echo "ERROR: existing ${MMC}p1 start ($P1_CUR_START) < 2048; aborting" >&2
    exit 1
}
P2_NEW_START=$((P1_CUR_START + P1_CUR_SIZE))

mkdir -p /tmp/p1
mount -o ro "${MMC}p1" /tmp/p1
[ -s /tmp/p1/uboot24.bin ] || { umount /tmp/p1; echo "ERROR: uboot24.bin missing on ${MMC}p1; aborting" >&2; exit 1; }
[ -s /tmp/p1/boot.scr ] || { umount /tmp/p1; echo "ERROR: chainloader boot.scr missing on ${MMC}p1; aborting" >&2; exit 1; }
umount /tmp/p1

# Preflight 3: back up stock partition table + p1 + p2 for clean rollback
mkdir -p "$BACKUP_DIR"
sfdisk -d "$MMC" > "$BACKUP_DIR/stock-ptable.sfdisk"
dd if="${MMC}p1" of="$BACKUP_DIR/stock-p1.img" bs=1M conv=fsync
dd if="${MMC}p2" bs=1M | gzip -1 > "$BACKUP_DIR/stock-p2.img.gz"
echo "Stock backup saved to $BACKUP_DIR (copy this off-device before rebooting!)"

# Unpack OpenWrt sdcard image and locate its p1 (kernel/dtb) and p2 (SquashFS)
RAW_IMG="/tmp/openwrt-sdcard.img"
case "$SDCARD_IMG" in
    *.gz) gzip -dc "$SDCARD_IMG" > "$RAW_IMG" ;;
    *)    cp "$SDCARD_IMG" "$RAW_IMG" ;;
esac

IMG_P1_START="$(sfdisk -d "$RAW_IMG" | awk -F'start=|,' '/img1/ {gsub(/ /,"",$2); print $2}')"
IMG_P2_START="$(sfdisk -d "$RAW_IMG" | awk -F'start=|,' '/img2/ {gsub(/ /,"",$2); print $2}')"
IMG_P2_SIZE="$(sfdisk -d "$RAW_IMG" | awk -F'size=|,' '/img2/ {gsub(/ /,"",$4); print $4}')"

# Unmount p2/p3+ (leave p1 definition intact; only update p2 onward in table)
for p in "${MMC}"p*; do
    umount "$p" 2>/dev/null || true
done

sfdisk --no-reread "$MMC" <<EOF
label: dos
unit: sectors

${MMC}p1 : start=${P1_CUR_START}, size=${P1_CUR_SIZE}, type=c, bootable
${MMC}p2 : start=${P2_NEW_START}, type=83
EOF

partprobe "$MMC" 2>/dev/null || true
sleep 2

# Write p2 SquashFS from OpenWrt sdcard image (OpenWrt fstools auto-creates rootfs_data overlay)
dd if="$RAW_IMG" of="${MMC}p2" bs=512 skip="$IMG_P2_START" count="$IMG_P2_SIZE" conv=fsync

# Copy OpenWrt zImage, GearHub DTB, and boot.scr onto existing p1 (uboot24.bin untouched)
mkdir -p /tmp/p1
mount "${MMC}p1" /tmp/p1
mkdir -p /tmp/p1/boot
cp "$ZIMAGE" /tmp/p1/boot/zImage
cp "$DTB" /tmp/p1/boot/sun8i-h3-focalcrest-gearhub.dtb
cp "$BOOT_SCR" /tmp/p1/boot.scr
sync
umount /tmp/p1
rm -f "$RAW_IMG"

echo "DONE: ${MMC}p1 kept in-place (uboot24.bin + /boot.scr untouched), ${MMC}p2 flashed."
