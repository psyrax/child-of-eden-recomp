#!/usr/bin/env python3
"""Searches for a byte sequence (hex) in every file of a directory and shows context. Read-only.
Usage: find_bytes.py <dir> <hex> [before=8] [after=8] [max_per_file=3]
E.g. (words 2..4 of a Xenos texture fetch constant, big-endian as on disc):
    python3 -I find_bytes.py /assets 001FE0FF01280D1000000203 8 4
Exits with 2 if the directory does not exist or is empty (so "not mounted" is not mistaken for "no matches")."""
import mmap, os, sys

def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr); return 2
    d, pat = sys.argv[1], bytes.fromhex(sys.argv[2])
    before = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    after = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    limit = int(sys.argv[5]) if len(sys.argv) > 5 else 3
    if not os.path.isdir(d):
        print(f"ERROR: {d} is not a directory; mount the game data (-v work/game:/assets:ro)", file=sys.stderr); return 2
    files = total = with_hits = 0
    for root, _, names in os.walk(d):
        for n in sorted(names):
            p = os.path.join(root, n)
            try:
                size = os.path.getsize(p)
                if size < len(pat): continue
                files += 1
                with open(p, 'rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
                    i, k = m.find(pat), 0
                    while i >= 0:
                        if k < limit:
                            a = m[max(0, i - before):i].hex(); b = m[i + len(pat):i + len(pat) + after].hex()
                            print(f"{os.path.relpath(p, d)} @0x{i:X}: [{a}] {pat.hex()} [{b}]")
                        k += 1; i = m.find(pat, i + 1)
                    if k:
                        with_hits += 1; total += k
                        if k > limit: print(f"{os.path.relpath(p, d)}: {k} matches in total")
            except OSError as e:
                print(f"WARNING: could not read {p}: {e}", file=sys.stderr)
    if files == 0:
        print(f"ERROR: {d} has no readable files; is it mounted?", file=sys.stderr); return 2
    print(f"-- {total} matches in {with_hits} of {files} files")
    return 0

sys.exit(main())
