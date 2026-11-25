#!/bin/bash
# Runs INSIDE the eden-recomp:wivrn container (launched by quest.sh): audio (PipeWire), configuration and the WiVRn server.
# WiVRn launches /s/vr/quest_game.sh when the headset connects.
export XDG_RUNTIME_DIR=/tmp/xdg XDG_CONFIG_HOME=/tmp/cfg
mkdir -p -m 700 /tmp/xdg
PUB='null'; [ "$QUEST_AVAHI" = 1 ] && PUB='"avahi"'
echo "{\"application\": [\"bash\", \"/s/vr/quest_game.sh\"], \"publish-service\": $PUB}" > /tmp/cfg/wivrn/config.json
exec dbus-run-session -- bash -c '
  (pipewire > /b/quest_pipewire.log 2>&1 &) ; sleep 0.5
  (wireplumber >> /b/quest_pipewire.log 2>&1 &) ; (pipewire-pulse >> /b/quest_pipewire.log 2>&1 &) ; sleep 1
  echo "wivrn-server starting $(date)" > /b/quest_wivrn.log
  exec /w/bin/wivrn-server >> /b/quest_wivrn.log 2>&1'
