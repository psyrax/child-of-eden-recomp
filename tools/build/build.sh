#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman). Builds the eden project (rexglue output, work/project)
# against rexglue-sdk (work/rexglue-sdk) inside the build container. Output: work/build. Limits: 7 GB / 6 CPUs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
ENGINE="${ENGINE:-docker}"
mkdir -p "$WORK/build"
$ENGINE run --rm --user $(id -u):$(id -g) -e HOME=/tmp -m 7g --cpus 6 -v "$WORK/rexglue-sdk:/sdk" -v "$WORK/project:/w/project" -v "$WORK/game:/w/game:ro" -v "$WORK/game:/assets:ro" -v "$WORK/build:/out" -v "$ROOT/tools/build/sort_eh_frame_hdr.py:/s/sort_eh_frame_hdr.py:ro" -w /w/project eden-recomp:build bash -c '
cmake -S /w/project -B /out -G Ninja -DCMAKE_BUILD_TYPE=Release -DREXSDK_DIR=/sdk -DREXGLUE_BUILD_TESTS=OFF -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_ENABLE_PERF_COUNTERS=ON &&
cmake --build /out -j4 -- -k 0 &&
# LLD 21 leaves the .eh_frame_hdr table unsorted with -mcmodel=large: without this every throw ends in std::terminate.
python3 -I /s/sort_eh_frame_hdr.py /out/eden /out/*.so'
