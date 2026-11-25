#!/bin/bash
# Runs INSIDE gamescope (image eden-recomp:monado, launched by xr_test.sh). Usage: xr_inner.sh <N> <seconds> <OpenXR client command...>
N=$1; T=$2; shift 2
(tail -f /dev/null | env $MONADO_ENV monado-service > /b/monado$N.log 2>&1) &
sleep 4
(tail -f /dev/null | "$@" > /b/xrclient$N.log 2>&1) &
sleep $T; gamescopectl screenshot /c/xr${N}_a.png; sleep 3; gamescopectl screenshot /c/xr${N}_b.png; sleep 1
pkill -f hello_xr; pkill eden; pkill monado-service; sleep 1; pkill tail
