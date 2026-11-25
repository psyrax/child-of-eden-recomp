# VR fork — stage 3: playing with the hands and first image through OpenXR

2026-11-20 (branch `vr`). Follows `vr-stage2.md`. Static analysis in a container (6 GB RAM, 4 CPUs) and execution on
the build machine (RX 9070 XT, headless gamescope at 1280x720).
**Neither the playable package nor the handheld was touched** (the package's `bin/eden` remained at sha256
`2d2e020f…`, timestamp 03:22).

Tags: **[V]** measured or observed in the cited run; **[I]** inferred; **[?]** not determined.

## Summary

1. **The reticle inside the level is an aiming angle, not a screen position** [V]. It comes from the position of the
   hand relative to the torso, at 133.3 ° per meter for the synthetic skeleton, and the camera turns behind the sight
   (which is why in stage 2 it "barely moved": the sight returns to the center while the view shifts).
2. **Firing by gesture is confirmed with a counter** [V]: the active hand advances ≥ 11 cm toward the sensor within
   120 ms. Pulling it back does not fire. Left hand = rapid fire; both hands up = Euphoria. All checked against the
   game's own traces.
3. **The tutorial does close with the hand** [V]: the target is the ring icon (635, 660 px), not the text.
4. **"VR-controller-style" input** [V]: the hook accepts `a <right°> <up°> <n_trigger> <mode>` and translates it into
   the skeleton. Requesting ±20°/±40° gives exactly that on the game's sight; 5 triggers, 5 shots.
5. **First image through OpenXR** [V]: the game opens an OpenXR session, submits the stereo pair (one `XrSwapchain`
   per eye, 1280x720) and Monado's compositor shows it with its simulated headset. At 120 Hz: **120 fps from the
   game, 60 pairs/s submitted**. There is still no physical headset and no head tracking into the camera.

## 1. The Kinect cursor class, with names [V]

The constructor `sub_82D495F0` registers more than a hundred variables in the debug menu "N A T A L Matrix"
(`sub_82AB81E0` floats, `sub_82AB83F8` booleans, `sub_82AB7FD0` integers). With a symbolic emulator of the listing,
name → offset → default value was obtained. The ones that matter:

| Field | `obj+` | Value | Role |
|---|---|---|---|
| `ShotHandZ` | 368 | 1 | fire by hand advance |
| `ShotThresholdZ` | 372 | 0.11 | meters of advance that fire |
| `ShotThresholdTime` | 364 | 120 | window in ms |
| `ShotHandX` / `ShotHandY` | 369 / 370 | 0 / 0 | fire by lateral movement (off) |
| `ShotHandZByAngle` | 612 | 0 | elbow-angle variant (off) |
| `WaitCountShot` | 236 | 0.14 | wait between shots |
| `DoubleHand` | 2272 | 1 | two hands with different roles |
| `m_fSelectHandMargen` | 2856 | 0.1 | hysteresis for switching the active hand |
| `HandUpThreshold` | 2228 | 0.5 | hands up (Euphoria) |
| `SightMoveDistanceX/Y` | 500 / 504 | 1000 / 340 | limits of the sight on screen |
| `m_posFixedRate`, `m_minPosRate` | 2848 / 2852 | 0.9 / 0.01 | position smoothing |
| `m_bFakeNatalPad` | 80 | 0 | cursor with the controller (stage 0) |

The full list comes from `tools/analysis/debug_fields.py` run on the listing produced by
`tools/analysis/show_func.sh sub_82D495F0`.

**The game's debug trace is still there.** `sub_829B1FF0` is a "printf" emptied in the retail build (just `blr`),
but the calls with their format strings remained. With `EDEN_VR_TRACE=1` the hook prints the format and arguments of
those coming from the cursor class: `SightPOS:%f %f` (sight in pixels), `sightANG`/`fSightAngle`/`deg` (angle),
`BUTTON Shot` / `BUTTON Vulcan` / `BUTTON Bomb`, `RightFront:%s LeftFront:%s`, `TRIGGER BOMB END`. That gives
counters that do not depend on the image.

## 2. Reticle law in the level [V]

`sub_82D48CE0(obj, skeleton = obj+624, joint)` (joints at `skeleton + 304 + 16·k`):
- torso `T` = |head.y − spine.y|, smoothed;
- reference = (spine.x ± 0.3·T, spine.y + c·T); the sign depends on the hand;
- value = (hand.xy − reference) · K / T, smoothed, and from there to `sub_82D476F0` (final position).
  **It does not use z.**

Measured (runs 240 and 243, synthetic skeleton with T = 0.45 m, right hand):

| Hand x, y (m) | Sight (°) | | Hand x, y (m) | Sight (°) |
|---|---|---|---|---|
| 0.00, 0.30 | −18.00, −8.23 | | 0.20, 0.10 | 8.67, 18.43 |
| 0.20, 0.30 | 8.67, −8.23 | | 0.20, 0.20 | 8.67, 5.10 |
| 0.40, 0.30 | 35.33, −8.23 | | 0.20, 0.40 | 8.67, −21.57 |

