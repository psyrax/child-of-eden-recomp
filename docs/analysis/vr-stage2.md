# VR fork — stage 2: Kinect mode without a Kinect, and two eyes per frame

2026-11-20 (branch `vr`). Follows `vr-stage1.md`. Static analysis in a container (6 GB RAM, 4 CPUs) and execution on
the build machine on the development build (`work/build`), headless gamescope at 1280x720. **Neither the playable
package nor the handheld was touched.**

Tags: **[V]** measured or observed in the cited run; **[I]** inferred; **[?]** not determined.

## Summary

1. **The game enters and plays in Kinect mode without a sensor.** With a synthetic skeleton published directly into
   the game's buffers, the title shows the Kinect cursor, the hand "presses" START, confirms the profile, loads the
   save, picks the Matrix archive on "Normal (Kinect)" and the level starts with the Kinect tutorial ("Move the
   reticle using your right hand"). All with `EDEN_VR_FAKENUI=1 EDEN_VR_SKELETON=1` and a text file holding the hand
   positions.
2. **The cheap "mode variable" does not exist as such.** The mode is decided by which device is used to act: picking
   the archive with the stick makes it "Normal (Controller)"; picking it with the hand, "Normal (Kinect)".
   `FakeNatalPad` was not needed.
3. Five pieces were needed, all in `eden_hooks.cpp` and off by default (§2).

## 1. What decides that "there is a Kinect" [V]

- `CNatal` object: global pointer at `0x8337CDF4` (`sub_82D558E8` returns it), virtual table at `0x823A80C8`
  (80 methods).
- **"Kinect active?"** = method 31, `sub_82D4E920`: `obj+96 != 0` (set by `Init` if `NuiInitialize` succeeded) and
  state `obj+440` in 1..3 or 10. It is the most used query in the game (24 of the 108 calls to the object).
- `obj+440` is copied by `CNatal::Update` (`sub_82D546A8`, method 2) every frame from the global **`0x8337CCB0`**,
  which is written by the thread's error classifier (`sub_82D52388`): 1 = the frame arrived fine, 2/3 = no new
  frame, 4..12 = sensor errors.
- Just forcing that global to 1 (run 201) already makes the title behave as with a sensor: depth preview box,
  "No player detected in front of the sensor", "RS Kinect Tuner", and on pressing START with the controller it asks
  "If you sign in using a device other than the Kinect, you will be unable to play the game using Kinect".

## 2. The five pieces of synthetic Kinect mode

| # | What the game asks for | Where | What the hook does |
|---|---|---|---|
| 1 | Sensor initialized | `NuiInitialize` `0x83106DC8`, `NuiSkeletonTrackingEnable`, `NuiImageStreamOpen` | return success (`EDEN_VR_FAKENUI`, stage 1) |
| 2 | Skeleton frames | global buffers filled by the thread `sub_82D531E8` | before each `Update` it writes a `NUI_SKELETON_FRAME` (`EDEN_VR_SKELETON`) |
| 3 | "No player" flag at zero | global byte `0x8333CA3C` (→ `obj+9832`) | set to 0 |
| 4 | Sensor tilt | `NuiCameraAdjustTilt` `0x830FE6B8` (state machine at `obj+10392`) | returns success; without this it stays on "Your sensor is starting up" |
| 5 | Identity and storage | `sub_82D4EFD8` (skeleton's profile) and `XamShowNuiDeviceSelectorUI` (`sub_82E7AB78`) | answers "user 0"; redirects to the normal selector `sub_82E7AF08` |

### 2.1 Where the skeleton is injected [V]
When the Kinect thread receives a frame, it leaves it in two double buffers and signals with a counter:
- refined (after `RefineHands`): `0x8337A120 + i*2736`; raw: `0x8337B6D0 + i*2736`; `i = *0x8337CC7C` (0 or 1);
- frame number at `0x8333CA40` (`Update` copies only if it changed relative to `obj+10272`); byte `0x8337CCAC = 1`.

`Update` copies the frame to `obj+576` (refined) and `obj+3312` (raw), transforms the joints and stores it in a
32-frame history (`obj+104`, `sub_82D46400`). The real thread stays asleep waiting for events nobody signals, so
there is no race. Injecting here avoids simulating events, depth streams and hand refinement (what stage 1 §5 had
planned): **none of that was needed**.

### 2.2 Frame layout, confirmed against the code [V]
`sub_82D45CA0` and `sub_82D516E8` read exactly the XDK's `NUI_SKELETON_FRAME` (big-endian):
timestamp `+0` (8), frame number `+8`, floor plane `+16`, gravity `+32`, and 6 skeletons of 448 bytes from
`+48`: state `+0` (2 = tracked), tracking id `+4`, enrollment `+8`, user `+12` (254 = none), position `+16`,
20 joints of 16 bytes from `+32`, their states from `+352`, quality flags `+432`.
The game uses the skeleton at index `*0x8337CC30` (0 by default).

### 2.3 Hand → cursor calibration [V]
Run 208, right hand at z = 1.75 m (body at 2.2 m, right shoulder at x = 0.20, y = 0.40):

| Hand (x, y) m | Cursor (px, 1280x720) |
|---|---|
| 0.20, 0.35 | 860, 145 |
| 0.20, 0.20 | 860, 435 |
| 0.10, 0.20 | 515, 435 |
| 0.30, 0.10 | 1200, 625 |
| 0.25, 0.25 | 1030, 335 |

Linear: `px = 860 + (x − 0.20)·3450`, `py = 435 − (y − 0.20)·1933`. The whole screen fits in a rectangle of
≈ 37 x 37 cm in front of the shoulder. With VR controllers it will be enough to scale the controller position to
that rectangle.

### 2.4 Signing in through Kinect [V]
State machine `sub_82D70488` (37 states, jump table at `0x823B3DC8`, state at `obj+16`, substate at `obj+76`,
"entered through Kinect" at `obj+88`). With the controller: 2 → 10 → 12 → 18 → 19 → 20 → 21. Through Kinect, after
pieces 4 and 5: 3 (tilt) → 4 (identity) → prompt "Is the gamer profile correct?" → 10 → 12 → 18 → 19 → 20 → 21
(run 220). Without the storage-selector redirect the game showed "The selected storage device is no longer
available", did not load the save and played the full introduction (≈ 4 min, impossible to skip with the controller
in Kinect mode).

### 2.5 Menus and level [V]
- Buttons are selected by keeping the hand over them for ≈ 3 s (START, Yes, OK, DIVE, Back).
- Archive selector: pointing at a side sphere brings it to the center, and it keeps rotating while the hand stays
  there (≈ 1.5 s per step). With 1 s on the right sphere, Matrix ends up in the center (run 223).
- **Moving the stick in the selector switches to "Normal (Controller)"** and the level starts in controller mode
  (run 222).
- Matrix level in Kinect mode (runs 223–225): Kinect tutorial, cursor and lock-on marks visible.

## 3. How to use it

```
EDEN_VR_FAKENUI=1 EDEN_VR_SKELETON=1 EDEN_VR_HANDS=/b/vr_hands.txt bash tools/vr/run_vr.sh <N> <actions>
```
- `EDEN_VR_HANDS`: a file with `rx ry rz lx ly lz` (right and left hand, meters, Kinect space: x toward the player's
  right, y up, z = distance to the sensor). It is re-read every frame. **It is the entry point for the VR
  controllers**: whoever has the poses just writes there (or, later, calls the same function).
- New action in `tools/test/steps.sh`: `m<sec>:rx,ry,rz,lx,ly,lz`.
- `EDEN_VR_NATALDIAG=1`: dumps the `CNatal` state every 120 frames and the transitions of the sign-in state machine.
- Sequence tested up to the level (run 223): `m28:0.219,0.26,1.75,…` (START) `m36:0.052,0.198,…` (Yes)
  `m52:0.278,0.27,…` + `m53:` away (rotate one step) `m57:0.136,0.239,…` (DIVE).

### 2.6 Inside the level [V except where noted]
- Run 226: tutorial closed with **B on the controller** (the controller stays alive in Kinect mode for buttons; what
  changes the mode is picking the archive with the stick). The level continues in Kinect mode: large Kinect reticle,
  lock-on marks and laser lines over the targets (`r226_156s.png`, `r226_165s.png`).
- **[?] The tutorial does not close with the hand:** 30 s with the cursor over "Return to Game" was not enough
  (run 225), although the same gesture does select START, Yes, OK, DIVE and Back in the menus. The cause was not
  investigated.
- **[?] Reticle calibration in the level:** it moved much less than the menu cursor for the same hand displacements
  (≈ 7 px between two positions 7 cm apart). Inside the level the game uses another law (stage 0 saw two modes,
  "Cursor:Angle" and "Cursor:Skeleton", at `obj+264` of the cursor). It remains to be measured.
- **[?] Firing by gesture:** the "flick" was simulated by bringing the hand 35 cm closer for 1 s. After the gesture a
  target can be seen being purified (`r226_165s.png`), but it was not counted with a game counter; the one-frame jump
  may be too abrupt or too slow compared with the real gesture.
- The left hand (second weapon) and the two-hand gestures (Euphoria) were not tested.

## 4. Part B: the two eyes

### 4.1 Where a frame comes from [V]
Call chain dumped at run time (`EDEN_VR_STACK=8400`, run 226):
- End of frame: `main` (`sub_82FB7B68`) → loop `sub_82FB8C58` → `0x82FB8E64` (method 7 of the application object) →
  `sub_82E65F58` → `sub_82E658D0` (`VdSwap`).
- Scene camera: the same loop, **one call earlier** (`0x82FB8E54`, method 2 of the task manager), descends through a
  recursive task tree (`sub_82FC6670`/`sub_82FC6B28`, five levels) down to `sub_82D27128` → `sub_829EDDF8`.

That is: per frame the main loop walks the task tree **only once** (each task updates its logic and emits its
drawing there) and then presents. **There is no separable "draw the scene" function** that could be called twice:
repeating the walk would also repeat the logic. Option (1) considered for this stage (running the game's render
twice per frame) is ruled out by this evidence; option (2) (duplicating in the SDK's command processor) runs into the
fact that each draw uploads its `gWorldViewProj` already combined on the CPU (stage 0 §1.2), so there is no single
point where the eye can be switched there either.

### 4.2 What does work: one eye per frame, at 120 [V]
Runs 231 and 232 (Matrix level, `EDEN_VR_SEP=6 EDEN_VR_SBS=1 EDEN_VR_PERIOD=1 EDEN_VR_FPS=1`):

| `--ui.video_mode_refresh_rate` | Measured fps (every 600 frames) | Per eye |
|---|---|---|
| 60 | 59.5 – 60.0 | 30 |
| 120 | 117.4 – 120.0 | **≈ 60** |

At 120 the game produces 120 real frames alternating the eye, and the hook costs nothing measurable (on the build
machine's GPU). Known limitation of 120 mode (not VR-related): some sequences run faster.

### 4.3 Proposed design for headset output (part C) [I]
1. **Alternating eye:** each game frame is one eye; the camera hook already shifts the view. In VR it is not squeezed
   to half the screen: each eye is drawn at full resolution with the headset's asymmetric projection.
2. **Hook into the SDK:** at presentation (where the frame currently goes to the `VulkanPresenter`), the even frame
   is copied to the left-eye image and the odd one to the right-eye image of an `XrSwapchain`; `xrEndFrame` is
   submitted every two game frames. The head pose (`xrLocateViews`) is read once per pair and enters the camera hook
   as rotation and translation of the view.
3. **Hands:** the controller poses are written where `EDEN_VR_HANDS` is read today (§3), scaled to the ≈ 37 cm
   rectangle of §2.3.
4. **2D interface** (text, frames, life ring; stage 1 §3): it does not go through the camera, so it would come out
   duplicated without parallax (at "infinite" distance). Acceptable for a first image; separating it is separate
   work.
5. **Unmeasured risks [?]:** 8 ms offset between eyes on fast objects (partly corrected by the headset's
   reprojection); where it runs (Quest 2 does not execute x86: it would need a PC with a cable link/ALVR, or porting
   the runtime to ARM64); the units/meter scale for the eye separation.

## 5. What was left unverified
- Closing the tutorial with the hand, reticle calibration in the level, firing by gesture, left hand (§2.6).
- A full level in Kinect mode; the rest of the menus (options, Kinect Tuner).
- Nothing of OpenXR was compiled or run: §4.3 is design.
- The effect on the development build's save after playing in Kinect mode (the package and the handheld were not
  touched).

## 6. Runs
201 forced state · 202–203 `FakeNatalPad` and BACK on the title · 204–207 skeleton and flags · 208 calibration ·
209–215 sign-in · 216–219 introduction and menus without a save · 220 save loaded · 221–223 archive selector ·
224–226 level in Kinect mode · 231–232 fps alternating the eye · 233 no variables (0 `[vr` lines, normal menu;
the package's `bin/eden` remained at sha256 `6365f596…`). Screenshots `r2NN_*.png` are not included in the repository.
