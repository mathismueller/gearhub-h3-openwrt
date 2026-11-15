# Fragment to merge into the stage-2 chainloader boot.cmd (after uEnv.txt import).
# Stage-1 trampoline + uboot24.bin stay frozen. Adds os=openwrt|alpine selector.
# Compile with: mkimage -C none -A arm -T script -d boot.cmd boot.scr

# defaults (keep Alpine behaviour)
if test -z "${os}"; then
    setenv os alpine
fi

if test "${os}" = "openwrt"; then
    echo "Booting OpenWrt initramfs (devpart ${root_devpart})..."
    setenv fdt_high ffffffff
    setenv bootargs console=ttyS0,115200 earlyprintk root=/dev/ram0 rootwait rw
    load ${devtype} ${root_devpart} ${kernel_addr_r} /boot/openwrt-initramfs-kernel.bin
    load ${devtype} ${root_devpart} ${fdt_addr_r} /boot/sun8i-h3-focalcrest-gearhub.dtb
    bootm ${kernel_addr_r} - ${fdt_addr_r}
fi

# ... existing Alpine lts / 5.10 branches follow unchanged ...
