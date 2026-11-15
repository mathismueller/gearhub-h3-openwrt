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
MMC_NAME="${MMC##*/}"
P1_CUR_START="$(cat "/sys/block/${MMC_NAME}/${MMC_NAME}p1/start")"
P1_CUR_SIZE="$(cat "/sys/block/${MMC_NAME}/${MMC_NAME}p1/size")"
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

# Preflight 3: back up raw 0..2047 (1 MiB) + partition table + p1 + p2 for full rollback
if [ "${SKIP_BACKUP:-0}" != "1" ]; then
    mkdir -p "$BACKUP_DIR"
    dd if="$MMC" of="$BACKUP_DIR/stock-raw-0-2047.bin" bs=512 count=2048 conv=fsync
    partx -s "$MMC" > "$BACKUP_DIR/stock-ptable.txt" 2>/dev/null || true
    dd if="${MMC}p1" of="$BACKUP_DIR/stock-p1.img" bs=1M conv=fsync
    dd if="${MMC}p2" bs=1M | gzip -1 > "$BACKUP_DIR/stock-p2.img.gz"
    echo "Stock backup saved to $BACKUP_DIR (copy this off-device before rebooting!)"
fi

# Unpack OpenWrt sdcard image and locate its p2 (SquashFS)
RAW_IMG="/tmp/openwrt-sdcard.img"
case "$SDCARD_IMG" in
    *.gz) gzip -dc "$SDCARD_IMG" > "$RAW_IMG" ;;
    *)    cp "$SDCARD_IMG" "$RAW_IMG" ;;
esac

IMG_P2_START="$(dd if="$RAW_IMG" bs=1 skip=470 count=4 2>/dev/null | hexdump -e '1/4 "%u\n"')"
IMG_P2_SIZE="$(dd if="$RAW_IMG" bs=1 skip=474 count=4 2>/dev/null | hexdump -e '1/4 "%u\n"')"
[ -n "$IMG_P2_START" ] && [ -n "$IMG_P2_SIZE" ] && [ "$IMG_P2_SIZE" -gt 0 ] || {
    echo "ERROR: failed to read p2 geometry from $RAW_IMG" >&2
    exit 1
}

# Unmount p2/p3+ (leave p1 definition intact; only update p2 onward in table)
for p in "${MMC}"p*; do
    umount "$p" 2>/dev/null || true
done

if command -v sfdisk >/dev/null 2>&1; then
    sfdisk --no-reread "$MMC" <<EOF
label: dos
unit: sectors

${MMC}p1 : start=${P1_CUR_START}, size=${P1_CUR_SIZE}, type=c, bootable
${MMC}p2 : start=${P2_NEW_START}, type=83
EOF
    partprobe "$MMC" 2>/dev/null || partx -u "$MMC" 2>/dev/null || true
else
    # Update MBR p2 entry (offset 462) and clear p3/p4 (478..509), leaving p1 (446..461) intact
    DISK_SECTORS="$(cat "/sys/block/${MMC_NAME}/size")"
    P2_NEW_SIZE=$((DISK_SECTORS - P2_NEW_START))
    le32_esc() {
        printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
            $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255))
    }
    P2_FMT="\\x00\\xfe\\xff\\xff\\x83\\xfe\\xff\\xff$(le32_esc "$P2_NEW_START")$(le32_esc "$P2_NEW_SIZE")"
    printf "$P2_FMT" | dd of="$MMC" bs=1 seek=462 count=16 conv=notrunc 2>/dev/null
    dd if=/dev/zero of="$MMC" bs=1 seek=478 count=32 conv=notrunc 2>/dev/null
    sync
    partx -d --nr 2:4 "$MMC" 2>/dev/null || true
    partx -a --nr 2 "$MMC"
fi
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
