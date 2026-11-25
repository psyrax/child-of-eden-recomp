# Build image: Ubuntu 26.04 with clang 21 / lld 21, cmake, ninja and the development packages rexglue-sdk needs, plus
# Xvfb, Mesa Vulkan drivers and gdb for quick tests. Every other image derives from this one.
# Build (from the repo root): docker build -t eden-recomp:build -f containers/build.Dockerfile .
FROM ubuntu:26.04
RUN apt-get update && apt-get install -y --no-install-recommends clang-21 lld-21 llvm-21 cmake ninja-build git python3-minimal pkg-config xz-utils ca-certificates libc++-21-dev libc++abi-21-dev libvulkan-dev libvulkan-memory-allocator-dev glslang-tools libasound2-dev libpulse-dev libgtk-3-dev libx11-xcb-dev libxss-dev libwayland-dev libwayland-bin wayland-protocols libxkbcommon-dev libdecor-0-dev libpipewire-0.3-dev && rm -rf /var/lib/apt/lists/* && ln -sf /usr/bin/clang-21 /usr/local/bin/clang && ln -sf /usr/bin/clang++-21 /usr/local/bin/clang++
ENV CC=clang CXX=clang++
RUN ln -sf /usr/bin/ld.lld-21 /usr/local/bin/ld.lld
RUN apt-get update && apt-get install -y --no-install-recommends xvfb xauth mesa-vulkan-drivers libvulkan1 && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y --no-install-recommends gdb && rm -rf /var/lib/apt/lists/*
