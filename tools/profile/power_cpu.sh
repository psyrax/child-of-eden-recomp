#!/bin/bash
# Run on the build machine alongside a test run (needs perf and passwordless sudo). Package energy (CPU + integrated
# GPU, RAPL) over a window.
# Usage: power_cpu.sh <output.txt> <sec_since_launch> [duration=60]   -> joules and mean watts of the WHOLE machine
S=$1; D=${3:-60}
while [ $SECONDS -lt $2 ]; do sleep 1; done
sudo -n perf stat -a -x, -e power/energy-pkg/ -o /tmp/power.$$.csv -- sleep $D 2>/dev/null
J=$(grep energy-pkg /tmp/power.$$.csv | cut -d, -f1); sudo -n rm -f /tmp/power.$$.csv
echo "$J J in $D s = $(echo "scale=2; $J/$D" | bc) W (whole package)" > "$S"
