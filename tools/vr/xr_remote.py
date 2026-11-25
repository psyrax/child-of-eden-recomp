#!/usr/bin/env python3
"""Moves the head and the controllers of Monado's "remote" headset (remote driver, TCP 4242) following a timed script.
Useful to test the head tracking and the controllers of the VR fork without a physical headset.

Usage: xr_remote.py <action>...      (seconds count from when this program starts)
  H<sec>:<right°>,<up°>[,<roll°>[,<x>,<y>,<z>]]     head: rotation and, optionally, offset in meters from its center
  R<sec>:<right°>,<up°>[,<trigger>[,<grip>]]        right controller: where it points, trigger and grip (0..1)
  L<sec>:...                                        left controller, same
  X<sec>                                            quit
The letters D (right) and I (left) are accepted as aliases of R and L: recorded action lists use them.
State is kept between actions. Protocol: struct r_remote_data of Monado v25.0.0 (r_interface.h), 376 bytes."""
import math, socket, struct, sys, time

SIZE = 376
HEAD_CENTER = 8 + 96          # xrt_pose: quaternion (x y z w) and position
CONTROLLER = {'L': 8 + 128, 'R': 8 + 128 + 120}
CONTROLLER['I'], CONTROLLER['D'] = CONTROLLER['L'], CONTROLLER['R']
TRIGGER, GRIP, BOOLS = 28 + 12 + 12 + 20, 28 + 12 + 12 + 20 + 4, 104


def quat(right, up, roll=0.0):
    """Rotation about Y (right = negative), then about X (up = positive), then about Z."""
    def axis(a, i):
        q = [0.0, 0.0, 0.0, math.cos(a / 2)]
        q[i] = math.sin(a / 2)
        return q
    def mul(a, b):
        ax, ay, az, aw = a
        bx, by, bz, bw = b
        return [aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz]
    return mul(mul(axis(-math.radians(right), 1), axis(math.radians(up), 0)), axis(math.radians(roll), 2))


def read(s):
    b = b''
    while len(b) < SIZE:
        c = s.recv(SIZE - len(b))
        if not c:
            sys.exit('xr_remote: Monado closed the connection. Is monado-service still alive?')
        b += c
    return bytearray(b)


def main():
    actions = []
    for a in sys.argv[1:]:
        t, _, v = a[1:].partition(':')
        actions.append((float(t), a[0], [float(x) for x in v.split(',')] if v else []))
    actions.sort(key=lambda x: x[0])
    s = None
    for _ in range(100):  # Monado takes a few seconds to open the port
        try:
            s = socket.create_connection(('127.0.0.1', 4242), timeout=2)
            break
        except OSError:
            time.sleep(0.2)
    if s is None:
        sys.exit('xr_remote: nobody is listening on 127.0.0.1:4242. Monado must start with "active": "remote" in config_v0.json.')
    s.settimeout(None)
    base = read(s)   # rest values
    read(s)          # latest state
    d = bytearray(base)
    center = struct.unpack_from('<3f', base, HEAD_CENTER + 16)
    start = time.time()
    print('xr_remote: connected; head center', center, flush=True)
    while True:
        now = time.time() - start
        while actions and actions[0][0] <= now:
            _, kind, v = actions.pop(0)
            if kind == 'X':
                return
            if kind == 'H':
                v = v + [0.0] * (6 - len(v))
                struct.pack_into('<4f', d, HEAD_CENTER, *quat(v[0], v[1], v[2]))
                struct.pack_into('<3f', d, HEAD_CENTER + 16, center[0] + v[3], center[1] + v[4], center[2] + v[5])
            elif kind in CONTROLLER:
                o = CONTROLLER[kind]
                v = v + [0.0] * (4 - len(v))
                struct.pack_into('<4f', d, o, *quat(v[0], v[1]))
                struct.pack_into('<f', d, o + TRIGGER, v[2])
                struct.pack_into('<f', d, o + GRIP, v[3])
                d[o + BOOLS + 8] = 1 if v[2] > 0.7 else 0   # trigger_click
                d[o + BOOLS + 9] = 1 if v[2] > 0.05 else 0  # trigger_touch
            print(f'xr_remote: {now:.1f}s {kind} {v}', flush=True)
        if not actions:
            return
        s.sendall(d)
        time.sleep(1 / 90)


main()
