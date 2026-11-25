#!/bin/bash
# Child of Eden (recompiled). Launches the game from this folder. A built package contains game code and data: do not
# redistribute it.
#   ./play.sh                 fullscreen, controller through SDL (any gamepad SDL recognizes)
#   ./play.sh --windowed      in a window
#   ./play.sh --keyboard      keyboard as the controller (Enter=START, Space=A, L=X, Backspace=B, WASD=left stick)
#   ./play.sh --fps=30        limits the frame rate (the game is a 60 fps game; at 30 it does not go into slow motion; 0 = no limit)
#   ./play.sh --scale=2       internal resolution x2 (1280x720 -> 2560x1440; experimental on Vulkan)
#   ./play.sh --fxaa          FXAA (smooths edges; --fxaa=extreme uses fxaa_extreme). Can be combined with --scale=2
#   ./play.sh --gyro          the controller's gyro moves the reticle (added to the stick). --gyro=2 doubles the sensitivity;
#                             --gyro-invert-x / --gyro-invert-y flip the direction; --gyro-roll also uses the sideways tilt
#   ./play.sh --hz=120        EXPERIMENTAL: the game produces 120 real frames on a 120 Hz display (some sequences run faster)
#   In game, with a keyboard: F4 = settings menu ("Save to config" stores them in bin/eden.toml), F3 = frame counter.
#   anything else is passed straight to the game (e.g. --log.level=debug)
set -u
D="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
[ -x "$D/bin/eden" ] || { echo "$D/bin/eden is missing: the package is incomplete, copy it again."; exit 2; }
[ -f "$D/assets/default.xex" ] || { echo "The game data is missing in $D/assets (default.xex): copy the whole assets folder."; exit 2; }
needs=$(strings "$D/bin/eden" 2>/dev/null | grep -o 'GLIBC_2\.[0-9]*' | sort -uV | tail -1 | cut -d_ -f2)
has=$(ldd --version 2>/dev/null | head -1 | grep -o '[0-9]\+\.[0-9]\+$')
if [ -n "$needs" ] && [ -n "$has" ] && [ "$(printf '%s\n%s\n' "$needs" "$has" | sort -V | head -1)" != "$needs" ]; then
  echo "This build needs glibc $needs and the system has $has: update the system (e.g. sudo pacman -Syu) or make a new build."; exit 3
fi
has_vulkan=no; for v in /usr/lib/libvulkan.so.1 /usr/lib64/libvulkan.so.1 /usr/lib/x86_64-linux-gnu/libvulkan.so.1; do [ -e "$v" ] && has_vulkan=yes; done
[ $has_vulkan = yes ] || echo "Warning: libvulkan.so.1 not found (install vulkan-icd-loader and your GPU driver)."
extra=();
for a in "$@"; do case "$a" in
  --windowed) extra+=(--ui.fullscreen=false);;
  --keyboard) extra+=(--hid.mnk_mode=true);;
  --fxaa) extra+=(--gpu.xenos.swap_post_effect=fxaa);;
  --fxaa=extreme) extra+=(--gpu.xenos.swap_post_effect=fxaa_extreme);;
  --gyro) extra+=(--hid.sdl.gyro=true);;
  --gyro=*) extra+=(--hid.sdl.gyro=true --hid.sdl.gyro_sensitivity="${a#--gyro=}");;
  --gyro-invert-x) extra+=(--hid.sdl.gyro_invert_x=true);;
  --gyro-invert-y) extra+=(--hid.sdl.gyro_invert_y=true);;
  --gyro-roll) extra+=(--hid.sdl.gyro_roll=1);;
  --hz=*) extra+=(--ui.video_mode_refresh_rate="${a#--hz=}");;
  --fps=*) extra+=(--gpu.frame_limit="${a#--fps=}");;
  --scale=*) extra+=(--gpu.resolution_scale_x="${a#--scale=}" --gpu.resolution_scale_y="${a#--scale=}");;
  *) extra+=("$a");;
esac; done
# Testing: if test.env exists next to this script it is sourced (tools/handheld/handheld_test.sh writes and removes it).
# EDEN_ARGS appends options at the end; EDEN_BIN_DIR runs another build (e.g. bin.prev-*).
[ -f "$D/test.env" ] && . "$D/test.env"
mkdir -p "$D/user" "$D/logs" "$D/cache"
# Precompiled shader cache: if the package ships cache_base/, whatever is missing is added to cache/ (it never removes
# anything from yours). The game compiles it at startup, so the first appearance of each effect no longer stutters. If it
# fails, the game still runs.
if [ -d "$D/cache_base/shaders/shareable" ] && [ -f "$D/bin/merge_cache.py" ] && command -v python3 >/dev/null 2>&1 \
   && ! pgrep -x eden >/dev/null 2>&1; then
  python3 -I "$D/bin/merge_cache.py" "$D/cache" "$D/cache_base" > "$D/logs/cache_base.log" 2>&1 \
    || echo "Warning: could not add the precompiled shader cache (see logs/cache_base.log); the game works the same."
fi
B="${EDEN_BIN_DIR:-$D/bin}"
cd "$B" || exit 2
LD_LIBRARY_PATH="$B${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec ./eden --title.game_root="$D/assets" --app.user_root="$D/user" --app.log_root="$D/logs" --app.cache_root="$D/cache" \
  --gpu.driver=vulkan --gpu.xenos.allow_invalid_fetch_constants=true --gpu.xenos.readback_memexport=false \
  --gpu.xenos.clear_memory_page_state=false "${extra[@]}" ${EDEN_ARGS:-}
# readback_memexport=false: the runtime was reading back to memory, waiting for the GPU on every draw, the particles the
# game computes on the GPU; that dropped the frame rate to 30 and 15 fps in busy scenes (runs 430 and 431). To turn it
# back on: ./play.sh --gpu.xenos.readback_memexport=true
# clear_memory_page_state=false: by default the runtime invalidated, at the end of every frame, all the game memory
# already uploaded to the GPU and copied it again (47 MB per frame when starting the second level, 99.7 % identical;
# runs 525-529). On a ROG Ally on battery that dropped the frame rate to 30 fps. If broken geometry or missing models
# show up, try ./play.sh --gpu.xenos.clear_memory_page_state=true
