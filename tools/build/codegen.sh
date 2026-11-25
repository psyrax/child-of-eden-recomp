#!/bin/bash
# Runs the rexglue codegen (PowerPC -> C++) for the project in work/project, inside the build container, with the
# `rexglue` tool mounted at /rx and the game mounted read-only. Limits: 6 GB / 4 CPUs.
#   tools/build/codegen.sh                 runs: /rx/rexglue codegen /w/project/eden_manifest.toml
#   tools/build/codegen.sh '<command>'     runs that command inside the same container instead (cwd /w), e.g.
#                                          tools/build/codegen.sh 'python3 -I /w/tools/analysis/string_at.py ...'
# Mounts: work/project -> /w/project (read-write), work/game -> /w/game and /assets (read-only), tools/ -> /w/tools (ro).
# The manifest refers to the game as ../game, which resolves to /w/game.
# The `rexglue` tool is built with tools/build/build_rexglue_tool.sh; it lands in
# work/rexglue-sdk/out/linux-<arch>/ (override the directory with REXGLUE_DIR).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
ENGINE="${ENGINE:-docker}"
RX="${REXGLUE_DIR:-$(ls -d "$WORK"/rexglue-sdk/out/linux-* 2>/dev/null | head -1)}"
[ -n "$RX" ] && [ -x "$RX/rexglue" ] || { echo "ERROR: the rexglue tool is missing (looked in ${RX:-$WORK/rexglue-sdk/out/linux-*}). Build it with: tools/build/build_rexglue_tool.sh" >&2; exit 1; }
[ -f "$WORK/game/default.xex" ] || { echo "ERROR: $WORK/game/default.xex is missing. Extract your disc image first: python3 -I tools/extract/xdvdfs_extract.py <iso> $WORK/game" >&2; exit 1; }
[ -f "$WORK/project/eden_manifest.toml" ] || { echo "ERROR: $WORK/project/eden_manifest.toml is missing. Copy the contents of game/ to $WORK/project first." >&2; exit 1; }
[ $# -gt 0 ] || set -- '/rx/rexglue codegen /w/project/eden_manifest.toml'
exec $ENGINE run --rm --user $(id -u):$(id -g) -e HOME=/tmp -m 6g --cpus 4 -v "$RX:/rx:ro" -v "$WORK/game:/assets:ro" -v "$WORK/game:/w/game:ro" -v "$WORK/project:/w/project" -v "$ROOT/tools:/w/tools:ro" -w /w ${IMG:-eden-recomp:build} bash -c "export LD_LIBRARY_PATH=/rx; $*"
