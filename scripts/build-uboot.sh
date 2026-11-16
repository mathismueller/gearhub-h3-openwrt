#!/usr/bin/env bash
# Build Stage-2 uboot24.bin (mainline U-Boot v2024.10) for FocalCrest GearHub H3.
set -euo pipefail

UBOOT_TAG="${UBOOT_TAG:-v2024.10}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UBOOT_DIR="${UBOOT_DIR:-${ROOT_DIR}/build/u-boot}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/artifacts}"
CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabihf-}"

mkdir -p "$(dirname "$UBOOT_DIR")" "$OUT_DIR"

if [ ! -d "$UBOOT_DIR/.git" ]; then
  git clone --depth 1 --branch "$UBOOT_TAG" https://github.com/u-boot/u-boot.git "$UBOOT_DIR"
fi

# SWIG 4.3+ (Ubuntu 24.04+) adds a 3rd arg to SWIG_Python_AppendOutput; SWIG_AppendOutput is portable
if [ -f "${UBOOT_DIR}/scripts/dtc/pylibfdt/libfdt.i_shipped" ]; then
  sed -i.bak 's/SWIG_Python_AppendOutput/SWIG_AppendOutput/g' \
    "${UBOOT_DIR}/scripts/dtc/pylibfdt/libfdt.i_shipped"
  rm -f "${UBOOT_DIR}/scripts/dtc/pylibfdt/libfdt.i_shipped.bak"
fi

DTB_PATH="${OUT_DIR}/sun8i-h3-focalcrest-gearhub.dtb"
DTS_FILE="${ROOT_DIR}/openwrt/target/sunxi/dts/sun8i-h3-focalcrest-gearhub.dts"
if [ -f "${UBOOT_DIR}/dts/upstream/src/arm/allwinner/sun8i-h3.dtsi" ]; then
  DTS_INC_ARGS="-I ${UBOOT_DIR}/dts/upstream/include -I ${UBOOT_DIR}/dts/upstream/src/arm/allwinner"
else
  DTS_INC_ARGS="-I ${UBOOT_DIR}/include -I ${UBOOT_DIR}/arch/arm/dts"
fi
cpp -nostdinc $DTS_INC_ARGS -undef -x assembler-with-cpp "$DTS_FILE" \
  | dtc -@ -I dts -O dtb -o "$DTB_PATH" -

make -C "$UBOOT_DIR" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" nanopi_m1_plus_defconfig
(
  cd "$UBOOT_DIR"
  ./scripts/kconfig/merge_config.sh -m .config "${ROOT_DIR}/uboot/gearhub.fragment"
)
make -C "$UBOOT_DIR" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" olddefconfig
make -C "$UBOOT_DIR" -j"$(nproc)" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" EXT_DTB="$DTB_PATH" u-boot.bin

cp "${UBOOT_DIR}/u-boot.bin" "${OUT_DIR}/uboot24.bin"
(cd "$OUT_DIR" && sha256sum uboot24.bin > uboot24.bin.sha256)
ls -lh "${OUT_DIR}/uboot24.bin"