`angle_x = 133.33·(x − 0.135)`, `angle_y = −133.33·(y − 0.2383)` (up is negative). That is, **K = 60 ° per torso
length**. The left hand uses the mirrored reference (x = −0.135) [V, run 244].

The on-screen sight (`SightPOS`) returns toward the center a few seconds after each movement while the view turns:
the angle is the aiming direction in the world and the camera follows it (`r240_154s.png` versus `r240_166s.png`).
For VR this is good news: a controller's direction converts directly into an angle, with no pixel calibration.

## 3. Firing, active hand and Euphoria [V]

- **Detector** `sub_82D47A10` (state `obj+408 = 1`): asks `CNatal` (method 9) for the displacement of each joint over
  the last `ShotThresholdTime` ms; if the z component of the active hand is ≥ `ShotThresholdZ`, it calls
  `sub_82D475A8(obj, 1)` and sets `obj+2372 = 1`, `obj+2376 = 11` (right hand).
- **Run 241** (counter `[vr-trigger]`, one per call to `sub_82D475A8` with `lr=82D4817C`):

| Right-hand gesture | Fires? |
|---|---|
| z 1.75 → 1.60 (15 cm toward the sensor, abruptly) | yes |
| z 1.75 → 1.50 (25 cm) | yes |
| z 1.60 → 1.75 (pull back) | no |
| z 1.75 → 1.90 (move away) | no; on returning to 1.75, yes |

- **Active hand** (`sub_82D47788`): a hand stops counting if the wrist is less than 20 cm in front of the body and
  30 cm to the sides, and below the elbow and the spine. If both count, the higher one wins, with 10 cm of
  hysteresis. With the right one down and the left one forward: `obj+488 = 6`, `BUTTON Vulcan` flag and the purple
  rapid fire on screen (`r242_159s.png`).
- **Both hands up** (y = 0.9 m): `BUTTON Bomb` once and `TRIGGER BOMB END`; Euphoria on screen (`r242_166s.png`).
- `BUTTON Shot` (flag 0x10) is set every frame while the right hand is active: it is equivalent to "holding A"
  (locking on to targets); the gesture is equivalent to releasing.

## 4. Tutorials [V]

- Tutorials pause the cursor class (`[vr-sight]` lines stop appearing); at least two appear in Matrix: the reticle
  one (≈ second 140) and "Player Life" (≈ second 175; [I] triggered by the first damage taken).
- They are closed by leaving the menu cursor over **the ring icon**, not over the text: hand at
  (0.1348, 0.0836, 1.75) → (635, 660) px; it closes in ≈ 3 s (run 241: open in `r241_139s.png`, closed in
  `r241_143s.png`). In stage 2 the text was targeted, which is why it did not respond.

## 5. Input by angle and trigger [V]

`EDEN_VR_HANDS` accepts a second format, intended for VR controllers:

```
a <right°> <up°> <n_trigger> <mode>      mode: 0 laser (right), 1 rapid fire (left), 2 Euphoria
```
The hook builds the skeleton with the law of §2 and, each time `n_trigger` changes, moves the hand 20 cm forward for
5 skeleton frames. In `tools/test/steps.sh`: `m<sec>:a,10,5,1,0`.

Run 243: requested ±20, ±40 in x and ±15, ±30 in y → `[vr-sight]` reports 20.00, 40.00, 15.01, 30.01; five counter
changes → five `[vr-trigger]`. Run 244: mode 1 → `e488=6` and `BUTTON Vulcan`; mode 2 → `BUTTON Bomb`.
Note: any change of the counter fires, including the first one if a stale file was left behind; `steps.sh` now
deletes it.

## 6. OpenXR: from the game to the headset

### 6.1 Test bench without a headset [V]
Monado 25.0.0 (Ubuntu 26.04 package) with its simulated headset runs on the build machine inside the container
(`containers/monado.Dockerfile`), on the RX 9070 XT. Its compositor opens a window with both eyes and
`gamescopectl screenshot` captures it. Two snags, both solved:
- `monado-service` requires a live standard input (`tail -f /dev/null | monado-service`);
- with gamescope's WSI layer its window ends up with no images and aborts (`Requested 0 command buffers`): the layer
  is disabled for it alone (`DISABLE_GAMESCOPE_WSI=1`).
Smoke test: `tools/vr/xr_test.sh 4 8 hello_xr -g Vulkan` → `xr4_b.png` (the sample cubes in both eyes).

### 6.2 Hook into the SDK [V]
The code is `vulkan_openxr.h/.cpp` plus a small set of hooks into the presenter; both are part of the SDK patch
series under `patches/`. It is only compiled with `-DREXGLUE_VR_OPENXR=ON` and only activated with
`EDEN_VR_OPENXR=1`.

- **Where:** `VulkanPresenter::DriverRefreshGuestOutput`, right after the game refreshes its output image
  (A2B10G10R10, in shader-read layout). Each refresh is one eye.
- **Which eye:** the game's end-of-frame hook calls `rex_vr_mark_eye()` (weak symbol: in the normal build it does not
  exist and nothing happens).
