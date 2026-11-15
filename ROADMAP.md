# gearhub-h3-openwrt — Roadmap: first boot → persistence → upstream

Goal: stock Hornbach Gateway V2 becomes a radio-only OpenWrt box (`ser2net` for
`/dev/ttyS2` + `/dev/ttyS3`), consumed by a remote 64-bit host. No Node.js on the
device — both `z2m` (deprecated 32-bit, EOL April 2027 with Node 22) and
`zwave-js-ui` (same Node 24 cliff, unofficial armv7 builds only) age out on
`armv7` regardless of distro.

Where we are now (2026-11-15):

* Repo scaffolded, CI builds `25.12.6` ImageBuilder `initramfs-kernel.bin` for
  proxy profile `friendlyarm_nanopi-m1-plus` (+ `ser2net`, `brcmfmac`,
  `cypress-firmware-43430-sdio`), with a `:` workaround for the upstream
  IB+APK `prepare_rootfs` `then  ;` syntax error (`scripts/build.sh`,
  `.github/workflows/imagebuilder.yml`).
* Debug rig: serial mux (`scripts/serial-mux.py`, `pyserial` via `uv`) holds
  `/dev/cu.usbserial-110` once → `/tmp/gateway-serial.log` + TCP `127.0.0.1:3335`
  (`gw-ctl -p socket://localhost:3335`). TFTP via `tftp-now` on
  `169.254.65.108:6969` over direct `en7` link (`169.254.65.108 ↔ 169.254.77.2`).
  Power-cycle webhook is HA-dependent and flaky — treat as convenience, not infra.
* Known bootloader facts: factory U-Boot 2020.04 has **no** USB/Ethernet
  (disabled DTB + missing `ehci/ohci/emac` drivers) — first install must go
  through running stock Linux. Stage-2 `uboot24.bin` (2024.10, `PL2` VBUS,
  EHCI, `pxe/dhcp`) is distro-agnostic and frozen.

## Phase 0 — RAM-boot initramfs (now, no eMMC writes)

1. CI green → download `openwrt-*-initramfs-kernel.bin` into `artifacts/`.
2. From stage-2 U-Boot (`halt-boot` to `=>`):
   `setenv serverip 169.254.65.108; setenv tftpsrvport 6969;`
   `tftpboot $kernel_addr_r openwrt-initramfs-kernel.bin;`
   `tftpboot $fdt_addr_r sun8i-h3-focalcrest-gearhub.dtb; bootm`.
   (New users run their own TFTP on `:69` and skip `tftpsrvport`.)
3. Verify, in order: correct `compatible` in `dmesg`, `eth0` gets a real MAC
   (not `00:…` — factory U-Boot injects `ethaddr` from env; confirm stage-2
   preserves this or add a preinit fixup), `ser2net` on `3332/3333`,
   remote `z2m`/`zwave-js` connect over TCP.
4. Merge `boot/boot-openwrt.cmd` (`os=openwrt|alpine` selector + OpenWrt
   stanza) into the chainloader `boot.cmd`, `mkimage` → `boot.scr` on USB only.

Gate: serial shell + eth + remote radio clients work, eMMC untouched
(raw `0..2047` never written). Stop here — sysupgrade comes later.

Risks:

* **8 MiB `bootm` cap** (`CONFIG_SYS_BOOTM_LEN` in `uboot24.bin`, the same
  limit Alpine hit with its 8.13 MiB `vmlinuz`): if `initramfs-kernel.bin`
  exceeds it, the board resets on `bootm`. Mitigations in order: `bootz`
  instead of `bootm`, slim the initramfs package set, rebuild `uboot24.bin`
  with a larger cap (we own the OpenWrt-side bootloader build chain).
* Proxy-profile DTB mismatch: boot with our external DTB, never the profile's.

## Phase 1 — First persistent install (initramfs → eMMC, still our tooling)

Typical OpenWrt way, not Alpine way: **no A/B slots**, SquashFS + `rootfs_data`
overlay, `procd/UCI/netifd`, `apk`, `sysupgrade`. Stock already looks like
this (`p1` FAT boot, `p2` SquashFS, `p3` F2FS `/root`, tmpfs overlay) — we
restore that shape instead of inventing one.

1. Boot initramfs (Phase 0), `scp` the `squashfs-sysupgrade.bin` over.
2. Repartition from sector **2048** only (raw SPL/U-Boot/env at `0..2047`
   untouched — `binding_key`, `ethaddr`, `serial#` live at `0x88000`):
   `p1` FAT `/boot` (`uboot24.bin`, `boot.scr`, `uEnv.txt`),
   `p2`+`p3` in the upstream `sdcard.img` geometry (kernel + rootfs, overlay
   auto-created on first boot), state mounted by label/UUID, never `mmcblkXpY`.
3. From then on updates are **stock** `sysupgrade` / `owut` — our installer is
   a one-shot, not a parallel update system. `/etc/sysupgrade.conf` preserves
   `ser2net.yaml`, `network`, `wireless`, `dropbear`.
