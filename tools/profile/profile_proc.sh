#!/bin/bash
# Run on the build machine alongside a test run (needs perf and passwordless sudo). Flat profile (perf) of ALL the
# game's threads at a given moment.
# Usage: profile_proc.sh <output.txt> <sec_since_launch> [duration=30]
S=$1; D=${3:-30}
while [ $SECONDS -lt $2 ]; do sleep 1; done
PID=$(pgrep -x eden | head -1); [ -n "$PID" ] || { echo "no eden process at $2 s" > "$S"; exit 1; }
sudo -n perf record -q -F 499 -p $PID -o /tmp/perfp.$$.data -- sleep $D 2>/dev/null
{ echo "== per thread"; sudo -n perf report -i /tmp/perfp.$$.data --stdio --no-children --sort comm 2>/dev/null | grep -v "^#" | grep -v "^$" | head -25
  echo "== per thread and symbol"; sudo -n perf report -i /tmp/perfp.$$.data --stdio --no-children --sort comm,dso,symbol 2>/dev/null | grep -v "^#" | grep -v "^$" | head -70; } > "$S"
sudo -n rm -f /tmp/perfp.$$.data
