# GPU warnings from `eden`, the SDK's capture options and the 27 s before drawing

2026-11-19, static analysis. No ssh, no builds, no running the game.
Inputs: `work/rexglue-sdk` (tag v0.11.0 = a3e1d826; `git describe` says `nightly-20261114-a3e1d826`), generated code in
`work/project/generated/default`, `default.pe` (the decrypted PE), `work/game` (read-only).
Marks: **[V]** verified (SDK file:line, or a command from the final section) · **[I]** inferred.
SDK paths are relative to `work/rexglue-sdk/`.

## Summary in 6 lines

1. The 2 constants are **real, coherent textures** (DXT5 256x256 and DXT3 64x64, with a full mip chain), not garbage and not a video
   frame. The only "invalid" part is the 2 `type` bits (they are 0; the SDK requires 2). [V]
2. The SDK **does not discard the draw**: it lets it through with the texture unbound, which reads as (0,0,0,0) transparent black. Today
   those draws are invisible. `gpu.xenos.allow_invalid_fetch_constants=true` only skips that check. **Recommendation: enable it.** [V]/[I]
3. The SDK **ships no frame dump, screenshots or GPU command trace** in this version, and no off-screen presentation path. [V] Seeing a
   frame depends on giving it a display server with DRI3 (the goal of a separate headless-display task); the SDK does not solve it on
   its own.
4. The main thread's stack is D3D's `main → frame loop → Present → Swap → BlockUntilGPUReached → BusyLoop`. It is **the normal wait of
   `Swap`** for the previous frame: the game was already presenting frames at 35 s. It is not a hang and not the logo video. [V]
5. The 27 s **cannot be explained statically**. Ranked hypotheses in §3.4, with a 1-command experiment.
6. Stubs: the first thing that will get in the way is Kinect (`XamNui*`, `XamShowNui*`) and then `LDIDecompress`; WMV video and XMA do
   not go through stubs. §4.

---

## 1. Warning "Texture fetch constant … has "invalid" type"

### 1.1 Where and why
- It is emitted at `src/gpu/xenos/pipeline/texture/cache.cpp:695-700`, inside `TextureCache::GetTextureKeyFromFetchConstant` (line 679). [V]
- The field is `type`, the **low 2 bits of word 0** (`include/rex/xenos/fetch.h:247`). Values (`fetch.h:163-168`):
  0 `kInvalidTexture`, 1 `kInvalidVertex`, 2 `kTexture`, 3 `kVertex`. Both constants carry 0. [V]
- With `type == 0` and the option off, the function logs the warning and **returns with the key invalidated** (`cache.cpp:682` and `:701`). [V]

### 1.2 What the SDK does with that draw
- `RequestTextures` sees the invalid key, does `binding.Reset()` and continues with the next texture (`cache.cpp:302-307`). **The draw is
  not discarded.** [V]
- In Vulkan, with no image view it returns `VK_NULL_HANDLE` if the device has `nullDescriptor`, or the 1x1 null image
  (`vulkan/texture_cache.cpp:601-614`), whose color is `{0,0,0,0}` (`vulkan/texture_cache.cpp:96-97`, `:457`). [V]
- Effect: the triangle is drawn sampling transparent black. With alpha blending nothing is visible; without blending it comes out
  black. [I]
- The warning is emitted **every time the binding is re-evaluated** (every write of the constant followed by a draw), not once per
  texture. 26,396 warnings in the ~33 s in which there was drawing is ~13 per frame at 60 Hz. [I]
- **Caution:** the warning only appears for the invalid constants. That there are 2 distinct ones says nothing about how many *valid*
  textures are drawn; it could be all of the game's or just these two. That is known by looking at a frame. [I]

### 1.3 What `allow_invalid_fetch_constants` changes
- Declared at `src/gpu/xenos/xenos_settings.h:36` (`bool`, default `false`, "live" lifetime). Full name
  **`gpu.xenos.allow_invalid_fetch_constants`**; the old alias `xenos.allow_invalid_fetch_constants` (`src/base/settings/aliases.cpp:22`)
  works but logs a warning per use. [V]
- It has exactly 2 effects: (a) at `cache.cpp:692` it does `break` and the rest of the constant is decoded as if `type` were 2;
  (b) the same for **vertex** constants with type 1 (`vulkan/command_processor.cpp:3748-3749`). It touches nothing else. [V]
