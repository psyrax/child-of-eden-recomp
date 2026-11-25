#!/bin/bash
# Run on the build machine alongside a test run (needs perf and passwordless sudo). Waits until the log shows a streak
# of 33 ms frames (>= 30 new "diag: stutter" lines in 5 s) and then profiles ALL the game's threads for 20 s. Only once.
# Usage: profile_stutter.sh <run.log> <output.txt> <timeout_seconds>
L=$1; S=$2; END=$((SECONDS+$3)); A=0
while [ $SECONDS -lt $END ]; do
  sleep 5; N=$(grep -c "diag: stutter" "$L" 2>/dev/null); N=${N:-0}
  if [ $((N-A)) -ge 30 ]; then
    PID=$(pgrep -x eden | head -1); [ -n "$PID" ] || break
    echo "streak detected $(date +%H:%M:%S) (stutters $A -> $N)" > "$S"
    sudo -n perf record -q -F 999 -p $PID -o /tmp/perf.t.data -- sleep 20 2>/dev/null
    sudo -n perf report -i /tmp/perf.t.data --stdio --no-children --sort comm 2>/dev/null | grep -v "^#" | grep -v "^$" | head -14 >> "$S"
    echo "--- per thread and symbol" >> "$S"
    sudo -n perf report -i /tmp/perf.t.data --stdio --no-children --sort comm,dso,symbol 2>/dev/null | grep -v "^#" | grep -v "^$" | head -60 | cut -c1-120 >> "$S"
    sudo -n rm -f /tmp/perf.t.data; exit 0
  fi
  A=$N
done
echo "no streak in $3 s" > "$S"
