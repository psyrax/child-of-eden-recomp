#!/bin/bash
# Run on the build machine alongside a test run: every 20 s notes the CPU per thread of the eden process and the GPU load.
# Usage: sample_threads.sh <output.txt> <total_seconds>
S=$1; END=$((SECONDS+$2)); : > "$S"
while [ $SECONDS -lt $END ]; do
  P=$(pgrep -x eden | head -1)
  if [ -n "$P" ]; then
    echo "== $(date +%H:%M:%S) gpu=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | tr "\n" " ") rss_kb=$(awk "/VmRSS/{print \$2}" /proc/$P/status)" >> "$S"
    top -H -b -n 2 -d 2 -p $P | awk "/^top/{n++} n==2" | sed -n "8,17p" | awk "{print \$9, \$12, \$13, \$14}" >> "$S"
  fi
  sleep 16
done
