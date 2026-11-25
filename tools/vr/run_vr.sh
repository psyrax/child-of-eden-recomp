#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman and a Vulkan GPU): run_vr.sh <N> <actions...>
#   -> work/build/run<N>.log and work/shots/r<N>_*.png
# VR fork variant of tools/test/run.sh: identical, except that it forwards every EDEN_XMA_* and EDEN_VR_* variable to
# the game instead of the fixed list of diagnostic variables run.sh forwards. No OpenXR runtime is involved (see run_xr.sh).
# AUDIO=pulseaudio records the sound to work/build/audio<N>.wav (see tools/test/steps.sh). Default AUDIO=dummy (no sound).
# NOTE: --group-add 44 / 990 are the `video` / `render` GIDs of the development machine (see tools/test/run.sh).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
mkdir -p "$WORK/shots" && N=$1 && $ENGINE run --rm --shm-size=3g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) -m 6g --cpus 4 \
 -e XDG_RUNTIME_DIR=/tmp/xdg -e HOME=/tmp -e SDL_AUDIODRIVER=${AUDIO:-dummy} -e SDL_AUDIO_DISK_OUTPUT_FILE=/b/audio$N.raw -e SDL_DISKAUDIOFILE=/b/audio$N.raw -e LD_LIBRARY_PATH=/b $(env | grep -o "^EDEN_XMA_[A-Z]*\|^EDEN_VR_[A-Z_0-9]*" | sed "s/^/-e /") -e EDEN_EXTRA="$EDEN_EXTRA" -e EDEN_PAD_SCRIPT="$EDEN_PAD_SCRIPT" -e VIDEO="$VIDEO" -e BOT_SHOT="$BOT_SHOT" -e VIDEO_FROM="$VIDEO_FROM" \
 -v "$WORK/build:/b" -v "$WORK/game:/assets:ro" -v "$WORK/shots:/c" -v "$ROOT/tools:/s:ro" -w /b ${IMG:-eden-recomp:run-audio} \
 bash -c "mkdir -m 700 /tmp/xdg; PATH=\$PATH:/usr/games gamescope --backend headless -W ${GS_W:-1280} -H ${GS_H:-720} -w ${GS_W:-1280} -h ${GS_H:-720} $GS_EXTRA -- bash /s/test/steps.sh $* > /b/gamescope$N.log 2>&1"
grep "^key " "$WORK/build/gamescope$N.log"; ls "$WORK"/shots/r${N}_* | wc -l
