# gearhub-h3-openwrt

OpenWrt PoC for the **FocalCrest GearHub H3** (`RFC24 V 2.0`, Allwinner H3 `sunxi/cortexa7`) — aka Hornbach Smart Home Gateway V2.

Scope is deliberately narrow: **RAM-boot `initramfs` only, no eMMC `sysupgrade` yet.** The gateway becomes a radio-only `ser2net` box; Zigbee2MQTT / Z-Wave JS run on a remote 64-bit host (both are Node apps hitting the 32-bit EOL cliff).

## Hardware

* SoC: Allwinner H3, 4x Cortex-A7, 1 GiB DDR3, 8 GB eMMC (`/dev/mmcblk1`)
* Zigbee/Thread: EFR32MG24 on `/dev/ttyS2` (`PA08/PA07`, 39 MHz HFXO) — flash our `zigbee_ncp` (`115200` EZSP) or `ot-rcp` (`115200` Spinel) from `silabs-firmware-builder`
* Z-Wave: EFR32ZG23 on `/dev/ttyS3` (`115200 8N1`, no flow) — flash `8.1.1`, stock `7.22.0` has TX-queue/jam lockups
* Stock has **no A/B**, no USB/Ethernet in factory U-Boot 2020.04. First boot the chainloader (`uboot24.bin`, U-Boot 2024.10), then USB/TFTP works.

## Repo layout

* `openwrt/` — `Device/focalcrest_gearhub` stanza + cleaned `sun8i-h3-focalcrest-gearhub.dts` (upstreaming material, not yet applied to ImageBuilder)
* `files/` — ImageBuilder overlay: `ser2net.yaml`, `sysupgrade.conf`
* `boot/boot-openwrt.cmd` — `os=openwrt` stanza to merge into the chainloader `boot.cmd`
* `scripts/build.sh` — x86_64-only ImageBuilder wrapper (does **not** run on aarch64 Mac, use GH Action)
* `.github/workflows/imagebuilder.yml` — builds `initramfs-kernel.bin` on `25.12` + publishes artifacts

## Fast debug loop (no flash)

1. `./gw-ctl halt-boot` (serial `/dev/cu.usbserial-310@115200` + smart-plug power-cycle), or SSH `192.168.188.224` / link-local `169.254.77.2` on `en7`.
2. `usb start; fatload usb 0:1 $kernel_addr_r openwrt-initramfs.bin; fatload mmc 1:1 $fdt_addr_r sun8i-h3-focalcrest-gearhub.dtb; bootm` (or `dhcp; tftpboot` on `en7`).
3. Serial shell → check `eth0`, `dmesg | grep compatible`, `ser2net -n` proxies `ttyS2:3332`, `ttyS3:3333`.

Done = serial shell + eth + correct `compatible` + remote `z2m`/`zwave-js` connect over TCP. eMMC untouched (raw `0..2047` never written).

## Releases

GH Releases carry `openwrt-*-initramfs-kernel.bin` + `sha256sums` + `manifest`. No `sdcard.img.gz` / `sysupgrade.bin` until the DTS is validated in RAM.
