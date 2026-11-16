# gearhub-h3-openwrt — Roadmap: RAM-boot → eMMC → Upstream

Goal: turn the stock **Hornbach Smart Home Gateway V2** (`FocalCrest GearHub H3` / `RFC24 V 2.0`, Allwinner H3 `sunxi/cortexa7`) into a maintainable, stock-OpenWrt gateway (similar to V1 `sercomm_na502`): wired Ethernet + Wi-Fi (`brcmfmac`), `ser2net` for `/dev/ttyS2` + `/dev/ttyS3`, status LEDs, and standard Linux Bluetooth (`hci0`) if straightforward (no ESPHome BT proxy), consumed by a remote 64-bit host. No Node.js on the device — `zigbee2mqtt` and `zwave-js-ui` are phasing out 32-bit `armv7` support.

## Architectural Decisions (OpenWrt Best Practices & Keep-vs-Redo from Alpine)

| Area | Prior Alpine setup | OpenWrt (`gearhub-h3-openwrt`) | Rationale |
|---|---|---|---|
| **Radio firmware** | Custom 39 MHz / `CTUNE 140` GBLs from `silabs-firmware-builder` | **Keep** (`zigbee_ncp` or `ot-rcp` on `ttyS2`, `zwave 8.1.1` on `ttyS3`) | Hardware-calibrated for this board's EFR32MG24 / EFR32ZG23; stored in EFR32 flash, independent of Linux rootfs. |
| **Wi-Fi / BT / LEDs** | `brcmfmac`, `hciattach bcm43xx`, custom LED daemon + `lamp` | **OpenWrt-native** (`kmod-brcmfmac` + `cypress-firmware-43430-sdio` + `wpad-basic-mbedtls`; `kmod-leds-gpio` / SPI LED support; standard BT if easy) | Stock OpenWrt experience like V1 `sercomm_na502`; no custom Rust LED daemon needed. |
| **Bootloader / Chainloader** | Factory SPL+U-Boot untouched (`0..2047`), stage-2 `uboot24.bin` on `p1` FAT | **Keep** stage-2 `uboot24.bin` on `p1` FAT | **Zero-brick safety**: SD slot is unpopulated, factory U-Boot lacks USB/Ethernet, and USB-C lacks CC pull-downs (needs USB-A↔USB-C cable for data/FEL). Without `uboot24.bin`, a bad kernel/rootfs requires opening the case and shorting eMMC `CLK`/`DAT0` for FEL. |
| **eMMC Partition Layout** | Custom 4-part A/B (`p1` FAT, `p2`/`p3` ext4 slots, `p4` `/data`) | **Redo → Standard OpenWrt** (`p1` FAT `/boot`, `p2` SquashFS + `rootfs_data` overlay) | Aligns with `sunxi/cortexa7` OpenWrt (`firstboot` factory reset, read-only SquashFS, `sysupgrade -c` config preservation). **No A/B slots.** |
| **Upgrade & Revert** | Custom `gw-upgrade` A/B + button daemon | **Redo → Stock `sysupgrade`** (+ `owut` once upstreamed) | Revert/recover via `firstboot` (bad config) or TFTP/USB `initramfs` via `uboot24.bin` (bad image). |
| **Watchdogs** | Custom watchdog daemon | **Redo → Kernel `gpio_wdt` + `procd`** | `PL10` external supervisor runs with `always-running` + `watchdog.open_timeout=0` (kernel pets it); `procd` natively pets `/dev/watchdog0` (`sunxi_wdt`). |
| **Hardware Init & Button** | OpenRC init script + button daemon | **Redo → DTS + `uci-defaults` / `procd` + `kmod-gpio-button-hotplug`** | Deassert `PD9`/`PD15` radio resets, preserve `ethaddr` from `0x88000`, handle `PL4` reset via `/etc/rc.button/reset`. |
| **Flash Wear** | Custom `zram`, `commit=600`, `syslogd -C128` | **Mostly built-in** (`tmpfs` `/tmp` + RAM `logread` ring buffer) | OpenWrt already avoids rootfs log/tmp writes; optionally add `zram-swap` if needed. |

## Where We Are Now (2026-11-16)

