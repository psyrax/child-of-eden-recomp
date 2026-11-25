#!/usr/bin/env python3
"""Virtual keyboard (uinput) to drive the game on the handheld without a controller. Runs ON THE HANDHELD with sudo.
Usage: uinput_keys.py <action>...   action = <sec>:<key> (press for 0.3 s) | bot:<start>-<end> (same sweep as steps.sh)
Keys: enter space l backspace w a s d esc. The game must run with --hid.mnk_mode=true. Exits on its own when done."""
import fcntl, os, struct, sys, time
K = {"enter": 28, "space": 57, "l": 38, "backspace": 14, "w": 17, "a": 30, "s": 31, "d": 32, "esc": 1}
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, UI_SET_EVBIT, 1)
for c in K.values(): fcntl.ioctl(fd, UI_SET_KEYBIT, c)
os.write(fd, struct.pack("80sHHHHi", b"eden-test-keyboard", 3, 0x1234, 0x5678, 1, 0) + b"\0" * (64 * 4 * 4))
fcntl.ioctl(fd, UI_DEV_CREATE)
t0 = time.time()
def ev(t, c, v): os.write(fd, struct.pack("llHHi", int(time.time()), 0, t, c, v))
def key(k, v): ev(1, K[k], v); ev(0, 0, 0)
def wait_until(s):
    while time.time() - t0 < s: time.sleep(0.05)
try:
    time.sleep(1)
    for a in sys.argv[1:]:
        if a.startswith("bot:"):
            start, end = map(float, a[4:].split("-")); wait_until(start); i = 0; dirs = "dwaasddwas"
            while time.time() - t0 < end:
                k = dirs[i % 10]; b = "l" if i % 5 == 4 else "space"
                key(b, 1); key(k, 1); time.sleep(0.5); key(k, 0); time.sleep(0.1); key(b, 0); i += 1
                if i % 20 == 0: key("backspace", 1); time.sleep(0.2); key("backspace", 0)
        else:
            s, k = a.split(":"); wait_until(float(s)); key(k, 1); time.sleep(0.3); key(k, 0); print("key", s, k, flush=True)
finally:
    fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
