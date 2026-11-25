#!/usr/bin/env python3
"""Name -> offset -> default value of the variables a constructor registers in a debug menu
(sub_82AB81E0 floats, sub_82AB83F8 booleans, sub_82AB7FD0 integers). Hand-emulates lis/addi/li/mr/lfs/stfs from the listing.
Usage: show_func.sh sub_82D495F0 > /x/ctor.txt ; python3 -I debug_fields.py <default.pe> /x/ctor.txt
Read-only. Run in a container with `python3 -I`."""
import re, struct, sys
d = open(sys.argv[1], 'rb').read(); B = 0x82000000
OBJ = 0x10000000
reg = {}; freg = {}; field = {}
def s16(x): return x
def cstr(a):
    o = a - B
    if not (0 <= o < len(d)): return None
    e = d.find(b'\0', o); return d[o:e].decode('latin1')
def flt(a):
    o = a - B
    if not (0 <= o + 4 <= len(d)): return None
    return struct.unpack('>f', d[o:o+4])[0]
first = True
for l in open(sys.argv[2]):
    l = l.strip()
    m = re.match(r'(\w+) (.*)', l)
    if not m: continue
    op, a = m.group(1), m.group(2).split(',')
    try:
        if op == 'mr':
            if a[1] == 'r3' and first: reg[a[0]] = OBJ; first = False
            else: reg[a[0]] = reg.get(a[1])
        elif op == 'lis': reg[a[0]] = (int(a[1]) << 16) & 0xFFFFFFFF
        elif op == 'li': reg[a[0]] = int(a[1]) & 0xFFFFFFFF
        elif op == 'addi':
            v = reg.get(a[1]); reg[a[0]] = None if v is None else (v + int(a[2])) & 0xFFFFFFFF
        elif op == 'ori':
            v = reg.get(a[1]); reg[a[0]] = None if v is None else v | int(a[2])
        elif op in ('lfs',):
            mm = re.match(r'(-?\d+)\((\w+)\)', a[1]); v = reg.get(mm.group(2))
            freg[a[0]] = None if v is None else flt((v + int(mm.group(1))) & 0xFFFFFFFF)
        elif op == 'fmr': freg[a[0]] = freg.get(a[1])
        elif op in ('stfs', 'stw', 'stb'):
            mm = re.match(r'(-?\d+)\((\w+)\)', a[1]); v = reg.get(mm.group(2))
            if v is not None and OBJ <= v + int(mm.group(1)) < OBJ + 0x10000:
                src = freg.get(a[0]) if op == 'stfs' else reg.get(a[0])
                field[v + int(mm.group(1)) - OBJ] = (op, src)
        elif op == 'bl':
            t = int(a[0], 16)
            if t in (0x82ab81e0, 0x82ab83f8, 0x82ab7fd0):
                n = cstr(reg.get('r5') or 0); c = cstr(reg.get('r4') or 0); v = reg.get('r6')
                off = v - OBJ if v is not None and OBJ <= v < OBJ + 0x10000 else None
                kind = {0x82ab81e0: 'float', 0x82ab83f8: 'bool', 0x82ab7fd0: 'int'}[t]
                print(f"{off if off is not None else '?':>6} {kind:5} {str(field.get(off, ('', ''))[1]):>14}  {n!r}  [{c!r}]")
            for r in ('r3','r4','r5','r6','r7','r8','r9','r10','r11','r12'): reg.pop(r, None)
    except Exception as e:
        pass
