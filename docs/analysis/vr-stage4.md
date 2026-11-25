# VR fork — stage 4: head, controllers and the road to the Meta Quest 2

2026-11-20 (branch `vr`). Follows `vr-stage3.md`. Everything was run on the build machine (RX 9070 XT) in
containers; the headset was **simulated** (Monado with its "remote" device, driven by a script).
**It was not tested with a physical Quest 2** (none was at hand). Neither the playable package nor the handheld was
touched.

Tags: **[V]** measured or observed in the cited run; **[I]** inferred; **[?]** not determined.

## Summary

1. **Chosen architecture:** the Quest 2 does not execute x86, so the game runs on the build machine and the headset
   is display and controllers over Wi-Fi with **WiVRn 26.9** (OpenXR server on top of Monado, open source; client in
   the Meta Store). Ruled out for now: a native port to Android ARM64 (large job, the headset's GPU is the
   bottleneck) and ALVR (requires SteamVR).
2. **Head tracking working** [V]: the scene camera receives the rotation, the position and the asymmetric projection
   of each eye, and the pair is submitted as a projection layer. On turning the head 25° the scene shifts to the
   opposite side and keeps filling the headset (runs 262, 265).
3. **Controllers working** [V]: no file. In menus the right controller is a laser pointer on the floating screen; in
   the level its direction is the aiming angle, the trigger fires, the left trigger gives rapid fire and both grips
   Euphoria. A full pass title → level → tutorial → shots with controllers only (run 266).
4. **The 2D reticle is repositioned per eye** [V]: it used to be drawn stuck to the center of the screen; it now
   lands on the real aiming point even when the head turns (run 265).
5. **Correction to stage 3** [V]: the eye mark never reached the SDK (the GPU library is loaded with `dlopen` and the
   weak symbol stayed null); the eye was assigned by parity, with a 50 % risk of coming out swapped. Fixed.
6. **WiVRn server built from source, and a start-up script** [V up to "listening"]: `bash tools/vr/quest.sh` on the
   build machine. Hardware encoding available (H.264/HEVC/AV1 through VAAPI). What happens after the headset
   connects **is not verified**.

## 1. How to play on the Quest 2 (steps for the player)

1. On the Quest 2: install **WiVRn** from the Meta Store (it must be version **26.9**, the same as the server).
   The headset must be on the same network as the build machine (5 GHz Wi-Fi preferred).
2. On the build machine: `bash tools/vr/quest.sh` (first `bash tools/vr/quest.sh --dry-run` to see what it will do).
   It opens port 9757 for the LAN only while it runs and closes it on exit (Ctrl+C).
3. In the WiVRn app on the headset: add the server manually with the IP the script prints (`<build-machine-ip>`) and,
   the first time, type the **PIN** the script shows. The pairing is saved in the script's WiVRn configuration
   directory.
4. On connecting, WiVRn launches the game. Menus: point the right controller at the button and hold for ≈ 3 s. Level:
   aim and right trigger; left trigger held = rapid fire; both grips = Euphoria.
5. If something fails: `work/build-xr/quest_wivrn.log` (server) and `work/build-xr/quest_game.log` (game; `[vr-xr]`
   lines).

Settings: `QUEST_HZ` (120 by default; 60 = 30 per eye), `QUEST_SCALE` (units per meter, 100), `QUEST_HEAD=0`
(floating screen always, in case of motion sickness), `QUEST_ENV="EDEN_VR_OPENXR_DIST=2.5 EDEN_VR_OPENXR_WIDTH=4"`.

## 2. Head → camera

### 2.1 SDK ↔ game link [V]
`vulkan_openxr.cpp` exports `rex_vr_state` (pose and field of view of each eye and pose/trigger/grip of each
controller, predicted for the next refresh with `xrLocateViews` / `xrSyncActions` on the headset thread) and
`rex_vr_mark_eye2` (at the end of the frame: which eye it is and with which view it was drawn). The hook looks them
up with `dlopen(…, RTLD_NOLOAD)` + `dlsym`.

**Why not a weak symbol:** `librexgpu-xenos-vulkan.so` is not among the executable's dependencies; the SDK opens it
with `dlopen` (local). In run 261 `rex_vr_state` was null. The same thing was happening to `rex_vr_mark_eye` in
stage 3: the pair was being assembled with the "alternate blindly" fallback.

### 2.2 Math [V in the image]
In the single scene caller (`lr = 0x829EDEBC`), after the original call:
- view: `V' = V · M`, with `M = [R ; −Rᵀ·t]` (row vectors), `R` from the eye's quaternion and
  `t = scale · (eye − initial_head_center)`. OpenXR and the game share axes (X right, Y up, −Z forward).
