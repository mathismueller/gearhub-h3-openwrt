#!/usr/bin/env python3
"""Serial mux for the GearHub debug console.

Holds /dev/cu.usbserial-* once (macOS grants it exclusively), appends all
RX to a log file, and exposes the port over TCP so gw-ctl and a human can
share it simultaneously:

  python3 scripts/serial-mux.py -d /dev/cu.usbserial-110 -l /tmp/gateway-serial.log -p 3335 &
  tail -f /tmp/gateway-serial.log            # side monitor (read-only)
  ./gw-ctl -p socket://localhost:3335 uboot-cmd "version"   # via mux

pyserial speaks socket:// natively, so gw-ctl needs no code changes.
"""
import argparse
import datetime
import select
import socket
import sys
import time

import serial


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-d", "--device", default="/dev/cu.usbserial-110")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("-l", "--log", default="/tmp/gateway-serial.log")
    ap.add_argument("-p", "--port", type=int, default=3335)
    args = ap.parse_args()

    ser = serial.Serial(args.device, args.baud, timeout=0)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(5)
    srv.setblocking(False)
    clients: list[socket.socket] = []
    log = open(args.log, "ab", buffering=0)
    pending = bytearray()  # incomplete log line (raw serial bytes)

    def stamp() -> bytes:
        return datetime.datetime.now().strftime("[%H:%M:%S] ").encode()

    def log_bytes(chunk: bytes) -> None:
        pending.extend(chunk)
        while True:
            nl = pending.find(b"\n")
            if nl < 0:
                break
            line = bytes(pending[: nl + 1])
            del pending[: nl + 1]
            log.write(stamp() + line.replace(b"\r\n", b"\n"))
    print(f"mux: {args.device}@{args.baud} -> {args.log} + tcp 127.0.0.1:{args.port}",
          flush=True)

    try:
        while True:
            r, _, _ = select.select([ser, srv, *clients], [], [], 0.05)
            if ser in r:
                try:
                    chunk = ser.read(4096)
                except serial.SerialException as e:
                    print(f"mux: serial error {e}, retrying...", flush=True)
                    time.sleep(1)
                    continue
                if chunk:
                    log_bytes(chunk)
                    dead = []
                    for c in clients:
                        try:
                            c.sendall(chunk)
                        except OSError:
                            dead.append(c)
                    for c in dead:
                        clients.remove(c)
                        c.close()
            if srv in r:
                conn, _ = srv.accept()
                conn.setblocking(False)
                clients.append(conn)
            for c in [c for c in clients if c in r]:
                try:
                    data = c.recv(4096)
                except OSError:
                    data = b""
                if data:
                    ser.write(data)
                else:
                    clients.remove(c)
                    c.close()
    except KeyboardInterrupt:
        if pending:
            log.write(stamp() + bytes(pending) + b"\n")
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
