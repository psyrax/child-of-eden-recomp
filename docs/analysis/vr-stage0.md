# VR fork — stage 0: where the camera comes in and where Kinect comes in

2026-11-20 (branch `vr`). Static analysis of the executable's PE image and of `work/project/generated/default`, using
the scripts in `tools/analysis/` inside a container (6 GB RAM, 4 CPUs, `python3 -I`). **The game was not run, and
neither the generated code nor the SDK was modified.**
Continues `vr-feasibility.md` (§5, stage 0), which was written without shell access.

Tags: **[V]** seen in the cited listing or dump; **[I]** inferred; **[?]** not determined.

## Summary

1. **The camera is separable on the CPU.** The previous analysis feared that only the combined matrix
   `gWorldViewProj` existed. That is not the case: the game stores world, view and projection separately and computes
   the combined ones afterwards. There is **one function that sets all three** (`sub_82FC09A8`, 26 calls) and another
   that sets only the world matrix (`sub_82FC0A48`, 228 calls). Replacing view and projection per eye can be done with
   a hook at a single point.
2. **The NUI library has concrete addresses** for initializing, enabling the skeleton, requesting a skeleton frame and
   opening/reading/releasing image streams. The skeleton is requested from the Kinect thread into a 2736-byte buffer.
3. **`FakeNatalPad` exists in the retail code**, off by default: it is byte `+80` of the Natal cursor object and, when
   enabled, it moves the cursor with the controller without going through the skeleton (§3).

## 1. Camera and matrices

### 1.1 Table of global shader parameters [V]
Static table at `0x83351C00`, 64 rows of 16 bytes `{name, id, 0, rows}`; `sub_82FC56D8` (render init) copies it to
`0x83394260`. The id is `type<<16 | index`:

| id | name | id | name |
|---|---|---|---|
| `0x80000` | `gWorld` | `0x80005` | `gProjInv` |
| `0x80001` | `gWorldInv` | `0x80006` | `gWorldView` |
| `0x80002` | `gView` | `0x80007` | `gWorldViewProj` |
| `0x80003` | `gViewInv` | `0x80008` | `gScreen` |
| `0x80004` | `gProj` | `0x80009`–`C` | `gMatrix_0..3` |

Type `0x2xxxx` = vectors (`gTime_Second`, lights, `gParam_*`, `gColor_*`, `gHitPos`…), `0x4000000` = textures.
`gViewProj` is **not** in the table: it is a parameter owned by a few shaders (a single reference, `sub_829D1158`).

### 1.2 The render object [V]
Global pointer at `0x83394224` (called `R` here). From the listings of `sub_82FBF750` (applies the parameters when
drawing) and `sub_82FBF0F0` (recomputes derived values):

- Matrices at `R + index*64`: world `+0`, world inverse `+64`, **view `+128`**, view inverse `+192`,
  **projection `+256`**, projection inverse `+320`, world·view `+384`, world·view·projection `+448`, screen `+512`.
- Vectors at `R + (index+52)*16`.
- "Dirty" flags at `R+2720` (derived values to recompute) and `R+2724`/`R+2728` (to upload to the GPU).
- `sub_82FBF0F0(R, index)` computes lazily: `gWorldView = world × view`, `gWorldViewProj = gWorldView ×
  projection`, and the inverses. That is, **the combined matrices are derived from the three basic ones at draw
  time**.
- Matrix stack at `R+2688`; `sub_82FC22F8` (63 calls) restores screen, projection and view from the stack.

### 1.3 The entry points [V]

| Function | What it does | Calls |
|---|---|---|
| **`sub_82FC09A8(r3=world, r4=view, r5=projection)`** | copies the three to `R+0`, `R+128`, `R+256`; marks everything dirty (`R+2720=234`, `R+2724=60`) | 26 direct + 1 pointer at `0x8290F478` |
| `sub_82FC0A48(r3=world)` | copies only the world matrix; `R+2720 \|= 194` | 228 |
| `sub_82FC22F8()` | pops screen/projection/view from the stack | 63 |
| `sub_82FBFAB0()` | uploads view/projection and vectors to the constant buffer | — |

Callers of `sub_82FC09A8`: `sub_829890B0` (4), `sub_82C58880` (3), `sub_82C5EB58` (3), `sub_82C93570` (3),
`sub_82C57158` (2), `sub_82D56A50` (2), and once each `sub_82933700`, `sub_82980BA0`, `sub_829EDDF8`,
`sub_82C25070`, `sub_82C8AF88`, `sub_82D0C390`, `sub_82D5F2E8`, `sub_82DE47F8`, `sub_82DFEEE0`.

### 1.4 What this means for stereo [I]
- A hook on `sub_82FC09A8` receives clean view and projection matrices: the view can be shifted per eye and, later,
  rotated with the head, and the headset's asymmetric projection can be set. This resolves the main objection of
  `vr-feasibility.md` §1.1 (only the combined matrix was visible there).
- Since the inverses and combined matrices are derived from the basic ones, the passes that reconstruct position with
  `gViewInv`/`gProjInv` receive values consistent with the eye.
- What does **not** change: the frame still has to be drawn twice (one eye per pass); the option of two command
  processors or of alternating the eye per frame remains open, now with the matrix identified.
- **[?]** Which of the 15 callers is the scene camera and which are 2D interface, shadow maps or full-screen passes.
  They must not all be shifted the same way. Who builds the perspective projection was not located either
  (`FOV DEGREE` is a label in a debug menu, with no direct code reference). This is resolved faster at run time: log
  in the hook the projection received from each caller during one frame.

## 2. Kinect: the `CNatal` class and the NUI library

