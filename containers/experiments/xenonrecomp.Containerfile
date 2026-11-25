# Experiment (originally run on an ARM Mac with Apple `container`, Linux arm64): build environment for XenonRecomp
# (clang/cmake/ninja). Nothing is installed on the host.
# Build (from the repo root): docker build -t eden-recomp:exp-xenonrecomp -f containers/experiments/xenonrecomp.Containerfile containers/experiments
FROM docker.io/library/debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      clang lld cmake ninja-build git ca-certificates python3 make pkg-config \
    && rm -rf /var/lib/apt/lists/*
ENV CC=clang CXX=clang++
WORKDIR /work
