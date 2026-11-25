#!/bin/bash
# Assembles the playable package in work/package/child-of-eden from work/build (binaries) and work/game (your own
# extracted disc data). The result contains game code and data: it is for your own use and must not be redistributed.
# Usage: make_package.sh [--dry-run] [--copy-data]
#   --dry-run    print what would be done, change nothing
#   --copy-data  copy the game data instead of hard-linking it (needed when the package lives on another filesystem)
# Never touched if they already exist in the package: user/ (saves), cache/, logs/, bin/eden.toml (your settings).
# Optional: a shader cache in work/cache_base/ is shipped as cache_base/ (play.sh merges it into cache/ at launch).
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
BUILD="$WORK/build"; GAME="$WORK/game"; PKG="$WORK/package/child-of-eden"
DRY=0; COPY=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1;; --copy-data) COPY=1;;
  *) echo "ERROR: unknown option $a (use --dry-run or --copy-data)" >&2; exit 2;;
esac; done
run() { if [ $DRY = 1 ]; then echo "would run: $*"; else "$@"; fi; }

[ -x "$BUILD/eden" ] || { echo "ERROR: $BUILD/eden not found. Run tools/build/build.sh first." >&2; exit 1; }
ls "$BUILD"/librex*.so >/dev/null 2>&1 || { echo "ERROR: no librex*.so in $BUILD: the build is incomplete, run tools/build/build.sh again." >&2; exit 1; }
[ -f "$GAME/default.xex" ] || { echo "ERROR: $GAME/default.xex not found. Extract your disc image first (tools/extract/xdvdfs_extract.py)." >&2; exit 1; }
if pgrep -x eden >/dev/null 2>&1; then echo "ERROR: the game is running; close it and run this again." >&2; exit 1; fi

run mkdir -p "$PKG/bin"
# Binaries: the executable and every shared library the build produced (runtime + SDL3).
for f in "$BUILD"/eden "$BUILD"/lib*.so*; do run install -m 755 "$f" "$PKG/bin/"; done
run install -m 644 "$ROOT/tools/package/merge_cache.py" "$PKG/bin/merge_cache.py"
run install -m 755 "$ROOT/tools/package/play.sh" "$PKG/play.sh"
run install -m 644 "$ROOT/tools/package/README-package.md" "$PKG/README.md"
# Game data: hard links by default (no extra disk space); the package never writes to assets/.
if [ -d "$PKG/assets" ]; then
  echo "assets/ already present, left as is"
elif [ $COPY = 1 ]; then
  run cp -a "$(readlink -f "$GAME")" "$PKG/assets"
else
  run cp -al "$(readlink -f "$GAME")" "$PKG/assets" || { echo "ERROR: could not hard-link the game data (different filesystem?). Run again with --copy-data." >&2; exit 1; }
fi
if [ -d "$WORK/cache_base/shaders" ]; then run mkdir -p "$PKG/cache_base"; run cp -a "$WORK/cache_base/." "$PKG/cache_base/"; fi
[ $DRY = 1 ] || echo "Package ready: $PKG  (start it with $PKG/play.sh)"
