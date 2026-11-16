# Installation, Upgrading & Recovery

This guide covers installing OpenWrt (`25.12.6`, Linux `6.12`) onto the **Hornbach Smart Home Gateway V2** (**FocalCrest GearHub H3** / `RFC24 V 2.0`), upgrading with `sysupgrade`, enabling optional Bluetooth, and rolling back to stock firmware.

---

## Prerequisites

- **UART serial adapter** (`115200 8N1`) connected to the internal debug header.
- **Direct Ethernet link** between your host and the gateway.
- **TFTP server on UDP port `69`** (the stage-2 `uboot24.bin` bootloader does not support custom TFTP ports). Default IPs used by [scripts/first-boot.py](../scripts/first-boot.py): host `169.254.65.108` ↔ gateway `169.254.77.3`.
- **Build artifacts** from [GitHub Releases](../../../releases) (or local `scripts/build.sh` + `scripts/build-uboot.sh` runs):
  - `uboot24.bin` *(for first-time setup on unmodified stock gateways)*
  - `*-initramfs-kernel.bin`
  - `*-squashfs-sdcard.img.gz`
  - `openwrt-gearhub-zImage`
  - `sun8i-h3-focalcrest-gearhub.dtb`
  - `boot.scr`

---

## 0. Stock Device Preparation (First-Time Only)

