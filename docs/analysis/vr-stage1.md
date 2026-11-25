# VR fork — stage 1: test hooks at run time

2026-11-20 (branch `vr`). Follows `vr-stage0.md`. Everything was run on the build machine on the development build
(`work/build`), with headless gamescope at 1280x720. **The playable package was not touched (its `bin/eden` remained
at sha256 `6365f596…`), nor was the handheld.**

Tags: **[V]** measured or observed in the cited run; **[I]** inferred; **[?]** not determined.

## Summary

1. **The scene camera is a single caller** of `sub_82FC09A8`: `lr = 0x829EDEBC` (`sub_829EDDF8`), exactly once per
   frame, 45° vertical perspective, 16:9, right-handed, row vectors. The other callers seen are interface layers at a
   fixed depth (a plane at 200 units) and the camera of the level selector.
2. **The depth test works.** Shifting the view per eye and squeezing the projection to half the screen in that single
   hook produces a correct stereo pair of the 3D scene, with parallax, without glitches or crashes. What breaks is
   what was expected: 2D text and some particles do not go through the camera and stay full-screen.
3. **`FakeNatalPad` is not enough.** The flag gets set, but the game stays in "Normal (Controller)". Pretending that
   Kinect started (`NuiInitialize` returns success) is not enough either: the game runs the same and stays in
   controller mode. A **synthetic skeleton** is needed (or finding the game-mode variable) — left for stage 2.

## 1. How it was done

- SDK hooks (`REX_HOOK_RAW`, weak symbol; the original remains available as `__imp__sub_X`) in
  `work/project/src/eden_hooks.cpp`. Source: `game/src/eden_hooks.cpp`. It compiled and hooked on the first attempt
  (5 s incremental build with `tools/build/build.sh`).
- **Everything off by default**; enabled with environment variables: `EDEN_VR_CAMLOG`, `EDEN_VR_CAMLOG_EVERY`,
  `EDEN_VR_FAKEPAD`, `EDEN_VR_SEP`, `EDEN_VR_PERIOD`, `EDEN_VR_SBS`, `EDEN_VR_ORTHO`, `EDEN_VR_LR`, `EDEN_VR_NUILOG`,
  `EDEN_VR_FAKENUI` (described at the top of the source). Run 106 with no variables: 0 `[vr` lines, normal title and
  menu [V].
- End of frame: `sub_82E658D0`, the only game function that calls `VdSwap` [V].
- Launcher: `tools/vr/run_vr.sh` (a copy of `tools/test/run.sh` that passes the `EDEN_VR_*` variables into the
  container). Example:
  `EDEN_VR_CAMLOG=/b/vr_cam101.log EDEN_VR_CAMLOG_EVERY=300 bash tools/vr/run_vr.sh 101 f30 k33:Return k40:l k46:space k70:BackSpace f100 f128 f135`
- Rollback at the time: restore the original one-line hooks file and rebuild with `bash tools/build/build.sh`.

## 2. Camera callers, measured [V]

Run 101, 140 s (title → menu → selector → entry flight → Matrix level → tutorial), 8100 frames. Only 6 of the 26 call
sites showed up:

| `lr` | Function | Times per frame | When | Projection | View | Role |
|---|---|---|---|---|---|---|
| **`0x829EDEBC`** | `sub_829EDDF8` | **1, always** (300 out of every 300) | all the time | 45°, 16:9, near 2, far ≈10000 | identity on the title; moving camera in the level | **scene camera** |
| `0x82DFF00C` | `sub_82DFEEE0` | 1 | title and main menu | 45°, near 2 | translation (0,0,−200) | 3D interface layer |
| `0x82C93910` | `sub_82C93570` | ≈2 | level selector | 45°, near 0.2 | orbit at ≈180 units | selector spheres |
| `0x82C93728` | `sub_82C93570` | sporadic (8 in 300) | selector, during transitions | — | — | same |
| `0x82DE494C` | `sub_82DE47F8` | 1 | level selector | 45°, near 2 | (0,0,−200) | interface layer |
| `0x82980CFC` | `sub_82980BA0` | 1 | tutorials and pause | 45°, near 2 | (0,0,−200) | interface layer (life icon, etc.) |

- **There is no orthographic projection** in what was covered: the "3D" interface uses the same perspective with a
  plane at 200 units (visible height ≈166 units). 2D text and frames do not go through this function.
- Convention: `P[11] = −1`, `P[15] = 0`, view translation in elements 12–14: row vectors, right-handed.
- Scale: during the flight the camera advances ≈120 units per second.
- **[?]** The other 20 call sites (10 functions) were not exercised: other levels, bosses, results, Kinect Tuner.

## 3. Depth test [V]

Run 103: `EDEN_VR_SEP=6 EDEN_VR_SBS=1 EDEN_VR_PERIOD=60`. After the original call, the hook modifies, in the render
object (`*0x83394224`), the view (`+128`: `V[12] −= eye·sep/2`) and the projection (`+256`: `x' = x/2 + eye·w/2`),
for all perspective calls. The eye alternates every 60 frames; the pair is assembled from two consecutive screenshots
(left half of one, right half of the other), taking advantage of the tutorial freezing the scene.

