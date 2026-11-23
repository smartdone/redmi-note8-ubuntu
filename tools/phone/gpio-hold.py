#!/usr/bin/python3
"""gpio-hold.py CHIP LINE VALUE SECONDS: drive a GPIO via the v2 chardev uAPI
(Ubuntu's libgpiod 1.6 tools need the v1 uAPI, which this kernel lacks)."""
import fcntl, os, struct, sys, time
chip, line, value, secs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
offsets = struct.pack("64I", line, *([0] * 63))
consumer = b"gpio-hold".ljust(32, b"\0")
attr = struct.pack("IIQQ", 2, 0, value & 1, 1)          # OUTPUT_VALUES, mask bit 0
attrs = attr + b"\0" * (24 * 9)
config = struct.pack("QI5I", 1 << 3, 1, 0, 0, 0, 0, 0) + attrs   # FLAG_OUTPUT
req = bytearray(offsets + consumer + config + struct.pack("II5Ii", 1, 0, 0, 0, 0, 0, 0, 0))
GPIO_V2_GET_LINE_IOCTL = (3 << 30) | (len(req) << 16) | (0xB4 << 8) | 0x07
fd = os.open(f"/dev/{chip}", os.O_RDWR)
fcntl.ioctl(fd, GPIO_V2_GET_LINE_IOCTL, req)
print(f"{chip} line {line} = {value} for {secs}s", flush=True)
time.sleep(secs)
