# gearhub-h3-openwrt

OpenWrt (`25.12.6`, Linux `6.12`) port for the **Hornbach Smart Home Gateway V2** (**FocalCrest GearHub H3** / `RFC24 V 2.0`, Allwinner H3 `sunxi/cortexa7`).

Provides a stock OpenWrt experience—wired Ethernet, Wi-Fi (`brcmfmac`), `ser2net` TCP bridges for Zigbee/Thread (`/dev/ttyS2` → `:3332`) and Z-Wave (`/dev/ttyS3` → `:3333`), hardware watchdogs, RTCs, SPI LED bus, reset button, and optional Bluetooth (`hci0`)—while leaving heavy coordinators (Zigbee2MQTT, Z-Wave JS UI, Home Assistant) on a remote 64-bit host.

---

## Hardware Summary

| Component | Hardware | OpenWrt Support |
|---|---|---|
| **SoC / RAM / Flash** | Allwinner H3 (4× Cortex-A7), 1 GiB DDR3, 8 GiB eMMC (`mmcblk1`) | `sunxi/cortexa7` |
| **Ethernet** | 100 Mbps (`dwmac-sun8i`, `eth0`) | Built-in (`ethaddr` restored from `0x88000`) |
| **Wi-Fi** | Broadcom BCM43430 (`AP6212A1` SDIO, `wlan0`) | `kmod-brcmfmac` + `cypress-firmware-43430-sdio` |
| **Bluetooth** | Broadcom BCM43430A1 (`/dev/ttyS1`, `PD4` reset, PCF8563 LPO) | Optional (`kmod-bluetooth`, `kmod-hci-uart`, `bluez-utils`; user-supplied `BCM43430A1.hcd`) |
| **Zigbee / Thread** | Silicon Labs EFR32MG24 (`/dev/ttyS2`, `115200 8N1`, `PD9` reset) | `ser2net` on TCP `:3332` |
| **Z-Wave** | Silicon Labs EFR32ZG23 (`/dev/ttyS3`, `115200 8N1`, `PD15` reset) | `ser2net` on TCP `:3333` |
| **Watchdogs** | `sunxi_wdt` (`/dev/watchdog0`) + external `PL10` `gpio_wdt` (`/dev/watchdog1`) | `CONFIG_GPIO_WATCHDOG=y` + `watchdog.open_timeout=0` |
| **RTCs / LEDs / Reset** | `sun6i-rtc` (`/dev/rtc0`), PCF8563 (`/dev/rtc1`), WS2812B (`/dev/spidev0.0`), `PL4` | `kmod-rtc-*`, `kmod-spi-dev`, `/etc/rc.button/reset` |

---

## Quick Start

See **[docs/INSTALL.md](docs/INSTALL.md)** for full step-by-step instructions, `sysupgrade` usage, optional Bluetooth setup, and stock rollback.

1. **RAM-boot `initramfs` (zero eMMC writes):** Start `scripts/serial-mux.py` and a TFTP server on UDP `:69`, then run `python3 scripts/first-boot.py`.
2. **Back up & flash eMMC:** Back up `0..2047`, `p1`, and `p2` over SSH, then run `scripts/install-emmc.sh` to install OpenWrt onto `p2` while keeping `0..2047` and `p1`'s `uboot24.bin` chainloader in-place.
3. **Connect radios:** Point Zigbee2MQTT / OTBR to `tcp://<gateway-ip>:3332` and Z-Wave JS UI to `tcp://<gateway-ip>:3333`.

---

## Build Considerations & Reproducibility