Calls from the `CNatal` range (`0x82D51000`–`0x82D55800`, 90 functions) into the library. The identity of each one
comes from the error string the game prints right afterwards and from its arguments.

| Address | Function | Evidence |
|---|---|---|
| `0x83106DC8` | `NuiInitialize` | single call in `sub_82D54010` (`CNatal::Init`), followed by the strings `CNatal::Init:NuiInitialize:…` [V] |
| `0x830FB2E8` | `NuiSkeletonTrackingEnable(event, flags)` | thread `sub_82D531E8`; on failure prints "Error calling NuiSkeletonTrackingEnable" [V] |
| `0x830FAB70` | `NuiSkeletonTrackingDisable` | on thread exit and in `sub_82D515E0` [I] |
| **`0x830FB438`** | **`NuiSkeletonGetNextFrame(0, &frame)`** | thread `sub_82D531E8`, `r3=0`, `r4=` 2736-byte stack buffer; then `sub_82D52388` classifies the error [V] |
| `0x830FD820` | `NuiImageStreamOpen(type, resolution, flags, frames, event, &stream)` | 6 calls (color, depth, 80x60 depth) [V] |
| `0x830FCC68` | `NuiImageStreamGetNextFrame(stream, 0, &frame)` | 2 calls in the thread [V] |
| `0x830FCF90` | `NuiImageStreamReleaseFrame(stream, frame)` | 6 calls [V] |
| `0x830FE6B8` | `NuiCameraAdjustTilt` | `sub_82D517D8`, `sub_82D51828`, `sub_82D51908` [I] |
| `0x830FC290`, `0x830FFE10`, `0x830FC0C8/D0`, `0x830FACE8` | identity / enrollment | `sub_82D51E78` (`startIdentity`), `sub_82D51FC0`, `sub_82D52108`, `sub_82D521E0` [I] |
| `0x83104DD8` | hand refinement (ATG routine) | `sub_82D52E70`, `sub_82D54C20`; string `CNatal::ATG::RefineHands` in `sub_82D52848` [I] |

Game functions: `sub_82D54010` = `CNatal::Init`; `sub_82D531E8` = Kinect thread (creates 3 events, enables the
skeleton, opens 2 streams, and on each iteration requests depth, 80x60 depth and skeleton); `sub_82D52388` = error
classifier of `CNatal::Update`; `sub_82D52BB0`/`sub_82D52D10` = `EnableColorStream`/`EnableDepthStream`.

For stage 1 (synthetic Kinect) the minimum hooks are `0x83106DC8` (return success), `0x830FB2E8`, `0x830FB438`
(fill the frame) and the three image-stream ones. **[?]** The layout of the 2736 bytes of the skeleton frame was not
read from the binary (it matches the XDK's `NUI_SKELETON_FRAME` in size, to be confirmed field by field), nor whether
hand refinement tolerates empty depth images.

## 3. `FakeNatalPad`

**It exists and is alive in the retail code, off by default.**

- The Natal cursor/player class (constructor `sub_82D495F0`, vtable `0x823A55F8`) registers its variables in a debug
  menu "N A T A L Matrix" with `sub_82AB83F8(obj, category, name, &variable, value, 0)`. `m_bFakeNatalPad` is
  **byte `obj+80`**, initialized to 0 (`0x82D49AF0`); `m_fFakeNatalPadAngNoise/LR/Up/Down` are registered right
  after. [V]
- It is read by, among others: [V]
  - `sub_82D48608(obj, &x, &y)`: if `obj+80` is set, it takes the state of controller 0 (`sub_82FD16A8` on the object
    at `0x83395E60`) and computes the cursor position from it; otherwise it returns without doing anything.
  - `sub_82D48CE0`: with the flag set it replaces the cursor position with the one from `sub_82D48608`.
  - `sub_82D4B2B8` (large update, 622 lines): with the flag set it skips hand detection by skeleton
    (`sub_82D47788`) and leaves the tracking state as active (`obj+488 = 10`).
  - `sub_82D46B88` (debug draw): labels "Cursor:Angle" or "Cursor:Skeleton" depending on `obj+264`.
- **[I]** Setting `obj+80 = 1` with a hook would give the Kinect cursor driven by the controller, with no synthetic
  skeleton. It is the cheapest experiment for stage 1.
- **[?]** It is not known whether the debug menu is reachable in this build, nor whether with the flag set the game
  offers the Kinect modes in the main menu (that also depends on `NuiInitialize` and on the hardware notification).
  Nor whether it simulates one hand or both. Running it will answer this.

In passing: `FOV DEGREE` is a label of the same kind of menu, used in `sub_82C94688` (`0x82C949B0`), next to
`TARGET LENGTH`, `CURSOR RANGE`, `ROUND DEGREE`, `YAW DOT LIMIT`: parameters of a follow camera. [V for the reference,
I for the role]

## 4. New tool
`tools/analysis/xref_addr.py`: references through `lis`+`addi/ori` or `lis`+load/store pairs to an address or
constant, with a range option for structures and tables. This is how the parameter table and the pointer `R` were
found.

## 5. What is needed to continue
1. **Stage 1, first experiment:** set `obj+80` (FakeNatalPad) with a hook and see what the game offers.
   **If that is not enough (synthetic Kinect):** rexglue hooks on the 6 functions of §2; before that, confirm the
   layout of the skeleton frame by reading how `sub_82D531E8` consumes the buffer. Requires a build on the build
   machine.
2. **Classify the callers of `sub_82FC09A8`** with a logging hook (one frame of the level is enough).
3. **Depth test:** shift the view in that hook, alternating the eye per frame, side-by-side output.