* **Phase 0 & Phase 1 complete and verified on hardware**:
  * Cold power-on eMMC boot works end-to-end (`U-Boot SPL 2020.04` → CI-built Stage-2 `uboot24.bin` (`U-Boot 2024.10`) → FIT `uImage` (`bootm`) + `sun8i-h3-focalcrest-gearhub.dtb` → `overlayfs:/overlay` 7.3 GiB on `mmcblk1p2`).
  * Verified `sysupgrade` (preserving `uboot24.bin`, `boot.scr`, and user-extracted `BCM43430A1.hcd`), `eth0` factory MAC, `wlan0` (with PCF8563 32.768 kHz LPO clock + `brcmfmac43430-sdio.focalcrest,gearhub.*` symlinks), Bluetooth `hci0` (`gearhub-bt`), `/dev/rtc0` + `/dev/rtc1`, `/dev/spidev0.0`, `/dev/watchdog0` + `/dev/watchdog1`, and `ser2net` (`:3332`/`:3333`).
  * Standalone `uboot24.bin` CI build (`.github/workflows/build-uboot.yml`, `scripts/build-uboot.sh`, `uboot/gearhub.fragment` with `CONFIG_BINMAN_FDT` disabled) tested in RAM and promoted to `/dev/mmcblk1p1`.
  * `8ff9567` `sysupgrade` smoke-tested on hardware (`wlan0` cold-boot reload, `hci0`, `ser2net`, `watchdog0`/`watchdog1` all verified).
  * Clean `#include "sun8i-h3.dtsi"` DTS (`0a1021d`) written, compiled, RAM-booted (`scripts/first-boot.py`), and verified on eMMC via `sysupgrade` (`43850353026` — `rtc0`/`rtc1`, `spidev0.0`, `wlan0`, `hci0`, `ser2net`, `watchdog0`/`watchdog1` all passing); `7e2428f` added `vcc-p*-supply` on `&pio`/`&r_pio`.
  * **Reproducibility & packages**: `openwrt/feeds.conf` pinned to `25.12.6` release feed SHAs (`6ee86f4`), and `luci` + `kmod-wireguard` + USB serial `kmods` included (`0823095`).
  * **Phase 3 prep**: `make ARCH=arm CHECK_DTBS=y` and `dt_binding_check` **passed (0 warnings)** in `../linux` (`sunxi/for-next`); OpenWrt upstream branch `focalcrest-gearhub` pushed to `mathismueller/openwrt` (Draft PR `#1` running CI on `59c3f9f`).
* **Next**: Once `gearhub-h3-openwrt` (`0823095`) finishes CI, tag initial GitHub Releases in `gearhub-h3-openwrt` and `silabs-firmware-builder`, then post on the OpenWrt forum for community feedback before resuming Phase 3 upstreaming (`linux-sunxi` + `openwrt/openwrt` PR).
* **CI & Build**: `.github/workflows/build.yml` and `scripts/build.sh` run a **full OpenWrt `25.12.6` source build** (stable release; pinned `openwrt/feeds.conf`) on `x86_64` using proxy profile `friendlyarm_nanopi-m1-plus` with `files/`, and preprocess/compile `sun8i-h3-focalcrest-gearhub.dtb` + `boot.scr`.
* **OpenWrt DTS**: `openwrt/target/sunxi/dts/sun8i-h3-focalcrest-gearhub.dts` is a clean `#include "sun8i-h3.dtsi"` DTS validated by `dtbs_check`.
* **Debug rig**: Serial mux (`scripts/serial-mux.py`) holds UART (`115200 8N1`) → `/tmp/gateway-serial.log` + TCP `127.0.0.1:3335`. `uboot24.bin` has **no `tftpsrvport`** — TFTP must be served on standard UDP **port 69** over direct `en7` link (`169.254.65.108 ↔ 169.254.77.3`).

---

## Phase 0 — Valid DTS + RAM-Boot `initramfs` (No eMMC Writes)

1. **Fix DTS syntax & hardware essentials**:
   * Decompile the stock `sun8i-h3-focalcrest-gearhub.dtb` with `dtc -I dtb -O dts` into valid DTS, then clean it against mainline `sun8i-h3.dtsi` so `scripts/check-dts.sh` (`dtc`) passes.
   * Ensure critical nodes are present and enabled:
     * `linux,wdt-gpio` on `PL10` (`always-running`) + `sun6i-a31-wdt` (`sunxi_wdt`) — **without `gpio_wdt` + `watchdog.open_timeout=0`, the external supervisor resets the board**.
     * `uart2` (`ttyS2`, `PA0..PA3`, RTS/CTS) and `uart3` (`ttyS3`, `PA13..PA14`), plus `vcc_zigbee` (`PD16`).
     * Radio reset lines `PD9` (Zigbee/Thread) and `PD15` (Z-Wave) deasserted (`high`) via `gpio-hog` or early init script (prefer init script + `gpioset` if runtime radio reset is needed).
     * Unused HDMI/display-engine/audio/IR nodes set to `status = "disabled"`.