- Real risk: if some constant with type 0 really carries garbage, arbitrary memory would be loaded as a texture (broken image, not a
  crash: the address comes from 20 page bits and the size is bounded). [I]

### 1.4 Decoding (per `fetch.h:237-311`, bits from low to high) [V]

| Field | Constant A | Constant B |
|---|---|---|
| Words | `02000000 1D0F0054 001FE0FF 01280D10 00000203 1D0E0A00` | `01000000 1D108053 0007E03F 01280D10 00000183 1D100A00` |
| `type` (w0, bits 0-1) | **0 = kInvalidTexture** | **0 = kInvalidTexture** |
| `pitch` (w0, bits 22-30) | 8 → 256 px | 4 → 128 px |
| `tiled` (w0, bit 31) | 0 | 0 |
| `format` (w1, bits 0-5) | 20 = `k_DXT4_5` (`format.h:219`) | 19 = `k_DXT2_3` (`format.h:218`) |
| `endianness` (w1, bits 6-7) | 1 = `k8in16` | 1 = `k8in16` |
| `base_address` (w1, bits 12-31) | page 0x1D0F0 → **0x1D0F0000** | page 0x1D108 → **0x1D108000** |
| width x height (w2) | **256 x 256** | **64 x 64** |
| `swizzle` (w3, bits 1-12) | RGBA | RGBA |
| mag/min/mip filters (w3) | linear / linear / `kBaseMap` | same |
| `mip_min`/`mip_max` (w4) | 0 / **8** | 0 / **6** |
| `dimension` (w5, bits 9-10) | 1 = 2D | 1 = 2D |
| `packed_mips` (w5, bit 11) | 1 | 1 |
| `mip_address` (w5, bits 12-31) | **0x1D0E0000** | **0x1D100000** |

Why they are real and not garbage:
- `mip_max` matches log2 of the size (256 → 8, 64 → 6): full chain. [V]
- 256x256 DXT5 takes 0x10000 bytes, and `base − mip` is exactly 0x10000 in A (0x8000 in B). The two allocations are contiguous. [V]
- DXT with `k8in16` is the norm on the 360. No padding field carries stray bits. [V]
- **It is not video**: a video frame would be 1280x720 (or `k_8` Y/U/V planes), not square DXT with mips. By size they look like a UI
  or font texture (256²) and an icon (64²). [I]

### 1.5 Enable the option, or is there a bug upstream of it?
- **Enable it.** The other 5 and a half words are fine, so the code that builds the header runs correctly. A recompilation fault that
  leaves exactly 2 bits at zero and everything else fine would be a mistranslated `rlwimi`, and that would break many more things. [I]
- The SDK's own message says it is incorrect behavior with no known cause and offers the option as a workaround. [V] (`cache.cpp:696-699`)
- These constants **are not on disc**: words 2-4 of A and of B do not appear in any of the 5,943 files of `work/game`
  (0 matches). The header is built by the game on the fly, or comes from a compressed container. [V]
- **Not verified:** which game function writes the `type`. If those textures come out right with the option on, it is closed in
  practice; if they come out broken, the writer has to be found (candidate: whoever copies the 6 words from the texture header into
  registers 0x4800+6·n). [I]

---

## 2. Presentation and SDK options

### 2.1 "Skipping Vulkan frame presentation due to async placeholder draw usage"
- It is emitted at `src/gpu/xenos/vulkan/command_processor.cpp:2162-2164`, inside `IssueSwap`, **only once per process** (static flag
  at `:2159`). That it appears once says nothing about how many frames were skipped. [V]
- With `gpu.xenos.async_shader_compilation=true` shaders and pipelines are compiled on background threads. If at draw time the pipeline
  is still a placeholder, the draw **is skipped** and the frame is flagged (`:3641-3643`). [V]
- When the `Swap` arrives, if the frame was flagged and `gpu.vulkan.async_skip_incomplete_frames=true`, **that frame is not presented**
  (`:2154-2168`); the screen keeps the previous one. The flag is cleared at `:4862`. [V]
- It is benign: it is the cost of the first use of each shader. For deterministic screenshots it is better to turn async compilation
  off. [I]