Evidence (screenshots, not included in the repository): `r103_128s.png` and `r103_129s.png` (one eye each),
`vr_pair_128.png`, `vr_pair_100.png`, `vr_pair_044.png`, `vr_pair_037.png` (assembled pairs).

What works:
- The level's 3D scene (tunnel, enemies, glow) lands complete in each eye's half, with visible parallax between them.
- The full-screen passes (glow, compositing) do not visibly break.
- 60 fps unchanged, no new GPU warnings, no crashes in 135 s.

What breaks (and why it matters for the design):
- **2D text and frames** (tutorial, labels, buttons): they stay full-screen, crossing both eyes. They do not go
  through `sub_82FC09A8`. In VR they will have to be drawn on their own plane or captured at another stage.
- **Level-selector particles** (stars): not squeezed; they use another path (probably the shader-owned `gViewProj`
  of `sub_829D1158`, see stage 0 §1.1) [I].
- **Life icon:** the 3D model is squeezed and shifted, but its ring is 2D and stays in place: they become misaligned.
- **One eye per frame:** the game clears the frame, so when alternating only one eye is visible at a time (30 Hz per
  eye). For real VR the scene has to be drawn twice per frame or reprojected; the hook does not solve this.
- The separation of 6 units is a test value; the real scale (units per meter) is not established [?].

## 4. `FakeNatalPad` and Kinect start-up [V]

| Run | Options | Result |
|---|---|---|
| 102 | `EDEN_VR_FAKEPAD=1` | The constructor runs once (`obj=0x44E00570`), the flag ends up at 1. No visible change: same title, same menu, selector on "Normal (Controller)", level playable with the controller as always. |
| 104 | `EDEN_VR_NUILOG=1` | `NuiInitialize(0x4000001B, −1)` → **`0x8301000D`** (no sensor); `CNatal::Init` → `0x80004005`. Nothing else from NUI is called. |
| 105 | `EDEN_VR_FAKENUI=1 EDEN_VR_FAKEPAD=1` | `NuiInitialize` → 0, `CNatal::Init` → 0; the Kinect thread starts and calls `NuiSkeletonTrackingEnable(event 0xF8000070, 1)` and two `NuiImageStreamOpen` (type 0 and type 7). **It never requests frames** (it waits for events nobody signals). The game runs 128 s without failing, and **stays in "Normal (Controller)"**. |

Conclusions:
- The gate of `CNatal::Init` is only `NuiInitialize`; with simulated success everything else starts without touching
  hardware.
- The game mode does not depend on `FakeNatalPad` or on Kinect "existing": it is chosen according to who enters at the
  title screen. With START on the controller it stays in controller mode [I]. `FakeNatalPad` only replaces the cursor
  position **inside** Kinect mode (stage 0 §3), which was not reached.
- **[?]** Moving the cursor with the flag set in the Kinect Tuner (RS) and entering the debug menu were not tried.

## 5. How the thread consumes the skeleton frame (reading `sub_82D531E8`) [V except where noted]

Per iteration: it waits for an event (`sub_82E79E80`), and for each stream calls `NuiImageStreamGetNextFrame` (twice:
depth and 80x60 depth) and `NuiSkeletonGetNextFrame(0, stack+144)`; each result goes through `sub_82D52388` (error
classifier). If the skeleton arrived fine: it sets byte `0x8337CCAC = 1`, calls `sub_82D521E0(frame)` (identity) and
**only continues if both image frames are non-null** (`stack+88` and `stack+92`); then it copies and calls hand
refinement (`sub_82D52848`). At the end it releases the frames with `NuiImageStreamReleaseFrame`.

Proposed synthetic skeleton (stage 2):
1. `NuiInitialize`, `NuiSkeletonTrackingEnable`, `NuiImageStreamOpen` → success (already done), saving the event
   handles the game passes in (`r3` of `TrackingEnable`, 5th argument of `StreamOpen`).
2. A host thread signals those events at 30 Hz (with the SDK's kernel event API).
3. `NuiImageStreamGetNextFrame` delivers a synthetic depth frame (our own buffer in game memory; a far plane with a
   simple silhouette), and `ReleaseFrame` does nothing.
4. `NuiSkeletonGetNextFrame` fills the 2736 bytes: a "tracked" skeleton with the 20 joints, hands taken from the VR
   controllers (or from the gamepad, for testing without a headset).
5. **[?]** Unconfirmed: the field-by-field layout of the frame (it matches `NUI_SKELETON_FRAME` in size), and whether
   hand refinement (`0x83104DD8`, a library routine) tolerates synthetic depth. If it does not, `sub_82D52848` is
   replaced entirely by a version that writes the hands directly.

Cheaper alternative to explore first: locate the game-mode variable (what makes the selector say
"Normal (Controller)") and force it together with `FakeNatalPad`; that way the Kinect cursor would move with the
controller without a skeleton. Not searched for in this stage.

## 6. What comes next (stage 2, to be decided)

1. Kinect mode: look for the mode variable (cheap) and, if that is not enough, the synthetic skeleton of §5.
2. Real stereo: draw twice per frame (two passes of the game's render or of the SDK's command processor) and output
   to OpenXR; decide what to do with the 2D interface.
3. Cover more content with `EDEN_VR_CAMLOG` to classify the remaining callers.
