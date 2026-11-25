#!/usr/bin/env python3
"""Merges shader caches of the runtime (rexglue, Vulkan backend) without losing anything from the destination one.

The "shareable" cache is two files per game, portable across machines (they carry no driver binaries):
  <TITLE>.xsh            'XESH' + version; records = hash(8) + [n_dwords:31|type:1](4) + microcode (n*4 bytes)
  <TITLE>.fbo.vk.xpso    'XEPS' + api + version; 68-byte records = hash(8) + pipeline description(60)
On startup the runtime translates those shaders and creates those pipelines before entering the game: that is the
"precompilation".

Usage:  merge_cache.py [--dry-run] <destination/cache> <source/cache> [<source2/cache> ...]
        (each path is the root that contains shaders/shareable/)
- Adds to the destination the records of the sources that it lacks (by hash). Never removes or reorders what was there.
- Idempotent: if there is nothing new, nothing is written. Writes to a temporary file and renames (no half-written files).
- If the version of a source does not match the destination's, that source is ignored (the runtime would discard it).
- Do NOT run with the game open: the game keeps those files open and appends to them.
Exit code: 0 ok (even if there was nothing to do), 2 wrong usage or unreadable destination.
"""
import os, struct, sys

PIPELINE_RECORD = 68


def read_xsh(path):
    """-> (header, [(key, bytes)]) with complete records only; None if it does not exist or is not XESH."""
    try:
        d = open(path, 'rb').read()
    except OSError:
        return None
    if len(d) < 8 or d[:4] != b'XESH':
        return None
    recs, o = [], 8
    while o + 12 <= len(d):
        h, n = struct.unpack_from('<QI', d, o)
        end = o + 12 + (n & 0x7FFFFFFF) * 4
        if end > len(d):
            break  # truncated record (power loss in the middle of a write): the tail is dropped
        recs.append(((h, n >> 31), d[o:end]))
        o = end
    return d[:8], recs


def read_xpso(path):
    try:
        d = open(path, 'rb').read()
    except OSError:
        return None
    if len(d) < 12 or d[:4] != b'XEPS':
        return None
    n = (len(d) - 12) // PIPELINE_RECORD
    return d[:12], [(d[12 + i * PIPELINE_RECORD:20 + i * PIPELINE_RECORD], d[12 + i * PIPELINE_RECORD:12 + (i + 1) * PIPELINE_RECORD])
                    for i in range(n)]


def merge(name, reader, dest, sources, dry):
    dest_path = os.path.join(dest, 'shaders', 'shareable', name)
    base = reader(dest_path)
    header, recs = base if base else (None, [])
    seen = {k for k, _ in recs}
    before = len(recs)
    for o in sources:
        src_path = os.path.join(o, 'shaders', 'shareable', name)
        other = reader(src_path)
        if other is None:
            print(f'  {name}: {src_path} does not exist or is not valid; ignored')
            continue
        if header is None:
            header = other[0]
        elif other[0] != header:
            print(f'  {name}: {src_path} is from another runtime version; ignored')
            continue
        for k, r in other[1]:
            if k not in seen:
                seen.add(k)
                recs.append((k, r))
    new = len(recs) - before
    print(f'  {name}: {before} in destination, {new} new, {len(recs)} in total')
    if new and not dry:
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        tmp = dest_path + '.tmp'
        with open(tmp, 'wb') as f:
            f.write(header)
            for _, r in recs:
                f.write(r)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, dest_path)
    return new


def main(a):
    dry = '--dry-run' in a
    a = [x for x in a if x != '--dry-run']
    if len(a) < 2:
        print(__doc__)
        return 2
    dest, sources = a[0], a[1:]
    if not os.path.isdir(dest):
        print(f'ERROR: the destination {dest} does not exist; create it (mkdir) or check the path.')
        return 2
    sh = os.path.join(dest, 'shaders', 'shareable')
    names = set()
    for r in [dest] + sources:
        p = os.path.join(r, 'shaders', 'shareable')
        if os.path.isdir(p):
            names |= {n for n in os.listdir(p) if n.endswith('.xsh') or n.endswith('.vk.xpso')}
    if not names:
        print('Nothing to merge: no source has shaders/shareable/*.xsh or *.vk.xpso.')
        return 0
    print(('[dry run] ' if dry else '') + f'destination: {sh}')
    for n in sorted(names):
        merge(n, read_xsh if n.endswith('.xsh') else read_xpso, dest, sources, dry)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