- **Pinned OpenWrt target:** Builds target OpenWrt **`v25.12.6`** (`sunxi/cortexa7`) using `friendlyarm_nanopi-m1-plus` as a proxy profile until upstreaming (`Device/focalcrest_gearhub`), with our `files/` overlay and `openwrt/target/sunxi/dts/sun8i-h3-focalcrest-gearhub.dts`.
- **External watchdog requirement:** The board has an always-running hardware supervisor on `PL10`. The kernel **must** enable `CONFIG_GPIO_WATCHDOG=y` + `CONFIG_GPIO_WATCHDOG_ARCH_INITCALL=y` and boot with `watchdog.open_timeout=0`, or the board resets after ~20 minutes.
- **Anti-brick boot chain:** Because factory U-Boot (`2020.04`) lacks USB/Ethernet and the board has no SD slot, raw eMMC `0..2047` and `p1`'s `uboot24.bin` (`U-Boot 2024.10`) are never overwritten. [files/lib/upgrade/platform.sh](files/lib/upgrade/platform.sh) overrides `sunxi` `sysupgrade` to extract `zImage` from `uImage` onto `p1:/boot/zImage` and flash `p2` only.
- **Bluetooth & proprietary firmware:** OpenWrt's `kmod-hci-uart` builds generic H4 (`CONFIG_BT_HCIUART_BCM=n`), so [files/etc/init.d/gearhub-bt](files/etc/init.d/gearhub-bt) enables the PCF8563 32 kHz LPO clock, pulses `PD4`, and runs `hciattach /dev/ttyS1 bcm43xx`. Proprietary `BCM43430A1.hcd` is intentionally excluded from the repo.
- **Reproducible builds:** CI ([.github/workflows/build.yml](.github/workflows/build.yml)) and [scripts/build.sh](scripts/build.sh) build from the pinned `v25.12.6` tag, validate the DTS/boot script upfront, and publish `sha256sums` and package manifests alongside every build.

---

## Dev Tooling Setup

- **DTS validation:** Install `dtc` (`brew install dtc` on macOS, `device-tree-compiler` on Debian/Ubuntu) and run `./scripts/check-dts.sh`.
- **Serial & TFTP test rig:** Install [`uv`](https://docs.astral.sh/uv/) for Python dependencies (`pyserial`), run `uv run python scripts/serial-mux.py -d /dev/cu.usbserial-XXX -l /tmp/gateway-serial.log -p 3335`, and serve build artifacts over TFTP on **UDP port `69`**.
- **Local full build:** Run `./scripts/build.sh` on a Linux `x86_64` host (with standard OpenWrt build dependencies) or trigger `.github/workflows/build.yml` on GitHub Actions.

---

## Repository Layout

- [docs/INSTALL.md](docs/INSTALL.md) — Full installation, `sysupgrade`, optional Bluetooth, and recovery guide
- [ROADMAP.md](ROADMAP.md) — Phased migration plan, architecture decisions, and upstreaming roadmap
- `openwrt/` — Device stanza and `sun8i-h3-focalcrest-gearhub.dts`
- `files/` — OpenWrt rootfs overlay (`ser2net.yaml`, `sysupgrade.conf`, `init.d/gearhub-hw`, `init.d/gearhub-bt`, `lib/firmware/brcm/` symlinks, `rc.button/reset`, `lib/upgrade/platform.sh`)
- `boot/boot-openwrt.cmd` — Stage-1 (`uboot24.bin` chainload) + Stage-2 (`bootz`) eMMC boot script
- `scripts/` — `serial-mux.py`, `first-boot.py`, `install-emmc.sh`, `check-dts.sh`, `build.sh`
- `.github/workflows/build.yml` — Automated OpenWrt `25.12.6` source build
- [LICENSE](LICENSE) — GNU GPL-2.0 (`GPL-2.0-only`)

---

## Disclaimers

- **Non-affiliation:** This is an independent community project. It is **not** affiliated with, endorsed by, sponsored by, or supported by **Hornbach** or **FocalCrest**. All product names and trademarks belong to their respective owners.
- **AI-assisted development:** Parts of the code, scripts, and documentation in this repository were written or refined with AI assistance. Review scripts and always back up your stock eMMC before flashing; you assume full responsibility for any modifications made to your hardware.
