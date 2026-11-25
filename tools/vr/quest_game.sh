#!/bin/bash
# Launched by wivrn-server (inside the eden-recomp:wivrn container) when the Quest connects: the game with OpenXR output to WiVRn.
cd /b
export XR_RUNTIME_JSON=/w/share/openxr/1/openxr_wivrn.json LD_LIBRARY_PATH=/b SDL_AUDIODRIVER=pulseaudio PATH=$PATH:/usr/games
export EDEN_VR_OPENXR=1 EDEN_VR_FAKENUI=1 EDEN_VR_SKELETON=1 EDEN_VR_PERIOD=1 EDEN_VR_CONTROLLERS=1 EDEN_VR_FPS=1
export EDEN_VR_HEAD=${QUEST_HEAD:-1} EDEN_VR_SCALE=${QUEST_SCALE:-100}
for v in $QUEST_ENV; do export "$v"; done
# The sound goes to the headset through the device WiVRn creates; if it exists it is made the default output.
S=$(pactl list short sinks 2>/dev/null | awk 'tolower($2) ~ /wivrn/ {print $2; exit}')
[ -n "$S" ] && pactl set-default-sink "$S"
echo "game starting $(date); audio output: ${S:-the default one (the WiVRn one was not found)}" > /b/quest_game.log
exec gamescope --backend headless -W 1280 -H 720 -w 1280 -h 720 -- ./eden --title.game_root=/assets --gpu.driver=vulkan \
  --gpu.xenos.allow_invalid_fetch_constants=true --hid.mnk_mode=true --ui.video_mode_refresh_rate=${QUEST_HZ:-120} >> /b/quest_game.log 2>&1
