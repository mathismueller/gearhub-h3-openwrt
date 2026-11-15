#!/usr/bin/env python3
"""Phase-0 first boot: RAM-boot OpenWrt initramfs via stage-2 U-Boot + TFTP.

Talk to the gateway serial console through the mux
(scripts/serial-mux.py, TCP 127.0.0.1:3335). Flow:

  1. reboot via SSH (link-local), fall back to manual power-cycle
  2. stop stage-2 U-Boot autoboot
  3. static IP + tftpboot zImage + DTB, ping gateway first
  4. bootz, watch for the OpenWrt banner

Everything is also appended to the mux log file (/tmp/gateway-serial.log).
No eMMC writes anywhere in this path.
"""
import select
import socket
import subprocess
import sys
import time

MUX_HOST, MUX_PORT = "127.0.0.1", 3335
GW_SSH = "root@169.254.77.2"
SERVER_IP = "169.254.65.108"
# NOTE: stage-2 uboot24.bin has no tftpsrvport/wget support (checked strings:
# tftpboot + tftpblocksize/tftpwindowsize/tftptimeout only). The TFTP server
# MUST listen on standard port 69. Our unprivileged :6969 instance is only
# good for Mac-side self-tests, never for the board.
KADDR, FADDR = "0x42000000", "0x43000000"
ZIMAGE = "openwrt-initramfs-zImage"
DTB = "sun8i-h3-focalcrest-gearhub.dtb"


class Mux:
    def __init__(self):
        self.s = socket.create_connection((MUX_HOST, MUX_PORT), timeout=10)
        self.s.setblocking(False)
        self.buf = bytearray()

    def send(self, line):
        print(f">> {line.strip()}", flush=True)
        self.s.sendall((line if line.endswith("\n") else line + "\n").encode())

    def expect(self, needles, timeout, send_on_hit=None):
        """Wait until one of needles appears. Returns (needle, chunk)."""
        if isinstance(needles, (bytes, str)):
            needles = [needles]
        needles = [n.encode() if isinstance(n, str) else n for n in needles]
        deadline = time.time() + timeout
        while time.time() < deadline:
            r, _, _ = select.select([self.s], [], [], 0.5)
            if r:
                try:
                    chunk = self.s.recv(65536)
                except OSError:
                    chunk = b""
                if not chunk:
                    time.sleep(0.5)
                    continue
                self.buf.extend(chunk)
                for n in needles:
                    if n in self.buf:
                        out = bytes(self.buf)
                        self.buf.clear()
                        if send_on_hit:
                            self.send(send_on_hit)
                        return n, out
        return None, bytes(self.buf)


def main():
    print("== 1. reboot via SSH ==", flush=True)
    try:
        subprocess.run(["ssh", "-o", "ConnectTimeout=8", GW_SSH, "reboot"],
                       timeout=25, capture_output=True)
        print("reboot issued", flush=True)
    except Exception as e:
        print(f"SSH reboot failed ({e}); power-cycle manually if needed",
              flush=True)
    time.sleep(3)
    m = Mux()

    print("== 2. wait for reset ==", flush=True)
    n, _ = m.expect(b"U-Boot SPL", timeout=300)
    if n is None:
        sys.exit("FAIL: no reset within 300s (board still in Linux?)")
    print("reset seen, watching autoboot", flush=True)

    print("== 3. stop U-Boot autoboot ==", flush=True)
    hits = 0
    deadline = time.time() + 120
    saw_prompt = False
    prompt_since = None
    while time.time() < deadline and hits < 2:
        n, _ = m.expect([b"Hit any key to stop autoboot", b"=> "], timeout=5)
        if n == b"Hit any key to stop autoboot":
            hits += 1
            print(f"autoboot hit {hits}/2", flush=True)
            m.send(" ")
            saw_prompt = False
        elif n == b"=> ":
            if not saw_prompt:
                saw_prompt = True
                prompt_since = time.time()
            elif time.time() - prompt_since > 8 and hits == 0:
                print("sitting at stage-1, continuing boot", flush=True)
                m.send("boot")
                saw_prompt = False
    if hits < 2:
        print("WARN: autoboot not stopped twice; continuing anyway", flush=True)
    time.sleep(2)
    m.buf.clear()

    cmds = [
        "setenv ipaddr 169.254.77.3",
        "setenv netmask 255.255.0.0",
        f"setenv serverip {SERVER_IP}",
        # No tftpsrvport: uboot24.bin always uses TFTP port 69.
        f"ping {SERVER_IP}",
    ]
    print("== 4. network ==", flush=True)
    for c in cmds:
        m.send(c)
        n, out = m.expect(b"=> ", timeout=40)
        tail = out.decode("utf-8", "replace")[-400:]
        print(tail, flush=True)
        if n is None:
            sys.exit(f"FAIL: no prompt after: {c}")

    alive = False
    for attempt in range(12):
        m.send(f"ping {SERVER_IP}")
        n, out = m.expect(b"=> ", timeout=40)
        tail = out.decode("utf-8", "replace")[-400:]
        print(tail, flush=True)
        if n is None:
            sys.exit("FAIL: no prompt after ping")
        if b"is alive" in out:
            alive = True
            break
        print(f"ping {attempt + 1}/12 not alive yet, waiting 10s...",
              flush=True)
        time.sleep(10)
    if not alive:
        sys.exit("FAIL: TFTP server not reachable (L2?). Aborting.")

    print("== 5. TFTP ==", flush=True)
    for fname, addr in [(ZIMAGE, KADDR), (DTB, FADDR)]:
        m.send(f"tftpboot {addr} {fname}")
        n, out = m.expect(b"=> ", timeout=120)
        tail = out.decode("utf-8", "replace")[-400:]
        print(tail, flush=True)
        if n is None or b"Bytes transferred" not in out:
            sys.exit(f"FAIL: tftpboot {fname} failed")

    print("== 6. bootz ==", flush=True)
    m.send(f"bootz {KADDR} - {FADDR}")
    n, out = m.expect([b"OpenWrt", b"Please press Enter to activate this console",
                        b"Kernel panic", b"Wrong Image Format"],
                       timeout=120)
    tail = out.decode("utf-8", "replace")[-1500:]
    print(tail, flush=True)
    if n in (b"OpenWrt", b"Please press Enter to activate this console"):
        print("PASS: OpenWrt initramfs booted from RAM", flush=True)
        return 0
    sys.exit(f"FAIL: unexpected boot outcome (saw: {n})")


if __name__ == "__main__":
    sys.exit(main())
