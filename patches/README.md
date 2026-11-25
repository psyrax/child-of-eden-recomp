# Patches

## `sdk/` — rexglue-sdk v0.11.0

Applied in order by `tools/build/setup_sdk.sh` onto a clean checkout of tag `v0.11.0`
(commit `a3e1d82678ca20d68d4837a8e9ee4652ff073745`). The files are split by area and do not overlap, so each one
also applies on its own. They have to be rebased when the SDK is updated.

| Patch | What it does |
|---|---|
| `0001-hid-gyro-aiming-and-scripted-pad` | Adds the controller's gyro as a velocity summed to the stick (`hid.sdl.gyro*`), and a scripted virtual pad for tests (`EDEN_PAD_SCRIPT`) |
| `0002-ui-controller-settings-menu` | A short settings menu driven by the controller (hold START), with autosave to the config file and seven languages |
| `0003-xma-audio-fixes` | Tolerates XMA voices without a context and buffers with an invalid packet index, which crashed or hung the audio decoder |
| `0004-gpu-fixes-and-diagnostics` | Invalidates GPU-side page state when physical memory is allocated (stale geometry after a level change), backs unassigned vertex streams (GPU hang with RADV), a null-safe string append, a register-info lookup table, and per-minute frame/stutter/upload diagnostics |
| `0005-vr-openxr-output` | Experimental OpenXR output, compiled only with `-DREXGLUE_VR_OPENXR=ON` and active only with `EDEN_VR_OPENXR=1` |
| `0006-gpu-memexport-lazy-readback` | `gpu.xenos.readback_memexport_lazy`: memexport readback that never waits for the GPU (the copy is picked up a few frames later). Needed because the game reads GPU-computed data on the CPU (projectile spawn points in Evolution) and the stock readback halves the frame rate |

The reasoning and measurements behind each change are in `docs/ARCHITECTURE.md` and `docs/DEVLOG.md`.

## `gamescope/`

`gamescope-pipewire-enter.patch` adds `pw_loop_enter`/`pw_loop_leave` around gamescope's PipeWire loop. Without
it, with PipeWire 1.6 the capture thread blocks and never delivers frames. It is applied to gamescope 3.16.20 by
`containers/capture-gamescope.Dockerfile` and is only needed to record video of test runs.
