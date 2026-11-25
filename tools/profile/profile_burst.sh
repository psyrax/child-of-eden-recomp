#!/bin/bash
# Run on the build machine alongside a test run with EDEN_STUTTER_DIAG (needs perf and passwordless sudo). Tells what
# ALL the game's threads were doing during a stutter: samples the process every 0.25 ms of CPU (fixed period, monotonic
# clock) over a window and, when the run ends, cuts out the samples of each long frame using the "mono=" the game
# wrote to the log.
# Usage: profile_burst.sh <run.log> <output.txt> <start_sec> <duration>
L=$1; S=$2
while [ $SECONDS -lt $3 ]; do sleep 1; done
PID=$(pgrep -x eden | head -1); [ -n "$PID" ] || { echo "no eden process" > "$S"; exit 1; }
sudo -n perf record -q -k CLOCK_MONOTONIC -e cpu-clock -c 250000 -p $PID -o /tmp/perfr.$$.data -- sleep $4 2>/dev/null
while pgrep -x eden > /dev/null; do sleep 2; done
sudo -n perf script -i /tmp/perfr.$$.data -F comm,tid,time,sym 2>/dev/null > /tmp/perfr.$$.txt
echo "total samples: $(wc -l < /tmp/perfr.$$.txt); window $(head -1 /tmp/perfr.$$.txt | grep -o '[0-9]*\.[0-9]*:') .. $(tail -1 /tmp/perfr.$$.txt | grep -o '[0-9]*\.[0-9]*:')" > "$S"
grep -a "\[eden\] stutter" "$L" | grep -a -o "mono=[0-9.]*.*" | while read -r line; do
  M=${line%%)*}; M=${M#mono=}; D=$(echo "$line" | grep -o ": [0-9.]* ms" | grep -o "[0-9.]*")
  echo "== $line" >> "$S"
  awk -v m=$M -v d=$D '
    { t=-1; for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) { t=$i+0; c=$1; for(j=2;j<i-1;j++) c=c "_" $j; s=$(i+1); break }
      if (t >= m-d/1000 && t <= m) { h[c]++; hs[c " " s]++ } }
    END { for (k in h) printf "A %6.1f ms on CPU  %s\n", h[k]*0.25, k; for (k in hs) if (hs[k] >= 8) printf "B %6.1f ms  %s\n", hs[k]*0.25, k }' /tmp/perfr.$$.txt | sort -k1,1 -k2,2rn | head -40 >> "$S"
done
sudo -n rm -f /tmp/perfr.$$.data; rm -f /tmp/perfr.$$.txt
