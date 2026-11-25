#!/usr/bin/env python3
"""Xrefs to a code address over the decrypted PE, without depending on what the codegen recognized as a function.
Looks for: direct branches (b/bl/ba/bla, bc/bcl) whose target is the address, and 32-bit words with that value anywhere
in the PE (pointers in data, vtables). For each branch it prints the containing function according to
codegen.partition.json and the `li rX,imm` of the 12 preceding instructions (useful to see argument constants, e.g. the
info class).

Usage: xref_calls.py <default.pe> <codegen.partition.json> <0xADDRESS> [<0xADDRESS> ...]
Read-only. Run in a container with `python3 -I`.
"""
import struct, sys, json, bisect

B = 0x82000000
T0, TL = 0x82920000, 0x9eed9c


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    d = open(sys.argv[1], 'rb').read()
    if len(d) < (T0 - B) + TL:
        sys.exit("ERROR: the PE is smaller than the expected .text; is it the decrypted default.pe?")
    w = struct.unpack('>%dI' % (TL // 4), d[T0 - B:T0 - B + TL])
    funcs = sorted(int(k, 16) for k in json.load(open(sys.argv[2]))['assignments'])

    def fn(a):
        i = bisect.bisect_right(funcs, a) - 1
        return funcs[i] if i >= 0 else 0

    for arg in sys.argv[3:]:
        tgt = int(arg, 16)
        print(f"== target 0x{tgt:08X}")
        n = 0
        for i, x in enumerate(w):
            pc = T0 + 4 * i
            op = x >> 26
            dest = None
            if op == 18:  # b/bl/ba/bla
                li = x & 0x03FFFFFC
                if li & 0x02000000:
                    li -= 0x04000000
                dest = (li if x & 2 else pc + li) & 0xFFFFFFFF
                kind = 'bl' if x & 1 else 'b'
            elif op == 16:  # bc
                bd = x & 0xFFFC
                if bd & 0x8000:
                    bd -= 0x10000
                dest = (bd if x & 2 else pc + bd) & 0xFFFFFFFF
                kind = 'bcl' if x & 1 else 'bc'
            if dest != tgt:
                continue
            n += 1
            lis = []
            for j in range(max(0, i - 12), i):
                y = w[j]
                if (y >> 26) == 14 and ((y >> 16) & 31) == 0:  # li rD,imm
                    imm = y & 0xFFFF
                    if imm & 0x8000:
                        imm -= 0x10000
                    lis.append(f"r{(y >> 21) & 31}={imm}")
            print(f"  {kind:3} @0x{pc:08X}  in sub_{fn(pc):08X}  preceding li: {' '.join(lis) or '-'}")
        print(f"  direct branches: {n}")
        pat = struct.pack('>I', tgt)
        k = d.find(pat)
        m = 0
        while k != -1:
            if k % 4 == 0:
                m += 1
                a = B + k
                where = '.text' if T0 <= a < T0 + TL else 'data'
                print(f"  word 0x{tgt:08X} at 0x{a:08X} ({where})")
            k = d.find(pat, k + 1)
        print(f"  aligned pointers in the PE: {m}")


main()