### 2.2 How options are passed [V] (`docs/site/pages/reference/cvars.md:5`, `:575-587`)
- Command line: `--scope.name=value`. A name that no class declares **is an error** on the command line (`cvars.md:28`).
- File: `{app.root}/{app.name}.toml` by default, or `--config_file <path>` (`include/rex/path_settings.h:25`).
- Environment: only with the new name, not with aliases.
- The `gpu.xenos.*` and `gpu.vulkan.*` scopes exist only when that driver is initialized (`cvars.md:167`, `:214`): with
  `--gpu.driver=null` a `--gpu.vulkan.*` may be rejected. [I]

### 2.3 What was asked for

| Purpose | Exact name | Default | Where |
|---|---|---|---|
| Choose driver | `gpu.driver` (`d3d12`, `vulkan`, `null`, `none`, `any`) | `"any"` | `include/rex/gpu/graphics_system.h:33-34` |
| **Choose Vulkan device** | `gpu.vulkan.device` (index, −1 automatic; alias `gpu.vulkan_device`) | `-1` | `src/gpu/xenos/host/vulkan/vulkan_settings.h:27` |
| Vulkan validation layers | `gpu.vulkan.validation` | `false` | `vulkan_settings.h:74` |
| Vulkan debug messages | `gpu.vulkan.log_debug_messages` | `true` | `vulkan_settings.h:68` |
| Skip incomplete frames | `gpu.vulkan.async_skip_incomplete_frames` | `true` | `vulkan_settings.h:32` |
| Async compilation | `gpu.xenos.async_shader_compilation` | `true` | `src/gpu/xenos/xenos_settings.h:82-83` |
| Invalid constants | `gpu.xenos.allow_invalid_fetch_constants` | `false` | `xenos_settings.h:36` |
| Dump **shaders** to disk | `gpu.xenos.dump_shaders` (folder; empty = nothing) | `""` | `xenos_settings.h:37` |
| Shader cache | `gpu.xenos.store_shaders` + `app.cache_root` (`--cache_root`) | `true` / `""` | `xenos_settings.h:40`, `path_settings.h:29` |
| VSync / frame cap | `gpu.vsync`, `gpu.frame_limit` | `true`, `0.0` | `graphics_system.h:39-40` |
| **No window** | `ui.sdl.video_driver=dummy` ("runs with no display") | `""` | `src/ui/sdl3/sdl3_ui_driver.h:29-30` |
| No UI | `ui.driver=none` (fails in a `TitleApp`, `cvars.md:323`) | `"sdl3"` | `include/rex/ui/ui_system.h:122` |
| Fullscreen | `ui.fullscreen` | `true` | `ui_system.h:127` |
| System dialogs not shown | `kernel.headless` | `false` | `include/rex/kernel/kernel_settings.h:23` |
| **Log level** | `log.level` (`trace`, `dev`, `debug`, `info`, `warn`, `error`, `critical`, `off`) | `"info"` | `include/rex/logging/logger.h:218` |
| Per-category level | `log.categories.<cat>` (e.g. `log.categories.gpu`, `.kernel`, `.cpu`) | empty | `cvars.md:347-353` |
| Flush the log immediately | `log.flush_level` | `"warn"` | `logger.h:221` |
| Log folder | `app.log_root` | `{app.root}/logs` | `include/rex/app/app.h:79` |
| Profiler | `perf.profiler` (needs a build with Tracy) | `false` | `cvars.md:80` |

### 2.4 What does NOT exist in this version
- **Dumping frames or screenshots to disk: none.** In `src/` and `include/` there is no `screenshot`, `frame_dump`, `SaveFrame`,
  `stb_image_write` or similar (0 matches outside RenderDoc). [V]
- **Tracing GPU commands: none** (no `TraceWriter` and no PM4 dump). The closest thing is `log.categories.gpu=trace`, which enables the
  `REXGPU_TRACE` lines (e.g. `command_processor.cpp:843`). [V]
- **RenderDoc:** the SDK loads the API if `librenderdoc.so` is in the process (`host/renderdoc_api.cpp:20-41`,
  `host/vulkan/vulkan_instance.cpp:39`), but `GetRenderDocAPI()` has no callers: it does not trigger captures on its own. `eden` would
  have to be run under `renderdoccmd capture`, and that means installing a third-party binary in the build image (a project decision,
  not taken here). [V]/[I]
- `ui.sdl.video_driver=dummy` leaves the app without a display: the SDK treats it as "headless" (`sdl3_ui_driver.cpp:435`, `:475`) and
  then there is no surface to present to. **It is no use for capturing.** [I]

