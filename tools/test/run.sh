#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman and a Vulkan GPU): run.sh <N> <actions...>
#   -> work/build/run<N>.log and work/shots/r<N>_*.png   (actions: see steps.sh)
# DOCKER_EXTRA="-v /path:/path:ro" adds mounts or options to the container engine (e.g. system fonts).
# AUDIO=pulseaudio records the sound to work/build/audio<N>.wav (see steps.sh). Default AUDIO=dummy (no sound).
# IMG=<image> picks another runtime image (default eden-recomp:run-audio).
# NOTE: --group-add 44 / 990 are the GIDs of the `video` and `render` groups on the machine this was developed on
# (they give the container access to /dev/dri); check yours with `getent group video render`.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
mkdir -p "$WORK/shots" && N=$1 && $ENGINE run --rm --shm-size=3g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) -m 6g --cpus 4 \
 -e XDG_RUNTIME_DIR=/tmp/xdg -e HOME=/tmp -e SDL_AUDIODRIVER=${AUDIO:-dummy} -e SDL_AUDIO_DISK_OUTPUT_FILE=/b/audio$N.raw -e SDL_DISKAUDIOFILE=/b/audio$N.raw -e LD_LIBRARY_PATH=/b -e EDEN_EXTRA="$EDEN_EXTRA" -e EDEN_PAD_SCRIPT="$EDEN_PAD_SCRIPT" -e VIDEO="$VIDEO" -e BOT_SHOT="$BOT_SHOT" -e VIDEO_FROM="$VIDEO_FROM" --env-file <(env | grep -E "^EDEN_(INVINCIBLE|AUTOAIM|VIDEO_TRACE|DAMAGE|AIM_TEST|XMA_MAX|GPU_[A-Z_]*|WAIT_[A-Z_]*|STUTTER_DIAG|UPLOAD_DIAG)=" || true) \
 $DOCKER_EXTRA -v "$WORK/build:/b" -v "$WORK/game:/assets:ro" -v "$WORK/shots:/c" -v "$ROOT/tools:/s:ro" -w /b ${IMG:-eden-recomp:run-audio} \
 bash -c "mkdir -m 700 /tmp/xdg; PATH=\$PATH:/usr/games gamescope --backend headless -W ${GS_W:-1280} -H ${GS_H:-720} -w ${GS_W:-1280} -h ${GS_H:-720} $GS_EXTRA -- bash /s/test/steps.sh $* > /b/gamescope$N.log 2>&1"
grep "^key " "$WORK/build/gamescope$N.log"; ls "$WORK"/shots/r${N}_* | wc -l
