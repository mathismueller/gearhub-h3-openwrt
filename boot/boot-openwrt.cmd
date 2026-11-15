# U-Boot boot script for FocalCrest GearHub H3 (OpenWrt eMMC).
# Supports both:
#   - Stage-1 (Factory U-Boot 2020.04): Chainload U-Boot 2024.10 into RAM
#   - Stage-2 (U-Boot 2024.10):         Boot OpenWrt SquashFS from mmcblk1p2
# Compile with: mkimage -C none -A arm -T script -d boot-openwrt.cmd boot.scr

if test -z "${usb_ignorelist}"; then
    echo "=== [Stage-1] Chainloading U-Boot 2024.10 ==="
    mw.l 0x49000000 0xe3a0044a
    mw.l 0x49000004 0xe2801601
    mw.l 0x49000008 0xee070f3e
    mw.l 0x4900000c 0xe2800020
    mw.l 0x49000010 0xe1500001
    mw.l 0x49000014 0x3afffffb
    mw.l 0x49000018 0xe3a00000
    mw.l 0x4900001c 0xee070f15
    mw.l 0x49000020 0xf57ff04f
    mw.l 0x49000024 0xf57ff06f
    mw.l 0x49000028 0xe3a0f44a
    fatload mmc 1:1 0x4a000000 uboot24.bin
    go 0x49000000
fi

echo "=== [Stage-2] OpenWrt eMMC Boot ==="
setenv fdt_high ffffffff
setenv bootargs "console=ttyS0,115200 earlyprintk root=/dev/mmcblk1p2 rootwait watchdog.open_timeout=0"
load mmc 1:1 ${kernel_addr_r} /boot/zImage
load mmc 1:1 ${fdt_addr_r} /boot/sun8i-h3-focalcrest-gearhub.dtb
bootz ${kernel_addr_r} - ${fdt_addr_r}