2. **Build & RAM-boot**:
   * Wire the valid DTS + `Device/focalcrest_gearhub` (with `kmod-wdt-gpio`, `kmod-gpio-button-hotplug`, `kmod-rtc-sunxi`, `ser2net`, `uboot-envtools`) into `.github/workflows/build.yml`.
   * Download `initramfs` (`zImage` or `uImage`) + compiled `sun8i-h3-focalcrest-gearhub.dtb` and run `scripts/first-boot.py` (uses `bootz`, `watchdog.open_timeout=0`, TFTP on `:69`, zero eMMC writes).
   * Keep **8 MiB `bootm` cap** (`CONFIG_SYS_BOOTM_LEN` in `uboot24.bin`) in mind if using `uImage` (`bootz` avoids the `uImage` header cap, or slim the initramfs).
3. **Verify in RAM**:
   * `dmesg` shows `focalcrest,gearhub` `compatible` and `gpio_wdt` + `sunxi_wdt` probed.
   * `eth0` has the factory MAC (`ethaddr`, not `00:…` — verify `uboot24.bin` injects it from `0x88000` or add a `preinit` / `fw_printenv` fixup).
   * `PD9`/`PD15` are high, `ser2net` listens on `:3332` and `:3333`, and remote `zigbee2mqtt` / `zwave-js` connect over TCP.
   * Board stays up >25 minutes without a `PL10` watchdog reset.

**Gate**: Serial shell + Ethernet + MAC + watchdogs + remote radio clients work in RAM; eMMC completely untouched.

---

## Phase 1 — Safe Persistent eMMC Install & `sysupgrade`

**Anti-Bricking Invariants (MUST verify before writing eMMC):**
* **Never write raw eMMC sectors `0..2047` (`0x0..0xFFFFF`)**: Factory SPL (`0x2000`), factory U-Boot (`0xa000`), and factory U-Boot env (`0x88000`: `ethaddr`, `serial#`, `binding_key`) live here.
* **Audit `target/linux/sunxi/base-files/lib/upgrade/platform.sh`**: Upstream OpenWrt `sunxi` `sysupgrade` writes `sdcard.img` partitions and may write U-Boot SPL at sector 16 unless guarded. Patch/customize `platform_do_upgrade` (or `boot.scr` + `p1` update) so `sysupgrade` **only updates `p1` kernel/dtb/boot.scr (preserving `uboot24.bin`) and `p2` rootfs**, never touching `0..2047`.

Steps:
1. **One-shot eMMC repartition (from RAM-booted `initramfs`)**:
   * Verify `0..2047` backup/preflight, then partition from sector **2048** onward:
     * `p1`: FAT16/FAT32 `/boot` (`uboot24.bin`, `boot.scr`, `uEnv.txt`, kernel, `sun8i-h3-focalcrest-gearhub.dtb`).
     * `p2`: OpenWrt SquashFS rootfs + `rootfs_data` overlay (standard OpenWrt `sunxi` geometry).
   * Merge `boot/boot-openwrt.cmd` (`os=openwrt|alpine` selector) into `boot.cmd` → `boot.scr`.
2. **OpenWrt-native system configuration**:
   * `/etc/sysupgrade.conf` preserves `/etc/ser2net.yaml`, `/etc/config/network`, `/etc/config/wireless`, `/etc/dropbear/`, `/etc/uci-defaults/` or radio GPIO config.
   * `/etc/rc.button/reset` mapped to `PL4` (`KEY_RESTART`) for standard OpenWrt reset/reboot behavior.
3. **Radio firmware (one-time flash)**:
   * Flash `silabs-firmware-builder` GBLs (`zigbee_ncp` **XOR** `ot-rcp` on `ttyS2`, `zwave 8.1.1` on `ttyS3`) over serial / Gecko Bootloader if not already flashed. EFR32 flash persists across OpenWrt upgrades.

**Gate**: Cold power-cycle boots OpenWrt from eMMC; `sysupgrade -c` preserves config and `uboot24.bin`; `firstboot` cleanly resets overlay; radios answer on `:3332`/`:3333`.