### 2.5 How to see a frame without a display
**With SDK options it cannot be done.** What is known:
- The SDK always presents to the surface of the SDL window (`xenos_graphics_driver_base.cpp:77-92`); there is no path that writes the
  frame to a file or to accessible memory. [V]
- Already measured on the build machine (`run6.log`): under Xvfb, Mesa warns `No DRI3 support detected - required for presentation`
  and does not present. That is why **`Xvfb -fbdir` and `xwd` against Xvfb would give black**: the frame never reaches the X server.
  [V, measured separately on the build machine]
- What is needed is a server with DRI3 that does not need a monitor: weston/gamescope in headless mode with Xwayland, or Xorg with the
  `dummy` driver and glamor. That is the work of the separate headless-display task; this analysis offers no shortcut. [I]
- Once it presents to such a server, any capture of the server works (`weston-screenshooter`, `xwd -root`, `grim`).
  `tools/test/xwd_to_png.py` (new) converts an XWD to PNG with the standard library and **reports how many pixels are not black**,
  to know whether there is an image without opening it. Tested only with a synthetic XWD (correct colors, rc=0) and with invalid
  inputs (rc=2). [V]
- **For the screenshot to be useful** async compilation has to be off (`--gpu.xenos.async_shader_compilation=false`): with it on, the
  first frames of each screen are skipped (§2.1) and an early screenshot may show a stale frame. [I]
- RenderDoc would be the other route (it captures the frame even if it is not presented), but it is a third-party binary in the image:
  a project decision (§2.4). [I]

---

## 3. The 27 s

### 3.1 What each function on the stack is [V] (listings with `show_func.sh`, §Commands)

| Function | What it is | Evidence |
|---|---|---|
| `sub_8316DB38` | CRT startup (`mainCRTStartup`) | calls `XamLoaderTerminateTitle` on return from `sub_82FB7B68` |
| `sub_82FB7B68` | The game's `main` | initializes and enters `sub_82FB8C58` |
| `sub_82FB8C58` | Main loop / frame (510 lines, 16 indirect calls) | calls `Present` |
| `sub_82E65F58` | `D3DDevice_Present` | copies state, calls `sub_82E654A0` and ends in `sub_82E658D0` |
| `sub_82E658D0` | `D3DDevice_Swap` | imports `VdSwap`, `VdGetSystemCommandBuffer`, `VdPersistDisplay` |
| `sub_82E58A00` | "block until the GPU reaches mark N" | compares `N` against `*(dev+11024)[0]` in a loop |
| `sub_82E5DF40` | One iteration of busy-waiting with a hung-GPU detector | 4 x 8 `db16cyc`; if 5000 ms pass with no progress it calls `sub_82E6B900` |

API names from the shape of the code (there are no symbols). [I]

### 3.2 What `sub_82E5DF40` waits for
- It waits for the word at `*(dev+11024)` to change: the **progress counter that the GPU writes to memory**. `sub_82E58A00` exits when
  `cpu_mark(dev+11036) − gpu_mark ≤ cpu_mark − N`. [V]
- In `Swap` the call is `sub_82E58A00(dev, *(dev+15216), 3, …)` and in normal mode the current mark is then saved in `dev+15216`. That is:
  **every `Swap` waits for the GPU to have finished the previous frame**. It is D3D's normal throttle to avoid queuing more than one
  frame. [V]
- That counter is updated by the SDK when the game writes `SCRATCH_REG0..7` (0x0578-0x057F) with the bit set in `SCRATCH_UMSK`:
  it copies it to `SCRATCH_ADDR + 4·n` (`src/gpu/xenos/command_processor.cpp:356-364`). [V] That `dev+11024` points to that block is [I].
- If the wait exceeds **5000 ms**, `sub_82E6B900` prints a line of `+++…` through `DbgPrint` and, depending on the mode, marks the
  device as hung or prints "The GPU is hung and can't be recovered…" (0x8244DCB0) and executes a `trap`. [V]
  **If that line of `+` is not in the log, no `Swap` wait exceeded 5 s** and the GPU thread was never stuck. [I]

