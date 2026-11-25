#!/bin/bash
# Run on the build machine: six runs in a row (519-524) of Matrix with the bot, 1920x1080 output, to compare upscalers.
# The run numbers, the action list and the cache directory (work/build/cache_merged, a shader cache merged beforehand
# with tools/package/merge_cache.py) are the parameters of that experiment; they are kept as they were.
# Needs passwordless sudo for perf (power_cpu.sh). Results: work/build/power<N>.txt, power_gpu<N>.txt, threads<N>.txt, run<N>.log.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"
[ -d "$WORK/build" ] || { echo "ERROR: $WORK/build does not exist; build the game first (tools/build/build.sh)." >&2; exit 2; }
one() { local N=$1 gs=$2 ex=$3
  pgrep -x eden >/dev/null && { echo "ERROR: another run is in progress" >&2; exit 1; }
  bash "$ROOT/tools/profile/power_cpu.sh" "$WORK/build/power$N.txt" 90 100 & bash "$ROOT/tools/profile/power_gpu.sh" "$WORK/build/power_gpu$N.txt" 90 100 &
  bash "$ROOT/tools/profile/sample_threads.sh" "$WORK/build/threads$N.txt" 90 > /dev/null 2>&1 &
  GS_W=1920 GS_H=1080 GS_EXTRA="$gs" EDEN_DAMAGE=20 EDEN_INVINCIBLE=1 EDEN_AUTOAIM=1 EDEN_EXTRA="--app.cache_root=/b/cache_merged $ex" \
    bash "$ROOT/tools/test/run.sh" $N f30 k33:Return k40:l f48 k49:space f63 b73-150 f150 b151-195 > /tmp/r$N.out 2>&1
  wait; sleep 5; }
one 519 "" ""
one 520 "-w 1280 -h 720 -F linear" ""
one 521 "-w 1280 -h 720 -F fsr" ""
one 522 "-w 1280 -h 720 -F fsr --fsr-sharpness 0" ""
one 523 "-w 1280 -h 720 -F nis" ""
one 524 "" "--gpu.resolution_scale_x=2 --gpu.resolution_scale_y=2"
touch /tmp/fsr.done
