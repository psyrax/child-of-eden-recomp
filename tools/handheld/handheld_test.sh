#!/bin/bash
# Runs on any machine with ssh access to the handheld: launches the game on the handheld inside the Steam session,
# with a COPY of the save (<HANDHELD_DIR>/test-user), lets it run N seconds while measuring, closes it and summarizes
# the frames per minute.
# Usage: handheld_test.sh <tag> <seconds> [extra game options...]   (EDEN_* variables are passed with ENVX="A=1 B=2")
#   HANDHELD=user@host    ssh target of the handheld (required)
#   STEAM_GAMEID=<id>     id of the game's non-Steam shortcut in your Steam library (required; it is the number in
#                         steam://rungameid/<id>, different on every install)
#   HANDHELD_DIR          where the game lives on the handheld (default ~/Apps/child-of-eden)
# KEYS="33:enter 40:l 43:d 49:space bot:73-300" drives the game with a virtual keyboard (needs --hid.mnk_mode=true and
#   passwordless sudo on the handheld for uinput).
# LIMIT=<n> sets gamescope's frame limit at 25 s (0 = no limit); Steam restores it when another game is opened.
# HZ=<n> asks gamescope for that display refresh rate at 25 s (removed when the test ends).
# It does not touch user/ (the save). If the game is already open, it does nothing.
# NOTE: assumes the Steam session of uid 1000 on display :0 (XDG_RUNTIME_DIR=/run/user/1000), an AMD GPU (sysfs
# gpu_busy_percent / pp_dpm_sclk) and battery BAT0, as on the ROG Ally this was written for.
set -u
HANDHELD=${HANDHELD:-}; GAMEID=${STEAM_GAMEID:-}
[ -n "$HANDHELD" ] || { echo "ERROR: set HANDHELD=user@host (the ssh target of the handheld)." >&2; exit 2; }
[ -n "$GAMEID" ] || { echo "ERROR: set STEAM_GAMEID=<id of the game's non-Steam shortcut> (the number in steam://rungameid/<id>)." >&2; exit 2; }
[ $# -ge 2 ] || { echo "Usage: HANDHELD=user@host STEAM_GAMEID=<id> $0 <tag> <seconds> [extra game options...]" >&2; exit 2; }
TAG=$1; DUR=$2; shift 2
S="ssh -o ConnectTimeout=10 -o BatchMode=yes -o ServerAliveInterval=15"
A=${HANDHELD_DIR:-}; [ -n "$A" ] || A='~/Apps/child-of-eden'
scp -q -o BatchMode=yes "$(dirname "$0")/uinput_keys.py" $HANDHELD:/tmp/uinput_keys.py || { echo "ERROR: could not copy uinput_keys.py to the handheld" >&2; exit 1; }
$S $HANDHELD "pgrep -x eden >/dev/null" && { echo "ERROR: the game is already open on the handheld; close it and try again." >&2; exit 1; }
$S $HANDHELD "bash -c 'cd $A && [ -d test-user ] || { echo \"ERROR: test-user is missing (cp -a user test-user)\" >&2; exit 2; }
  { for v in ${ENVX:-}; do echo \"export \$v\"; done; echo \"EDEN_ARGS=\\\"--app.user_root=\$PWD/test-user $*\\\"\"; } > test.env
  /bin/ls -t logs/eden_*.log | head -1 > /tmp/test_before.txt
  DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 setsid steam steam://rungameid/$GAMEID >/dev/null 2>&1 < /dev/null &
  for i in \$(seq 1 30); do pgrep -x eden >/dev/null && break; sleep 1; done; pgrep -x eden >/dev/null || { rm -f test.env; echo \"ERROR: the game did not start within 30 s\" >&2; exit 3; }
  D=\$(ls -d /sys/class/drm/card*/device | head -1); P=\$(pgrep -x eden)
  [ -n \"${KEYS:-}\" ] && { sudo -n python3 /tmp/uinput_keys.py ${KEYS:-} > /tmp/test_keys.txt 2>&1 & }
  [ -n \"${LIMIT:-}\" ] && { ( sleep 25; DISPLAY=:0 xprop -root -f GAMESCOPE_FPS_LIMIT 32c -set GAMESCOPE_FPS_LIMIT ${LIMIT:-0} ) & }
  [ -n \"${HZ:-}\" ] && { ( sleep 25; DISPLAY=:0 xprop -root -f GAMESCOPE_DYNAMIC_REFRESH 32c -set GAMESCOPE_DYNAMIC_REFRESH ${HZ:-0} ) & }
  for i in \$(seq 1 $DUR); do kill -0 \$P 2>/dev/null || break
    echo \"\$(date +%H:%M:%S) busy=\$(cat \$D/gpu_busy_percent) sclk=\$(grep \"\\*\" \$D/pp_dpm_sclk | cut -d\" \" -f2) bat=\$(awk \"{printf \\\"%.1f\\\", \\\$1/1e6}\" /sys/class/power_supply/BAT0/power_now) \$(cat /sys/class/power_supply/BAT0/status) limit=\$(DISPLAY=:0 xprop -root GAMESCOPE_FPS_LIMIT | cut -d= -f2) hz=\$(DISPLAY=:0 xprop -root GAMESCOPE_DISPLAY_REFRESH_RATE_FEEDBACK | cut -d= -f2) cpu=\$(ps -o %cpu= -p \$P | tr -d \" \")\"
    sleep 1; done > /tmp/test_$TAG.txt
  sudo -n pkill -x -f \"python3 /tmp/uinput_keys.py .*\" 2>/dev/null  # -x: full pattern, so this very ssh is not killed
  kill \$P 2>/dev/null; for i in 1 2 3 4 5 6; do kill -0 \$P 2>/dev/null || break; sleep 1; done; kill -9 \$P 2>/dev/null
  rm -f test.env
  [ -n \"${HZ:-}\" ] && DISPLAY=:0 xprop -root -remove GAMESCOPE_DYNAMIC_REFRESH
  L=\$(/bin/ls -t logs/eden_*.log | head -1); [ \"\$L\" = \"\$(cat /tmp/test_before.txt)\" ] && echo \"WARNING: there is no new log\"
  echo \"== \$L\"; grep -c user_root=.*test-user /dev/null >/dev/null; grep \"last minute\" \$L | sed -E \"s/^.{11}(.{8}).*last minute: /\\1 /\"
  grep \"stutter of\" \$L | sed -E \"s/^.*stutter of ([0-9]+) ms.*/\\1/\" | awk \"{b=int(\\\$1/8)*8; h[b]++} END{for(k in h) printf \\\"%d-%dms:%d \\\", k,k+7,h[k]; print \\\"\\\"}\"
  awk \"NR%15==1\" /tmp/test_$TAG.txt | cut -c1-110
  echo \"player save: \$(find user -type f | sort | xargs sha256sum | sha256sum | cut -c1-16)\"'"
