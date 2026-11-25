#!/bin/bash
# Fetches rexglue-sdk at the pinned version into work/rexglue-sdk and applies patches/sdk/*.patch in order.
# Idempotent: an SDK that already carries the patches is left alone. Usage: setup_sdk.sh [--dry-run] [--force]
#   --dry-run  print what would be done, change nothing
#   --force    discard local changes in work/rexglue-sdk and re-apply the series
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
SDK="$WORK/rexglue-sdk"
URL=https://github.com/rexglue/rexglue-sdk
TAG=v0.11.0
COMMIT=a3e1d82678ca20d68d4837a8e9ee4652ff073745
DRY=0; FORCE=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1;; --force) FORCE=1;;
  *) echo "ERROR: unknown option $a (use --dry-run or --force)" >&2; exit 2;;
esac; done
run() { if [ $DRY = 1 ]; then echo "would run: $*"; else "$@"; fi; }
ls "$ROOT"/patches/sdk/*.patch >/dev/null 2>&1 || { echo "ERROR: no patches in $ROOT/patches/sdk; is the checkout complete?" >&2; exit 1; }

if [ ! -d "$SDK/.git" ]; then
  run mkdir -p "$WORK"
  run git clone --branch "$TAG" --depth 1 --recurse-submodules --shallow-submodules "$URL" "$SDK"
  [ $DRY = 1 ] && { echo "would apply: $(ls "$ROOT"/patches/sdk/*.patch | wc -l) patches"; exit 0; }
fi
HEAD_NOW=$(git -C "$SDK" rev-parse HEAD)
[ "$HEAD_NOW" = "$COMMIT" ] || { echo "ERROR: $SDK is at $HEAD_NOW, expected $TAG = $COMMIT. Remove the directory and run this again." >&2; exit 1; }

if [ -f "$SDK/.eden-patches-applied" ] && [ $FORCE = 0 ]; then
  echo "SDK already patched ($(cat "$SDK/.eden-patches-applied")). Use --force to reset and re-apply."; exit 0
fi
if [ -n "$(git -C "$SDK" status --porcelain --untracked-files=no)" ]; then
  if [ $FORCE = 1 ]; then run git -C "$SDK" checkout -- . ; run rm -f "$SDK/.eden-patches-applied"
  else echo "ERROR: $SDK has local changes but no patch marker. Run with --force to discard them and re-apply." >&2; exit 1; fi
fi
[ $FORCE = 1 ] && run git -C "$SDK" clean -fdq -- src include
for p in "$ROOT"/patches/sdk/*.patch; do
  run git -C "$SDK" apply --check "$p" || { echo "ERROR: $(basename "$p") does not apply to a clean $TAG. Nothing was changed by this patch; run with --force to start over." >&2; exit 1; }
  run git -C "$SDK" apply "$p"
  [ $DRY = 1 ] || echo "applied $(basename "$p")"
done
[ $DRY = 1 ] || { ls "$ROOT"/patches/sdk/*.patch | xargs -n1 basename | tr '\n' ' ' > "$SDK/.eden-patches-applied"; echo "SDK ready in $SDK"; }
