#!/bin/bash
# Experiment (originally run on an ARM Mac with Apple `container`). Idempotent: builds the image if it is missing and
# compiles XenonRecomp inside the container. Limits: 6 GB / 4 CPUs. Usage: build_xenonrecomp.sh [--dry-run]
# Sources: a XenonRecomp checkout with submodules in work/src/XenonRecomp (commit in VERSIONS.md). Output: work/build-xenonrecomp.
# ENGINE=container uses Apple `container` as the original did; the default is docker.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
ENGINE="${ENGINE:-docker}"
IMG=eden-recomp:exp-xenonrecomp
DRY=
[ "${1:-}" = "--dry-run" ] && DRY=echo
# Apple `container` and Docker/Podman spell the CPU limit differently, and only Docker/Podman need the user mapping.
if [ "$ENGINE" = container ]; then LIMITS="-m 6G -c 4"; BUILD_LIMITS="-m 6G -c 4"; else LIMITS="-m 6g --cpus 4 --user $(id -u):$(id -g) -e HOME=/tmp"; BUILD_LIMITS=""; fi
[ -d "$WORK/src/XenonRecomp/thirdparty/fmt" ] || { echo "Missing: clone XenonRecomp with submodules into $WORK/src/XenonRecomp (see VERSIONS.md)"; exit 1; }
if [ "$ENGINE" = container ]; then container system status >/dev/null || { echo "Start the service: container system start"; exit 1; }; fi
if ! $ENGINE image inspect "$IMG" >/dev/null 2>&1; then
  $DRY $ENGINE build $BUILD_LIMITS -t "$IMG" -f "$ROOT/containers/experiments/xenonrecomp.Containerfile" "$ROOT/containers/experiments"
fi
mkdir -p "$WORK/build-xenonrecomp"
$DRY $ENGINE run --rm $LIMITS --name eden-build \
  -v "$WORK/src/XenonRecomp:/src:ro" -v "$WORK/build-xenonrecomp:/out" "$IMG" \
  bash -c 'cmake -S /src -B /out -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build /out -j4'
