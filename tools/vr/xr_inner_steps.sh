#!/bin/bash
# Runs INSIDE gamescope (image eden-recomp:monado, launched by run_xr.sh): starts Monado (simulated headset) and then the
# regular step script tools/test/steps.sh.
# The screenshots steps.sh takes are of what gamescope shows: the window of Monado's compositor (both eyes).
# XR_REMOTE="<xr_remote.py actions>": Monado with its "remote" headset (head and controllers driven over TCP) instead of the simulated one.
if [ -n "$XR_REMOTE" ]; then
  export XDG_CONFIG_HOME=/tmp/cfg; mkdir -p /tmp/cfg/monado
  echo '{"active": "remote", "remote": {"version": 0, "port": 4242, "view_count": 2}}' > /tmp/cfg/monado/config_v0.json
fi
(tail -f /dev/null | env $MONADO_ENV monado-service > /b/monado$1.log 2>&1) &
sleep 4
[ -n "$XR_REMOTE" ] && (python3 -I /s/vr/xr_remote.py $XR_REMOTE > /b/remote$1.log 2>&1 &)
bash /s/test/steps.sh "$@"
pkill monado-service; sleep 1; pkill tail
