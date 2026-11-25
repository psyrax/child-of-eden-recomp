#!/bin/bash
# Builds only the `rexglue` tool (codegen) of rexglue-sdk v0.11.0 in a container. Limits: 6 GB / 4 CPUs.
# Sources: work/rexglue-sdk. Build tree: work/rexglue-tool. The SDK's CMake puts the binary and its libraries in
# work/rexglue-sdk/out/linux-<arch>/, which is where tools/build/codegen.sh looks for it.
# IMG=<image> picks the image (default eden-recomp:build, clang 21). ENGINE=container uses Apple `container`.
# Perf counters stay ON: with them OFF the tool fails to link on x86_64 (undefined rex::platform::RegisterCounter).
# History: the tool was first built on an ARM Mac with Apple `container` and the image eden-recomp:exp-rexglue-tool
# (Debian, clang 19, which needs the two local SDK adjustments listed in VERSIONS.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
ENGINE="${ENGINE:-docker}"
# Apple `container` and Docker/Podman spell the CPU limit differently, and only Docker/Podman need the user mapping.
if [ "$ENGINE" = container ]; then LIMITS="-m 6G -c 4"; else LIMITS="-m 6g --cpus 4 --user $(id -u):$(id -g) -e HOME=/tmp"; fi
[ -f "$WORK/rexglue-sdk/CMakeLists.txt" ] || { echo "ERROR: $WORK/rexglue-sdk is missing. Fetch and patch it with: tools/build/setup_sdk.sh" >&2; exit 1; }
mkdir -p "$WORK/rexglue-tool"
$ENGINE run --rm $LIMITS --name eden-rex -v "$WORK/rexglue-sdk:/src" -v "$WORK/rexglue-tool:/out" ${IMG:-eden-recomp:build} bash -c '
cmake -S /src -B /out -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DREXGLUE_BUILD_TESTS=OFF -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_ENABLE_PERF_COUNTERS=ON && cmake --build /out --target rexglue -j3'
