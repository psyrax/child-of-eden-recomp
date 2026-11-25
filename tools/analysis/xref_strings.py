#!/usr/bin/env python3
"""Static xrefs to strings of the decrypted PE: looks for lis/addi(ori) pairs in .text that form the address.
Usage: xref_strings.py <default.pe> <codegen.partition.json> <string> [<string> ...]"""
import struct, sys, json, bisect
d = open(sys.argv[1], 'rb').read(); B = 0x82000000
T0, TL = 0x82920000, 0x9eed9c
w = struct.unpack('>%dI' % (TL // 4), d[T0 - B:T0 - B + TL])
funcs = sorted(int(k, 16) for k in json.load(open(sys.argv[2]))['assignments'])
def fn(a):
    i = bisect.bisect_right(funcs, a) - 1
    return funcs[i] if i >= 0 else 0
targets = {}
for s in sys.argv[3:]:
    b = s.encode(); i = d.find(b + b'\0')
    while i != -1:
        if i == 0 or d[i-1] == 0: targets[B + i] = s
        i = d.find(b + b'\0', i + 1)
hi = {}
for a in targets:
    lo = a & 0xFFFF; h = (a >> 16) + (1 if lo >= 0x8000 else 0)
    hi.setdefault(h & 0xFFFF, []).append((lo, a))
    hi.setdefault((a >> 16) & 0xFFFF, []).append((lo | 0x10000, a))  # ori variant
out = set()
for i, x in enumerate(w):
    if (x >> 26) == 15 and ((x >> 16) & 31) == 0 and (x & 0xFFFF) in hi:   # lis rD,imm
        rd = (x >> 21) & 31
        for j in range(i + 1, min(i + 24, len(w))):
            y = w[j]; op = y >> 26
            if op in (14, 24) and (((y >> 16) & 31) == rd if op == 14 else ((y >> 21) & 31) == rd):
                for lo, a in hi[x & 0xFFFF]:
                    if (op == 14 and lo < 0x10000 and (y & 0xFFFF) == lo) or (op == 24 and lo >= 0x10000 and (y & 0xFFFF) == (lo & 0xFFFF)):
                        out.add((targets[a], fn(T0 + 4 * j), T0 + 4 * j))
for s, f, a in sorted(out): print(f"{s!r:45} func=sub_{f:08X} @0x{a:08X}")
print("strings found:", len(targets), "xrefs:", len(out))
