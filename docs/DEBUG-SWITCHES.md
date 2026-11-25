# Debug switches

Environment variables read by the game hooks (`game/src/eden_hooks.cpp`) and by our runtime patches
(`patches/sdk/`). All of them are off unless set; none is needed to play. `tools/test/run.sh` forwards them into
the test container.

## Game hooks

Everything is off unless the variable is set; without any of them only the unconditional fixes run (XMA null-context
guards, the video file-read fix, and the D3D wait sleep with its defaults).

### General

| Variable | Default | What it does |
|---|---|---|
| `EDEN_WAIT_SLEEP_US` | `200` | Microseconds each iteration of the game's D3D command-ring wait loop (`sub_82E5DF40`) sleeps once the spin phase is over. `0` keeps the game's original busy spin. |
| `EDEN_WAIT_SPIN_US` | `50` | Microseconds a D3D wait keeps spinning (original behavior) before it starts sleeping. |
| `EDEN_STUTTER_DIAG` | off | `<ms>`: for every frame longer than `<ms>` prints one `[eden] stutter` line splitting the frame into game work, swap time and time spent waiting for the GPU, with a monotonic timestamp (`mono=`). Only the thread that calls swap is counted. |
| `EDEN_VIDEO_TRACE` | off | `1`: traces the game's WMV player (`[eden] vtrace` lines): suspend/resume of its threads, flag changes with the guest return chain, codec routine errors, 64 KB reader failures, and frame requests that take more than 100 ms. |
| `EDEN_INVINCIBLE` | `0` | Debug cheat. `1`: restores player health to the maximum before every hit, so the hit is processed normally but health never reaches 0. `2` (or more): the hit is not processed at all. |
| `EDEN_AUTOAIM` | `0` | Debug/bot cheat. `1`: every frame moves the reticle to the lockable on-screen target closest to it and pushes the left stick (user 0) towards it; with no target on screen, steers towards the off-screen target with the most health. `2`: same, also considering targets flagged as not lockable (flag `0x08`). |
| `EDEN_AIM_TEST` | `0` | Diagnostic, only effective when `EDEN_AUTOAIM` is on (it replaces the auto-aim). `1`: moves the real cursor between the top and bottom screen edge every 600 calls and logs the view matrix every 100 calls. `2`: logs only. |
| `EDEN_DAMAGE` | `0` | Bot cheat, only evaluated when `EDEN_AUTOAIM` is on. `N` > 1: every hit on a big target (health > 1000, i.e. bosses) removes `N` times what the game removed (health never forced below 1). The `[eden] boss` log line is printed for such hits regardless of `N`. |

### VR fork

