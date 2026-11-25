#!/usr/bin/env python3
"""Sorts the binary-search table of .eh_frame_hdr in a little-endian ELF64.

Why it exists: with -mcmodel=large, LLD 21.1.8 leaves a small .text AFTER .eh_frame_hdr and writes the table with
those entries first (unsorted). libgcc rejects any pc lower than the first entry, _Unwind_Find_FDE returns NULL and
every `throw` ends in std::terminate. Measured on 2026-11-19 on eden, librexkernel.so and librexbase.so
(see docs/analysis/threadstop.md).

Usage:  sort_eh_frame_hdr.py [--dry-run] FILE [FILE...]
Idempotent: if the table is already sorted nothing is written. Exits with 2 if a file could not be processed.
"""
import struct
import sys


def process(path, dry):
    with open(path, "rb") as f:
        d = bytearray(f.read())
    if d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 1:
        raise ValueError("not a little-endian ELF64")
    shoff, = struct.unpack_from("<Q", d, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)
    if shoff == 0 or shnum == 0:
        raise ValueError("no section table (fully stripped binary?)")
    secs = [struct.unpack_from("<IIQQQQ", d, shoff + i * shentsize) for i in range(shnum)]
    stro = secs[shstrndx][4]
    hdr = None
    for n, _t, _fl, addr, off, size in secs:
        if bytes(d[stro + n:d.index(b"\0", stro + n)]) == b".eh_frame_hdr":
            hdr = (addr, off, size)
    if hdr is None:
        raise ValueError("it has no .eh_frame_hdr section")
    _addr, off, size = hdr
    ver, _ehp, cnt_enc, tab_enc = struct.unpack_from("<BBBB", d, off)
    if ver != 1 or cnt_enc != 0x03 or tab_enc != 0x3B:
        raise ValueError(f"unsupported encoding (ver={ver} count={cnt_enc:#x} table={tab_enc:#x}); "
                         "only udata4 + datarel|sdata4")
    cnt, = struct.unpack_from("<I", d, off + 8)
    if 12 + 8 * cnt > size:
        raise ValueError("the table does not fit in the section: corrupt header")
    base = off + 12
    table = [struct.unpack_from("<ii", d, base + 8 * i) for i in range(cnt)]
    out_of_order = sum(1 for i in range(cnt - 1) if table[i][0] > table[i + 1][0])
    if out_of_order == 0:
        print(f"{path}: {cnt} entries, already sorted; no changes")
        return
    ordered = sorted(table, key=lambda e: e[0])
    if dry:
        print(f"{path}: {cnt} entries, {out_of_order} order break(s); --dry-run, nothing written")
        return
    for i, (a, b) in enumerate(ordered):
        struct.pack_into("<ii", d, base + 8 * i, a, b)
    with open(path, "r+b") as f:
        f.seek(base)
        f.write(d[base:base + 8 * cnt])
    print(f"{path}: {cnt} entries, {out_of_order} order break(s); table re-sorted")


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    paths = [a for a in args if a != "--dry-run"]
    if not paths:
        sys.exit(__doc__)
    bad = 0
    for p in paths:
        try:
            process(p, dry)
        except (OSError, ValueError, struct.error) as e:
            bad = 1
            print(f"{p}: ERROR: {e}. Check that it is the linked binary (eden or lib*.so) and run again.",
                  file=sys.stderr)
    sys.exit(2 if bad else 0)


if __name__ == "__main__":
    main()
