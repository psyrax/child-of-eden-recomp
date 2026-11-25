# Feasibility of a VR (Meta Quest 2) version of Child of Eden — analysis only

2026-11-19. **Read-only**: nothing was compiled, the game was not run, and nothing outside this file was modified.

**Limitation of this pass (important):** no shell was available, so **only text search and file reads were used**.
`xref_strings.py`, `xref_calls.py` and `show_func.sh` could not be run. The addresses therefore come from direct reads of
the generated C++ (`work/project/generated/default`), of the import list (`imports.txt`) and string dump (`strings.txt`)
extracted from the executable, and of the code in `work/rexglue-sdk`. Every statement is tagged:
**[V]** = seen in the cited file; **[I]** = inferred; **[D]** = from documentation/public knowledge (OpenXR, Quest,
Adreno, WiVRn/Monado), **not verified here**; **[?]** = not determined.

## Summary (what matters)

1. **Stereo.** The game's shaders (HLSL in `shader.bin`) almost always receive **a single combined matrix**,
   `gWorldViewProj` (and in other passes `gViewProj`, `gView`, `gProj`, `gViewInv`, `gProjInv`). There is no separable
   "camera" in the GPU backend. Neither the CPU-side code that builds the projection (field of view, near/far) nor the
   camera was located [?]. The least bad option is **(c)**: two command processors reading the same ring, one per eye,
   with the matrix replaced per eye. High risk, see §1.
2. **Kinect.** The executable does **not** import `XamNuiGetDeviceStatus` or any skeleton API through XAM. It imports 16
   NUI/camera symbols; **all** calls to them are in the statically linked NUI library (0x830FB388–0x83116CA0), not in
   the game code. The game calls that library (`NuiInitialize`, `NuiSkeletonGetNextFrame`, `NuiImageStreamOpen`,
   according to the `CNatal` strings). Returning a synthetic skeleton **cannot** be solved in the XAM stubs: it has to
   be done **in the NUI library or in `CNatal`** (rexglue hooks). The game also ships a debug mode, `FakeNatalPad`.
3. **Runtime/OpenXR.** rexglue has nothing for VR/OpenXR/stereo/multiview. The final frame reaches a **guest output
   image** (`A2B10G10R10`) and from there a Vulkan swapchain created at `vulkan_presenter.cpp:823`. It is separable:
   that image can be handed to OpenXR without touching the GPU emulation.
