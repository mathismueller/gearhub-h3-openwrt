#!/bin/sh
# Validate the GearHub DTS: dtc round-trip + (in Debian container) dtbs_check.
set -eu
DTS="openwrt/target/sunxi/dts/sun8i-h3-focalcrest-gearhub.dts"
command -v dtc >/dev/null || { echo "install dtc (brew install dtc)" >&2; exit 1; }
dtc -I dts -O dtb -o /tmp/gearhub.dtb "$DTS"
echo "dtc OK: $DTS -> /tmp/gearhub.dtb"
echo "for dtbs_check, run inside the Debian container with dtschema + linux tree"
