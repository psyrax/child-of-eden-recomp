#!/bin/bash
# Run on the build machine alongside a test run (needs gdb and passwordless sudo). When the log shows a whole minute
# below <threshold> fps, takes <n> snapshots of the stacks of ALL the game's threads with gdb ("poor man's profiler":
# it tells what each thread is WAITING on, which perf does not see) and notes GPU load and CPU per thread. Only once.
# Usage: slow_stack.sh <run.log> <output.txt> <timeout_seconds> [threshold=40] [n=20]
L=$1; S=$2; END=$((SECONDS+$3)); U=${4:-40}; N=${5:-20}
while [ $SECONDS -lt $END ]; do
  sleep 5
  F=$(grep "diag: last minute" "$L" 2>/dev/null | tail -1 | sed -n 's/.*minute: \([0-9]*\)\..*/\1/p')
  [ -n "$F" ] && [ "$F" -lt "$U" ] || continue
  PID=$(pgrep -x eden | head -1); [ -n "$PID" ] || break
  echo "slow minute ($F fps) detected $(date +%H:%M:%S)" > "$S"
  for i in $(seq 1 "$N"); do
    echo "=== snapshot $i $(date +%H:%M:%S.%N | cut -c1-12) gpu=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | tr '\n' ' ')" >> "$S"
    sudo -n timeout 60 gdb -p "$PID" -batch -ex "set pagination off" -ex "thread apply all bt 14" 2>/dev/null \
      | grep -E "^Thread|^#" | cut -c1-200 >> "$S"
    sleep 1
  done
  echo "=== cpu per thread" >> "$S"
  top -H -b -n 2 -d 3 -p "$PID" | awk '/^top/{n++} n==2' | sed -n '8,22p' | awk '{print $9, $12, $13, $14}' >> "$S"
  exit 0
done
echo "no slow minute in $3 s" > "$S"
