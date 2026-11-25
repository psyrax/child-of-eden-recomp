# Eden-Recomp — Feasibility study (Child of Eden, Xbox 360 → Windows/Linux)

> This is the original feasibility study, dated 2026-11-19 and kept as written. `docs/ARCHITECTURE.md` reflects the
> current state of the project.

Written 2026-11-19. Everything here is **measured** except what is marked "NOT VERIFIED". You need your own legally
obtained copy of the game; this repository contains no game code or data.

## 1. Verdict

**Feasible, with a clear path that is shorter than assumed.** There is no need to write a runtime from scratch:
`rexglue-sdk` (BSD-3, v0.11.0) already ships kernel, XAM, GPU (Vulkan/D3D12), XMA, audio and input, and its code
generator translated `default.xex` **end to end without intervention** (47 s, 3 diagnostics). What remains is
**integration and tuning** work, not research: build the result, boot it, and fix whatever fails at boot (predictably
GPU, WMV video, Kinect and a handful of stubs).

What is NOT known yet (and can only be known by running it): whether the game **gets to draw a frame** and how many
translation/runtime bugs show up. That requires the runtime built on the target machine (see §7).

## 2. Corrections to the initial assumptions

| Claim | Verdict | Evidence |
|---|---|---|
| "The tools are XenonRecomp + XenosRecomp" | **Partial.** XenonRecomp exists and works, but there is something better today: `rexglue-sdk` (codegen + runtime) | §4 and §5 |
| "The only known complete port: Sonic Unleashed" | **NOT VERIFIED** (UnleashedRecomp exists and is cited in the XenonRecomp README; others were not searched for) | XenonRecomp README |
| "It runs on Unreal Engine 3" | **FALSE.** Q Entertainment's own engine: zero "Unreal"/"UE3" strings, build paths `F:\Project\Eden\AppE_FPP_Check\soft\build\source\main\...`, scripting with **Lua 5.1.2**, boost, its own formats (`.bmbin`, `.param`, `.csa`, `Database.xmplr`) | strings of `default.pe` |
| "XenosRecomp is needed for the shaders" | **Probably NOT** (see §6) | §6 |

## 3. Game inventory (measured)

- Image: zip archive of 6,265,337,434 B, sha256
  `53221c9a3cc46a04f6bda0d6e28963f5c9df248922d2e7452def6fc28e03d40b`. ISO 7,838,695,424 B, sha256
  `c93add0a32ffac02346e932b84f29ff1e8d3d467cf8972aebba1f79267f37791`. Extracted with our own XDVDFS extractor
  (`tools/extract/xdvdfs_extract.py`, runs in a container) → `work/game/` (2.3 GB, outside git).
- `default.xex`: 20,955,136 B, sha256 `58d0eec0219d110dfdc55a9a6e071995631457654f403df312afad43daa788ed`. Title ID
  `5553084C`, version 0.0.0.3, base `0x82000000`, entry `0x82FB7B58`. Decrypted PE image of 0x1430000 B.
- Sections: `.text` 0x9EED9C (**10.4 MB, ≈2.6 M instructions**), `.rdata` 9.2 MB, `.data` 0.6 MB, `.pdata` 38 k
  entries, `.XBMOVIE`, `.XBLD`.
- Code: 156,241 `bl`, 27,398 `bctrl` (virtual/indirect calls), 743 `bctr`, 32,444 `mtctr`.
- **Engine / middleware** (no Unreal, Havok, Bink, Scaleform, FMOD or Wwise): own engine; Lua 5.1.2; **Xbox 360 D3D9
  statically linked** (with the HLSL/D3DX compiler inside: `shader.bin` is HLSL as text, 823 `//vs_3_0`/`//ps_3_0`
  lines); own audio (`sound/midi`, `sound_queue`, XMA through `XMACreateContext`); video = **ASF/WMV**
  (165 `.wmv`, 249 MB in `movie/`, ASF header `3026B275…`).
- **Kernel/XAM imports: 218 in total** (few). Notable: `Vd*` (the GPU is driven through a direct ring buffer:
  `VdInitializeRingBuffer`, `VdGetSystemCommandBuffer`, `VdSwap`), `XMA*`, `XAudio*RenderDriver*`, `Nt*File*`,
  `Xam*Content*`, and the whole **Kinect** block (`XamNui*`, `PsCamDeviceRequest`, biometrics).
- Data: 2.3 GB; `stage/` 1.3 GB, `movie/` 249 MB, `enemy/` 245 MB, `common/` 387 MB.

## 4. XenonRecomp (measured, `ddd128bc`, built in a container)

Verified that the built `XenonAnalyse` and `XenonRecomp` binaries run (aarch64 ELF in the container).

