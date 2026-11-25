#!/usr/bin/env python3
"""Converts an XWD dump (the one `Xvfb -fbdir <dir>` writes as <dir>/Xvfb_screen0, or `xwd -root`) to PNG.
Standard library only. Useful to look at a game frame without a display.
Usage: xwd_to_png.py <input.xwd> <output.png>
It also prints how many pixels are NOT black, to know whether anything was drawn without opening the image.
Exits with 2 if the file is not a 24/32-bit XWD v7 ZPixmap (it says what it found)."""
import struct, sys, zlib

def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr); return 2
    try:
        d = open(sys.argv[1], 'rb').read()
    except OSError as e:
        print(f"ERROR: could not read {sys.argv[1]} ({e.strerror}); Xvfb only writes Xvfb_screen0 if it was started with -fbdir <existing dir>", file=sys.stderr); return 2
    if len(d) < 100:
        print("ERROR: file too short to be XWD; was it copied while Xvfb was still alive and started with -fbdir?", file=sys.stderr); return 2
    h = struct.unpack('>25I', d[:100])
    (hsize, ver, fmt, depth, w, hgt, _xoff, byte_order, _unit, _bit_order, _pad, bpp, bpl, _vis,
     rmask, gmask, bmask, _bprgb, _cmap, ncolors) = h[:20]
    if ver != 7 or fmt != 2 or bpp not in (24, 32):
        print(f"ERROR: not an XWD v7 ZPixmap 24/32 bpp (version={ver} format={fmt} bpp={bpp}); use a 24-bit screen", file=sys.stderr); return 2
    off = hsize + ncolors * 12
    n = bpp // 8
    if len(d) < off + bpl * hgt:
        print(f"ERROR: truncated data ({len(d)} bytes, expected {off + bpl * hgt})", file=sys.stderr); return 2
    def pos(mask):  # index of that channel's byte within the pixel, according to the image byte order
        sh = (mask & -mask).bit_length() - 1
        return (n - 1 - sh // 8) if byte_order == 1 else sh // 8
    r, g, b = pos(rmask), pos(gmask), pos(bmask)
    rows, non_black = [], 0
    for y in range(hgt):
        f = d[off + y * bpl: off + y * bpl + w * n]
        rgb = bytearray(w * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = f[r::n], f[g::n], f[b::n]
        non_black += w - sum(1 for i in range(0, w * 3, 3) if rgb[i] == 0 and rgb[i + 1] == 0 and rgb[i + 2] == 0)
        rows.append(b'\x00' + bytes(rgb))
    def chunk(t, c):
        return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, hgt, 8, 2, 0, 0, 0)) \
        + chunk(b'IDAT', zlib.compress(b''.join(rows), 6)) + chunk(b'IEND', b'')
    open(sys.argv[2], 'wb').write(png)
    print(f"{w}x{hgt} depth={depth} bpp={bpp}: {non_black} of {w * hgt} pixels not black ({100.0 * non_black / (w * hgt):.1f}%) -> {sys.argv[2]}")
    return 0

sys.exit(main())
