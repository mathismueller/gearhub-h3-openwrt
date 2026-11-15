#!/bin/sh
# Full OpenWrt source build — same steps as .github/workflows/build.yml.
# Needs x86_64 Linux with ~25 GB free (GH runner) or a lot of patience on
# the aarch64 container VM. ImageBuilder can't emit per-device initramfs,
# so there is no ImageBuilder path anymore.
set -eu
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.6}"

if [ ! -d openwrt-build ]; then
  git clone --branch "v${OPENWRT_VERSION}" --depth 1 \
    https://github.com/openwrt/openwrt.git openwrt-build
fi
cd openwrt-build
./scripts/feeds update -a
./scripts/feeds install -a
cat > .config <<EOF
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa7=y
EOF
make defconfig
cp -r ../files files
make -j"$(nproc)" world
ls -lh bin/targets/sunxi/cortexa7/ | head -n 20
