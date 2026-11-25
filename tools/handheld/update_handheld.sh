#!/bin/bash
# Updates the game binaries on the handheld (e.g. a ROG Ally running CachyOS) from the playable package.
# Runs on any machine with ssh access to the handheld.
#   HANDHELD=user@host   ssh target of the handheld (required)
#   HANDHELD_DIR         where the game lives on the handheld (default ~/Apps/child-of-eden)
#   PKG                  the package to copy (default work/package/child-of-eden; no spaces in the path)
#   SRC                  optional ssh target of the build machine if the package is not on this machine; PKG is then a
#                        path on that host
# Only touches <HANDHELD_DIR>/bin, play.sh and cache_base/ (precompiled shaders of the package); never user/ (the save),
# cache/ (the handheld's own cache; play.sh adds what is in cache_base/ to it without removing anything) or logs/.
# Idempotent: if the handheld already has the same binaries it does nothing. Usage: update_handheld.sh [--dry-run]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"
HANDHELD=${HANDHELD:-}; SRC=${SRC:-}; PKG=${PKG:-$WORK/package/child-of-eden}; DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ -n "$HANDHELD" ] || { echo "ERROR: set HANDHELD=user@host (the ssh target of the handheld) and run this again." >&2; exit 2; }
DEST=${HANDHELD_DIR:-}; [ -n "$DEST" ] || DEST='~/Apps/child-of-eden'
LOCK=/tmp/update_handheld.lock
mkdir "$LOCK" 2>/dev/null || { echo "ERROR: an update is already in progress ($LOCK). If that is not the case: rmdir $LOCK" >&2; exit 1; }
trap 'rmdir "$LOCK"' EXIT
# No `timeout` (macOS does not ship it): a dead connection is cut by ssh itself (60 s with no answer).
S="ssh -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4"
# Runs a command where the package is: on this machine, or on $SRC through ssh.
src_run() { if [ -n "$SRC" ]; then $S "$SRC" "bash -c $(printf %q "$1")"; else bash -c "$1"; fi; }
WHERE=${SRC:-this machine}
# Only the files the package ships are compared: the handheld also has bin/eden.toml (local settings), which is left alone.
list=$(src_run "cd $PKG && ls -d bin/* play.sh; if [ -d cache_base ]; then find cache_base -type f | sort; fi" | tr '\n' ' ') || { echo "ERROR: could not read the package $PKG on $WHERE. Check the path${SRC:+ and 'ssh $SRC'}." >&2; exit 1; }
[ -n "${list// /}" ] || { echo "ERROR: the package $PKG on $WHERE is empty; nothing is updated." >&2; exit 1; }
new=$(src_run "cd $PKG && sha256sum $list 2>&1 | sha256sum | cut -c1-16") || { echo "ERROR: could not read the package $PKG on $WHERE. Check the path${SRC:+ and 'ssh $SRC'}." >&2; exit 1; }
[ ${#new} = 16 ] || { echo "ERROR: empty package checksum; nothing is updated." >&2; exit 1; }
remote_sum() { $S "$HANDHELD" "bash -c 'cd $DEST && sha256sum $list 2>&1 | sha256sum | cut -c1-16'"; }
current=$(remote_sum) || { echo "ERROR: the handheld does not answer ($HANDHELD). Turn it on and connect it to the network; then run this again." >&2; exit 1; }
echo "package=$new handheld=$current"
[ "$new" = "$current" ] && { echo "The handheld is already up to date."; exit 0; }
if $S "$HANDHELD" 'pgrep -x eden >/dev/null'; then echo "ERROR: the game is open on the handheld. Close it (hold START -> Quit) and run this again." >&2; exit 1; fi
[ $DRY = 1 ] && { echo "(--dry-run) bin/ would be backed up and bin/, play.sh and cache_base/ would be copied"; exit 0; }
stamp=$(date +%Y%m%d-%H%M)
$S "$HANDHELD" "bash -c 'cd $DEST && [ -e bin.prev-$stamp ] || cp -a bin bin.prev-$stamp; [ ! -e play.sh ] || [ -e play.sh.prev-$stamp ] || cp -p play.sh play.sh.prev-$stamp'"
src_run "cd $PKG && tar -cf - bin play.sh \$([ -d cache_base ] && echo cache_base)" | $S "$HANDHELD" "bash -c \"tar -C $DEST -xf -\""
final=$(remote_sum)
[ "$final" = "$new" ] || { echo "ERROR: the copy does not match (handheld=$final). To go back: on the handheld, rm -r bin && mv bin.prev-$stamp bin" >&2; exit 1; }
echo "Handheld updated ($final). Previous build in bin.prev-$stamp (rollback: rm -r bin && mv bin.prev-$stamp bin)."
