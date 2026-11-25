#!/usr/bin/env python3
"""Checks whether the lookup table of .eh_frame_hdr in an ELF64 is sorted AS SIGNED INTEGERS.

Why it matters: libgcc (unwind-dw2-fde-dip.c, find_fde_tail) binary-searches that table reading `initial_loc` as an
int32 relative to .eh_frame_hdr. If the linker sorted it as uint32 and there are functions both BEFORE and AFTER
.eh_frame_hdr (e.g. `.ltext` before and `.text` after, which is what lld >= 21 does with -mcmodel=large), the table
ends up as [positives..., negatives...]: for any PC below the section, `pc < table[0]` and libgcc returns "no FDE"
-> _URC_END_OF_STACK -> std::terminate on every `throw`, even when the `catch` exists. See docs/analysis/threadstop.md.

Usage:  python3 check_eh_frame_hdr.py <elf> [<elf> ...]
Exits with 0 if every table is fine, 1 if any is wrong, 2 if a file could not be read.
Read-only; no dependencies outside the standard library.
"""
import struct
import sys

SECTIONS = (".ltext", ".lrodata", ".rodata", ".eh_frame_hdr", ".eh_frame", ".text", ".init", ".plt")


def read_sections(data):
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF")
    if data[4] != 2 or data[5] != 1:
        raise ValueError("only little-endian ELF64 is supported")
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    if shoff == 0 or shnum == 0:
        raise ValueError("no section table (fully stripped binary?)")
    raw = []
    for i in range(shnum):
        name, kind, flags, addr, off, size = struct.unpack_from("<IIQQQQ", data, shoff + i * shentsize)
        raw.append((name, kind, flags, addr, off, size))
    str_off = raw[shstrndx][4]
    sections = {}
    for name, kind, flags, addr, off, size in raw:
        end = data.index(b"\0", str_off + name)
        sections[data[str_off + name:end].decode("ascii", "replace")] = (kind, flags, addr, off, size)
    return sections


def check(path):
    with open(path, "rb") as fh:
        data = fh.read()
    sections = read_sections(data)
    print(f"== {path}")
    for name in SECTIONS:
        if name in sections:
            _, _, addr, _, size = sections[name]
            print(f"   {name:<14} addr={addr:#014x} size={size:#x}")
    if ".eh_frame_hdr" not in sections:
        print("   NO .eh_frame_hdr: libgcc cannot find FDEs in this binary")
        return False
    _, _, hdr_addr, hdr_off, hdr_size = sections[".eh_frame_hdr"]
    version, ptr_enc, count_enc, table_enc = struct.unpack_from("<BBBB", data, hdr_off)
    print(f"   hdr: version={version} eh_frame_ptr_enc={ptr_enc:#x} fde_count_enc={count_enc:#x} "
          f"table_enc={table_enc:#x}")
    if ptr_enc != 0x1B or count_enc != 0x03 or table_enc != 0x3B:
        print("   encoding differs from the usual one (pcrel|sdata4, udata4, datarel|sdata4): "
              "this script does not interpret it; libgcc would use a linear search if table_enc != 0x3b")
        return True
    count, = struct.unpack_from("<I", data, hdr_off + 8)
    table = struct.unpack_from(f"<{2 * count}i", data, hdr_off + 12)
    locs = table[0::2]
    negatives = sum(1 for v in locs if v < 0)
    positives = count - negatives
    breaks = [i for i in range(1, count) if locs[i] < locs[i - 1]]
    print(f"   entries={count}  before_hdr(negative)={negatives}  after_hdr(positive)={positives}")
    if count:
        print(f"   table[0]  = {locs[0]:+#x} -> pc {hdr_addr + locs[0]:#x}")
        print(f"   table[-1] = {locs[-1]:+#x} -> pc {hdr_addr + locs[-1]:#x}")
    if not breaks:
        print("   OK: sorted as signed; libgcc's binary search works")
        return True
    i = breaks[0]
    below_first = sum(1 for v in locs if v < locs[0])
    print(f"   BAD: NOT sorted as signed ({len(breaks)} break(s); the first at index {i}: "
          f"{locs[i - 1]:+#x} -> {locs[i]:+#x}).")
    print(f"   {below_first} of {count} functions fall below table[0]: libgcc answers 'no FDE' "
          "for them.")
    if locs[-1] < locs[0]:
        print("   Also table[-1] < table[0]: for the rest libgcc picks the last entry and the range does not "
              "match, so NO function of the binary can be found.")
    print("   Effect: every throw that goes through this binary ends in std::terminate even if there is a catch.")
    print("   What to do: link with lld 20 (as the SDK expects) or with an lld that sorts as signed, or run "
          "tools/build/sort_eh_frame_hdr.py on the binary; see docs/analysis/threadstop.md")
    return False


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    status = 0
    for path in argv[1:]:
        try:
            if not check(path):
                status = max(status, 1)
        except (OSError, ValueError, struct.error) as exc:
            print(f"== {path}\n   ERROR: {exc}. Check that the path exists and is an x86_64/arm64 ELF64.")
            status = 2
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