### 3.3 Which `WAIT_REG_MEM` that path sends [V]
Opcode 0x3C, header `0xC0043C00` (5 words: info, address, reference, mask, wait). There are 16 sites in 12 functions that build a
header ending in `0x3C00`: 11 in the D3D library (0x82E56DB8-0x82E656E8) and 1 outside (`sub_82D55A50`). The ones on the
`Present`/`Swap` path:

| Emitter | info | address | ref | mask | wait | Meaning |
|---|---|---|---|---|---|---|
| `sub_82E656E8` (from `Swap`), 2 conditional packets | 3 = register, `==` | 0x1973 `AVIVO_D1SCL_UPDATE` | 0 | 0x1 | 0x100 | wait for the scaler to finish updating |
| `sub_82E654A0` (from `Present`), 1st | 0x13 = memory, `==` | `*(dev+11028)+4`, endian 2 | 1 | 0xFFFFFFFF | 0x100 | wait for the word to equal 1 |
| `sub_82E654A0`, 2nd | 0x13 = memory, `==` | the same | 0 | 0xFFFFFFFF | 0x100 | wait for it to go back to 0 |

- Before the 1st memory wait the game writes `SCRATCH_REG1` (0x0579) = 1, and between the two it inserts a packet with the routine
  `0x82E65238` as a callback (`sub_82E59660`). Reading: "set the word to 1, notify the CPU, and **wait for the CPU to set it to 0**". [I]
- The 2nd wait depends on the SDK delivering the **graphics interrupt** to the guest CPU
  (`command_processor.cpp:874-889` → `xenos_graphics_driver_base.cpp:290-294`). If it is not delivered, the GPU thread stays there
  forever and `Swap` trips the 5 s detector. [I]
- How the SDK waits: `ExecutePacketType3_WAIT_REG_MEM` (`command_processor.cpp:939-1032`). With `wait ≥ 0x100` and vsync on it sleeps
  `wait/0x100` ms per iteration (here 1 ms) and retries **with no time limit** (`:1009-1021`). [V]
- Seeing the GPU thread inside that function in a sample is what is expected of a 60 Hz game: it spends almost the whole frame
  there. [I]

### 3.4 Why it takes 27 s: hypotheses
What was measured only says that the first **texture warning** arrived at 27 s, not that the first frame arrived at 27 s. The stack
from point 4 (null driver, 35 s) shows that the frame loop was already running.

1. **There were frames from earlier on, without textures (or with valid textures, which do not warn).** The game presents black while
   it does something else, and at 27 s the screen that uses these 2 textures starts. This is the most likely. [I]
2. **A Kinect/profile wait with a timeout.** The game is a Kinect title and all the `XamNui*`/`XamShowNui*` it imports are stubs that
   set no return value (§4). An initialization that retries until it gives up fits a silence of fixed duration. [I]
3. **The logo videos.** `movie/ubi_logo.wmv` and `movie/q_logo.wmv` exist [V]. Against: the log shows no file opens in those 27 s. If
   the decoder fails and the game waits for the duration of the video, that would also give a fixed silence. [I]
4. **Shader compilation / skipped frames.** Unlikely: that happens after draws start, not before. [I]
5. **Stuck GPU with recovery.** Ruled out if there is no `+++` line in the log (§3.2). [I]

**1-command experiment that separates 1 from 2-3** (command 2 of the final section): run 40 s with `--log.level=debug` and count per
second the `VdSwap` calls and the most-called imports. If there are ~60 `VdSwap`/s from second 1 it is hypothesis 1, and the import
that dominates those seconds says what the game is waiting for. If there is no `VdSwap` until second 27, the name of the repeating
import gives the cause.
**Not verified:** that the `debug` level logs every import call; if not, repeat with `trace`.

---

## 4. Stubs that will get in the way

Of the game's imports, 39 are stubs in rexglue (list generated during the import inventory) and none is missing (the list of imports
absent from rexglue is empty). [V]

**How a stub fails:** `REX_EXPORT_STUB` (`include/rex/ppc/hook.h:80-84`, `:143`) logs in the `cpu` category (with an "already seen"
flag per stub, i.e. once [I]) and returns **without touching `r3`**: the game receives its own first argument as the result. A stub
that should return 0 or an error code returns a pointer or an index. That is why a called stub is not harmless and also does not show
up repeatedly in the log. [V]

Ordered by "what will get in the way first" (the number is the count of call sites in the generated code [V]; the order is [I]):

