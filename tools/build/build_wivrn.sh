#!/bin/bash
# Run on the build machine (Linux x86_64 with Docker or Podman). Builds the WiVRn server (no client, no dashboard) from
# a WiVRn source checkout in work/src/wivrn, in the eden-recomp:wivrn image.
# Output: work/build-wivrn (build tree) and an install in work/wivrn (prefix /w inside the container).
# The build downloads SOURCES pinned by hash (Monado at the revision in monado-rev, boost, etc.); no prebuilt binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
ENGINE="${ENGINE:-docker}"
[ -d "$WORK/src/wivrn" ] || { echo "ERROR: $WORK/src/wivrn is missing. Clone the WiVRn sources there (tag v26.9, see VERSIONS.md)." >&2; exit 1; }
mkdir -p "$WORK/build-wivrn" "$WORK/wivrn"
$ENGINE run --rm --user $(id -u):$(id -g) -e HOME=/tmp -m 7g --cpus ${CPUS:-6} -v "$WORK/src/wivrn:/src" -v "$WORK/build-wivrn:/out" -v "$WORK/wivrn:/w" -w /src eden-recomp:wivrn bash -c '
git config --global --add safe.directory "*" &&
rm -rf /out/CMakeCache.txt /out/CMakeFiles && cmake -S /src -B /out -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -DCMAKE_INSTALL_PREFIX=/w \
  -DWIVRN_BUILD_CLIENT=OFF -DWIVRN_BUILD_SERVER=ON -DWIVRN_BUILD_DASHBOARD=OFF -DWIVRN_BUILD_WIVRNCTL=ON \
  -DWIVRN_USE_NVENC=OFF -DWIVRN_USE_VAAPI=ON -DWIVRN_USE_VULKAN_ENCODE=ON -DWIVRN_USE_X264=ON -DWIVRN_USE_PIPEWIRE=ON \
  -DWIVRN_USE_SYSTEMD=OFF -DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=OFF -DWIVRN_FEATURE_SOLARXR=OFF \
  -DWIVRN_OPENXR_MANIFEST_TYPE=absolute -DGIT_TAG=v26.9 &&
cmake --build /out -j${CPUS:-6} && cmake --install /out'
ls -la "$WORK/wivrn/bin"
