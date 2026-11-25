# Experiment (originally run on an ARM Mac with Apple `container`, Linux arm64): eden-recomp:exp-xenonrecomp + g++ 14 and
# the development packages rexglue-sdk needs, to build only the `rexglue` codegen tool and DXC.
# Debian trixie ships clang 19 and the SDK asks for clang >= 20: building the tool in this image needs the two local SDK
# adjustments listed in VERSIONS.md. On x86_64 use eden-recomp:build (clang 21) instead.
# Build (from the repo root): docker build -t eden-recomp:exp-rexglue-tool -f containers/experiments/rexglue-tool.Containerfile containers/experiments
FROM eden-recomp:exp-xenonrecomp
RUN apt-get update && apt-get install -y --no-install-recommends g++ libstdc++-14-dev libvulkan-dev libvulkan-memory-allocator-dev glslang-tools libasound2-dev libpulse-dev libgtk-3-dev libx11-xcb-dev libxss-dev libwayland-dev libwayland-bin wayland-protocols libxkbcommon-dev libdecor-0-dev libpipewire-0.3-dev pkg-config python3-minimal xz-utils && rm -rf /var/lib/apt/lists/*
