#!/usr/bin/env python3
"""Minimal XDVDFS extractor (Xbox/360 ISO). Usage: xdvdfs_extract.py <iso> <destination> [--list]"""
import os, struct, sys
SECTOR = 2048
MAGIC = b"MICROSOFT*XBOX*MEDIA"
OFFSETS = [0x00000000, 0x0000FB20 * SECTOR, 0x00020600 * SECTOR, 0x0FD90000, 0x02080000, 0x18300000]

def find_root(f):
    for off in OFFSETS:
        f.seek(off + 32 * SECTOR)
        d = f.read(SECTOR)
        if d[:20] == MAGIC:
            root_sector, root_size = struct.unpack("<II", d[20:28])
            return off, root_sector, root_size
    raise SystemExit("XDVDFS descriptor not found at any of the known offsets")

def walk(f, base, sector, size, path, out, listonly):
    f.seek(base + sector * SECTOR)
    data = f.read(size)
    def entry(off):
        l, r, sec, sz, attr, nl = struct.unpack("<HHIIBB", data[off:off+14])
        return l, r, sec, sz, attr, data[off+14:off+14+nl].decode("latin1")
    seen = set()
    def visit(node):
        if node in seen or node * 4 >= len(data): return
        seen.add(node)
        off = node * 4
        l, r, sec, sz, attr, name = entry(off)
        if l == 0xFFFF and r == 0xFFFF and sec == 0xFFFFFFFF: return
        visit(l)
        if name in ("", ".", "..") or any(c in name for c in "/\\\0"):
            raise SystemExit(f"unsafe name in the ISO: {name!r}")
        p = os.path.join(path, name)
        if os.path.commonpath([os.path.realpath(os.path.join(out, p)), os.path.realpath(out)]) != os.path.realpath(out):
            raise SystemExit(f"path outside the destination in the ISO: {p!r}")
        if attr & 0x10:
            if not listonly: os.makedirs(os.path.join(out, p), exist_ok=True)
            if sz: walk(f, base, sec, sz, p, out, listonly)
        else:
            print(f"{sz:12d}  {p}")
            if not listonly:
                dst = os.path.join(out, p); os.makedirs(os.path.dirname(dst), exist_ok=True)
                f.seek(base + sec * SECTOR); rem = sz
                with open(dst, "wb") as o:
                    while rem > 0:
                        b = f.read(min(rem, 1 << 20)); o.write(b); rem -= len(b)
        visit(r)
    visit(0)

iso, out = sys.argv[1], sys.argv[2]
with open(iso, "rb") as f:
    base, rs, rz = find_root(f)
    print(f"# base=0x{base:x} root_sector={rs} root_size={rz}")
    walk(f, base, rs, rz, "", out, "--list" in sys.argv)
