#!/bin/sh
# Build OpenWrt initramfs via official ImageBuilder (x86_64 only).
# Does NOT run on aarch64 Mac — use the GH Action instead.
set -eu
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"
TARGET="${TARGET:-sunxi/cortexa7}"
PROFILE="$(cat openwrt/PROXY_PROFILE | grep -v '^#' | grep PROXY_PROFILE | cut -d= -f2)"
IB="openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET/\//-}.Linux-x86_64"
URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${IB}.tar.zst"

echo "==> downloading ${URL}"
curl -fSL -o "/tmp/${IB}.tar.zst" "${URL}"
tar --use-compress-program=unzstd -xf "/tmp/${IB}.tar.zst" -C /tmp
cd "/tmp/${IB}"

echo "==> building initramfs for ${PROFILE}"
make image PROFILE="${PROFILE}" \
  PACKAGES="ser2net kmod-brcmfmac cypress-firmware-43430-sdio kmod-gpio-button-hotplug kmod-rtc-sunxi kmod-leds-gpio -dnsmasq -wpad-basic-mbedtls" \
  FILES="$OLDPWD/files/"

echo "==> artifacts:"
ls -lh bin/targets/${TARGET}/*initramfs-kernel.bin bin/targets/${TARGET}/*.manifest
