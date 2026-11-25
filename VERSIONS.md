# Pinned versions (verified 2026-11-19)

| Repo | URL | Commit | License | Last push | Built |
|---|---|---|---|---|---|
| XenonRecomp | https://github.com/hedge-dev/XenonRecomp | ddd128bcca99fe8bfbb99bea583c972351fa6ace | MIT | 2025-08-04 | YES (XenonRecomp + XenonAnalyse, linux-arm64, clang) |
| XenosRecomp | https://github.com/hedge-dev/XenosRecomp | 70a084c2392378818a4da4086e8e3420b4c3ea8d | MIT | 2026-11-14 | NO: stopped, it requires dxc-bin (prebuilt binaries) |
| rexglue-sdk (runtime+toolkit) | https://github.com/rexglue/rexglue-sdk | tag v0.11.0 = a3e1d82678ca20d68d4837a8e9ee4652ff073745 | BSD-3-Clause (Tom Clay + Xenia; GitHub says "Other") | 2026-11-17 | YES, only the `rexglue` tool (linux-arm64, clang 19 + 2 local adjustments, see below) |
| DirectXShaderCompiler | https://github.com/microsoft/DirectXShaderCompiler | tag v1.9.2609 = 01b62ad47db7dee3dd33f90e7339cf9e860b3f93 | NCSA/Apache-LLVM | 2026-09-29 | YES: `libdxcompiler.so` (linux-arm64, `containers/experiments/build_dxc.sh`) |

XenonRecomp submodules: fmt 873670ba, libmspack 30590772 (v1.11), simde a532a12c, tiny-AES-c 23856752,
tomlplusplus c4369ae1, xxHash 2bf8313b (`git submodule status` in the XenonRecomp clone).
XenosRecomp submodules cloned: fmt 873670ba, smol-v 9dd54c37, xxHash 2bf8313b, zstd f7a8bb12.
NOT cloned: thirdparty/dxc-bin (12395e36, renderbag/dxc-bin = prebuilt dxc/libdxcompiler).

Reproduce: clone XenonRecomp with `--recurse-submodules`, `git checkout ddd128bc`, and run
`containers/experiments/build_xenonrecomp.sh`.
Container: `containers/experiments/xenonrecomp.Containerfile` (debian:trixie-slim + clang, lld, cmake, ninja, git,
python3), run with `-m 6G -c 4` in the original setup.

## rexglue-sdk: local adjustments (2026-11-19, in the local SDK clone, outside git)
The SDK requires clang >= 20; the container (Debian trixie) ships 19.1.7. To be able to measure, TWO local changes
were made that must NOT go into the real build (use clang >= 20 without patches):
1. `CMakeLists.txt`: `VERSION_LESS "20.0"` -> `"19.0"` (version check).
2. `src/kernel/xboxkrnl/xboxkrnl_crypt.cpp` lines 830 and 837: `std::size(title.words)` ->
   `std::extent_v<decltype(AESSchedule::words)>` (a constexpr that clang 19 rejects).
rexglue submodules (clone with `--depth 1 --recurse-submodules`): `git submodule status` in the rexglue-sdk clone.
DXC submodules: DirectX-Headers 980971e, SPIRV-Headers 4965431, SPIRV-Tools ef96ed7.

## Container images (ARM Mac experiments)
- `containers/experiments/xenonrecomp.Containerfile`: debian:trixie-slim + clang 19, lld, cmake, ninja, git, python3.
- `containers/experiments/rexglue-tool.Containerfile`: the previous one + g++ 14, libvulkan-dev, VMA, glslang-tools,
  gtk3, wayland, x11-xcb, pipewire, alsa, pulse (rexglue dependencies). All run with `-m 6G -c 4` in the original
  setup.

## VR fork, stage 3 (2026-11-20): OpenXR
- **Monado** (open-source OpenXR runtime): Ubuntu 26.04 package `monado-service` / `libopenxr1-monado`
  `25.0.0+dfsg-2build1`, installed with apt inside the image `eden-recomp:monado` (`containers/monado.Dockerfile`).
  Official source cloned for reading only: `https://gitlab.freedesktop.org/monado/monado.git`, tag `v25.0.0`,
  commit `a041c61`.
- **OpenXR SDK** (headers, loader, `hello_xr`): Ubuntu packages `libopenxr-dev`, `libopenxr-loader1`,
  `libopenxr-utils` `1.1.47~ds-2build1` (images `eden-recomp:monado` to run and `eden-recomp:build-xr` to build,
  `containers/build-xr.Dockerfile`).
- The OpenXR output is part of our SDK patches in `patches/sdk/`, applied on top of rexglue-sdk v0.11.0 after the
  controller menu, gyro and audio changes.

## VR fork, stage 4 (2026-11-20): WiVRn for the Meta Quest 2
- **WiVRn** (OpenXR server on top of Monado that streams to the headset): official source
  `https://github.com/WiVRn/WiVRn.git`, tag `v26.9`, commit `bbc6e4cc36c355fa6180980abd231673dc15115d`.
  Its CMake downloads pinned sources: Monado `f037264d23e2472a444a157370647fcd601ed81b` (`monado-rev`) and, by sha256
  hash, boost 1.89.0 and others. Server and `wivrnctl` only (`tools/build/build_wivrn.sh`, image `eden-recomp:wivrn`,
  `containers/wivrn.Dockerfile`: Ubuntu 26.04 packages). Built with gcc 15.2 (the image's clang does not work
  without the SDK's options). The headset client is the WiVRn 26.9 app from the Meta Store; it was not built.
- The stage 4 changes to rexglue-sdk are also part of the SDK patches in `patches/sdk/`.

## Image `eden-recomp:capture-gamescope` (2026-11-22): gamescope patched to capture through PipeWire
- **gamescope 3.16.20+ds-1**, Ubuntu 26.04 source package (`apt-get source gamescope=3.16.20+ds-1`), `orig.tar.xz`
  sha256 `a27984fdab2bbfe353efc772de214ae88cccab07c4507747ed4b7f063b2faa0e`, rebuilt with
  `patches/gamescope/gamescope-pipewire-enter.patch` (adds `pw_loop_enter`/`pw_loop_leave`). Reason: with
  PipeWire 1.6.2 the `gamescope-pw` thread blocks and the capture never delivers frames. Built with gcc (the image's
  clang does not link). Defined in `containers/capture-gamescope.Dockerfile`. Only for running and recording; the game
  is still built with the regular build image (`eden-recomp:build`).