4. **Native on Quest 2.** The SDK builds for **linux-arm64** (glibc), but **not for Android** (the CMake says "Windows,
   Linux, and macOS only" and `rex/main_android.h` is missing). Blockers: the Android/bionic platform, the exception
   handler and guest memory on Android, the Adreno 650 Vulkan device, and the GPU cost of two eyes. **Not recommended
   as a first step.**
5. **Recommendation:** PC VR (Quest 2 as a display through WiVRn/ALVR/Steam Link), in stages. First find the
   projection/camera and a synthetic skeleton; flat side-by-side stereo before OpenXR. §5.

---

## 1. Stereo: matrices, shaders and where to draw two eyes

### 1.1 What is in the shaders (strong evidence) [V]

`strings.txt` contains the HLSL of `shader.bin` as text. Global parameters that appear (line numbers in that file):

| Parameter | Where (lines of `strings.txt`) | Use |
|---|---|---|
| `gWorldViewProj` | 476–484, 9241–9421, 10447, 11237, 12135, 13161… (dozens) | `oPosition = mul(float4(position,1), gWorldViewProj)`: **most vertices** |
| `gViewProj` | 10334, 10561, 10635, 10758 | particles/geometry already in world space (`mul(float4(wp,1), gViewProj)`) |
| `gView`, `gViewInv`, `gProj`, `gProjInv` | 9242, 9769–70, 11678–80, 12037–38, 12545, 13940–41, 31818–19, 35366–71… | passes that reconstruct or need view space |
| `gViewCB`, `gViewInvCB`, `gProjCB`, `gProjInvCB` | 13755–61, 32199–32205, 35268–74, 36368–74 and hundreds of repetitions (53481…96197) | shared global buffer, repeated for every shader |
| `gScreen` | 456, 2916, 3444, 12191, 15379 | 2D / screen passes |
| `FOV DEGREE`, `arrow_fov_rate`, `Player with FovAnim` | 37241, 20595, 33120 | game parameters (the FOV is data and can be animated) |

Consequences [I]:
- Since almost everything uses `WorldViewProj` already multiplied on the CPU, **the GPU backend cannot separate view
  from projection** from a single uniform. What it can do is **apply a clip-space change** to `gl_Position`
  (e.g. the per-eye horizontal shift `x' = x + sep·(w − conv)`) without knowing the camera. That gives convergent
  stereo but **no** head tracking (rotation), and it fails in passes that **reconstruct position from depth**
  with `gViewInv`/`gProjInv` (light-volume lighting, e.g. `lightPosition = mul(...gWorldViewProj)` at
  lines 14948–14985; screen effects), because those passes read textures already drawn without the shift.
- `gScreen`/2D passes (HUD, reticle) **must not** be shifted the same way; they have to be told apart by shader or by
  state.

### 1.2 What was NOT found [?]

- **The CPU function that builds the perspective projection (FOV, near, far) and the camera was not located.** There
  are camera types in data (`CameraTypeConst_Lookat`, `_Handy`, `_Driving`; `NodeTypeConst_CameraLookat/Handy/Driving`,
  `strings.txt` 175–177, 202–205) and phases `Before Camera`, `Decide Camera`, `After Camera` (419–421). HLSL parameter
  names are registered by string: the way to reach the function is to **xref `"gProj"`, `"gViewProj"`,
  `"gWorldViewProj"`, `"gViewInv"` with `tools/analysis/xref_strings.py`** and walk up with `xref_calls.py` to whoever
  writes the 16 floats (typically a 4x4 multiply routine using VMX: `vmx.h` in the runtime). This could not be run in
  this pass.
- Whether the game uses one or several camera passes per frame: **not determined**. Hints [I] of several passes: there
  are per-shader global `gViewCB` blocks (a common constant block) and post-processing/bloom/light-volume shaders.
  2D interface: passes with `gScreen`.

### 1.3 How constants reach the backend [V]

`src/gpu/xenos/vulkan/command_processor.cpp`:
- The Xenos float constants (256 vertex vec4 + 256 pixel) are tracked in
  `current_float_constant_map_vertex_/_pixel_` (lines 1989–2075) and uploaded to the system buffer.
- **The only guest draw calls** are `CmdVkDraw` (line 3849) and `CmdVkDrawIndexed` (3880); the one at line
  2738 (`CmdVkDraw(3,1,0,0)`) is a helper triangle of the runtime itself. `IssueSwap` is at 2134 and calls
  `presenter->RefreshGuestOutput` (2270).
- Rendering is expressed on top of the **EDRAM** emulation: `render_target_cache.cpp` maps EDRAM tiles to host images.
  **Drawing the same draw twice into the same set of render targets does not produce two eyes**: both would blend
  into the same target.

### 1.4 Options for drawing two eyes, and their risk

| Option | What it is | Risk |
|---|---|---|
| **(a) Call the game's render twice with the camera shifted** | Re-run the game's draw function on the CPU with another camera. | **High.** The game mixes update and draw; repeating causes side effects (particles, animation, resource state, synchronization with the D3D `Swap`, GPU thread). It also requires having found the camera [?]. Not recommended. |
| **(b) Duplicate the draws in the backend (`command_processor.cpp:3849/3880`) shifting the projection** | For each draw, emit another with modified constants. | **High.** (1) Two sets of render targets/EDRAM are needed, one per eye, or they overwrite each other (§1.3). (2) With a combined `WorldViewProj` only the clip-space shift is possible (§1.1), not head rotation, and passes that reconstruct position break. (3) Draws have to be classified as 3D vs 2D/post. (4) 2x vertex/raster. |
| **(c) Two command processors in parallel** [proposal, untested] | A second `VulkanCommandProcessor` (with its own `shared_memory`, `texture_cache`, `render_target_cache` and EDRAM) that reads **the same** PM4 stream from the ring; each instance replaces the matrix differently and each result goes to one eye. | **Medium-high.** Isolates EDRAM/resolve state and avoids replay races; costs 2x GPU and 2x VRAM. Risks: whatever the GPU returns to the CPU (occlusion readbacks, `memexport`, resolves the CPU reads) must come from only one instance; the text in §1.1 about passes using `gViewInv` applies equally. Requires knowing **which constants are the matrix** (§1.2). |
| **(d) Replay the whole frame twice** [proposal] | Save the PM4 from swap to swap and re-run it with another constant. | **High.** The game's CPU may already be writing the next frame's memory while the replay runs; the data referenced by PM4 (vertices, textures) is not stable. |

Verdict: **(c)** is the most viable architecturally if the matrix is found; **(b)** is the cheapest to try just to
**demonstrate depth** (clip-space shift, no head tracking, single view side by side).

---

## 2. Kinect / NUI

### 2.1 What the executable imports [V]

`imports.txt` (218 imports). The ones related to NUI/camera/biometrics:

| Import (thunk address) | In the SDK |
|---|---|
| `XamShowNuiGuideUI` (0x8330E0AC), `XamShowNuiSigninUI` (…E0BC), `XamShowNuiGamerCardUIForXUID` (…E0CC), `XamShowNuiDeviceSelectorUI` (…E0DC) | stub (per our list of imports that are stubs in rexglue) |
| `XamShowNuiTroubleshooterUI` (0x8330E90C) | implemented: returns 0 (`src/xam/xam_nui.cpp:37`) |
| `XamNuiCameraTiltGetStatus/ReportStatus`, `…ElevationStopMovement/GetAngle/SetAngle`, `…RememberFloor`, `…TiltSetCallback` (0x8330E89C–E8FC) | stub (7) |
| `XamNuiIdentityGetSessionId` (0x8330E93C), `XamUserNuiGetUserIndex` (…E92C), `XamUserNuiGetEnrollmentIndex` (…E94C), `XamUserNuiEnableBiometric` (…E99C) | stub (4) |
| `XamReadBiometricData`, `XamWriteBiometricData` | stub |
| `PsCamDeviceRequest` (0x8330EB2C), `ObCreateObject` (…EB1C), `XamXStudioRequest` (…E86C) | stub |

It does **not** import `XamNuiGetDeviceStatus` (which the SDK does implement at `xam_nui.cpp:31`, returning "not
connected"), nor any skeleton/image function through XAM. [V] (absent from `imports.txt`).

### 2.2 What it actually calls, and from where [V]

All calls to `XamNui*`/`PsCamDeviceRequest` fall **between 0x830FB388 and 0x83116CA0**, i.e. in the statically linked
NUI library (earlier analysis already placed `sub_83104058` and `sub_8310FBA8` there; `docs/analysis/thread-exit.md`).
Call sites (return address `lr`):

- `XamNuiIdentityGetSessionId`: 0x8310D354, 0x8310D798, 0x831097A8, 0x83109560, 0x83116CA0, 0x8310C860 (6)
- `XamUserNuiGetUserIndex`: 0x8310BA0C, 0x8310B180, 0x831095F4 (3); `…GetEnrollmentIndex`: 0x8310AEE8; `…EnableBiometric`: 0x8310CDB4
- `XamNuiCameraTiltReportStatus`: 0x830FE960, 0x830FE99C, 0x830FEAE8, 0x830FEB24, 0x830FE308, 0x830FE33C, 0x830FDBD8 (7)
- `…ElevationSetAngle`: 0x830FE21C, 0x830FDDB8; `…GetAngle`: 0x830FE4A0; `…StopMovement`: 0x830FFD80, 0x830FDB44;
  `…RememberFloor`: 0x830FE370, 0x830FE3D8; `…TiltSetCallback`: 0x830FEC9C; `…TiltGetStatus`: 0x830FDE58
- `PsCamDeviceRequest`: **a single** call, in `sub_830FFE20` (0x830FFE6C): it requests `XamXStudioRequest(4099, &x)`
  and, if that fails (<0), retries with `PsCamDeviceRequest`. (`eden_recomp.76.cpp:27110`.)
- `ObCreateObject`: one call at 0x830FD7AC (`eden_recomp.60.cpp`); `ObReferenceObjectByHandle`/`ObOpenObjectByPointer` at
  0x830FCCB8, 0x830FB388, 0x830FD930/968, 0x830FCFD8, 0x8310C818/834, 0x83109240: the library stores and references
  **objects/events passed in by the game** (the handles of `NuiImageStreamOpen`).

The `XamShowNui*` calls were not caught by the search for the pattern `lr = …; __imp__…`; the game's strings
(`XShowNuiGuideUI start?`, `qeNatal : GUIDE`, `strings.txt` 44101–44103) confirm that they exist and that the
`CNatal` code calls them. **Call sites: not located [?].**

### 2.3 What the game does on top: the `CNatal` class [V from strings, I for addresses]

From `strings.txt` (≈ 43498–44233): `CNatal::Init` with `NuiInitialize` (errors `E_INVALIDARG`, `E_OUTOFMEMORY`,
`ERROR_ALREADY_INITIALIZED`); `EnableSkeletonTracking` → `NuiSkeletonTrackingEnable`; `EnableColorStream` /
`EnableDepthStream` → `NuiImageStreamOpen` (`NUI_IMAGE_TYPE_COLOR`, `NUI_IMAGE_TYPE_DEPTH_AND_PLAYER_INDEX`, and a
`Depth80x60`); `Update` → `NuiSkeletonGetNextFrame(0, &SkeletonFrame)`; `NuiCameraAdjustTilt`; identity
(`CNatal::StartIdentity`, `startEnroll`, `IdentityIdentifyCallback`); texture `NatalTex320x240`; `Natal:RefineHands`
(ATG routine); `CHistoryJoint`, `NatalUpdate HistoryEntry`, `Scale2DSkeleton`, `Cursor:Skeleton`, `SkeletonDraw`.

Addresses (in the `CNatal` range, 0x82D5xxxx):
- **`sub_82D54010`** = `CNatal::Init` [I]: returns 0x80004005 if `this+96` is already 1 (string "already initilized"),
  zeroes a large object (fields up to `this+10288`) (`eden_recomp.10.cpp:15095`).
- **`sub_82D53870`** creates the thread and **`sub_82D531E8`** is the Kinect thread (`docs/analysis/thread-exit.md`).
- The addresses of `NuiInitialize`, `NuiSkeletonGetNextFrame`, `NuiImageStreamOpen` in the library were not obtained [?]
  (they can be obtained with `xref_strings.py` on the strings `CNatal::Update:NuiSkeletonGetNextFrame…`).

### 2.4 The structure it expects [D] + [partial V]

Judging by the strings, the game uses the public `NUI_SKELETON_FRAME` API of the Kinect XDK (360): 6 skeletons, 20
joints, positions in skeleton space (meters, right-handed: +x right, +y up, +z forward from the sensor), tracking
state. **The exact layout was not read** from the binary [?]; the game also filters the joint history
(`CHistoryJoint`) and refines hands with its own routine (`RefineHands`, which requires `NatalTex320x240` and `80x60`
depth), i.e. **providing the hands is not enough: the "refined hands" path may read depth/color images**
(`NuiImageStreamGetNextFrame`, `strings.txt` 44231/44233) [I].

### 2.5 What decides that the menu only offers "Controller" [I/?]

- There are Kinect options: `NormalKinect`, `HardKinect`, `[FreeNatal]`, `[NormalNatal]`, `[HardNatal]`,
  `ASelExistKinect`, `SelExistKinect`, `SelKinectSignInUI`, `InfoKinectAdjust`, `DisconnectKinect`, and a menu
  `grp_menu_kinect` (`docs/analysis/boot-flow.md`). "Normal (Controller)" is the variant without a sensor.
- The game detects a present sensor through: (i) the return value of `NuiInitialize` and `NuiSkeletonGetNextFrame`
  (`E_NUI_DEVICE_NOT_CONNECTED`, `E_NUI_DEVICE_NOT_READY`), and (ii) the system notification
  `XN_SYS_NUIHARDWARESTATUSCHANGED` with parameters `XNUI_HARDWARE_STATUS_CONNECTED/READY/READ…`
  (`strings.txt` 44096–44100), which arrives through `XNotifyGetNext`.
- **The function that decides the menu list was not located [?]**; the natural candidate is the code that reads the
  `CNatal` state (a flag derived from those two sources) in `ZeroMenuCtrl` (`sub_82DEB858`) and in the archive
  selection.

### 2.6 Would a synthetic skeleton with two hands be enough? [I]

**Probably yes for the main mechanic, but not in the XAM stubs.** What has to be satisfied, from least to most:
1. `NuiInitialize` returns success and `NUI_HARDWARE_STATUS_CONNECTED/READY` arrives by notification → the game will
   offer the Kinect modes.
2. `NuiSkeletonGetNextFrame` delivers a `NUI_SKELETON_FRAME` with a "tracked" skeleton and hands in plausible positions
   (useful range and speed) → this would drive the reticle (`Cursor:Skeleton`, `NatalPad…`).
3. The "refined hands" path (`RefineHands`) and identity/enrollment (`NuiIdentity*`,
   `XamNuiIdentityGetSessionId` → without a session the game asks for `StartIdentity`/`startEnroll`) must not break.

Recommended injection point: **a rexglue hook (`REX_HOOK`/`REX_DETOUR`, `docs/site/pages/codegen/hooks.md` in the SDK)
on the NUI library functions** (`NuiInitialize`, `NuiSkeletonGetNextFrame`, `NuiImageStream*`, identity), not on
`XamNui*`: below those sits a protocol with the kernel that is not understood [?].

**Shortcut already included by the game itself [V from strings, ? for usage]:** `m_bFakeNatalPad`,
`m_fFakeNatalPadAngNoise`, `…AngLR`, `…AngUp`, `…AngDown`, `FakeNatalPad`, `NatalPad`, `NatalPadAngNoise/LR/Up/Down`
(`strings.txt` 43728–43736, 43930; `NatalPad…` also in the executable image). It looks like a debug mode that
**simulates the Kinect cursor with a controller**. Where it is enabled and whether it survives in the retail build:
**not determined [?]**; worth checking before inventing a skeleton.

---

## 3. Runtime, VR/OpenXR and presentation

- **VR in the runtime:** nothing. Searching for `openxr|XR_KHR|multiview|stereo|vr` in `work/rexglue-sdk/src`
  **only** gives hits in audio (XMA/mix) and `swap_chain_desc.Stereo = FALSE` in `d3d12_presenter.cpp:104`
  (Windows, DXGI) [V]. No `VK_KHR_multiview` and no OpenXR extensions. (Curiosity: the SDL3 in `thirdparty/` ships an
  `openvr` video driver, not used by rexglue.)
- **Where it presents [V]:**
  - The command processor ends the frame in `IssueSwap` (`command_processor.cpp:2134`) and hands the result to the
    output image with `presenter->RefreshGuestOutput(…)` (line 2270). Internal format
    `kGuestOutputFormat = VK_FORMAT_A2B10G10R10_UNORM_PACK32` (`vulkan_presenter.h:85`), with a mailbox of several
    versions (`kGuestOutputMailboxSize`).
  - `VulkanPresenter::DriverPaintAndPresent` (`vulkan_presenter.h:169`) paints that image onto the window swapchain:
    `vkCreateSwapchainKHR` at `vulkan_presenter.cpp:823`, `vkAcquireNextImageKHR` 978, `vkQueuePresentKHR` 1373. The
    surface comes from SDL3 (X11/Wayland/Android/Win32/Metal in `api.h` and `vulkan_instance.cpp:128–145`).
- **Separability:** high. The split between `RefreshGuestOutput` (emulation) and `PaintAndPresent` (display) allows
  replacing the presenter with an OpenXR one that takes the output image (sampler) and copies it to each eye's
  `XrSwapchain`. What **does** get in the way [I]: (1) rexglue creates its own `VkInstance`/`VkDevice`
  (`vulkan_instance.cpp`, `vulkan_device.cpp`) and OpenXR with `XR_KHR_vulkan_enable2` [D] requires creating them
  through `xrCreateVulkanInstanceKHR`/`…DeviceKHR` (or using `XR_KHR_vulkan_enable` with restrictions) → the OpenXR
  runtime must be allowed to choose the physical device; (2) the output image is **one**, not two (§1).
- **Device requirements [V]** (`vulkan_device.cpp:65–90, 564–576`): `independentBlend`, `fragmentStoresAndAtomics`,
  `vertexPipelineStoresAndAtomics` mandatory; `geometryShader` mandatory except on macOS (`require_geometry_shader`,
  `vulkan_settings.h:60`); also `fullDrawIndexUint32`, `sampleRateShading`, `depthClamp`, `shaderClipDistance`,
  `shaderCullDistance`.

---

## 4. Native on the Quest 2

| Topic | Evidence | Status |
|---|---|---|
| ARM64 | `CMakeLists.txt:162–198` defines `linux-arm64`, `win-arm64`, `mac-arm64`; `CMakePresets.json` includes them; `RELEASING.md:84` publishes `build-linux-arm64`; `rexglue_target.cmake:119–121` uses `-march=armv8-a`; `platform.h:59–61` defines `REX_ARCH_ARM64`; `exception_handler.h` and `ppc/context.h:68` have an ARM64 branch; `cmake/rexglue_physical_offset.cmake` handles 16 KiB pages | **It does build, on Linux/macOS/Windows ARM64 (glibc/Apple/MSVC ABI)** [V by reading; not compiled] |
| Android | `CMakeLists.txt:197`: "ReXGlue supports Windows, Linux, and macOS only". There are leftovers inherited from Xenia (`REX_PLATFORM_ANDROID` in `src/base/memory_posix.cpp:52,87,338`, `threading_posix.cpp:70`, `VK_USE_PLATFORM_ANDROID_KHR` in `api.h:26`), but **`rex/main_android.h` does not exist** (included in `threading_posix.cpp:73`) and neither does an Android preset/toolchain [V] | **Not supported**; a port is needed |
| Compiler | Clang ≥ 19 (relaxed here from 20); the Android NDK ships clang [D] | not a blocker in principle |
| Vulkan | uses Vulkan 1.0/1.1+ and the list in §3. Adreno 650 on Quest 2 [D]: Vulkan 1.1 with `geometryShader`, `independentBlend`, `fragmentStoresAndAtomics`, `shaderClipDistance`; **no** fragment interlock (the EDRAM emulation would fall back to the render-target path: slower) | **not verified**; would require testing on the headset |
| Guest memory | 4 GB reserved address space + views, page watching through SIGSEGV (`exception_handler.h`) [V]; Android allows both, with RAM limits (Quest 2: 6 GB, not all for the app) [D] | medium risk |
| CPU | statically recompiled code: the game uses ~1.4 cores on x86; on ARM64 the codegen emits C++ with VMX in `ppc/vmx.h` (445 intrinsic uses across `fpu.h`/`vmx.h`) | **performance not measured**; the XR2's Kryo is notably slower than a desktop [D] |
| GPU | Quest 2: 1832x1920 per eye at 72/90/120 Hz [D] ≈ 7 Mpixels per frame vs 0.92 Mpixels for the game at 720p (≈ 7.6x) | **the bottleneck**; only plausible at a much reduced resolution |
| Input/sensor | there is no OpenXR code, nor Quest controller/hand code in `src/hid` (only SDL3) [V] | to be written |
| Dependencies | SDL3 (in `thirdparty/`), Vulkan, VMA; audio libs (XMA/FFmpeg) | would have to be built for Android; **not audited** |

Conclusion (4): ARM64 is not a blocker; **Android is** (unsupported platform + GPU bottleneck + CPU + RAM). It is a
project of months, not a stage.

---

## 5. Recommendation in stages (cheapest to most expensive)

**Stage 0 — Code findings (no hardware; can already be done with the repo's tools).**
a) Xref `"gProj"`, `"gViewProj"`, `"gWorldViewProj"`, `"gViewInv"` and `"FOV DEGREE"` to find who builds the matrices
(§1.2). b) Xref `"NuiSkeletonGetNextFrame"`/`"CNatal::Update"` for the address of `CNatal::Update` and of the library
function. c) Find who reads `m_bFakeNatalPad` and who decides "Normal (Controller)" (§2.5). *It is not yet known*
whether the game is single-pass or multi-pass, nor where the projection is.