- projection: `P[10]`, `P[14]` (depth) are kept and `P[0] = 2/(tr−tl)`, `P[5] = 2/(tu−td)`,
  `P[8] = (tr+tl)/(tr−tl)`, `P[9] = (tu+td)/(tu−td)` are set from the tangents of the eye's field of view.
- The pair is submitted as an `XrCompositionLayerProjection` with the pose and field of view **it was drawn with**;
  the compositor corrects the delay.

Run 265 (Monado's remote headset, field of view −43/43/45/−45°): head forward → tunnel centered; 25° to the right →
the vanishing point moves left in both eyes; 20° up → it moves down; 20° of roll → the scene tilts. No black borders
(`r265_147s.png`, `r265_150s.png`, `r265_156s.png`, `r265_162s.png`).

### 2.3 Menu or level: when each layer is used [V]
Text, frames and buttons are 2D and do not go through the camera: with projection they would be stretched across the
whole field of view. So the mode is decided per pair:
- **floating screen** (quad layer, stage 3) if an interface camera was seen in the previous frame (`0x82DFF00C`
  title, `0x82DE494C`/`0x82C93910` selector, `0x82980CFC` tutorial and pause) or the scene view was the identity;
- **head-tracked projection** otherwise (flight and level).
`[vr-mode]` (with `EDEN_VR_TRACE=1`) logs it. Run 262: menu until frame ≈ 8500 (tutorial), projection afterwards.
`EDEN_VR_HEAD=2` forces projection always.

### 2.4 The reticle [V]
The sight is a separate object (virtual table `0x8237F560`; reached through
`manager(0x8336AE18)→method 7→method 17`). It stores its screen position at `obj+696/700` (method 9 sets it, 10 reads
it) and `sub_82D1A488` draws it. That position is computed for the original camera (45°, 16:9) and **does not depend
on the matrix** (`SightPOS` stayed at 636,364 when the head turned), whereas target lock-on does follow the world.
The hook, only during the draw, converts the pixel into a direction with the original projection, rotates it with
the head, projects it with the eye's projection and restores the value on exit.
Before: ring at the center of the eye and beams going elsewhere (`r262_150s.png`). After: ring over the targets
(`r265_150s.png`).

## 3. Controllers

`xrSyncActions` with an aim pose, trigger and grip per hand. Suggested profiles: `oculus/touch_controller`
(Quest 2), `valve/index_controller` (Monado's remote device) and `khr/simple_controller`. With
`EDEN_VR_CONTROLLERS=1`:

| Situation | What the controller does | How it is translated |
|---|---|---|
| Menu, tutorial (floating screen) | laser pointer from the right controller | intersection of the ray with the screen → pixel → hand position using the menu-cursor law (stage 2) |
| Level | direction of the right controller relative to forward | aiming angle, 133.33 °/m law (stage 3) |
| Right trigger | shot | one 20 cm pulse per press |
| Left trigger held | rapid fire, aiming with the left one | mode 1 |
| Both grips | Euphoria | mode 2 |

Run 266 (everything through simulated controllers, `xr_remote.py`): the pointer lands where requested (926,319 →
START; 349,439 → Yes; 639,360 → DIVE; 635,660 → tutorial ring), the level is reached and the tutorial closes;
9 `[vr-trigger]` (5 from the right trigger), `BUTTON Vulcan` with the left one and `BUTTON Bomb` with the grips
(`r266_143s.png`, `r266_166s.png`).

## 4. Test bench without a headset [V]

Monado's **remote** driver (TCP 4242) accepts the head pose and the state of both controllers.
`tools/vr/xr_remote.py` drives it from a timed script, and `tools/vr/xr_aim.py` converts a pixel of the floating
screen into the controller's angles.
```
XR_REMOTE="H1:0,0 D28:18.91,14.24 ... H148:25,0 D151:15,5,1" EDEN_VR_HEAD=1 EDEN_VR_CONTROLLERS=1 EDEN_VR_TRACE=1 \
  EDEN_VR_FAKENUI=1 EDEN_VR_SKELETON=1 EDEN_VR_PERIOD=1 bash tools/vr/run_xr.sh <N> f30 f100 f150
```
`H<sec>:right°,up°[,roll°[,x,y,z]]` head; `D`/`I<sec>:right°,up°[,trigger[,grip]]` controllers (right/left).
Scripts used: `tools/test/actions/acc260.txt`, `acc266.txt`.

## 5. WiVRn

- Official source `https://github.com/WiVRn/WiVRn`, tag `v26.9` (commit `bbc6e4cc`), checked out on the build
  machine. Its build downloads **sources** pinned by hash (Monado at revision `f037264d`, boost, etc.); no prebuilt
  binaries. Image `eden-recomp:wivrn` (`containers/wivrn.Dockerfile`), `bash tools/build/build_wivrn.sh` →
  `wivrn-server` (VAAPI, x264, PipeWire).
- The headset **client** is the Meta Store app: the player installs it. The APK was not built (it requires the
  Android SDK, which is binaries).
- `tools/vr/quest.sh` [V with `--test` and `--dry-run`]: lock, checks, port 9757 open only while it runs and only
  for the local subnet, `wivrn-server` inside the container (host network), pairing PIN on screen, and
  `application = quest_game.sh` so that the game starts when the headset connects. In the test the server ended up
  listening on `*:9757` and on exit no container or firewall rule was left behind.
- Encoding [V]: `vainfo` inside the container sees hardware H.264, HEVC and AV1 on the RX 9070 XT.
- **Unverified [?]**: the real headset connection, the game opening a session against WiVRn's Monado, latency,
  audio (PipeWire inside the container → WiVRn's device) and real Touch controllers.
- Attempt at a full test without a headset: the WiVRn client can be built for Linux and used as a fake headset, but
  it requires KTX-Software (not in Ubuntu; it has to be built separately with its tools). It did not fit in the time
  budget for this stage.

## 6. Scale [I]

`EDEN_VR_SCALE` = game units per meter; **100** by default (1 unit = 1 cm). It is an inference: the near plane is at
2 units and the interface layers at 200 units with 166 of visible height (2 m and 1.66 m at that scale, typical
dimensions for an interface). With 100, the eye separation comes from the headset (≈ 6.3 units), similar to the test
value 6 of the previous stages. Only with the headset on will it be known whether the world feels the right size.

## 7. Measurements

| Run | What | Result |
|---|---|---|
| 262 | head, 60 Hz | 60.0 fps, 30.0 pairs/s, 2042 pairs with projection |
| 265 | head + corrected reticle | 1944 pairs with projection |
| 266 | head + controllers, 60 Hz | 29.8 pairs/s; level reached with controllers only |
| 267, 269 | everything together at 120 Hz | **did not reach the level**: the script (calibrated at 60 Hz) rotates the selector too far and lands on a locked archive; in the selector, 97 – 103 fps and 49 – 51 pairs/s on the floating screen (`r267_100s.png`). Level with head tracking at 120 Hz: **not measured** |
| 268 | normal build (`work/build`) rebuilt with the same hooks, no variables | 0 `[vr` lines, `ldd` without `openxr`, normal menu; the package's `bin/eden` remained at sha256 `2d2e020f…` |

## 8. Known problems and what is missing

- **Nothing tested on a physical Quest 2.** It is the next step and needs someone with the headset (§1).
- **Faint duplicate ring** [V]: besides the corrected reticle, a weak ring remains at the old position
  (`r265_150s.png`); it is drawn by another routine that was not located.
- **2D interface in the level** (life ring, score, text): still stuck to the image and stretched to the headset's
  field of view. Separating it into its own layer is separate work.
- **At 120 Hz the measurement inside the level with head tracking is missing** (runs 267 and 269 did not get past
  the selector because of the script).
- **One eye per frame**: 60 pairs/s with the game at 120 (and at 120 some game sequences run faster); effects that
  only appear in one eye (rapid-fire beam).
- **Kinect depth preview box** visible in Euphoria (`r266_166s.png`): it is the sensor preview, with no data.
- **Resolution**: each eye is the game's 1280x720 image stretched to the field of view (≈ 86° x 90° in the test);
  the Quest 2 has 1832x1920 per eye. Raising the internal resolution remains to be tried.
- **Aim point versus the controller** [?]: the angle comes from the controller's direction relative to the forward
  axis of local space, not relative to the head; it remains to be seen with the headset on whether the reticle lands
  where the controller points.
- **Dwell selection**: menus are selected by holding the pointer for ≈ 3 s; the trigger does not confirm.
- The build machine's mDNS name stopped resolving to IPv4 during the session (≈ 10:25); work continued using its LAN
  IP address.

## 9. Runs
260 head without the link (0 pairs with projection) · 261 mode diagnosis · 262 head with the link through `dlsym` ·
263–264 locating the sight object · 265 corrected reticle · 266 everything through controllers · 267 and 269
integrated at 120 Hz (stays in the selector) · 268 normal build with no variables. Screenshots are not included in
the repository.
