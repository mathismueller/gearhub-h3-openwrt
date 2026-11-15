#!/bin/sh
# Full OpenWrt source build — same steps as .github/workflows/build.yml.
# Needs x86_64 Linux with ~25 GB free (GH runner) or a lot of patience on
# the aarch64 container VM.
set -eu
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.6}"
PROFILE="${PROFILE:-friendlyarm_nanopi-m1-plus}"

if [ ! -d openwrt-build ]; then
  git clone --branch "v${OPENWRT_VERSION}" --depth 1 \
    https://github.com/openwrt/openwrt.git openwrt-build
fi
cd openwrt-build
./scripts/feeds update -a
./scripts/feeds install -a
{
  echo "CONFIG_GPIO_WATCHDOG=y"
  echo "CONFIG_GPIO_WATCHDOG_ARCH_INITCALL=y"
} >> target/linux/sunxi/config-6.12
cat > .config <<EOF
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa7=y
CONFIG_TARGET_sunxi_cortexa7_DEVICE_${PROFILE}=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_CCACHE=y
CONFIG_PACKAGE_ser2net=y
CONFIG_PACKAGE_uboot-envtools=y
CONFIG_PACKAGE_gpiod-tools=y
CONFIG_PACKAGE_kmod-rtc-sunxi=y
CONFIG_PACKAGE_kmod-rtc-pcf8563=y
CONFIG_PACKAGE_kmod-spi-dev=y
EOF
make defconfig
cp -r ../files files
make -j"$(nproc)"
ls -lh bin/targets/sunxi/cortexa7/ | head -n 20