**Stage 1 — Synthetic Kinect (immediate value, no VR).** A rexglue hook on `NuiInitialize`/hardware status/
`NuiSkeletonGetNextFrame`, or enabling `FakeNatalPad` if it works; feed it from mouse/gyro/controller. Verify that
the menu offers the Kinect modes and that the reticle follows the "hand". This is **also useful on a handheld** and is
a prerequisite for the Quest hands. *It is not known* whether the `RefineHands` path requires depth images.

**Stage 2 — Depth test on a flat screen.** Clip-space shift (option (b) of §1.4) on a single view, side-by-side
output so it can be viewed in any PC headset (SBS mode in Virtual Desktop/Steam Link [D]). Goal: **measure how much
breaks** (passes using `gViewInv`, HUD, shadows). If the result is acceptable, (c) is not needed.

**Stage 3 — Real PC VR with OpenXR on Linux/Windows (Quest 2 as a display by streaming: WiVRn/Monado on Linux, ALVR,
Steam Link/Virtual Desktop).** Replace the presenter with an OpenXR one (§3); stereo through (c) or (b)+; head = camera
rotation (needs Stage 0a); hands = Quest controllers → synthetic skeleton (Stage 1). *Documentation [D]:* WiVRn and
ALVR expose an OpenXR runtime to the PC; the app runs on the PC and the headset only displays. **This is the
recommended route.**

