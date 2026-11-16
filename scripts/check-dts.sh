#!/bin/sh
# Validate the GearHub DTS: preprocess against LINUX_DIR (if set) + dtc round-trip.
set -eu
DTS="openwrt/target/sunxi/dts/sun8i-h3-focalcrest-gearhub.dts"
command -v dtc >/dev/null || { echo "install dtc (brew install dtc)" >&2; exit 1; }

if [ -n "${LINUX_DIR:-}" ]; then
  cpp -nostdinc \
    -I "${LINUX_DIR}/include" \
    -I "${LINUX_DIR}/arch/arm/boot/dts/allwinner" \
    -undef -x assembler-with-cpp "$DTS" \
    | dtc -I dts -O dtb -o /tmp/gearhub.dtb -
  echo "dtc OK: $DTS -> /tmp/gearhub.dtb"
else
  echo "Set LINUX_DIR=/path/to/linux (or DTS_INC=/tmp/linux-dts) to preprocess #include \"sun8i-h3.dtsi\"" >&2
  if [ -n "${DTS_INC:-}" ]; then
    clang -E -nostdinc -I "$DTS_INC" -undef -x assembler-with-cpp "$DTS" \
      | dtc -I dts -O dtb -o /tmp/gearhub.dtb -
    echo "dtc OK: $DTS -> /tmp/gearhub.dtb"
  fi
fi
