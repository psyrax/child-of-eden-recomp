# Child of Eden — package for Linux x86_64 (CachyOS / ROG Ally)

Static recompilation, built locally from your own legally obtained copy of the game.
**Do not redistribute this package: it contains game code and game data.**

## Use
1. Copy the whole `child-of-eden/` directory to the machine (any path you can write to).
2. `./play.sh` (fullscreen, with the controller). Options: `--windowed`, `--keyboard`.
3. In Steam (gaming mode): "Add a Non-Steam Game" → choose `play.sh`.

## Settings
- `./play.sh --fps=30` limits the frame rate (useful on battery). The game runs natively at 60; at 30 it does not go
  into slow motion.
- `./play.sh --scale=2` doubles the internal resolution (experimental).
- `./play.sh --gyro` makes the controller's gyro move the reticle (it is added to the stick; the stick keeps working).
  `--gyro=2` doubles the sensitivity (1 = full stick deflection when turning at 90°/s), `--gyro-invert-x` /
  `--gyro-invert-y` flip the direction and `--gyro-roll` adds the sideways tilt. It can also be adjusted live in the
  settings menu (`hid.sdl.gyro*`).
  **Requirement:** the system has to present the controller with a motion sensor (on the ROG Ally, the controller
  service —InputPlumber or Handheld Daemon— has to emulate a DualSense or similar). If the game is launched from Steam
  with Steam Input enabled, the game sees an Xbox controller without a sensor: either disable Steam Input for this
  game, or use Steam Input's gyro ("gyro as joystick") instead of `--gyro`. The log (`logs/`) says `gyroscope present`
  or `absent` when the controller is detected.
  Tested only with a virtual controller. On the ROG Ally used in development it does not work yet: InputPlumber
  presents the controller without a sensor (`gyroscope absent`).
- `./play.sh --fxaa` enables FXAA (smooth edges; `--fxaa=extreme` for the high level). It can be combined with
  `--scale=2`, which also smooths by drawing at a higher resolution. Both run at 60 on the test PC.
- `./play.sh --hz=120` (**experimental**): on a 120 Hz display the game produces 120 real frames. Measured: it works
  and looks fine, but the start of the level arrived ~6 s earlier than at 60; it still has to be played to know whether
  the music stays in sync.
- **Do not turn vsync off** (`--gpu.vsync=false`): it yields 500+ fps but throws the tutorials out of place and makes
  events happen early.
- FSR upscaling: it is not in the runtime; on the ROG Ally it is enabled from gamescope (Steam quick menu → FSR scaling
  filter), or better use `--scale=2`, which really draws at a higher resolution.
- **Menu with the controller:** hold **START for ~1 s** and a short menu appears (in English by default; a "Language"
  row switches it): frames per second, image quality, anti-aliasing, mute, volume, aiming by moving the console (gyro),
  frame counter, advanced options and quit game. D-pad up/down to move, left/right or **A** to change, a tap of
  **START** to close. Changes are saved automatically (to `bin/eden.toml`); image changes apply the next time you open
  the game. The held START does not reach the game; a normal tap does (with a minimal delay). "Advanced options" opens
  the runtime's full technical menu. The game's own options (vibration, brightness, inverted controls) are still under
  "Options" inside the game.
- **Shader cache:** stored in `cache/`. The first time an effect appears there may be a stutter; in later sessions it
  should not happen again.
- With a keyboard connected: **F4** opens the runtime's settings menu (all options; "Save to config" saves them to
  `bin/eden.toml`) and **F3** shows the frames per second. That technical menu is operated with keyboard and mouse
  (or the touchscreen); the short menu opened by holding START is the one made for the controller.

## Making it look good in Steam
No artwork is shipped. `tools/package/steam_art.sh` (in the source repository) can derive library images from your
own screenshots into `steam/` (`cover.png`, `hero.png`, `logo.png`, `wide.png`, `icon.png`/`.ico`). In desktop mode: right-click the game → Manage → "Set custom artwork" for
the cover image (600x900); on the game's page, right-click the background → "Set Custom Background" (the background
image) and "Set Custom Logo" (the logo image). The wide image is for the recent games view and the icon image
(`.png`/`.ico`) for the icon (Properties → click the icon).

## What is inside
- `bin/eden` + `bin/*.so`: the recompiled game and the runtime (rexglue-sdk v0.11.0, SDL3 included).
- `assets/`: the game data (2.3 GB), read-only.
- `cache_base/` (optional): a precompiled shader cache; `play.sh` adds what is missing to `cache/` at launch.
- `user/`: saves (created automatically). `cache/`: your shader cache. `logs/`: logs.

## Requirements
- glibc ≥ 2.43 and a recent libstdc++ (an up-to-date CachyOS has them), Vulkan (`vulkan-icd-loader` + the GPU driver),
  X11 or Wayland, and PipeWire/PulseAudio for sound.

## Controls (controller mode)
Left stick = reticle · A = lock-on laser (hold and release) · X = burst fire · B = Euphoria / back · START = pause.

## Known state (2026-11-25)
On the development PC (RX 9070 XT, headless): all six archives completed at 60 fps with audio by the test bot using
debug cheats. On a ROG Ally (CachyOS): playtested with the physical controller and vibration; a 30 fps drop on battery
at the start of the second level was fixed and verified there. No level has been verified end to end by a person
without cheats. If something fails, keep `logs/` and note which screen it happened on.