**Explicit non-goals**: A/B slots, on-device `zigbee2mqtt` / `zwave-js` / Matter Server, Docker, `cpcd`/`zigbeed` Multi-PAN packaging, custom Rust daemons.

---

## Phase 2 — Release Pipeline

* GitHub Releases publish `initramfs`, `sysupgrade.bin`, `sha256sums`, and package manifest per OpenWrt `25.12.x` bump.
* Each release smoke-tested: RAM-boot → `sysupgrade` → `sysupgrade` rollback to previous release.
* **Optional Bluetooth (`BCM43430A1`)**: The `BCM43430A1` has RAM-only patchram (`BCM43430A1.hcd`), which is proprietary and must not be committed to git. Users who want Bluetooth can extract `/lib/firmware/brcm/BCM43430A1.hcd` from their `stock-p2.img.gz` backup (or running stock OS) onto OpenWrt and list it in `/etc/sysupgrade.conf`.
* **Radio GBLs**: Versioned in `silabs-firmware-builder`, never bundled inside `sysupgrade.bin`. Document one-time TCP flashing via `ser2net` (`:3332`/`:3333`) in `docs/INSTALL.md`.

---

## Phase 3 — Upstreaming (DTS First, Device Second) — *Paused (pending OpenWrt forum feedback)*

`sunxi` builds mainline kernels, so the mainline DTS is the critical path:
1. ~~Clean `sun8i-h3-focalcrest-gearhub.dts` against `#include "sun8i-h3.dtsi"` and validate with `make ARCH=arm dtbs_check`~~ (0 warnings in `../linux` `sunxi/for-next`, including `vendor-prefixes.yaml`, `arm/sunxi.yaml`, and `allwinner,sun4i-a10-pinctrl.yaml`).
2. Submit DTS + binding patches to `linux-sunxi` / ARM DT maintainers (`git send-email`, human `Signed-off-by`, `Assisted-by:` trailer if applicable). Carry as an OpenWrt tree patch until merged.
3. Submit `Device/focalcrest_gearhub` PR to `openwrt/openwrt` **`main`** (staged in `mathismueller/openwrt#1` `focalcrest-gearhub`: `cortexa7.mk`, `uboot-sunxi`, `313-*.patch`, `gearhub-bt`, and safe eMMC `platform.sh`; gateway/Phase 2 releases stay on stable OpenWrt `25.12.x`).
4. Create OpenWrt Wiki ToH page + forum thread (following the V1 `sercomm_na502` precedent).

**Gate**: `focalcrest_gearhub` merged in `openwrt/openwrt`; this repo shrinks to `ser2net` image config + docs.

---

## Optional Add-on — On-Device OpenThread Border Router (OTBR)

* **Radio firmware**: Hardware-test `gateway_v2_openthread_rcp` (`ot-rcp` from `silabs-firmware-builder`, currently Renode-validated) on `/dev/ttyS2` (`EFR32MG24`, **XOR** with `zigbee_ncp`).
* **Host daemon (`apk`)**: Install OpenWrt's `otbr-agent` package via `apk` for standalone Thread Border Routing on `br-lan` (disable/stop `ser2net` on `/dev/ttyS2` when running `otbr-agent` locally so they don't contend for the UART; document both local `otbr-agent` and remote-host OTBR over `:3332`).

---

## Recovery & Rollback Ladder (Zero-Brick)

1. **Bad config**: `firstboot && reboot` (or hold `PL4` reset button ≥5 s).
2. **Bad rootfs/kernel**: Interrupt `uboot24.bin` over serial → `initramfs` RAM-boot via TFTP (`:69`) or USB → `sysupgrade -n` previous release.
3. **Rollback to stock Hornbach firmware**: `scripts/install-emmc.sh` (or off-device SSH backup) saves `stock-raw-0-2047.bin`, `stock-ptable.txt`, `stock-p1.img`, and `stock-p2.img.gz` (~205 MiB total; `0..2047` with `ethaddr`/`binding_key`/`x509` is already untouched). From RAM-booted `initramfs`, restore the partition table + `p1` + `p2` and `mkfs.f2fs -l misc /dev/mmcblk0p3`. *(Note: if EFR32 radios were reflashed from `silabs-firmware-builder`, reflash stock RCP/Z-Wave GBLs if returning to stock `zigbeed`.)*
4. **Last resort** (only if `0..2047` or `p1` `uboot24.bin` is corrupted): Short eMMC `CLK`/`DAT0` pads at power-on for BROM FEL + `sunxi-fel`.