4. Radio firmware is flashed **once** from initramfs over serial (XMODEM into
   the Gecko bootloader, 39 MHz/`CTUNE 140` builds from `silabs-firmware-builder`):
   `zigbee_ncp` **XOR** `ot-rcp` on `ttyS2` (single radio, no Multi-PAN),
   `zwave 8.1.1` on `ttyS3` (stock `7.22.0` has TX-queue/jam lockups).
   EFR32s keep firmware in their own flash — GBLs don't need persisting on
   the gateway afterwards, and `binding_key` is irrelevant (no CPC path).

Gate: power-cycle → OpenWrt from eMMC, config survives `sysupgrade -c`,
radios answer on TCP after a reflash-from-scratch.

Explicit non-goals: A/B slots, on-device `z2m`/`zwave-js`/Matter Server,
Docker, `cpcd`/`zigbeed` packaging (revisit only if Multi-PAN demand appears),
Python on device.

## Phase 2 — Release pipeline (boring, signed, repeatable)

* GH Releases carry `initramfs-kernel.bin` + `squashfs-sysupgrade.bin` +
  `sha256sums` + package manifest per `25.12.x` bump. ImageBuilder stays
  x86_64-only (Mac `container` VM can't run it — GH Action is the builder).
* `owut`-compatible upgrade path documented; each release smoke-tested as:
  RAM-boot → `sysupgrade` → rollback-to-previous-release.
* Radio GBLs versioned alongside (from `silabs-firmware-builder` releases),
  never bundled inside the sysupgrade image.

## Phase 3 — Upstreaming (DTS first, device second)

`sunxi` builds mainline kernels, so the DTS is the shared critical path —
Alphorn needs the same work for its own modules.

1. Clean `openwrt/target/sunxi/dts/sun8i-h3-focalcrest-gearhub.dts` to
   mainline style, `dtbs_check` clean in the Debian container VM,
   decompiled vendor DTB as reference.
2. Submit to sunxi/ARM DT maintainers (`git send-email`, human
   `Signed-off-by`, `Assisted-by:` trailer where applicable). Expect
   multi-revision review across kernel cycles; carry it as a tree patch meanwhile.
3. OpenWrt `Device/focalcrest_gearhub` PR (`cortexa7.mk`, modeled on
   `nanopi-m1-plus`), with our GH-built artifacts as boot evidence.
   Real name + `Signed-off-by`, PR via GitHub mirror.
4. Wiki ToH page + firmware-selector entry + forum thread. Precedent: V1
   `sercomm_na502` — first PR closed unmerged, device is in-tree today.
   Sustained engagement, not first-try merge, is the mechanism.

Gate: `focalcrest_gearhub` in `openwrt/openwrt`, ToH page live, this repo
shrinks to ImageBuilder recipes + docs.

## New-user experience (the whole point)

Target: sealed-box owner, ~45 min, ~€8 USB-TTL adapter, no soldering
(test pads are under solder mask — scrape only the two UART pads + use the
`GND` pad by the USB-C jack; never `5V`/`3V3`).

1. **Open + wire** (10 min): pads left of the 8 unpopulated pinholes —
   pinhole-side = board RX (adapter TX), antenna-side = board TX (adapter RX),
   `115200 8N1`. Direct Ethernet to laptop (`169.254.x` link-local is fine).
2. **Chainload** (10 min): boot stock, mount `mmcblk1p1`, drop in `uboot24.bin`
   + chainloader `boot.scr` (via UART root shell or SSH), reboot → stage-2
   with USB + `pxe/dhcp`. Factory U-Boot menu alone can't do USB/TFTP —
   anyone telling you otherwise hasn't read its DTB.
3. **RAM-boot** (10 min): TFTP/USB `initramfs-kernel.bin` + our DTB, verify
   serial shell + `eth0` MAC + `ser2net` ports from your laptop.
4. **Install** (10 min): one-shot repartition (raw `0..2047` preserved, shown
   by the installer preflight or it aborts), flash radio GBLs, reboot into
   eMMC OpenWrt. First boot: set root password, region, `ser2net` check.
5. **Consume** (5 min): point remote `z2m` at `tcp://gw:3332`/`ember`,
   `zwave-js` at `tcp://gw:3333`, Thread at the `ot-rcp` box if that's the
   flashed personality. Updates after this are LuCI/`owut`, like any OpenWrt.

Troubleshooting table (ship in `docs/INSTALL.md`):

| Symptom | Cause → fix |
|---|---|
| No serial output | RX/TX swapped → swap the two data wires |
| `tftpboot` timeout | `serverip`/`tftpsrvport` wrong, or stock (stage-1) U-Boot → chainload first |
| `bootm` resets board | image > 8 MiB cap → `bootz`, slimmer initramfs, or rebuilt `uboot24.bin` |
| `eth0` MAC `00:…` | env injection lost → preinit fixup from `ethaddr` |
| `sysupgrade` bricks boot | raw sectors touched → restore from `hornbach-emmc.img` reference, never `dd` below sector 2048 |

Recovery ladder: `sysupgrade` previous release → USB/TFTP initramfs reinstall
→ (last resort) eMMC `CLK`/`DAT0` short at power-on for BROM FEL + `sunxi-fel`.
Every step above states what it preserves before it writes.
