#!/bin/bash
# Runs ON THE HANDHELD while the game is open: profile of a stretch of play. Usage: handheld_profile.sh <wait_s> <samples>
# Each sample (~3 s): power state, active GPU clocks, core frequency and the busiest threads.
# NOTE: reads AMD GPU sysfs files (pp_dpm_*, gpu_busy_percent) and battery BAT0, as on the ROG Ally this was written for.
sleep $1; P=$(pgrep -x eden); D=$(ls -d /sys/class/drm/card*/device | head -1)
echo "power=$(cat /sys/class/power_supply/BAT0/status) dpm_state=$(cat $D/power_dpm_state 2>/dev/null) ac_online=$(cat /sys/class/power_supply/A*/online 2>/dev/null | tr '\n' ' ')"
for f in pp_dpm_sclk pp_dpm_mclk pp_dpm_fclk pp_dpm_socclk; do echo "$f: $(tr '\n' ' ' < $D/$f 2>/dev/null)"; done
for i in $(seq 1 $2); do
  echo "-- $(date +%H:%M:%S) busy=$(cat $D/gpu_busy_percent) sclk=$(grep '\*' $D/pp_dpm_sclk | cut -d' ' -f2) mclk=$(grep '\*' $D/pp_dpm_mclk | cut -d' ' -f2) fclk=$(grep '\*' $D/pp_dpm_fclk | cut -d' ' -f2) gpuW=$(($(cat $D/hwmon/hwmon*/power1_input)/1000000)) cpuMHz_max=$(sort -n /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | tail -1 | cut -c1-4)"
  top -H -b -n 2 -d 3 -p $P | awk '/^top/{n++} n==2' | sed -n '8,12p' | awk '{printf "%s %s %s; ", $9, $12, $13}'; echo
done