| # | Import (sites) | Why it gets in the way |
|---|---|---|
| 1 | `XamNuiIdentityGetSessionId` (6), `XamUserNuiGetUserIndex` (3), `XamUserNuiGetEnrollmentIndex` (1), `XamUserNuiEnableBiometric` (1) | Kinect identity at startup. With `r3` undefined the game may believe there is a session or wait for one. Candidate for the 27 s. |
| 2 | `XamNuiCameraTiltReportStatus` (7), `…TiltGetStatus` (1), `…TiltSetCallback` (1), `…Elevation*` (5), `…RememberFloor` (2), `PsCamDeviceRequest` (1) | Camera sensor and motor. The game is also playable with a controller, but the initialization runs anyway. |
| 3 | `XamShowNuiSigninUI` (1), `XamShowNuiDeviceSelectorUI` (1), `XamShowNuiGuideUI` (1), `XamShowNuiGamerCardUIForXUID` (1), `XamShowGamerCardUIForXUID` (1) | Kinect versions of the system dialogs. `kernel.headless` only covers the implemented ones (`src/xam/xam_ui.cpp:226`, `:290`); these are stubs and never complete their asynchronous operation. When asking for sign-in or a save device, the game may sit waiting. |
| 4 | `LDICreateDecompression` (1), `LDIDecompress` (2), `LDIDestroyDecompression` (1) | The system's LZX decompression. If some resource is compressed that way, the buffer is left unfilled: garbage data with no warning. |
| 5 | `XamProfileCreateEnumerator` (1), `XamProfileEnumerate` (1), `XamUserGetIndexFromXUID` (1), `XamReadBiometricData` (2), `XamWriteBiometricData` (1) | Profile. Gets in the way on reaching the menu or when saving. |
| 6 | `XamCacheOpenFile` (1), `XamCacheCloseFile` (1), `XamCacheReset` (1) | Hard-disk cache. It normally has an alternate path. |
| 7 | `XamXStudioRequest` (15), `EtxProducer*` (8), `XamXlfs*` (4), `XamGetActiveDashAppInfo` (6), `ObCreateObject` (1), `XeKeysGetConsoleID` (1) | Telemetry and studio tools. Almost certainly harmless. |

What is **not** a stub although it was suspected:
- **WMV video:** there is no video import; the decoder is linked inside the game (thread `sub_8292A428`, see `thread-exit.md`).
  It depends on file I/O, audio and texture uploads, not on a stub. [I]
- **XMA:** the SDK decodes it with FFmpeg (`runtime.ffmpeg_verbose` exists, `cvars.md:289`). It is not in the stub list. [V]
- **Earlier open item that still stands:** `0x830EF968` is a `REXCPU_FATAL` on the sound thread's path (`thread-exit.md` §3). As soon
  as that audio path is used the process dies. It is more urgent than any stub in this table.

**Not verified:** which of these are actually called at startup. Command 2 answers that: called stubs appear once each in the `cpu`
category.

---

## What to run now (build side, on the build machine)

`BASE` = the `docker run … eden-recomp:build bash -c "LD_LIBRARY_PATH=/b … "` wrapper used for the earlier runs. `XSRV` = the wrapper
that provides a server with DRI3 (whatever comes out of the headless-display task); until it exists,
`xvfb-run -a -s '-screen 0 1280x720x24'` works for commands 1, 2 and 5, which only read the log.