**Stage 4 — Native on Quest 2.** Port to Android ARM64 + Android OpenXR. Only if Stage 3 shows that the game is
**worth** it in VR, and even then with GPU and CPU unmeasured. Do not start here.

### What is NOT known (explicit)
1. Where the projection (FOV/near/far) and the camera are built, and how many passes there are per frame.
2. Addresses of the library functions `NuiInitialize`, `NuiSkeletonGetNextFrame`, `NuiImageStream*`, and of
   `CNatal::Update`; call sites of `XamShowNui*`.
3. What exact condition hides the Kinect modes in the menu, and whether `FakeNatalPad` works in the retail build.
4. The exact layout of the `NUI_SKELETON_FRAME` in use and whether `RefineHands` needs images.
5. How much breaks with a clip-space shift (position-reconstruction passes).
6. Performance on ARM64 and on the Adreno 650; availability of `geometryShader` and the rest on the headset.
7. None of this was executed; everything is static reading. This pass **could not use the shell** (see the top).

## Evidence consulted
`docs/FEASIBILITY.md`, `docs/analysis/boot-flow.md`, `docs/analysis/thread-exit.md`, `docs/analysis/gpu-startup.md`;
the import list, the list of imports that are stubs in rexglue, and the string dump of the executable;
`work/project/generated/default/eden_recomp.{10,60,76,…}.cpp`, `eden_register.cpp`; `work/rexglue-sdk`:
`CMakeLists.txt`, `CMakePresets.json`, `cmake/rexglue_target.cmake`, `src/xam/xam_nui.cpp`, `src/xam/xam_msg.cpp`,
`src/kernel/xam/xam_stub.cpp`, `src/gpu/xenos/vulkan/command_processor.cpp`,
`src/gpu/xenos/host/vulkan/{vulkan_presenter,vulkan_device,vulkan_instance,vulkan_settings,api}.*`,
`docs/site/pages/codegen/hooks.md`.