> **Already have `uboot24.bin` on `p1`?** Skip directly to [Step 1](#1-boot-openwrt-in-ram-zero-emmc-writes).

Factory `U-Boot 2020.04` has **no Ethernet** and **no USB**, so unmodified stock Hornbach gateways must first install stage-2 `uboot24.bin` onto the existing FAT16 boot partition (`p1`):

1. Obtain a root shell on the stock Hornbach OS (`5.10.176`) via the internal UART header (see Erik Kallen's *Hornbach H3 Gateway Hack* Part 1 & Part 2).
2. Mount `p1` and copy `uboot24.bin` + `boot.scr` onto it (never touch raw eMMC sectors `0..2047`):
   ```sh
   mkdir -p /tmp/p1
   mount /dev/mmcblk1p1 /tmp/p1   # (or /dev/mmcblk0p1 on stock 5.10)
   cp /tmp/uboot24.bin /tmp/p1/uboot24.bin
   cp /tmp/boot.scr /tmp/p1/boot.scr
   sync
   umount /tmp/p1
   reboot
   ```
3. *(Alternative bare-metal path if stock shell is unavailable)*: Short eMMC `CLK`/`DAT0` pads at power-on to enter USB FEL mode (`1f3a:efe8`) and RAM-boot `uboot24.bin` via `sunxi-fel`.

On reboot, factory `U-Boot 2020.04` executes `boot.scr` Stage-1 and chainloads `uboot24.bin` (`U-Boot 2024.10` with Ethernet/TFTP/USB). Continue to Step 1.

---

## 1. Boot OpenWrt in RAM (Zero eMMC Writes)

Start the serial mux and TFTP server (serving your downloaded artifacts on UDP `:69`), then boot the `initramfs` image in RAM:

```sh
uv run python scripts/serial-mux.py -d /dev/cu.usbserial-XXX -l /tmp/gateway-serial.log -p 3335
python3 scripts/first-boot.py
```

If you want to trigger a manual power-cycle instead of an automated reset, run `NO_REBOOT=1 python3 scripts/first-boot.py` and power-cycle the board.

Once booted, verify you can SSH in (`ssh root@169.254.77.3`) and confirm `eth0` has your factory MAC.

---

## 2. Back Up Stock eMMC (Recommended)

Before writing to eMMC, back up the stock partitions off-device over SSH. *(Note: OpenSSH clients require `-O` on `initramfs` because `sftp-server` is not included.)*

```sh
mkdir -p stock-backup
ssh root@169.254.77.3 "partx -s /dev/mmcblk1" > stock-backup/stock-ptable.txt
ssh root@169.254.77.3 "dd if=/dev/mmcblk1 bs=512 count=2048 2>/dev/null" > stock-backup/stock-raw-0-2047.bin
ssh root@169.254.77.3 "dd if=/dev/mmcblk1p1 bs=1M 2>/dev/null" > stock-backup/stock-p1.img
ssh root@169.254.77.3 "dd if=/dev/mmcblk1p2 bs=1M 2>/dev/null | gzip -1" > stock-backup/stock-p2.img.gz
```

*(Alternatively, `scripts/install-emmc.sh` saves these into `/tmp/stock-backup` automatically when `SKIP_BACKUP` is not set — copy them off the device before rebooting.)*

---

## 3. Install OpenWrt to eMMC

Upload the image artifacts and [scripts/install-emmc.sh](../scripts/install-emmc.sh) to `/tmp/` on the RAM-booted gateway and run the installer:

```sh
scp -O \
  *-squashfs-sdcard.img.gz \
  openwrt-gearhub-zImage \
  sun8i-h3-focalcrest-gearhub.dtb \
  boot.scr \
  scripts/install-emmc.sh \
  root@169.254.77.3:/tmp/

ssh root@169.254.77.3 "SKIP_BACKUP=1 sh /tmp/install-emmc.sh \
  /tmp/*-squashfs-sdcard.img.gz \
  /tmp/openwrt-gearhub-zImage \
  /tmp/sun8i-h3-focalcrest-gearhub.dtb \
  /tmp/boot.scr"

ssh root@169.254.77.3 "sync && reboot"
```

What `install-emmc.sh` does:
- Verifies factory U-Boot env (`ethaddr` at `0x88000`) and `uboot24.bin` on `p1`.
- Leaves raw eMMC sectors `0..2047` and `p1` FAT **untouched in-place**.
- Resizes `p2` to use the remaining eMMC (~7.3 GiB) and flashes the OpenWrt SquashFS rootfs (OpenWrt `fstools` creates the `f2fs` `/overlay` automatically on first boot).
- Copies `zImage`, `sun8i-h3-focalcrest-gearhub.dtb`, and `boot.scr` to `p1`.

After reboot, OpenWrt boots from eMMC with `br-lan` at **`192.168.1.1`** (standard OpenWrt default).

---

## 4. Connect Zigbee / Thread & Z-Wave

`ser2net` starts automatically on boot:
- **Zigbee / Thread** (`/dev/ttyS2`): connect Zigbee2MQTT or OTBR to `tcp://<gateway-ip>:3332` (`115200`, `8N1`).
- **Z-Wave** (`/dev/ttyS3`): connect Z-Wave JS UI to `tcp://<gateway-ip>:3333` (`115200`, `8N1`).

> **Radio firmware note:** EFR32 flash is independent of the Linux rootfs. If you haven't already updated the radio firmwares, compatible `zigbee_ncp` / `ot-rcp` and `zwave 8.1.1` GBLs are built in `silabs-firmware-builder` (stock Z-Wave `7.22.0` has known TX-queue lockups).

### One-Time EFR32 Radio Flashing over `ser2net`

You can flash `.gbl` images from [`silabs-firmware-builder` (`v2026.11.16`)](https://github.com/mathismueller/silabs-firmware-builder/releases/tag/v2026.11.16) remotely over TCP using `universal-silabs-flasher` (stop Zigbee2MQTT / OTBR / Z-Wave JS first so the `ser2net` port is idle):

```sh
# Zigbee NCP (EFR32MG24 on :3332)
universal-silabs-flasher \
  --device socket://<gateway-ip>:3332 \
  flash --firmware https://github.com/mathismueller/silabs-firmware-builder/releases/download/v2026.11.16/gateway_v2_zigbee_ncp_9.1.1.0_hw_flow_115200.gbl

# OR OpenThread RCP (EFR32MG24 on :3332)
universal-silabs-flasher \
  --device socket://<gateway-ip>:3332 \
  flash --firmware https://github.com/mathismueller/silabs-firmware-builder/releases/download/v2026.11.16/gateway_v2_openthread_rcp_3.1.1.0_GitHub-fb274efe6_gsdk_2026.6.1.gbl

# Z-Wave Controller 8.1.1 (EFR32ZG23 on :3333)
universal-silabs-flasher \
  --device socket://<gateway-ip>:3333 \
  --probe-methods zwave:115200 \
  flash --firmware https://github.com/mathismueller/silabs-firmware-builder/releases/download/v2026.11.16/gateway_v2_zwave_controller_8.1.1.gbl
```

### Hardware SWD Fallback (If Gecko Bootloader Entry Fails)

If a bad radio image prevents software entry into the Gecko Bootloader over `ser2net`, both radios can be recovered directly over 3-wire SWD (`SWCLK`, `SWDIO`, `GND`) using `probe-rs` (e.g. Raspberry Pi Pico / RP2040 `debugprobe`, J-Link, or ST-Link):

> **Pinout & power warning:** The header/pad numbers below are from a single `RFC24 V 2.0` board and are **not guaranteed** across hardware revisions. Always cross-reference `PA01` (`SWCLK`) and `PA02` (`SWDIO`) against the Silicon Labs datasheets ([EFR32MG24 Datasheet](https://www.silabs.com/documents/public/data-sheets/efr32mg24-datasheet.pdf), [EFR32ZG23 Datasheet](https://www.silabs.com/documents/public/data-sheets/efr32zg23-datasheet.pdf)) and verify with a **multimeter continuity test** before probing. Keep the gateway powered by its 12 V barrel plug and **do not** connect 3.3 V / VDD from your SWD probe.

| Radio | Chip (`probe-rs`) | `SWCLK` | `SWDIO` | `GND` |
|---|---|---|---|---|
| **Zigbee / Thread** (`EFR32MG24`) | `EFR32MG24A020F1024IM40` | `PA01` (QFN40 Pin 27 / Daughterboard Pin 17 / Motherboard 8-pin Header **Pin 5**) | `PA02` (QFN40 Pin 28 / Daughterboard Pin 18 / Motherboard 8-pin Header **Pin 6**) | Common `GND` / screw ring |
| **Z-Wave** (`EFR32ZG23`) | `EFR32FG23A010F512` | `PA01` (QFN40 Pin 22 / Daughterboard **Pad 44**) | `PA02` (QFN40 Pin 23 / Daughterboard **Pad 45**) | Header Pin 1 / `GND` pad |

```sh
# Zigbee / Thread (EFR32MG24) — flash .hex (preserves Gecko Bootloader at 0x08000000..0x08005FFF)
probe-rs download --chip EFR32MG24A020F1024IM40 --protocol swd --speed 1000 \
  --binary-format hex --verify --reset gateway_v2_zigbee_ncp.hex

# Z-Wave (EFR32ZG23) — flash .hex (FG23A010F512 shares silicon/flash controller)
probe-rs download --chip EFR32FG23A010F512 --binary-format hex --verify --reset \
  gateway_v2_zwave_controller_8.1.1.hex
```

---

## 5. Optional: Enable Bluetooth (`BCM43430A1`)

The BCM43430A1 Bluetooth controller has no onboard flash and requires proprietary patchram (`BCM43430A1.hcd`), which is not redistributed in this repository. To enable Bluetooth:

1. Extract `/lib/firmware/brcm/BCM43430A1.hcd` from your `stock-p2.img.gz` backup.
2. Copy it to `/lib/firmware/brcm/BCM43430A1.hcd` on OpenWrt.
3. Add `/lib/firmware/brcm/BCM43430A1.hcd` to `/etc/sysupgrade.conf` so `sysupgrade` preserves it.
4. Start Bluetooth (or reboot): `/etc/init.d/gearhub-bt start`.

Verify with `hciconfig -a` (`hci0 UP RUNNING`).

---

## Upgrading & Recovery

- **Standard upgrade**: Run `sysupgrade <new-squashfs-sdcard.img.gz>`. [files/lib/upgrade/platform.sh](../files/lib/upgrade/platform.sh) preserves `0..2047`, `uboot24.bin`, `/boot.scr`, and your `/etc/sysupgrade.conf` backup while updating `/boot/zImage` on `p1` and the SquashFS rootfs on `p2`.
- **Factory reset**: Run `firstboot && reboot`, or hold the `PL4` reset button for ≥5 seconds.
- **Bad image recovery**: Interrupt `uboot24.bin` over serial, TFTP-boot `initramfs` with `scripts/first-boot.py`, and run `sysupgrade -n` with a known-good image.
- **Rollback to stock**: Boot `initramfs` in RAM and restore `stock-ptable.txt`, `stock-p1.img`, and `stock-p2.img.gz` from your `stock-backup/` directory.
