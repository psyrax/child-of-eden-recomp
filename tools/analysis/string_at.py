#!/usr/bin/env python3
"""Prints the C string (ASCII) found at each given address of the decrypted PE.
Usage: string_at.py <default.pe> <0xADDR> [<0xADDR> ...]   Read-only; run with `python3 -I`."""
import sys
d = open(sys.argv[1], 'rb').read(); B = 0x82000000
for s in sys.argv[2:]:
    a = int(s, 16); o = a - B
    if not 0 <= o < len(d): print(f"0x{a:08X}: outside the PE"); continue
    e = d.find(b'\0', o); print(f"0x{a:08X}: {d[o:min(e, o + 160)]!r}")
