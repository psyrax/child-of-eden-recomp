#!/bin/bash
# Disassembles N PPC instructions of the decrypted PE starting at an address, with llvm-mc (from the llvm package).
# Useful for code the codegen did NOT recognize as a function (show_func.sh sees nothing there).
# Usage (inside the container): disassemble.sh <default.pe> <0xADDR> <n_instr>
set -euo pipefail
[ $# -eq 3 ] || { echo "Usage: $0 <default.pe> <0xADDR> <n_instr>" >&2; exit 2; }
MC=$(command -v llvm-mc || ls /usr/bin/llvm-mc-* 2>/dev/null | head -1 || true)
[ -n "$MC" ] || { echo "ERROR: there is no llvm-mc in this image. Use an image that has the llvm package (eden-recomp:build does), or use: GEN=<XenonRecomp output dir> show_func.sh sub_<ADDR>" >&2; exit 1; }
off=$(( $2 - 0x82000000 ))
[ "$off" -ge 0 ] || { echo "ERROR: address below the base 0x82000000" >&2; exit 2; }
i=0
od -An -v -tx1 -j "$off" -N $(( $3 * 4 )) "$1" | tr -s ' \n' ' ' | sed 's/^ //' | fold -w 12 | while read -r a b c d; do
  ins=$(echo "0x$a 0x$b 0x$c 0x$d" | "$MC" --disassemble --triple=powerpc64-unknown-linux -mattr=+altivec 2>/dev/null | grep -v '\.text' | sed 's/^[[:space:]]*//' | tr '\t' ' ' || true)
  [ -n "$ins" ] || ins="<does not decode>"
  printf '0x%08X: %s%s%s%s  %s\n' $(( $2 + i * 4 )) "$a" "$b" "$c" "$d" "$ins"
  i=$(( i + 1 ))
done