```bash
# 1. Do the warnings disappear with the option? (0 expected; 26,396 before)
timeout 60 XSRV ./eden --title.game_root=/assets --gpu.driver=vulkan --gpu.xenos.allow_invalid_fetch_constants=true --gpu.xenos.async_shader_compilation=false > /b/run7.log 2>&1; grep -c 'has "invalid" type' /b/run7.log

# 2. What the game does in the first 27 s (§3.4) and which stubs it touches (§4): VdSwap per second, stubs, and the hung-GPU line
timeout 40 XSRV ./eden --title.game_root=/assets --gpu.driver=vulkan --log.level=debug > /b/run8.log 2>&1; grep VdSwap /b/run8.log | cut -c1-19 | uniq -c | head -40; grep -ciE 'stub|unimplemented' /b/run8.log; grep -c '+++++' /b/run8.log

# 3. With a DRI3 server: screenshot at 45 s WITH the option (capture method of the headless-display task; if it is xwd, convert with xwd_to_png.py)
XSRV bash -c 'timeout 60 ./eden --title.game_root=/assets --gpu.driver=vulkan --gpu.xenos.allow_invalid_fetch_constants=true --gpu.xenos.async_shader_compilation=false > /b/run9.log 2>&1 & sleep 45; xwd -root -silent -out /b/frame45.xwd; wait'; python3 -I /b/xwd_to_png.py /b/frame45.xwd /b/frame45.png

# 4. The same screenshot WITHOUT the option, to see what those 2 textures contribute (compare the % of non-black pixels)
XSRV bash -c 'timeout 60 ./eden --title.game_root=/assets --gpu.driver=vulkan --gpu.xenos.async_shader_compilation=false > /b/run10.log 2>&1 & sleep 45; xwd -root -silent -out /b/frame45_without.xwd; wait'; python3 -I /b/xwd_to_png.py /b/frame45_without.xwd /b/frame45_without.png

# 5. Summary of warnings and errors of run 1, grouped
grep -E ' W | E ' /b/run7.log | grep -v 'unimplemented' | cut -c25-160 | sort | uniq -c | sort -rn | head -20
```

Notes: 3 and 4 need `xwd` (`x11-apps`) in the image and `tools/test/xwd_to_png.py` copied into `work/build/`. The `cut` calls assume
the default log pattern (`%Y-%m-%d %H:%M:%S.%e %Q …`, `cvars.md:71`); if the counts come out empty, adjust the columns.

---

## Commands that prove the above

Everything in a local container, read-only (the experiments image built from `containers/experiments/`, `-m 6G -c 4`). `OUT` is the
directory holding `default.pe`, the rexglue project (`rex/eden`, i.e. `work/project`) and the two import lists. The commands were
written for Apple's `container` CLI on the ARM Mac:

```bash
# from the repo root
container run --rm -m 6G -c 4 -v "$PWD/tools:/r/tools:ro" -v "$OUT:/r/out:ro" \
  -v "$PWD/work/game:/assets:ro" "$IMAGE" bash -c '<command>'

H=/r/tools/analysis; G=/r/out/rex/eden/generated/default; PE=/r/out/default.pe
# §3.1-3.2: the stack
bash $H/show_func.sh sub_82E5DF40 sub_82E58A00 sub_82E6B900 sub_82E65F58 sub_82E658D0 sub_82E5DE48 sub_82E5DE78
python3 -I $H/call_tree.py $G sub_82E658D0 0      # Vd* imports => it is Swap
python3 -I $H/string_at.py $PE 0x8244DDF0 0x8244DD10 0x8244DCB0 0x8244CA98   # hung-GPU messages
# §3.3: who emits WAIT_REG_MEM (header 0xC0043C00 = lis -16380 ; ori 15360)
awk '/^DEFINE_REX_FUNC\(/{f=$0} /\/\/ ori r[0-9]+,r[0-9]+,15360$/{print FILENAME":"FNR" "f}' $G/eden_recomp.*.cpp
bash $H/show_func.sh sub_82E656E8 sub_82E654A0 sub_82E65668
# §1.5: the constants are not in the game data
python3 -I $H/find_bytes.py /assets 001FE0FF01280D1000000203 8 4
python3 -I $H/find_bytes.py /assets 0007E03F01280D1000000183 8 4
# §4: call sites per stub
for i in $(cat /r/out/imports_stub_in_rexglue.txt); do echo "$i $(grep -h "__imp__$i(ctx, base)" $G/eden_recomp.*.cpp | wc -l)"; done
```

## New tools

| File | Purpose |
|---|---|
| `tools/analysis/find_bytes.py` | Searches for a hex sequence in every file of a directory, with context. Exits with 2 if the directory is empty or not mounted. |
| `tools/test/xwd_to_png.py` | Converts an XWD screenshot (`xwd -root`) to PNG and counts non-black pixels. Only useful once there is a server that presents. |

## What is left unverified
- That with the option on the 2 textures look right (commands 1, 3 and 4).
- Which game function leaves `type` at 0.
- The cause of the 27 s (command 2).
- That `dev+11024`/`dev+11028` are the `SCRATCH_ADDR` block, and what exactly the callback `0x82E65238` does.
- That `debug` logs every import (if not, `trace`), and the exact format of the XWD delivered by whichever server is chosen.
- Which stubs are touched at startup.
