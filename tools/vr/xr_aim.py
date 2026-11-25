#!/usr/bin/env python3
"""Converts a point of the floating screen (pixels of 1280x720) into the "right,up" angles a controller must have to
touch it as a laser pointer. Usage: xr_aim.py <px> <py> [ox oy oz] [dist width]
(controller position in LOCAL space; by default the rest position of the right controller of Monado's "remote" device)."""
import math, sys
a = [float(x) for x in sys.argv[1:]]
px, py = a[0], a[1]
o = a[2:5] if len(a) >= 5 else [0.2, -0.3, -0.5]
dist, width = (a[5], a[6]) if len(a) >= 7 else (2.0, 3.2)
height = width * 720 / 1280
d = [(px / 1280 - 0.5) * width - o[0], (0.5 - py / 720) * height - o[1], -dist - o[2]]
print(f"{math.degrees(math.atan2(d[0], -d[2])):.2f},{math.degrees(math.atan2(d[1], math.hypot(d[0], d[2]))):.2f}")
