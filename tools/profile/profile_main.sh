#!/bin/bash
# Run on the build machine alongside a test run (needs perf and passwordless sudo). Flat profile (perf) of the game's
# main thread at two moments.
# Usage: profile_main.sh <output_prefix> <sec1> <sec2> [duration]   (seconds since this script was launched)
P=$1; D=${4:-25}
for T in $2 $3; do
  while [ $SECONDS -lt $T ]; do sleep 1; done
  PID=$(pgrep -x eden | head -1); [ -n "$PID" ] || { echo "no eden process at $T s" > $P.$T.txt; continue; }
  TID=$(grep -l "^Main XT" /proc/$PID/task/*/comm | head -1 | cut -d/ -f5)
  sudo -n perf record -q -F 999 -t $TID -o /tmp/perf.$T.data -- sleep $D 2>/dev/null
  sudo -n perf report -i /tmp/perf.$T.data --stdio --no-children --sort dso,symbol 2>/dev/null | grep -v "^#" | grep -v "^$" | head -45 > $P.$T.txt
  sudo -n rm -f /tmp/perf.$T.data
done
