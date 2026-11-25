#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman and a Vulkan GPU): Monado (simulated headset) + an
# OpenXR client inside a headless gamescope.
# Usage: xr_test.sh <N> <seconds> <client...>
#   -> work/${BDIR:-build}/monado<N>.log, work/${BDIR:-build}/xrclient<N>.log, work/shots/xr<N>_*.png
# BDIR picks the build directory under work/ mounted at /b (build or build-xr); TAIL=<n> Monado log lines shown.
# XRT_*, SIMULATED_*, OXR_* and EDEN_* variables are forwarded to the container.
# NOTE: --group-add 44 / 990 are the `video` / `render` GIDs of the development machine (see tools/test/run.sh).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
mkdir -p "$WORK/shots" && N=$1 && $ENGINE run --rm --shm-size=3g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) -m 6g --cpus 4 \
 -e XDG_RUNTIME_DIR=/tmp/xdg -e HOME=/tmp -e LD_LIBRARY_PATH=/b -e DEBUGINFOD_URLS="$DEBUGINFOD_URLS" -e MONADO_ENV="$MONADO_ENV" $(env | grep -o "^XRT_[A-Z_0-9]*=.*\|^SIMULATED_[A-Z_]*=.*\|^OXR_[A-Z_]*=.*\|^EDEN_[A-Z_0-9]*=.*" | sed "s/^/-e /") \
 -v "$WORK/${BDIR:-build}:/b" -v "$WORK/game:/assets:ro" -v "$WORK/shots:/c" -v "$ROOT/tools:/s:ro" -w /b eden-recomp:monado \
 bash -c "mkdir -m 700 /tmp/xdg; PATH=\$PATH:/usr/games gamescope --backend headless -W 1280 -H 720 -w 1280 -h 720 -- bash /s/vr/xr_inner.sh $* > /b/gamescope_xr$N.log 2>&1"
grep -v "VK_FORMAT\|^$" "$WORK/${BDIR:-build}/monado$N.log" | tail -${TAIL:-25} | cut -c1-200; echo ----; tail -12 "$WORK/${BDIR:-build}/xrclient$N.log" | cut -c1-200; ls -la "$WORK"/shots/xr${N}_*
