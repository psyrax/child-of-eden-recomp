#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman and a Vulkan GPU): run_video.sh <N> <actions...>
#   -> work/build/video<N>.mkv (real video + audio), run<N>.log and screenshots.
# Unlike VIDEO=1 (burst of screenshots), here gamescope publishes its image through PipeWire and GStreamer encodes it
# together with the game audio into a single file. Image ${IMG:-eden-recomp:capture-gamescope}. Same actions as run.sh.
# Variables: GS_W/GS_H (1280x720), VIDEO_FPS (60), VIDEO_KBPS (12000), EDEN_EXTRA, EDEN_INVINCIBLE, EDEN_AUTOAIM, BOT_SHOT.
# NOTE: --group-add 44 / 990 are the `video` / `render` GIDs of the development machine (see run.sh).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
[ -d "$WORK/build" ] || { echo "ERROR: $WORK/build does not exist; build the game first (tools/build/build.sh)." >&2; exit 2; }
N=$1
pgrep -x eden >/dev/null && { echo "ERROR: a game run is already in progress; wait for it to finish." >&2; exit 1; }
$ENGINE image inspect ${IMG:-eden-recomp:capture-gamescope} >/dev/null 2>&1 || { echo "ERROR: the image is missing; build it with: containers/build_images.sh --capture" >&2; exit 2; }
mkdir -p "$WORK/shots"
rm -f "$WORK/build/video$N.mkv"
$ENGINE run --rm --shm-size=3g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) -m 7g --cpus 6 \
 -e XDG_RUNTIME_DIR=/tmp/xdg -e HOME=/tmp -e SDL_AUDIODRIVER=pulseaudio -e LD_LIBRARY_PATH=/b -e EDEN_EXTRA="${EDEN_EXTRA:-}" \
 -e EDEN_PAD_SCRIPT="${EDEN_PAD_SCRIPT:-}" -e VIDEO=pw -e VIDEO_FPS="${VIDEO_FPS:-60}" -e VIDEO_KBPS="${VIDEO_KBPS:-12000}" -e BOT_SHOT="${BOT_SHOT:-}" \
 --env-file <(env | grep -E "^EDEN_(INVINCIBLE|AUTOAIM|VIDEO_TRACE|DAMAGE|AIM_TEST|XMA_MAX|GPU_[A-Z_]*|WAIT_[A-Z_]*|STUTTER_DIAG)=" || true) \
 -v "$WORK/build:/b" -v "$WORK/game:/assets:ro" -v "$WORK/shots:/c" -v "$ROOT/tools:/s:ro" -w /b ${IMG:-eden-recomp:capture-gamescope} \
 bash -c "mkdir -m 700 /tmp/xdg; export PATH=\$PATH:/usr/games
   dbus-run-session -- bash -c '
     pipewire > /tmp/pipewire.log 2>&1 & sleep 1; wireplumber > /tmp/wireplumber.log 2>&1 & sleep 1; pipewire-pulse > /tmp/pwpulse.log 2>&1 & sleep 2
     pactl load-module module-null-sink sink_name=nullsink rate=48000 channels=2 >/dev/null; pactl set-default-sink nullsink
     gamescope --backend headless -W ${GS_W:-1280} -H ${GS_H:-720} -w ${GS_W:-1280} -h ${GS_H:-720} ${GS_EXTRA:-} -- bash /s/test/steps.sh $* > /b/gamescope$N.log 2>&1
     cp /tmp/gst.log /b/gst$N.log 2>/dev/null'"
ls -la "$WORK/build/video$N.mkv" 2>/dev/null || { echo "ERROR: the video was not produced; check $WORK/build/gst$N.log and gamescope$N.log" >&2; exit 1; }
