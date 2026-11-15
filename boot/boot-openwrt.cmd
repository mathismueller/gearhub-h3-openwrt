# Boot script fragment for stage-2 uboot24.bin (FAT p1: /boot.scr).
# Leaves factory SPL/U-Boot (sectors 0..2047) and uboot24.bin untouched.
# Compile with: mkimage -C none -A arm -T script -d boot-openwrt.cmd boot.scr

setenv fdt_high ffffffff
setenv bootargs "console=ttyS0,115200 earlyprintk root=/dev/mmcblk0p2 rootwait watchdog.open_timeout=0"

if test -e ${devtype} ${devnum}:${distro_bootpart} /boot/zImage; then
    load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /boot/zImage
    load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} /boot/sun8i-h3-focalcrest-gearhub.dtb
    bootz ${kernel_addr_r} - ${fdt_addr_r}
fi
