#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman and a Vulkan GPU): like run_vr.sh but with the headset
# output through OpenXR to Monado (simulated headset).
# Uses the build made with -DREXGLUE_VR_OPENXR=ON (work/build-xr, from tools/build/build_xr.sh) and the image
# eden-recomp:monado (containers/monado.Dockerfile).
# Usage: run_xr.sh <N> <steps.sh actions...>  -> work/build-xr/run<N>.log, monado<N>.log, work/shots/r<N>_*.png
# XR_REMOTE="<xr_remote.py actions>" drives the head and controllers (see xr_inner_steps.sh); TAIL=<n> log lines shown.
# NOTE: --group-add 44 / 990 are the `video` / `render` GIDs of the development machine (see tools/test/run.sh).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
mkdir -p "$WORK/shots" && N=$1 && $ENGINE run --rm --shm-size=3g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) -m 6g --cpus 4 \
 -e XDG_RUNTIME_DIR=/tmp/xdg -e HOME=/tmp -e SDL_AUDIODRIVER=${AUDIO:-dummy} -e LD_LIBRARY_PATH=/b -e EDEN_VR_OPENXR=1 \
 -e MONADO_ENV="DISABLE_GAMESCOPE_WSI=1 ENABLE_GAMESCOPE_WSI=0 $MONADO_ENV" \
 $(env | grep -o "^EDEN_XMA_[A-Z]*\|^EDEN_VR_[A-Z_0-9]*" | sed "s/^/-e /") -e XR_REMOTE="$XR_REMOTE" -e EDEN_EXTRA="$EDEN_EXTRA" -e BOT_SHOT="$BOT_SHOT" \
 -v "$WORK/build-xr:/b" -v "$WORK/game:/assets:ro" -v "$WORK/shots:/c" -v "$ROOT/tools:/s:ro" -w /b eden-recomp:monado \
 bash -c "mkdir -m 700 /tmp/xdg; PATH=\$PATH:/usr/games gamescope --backend headless -W ${GS_W:-1280} -H ${GS_H:-720} -w ${GS_W:-1280} -h ${GS_H:-720} $GS_EXTRA -- bash /s/vr/xr_inner_steps.sh $* > /b/gamescope$N.log 2>&1"
grep "^key \|^hands " "$WORK/build-xr/gamescope$N.log" | tail -3; grep "vr-xr\|vr-fps" "$WORK/build-xr/run$N.log" | tail -${TAIL:-12} | cut -c1-160; ls "$WORK"/shots/r${N}_* | wc -l
