#!/bin/bash
# Run on the build machine alongside a test run. Mean power of the discrete GPU (hwmon power1_average, µW) over a window.
# Usage: power_gpu.sh <output.txt> <sec_since_launch> [duration=60]
# NOTE: the original read card1, the discrete GPU of the development machine; pick yours with GPU_CARD=cardN.
S=$1; D=${3:-60}; CARD=${GPU_CARD:-card1}; F=$(ls /sys/class/drm/$CARD/device/hwmon/hwmon*/power1_average 2>/dev/null | head -1)
[ -r "$F" ] || { echo "ERROR: power1_average of $CARD not found (set GPU_CARD=cardN)" > "$S"; exit 1; }
while [ $SECONDS -lt $2 ]; do sleep 1; done
n=0; t=0; end=$((SECONDS+D)); while [ $SECONDS -lt $end ]; do t=$((t+$(cat $F))); n=$((n+1)); sleep 0.5; done
echo "$(echo "scale=1; $t/$n/1000000" | bc) W mean GPU power in $D s ($n samples)" > "$S"
