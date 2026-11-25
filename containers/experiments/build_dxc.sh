#!/bin/bash
# Experiment (originally run on an ARM Mac with Apple `container`): builds libdxcompiler (DXC v1.9.2609) from source in a
# container. Limits: 6 GB / 4 CPUs. Only -j3 so it does not run out of RAM.
# Sources: a DirectXShaderCompiler checkout with submodules in work/src/DirectXShaderCompiler. Output: work/build-dxc.
# IMG=<image> picks the image (default eden-recomp:exp-rexglue-tool). ENGINE=container uses Apple `container`.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${EDEN_WORK:-$ROOT/work}"
ENGINE="${ENGINE:-docker}"
# Apple `container` and Docker/Podman spell the CPU limit differently, and only Docker/Podman need the user mapping.
if [ "$ENGINE" = container ]; then LIMITS="-m 6G -c 4"; else LIMITS="-m 6g --cpus 4 --user $(id -u):$(id -g) -e HOME=/tmp"; fi
[ -f "$WORK/src/DirectXShaderCompiler/CMakeLists.txt" ] || { echo "ERROR: $WORK/src/DirectXShaderCompiler is missing. Clone DirectXShaderCompiler v1.9.2609 there with submodules (see VERSIONS.md)." >&2; exit 1; }
mkdir -p "$WORK/build-dxc"
$ENGINE run --rm $LIMITS --name eden-dxc -v "$WORK/src/DirectXShaderCompiler:/src" -v "$WORK/build-dxc:/out" ${IMG:-eden-recomp:exp-rexglue-tool} bash -c '
cmake -S /src -B /out -G Ninja -C /src/cmake/caches/PredefinedParams.cmake -DCMAKE_BUILD_TYPE=Release -DLLVM_USE_LINKER=lld -DSPIRV_BUILD_TESTS=OFF -DLLVM_INCLUDE_TESTS=OFF -DHLSL_INCLUDE_TESTS=OFF -DLLVM_PARALLEL_LINK_JOBS=1 && cmake --build /out --target dxcompiler -j3'
