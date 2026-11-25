#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman and a Vulkan GPU): pw_test.sh <tag> <pipewiresrc ...>
#   -> work/build/pw_<tag>.{log,mkv}
# Short test (15 s) of gamescope's PipeWire capture with vkcube instead of the game. Separate container, 2 CPUs.
# STACK=1 also dumps the gamescope thread states and stacks with gdb. Image ${IMG:-eden-recomp:capture}.
# NOTE: --group-add 44 / 990 are the `video` / `render` GIDs of the development machine (see run.sh).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; WORK="${EDEN_WORK:-$ROOT/work}"; ENGINE="${ENGINE:-docker}"
mkdir -p "$WORK/build" "$WORK/shots" || exit 2
TAG=$1; shift
$ENGINE run --rm --shm-size=1g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) -m 3g --cpus 2 --cap-add SYS_PTRACE -e STACK="${STACK:-}" \
 -e XDG_RUNTIME_DIR=/tmp/xdg -e HOME=/tmp -e GST_DEBUG="${GST_DEBUG:-}" -e DUR="${DUR:-}" -e PIPEWIRE_DEBUG="${PIPEWIRE_DEBUG:-}" -v "$WORK/build:/b" -v "$WORK/shots:/c" -v "$ROOT/tools:/s:ro" -w /b ${IMG:-eden-recomp:capture} \
 bash -c "mkdir -m 700 /tmp/xdg; export PATH=\$PATH:/usr/games
   dbus-run-session -- bash -c \"
     PIPEWIRE_DEBUG=${PWD_DEBUG:-2} pipewire > /b/pw_${TAG}_daemon.log 2>&1 & sleep 1; wireplumber > /tmp/wireplumber.log 2>&1 & sleep 2
     timeout 40 gamescope --backend headless -W 1280 -H 720 -w 1280 -h 720 ${GS_EXTRA:-} -- bash /s/test/pw_test_inner.sh $TAG $* > /b/pw_${TAG}_gs.log 2>&1\""
ls -la "$WORK/build/pw_$TAG.mkv" 2>&1; cut -c1-300 "$WORK/build/pw_$TAG.log" | grep -v -E "^\s*$" | tail -60
