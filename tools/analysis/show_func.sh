#!/bin/bash
# Prints the PPC listing (the `// instr` comments and the labels) of one or more functions of the generated C++,
# compact, to read control flow without the C++. Read-only. Understands both formats used in the project:
#   rexglue     (DEFINE_REX_FUNC)        -> work/project/generated/default   (default)
#   XenonRecomp (PPC_FUNC_IMPL(__imp__)) -> GEN=<XenonRecomp output dir>; it recognizes functions rexglue does not.
# Usage: show_func.sh sub_82E7D008 [sub_...]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
GEN="${GEN:-$WORK/project/generated/default}"
[ -d "$GEN" ] || { echo "ERROR: $GEN does not exist; run the codegen first (tools/build/codegen.sh) or pass GEN=<dir>" >&2; exit 1; }
[ $# -ge 1 ] || { echo "Usage: $0 sub_XXXXXXXX [...]" >&2; exit 2; }
for f in "$@"; do
  file=$(grep -lE "^(DEFINE_REX_FUNC\($f\)|PPC_FUNC_IMPL\(__imp__$f\)) \{" "$GEN"/*recomp.*.cpp | head -1 || true)
  [ -n "$file" ] || { echo "== $f: not defined in $GEN (try GEN=<XenonRecomp output dir> or xref_calls.py)"; continue; }
  echo "== $f  ($(basename "$file"))"
  awk -v f="$f" '$0=="DEFINE_REX_FUNC(" f ") {" || $0=="PPC_FUNC_IMPL(__imp__" f ") {"{p=1;next} p&&/^}/{exit} p' "$file" \
    | grep -E '^	// |^loc_' | sed -e 's/^	\/\/ /  /'
done
