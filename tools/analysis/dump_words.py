#!/usr/bin/env python3
"""Dumps 32-bit big-endian words of the decrypted PE. Usage: dump_words.py <default.pe> <0xADDR> <n_words>
Marks the ones that fall inside the image (possible pointers). Read-only; run with `python3 -I`."""
import struct, sys
d = open(sys.argv[1], 'rb').read(); B = 0x82000000
a = int(sys.argv[2], 16); n = int(sys.argv[3])
for i in range(n):
    o = a - B + 4 * i
    if o + 4 > len(d): sys.exit("ERROR: outside the PE; check the address")
    v = struct.unpack('>I', d[o:o + 4])[0]
    print(f"0x{a + 4 * i:08X}: {v:08X}" + ("  <- in image" if B <= v < B + len(d) else ""))
