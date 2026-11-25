#!/usr/bin/env python3
"""Xrefs through lis/addi|ori pairs (or lis + load/store displacement) to 32-bit addresses or constants.
Usage: xref_addr.py <default.pe> <codegen.partition.json> [--range N] <0xVALUE> [...]
  --range N: also accepts VALUE..VALUE+N-1 (useful for fields of a struct or rows of a table).
Prints the containing function, the address of the 2nd instruction, the kind (addi/ori/load/store) and the value formed.
Read-only. Run in a container with `python3 -I`."""
import struct, sys, json, bisect
B = 0x82000000; T0, TL = 0x82920000, 0x9eed9c
def main():
    a = sys.argv[1:]
    if len(a) < 3: sys.exit(__doc__)
    d = open(a[0], 'rb').read()
    funcs = sorted(int(k, 16) for k in json.load(open(a[1]))['assignments'])
    a = a[2:]; span = 1
    if a[0] == '--range': span = int(a[1], 0); a = a[2:]
    vals = [int(x, 16) for x in a]
    w = struct.unpack('>%dI' % (TL // 4), d[T0 - B:T0 - B + TL])
    fn = lambda x: funcs[max(bisect.bisect_right(funcs, x) - 1, 0)]
    LOAD = {32:'lwz',33:'lwzu',34:'lbz',40:'lhz',42:'lha',48:'lfs',50:'lfd'}; STORE = {36:'stw',37:'stwu',38:'stb',44:'sth',52:'stfs',54:'stfd'}
    n = 0
    for i, x in enumerate(w):
        if (x >> 26) != 15 or ((x >> 16) & 31) != 0: continue
        rd = (x >> 21) & 31; hi = (x & 0xFFFF) << 16
        for j in range(i + 1, min(i + 32, len(w))):
            y = w[j]; op = y >> 26; ra = (y >> 16) & 31; rs = (y >> 21) & 31; im = y & 0xFFFF
            sim = im - 0x10000 if im & 0x8000 else im
            v = None
            if op == 14 and ra == rd: v, t = (hi + sim) & 0xFFFFFFFF, 'addi'
            elif op == 24 and rs == rd: v, t = hi | im, 'ori'
            elif op in LOAD and ra == rd: v, t = (hi + sim) & 0xFFFFFFFF, LOAD[op]
            elif op in STORE and ra == rd: v, t = (hi + sim) & 0xFFFFFFFF, STORE[op]
            if v is not None:
                for t0 in vals:
                    if t0 <= v < t0 + span:
                        print(f"0x{v:08X} {t:5} func=sub_{fn(T0+4*j):08X} @0x{T0+4*j:08X}"); n += 1
            # the register is redefined: stop tracking it
            if op in (14, 15) and rs == rd and not (op == 14 and ra == rd): break
            if op in LOAD and rs == rd and op < 48: break
    print("xrefs:", n)
main()