- **XenonAnalyse finds 0 jump tables** in 8 s (there are 743 `bctr`): its detector is made for the Sonic Unleashed
  pattern and **does not recognize this binary's**. The detector would have to be extended (real work).
- XenonRecomp translates in **3.7 s**: **65,843 functions**, 7.4 M lines of C++ (215 MB). **9,793 unrecognized
  instructions (0.38 %)**, concentrated in ~60 opcodes: `vslh` 2420, `stfsu` 1709, `vsrah` 1024, `vsubshs` 928,
  `vspltish` 614, `bdzf` 460, `sthu` 324, `lhzu` 279, `lfsu` 276, `vmaxsh` 265, `eqv` 154, etc. Plus 46
  `__builtin_debugtrap` (`vpkd3d128`/`vupkd3d128` incomplete).
- Syntax of the generated C++ (`clang -fsyntax-only`, 259 files): **1 error** (`loc_831042F4` undeclared, a
  `bdz` that leaves the function).
- Conclusion: it works, but leaves ~10 k instructions to implement by hand plus the table detector, and it ships no
  runtime.

## 5. rexglue-sdk (measured, v0.11.0 = commit `a3e1d826`)

- **What it is:** "Xbox 360 Recompilation Runtime and Toolkit". `rexglue codegen` (XEX → C++) + libraries that **act
  as kernel, XAM, XBDM, GPU (Vulkan/D3D12), APU/XMA (FFmpeg), HID, UI, filesystem**. CI binaries for win-amd64,
  linux-amd64/arm64, mac-amd64/arm64. Active (last push 2026-11-17, 1,304 stars). README: "early
  development, expect things to break".
- **License:** BSD-3-Clause (text in `LICENSE`, GitHub labels it "Other"). The README says it is "for education and
  research, not for porting/redistributing games"; the SDK ships no game code. This project uses it with the user's
  own copy of the game and distributes no game code or data.
- **Does it work for a game other than its own?** Yes: it is generic (`rexglue init --xex-path <any.xex>`); we did it
  with Child of Eden without touching the SDK.
- **Build from source** (no binaries): `tools/build/build_rexglue_tool.sh`
  (`containers/experiments/rexglue-tool.Containerfile`). The SDK requires **clang ≥ 20**; Debian trixie ships 19.1.7.
  It was built anyway with **two local adjustments** (noted in `VERSIONS.md`): relaxing the version check to 19.0 and
  a non-constant `std::size(title.words)` in `xboxkrnl_crypt.cpp`. For the real Windows/Linux x86 build the appropriate
  clang (≥ 20) will be used, without patches.
- **`rexglue codegen` on `default.xex`:** 47.1 s, exit 0. **46,579 functions**, 177 `.cpp` (6.2 M lines, 186 MB),
  186 `switch` (resolved jump tables), **0 `debugtrap`/unimplemented**; it implements the opcodes XenonRecomp left
  uncovered (`vslh` 2420, `stfsu` 1585, `lhzu` 319…), including complete `vupkd3d128`. It handles C++ EH/SEH and
  vtables. Diagnostics (only 3): `Unresolved b target 0x830EF968 from 0x82A07E20` and `bdz` at `0x831040C0/C4` that
  jumps out of the function to `0x831042F4`.
- Syntax of the generated C++ against the SDK headers (`clang -fsyntax-only`, 177 files): **2 errors**, both
  undeclared labels in `eden_recomp.103.cpp` (`loc_830ED3DC`, `loc_830ED3D0`; same kind of
  `bdz`-out-of-function problem). **Nothing was linked or executed** (NOT VERIFIED: that it compiles and links in
  full).
- **Import coverage:** of the 218, **179 have an implementation** in the SDK and **39 are stubs** (`REX_EXPORT_STUB`):
  Kinect/camera (`PsCamDeviceRequest`, `XamNuiCamera*`, `XamNui*`, biometrics), profile, `XamCache*`, `Etx*`
  (telemetry), `XamXlfs*`, `XeKeysGetConsoleID` and **`LDICreateDecompression/LDIDecompress/LDIDestroyDecompression`**
  (LZX decompression by the kernel). The Kinect ones should not block (the game is played with a controller); whether
  the game really uses `LDI*` has to be checked (NOT VERIFIED).
- Output architecture: the recompiled code calls the SDK's `__imp__<Export>`; accesses to hardware registers go to
  MMIO blocks (GPU → graphics system; APU → XMA decoder). It reports `codegen.mmio.json` with "guarded" MMIO accesses
  (to be reviewed).

## 6. Shaders and XenosRecomp / DXC

