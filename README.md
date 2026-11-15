# gearhub-h3-openwrt

OpenWrt port for the **FocalCrest GearHub H3** (`RFC24 V 2.0`, Allwinner H3 `sunxi/cortexa7`) — aka Hornbach Smart Home Gateway V2.

Target: stock OpenWrt experience (wired Ethernet, Wi-Fi `brcmfmac`, `ser2net` for `/dev/ttyS2` + `/dev/ttyS3`, status LEDs, reset button, and optional standard Bluetooth), with Zigbee2MQTT / Z-Wave JS running on a remote 64-bit host.

## Hardware

* SoC: Allwinner H3, 4x Cortex-A7, 1 GiB DDR3, 8 GB eMMC (`/dev/mmcblk0` / `/dev/mmcblk1`)
* Zigbee/Thread: EFR32MG24 on `/dev/ttyS2` (`PA08/PA07`, 39 MHz HFXO, `PD9` reset) — flash `zigbee_ncp` (`115200` EZSP) or `ot-rcp` (`115200` Spinel) from `silabs-firmware-builder`
* Z-Wave: EFR32ZG23 on `/dev/ttyS3` (`115200 8N1`, no flow, `PD15` reset) — flash `8.1.1` (stock `7.22.0` has TX-queue/jam lockups)
* Watchdogs: internal `sunxi_wdt` (`/dev/watchdog0`, petted by `procd`) + external `PL10` `gpio_wdt` (`always-running`, requires `CONFIG_GPIO_WATCHDOG=y` + `watchdog.open_timeout=0`)
* Bootloader safety: raw eMMC sectors `0..2047` (factory SPL, U-Boot 2020.04, `0x88000` env) stay **untouched**; stage-2 `uboot24.bin` on `p1` FAT provides USB/TFTP recovery

## Repo layout

* `ROADMAP.md` — Phased plan (RAM-boot → safe eMMC + stock rollback → releases → upstreaming)
* `openwrt/` — `Device/focalcrest_gearhub` stanza + `dtc`-compiled `sun8i-h3-focalcrest-gearhub.dts`
* `files/` — OpenWrt rootfs overlay: `ser2net.yaml`, `sysupgrade.conf`, `init.d/gearhub-hw`, `rc.button/reset`, and safe `lib/upgrade/platform.sh`
* `boot/boot-openwrt.cmd` — Stage-2 `uboot24.bin` eMMC boot script (`bootz` + `watchdog.open_timeout=0`)
* `scripts/serial-mux.py` & `scripts/first-boot.py` — Phase 0 serial mux + TFTP RAM-boot automation
* `scripts/install-emmc.sh` — Phase 1 zero-window eMMC installer (preserves `0..2047`, `p1` chainloader, and backs up stock `p1`/`p2` for rollback)
* `scripts/build.sh` & `.github/workflows/build.yml` — Full `25.12.6` source build (`CONFIG_GPIO_WATCHDOG=y` + `dl/`/`ccache` caching)

## Phase 0 Debug Loop (RAM-boot, Zero eMMC Writes)

1. Start serial mux (`uv run python scripts/serial-mux.py -d /dev/cu.usbserial-110 -l /tmp/gateway-serial.log -p 3335`) and TFTP server on `:69` (`169.254.65.108`).
2. Run `python3 scripts/first-boot.py` (or `NO_REBOOT=1` + power-cycle) to TFTP-load `openwrt-initramfs-zImage` + `sun8i-h3-focalcrest-gearhub.dtb` and boot with `bootz`.
3. Verify `focalcrest,gearhub` `compatible`, `eth0` factory MAC, `gpio_wdt` + `sunxi_wdt`, `brcmfmac`, and `ser2net` on `:3332`/`:3333`.