| Variable | Default | What it does |
|---|---|---|
| `EDEN_VR_CAMLOG` | off | `<file>`: writes a log of the calls to the camera setter `sub_82FC09A8` (matrices of one full frame every `EDEN_VR_CAMLOG_EVERY` frames, plus a per-caller call count summary). |
| `EDEN_VR_CAMLOG_EVERY` | `600` | Frame interval of the camera log (minimum 1). |
| `EDEN_VR_FAKEPAD` | off | `1`: sets `m_bFakeNatalPad` (object+80) to 1 when the Natal cursor constructor `sub_82D495F0` returns. |
| `EDEN_VR_SEP` | `0` | Eye separation in world units for the alternating-eye stereo (view matrix shifted by ± half of it). |
| `EDEN_VR_PERIOD` | `1` | Number of frames each eye is held before alternating (minimum 1). |
| `EDEN_VR_SBS` | off | `1`: squeezes each eye's projection into its half of the screen (side by side). |
| `EDEN_VR_ORTHO` | off | `1`: with `EDEN_VR_SBS`, also squeezes orthographic projections (interface). |
| `EDEN_VR_LR` | empty | Comma-separated hex list of caller return addresses; the `SEP`/`SBS` changes are applied only to camera calls from those callers (empty = all). |
| `EDEN_VR_OPENXR` | off | `1`: look up `rex_vr_mark_eye2` and `rex_vr_state` in the SDK's Vulkan GPU library (OpenXR build of the SDK) to drive the headset output. Required by `EDEN_VR_HEAD` and `EDEN_VR_CONTROLLERS`. |
| `EDEN_VR_HEAD` | `0` | `1`: the scene camera follows the headset (per-eye rotation, position and asymmetric projection) and the pair is submitted as a projection layer; menus, title and loading screens stay on the floating screen. `2`: projection always (for tests). Also re-projects the 2D reticle to match the headset view. |
| `EDEN_VR_SCALE` | `100` | Game units per meter, used for head and eye positions. |
| `EDEN_VR_HEAD_POS` | on | `0`: the camera does not follow head position (rotation and eye separation only). |
| `EDEN_VR_CONTROLLERS` | off | `1`: the hands of the synthetic skeleton come from the headset controllers: aim angle from controller direction, right trigger = shot, left trigger held = rapid fire, both grips = Euphoria; in menus the right controller is a laser pointer on the floating screen. |
| `EDEN_VR_FPS` | off | `1`: prints the real frame rate every 600 frames (`[vr-fps]`). |
| `EDEN_VR_NUILOG` | off | `1`: logs the first calls (and then every 2000th) to each hooked NUI (Kinect) function with caller and result (`[vr-nui]`). |
| `EDEN_VR_FAKENUI` | off | `1`: `NuiInitialize`, `NuiSkeletonTrackingEnable`, `NuiImageStreamOpen`, `NuiImageStreamReleaseFrame` and `NuiCameraAdjustTilt` return success without touching hardware; the "get next frame" calls return failure (`0x80004005`). Implies `EDEN_VR_NUILOG`. |
| `EDEN_VR_NATALACTIVE` | `0` | `<n>`: before each `CNatal::Update` (`sub_82D546A8`) writes `n` to the sensor's global state (`0x8337CCB0`; 1 = OK) so the game treats Kinect as active. Needs `EDEN_VR_FAKENUI=1`. |
| `EDEN_VR_SKELETON` | off | `1`: before each `CNatal::Update` publishes a synthetic tracked skeleton frame (30 per second) in the game's global skeleton buffers and sets the sensor state to 1; also answers player identification as user 0 and redirects `XamShowNuiDeviceSelectorUI` to `XamShowDeviceSelectorUI`. |
| `EDEN_VR_HANDS` | none | `<file>`: hand positions for the synthetic skeleton, re-read on every update. One line, either six floats `rx ry rz lx ly lz` (right hand, left hand; meters in Kinect space) or `a <right°> <up°> <trigger_count> <mode>` (aim angles; mode 0 = right hand, 1 = left hand, 2 = both hands up). Without a file (and without controllers) fixed default hands are used. |
| `EDEN_VR_NATALDIAG` | off | `1`: every 120 updates dumps the `CNatal` fields that decide whether a player is present (`[vr-diag]`), and logs every state change of the title's sign-in state machine (`[vr-session]`). |
| `EDEN_VR_STACK` | `0` | `<frame>`: on reaching that frame prints once the guest call chain at end of frame (`sub_82E658D0`) and at the scene camera (`sub_829EDDF8`) (`[vr-stack]`). |
| `EDEN_VR_TRACE` | off | `1`: prints the game's own (stubbed-out in retail) debug printf for the Kinect cursor class (`[vr-trace]`), the final reticle position (`[vr-sight]`), changes of the shot detector result (`[vr-shot]`) and the first 400 shot-commit calls (`[vr-trigger]`). When set to any value, also enables the periodic `[vr-mode]` (every 300 frames) and `[vr-ctrl]` (every 60 updates) lines if head tracking or controllers are on. |
| `EDEN_VR_TRACE_EVERY` | `30` | Sampling interval of the `[vr-trace]` and `[vr-sight]` lines (minimum 1). |

`EDEN_XMA_MAX` is mentioned in a comment but is not read by this file.

## Runtime patches

| Variable | What it does |
|---|---|
| `EDEN_GPU_DRAWS` | Set to anything: keeps the latest 8192 draws and dumps them to the log if the GPU device is lost. |
| `EDEN_GPU_SKIP` | `"hash,hash"`: does not draw anything that uses a vertex or pixel shader with one of those hashes. |
| `EDEN_GPU_VFETCH` | `hash`: prints the vertex fetch constants of the first draws that use that vertex shader. |
| `EDEN_GPU_CLEAR` | `"frames:mask"`: clears caches every N frames. Mask: 1 textures, 2 primitives (converted indices), 4 shared memory, 8 also forget what the GPU wrote. |
| `EDEN_GPU_WATCH` | Set to anything: every 30 frames checks pages marked as written by the GPU and reports the ones whose content changed without an invalidation (`eden watch:` lines). |
| `EDEN_UPLOAD_DIAG` | `<pages>`: logs shared-memory uploads of at least that many pages (`eden upload:` lines, up to 3000) and counts how many re-uploaded pages were identical to the previous upload. |
| `EDEN_XMA_MAX` | `<n>`: caps the number of XMA contexts, to exercise the exhaustion path. |
| `EDEN_XMA_DIAG` | Set to anything: when the number of XMA contexts in use reaches a new peak, lists the contexts that are allocated. |
| `EDEN_PAD_SCRIPT` | `"ms:button:duration_ms,..."` (milliseconds since SDL started; buttons `start a b x y up down left right`): presses buttons on the virtual test controller. Only with `--hid.sdl.gyro_test=true`. |
| `EDEN_VR_OPENXR` | `1`: enables the OpenXR output (SDK built with `-DREXGLUE_VR_OPENXR=ON`) and requests the Vulkan extensions the OpenXR runtime needs. |
| `EDEN_VR_OPENXR_DIST`, `EDEN_VR_OPENXR_WIDTH` | Distance and width, in meters, of the floating screen used for menus. |

The per-minute `diag: last minute:` line and the `diag: stutter of <N> ms` lines are always written to the log.