- **Key finding:** the game ships the **static Xbox 360 D3D9 + the HLSL compiler**, and `shader.bin` is **HLSL
  source**. It compiles shaders **at run time** and sends commands through the ring buffer. That is why the natural
  path is to **emulate the Xenos command processor** as Xenia/rexglue do (`gpu/xenos/command_processor`, microcode to
  SPIR-V translation at run time), not to recompile shaders ahead of time.
- **XenosRecomp** converts already compiled microcode to HLSL ahead of time; here the shaders generated at run time
  would have to be *captured*, and its advantage (performance) does not justify the work now. **Not needed to start.**
- **DXC from source?** XenosRecomp links `Microsoft::DirectXShaderCompiler` from the `dxc-bin` submodule
  (binaries from `renderbag/dxc-bin`, NOT downloaded). A source-only alternative **does exist**:
  `microsoft/DirectXShaderCompiler` v1.9.2609 (`01b62ad4`, submodules DirectX-Headers `980971e`, SPIRV-Headers
  `4965431`, SPIRV-Tools `ef96ed7`; NCSA/Apache-LLVM license). Result of the attempt to build it in a container: **it
  built completely** (`containers/experiments/build_dxc.sh`, 971/971 steps, 0 failures, `libdxcompiler.so`,
  linux-arm64). That is: the source-only route for XenosRecomp exists and works; what is missing is pointing
  XenosRecomp's CMake at that library (NOT done, because XenosRecomp is not on the critical path).

## 7. Runtime plan (if the project continues)

1. **Build the complete `eden` project** (`rexglue init` already done, in what is now `work/project/`): fix the 2 `bdz`
   labels (probably `[[midasm]]`/hook or a manual function in the manifest) and the `Unresolved b`. Use clang ≥ 20 (in
   a Debian container: the LLVM repository = third-party binaries → a decision left open at the time; alternative:
   build clang 20 from source, or build directly on Windows with VS 2026 + Clang).
2. **Headless boot on Linux** (container, no GPU): see how far the main thread gets, which imports hit stubs, what
   hangs. Without the handheld, visual validation waits for the target machine.
3. **GPU:** get the ring buffer/`VdSwap` to produce frames (the SDK's Vulkan driver on Linux, D3D12/Vulkan on Windows).
4. **Video:** a player for the `.wmv` files (ASF/WMV9). NOT VERIFIED whether the game decodes WMV with its own code
   (there are 91 `wmv`/`WMV` strings in the PE) or through XAM services (`XMsg*`); `FFmpeg` is already in the SDK as a
   submodule.
5. **Audio:** XMA is covered by the SDK; the game's own sound engine (`midi.cpp`) is recompiled code.
6. **Input:** controller (the SDK's HID). Kinect: stubs; the game has a controller mode.
7. **Data:** mount the extracted disc contents (`work/game/`) as `game_root`; `Database.xmplr`, `shader.bin` and the
   `.bmbin` files belong to the game.

**Size of the work (no hours):** the translation is already solved except for ~3 targeted patches. The real bulk is
(a) getting a valid build toolchain, (b) debugging boot on an "early development" runtime (graphics and video are
where things usually break most), and (c) polish (performance on the ROG Ally, controls, display). It is a
**medium-sized project with risk concentrated in GPU and video**, not a rewrite project.

## 8. Risks

- rexglue is early: it may not support something in this title and require patches to the SDK (they should be kept
  outside the SDK, through hooks, if possible).
- GPU: the game uses static D3D9 over the ring buffer; fidelity depends on the SDK's Xenos backend. Specific effects
  (EDRAM, resolves) may require work.
- Performance on the ROG Ally (x86-64, iGPU): NOT VERIFIED.
- Legal: you need your own legally obtained copy of the game; the repository contains no game code or data, and a
  built package must not be redistributed. The rexglue README asks not to use it to redistribute games.

## 9. What could NOT be verified

- That the generated C++ **compiles, links and boots** (only a syntax check was done).
- How many of the 743 `bctr` are tail calls versus tables not detected by rexglue (186 `switch` generated).
- Real use of `LDI*`, WMV and Kinect in the game's normal flow.
- Operation on Windows/ROG Ally (not available).
- XenosRecomp linked against the DXC built from source (DXC did build; XenosRecomp was not attempted).
- The boot flow in `docs/analysis/boot-flow.md` is static analysis, not a trace.

## 10. Reproduce

```
# Containers (see containers/experiments/), run with -m 6G -c 4 in the original setup
containers/experiments/build_xenonrecomp.sh     # XenonRecomp
tools/build/build_rexglue_tool.sh    # rexglue (needs the 2 local adjustments from VERSIONS.md)
tools/build/codegen.sh                          # rexglue codegen on eden_manifest.toml
tools/analysis/syntax_check.sh                  # syntax check of the generated C++
```
Artifacts (manifest, logs, XenonRecomp output, rexglue's `generated/`) live under `work/` — outside git.