- **Two threads.** The GPU thread copies the eye to an intermediate image and publishes the pair; the headset thread
  keeps the pace of `xrWaitFrame` and submits the latest pair. Three slots (write / ready / read) so that neither
  waits for the other.
- **What is submitted:** two `XrCompositionLayerQuad` layers, one visible per eye: a 3.2 m stereo screen at 2 m
  (`EDEN_VR_OPENXR_WIDTH`, `EDEN_VR_OPENXR_DIST`). It is not yet a head-tracked projection.
- **Extensions:** the runtime requires `VK_KHR_external_{memory,semaphore,fence}_fd` and `image_format_list` on the
  device, and on the instance `VK_KHR_get_physical_device_properties2` and the `external_*_capabilities`
  **enabled by name** even though core 1.1 includes them: Monado asks for `vkGetPhysicalDeviceProperties2KHR` and, if
  the instance did not enable the extension, it gets a null pointer and the process dies inside
  `xrGetVulkanGraphicsDeviceKHR` (stack from gdb, run xr7; cause read in `oxr_vulkan.c` of Monado v25.0.0).

### 6.3 Measurements [V]

| Run | Design | Game (fps) | Pairs submitted/s |
|---|---|---|---|
| 250 | everything on the GPU thread, 120 Hz | 65 – 72 | ≈ 35 |
| 251 | dedicated headset thread, 120 Hz | **120.0** | **60.0** (all with a new pair) |
| 253 | dedicated thread, 60 Hz, Kinect mode | 59.7 – 60.0 | 29.6 – 29.9 new (60 refreshes) |

The `xrWaitFrame` wait on the GPU thread cost half the frame rate; with the separate thread it costs nothing
measurable.

**Run 253, everything together:** Kinect mode without a sensor + input by angle and trigger + alternating eye +
OpenXR. It reaches the level, closes the tutorial with the hand, fires (4 triggers + rapid fire + Euphoria in the
traces) and the simulated headset shows the pair (`r253_153s.png`, `r253_162s.png`). Title screen through OpenXR:
`xr9_b.png`.

### 6.4 How to use it
```
bash tools/build/build_xr.sh                                           # work/build-xr, image eden-recomp:build-xr
EDEN_VR_FAKENUI=1 EDEN_VR_SKELETON=1 EDEN_VR_HANDS=/b/vr_hands.txt EDEN_VR_SEP=6 EDEN_VR_PERIOD=1 \
  bash tools/vr/run_xr.sh <N> $(cat tools/test/actions/acc253.txt)     # screenshots = Monado's window
# (the action scripts of each run are in tools/test/actions/)
```
`EDEN_EXTRA="--ui.video_mode_refresh_rate=120"` for 60 pairs/s. `EDEN_VR_FPS=1` and the `[vr-xr]` headset lines give
the rate.

## 7. Known problems and what is missing

- **The virtual keyboard does not reach the game with Monado open** [V]: its window takes the focus in gamescope
  (run 252 stayed on the title). Hands from a file do not depend on focus. On a real headset that window will not
  exist.
- **Eye separation not calibrated** [V]: with `EDEN_VR_SEP=6` the eyes differ too much (`r253_153s.png`) and the life
  ring appears in different places. The units/meter scale is missing.
- **Effects that only appear in one eye** [V]: the rapid-fire beam shows up in only one eye (`r253_162s.png`); the
  introduction video arrives with one frame of offset between eyes. This is the cost of the alternating eye.
- **Gamma** [?]: the copy goes to a UNORM format to avoid re-encoding; tones still need to be compared against the
  normal output.
- **No head tracking** [I]: `xrLocateViews` is not used yet; the next step is to bring the pose into the camera hook
  (rotation and projection per eye) and move from a "floating screen" to a projection layer.
- **Real controllers** [I]: poses and triggers still have to be read (`xrSyncActions`) and written where the file
  comes in today.
- **Where it runs** [?]: still open (Quest 2 does not execute x86: PC with link/ALVR/WiVRn, or porting the runtime to
  ARM64). None of this was tested with a physical headset.
- The OpenXR output object is not destroyed on exit (its thread uses the device until the end); when the process is
  killed with Monado already closed, an `XR_ERROR_INSTANCE_LOST` shows up in the log.
- A full level in Kinect mode has still not been played.

## 8. Runs
240 hand sweep (reticle law) · 241 tutorial with the hand and firing gestures · 242 left hand and both hands up ·
243 input by angle and trigger · 244 modes 1 and 2 by angle (this run's log mixes two overlapping executions; the
cited lines appear in both) · xr2–xr4 Monado + `hello_xr` · xr5–xr8 crashes when creating the session · xr9 first
game image through OpenXR · 250 level with everything on the GPU thread · 251 dedicated thread at 120 Hz · 252
keyboard route (does not arrive: focus) · 253 integrated · 254 normal build with no variables (0 `[vr` lines, no
crash, `ldd` without `openxr`). Screenshots are not included in the repository.
