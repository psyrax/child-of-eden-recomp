# Development log

Reverse-chronological engineering log of the project (newest first), translated from the original Spanish notes.
It is a historical record: entries describe what was known at the time, including discarded hypotheses and mistakes.
Paths and script names were mapped to this repository's layout; commit hashes mentioned in entries refer to the
private development history and the local SDK working tree, and do not resolve here. Screenshots, videos and logs
cited as evidence are not published. For the current state see [ARCHITECTURE.md](ARCHITECTURE.md).

# 2026-11-24 (3): the Opus warning in video 530 is harmless

- No prior plan entry: this was a read-only diagnosis on the build machine, left over as a pending item.
- `ffmpeg -v warning -i video530.mkv -map 0:a -f null -` prints a single `Error parsing Opus packet header`; it also
  shows up with `ffprobe` alone (on opening the file). With `video530.mp4` (the delivered file) **no warning appears**,
  not even when decoding the full audio and video (exit code 0).
- The audio packets are identical in both containers: `ffmpeg -i <f> -map 0:a -c copy -f md5 -` gives
  `af38ae84bdb1b9d271902d038b83c665` for both. So there is no damaged packet; the warning comes from how the GStreamer
  `.mkv` presents the stream when it is opened.
- The decoded PCM differs by 672 bytes (168 stereo samples, 3.5 ms: 33,290,880 versus 33,291,552 bytes), which is the
  codec's initial trim handled differently by each container.
- Of the 8670 packets, 1118 are 3 bytes long (silence, DTX) and 7552 carry data.
- **Not determined:** which exact field of the `.mkv` triggers the warning. **Not verified yet:** nobody has watched or
  listened to the video being played back.
- Conclusion: use the `.mp4`; there is no need to record again.

# 2026-11-24 (2): all six levels with `clear_memory_page_state=false`, and real video with audio

## The other levels with the option off
- Runs on the build machine with the bot (`EDEN_DAMAGE=20 EDEN_INVINCIBLE=1 EDEN_AUTOAIM=1 BOT_SHOT=5
  EDEN_EXTRA="--app.cache_root=/b/cache_merged --gpu.xenos.clear_memory_page_state=false" bash tools/test/run.sh <N> …`;
  level selection is `k43:d` repeated: 2 = Beauty, 3 = Passion, 4 = Journey, 5 = Hope):

  | Run | Route (as seen in screenshots) | Duration | fps per minute | Worst frame | Upload MB/frame (min/median/max) | Crashes |
  |---|---|---|---|---|---|---|
  | 530 (video) | start of Beauty | 170 s | 60.0 | 18 ms | 0.26 | 0 |
  | 531 | full Beauty, then Matrix and Evolution (two laps) | 45 min | 60.0 ×43, 59.9 ×2 | 51 ms | 0.16 / 0.52 / 1.47 | 0 |
  | 532 | full Journey with credits, then Matrix | 45 min | 60.0 ×43, 59.9 ×1 | 51 ms | 0.33 / 0.78 / 1.37 | 0 |
  | 533 | full Hope, then Matrix | 30 min | 60.0 ×30 | 50 ms | 0.36 / 0.60 / 1.43 | 0 |
  | 534 | full Passion (results screen), then Evolution and Matrix | 25 min | 60.0 ×25 | 34 ms | 0.24 / 0.52 / 1.34 | 0 |

- **Geometry:** I reviewed one in every 6 screenshots of each run (130 + 130 + 86 + 71 thumbnails,
  `tools/test/sample_sheet.py`). I saw no giant polygons, missing models or black screens outside the fades. One contact
  sheet per run (the first of each, runs 531–534) was kept as evidence; contact sheets are not published.
- **White screenshots:** 0–5 per run; they also appear with the option on (474: 3, 502: 4, 504: 1). They are the
  level-change fade, not an effect of the option.
- **Limit of the review:** it is a visual inspection of 256 px thumbnails every ~20 s, with a bot that never plays the
  same way twice; there is no frame-by-frame comparison against the option being on. A small or brief defect may have
  escaped me.
- As a side effect this replaces the contaminated run 518: the wait hook holds for 45 minutes straight with no
  regression.
- The copy of `tools/test/steps.sh` on the build machine did not carry the option (the one in the repo did): synced
  with the repo's.
- **Plan versus what happened:** I expected run 531 to continue from Beauty into Passion like run 474 did; it went on to
  Matrix and Evolution, so I added run 534 going straight to Passion.

## Real video of the game with audio
- `work/build/video530.mp4` on the build machine (225 MB; original `video530.mkv`).
  `ffprobe`: H.264 1280x720, 10,440 frames in 174.0 s (a real 60.0 fps); Opus 48 kHz stereo, 8670 packets;
  `volumedetect`: mean −18.4 dB, max 0.0 dB. The game ran at 60.0 fps while it was being recorded.
- Command: the one above with
  `bash tools/test/run_video.sh 530 k33:Return k40:l k43:d k44:d f48 k49:space f63 b73-170`
  (image `eden-recomp:capture-gamescope`). Conversion to mp4:
  `ffmpeg -i video530.mkv -c copy -movflags +faststart video530.mp4` inside the image.
- **Not verified:** nobody has watched or listened to it being played back (measurements only). ffmpeg warns once
  "Error parsing Opus packet header" (one packet, not investigated). The video contains game content and is not
  published.

# 2026-11-24: fix for the 30 fps on battery verified on the ROG Ally

- The ROG Ally had suspended in the middle of the test (it did not hang: it had been on for 2 days). The test marker
  file (`test.env`) was left behind; it was deleted before anyone played (the only later log, `eden_039.log`, is the
  interrupted run). Save intact (checksum unchanged).
- `tools/handheld/update_handheld.sh` (previous files kept in `bin.prev-20261124-0049` and
  `play.sh.prev-20261124-0049`): the handheld's `play.sh` now passes `--gpu.xenos.clear_memory_page_state=false`.
- **Verified on battery** (`handheld_test.sh battery-fix 150`, 120 Hz, limit 60, discharging): minute 2 at **60.0 fps**,
  9 frames of 33 ms in the whole run (before: ~950 and 46 fps). Process at 68–74 % of one core.
- **Not verified:** the other levels with the option off, played by a person. Power draw is still 28–30 W on battery
  in that stretch; it was not worked on.

# 2026-11-22: real video with patched gamescope, FSR measured, ROG Ally updated, and the cause of the 30 fps on battery

## ROG Ally on battery at 30 fps when the second level starts — cause found, fix NOT verified on the handheld
- **Symptom (tester report):** the second level starts slow and then returns to 60; sometimes pausing fixes it.
- **Reproduction:**
  `KEYS="33:enter 40:l 43:d 49:space bot:73-140" bash tools/handheld/handheld_test.sh <label> 150 --hid.mnk_mode=true`
  (launches through Steam with a copy of the save, virtual keyboard via uinput). On battery: ~950 frames of 33 ms
  between s75 and s125 (46 fps in minute 2). On the charger: 60.0.
- **Ruled out by measurement:** the new build (the previous one, `bin.prev-20261122-0012`, does the same on battery: 880
  slow frames versus 807); the wait hook; gamescope's frame limit; present mode
  (`MESA_VK_WSI_PRESENT_MODE=mailbox`, no change); GPU clock; governor and EPP (already `performance`); the 25 W cap.
  The charger power caps (30/43/53 W) cannot be set on battery (`Invalid argument`, maximum 25/30/35).
  Not tested: display at 60 Hz on battery (I could not switch it live).
- **Profile on the handheld** (`stack_sampler.py`, `stack_sampler_user.py`): no thread is waiting on the GPU. The
  "GPU Commands" thread runs at 66 % (~22 ms per frame) and half of its samples are in
  `VulkanSharedMemory::UploadRanges` (a `memcpy`). Cores at 3.6 GHz on average on battery.
- **Measurement on the build machine** (new diagnostic, rexglue-sdk `e595229`, the shared-memory upload diagnostic
  patch; runs 525–527): in that stretch **47 MB per frame** are re-uploaded in 73 calls, and **99.7 % of the pages are
  identical** to the previous time. Cause: `gpu.xenos.clear_memory_page_state` (defaults to `true` in this SDK) leaves
  as valid, at the end of every frame, only the pages written by the GPU; everything else is copied again in the next
  frame.
- **Fix:** `--gpu.xenos.clear_memory_page_state=false` in `play.sh` and `steps.sh` (commit `78b8d64`; the `play.sh` of
  the package on the build machine updated, with the previous one kept alongside). Run 528: 0.31–0.37 MB per frame,
  60.0. Run 529 (the reproduction of the giant polygons from the level-change artifacts investigation: 5 min of Matrix,
  quit, Evolution): entry into Evolution is clean in the screenshots at 422–473 s, 0.3–0.9 MB per frame.
- **Not verified:** the handheld stopped responding (no ping) in the middle of the test run with the option, at 63 %
  battery; **the test marker file `~/Apps/child-of-eden/test.env` may have been left behind** (it makes the game start
  with the test copy of the save): it must be deleted before anyone plays. Still missing: `update_handheld.sh` and
  repeating the run on battery. Beauty, Passion, Journey and Hope were not tested with the option off either, and
  screenshots were not compared frame by frame against the option being on. The new diagnostic is in `work/build` but
  not in the package's `bin/`.
- **Plan versus what happened:** the request was to compare builds, and that test should have gone first; before it I
  spent the handheld's battery (it got down to 3 %) on loose hypotheses. The handheld's `play.sh` was edited in place
  (`test.env`, `EDEN_BIN_DIR`); the repo copy now matches.

## Real video — path solved, the game still has to be recorded
- gamescope 3.16.20 with PipeWire 1.6.2 stayed in "negotiating": `pw_loop_enter`/`pw_loop_leave` was missing. Image
  `eden-recomp:capture-gamescope` (`containers/capture-gamescope.Dockerfile`, patch
  `patches/gamescope/gamescope-pipewire-enter.patch`, source pinned in `VERSIONS.md`).
  `pipewiresrc target-object=gamescope`. Test with vkcube: H.264 1280x720, 681 frames in 11.35 s. The .mp4 of the game
  with audio is still missing (`tools/test/run_video.sh`). Commit `900e8e1`.
- Run 518 (end of Matrix with the hook): contaminated by simultaneous compilations; it has to be repeated.

## ROG Ally updated and FSR measured
- Handheld updated on 2026-11-22 00:12 with `update_handheld.sh` (previous files in `bin.prev-20261122-0012`).
- FSR on the build machine (runs 519–524, `tools/test/fsr_measure.sh`), all at 60.0; GPU/CPU in W: 1080p direct
  28.5/18.3; 720p+linear 28.5/17.4; 720p+FSR 30.5/17.6; FSR sharpness 0 29.5/17.4; NIS 29.5/19.4; internal scale 2
  52.3/18.0. Recommendation: no internal scale on the handheld; FSR optional. A comparison contact sheet was kept as
  evidence (not published).
- On the handheld, `mangoapp` was using 74 % of one core after 2.3 days powered on; a reboot cleared it.

# 2026-11-21 (10): performance round — the D3D wait no longer spins

- **Measured cause (run 505, baseline):** 62 % of all the process's CPU was the D3D wait loop on the main thread
  (`sub_82E5DF40` 40.6 %, `sub_82E58A00` 9.8 %, `__savegprlr_29`/`__restgprlr_29` 9.3 %, `sub_82E7A128` 2.0 %):
  `sub_82E58A00` waits for the GPU to advance the command ring by calling `sub_82E5DF40` (32 `db16cyc` and a 5 s hang
  detector) without ever yielding.
- **Fix:** hook on `sub_82E5DF40` (`game/src/eden_hooks.cpp`): it keeps the original iteration and, after 50 µs of
  spinning (`EDEN_WAIT_SPIN_US`), sleeps 200 µs per iteration (`EDEN_WAIT_SLEEP_US`; **`EDEN_WAIT_SLEEP_US=0` restores
  the original spin**). On by default.
- **Second change (SDK, commit `c07d24b`, the known-register table patch):** `CommandProcessor::WriteRegister` walked
  the ~3500-case switch of `GetRegisterInfo` on every write just for a warning (2.1 of 22.8 profile points, 9 % of the
  GPU thread in run 506); it now looks up a table. In run 508 it no longer appears in the profile; the effect on the
  GPU thread's % is within noise (13.6 → 11.7 %).
- **Before/after table** (Matrix with the bot up to s330, build machine, container with `-m 6g --cpus 4`; CPU = mean of
  18 `top -H` samples, sum of the 10 busiest threads; energy = RAPL of the CPU package over 60 s, **does not include
  the discrete GPU**; machine idle: 13.9 W):

  | Run | Configuration | fps (per minute) | Worst frame | Main thread | GPU thread | Thread sum | Package |
  |---|---|---|---|---|---|---|---|
  | 505 | before (binary `d7b6474`) | 60.0 / 60.0 / 59.9 / 60.0 / 60.0 | 18 ms (one minute 50) | 99.9 % | ~13 % | 140.4 % | — |
  | 506 | wait hook | 60.0 ×5 | 18 ms | ~14 % | ~14 % | 55.8 % | — |
  | 507 | new binary, `EDEN_WAIT_SLEEP_US=0` | 60.0 / 60.0 / 59.9 / 60.0 / 60.0 | 18 ms (one minute 50) | 99.8 % | 11.3 % | 138.0 % | 30.5 W |
  | 508 | hook + register table | 60.0 ×5 | 18 ms (one minute 36) | 13.6 % | 11.7 % | 52.6 % | 17.4 W |
  | 509 | same, at 120 Hz | 119.9 / 120.0 / 120.0 / 120.0 / 119.9 | 17–18 ms (one of 51) | 23.1 % | 22.8 % | 75.4 % | 22.1 W |

  Above idle, the game went from costing ~16.7 W to ~3.5 W of CPU. At 120 Hz the result is the same as in run 436
  from before the change (119.9–120.0, worst frame 17 ms).
- **The stutter that repeats in Matrix (≈169 s, frame ~10100–10160; 26–60 ms, once per run):** it appears the same with
  and without the hook (505, 507, 508, 510–517). Measured with the new diagnostic `EDEN_STUTTER_DIAG=<ms>` and three
  traces:
  - sometimes the time falls in the game's work (510: 41.7 ms of game; 517: 34.9) and sometimes in the wait for the GPU
    (514: 55.9 ms; 516: 38.6): it does not belong to a fixed thread;
  - **it is not pipelines** (0 compiled), **there are no long system calls** (`perf trace` of the whole process, run
    515: only the 16 ms vsync waits, regular; no `mmap`/`munmap`/`mprotect`), **there are no long locks on the main
    thread or the GPU thread** (517: zero `futex` calls over 5 ms on both);
  - in the 42 ms of run 516's stutter no thread is on CPU the whole time: GPU 5 ms, main 4 ms, and three game threads
    with 14.5, 13 and 8.8 ms.
  - **Conclusion (with its limit):** it is not the runtime being saturated or blocked; it points to the game waiting in
    short stretches for its own loader threads at an area change. **I did not identify the game routine** (my script
    did not extract the symbols from `perf script`); it remains a minor pending item.
- **Hypotheses that fell:** that the stutter was a large memory operation (there is no such call), and that
  `clear_memory_page_state` was expensive: `EnableAccessCallbacks` + `LockWriteWatches` add up to ~0.7 of 56 points.
  It was not touched.
- **Not attacked (it is real work, not waiting):** the game's audio thread (WMA decoding, 8–20 % of one core), the GPU
  thread (12–15 %).
- **New tools:** `tools/profile/profile_proc.sh` (profile of all threads), `tools/profile/profile_burst.sh` (what each
  thread was doing during a stutter, aligned with `mono=` in the log), `tools/profile/power_cpu.sh` (RAPL).
  `tools/test/run.sh` passes `EDEN_WAIT_*` and `EDEN_STUTTER_DIAG`.
- **Package on the build machine updated:** `work/package/child-of-eden/bin/eden` and `librexgpu-xenos-vulkan.so`;
  previous binaries kept in a `bin.prev-20261121-*` directory next to the package. Rollback: copy them back. Commit
  `69389e2` (`vr` and `main`).
- **Not verified:** the package launched with `play.sh` (the binaries are the same as in runs 510–517, but I did not
  run the package as such); the handheld (off: no ping at 22:30) — the saving should show there in battery and
  temperature, but it is not measured; other levels and bosses with the hook (only Matrix up to s330); audio not
  listened to.
- **Plan versus what happened:** the plan foresaw deciding after the baseline between `clear_memory_page_state`, other
  threads and stutters. The baseline showed that almost everything was the wait; the rest turned out small and the
  remaining time went into the Matrix stutter.

# 2026-11-21 (9): Hope finished by the bot; all six archives complete

- **Result:** run 504 on the build machine, no code changes (binary from `d7b6474`). Command:
  `EDEN_DAMAGE=20 EDEN_INVINCIBLE=1 EDEN_AUTOAIM=1 BOT_SHOT=5 EDEN_EXTRA="--app.cache_root=/b/cache_merged" bash tools/test/run.sh 504 k33:Return k40:l k43:d k44:d k45:d k46:d k47:d f48 k49:space f63 b73-1800`.
  Hope is one position to the right of Journey in the selector ("Hope — Challenge Mode (Controller)", second 48).
- **Observed:** the level runs from second ~75 to ~1297 (about 20 min) with no crashes or hangs. Second 1307: results,
  "Total Score 478740", four stars, notice "Achievement Unlocked — Hope Springs Eternal (30G)". Second 1311:
  "'17bit' Visual Effect has been unlocked". Second 1317: back at the selector; the bot enters Matrix and continues
  until the cutoff at second 1800. `run504.log`: 0 lines with crash/abort/segv/fatal and 0 occurrences of `0x80500001`.
- **With this the bot has finished all six archives:** Matrix, Evolution, Beauty, Passion, Journey and Hope.
- **Not verified:** any level without cheats or played by a person; Hope without `EDEN_DAMAGE` (I did not test whether
  it is needed); I did not review the 514 screenshots one by one (contact sheet sampled every ~30 s: no black frames or
  obvious artifacts; the white frame at second 1321 is the transition into Matrix); audio not listened to
  (`AUDIO=dummy`). The handheld is still off (no ping, night of 2026-11-21): it does not have the Journey fix.
- **Plan vs. done:** I expected to have to hunt down some failure specific to Hope; there was none on the first try.
- Evidence: 5 screenshot files from run 504 (not published).

# 2026-11-21 (8): Journey finished by the bot; the black screen in area 5 was a file read the game took for empty

- **Result:** run 502 (`EDEN_DAMAGE=20 EDEN_INVINCIBLE=1 EDEN_AUTOAIM=1`, 45 min): the area 5 video plays (seconds
  1087–1131), followed by the credits, the results and the notices "The Hope Archive has been unlocked" and
  "Hard Difficulty has been unlocked"; it returns to the selector and the bot enters Journey again. No crashes. That
  makes 5 levels: Matrix, Evolution, Beauty, Passion, Journey. **Hope is missing.**
- **Cause (measured, not assumed):**
  - 498: `obj+224/+228` are the flags of the two decoder threads; only `sub_82EE3780/37E8/38B8/3920` change them.
    The 2 is set by "stop" (`sub_82EE2670`) and, in the player that stays black, it is called by **the decoder thread
    itself** (chain `82EE3F2C 82EE34A4`) because `sub_82ED7D98` returned an error on the first sample. Only once in the
    whole run. With gdb on the stuck process: that decoder is the audio one (object at `P+48`).
  - 500: the internal error is `0x80500001` (`sub_82EDCB48` → `sub_82EDF1E0` returns 29 → `0x8000FFFF`). It is
    generated by `sub_82EE88F8` when the reader with a 64 KB cache (`sub_82ED8388`) delivers 0 bytes.
  - 501: the reader fails when asking for position `0x10000` (the second 64 KB block) from a game callback stream
    (`sub_8292A1C8`). The first block comes preloaded in memory; from the second on it reads from the file with
    `sub_8292A118`, which calls `ReadFile` (`sub_82E79550`) **without a bytes-read pointer** and only collects them
    with `GetOverlappedResult` if `ReadFile` answers "pending" (997) or end of file (38). In the runtime the read
    completes instantly, `ReadFile` answers success and `*bytes_read` stays at 0.
  - **Which video it is, unconfirmed:** of the 165 WMV files, `ffprobe` only finds audio packets in two, and in both
    the first one is past the 64 KB mark (`jny_a5_event.wmv` at 161674, `ubi_logo.wmv` at 202784); that points to
    `jny_a5_event.wmv`. But the player that failed in run 498 measured 256x256 (`+232/+236`) and `jny_a5_event.wmv` is
    640x480, so I do not consider it identified. What was measured is the mechanism, not the file. (The message of
    commit `d7b6474` overstates it.)
- **Fix:** hook `REX_HOOK_RAW(sub_8292A118)` in `game/src/eden_hooks.cpp`: after a successful read it stores the
  `InternalHigh` of the `OVERLAPPED` in `*bytes_read`. In run 502 it acted (bytes read 0 -> 65536) and the decoder did
  not stop anything again (0 occurrences of the chain `82EE3F2C 82EE34A4`, 0 reader-failure trace lines). Commit
  `d7b6474` on `vr` and `main`.
- **Hypotheses that fell:** the race between "stop" and startup (what I suspected at the beginning: there is no other
  thread, it is the decoder itself); and `XFileSectorInformation` (it is not involved).
- **Plan vs. what happened:** the plan was one run with the flag trace; it took five (498 to 502), going down one level
  per run. **Run 499 was wasted through a mistake of mine:** the trace's 600-line cap filled up with normal positive
  codes (`0x00500003`) and I also cut it at 1100 s, before the failure appeared.
- **Traces that remain** (inert without `EDEN_VIDEO_TRACE=1`): flags `+220/+224/+228` with the guest return chain,
  codec error returns and failures of the 64 KB reader. The temporary diagnostic I put in `NtReadFile`
  (`rexglue-sdk/src/kernel/xboxkrnl/xboxkrnl_io.cpp`) **was removed**; run 503 (final binary, 100 s) reaches the
  selector at 60 fps.
- **Package:** `work/package/child-of-eden/bin/` on the build machine updated from `work/build` (`eden` and
  `librexbase.so`, which also differed from the package; I did not investigate why). **The handheld was not updated:**
  `update_handheld.sh` reported that the handheld does not respond (offline). The package tar is still the previous
  one.
- **Not verified:** the fix on the handheld; `ubi_logo.wmv` (the game does not play it in the boot path the bot uses);
  Journey without `EDEN_DAMAGE`; that no other game system depends on the same `ReadFile` pattern.
- **Evidence:** three contact sheets from run 502 (area 5 video now plays; credits and Hope unlocked; Journey complete),
  not published; logs `work/build/run498.log` to `run503.log` on the build machine.

# 2026-11-21 (7): Journey with the bot: auto-aim that drives the stick, the EDEN_DAMAGE cheat, and an area 5 video that stays black (UNSOLVED)

- **Handheld updated:** `tools/handheld/update_handheld.sh` at 10:17; package checksum equal on the build machine and
  on the handheld; backup in `~/Apps/child-of-eden/bin.prev-20261121-1016`. It carries the Beauty fix (rexglue-sdk
  `01fb464`), the artifacts fix and the multilingual menu. A tester's playthrough is still missing.
- **Run 475 (Journey, 55 min):** no crashes, 60 fps, but the bot does not get past the first boss: health 9984 → ~7500.
- **Why it found no target (476):** new trace with the reason for each rejection. The boss is almost always off-screen
  (the off-screen counter), not "not lockable".
- **The view follows the cursor only if the stick moves it.** Writing `reticle+1460/1464` does not turn the view (478),
  nor does writing the device's real cursor (479, 480: the reticle copies it every frame from `dev->slot19()`, x at +4,
  y at +8, with `dev = sub_829202B0()->slot7()->slot8(0)`). With the stick held, the camera position does change
  (481: `pos.x` from +490 to −597 as the cursor goes from the bottom to the right; the cursor reaches ~1229 px and
  comes back on its own).
- **Auto-aim fix:** hook on `sub_8316E210` (wrapper of `XamInputGetState`) that replaces user 0's left stick while
  auto-aim asks for it (a request is valid for 150 ms). With a target on screen it requests a stick deflection
  proportional to its position; with no targets on screen, full deflection toward the target with the most health
  (which works if it ended up behind the camera). 482: target in 79 of 93 samples (475: 39 of 115).
- **Why it was still slow (483):** each laser takes 1 off the boss's 10,000, in batches of ~6 hits every ~165 frames.
  I do not know whether that pace is the original game's; there is no reference.
- **New cheat `EDEN_DAMAGE=N`** (off without the variable; `run.sh` already passes it): each hit on a target with
  health > 1000 removes N times what the game removed (it bottoms out at 1; the final blow is dealt by the game). With
  20 the first boss falls in ~4 min and the bot goes through the following areas (484, 485: flowers, whale,
  Matrix-like section).
- **UNSOLVED — black screen in Journey area 5** (484, 485, 486, 489, 490, 492, 494, 495; between seconds 985 and
  1756): after a cutscene the image stays fully black until the end, at 60 fps, with no crash or GPU loss.
  - The game is alive: `Return` opens the pause menu on top of the black (486).
  - Files open at that moment: `jny_a5_event.wmv` (640x480, 73 s, twice) and `jny_a5_af_bty.wmv` (256x256).
  - The title's intro video (same format, with WMA audio) plays in full (487, 493).
  - Stacks (485, 489): a worker thread inside `sub_82EE47E0` (the routine that requests a video's next frame) waiting
    for samples forever in the loop at `loc_82EE4A94` (vcall slot 44), with the player's threads suspended.
  - Trace (492, 495; `EDEN_VIDEO_TRACE=1`): it is a **new** player for a 256x256 video. On first start, the
    `sub_82EE3CF0` thread is suspended in the same millisecond it is resumed (lr `82EE3FBC`) with
    `obj+224 = obj+228 = 2`; in the ones that work those fields are 0 and that thread is suspended ~10 s later.
  - **Two fixes tried and discarded:** (a) treating as pending a `ResumeThread` that finds the thread awake (490: it
    did not trigger even once); (b) delaying the freshly resumed thread until startup finishes (494, 495: the black
    remained). Both removed from the code; only the trace remains.
  - Not checked: whether `EDEN_DAMAGE` causes it (the last bosses before the black do not die, they stay at ~9600 of
    10,000 and the section ends on time); what sets those fields to 2 (end of stream because of a failing read?);
    `XFileSectorInformation` is reported "unimplemented" 926 times per run and nobody has looked at whether it
    matters.
- **Plan vs. result:** the plan was to finish Journey and move on to Hope. Journey does not finish; Hope was not
  attempted.
- **My mistakes:** the watcher for run 484 got stuck in a loop (its `pgrep -f` was finding itself) and I did not report
  it in time; I named a "lost resume" as the cause before having the trace; the trace of run 494 came out empty because
  of a quote eaten by the shell (`*e == 1`).
- **Package:** no changes (the binaries in the package and on the handheld are those of the Beauty fix). The new work
  lives in `work/build` on the build machine and in `game/src/eden_hooks.cpp`.

# 2026-11-21 (6): Beauty hung the GPU; fixed. The bot finishes Beauty and Passion

- **Symptom:** on choosing Beauty (3rd level) the game crashed 6 s later, 2 out of 2 times (runs 464, 465). In the
  build machine's kernel log: `amdgpu ring gfx_0.0.0 timeout … Process eden … thread GPU Commands`; in the game,
  `vkQueueSubmit() failed (VK_ERROR_DEVICE_LOST)` and abort.
- **How it was narrowed down:** new diagnostic `EDEN_GPU_DRAWS=1` (dumps the last 8192 draws when the GPU is lost,
  466): no giant draws or tessellation; two shader pairs appeared for the first time 3–4 frames earlier.
  `EDEN_GPU_SKIP` (does not draw anything that uses a given shader): skipping both, it does not hang (468); skipping
  only `6B128D000AE933CE`, it does (469); skipping only `DB23C20E1EFC9546`, it does not (470). With
  `--gpu.vulkan.sparse_shared_memory=false` it does not hang either (471). `EDEN_GPU_VFETCH` (472): that shader uses
  three vertex streams and the third (`vf93`) arrives with type "invalid", address 0 and size 0.
- **Cause:** the game leaves that stream unassigned; with `allow_invalid_fetch_constants=true` the runtime accepted it
  but requested a 0-byte range, so those pages of the sparse shared-memory buffer were left without backing memory.
  Reading them from the shader hangs the GPU with RADV.
- **Fix:** rexglue-sdk `01fb464` (build machine); the unassigned-vertex-stream patch. In
  `VulkanCommandProcessor::IssueDraw`, if the constant has size 0, what the shader can reach is backed (vertices ×
  binding stride, minimum 4096 bytes, cap 16 MiB); new accessor `Shader::GetVertexBindingsEden()`. It warns once in
  the log that vertex stream 93 is unassigned and that 4096 bytes are backed from `00000000`.
- **Verified on the build machine:** 473 (Beauty loads, one minute of bot, 0 GPU losses; the model that used to hang it
  shows up) and **474, 45 min without a crash**: the bot finished **Beauty** (at 1300 s: 149,100 points, 2 stars,
  20:43.34, 95 % purified; achievement 9; "The Passion Archive has been unlocked"), entered **Passion** on its own and
  finished it (2087 s: 168,450 points, 2 stars, 12:35.48, 89 %; achievements 0A and 33; "The Journey Archive has been
  unlocked"), and then repeated Evolution. Frames: 44 minutes measured, all between 3587 and 3600 frames
  (59.8–60.0/s); longest stutter 165 ms. Evidence: screenshots of Beauty and Passion from that day (not published).
- **4 levels complete with the bot so far:** Matrix, Evolution, Beauty, Passion. Journey unlocked; run 475 attempts it
  (`k43:d k44:d k45:d k46:d k48:space`).
- **Package on the build machine updated** with these binaries (previous ones kept in a `bin.prev-20261121-*`
  directory).
- **Not verified:** the handheld (not responding; it has the package from 2026-11-20 23:17). It uses RADV just like the
  build machine, so Beauty can be expected to crash there with the old package; this is not confirmed. The selector
  shows "Stars Required 63/14" on the locked levels and I do not know how to read that counter.
- **Plan vs. result:** the plan was only to run Beauty; a runtime crash turned up that nobody had hit before, as
  anticipated. The architecture document was updated as planned (readback, artifacts, multilingual menu, bot and this
  fix).

# 2026-11-21 (5): artifacts after changing level, cause found and fixed

- **Short reproduction** (8 min, failed 6 out of 6 times: runs 451–456, 458): 5 min of Matrix with the bot, pause →
  Quit → Yes, Play → right → A; the first minute of Evolution comes out with giant polygons. With 35 s of Matrix it
  does not fail (450). Actions:
  `k33:Return k40:l k46:space b72-370 k375:Return k378:a k380:space k383:a k385:space k395:l k399:d k403:space b419-480`.
- **Ruled out by measurement:** memexport readback; `clear_memory_page_state` (it was already `true`); texture,
  primitive and shared-memory caches flushed every 120 frames (456, `EDEN_GPU_CLEAR=120:7`); the "memexport with no
  ranges" case (it does not happen even once, 458). Runs 446 and 452–455 do not count: `run.sh` was not passing
  `EDEN_GPU_*` into the container (fixed).
- **Narrowed down:** also invalidating the pages that are "valid and written by the GPU" leaves the entry clean (457,
  mask 15). The detector `EDEN_GPU_WATCH=1` (per-page fingerprint) showed, on loading Evolution, 100 of ~6500
  GPU-written pages (physical 17EF1000–1803F000) changed on the CPU side without notification (459).
- **Cause:** `SharedMemory` marks as valid and GPU-written pages that at that moment are not reserved in any physical
  heap; `PhysicalHeap::EnableAccessCallbacks` cannot watch them; when the next level reserves and writes them, nobody
  invalidates and the GPU draws with stale data.
- **Fix** (rexglue-sdk `2fc30fc`, the invalidate-on-allocation patch): `PhysicalHeap::NotifyAllocated` notifies the
  invalidation listeners at the end of `Alloc`, `AllocFixed` and `AllocRange`, whether or not the range is watched.
  The diagnostics `EDEN_GPU_CLEAR` and `EDEN_GPU_WATCH` remain, inactive without their variable.
- **Verified on the build machine:** 460 (detector on: clean entry, zero warnings), 461 (final binary, clean) and 462
  (40 min: Matrix, Matrix, Evolution; 36 minutes at 60.0 and 4 at 59.9, no crash, no polygons in what was reviewed up
  to 1659 s). Not verified: the handheld, the other levels and the cost on slow machines (no difference was measured
  on the build machine).
- `play.sh` and `steps.sh` no longer pass `clear_memory_page_state`. Package on the build machine updated (previous
  binaries kept in a `bin.prev-20261121-*` directory). **The handheld is still not updated** (not responding).
- New tool: `tools/test/contact_sheet.sh <run> <from_s> [n]` builds a contact sheet from the screenshots.

# 2026-11-21 (4): move on the build machine, an hour of bot, and three corrections

- **Move:** the working tree on the build machine now lives on an NVMe SSD (rsync verified: 47,786 files,
  17,955,479,012 bytes on both sides). The original was renamed (17 GB, not deleted). Cold data went to bulk storage:
  the three package `.tar` files and 772 screenshots from runs before 400. Runs 442–445 work from the new path.
- **Run 441:** one hour of bot, 60 minutes between 59.8 and 60.0 fps, no crash. It only alternates Matrix and
  Evolution. CPU: main thread at 99.8 % all the time (busy wait), GPU thread 13–34 %, GPU 29–50 %.
- **The bot can now choose a level:** in Archive Select (seconds 42–46) `k43:d` moves right; run 445 went straight into
  Evolution.
- **Correction 1 — the artifacts "fix" was no such thing:** `clear_memory_page_state` already defaults to `true` in
  `xenos_settings.h`; passing it in `play.sh` changes nothing. Run 435 was "clean" because of the window I looked at.
  In run 441 the entry into Evolution after Matrix comes out with giant polygons twice (628–671 s and 2901–2944 s),
  and there are reddish triangles in Matrix at 433–455 s. Evolution as the first level (run 445) comes out clean.
- **Correction 2 — level labels:** the first level of all the bot runs is Matrix (default cursor); several times I
  wrote "Evolution" for the first stretch.
- **Correction 3 — 120 Hz:** the conclusion "the game advances faster" does not hold: at 60 Hz Matrix lasted ~550 s in
  run 441 and ~890 s in run 422, and Evolution ~435 s versus ~1040 s. The duration depends on the bot. It remains
  unmeasured.
- **Real video, not achieved yet:** image `eden-recomp:capture` (`containers/capture.Dockerfile`) and
  `tools/test/run_video.sh` + the `VIDEO=pw` hook in `steps.sh`. Audio is recorded; video is not: `pipewiresrc` gives
  "target not found" (wireplumber does not link the `gamescope` node) and with a manual link
  (`pw-link gamescope:capture_1`) the stream stays paused without delivering frames.
- **Diagnosis in progress (level-change artifacts):** `EDEN_GPU_CLEAR="frames:mask"` in
  `vulkan/command_processor.cpp` (not committed yet) flushes the texture (1), primitive (2) and shared-memory (4)
  caches every N frames. Run 446 with `120:7`.

# 2026-11-21 (3): settings menu in several languages with a selector

- Requested feature; it had its own short design note. What was planned was done, with no scope changes.
- **rexglue-sdk** (build machine, local commit `dbc1898`; the menu-languages patch, applied after the controller-menu
  patch): setting `ui.language` (default `en`), table `kMenuTexts` in `src/ui/overlay/settings_overlay.cpp` with
  English, Spanish, French, German, Italian, Portuguese and Japanese, and a "Language" row under "Back to the game".
  `src/ui/imgui_host.cpp` adds a system Noto Sans CJK font if one exists.
- **Tested on the build machine** with a virtual controller (`EDEN_EXTRA="--hid.sdl.gyro_test=true"` +
  `EDEN_PAD_SCRIPT`):
  - 438: opens in English with nothing configured; with the d-pad it switches to Spanish, German and Japanese;
    `eden.toml` stores `language`.
  - 439: on reopening with `language = 'ja'` the menu comes up in Japanese.
  - 440: with no CJK font mounted, same stored `ja` → menu in English, and the selector skips Japanese (left from
    English gives Portuguese).
  - Screenshots kept as evidence (not published). French and Italian were not captured (same table).
- `tools/test/run.sh` accepts `DOCKER_EXTRA` (extra mounts, e.g. the system fonts).
- Package on the build machine updated (`bin/librexui.so`). **The handheld was not**: it was not responding. Once
  updated, its menu will come up in English until another language is chosen. Not verified: that CachyOS has the font
  in one of the searched paths.
- Out of scope: the advanced view, the messages of `play.sh`, automatic language detection.

# 2026-11-21 (2): test at 120 Hz with the bot (runs 436 and 437)

- The question was whether 120 fps could be tried again. Build machine, `GS_EXTRA="-r 120"`,
  `EDEN_EXTRA="--ui.video_mode_refresh_rate=120"`, readback off and `clear_memory_page_state=true`.
- **436** (11 min, Matrix): every minute at 119.9–120.0 fps, clean image, no crash.
- **437** (23 min, Matrix → selector → Evolution): 16 minutes at 120.0, worst minute 114.9, no crash. Second level
  clean except for two screenshots with flat lilac shapes when Evolution starts (849 s and 882 s); it was not
  clarified whether they are an artifact.
- **The game advances faster at 120 Hz:** Matrix ended around 785–815 s (at 60 Hz, 935–962 s) and Evolution reached
  the whale ~290 s after starting (at 60 Hz, ~940 s). Measured only from screenshots every 5 s and with the bot, which
  does not play the same way every time; the music was not listened to. It is not validated for playing.

# 2026-11-21: artifacts after finishing a level, solved with clear_memory_page_state

- **Tester report** (ROG Ally, 2026-11-20 23:35): first level perfect at 60.0 fps (`logs/eden_005.log`, 14 min); on
  returning to Archive Select, a huge beige triangle, a patch of noise and lines (from a Steam recording; frames kept
  as evidence, not published).
- **Reproduced on the build machine** with the bot (`BOT_SHOT=8`, `b72-1420`): after the first level, the selector and
  ALL of the second level come out with giant polygons. Run 433 (memexport readback off) and 434 (on): both with
  artifacts, so the readback is not the cause. It was already visible in runs 422 and 426, which I had noted down as
  "maybe art". Run 432 was useless (cutoff too short, my mistake).
- **Fix:** `--gpu.xenos.clear_memory_page_state=true` (at the end of every frame the runtime invalidates the
  shared-memory pages the GPU did not write and re-uploads them when used). Run 435: Evolution → results → selector →
  Matrix, all clean, 23 minutes at 59.9–60.0 fps. A single confirmation run.
- Made the default in `tools/package/play.sh` and `steps.sh`; the `play.sh` of the package on the build machine
  updated. **The handheld does NOT have it yet**: it was asleep when `update_handheld.sh` was attempted (around
  01:10).
- **Unsolved:** the underlying cause (some memory write that the page watch does not detect when a level is unloaded).
  The setting covers it up; I did not measure its cost on the handheld. The package tar was left with the previous
  `play.sh`.
- Two hypotheses of mine that fell, both of which I had already stated as findings: "it has nothing to do with the
  readback" and then "the readback makes it permanent"; run 434 ruled out the second.

# 2026-11-20 (night, 2): new package and ROG Ally updated

- **Package** `work/package/child-of-eden/` on the build machine rebuilt from `work/build/` (the 18:28 build):
  `bin/eden`, `play.sh` with `--gpu.xenos.readback_memexport=false`, `bin/merge_cache.py` and, for the first time,
  `cache_base/shaders/shareable/` (a copy of the merged shader cache in `work/build`: 278 shaders, 329 pipelines).
  Previous binaries kept in a `bin.prev-20261120-*` directory. A tar of the package was produced (it contains game
  code and data and must not be redistributed).
- **Package smoke test** (container `eden-recomp:run-audio`, headless gamescope, `play.sh --windowed --keyboard` on a
  copy with an empty cache): `merge_cache.py` added 329 pipelines and 278 shaders; first minute at 60.0 fps, worst
  frame 18 ms, 329 pipelines precompiled, 1 error line in the log. Boot and title only, not a level.
- **`tools/handheld/update_handheld.sh`** now also compares and copies `cache_base/` (it still does not touch `user/`,
  `cache/`, `logs/` or `bin/eden.toml`).
- **Handheld updated** (23:17): package checksum equal on both sides; previous files in
  `~/Apps/child-of-eden/bin.prev-20261120-2317` and `play.sh.prev-20261120-2317`. Rollback:
  `rm -r bin && mv bin.prev-20261120-2317 bin`. The game was not tested on the handheld (nothing was launched there).
- **The handheld crash at 11:57** (`logs/eden_004.log`, after 1 h 29 min of play): SIGSEGV in `sub_82E84E78+0x345` ←
  `sub_82EAD890` ← `sub_82EADA08` ← `sub_82EAC9F8` ← `sub_82E7D008`, a read of guest address 0. It is the third crash
  of the family of XMA voices without a context, the same as in run 425, already covered by the "phantom context"
  (commit `8ced426`), which ships in this package. Note: the crash report gives file offsets; for `nm` you have to add
  0x3000 (code segment: offset 0x6c5f60, address 0x6c8f60). In that session the handheld logged minutes at 31 to
  60 fps, consistent with the memexport readback.

# 2026-11-20: frame drops solved, debugging cheats, Matrix and Evolution complete

- **Cause of the 30 and 15 fps (and of the runs of 33 ms frames): the runtime's memexport readback.** The game computes
  particles on the GPU (memexport) and rexglue was copying the result back to memory, waiting for the GPU on every
  draw (`IssueDrawMemexportReadbackFullPath` → `vkWaitForFences`). Measured with `tools/profile/slow_stack.sh` (stack
  snapshots with gdb): 9 of 40 snapshots of the "GPU Commands" thread were there. `perf` did not see it because it is
  waiting, not CPU.
- **Fix:** `--gpu.xenos.readback_memexport=false` by default in `play.sh` and `steps.sh`. Run 430 (on): minutes at 48,
  30 and 15 fps. **Run 431 (off): 26 minutes, all at 60.0 fps**, the game advances and the particles are visible. Not
  verified: a frame-by-frame comparison of the image, and the test on the handheld.
- **Correction of a mistake of mine:** run 427 finished **Evolution**, not Matrix. Matrix was finished in run 422
  (achievement 7 "The Wireframe Web Expands", screenshot of run 422 at 962 s). That makes 2 complete levels.
- **XMA loop:** run 429 hung repeating "Invalid packet index" and wrote 90 GB of log. Deleted (`run429.log`,
  `logs/eden_131.log`; the beginnings were kept). Patch in `src/kernel/xma/context.cpp`: it discards the buffer and
  rate-limits the warning. **Not verified** (it did not happen again in 430 or 431).
- New diagnostic in the runtime: a per-minute `diag:` line for `WAIT_REG_MEM` waits. Patch: the XMA invalid-packet and
  wait-diagnostics patch (SDK on the build machine, local commit).
- Plan vs. done: the plan was to continue with Evolution; the frame rate was prioritized first, and that is what was
  done.
- Pending: a new package with all of this + `cache_base/`, and updating the handheld when it is on the network.
- Repo commit: `89607a0` (branch `vr`).

# 2026-11-20: VR fork, stage 4 — head, controllers and the path to the Quest 2 (branch `vr`)
- **Deliverable:** `docs/analysis/vr-stage4.md`. Package and handheld untouched. **Nothing was tested on the physical
  Quest 2**: everything was verified with Monado's script-driven "remote" headset.
- **Architecture decision (mine):** the game runs on the build machine and the Quest 2 is the display and controllers
  over Wi-Fi with WiVRn 26.9 (an OpenXR server on top of Monado). A native Android port and ALVR (which requires
  SteamVR) are discarded for now.
- **A. Head → camera (runs 262, 265):** `xrLocateViews` on the headset thread; the scene-camera hook
  (`lr=0x829EDEBC`) applies the eye's rotation, position and asymmetric projection, and the pair is submitted as a
  projection layer. In menus and tutorials (interface cameras `0x82DFF00C`, `0x82DE494C`, `0x82C93910`, `0x82980CFC`,
  or an identity view) the floating screen remains. `EDEN_VR_HEAD=1`, `EDEN_VR_SCALE`, `EDEN_VR_HEAD_POS`.
- **Reticle corrected per eye (run 265):** the 2D reticle (object with vtable `0x8237F560`, position at `obj+696/700`,
  drawn by `sub_82D1A488`) is repositioned only during the draw so that it lands on the real aim point.
- **B. Controllers (run 266):** `xrSyncActions` (Touch, Index and simple profiles). Menu = laser pointer on the floating
  screen; level = controller direction as the aim angle; right trigger shoots, left trigger held is rapid fire, both
  grips Euphoria. Title → level → tutorial → shots route done with simulated controllers only.
  `EDEN_VR_CONTROLLERS=1`.
- **Correction to stage 3:** the eye mark never reached the SDK (the GPU library is loaded with `dlopen`; the weak
  symbol stayed null) and the eye was being assigned by parity. The hook now looks the functions up with
  `dlopen(RTLD_NOLOAD)` + `dlsym`.
- **Test bench:** Monado's `remote` driver + `tools/vr/xr_remote.py` (scripted head and controllers, variable
  `XR_REMOTE` in `tools/vr/run_xr.sh`) and `tools/vr/xr_aim.py` (pixel → controller angles).
- **D. WiVRn:** source `v26.9` (`bbc6e4cc`) checked out on the build machine; image `eden-recomp:wivrn`
  (`containers/wivrn.Dockerfile`), `bash tools/build/build_wivrn.sh` → `wivrn-server` (VAAPI, x264, PipeWire). Script
  `tools/vr/quest.sh` (`--dry-run`, `--test`): takes a lock, opens port 9757 for the LAN only while it runs, shows the
  PIN and launches the game when the headset connects. Tested up to "server listening on *:9757"; on exit no container
  or ufw rule is left behind. `vainfo` in the container: hardware H.264/HEVC/AV1 on the RX 9070 XT.
- **C. Scale:** 100 units per meter by default; this is an inference (near plane at 2, interface at 200), not a
  measurement.
- **Measurements:** at 60 Hz, 60.0 fps and 30 pairs/s with projection (runs 262, 266). At 120 Hz (267, 269) the script
  does not get past the level selector (it is calibrated for 60 Hz); there, 97–103 fps and ≈ 50 pairs/s. **The level
  with head tracking at 120 Hz was left unmeasured.** Regression check (268): normal build with the same hooks, no
  variables → 0 `[vr` lines, `ldd` without `openxr`; the package binary is unchanged.
- **Plan vs. done:** fixing the reticle and the `dlsym` lookup were not planned; they came up while testing. An attempt
  was made to build the WiVRn client for Linux as a fake headset (a complete test without a Quest) and it was dropped:
  it requires building KTX-Software separately.
- **Stumbles:** the image's clang does not compile WiVRn (gcc 15.2 was used); `GIT_TAG` has to be passed on its own;
  the build machine's mDNS name stopped resolving to IPv4 around 10:25 (work continued by IP address; I did not touch
  avahi or the network); a `pkill -f` of mine killed my own ssh session once, with no further effect.
- **Pending:** the test on the Quest 2 (connection, latency, audio, real Touch controllers, scale); a faint duplicated
  ring on the reticle; the level's 2D interface stretched; per-eye resolution; one eye per frame.
- **SDK on the build machine:** local commit `329981e` (rollback: `git revert 329981e` in the rexglue-sdk checkout).

# 2026-11-20: VR fork, stage 3 (branch `vr`)
- **Deliverable:** `docs/analysis/vr-stage3.md`. Package and handheld untouched (the package's `bin/eden` is unchanged,
  dated 03:22).
- **A. Law of the reticle in the level (measured, runs 240 and 243):** it is an **aim angle**, not a screen position:
  `angle = 133.33 °/m · (hand − reference)` for the synthetic skeleton (60 ° per torso length), without using z; the
  camera follows the reticle. Function `sub_82D48CE0`. The name → offset map of the cursor's debug variables was
  extracted (`tools/analysis/debug_fields.py`).
- **B. Shooting by gesture, with a counter (runs 241, 242):** the active hand moves ≥ 11 cm toward the sensor within
  120 ms (`ShotThresholdZ`, detector `sub_82D47A10`); pulling back does not shoot. Left hand forward = rapid fire
  ("BUTTON Vulcan"); both hands up = Euphoria ("BUTTON Bomb"). The counter comes from reviving the game's debug trace
  (`sub_829B1FF0`, a `printf` emptied out in the retail build) with `EDEN_VR_TRACE=1`.
- **C. Tutorial with the hand:** it does close; the target is the ring icon (635, 660 px → hand 0.1348, 0.0836), not
  the text, which is where stage 2 aimed.
- **VR-controller-style input:** `EDEN_VR_HANDS` accepts `a <right°> <up°> <n_trigger> <mode>`. Run 243: what was
  requested (±20, ±40, ±15, ±30 °) is what the reticle shows; 5 trigger pulls, 5 shots.
- **D. OpenXR (more than planned):** the plan said "evaluate Monado and, if it fits, deliver frames". It ended with the
  **first image of the game through OpenXR**: Monado 25.0.0 (Ubuntu package, image `eden-recomp:monado`) with a
  simulated headset on the build machine; a new module in the SDK (`vulkan_openxr.h/.cpp`, now part of the SDK patch
  series), option `-DREXGLUE_VR_OPENXR=ON` and variable `EDEN_VR_OPENXR=1`; separate build `work/build-xr`
  (`tools/build/build_xr.sh`, image `eden-recomp:build-xr`); launcher `tools/vr/run_xr.sh`. It delivers a floating
  stereo screen (two quad layers, one 1280x720 `XrSwapchain` per eye). **Measured:** 120 fps for the game and
  60 pairs/s to the headset (run 251).
- **Plan vs. reality in D:** (1) the first version did everything on the GPU thread and the game dropped to 65–72 fps
  (run 250): it was redone with a dedicated thread for the headset and three image slots. (2) The game crashed inside
  `xrGetVulkanGraphicsDeviceKHR`: Monado requests `vkGetPhysicalDeviceProperties2KHR` and the SDK's Vulkan instance
  was not enabling that extension by name; cause found with gdb and by reading `oxr_vulkan.c` (Monado `v25.0.0`,
  cloned on the build machine only for reading). (3) `monado-service` needs a live stdin and must run without
  gamescope's WSI layer.
- **Integrated run 253:** Kinect mode without a sensor + angle and trigger + alternating eye + OpenXR: it reaches the
  level, closes the tutorial with the hand, shoots, and the simulated headset shows the pair (two screenshots kept as
  evidence, not published).
- **Normal build verified (run 254):** rebuilt without the option, 0 `[vr` lines, no crash, `ldd` without `openxr`.
- **On the build machine:** `rexglue-sdk` now has a local git repo of its sources (`ab720ac` baseline, `24fa46c`
  OpenXR). New images `eden-recomp:monado` and `eden-recomp:build-xr` (`containers/monado.Dockerfile`,
  `containers/build-xr.Dockerfile`). SDK rollback: `git revert 24fa46c` in the rexglue-sdk checkout.
- **Not verified / pending:** nothing tested on a physical headset; no head tracking (the camera does not receive the
  pose); eye separation uncalibrated (with `EDEN_VR_SEP=6` it is excessive); the rapid-fire beam shows in only one
  eye; gamma not compared; the virtual keyboard does not reach the game with Monado's window open (focus); a complete
  level in Kinect mode. The log of run 244 mixes two overlapping executions (I launched it while an image was
  building).

# 2026-11-20: the ROG Ally updated with the XMA audio fix (commit `e52ba1f`)
- **Done:** the handheld came back on the network (07:43) and was updated with
  `bash tools/handheld/update_handheld.sh` (from the dev machine). Verified: the 19 files of the package (`bin/*` and
  `play.sh`) are identical between the package on the build machine and `~/Apps/child-of-eden` on the handheld
  (checksums match). Save (`user/`) untouched; game closed during the copy.
- **Plan vs. reality:** the script failed twice before working. (1) It used `timeout`, which macOS does not ship: it
  died after the backup and before copying. (2) Once copied, it reported that the copy did not match although it was
  correct: the handheld also has `bin/eden.toml` (local settings) and the checksum included it. Fix: cutoff via
  `ssh -o ServerAliveInterval=15 -o ServerAliveCountMax=4`, checksum only over the package's file list, a backup that
  does not nest. Tested: a second run reports that it is already up to date; with a dead IP it exits with an error and
  the step to take.
- **Left over on the handheld:** three 77 MB backups from the retries: `bin.prev-20261120-0744` and `-0746` (previous
  binary, usable as rollback) and `-0748` (a copy of the new one, useless). They were not deleted. Rollback:
  `rm -r bin && mv bin.prev-20261120-0744 bin`.
- **Not verified:** that the crash at Matrix's second boss does not come back on the handheld; it depends on someone
  playing. If something happens, read `~/Apps/child-of-eden/logs/eden_00N.log` (`diag:`, `XMA:`, `[eden] XMA`).

# 2026-11-20: XMA audio crash, stutters and diagnostics (commit `f291fc6`)
- **Tester report:** it crashed again further in (Matrix's second boss), the frame drops came back, and a debug mode
  was requested.
- **Crash (measured on the handheld, `coredumpctl info 133834`, `logs/eden_003.log`):** a write to address 0 in
  `sub_82E84FE8` (the game's XMA playback): the pointer to a stream's XMA context was 0. Different from the previous
  crash (GPU, already fixed).
- **Plan vs. reality:** the initial hypothesis (the 320 contexts run out) **fell**: with the cap forced to 12
  (`EDEN_XMA_MAX=12`, run 302) the game does not crash. What remains is the cross-thread race: `sub_82E84760` frees
  without the critical section `0x83345AC0` that `sub_82E84FE8` does take. It was not reproduced with the bot
  (infrequent).
- **Fix:** always-on hooks in `eden_hooks.cpp` (free inside the same lock; a guard against a null context with the
  warning `[eden] XMA: …`). Runtime: the XMA audio and diagnostics patch (XMA context count and stutter diagnostics:
  `diag: stutter of N ms …` with the number of pipelines compiled in the meantime, plus a per-minute summary).
  The original files were kept alongside on the build machine.
- **Stutters (measured with the bot):** empty cache 25 stutters / 1053 ms; full cache 3 / 101 ms; they are the first
  appearance of each effect. `async_shader_compilation` was already `true` (no change).
- **Package:** `work/package/child-of-eden/bin/` on the build machine updated (`eden`, `librexkernel.so`,
  `librexgpu-xenos-vulkan.so`); previous binaries kept in a `bin.prev-20261120-*` directory. Tested (run 400).
  **The package's `eden` now includes the VR hooks (off without variables).** The `.tar` was not regenerated.
- **HALF DONE: the handheld is NOT updated.** It stopped responding on the network (≈ 03:10) before finishing. Pending
  step: `bash tools/handheld/update_handheld.sh` (only its failure path, "handheld does not respond", has been
  tested).
- **Not verified:** that the crash does not come back on the handheld; the context count in the crash dump;
  `update_handheld.sh` on its happy path.

# 2026-11-20: VR fork, stage 2 (branch `vr`, commit `cd1bed3`)
- **Deliverable:** `docs/analysis/vr-stage2.md`. New hooks in `game/src/eden_hooks.cpp`, launcher `tools/vr/run_vr.sh`
  (it now passes any `EDEN_VR_*`) and action
  `m<sec>:dx,dy,dz,ix,iy,iz` in `steps.sh`. Everything is off without the variables (run 233: 0 `[vr` lines, normal menu).
- **Part A achieved: the game enters and starts Matrix in "Normal (Kinect)" without a sensor.** Command:
  `EDEN_VR_FAKENUI=1 EDEN_VR_SKELETON=1 EDEN_VR_HANDS=/b/vr_hands.txt bash tools/vr/run_vr.sh <N> <actions>`.
  Five pieces: simulated success of `NuiInitialize`/streams; a synthetic `NUI_SKELETON_FRAME` written into the global buffers
  that `CNatal::Update` copies (`0x8337A120`, `0x8337B6D0`, counter `0x8333CA40`, state `0x8337CCB0`); "no player" flag
  `0x8333CA3C` set to 0; `NuiCameraAdjustTilt` returning success; identity = user 0 and `XamShowNuiDeviceSelectorUI`
  redirected to the normal selector (without that the save did not load). Hand→cursor calibration:
  `px = 860 + (x−0.20)·3450`, `py = 435 − (y−0.20)·1933`.
- **Plan vs. actual:** the plan was to first look for a "mode variable" and use `FakeNatalPad`; no such variable exists (the
  mode is decided by which device is used to pick the save file) and `FakeNatalPad` was not needed. The synthetic skeleton
  turned out cheaper than expected because it is injected below the Kinect thread (no events, no depth, no hand refinement).
  A mistake of mine cost two runs: I computed `0x8334CA40` instead of `0x8333CA40` for the frame counter.
- **Part B: "two eyes in the same frame" was not achieved, and the reason was measured.** The main loop (`sub_82FB8C58`)
  walks a task tree that mixes logic and drawing exactly once per frame, then presents: there is no separable draw pass.
  Measured alternative: one eye per frame at 120 Hz gives 117–120 fps (≈ 60 per eye); at 60 Hz, 30 per eye.
- **Part C:** design only (doc §4.3). No OpenXR code compiled or run.
- **Not verified / pending:** the tutorial cannot be dismissed with the hand (it can with B on the controller); reticle
  calibration inside the level (it moves far less than the menu cursor); firing by gesture without a counter; left hand; a
  full level in Kinect mode. Package and handheld untouched.
- **Note:** `work/build/eden` on the build machine carries the hooks (it is not the packaged binary). The development
  build's save may have changed by playing in Kinect mode (not checked).

# 2026-11-20: VR fork, stage 1 (branch `vr`)
- **Deliverable:** `docs/analysis/vr-stage1.md`. Hooks in `game/src/eden_hooks.cpp` (the project's `src/eden_hooks.cpp`; the
  pre-VR original was kept alongside) and launcher `tools/vr/run_vr.sh`. Everything is off without `EDEN_VR_*` variables
  (run 106 without variables: normal). Build: `bash tools/build/build.sh` (5 s incremental).
- **Camera (run 101, 8100 frames):** the scene camera is a single caller, `lr=0x829EDEBC` (`sub_829EDDF8`), once per frame,
  45° vertical, near 2 / far ≈10000, row vectors, right-handed. `0x82DFF00C`, `0x82DE494C`, `0x82980CFC` are UI layers in
  perspective with the plane at 200 units; `0x82C93910/728` is the level selector. None is orthographic.
  End of frame: `sub_82E658D0` (the only call to `VdSwap`). 20 call sites remain unexercised.
- **Depth (run 103, `EDEN_VR_SEP=6 EDEN_VR_SBS=1 EDEN_VR_PERIOD=60`):** correct side-by-side stereo pair of the 3D scene,
  60 fps, no failures. What breaks: 2D text and frames (full screen, they do not go through the camera), the selector's
  particles, the 2D ring of the life icon. It is still one eye per frame. Pairs under `work/shots/vr/` (assembled with
  ffmpeg in the `eden-recomp:run-ffmpeg` image).
- **Kinect:** `FakeNatalPad=1` (run 102) changes nothing visible; still "Normal (Controller)". `NuiInitialize` returns
  `0x8301000D` and `CNatal::Init` `0x80004005` (run 104). With simulated success (run 105) the Kinect thread starts
  (`NuiSkeletonTrackingEnable`, two `NuiImageStreamOpen`), does not request frames (it waits for events) and the game stays
  in controller mode. Conclusion: a synthetic skeleton is needed, or the mode variable has to be found; proposal in doc §5.
- **Plan vs. done:** all 4 planned points were done. Point 3 stayed at reading and proposal (the skeleton was not
  implemented). The "side by side" was assembled from two screenshots of alternating eyes, not within one frame. Snag: the
  `eden-recomp:run-audio` image does not ship ffmpeg.
- **Not verified:** the layout of the skeleton frame; the units/meter scale; `FakeNatalPad` inside the Kinect Tuner.
- **Side effect:** `build.sh` relinked the libraries of the SDK output tree (no source changes). The package was not
  touched: `work/package/child-of-eden/bin/eden` is unchanged; `work/build/eden` is now a different binary.

# 2026-11-20: VR fork, stage 0 (branch `vr`)
- **Goal:** run the VR fork work in parallel with a tester's session on the handheld. Before starting, it was checked by
  sha256 (read-only) that `play.sh`, the README and the 18 files in `bin/` on the handheld were identical to
  `work/package/child-of-eden/` on the build machine; `eden` was not running.
- **Deliverable:** `docs/analysis/vr-stage0.md` (branch `vr`). Static analysis on the dev machine, in a container:
  `container run --rm -m 6G -c 4 -v tools:/h:ro -v work:/s:ro <rexglue-tool image> python3 -I /h/<tool>`.
- **Camera:** the game stores world/view/projection separately in the render object (pointer at `0x83394224`, matrices at
  `+index*64`; view `+128`, projection `+256`) and derives the combined ones when drawing (`sub_82FBF0F0`). Single entry
  point: `sub_82FC09A8(world, view, projection)`, 26 calls. This corrects `vr-feasibility.md`, which only saw the combined
  matrix.
- **Kinect:** addresses in the NUI library: `NuiInitialize` `0x83106DC8`, `NuiSkeletonTrackingEnable` `0x830FB2E8`,
  `NuiSkeletonGetNextFrame` `0x830FB438` (2736-byte buffer), image streams `0x830FD820`/`0x830FCC68`/`0x830FCF90`.
- **`FakeNatalPad`:** it exists in the retail code, turned off; byte `+80` of the Natal cursor object (constructor
  `sub_82D495F0`). When active, it moves the cursor with the controller and skips hand detection.
- **New tool:** `tools/analysis/xref_addr.py` (`lis`+`addi/ori/load` references to addresses or tables).
- **Undetermined:** which of the 15 callers of `sub_82FC09A8` is the scene camera; the layout of the skeleton frame;
  whether the menu offers the Kinect modes with `FakeNatalPad`. All three are answered by running (build on the build machine).
- **Plan vs. done:** as planned; nothing of the game was executed. One snag: a badly posed search (670 functions through
  `show_func.sh`) took too long and was replaced by a direct search over the PE.

# 2026-11-20: Crash on the handheld fixed, shader cache and simple menu
- **Tester report after playing on the ROG Ally:** the game crashed mid-session; "a few fps drops"; rumble works (first data
  point from a real physical controller: the game is playable with the handheld's controller).
- **Cause of the crash (measured, not assumed):** `coredumpctl` on the handheld, PID 25863, SIGSEGV 00:24:05 in the
  `GPU Commands` thread. Stack: `VulkanCommandProcessor::IssueDraw → AnalyzeShaderUCode →
  Shader::GatherVertexFetchInformation → ParsedVertexFetchInstruction::Disassemble →
  StringBuffer::AppendFormat<const char*> → strlen`. In `src/gpu/xenos/pipeline/shader/translator_disasm.cpp` the
  `kVertexFetchDataFormats` table has holes (`{0}`) and the code formatted that null `const char*` with `{}`. A shader in
  the level uses a vertex format with no name in the table.
  **Fix:** a runtime patch (part of the `patches/sdk/` series): when there is no name it writes `FMT_<n>`.
  I do not know which format it was nor whether that shader draws correctly: only the failure while disassembling is
  removed. Same record in `~/Apps/child-of-eden/logs/eden_002.log` ("eden crash report").
- **Stutters:** the launcher did not pass `app.cache_root`, and without it the runtime does not open the shader store
  (`xenos_graphics_driver_base.cpp:188`): no cache folder existed on the handheld, so every session recompiled everything
  on the fly. `play.sh` now passes `--app.cache_root="$D/cache"`. Verified on the build machine that with this option
  `cache/shaders/shareable/5553084C.xsh` and `.fbo.vk.xpso` are created. **Reasonable hypothesis, not measured on the
  handheld:** that the stutters were this; the first appearance of each effect will still compile.
- **Simple menu** (on top of the controller-menu patch, now 721 lines): holding START opens "Child of Eden - Settings" (in
  Spanish at this point): Back to game · Frames per second (60/45/40/30) · Image quality (720p/1440p/2160p) · Smooth edges ·
  Mute · Volume · Aim by moving the console (+ sensitivity and axis inversion when enabled) · frame counter · Advanced
  options (the technical tree, with "< Back to simple menu") · Quit game (asks for a second press). D-pad left/right or A
  change values; every change is saved automatically to `eden.toml`; a notice is shown when a change applies on restart.
- **Held START no longer reaches the game:** `IInputSystem::SetStartHoldMs`; player 1's START is withheld until release:
  short tap → the game receives a 120 ms tap on release; held → the game never sees it. New `IUISystem::RequestQuit`.
- **Tests (build machine, virtual controller, 1920x1080):** run96 menu and value changes (`frame_limit = 45.0` in
  `eden.toml`); run97 "Back to game", 30 fps, "Quit" with confirmation (the process ends without a crash report); run98:
  a short tap on the title advances to the hub, held START opens only the menu (without the game's help screen behind it),
  focus visible, a tap closes it, a short tap afterwards opens the game's controls screen. Screenshots under
  `work/shots/r96…r98/`.
- **Plan vs. reality:** withholding START and fixing focus were not planned; they came out of the tests (in run97 the held
  START also opened the game's help screen, and focus was lost when the text of a row changed).
- **Package:** `child-of-eden-linux-x86_64-20261120.tar` (replaces the one from the previous entry, same name).
- **Handheld updated** (game closed, checked with `pgrep`): backup of the previous `bin/`, `play.sh` and README in
  `~/Apps/child-of-eden.prev-20261119/` (77 MB); copied `bin/`, `play.sh`, README; the checksum-of-checksums matches on both
  sides; `ldd` with nothing missing. Save and `assets/` untouched. Rollback: copy that folder back.
- **Not verified:** none of this has run on the handheld yet (I did not launch the game so as not to interrupt); physical
  controller in the menu; that the point of the level where it crashed now passes and looks right; that the clean exit of
  "Quit game" does not leave Steam believing it is still running. Autosave: it also saves whatever was passed on the command
  line for that launch.

# 2026-11-20: Settings menu with the controller
- **Goal:** open the options menu by holding START; and find out whether there is an options menu at all.
- **Answer to the second part:** there are two. (1) The **game's** own, "Options" in the hub: rumble, brightness,
  music/effects volume, inverted controls, HUD (texts in `common/font/Sheet1.en.txt_`; I have not opened it in a run).
  (2) The **runtime's** (F4): fps, scale, anti-aliasing, gyro, etc. This second one is what now opens with the controller.
- **Done (our own controller-menu patch, 393 lines, on rexglue-sdk v0.11.0):**
  - `IInputSystem::GetRawState(user)`: controller read that ignores the UI lock (`src/hid/input_system.*`).
  - `UISystem::DrawOverlays` (once per presented frame): START held for `ui.pad_menu_hold_ms` (800; 0 disables) opens the
    `settings` overlay; a tap on START closes it. While it is open via the controller the UI lock is taken (the game reads a
    neutral controller). Opened with F4 it behaves as before.
  - `ImGuiHost`: `NavEnableGamepad` and the controller state translated to ImGui keys (D-pad, stick, A/B/X/Y, LB/RB,
    triggers). Font scaled with height (x2 at 1080p).
  - `settings_overlay.cpp`: with the controller, window at 90 % of the screen, panels with `NavFlattened` (focus crosses
    between the tree and the list), fixed scaled widths and −/+ buttons on numbers (step 0.1, 1 or 5 depending on the
    setting's range).
- **Plan vs. reality:** the design doc (`docs/design/controller-menu.md`) did not foresee touching `settings_overlay.cpp`.
  The tests showed three things that forced it: the window stayed at 620x480 with a large font, focus did not enter the
  child panels, and numbers only accepted text.
- **Tests (build machine, SDL virtual controller with the `EDEN_PAD_SCRIPT` button script, 1920x1080):**
  - run90/92: log `pad menu opened` ~0.8 s after starting to hold START and `pad menu closed` on the tap; screenshots with
    the menu, focus moving down the tree (apu → console), A selects a category; on closing, the game continues (animated hub).
  - run94: A on `apu.mute` ticks the checkbox. run95: three A presses on "+" of `apu.peak_limit`: 0.0000 → 0.3000.
  - Screenshots: `work/shots/r90…r95/`.
- **Test scaffolding:** a test patch (72 lines, on top of the SDL driver already patched for gyro): the virtual controller
  of `--hid.sdl.gyro_test=true` obeys `EDEN_PAD_SCRIPT="ms:button:duration,..."`. `tools/test/run.sh` passes that variable.
- **Package:** `work/package/child-of-eden-linux-x86_64-20261120.tar` (changed: `librexui`, `librexhid`, `librexhid-sdl3`,
  `librexbase`, `librexxam`; README updated). The tar from the 19th is kept next to it. **The handheld is still on the
  previous version.**
- **Snag:** in run90 the script pressed A on "Save to config" and wrote `work/build/eden.toml` (252 B, with
  `gyro_test = true`). I deleted it; it did not exist in the package. I do not know whether there was an earlier `eden.toml`
  in `work/build/` (the runs used command-line options).
- **Not verified:** physical controller and the handheld; that the game truly receives no buttons with the menu open (it
  relies on the runtime's UI lock, I did not measure it separately); drop-down lists and "Rebind" with the controller; text
  fields (cannot be edited without a keyboard). The held START also reaches the game before the menu opens (pause, or
  advance on the title).
- Rollback: `git apply -R` of both patches on the `rexglue-sdk` checkout and rebuild; the previous package is the tar from
  the 19th.

# 2026-11-20: Architecture document brought up to date
- **Architecture document rewritten** (now `docs/ARCHITECTURE.md`): it was still at phase 1 ("nothing linked or executed").
  It now covers the full flow disc image → codegen → build, tests and package → handheld, the options of `play.sh`
  (checked against the launcher source), paths, decisions and known problems. The diagram comes from what was executed and
  recorded in the entries below; it was checked that day on the build machine that the build/run images, the 16
  `librex*.so` + SDL3 of the package and the tar exist.
- **Correction:** the package checksum quoted in the project summary was a stale one (from the Steam-art entry); it was
  replaced by the one measured that day.
- **No changes** to the runtime, the package or the handheld. No screenshots in the document: they are game content.
- **Still pending:** the test on the handheld.

# 2026-11-20 (early morning): The game installed and booting on the ROG Ally
- **Goal:** move the game to the handheld.
- **Done:** package copied from the build machine to the handheld (`~/Apps/child-of-eden/`, 2.4 GB) with
  `tar -C work/package -cf - child-of-eden | ssh <handheld> 'tar -C ~/Apps -xf -'`. 5,972 files; the checksum-of-checksums
  (`find … | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum`) matches on both sides.
  `ldd` of `bin/eden` and of all the `.so`: nothing missing (CachyOS, glibc 2.44). No system package was installed.
- **Steam:** "Child of Eden" shortcut registered with a small script that edits `shortcuts.vdf` (back up the file, stop
  Steam, write, start). appid `-113349245` (unsigned `4181618051`), `steam://rungameid/17959912773441814528`. Art copied to
  `config/grid/` (cover, horizontal, background, logo, icon) and a `.desktop` file at
  `~/.local/share/applications/child-of-eden.desktop`.
- **Real test:** launched from Steam in Game Mode; `eden` started after 4 s and at ~45 s the gamescope screenshot
  (1920x1080) shows the complete title screen ("press START button"). GPU `AMD Ryzen Z1 Extreme (RADV PHOENIX)`,
  ~140 % of one core, 615 MB. Game closed afterwards.
- **Gyro on the handheld:** the log says `SDL gamepad "Asus Rog Ally Controller": gyroscope absent`. As it stands, `--gyro`
  will do nothing there: InputPlumber (0.83.0, active) presents a controller without a sensor. A profile with a motion
  sensor has to be configured, or Steam Input's gyro used; I did not touch it (it is system configuration of the handheld).
- **Not verified:** physical controller, audio on the speakers, fps on the handheld, getting past the title.

# 2026-11-19: VR feasibility (Quest 2), analysis only
- **Done:** `docs/analysis/vr-feasibility.md`. Read-only over the codegen output and the `rexglue-sdk` sources.
- **Findings:** shaders with a combined `gWorldViewProj` (+ `gViewProj/gView/gProj/gViewInv/gProjInv`), CPU-side projection
  **not located**; the 16 NUI imports are called only from the static NUI library (0x830FB388–0x83116CA0), there is no
  skeleton through XAM → inject at `NuiSkeletonGetNextFrame`/`CNatal` (`sub_82D54010` = Init); the game ships
  `FakeNatalPad`; rexglue has no VR, it presents via output image → swapchain (`vulkan_presenter.cpp:823`), separable; ARM64
  yes (linux/mac/win), Android no. Recommendation: PC VR in stages.
- **Plan vs. reality:** no shell was available for this analysis, so only text search and reading were used: our own xref
  tools were not run.

# 2026-11-19 (night): Gyro aiming and start of the VR fork
- **Goals:** a gyro control option and, afterwards, a version for Meta Quest 2 (it is fine if the VR is not 360°, as long
  as it has depth and replaces the Kinect; treated as a fork).
- **Gyro (done, tested with a virtual controller):** runtime patch (262 lines, on
  `src/hid/sdl3/sdl3_input_driver.{h,cpp}` of rexglue-sdk v0.11.0; the originals were kept on the build machine). It enables
  the controller's `SDL_SENSOR_GYRO` sensor, averages the samples between reads and adds the rotation rate to the stick
  (yaw → x, pitch → y). New settings, all editable live: `hid.sdl.gyro`, `gyro_right_stick`, `gyro_sensitivity` (1 = full
  stick deflection at 90°/s), `gyro_deadzone` (°/s), `gyro_min_output`, `gyro_roll`, `gyro_invert_x/y`, and `gyro_test`
  (startup only: SDL virtual controller with a gyro that turns right/left/up/down in a 12 s cycle).
- **Test (run81):** `EDEN_EXTRA="--hid.sdl.gyro=true --hid.sdl.gyro_test=true" bash tools/test/run.sh 81 k33:Return k40:l
  k46:space k70:BackSpace k122:BackSpace f124 … f137`. Log: `gyroscope present`, `gyroscope on`. In the 14 screenshots the
  reticle goes left, up, down and back to the right following the cycle, and **stays where each turn leaves it**: the game's
  stick drives reticle velocity, so adding angular velocity is the right mapping (integrating the angle was not needed).
  At 40°/s with sensitivity 1 it covers ~20 % of the width in 2 s.
- The first test (run80, holding `d` on the keyboard) landed on a paused tutorial and was useless; switched to the virtual
  controller.
- Launcher: `play.sh --gyro`, `--gyro=N`, `--gyro-invert-x`, `--gyro-invert-y`, `--gyro-roll`. README updated.
  Package regenerated (changed: `librexhid-sdl3.so` and `librexbase.so`).
- **Not verified:** any physical controller. On the ROG Ally it depends on the system presenting the controller with a
  sensor (InputPlumber / Handheld Daemon emulating a DualSense; with Steam Input active the game sees an Xbox controller
  without a sensor) — I say that from memory, not measured. The axis signs follow SDL's convention; one may need inverting.
  A session without `--gyro` was not run again after the patch (it is off by default and does not touch controller state).
- **VR fork:** a feasibility analysis was started separately: view/projection matrices for stereo, NUI imports to replace
  the Kinect with hands, OpenXR in the runtime, native on Quest 2. Expected deliverable:
  `docs/analysis/vr-feasibility.md`. No VR code yet.
- The plan was not written before starting the gyro work (noted here): it was read the driver, patch, test.

# 2026-11-19 (night): Images for the Steam library
- **Goal:** generate art so the game looks good in Steam.
- **Delivered** in `work/package/child-of-eden/steam/` (outside git): cover 600x900 (title tree + logo), horizontal capsule
  920x430 (hub with Lumi + logo), background 3840x1240 (hub, no text), logo 779x339 with transparency, icon 256x256 plus an
  `.ico`. Everything comes from our own screenshots of the game at 2560x1440 (`GS_W=2560 GS_H=1440` +
  `--gpu.resolution_scale_x/y=2`, run70) composited with ImageMagick: `tools/package/steam_art.sh`.
- `run.sh` gained `GS_W`/`GS_H` (size of the virtual screen). Steam instructions are in the package README.
- Package regenerated.
- **Not verified:** how they look inside Steam (there is no Steam here); the logo's transparency was derived from
  brightness, it may carry a halo.
- The images are game content: they are not in the repo and must not be redistributed.

# 2026-11-19 (night): Anti-aliasing
- **Question: what about anti-aliasing?** Yes: the runtime ships FXAA (`gpu.xenos.swap_post_effect` = `fxaa` | `fxaa_extreme`).
- **Measured (runs 60–64, Archive Select, enlarged crop of the edge of the 3D sphere):** without anti-aliasing the edge is
  jagged; with `fxaa`, `fxaa_extreme`, x2 resolution and x2+`fxaa` it is smooth. On the menu's 2D text the difference is
  minimal (FXAA barely softens it). All five variants read 60–61 fps.
  The sphere is animated, so the crops are not the exact same frame; the comparison is of the kind of edge, not pixel by pixel.
- **Launcher:** `./play.sh --fxaa` (fxaa) and `--fxaa=extreme` (fxaa_extreme). Package regenerated.
- **Not verified:** the effect inside a level (thin-line meshes, where FXAA could blur) and the cost on the ROG Ally.

# 2026-11-19 (night): AMD upscaling and "frame gen": what is possible and what was measured
**Question: can upscaling and frame generation with AMD be supported?** Short answer: temporal FSR and AMD frame
generation, not realistically; but two better substitutes were measured (real resolution and 120 real frames).
- **The runtime ships neither FSR nor CAS** (0 matches for `fsr|fidelityfx|ffx_|sharpen` in `src/` and `include/` of rexglue
  v0.11.0; only `gpu.xenos.swap_post_effect` = `fxaa`/`fxaa_extreme`).
- **Correction to the previous entry (package, bot, settings menu, fps):** I said that with `gpu.frame_limit=30` "it does
  not go into slow motion" because it reached the tutorial at the same second. The evidence was weak. Measured better (runs
  430/460/4120, same script, `vsync=false` + limit 30/60/120): the level is at the same point at 76/84/92/100/110 s in all
  three (Euphoria tutorial at 100 s). The level logic is time-based. **But** see below.
- **`--gpu.vsync=false` breaks things:** it yields 530–600 fps (720p, RX 9070 XT), but the first tutorial appears ~6 s
  earlier (≤60 s instead of ~66 s) and misplaced (overlapping labels, without the enemy in the circle). It happens the same
  with limit 30, 60, 90 and 120: the cause is removing vsync, not the speed. **Do not use.**
- **120 real frames, the clean way:** vsync on + a 120 Hz display (`gamescope -r 120`) + `--ui.video_mode_refresh_rate=120`
  → "Guest: 120.0 FPS (8.33 ms)" and a correctly drawn tutorial (run53). Without declaring the 120 Hz to the game it stays
  at 60 (run52). **Caveat:** at 120 the tutorial appeared already at 60 s (at 60 Hz, ~66 s): some intro sequence runs
  faster. It still needs to be played and listened to in order to know whether the music stays in sync. It remains as
  `./play.sh --hz=120`, marked experimental.
- **Resolution:** `--scale=2` (real rendering at 2560x1440) runs at 60 with no visible problems in the stretch tested.
- **Why not FSR 2/3/4 or AMD frame generation:** they require per-frame motion vectors and depth, which a recompiled 360
  game does not provide (they would have to be extracted from the game's render: weeks of work with an uncertain result).
  AFMF (driver-level generation, the one that needs no integration) only exists on Windows. FSR1 (spatial) is possible
  without touching anything: gamescope does it on the handheld. [The AFMF/gamescope part is from memory, not verified here.]
- `run.sh` gained `GS_EXTRA` (extra options for gamescope). Package regenerated. The loose screenshots of runs 23–53 were
  deleted on the build machine.

# 2026-11-19 (night): Package for CachyOS, 20-minute bot, settings menu and frames per second
- **Linux x86_64 package:** `work/package/child-of-eden-linux-x86_64-20261119.tar` (2.5 GB). Folder `child-of-eden/`: `bin/`
  (eden + 16 `.so` + SDL3), `assets/` (2.3 GB), `play.sh`, README. Launcher and README sources in `tools/package/play.sh`
  and `tools/package/README-package.md`.
  - System dependencies measured with `ldd`: only libc/libm/libstdc++/libgcc, X11 (`libX11`, `libX11-xcb`, `libxcb`),
    `libwayland-client` and `libffi`. It requires **glibc ≥ 2.43**, GLIBCXX 3.4.32. In `archlinux:latest` (glibc 2.44) only
    the X11/Wayland ones were missing (image without a desktop). **Not tested on CachyOS or on the ROG Ally.**
  - Tested from the package with `play.sh --keyboard`: it reaches the title and responds to START. Failure path: without
    `bin/eden` it exits with code 2 and a clear message. Fixed a false Vulkan warning (`ls` over several paths returned an
    error if a single one was missing).
  - Launcher options: `--windowed`, `--keyboard`, `--fps=N` (`gpu.frame_limit`), `--scale=N` (`gpu.resolution_scale_x/y`).
    Verified `--fps=30 --scale=2` from the package: the counter reads "Guest: 30.0 FPS".
- **Native frame rate:** the game itself presents **60 per second** (runtime counter "Guest: 60.0 FPS (16.67 ms)"; matches
  the 59–60 `PRESENT`/s of run18). With `gpu.frame_limit=30` it drops to 30 and **does not go into slow motion**: it
  reached the Matrix tutorial at the same second as at 60 (run24 vs run25), so the logic is time-based. Not tested above 60
  or without vsync. I have no verified source for what it ran at on the real console; this is what the game asks for.
- **Settings menu:** the runtime already ships one (ImGui): **F4** settings (tree app/apu/gpu/hid/kernel/ui…, button "Save
  to config (eden.toml)"), **F3** frame counter, **`** console, F7 achievements. F4 and F3 were verified by rebinding the
  key (`--ui.bind.settings=M --ui.bind.debug=N`): in my headless setup `xdotool` cannot deliver the F keys; with a real
  keyboard it should work, **not verified**. It is driven with keyboard/mouse, not the controller.
  `--gpu.resolution_scale_x/y=2` runs at 60 with the warning "Vulkan draw resolution scaling is experimental".
- **Bot (run22, 20 min):** `steps.sh` gained `b<start>-<end>` (reticle sweep with A held, X every 5th step, B every ~12 s)
  and `t<sec>:<key>` (instant tap). 45 screenshots (contact sheet). The game **did not fail in 20 minutes**; the bot goes
  through several sections of Matrix (tunnel, line mesh, blue zone with creatures, Euphoria/Tracer/Life Recovery tutorials)
  but **dies around minute 5 of each attempt** (defeat screen → OK → retries; 3 laps). It does not finish the level: the
  results screen and the unlock of the next archive have still not been seen. The save was rewritten (20:22).
  In Archive Select there is no difficulty change with up/down/Y at this stage (run26): only "Normal (Controller)".
- **Images on the build machine:** `eden-recomp:build`, `eden-recomp:run` (+gamescope), `eden-recomp:run-audio`
  (+pulseaudio), `eden-recomp:run-ffmpeg` (+ffmpeg); also `archlinux:latest` pulled from Docker Hub only for the `ldd` check.
- **Not verified / pending:** finishing a level (needs a player or a bot that sees the screen); the ROG Ally; F4 with a real
  keyboard; driving the settings menu with a controller.

# 2026-11-19 (night): Video with the game's audio
**Goal: assemble a video. Delivered: `video21.mp4` (2:16, 1280x720, H.264 + AAC, 83 MB).**
- **Tester feedback:** the audio of `audio17.wav` "sounded clean"; **the target ROG Ally runs CachyOS** (Linux).
- **Content of the video:** boot → title → hub → Archive Select (Matrix) → transition → Matrix being played with stick + A
  and dismissing tutorials with B, up to the second section of the level (line mesh). Verified by extracting 7 frames from
  the MP4.
- **How it is recorded:** `IMG=eden-recomp:run-ffmpeg AUDIO=pulseaudio VIDEO=1 VIDEO_FROM=14 tools/test/run.sh 21 <actions>`
  and then `tools/test/make_video.sh 21`. `steps.sh` takes gamescope screenshots in a burst to
  `work/build/vf<N>/<epoch>.png` (~20 per second); `make_video.sh` builds a list with the real duration of each screenshot,
  trims the audio by timestamp (offset 14.02 s) and encodes at 30 fps. Image `eden-recomp:run-ffmpeg` =
  `eden-recomp:run-audio` + `ffmpeg` (`containers/run-ffmpeg.Dockerfile`).
- **Limitation:** the video runs at ~20 fps because of the capture method; the game presents at 60 (measured in run18).
- **Paths that failed:** `ffmpeg -f x11grab` records black (the game presents through Vulkan directly to gamescope; the X
  root stays empty). Run 20 got stuck in the hub because I moved the keys 9 s earlier: before ~33 s the title does not
  accept START.
- **Cleanup:** deleted the screenshot folders `vf19`, `vf20`, `vf21` (hundreds of MB each). `video20.mp4` and `video21.mp4`
  remain.

# 2026-11-19 (night): Playable controller mode and real audio
**Decision: focus on controller mode.** Kinect stays out of scope unless it blocks the controller path.
- **Controller in the level (run16):** B (`BackSpace`) dismisses the tutorial; with A held + left stick the reticle sweeps
  the screen and the camera follows it; more enemies appear and so does the next tutorial ("Player Life"). The level
  advances. `steps.sh` gained `d<sec>:<key>` (hold) and `u<sec>:<key>` (release).
- **Real audio (run17): it works.** 101.9 s recorded, 48 kHz stereo; silence for the first ~14 s (loading) and then a
  continuous signal (rms 0.04–0.10, max peak 0.61) in title, hub and Matrix. No crashes: the `sub_830EF968` path did not
  abort. Recording in `work/build/audio17.wav` (sent to a tester to listen to: **I cannot judge whether it sounds right**,
  only that there is signal).
- **How:** new image `eden-recomp:run-audio` (`containers/run-audio.Dockerfile` = `eden-recomp:run` +
  `pulseaudio pulseaudio-utils`, Ubuntu repos). `steps.sh` with `AUDIO=pulseaudio` starts PulseAudio with a null sink and
  `parec` records the monitor. Usage: `AUDIO=pulseaudio run.sh 17 …`.
- **Paths that failed, with their error:**
  1. `SDL_AUDIODRIVER=disk` → `Audio target 'disk' not available` (the SDL3 we build only ships alsa, pipewire, pulseaudio,
     dummy).
  2. ALSA with the `file` plugin over `null` → no clock, SDL wrote **47 GB of silence in 100 s** (`audio17.wav`, deleted on
     the spot; the build machine's disk ended at 69 %). Do not use.
  3. PulseAudio with `XDG_RUNTIME_DIR=/tmp` → "not owned by us (uid 1000)"; fixed by creating `/tmp/xdg` (mode 700) in
     `run.sh`.
- **Measured performance (run18, 99 s, `--log.categories.gpu=debug`, counting `XELOG_GPU PRESENT` per second):** 5,729
  frames; **a stable 59–60 per second** in title, hub and Matrix (minimum 54 in one second of loading), with vsync. The
  first frame is presented in the same second as startup: the earlier "27 s" were only the time until the first texture
  warning, not a wait. Process: **~144 % CPU (1.4 cores) and 643 MB of RAM** (`docker stats` at 80 s, in the level). GPU:
  RX 9070 XT, 1280x720; GPU load was not measured, nor was it tested without vsync or at a higher resolution.
- **Not verified:** audio quality by ear; a real physical controller through SDL (here it was simulated keyboard → the SDK's
  virtual gamepad), analog triggers and rumble; finishing the level.

# 2026-11-19 (night): Save verified and first level (Matrix) in play
**Result: the game enters the Matrix level and draws gameplay (tunnel, enemy, reticle, HUD) up to the tutorial. No new errors.**
- **Correction to the previous entry:** I said it "saved nothing". **False.** The save is written:
  `work/build/user/B13EBABEBABEBABE/5553084C/00000001/eden/eden_game.dat` (12,532 bytes) + `Headers/00000001/eden.header`.
  Proof that it is loaded: in the following runs the game no longer asks to create a save nor shows the prologue/video; it
  goes straight to the hub. The warning `no mount covers 'save:\'` only appears when the file already exists: with
  `--log.level=debug` (run12) one can see that the game mounts `save:`, unmounts it and 17 ms later tries to open
  `save:\eden_game.dat`; right after, it mounts it again on another thread. It is a failed probe, with no visible effect.
  Not investigated further (the game's call order, or a race with the SDK's deferred operations).
- **Keyboard controls confirmed:** `Return`=START, `space`=A, `l`=X, `a`/`d`=left stick. In the hub, X = "Play" opens
  Archive Select with Matrix already selected ("DIVE!"); the other archives show as "?????" with required stars (14, 20).
- **Sequence up to the level (run15, 170 s):** `run.sh 15 k33:Return k40:l k46:space f50 f55 k58:space f62 …` →
  particle transition (55 s) → **Matrix in play** (62 s: panel tunnel, red enemy, reticle, blue indicator at bottom right)
  → screen "Tutorial: Purify the infected targets" waiting for B (70–170 s; that is why the screenshots from there weigh
  the same).
- **Warnings in run15:** only the known ones (`save:` probe, 1 `XMA unknown register`, 1 frame skipped by async shaders,
  and `indirect buffer failed` when killing the process). No Kinect stub complained in the log at `info` level.
- **Not verified:** audio, actually playing (aiming/shooting, finishing the level), real fps, and Kinect mode.

# 2026-11-19 (night): Title, new save, prologue and intro video
**Result: `eden` gets past the title with START, accepts creating the save, shows the prologue and plays the intro video. No crashes in 180 s.**
- **Two parallel pieces of work collected** (both delivered): screenshots via headless gamescope +
  `gamescopectl screenshot`, image `eden-recomp:run` (entry below), and `docs/analysis/gpu-startup.md` (entry below).
- **Manifest:** `0x830EF968 = { size = 0x8 }` in the project's `eden_manifest.toml` (`game/eden_manifest.toml`).
  Re-codegen on the dev machine: `tools/build/codegen.sh 'cd /w/eden_new && /rx/rexglue codegen eden_manifest.toml'` (47 s,
  exit 0, 9 files written). `Unresolved b 0x830EF968` disappeared; the `REXCPU_FATAL` in `sub_82A07E08` is now
  `REX_MUSTTAIL return sub_830EF968`. It was done on a copy and then swapped in; the previous project tree was kept aside.
  **Finding:** the dev machine's copy had an old `eden_recomp.103.cpp` (from before the `0x830ED250` fix); the build machine
  already had the good one.
- **Rebuild on the build machine:** `rsync -a --checksum` of the project tree + `bash tools/build/build.sh` (47 s, 29 steps,
  0 errors). The string `Unresolved call from 0x82A07E20` is no longer in the binary.
- **Run tool with input:** `tools/test/run.sh <N> <actions>` (+ `steps.sh`, which runs inside gamescope). Actions:
  `f<sec>` = screenshot, `k<sec>:<key>` = key via `xdotool`. It uses `--hid.mnk_mode=true` (keyboard as controller:
  `Return` = START, `space` = A) and `--gpu.xenos.allow_invalid_fetch_constants=true`. Variables: `EDEN_EXTRA` (more
  options), `AUDIO`. Real example: `run.sh 10 k33:Return k40:space k50:space f58 k62:Return f66 … f180`.
- **Measured:**
  - With `allow_invalid_fetch_constants`: texture warnings 26,378 → **0** (run8). In the screenshot, "press START button"
    goes from almost invisible to sharp with its halo, and particles appear: those were the textures with `type=0`. The
    analysis' recommendation was correct.
  - run7 had **8** distinct constants, not 2 as in run6.
  - Sequence seen (screenshots under `work/shots/r8|r9|r10/`, outside git): title → START → "The selected storage device
    does not contain Child of Eden Save Data. Create new Save Data?" → A → "Data saved." → A → text prologue ("September
    11th, 2019…", "Her name is Lumi", "Project Lumi") → full-screen intro video (120–180 s).
  - Remaining warnings per run: 73 `unimplemented: XFileSectorInformation`, 1 `XMA: Write to unknown register (0601)`, and
    on exit (because of the `kill`) `indirect buffer failed to execute a packet`.
- **run11 (360 s, no crashes):** the intro video ends around ~215 s and the game enters the **real-time 3D scene of the
  archive selector** (Lumi floating with a blue glow, the archives' spheres, a light beam with particles; screenshots
  `r11_240s`…`r11_360s`). It is the first 3D render of the engine seen, not video. Navigating or entering a level was not
  tested.
- **New problem:** `E filesystem no mount covers 'save:\'` + `NtCreateFile failed path='save:\eden_game.dat' -> 0xc000003a`.
  The game says "Data saved." but **saved nothing**: the `save:` root is not mounted (the SDK mounts it when the game opens
  a content package with XAM, `docs/site/pages/filesystem/folders-and-storage.md:76`). Why it does not happen remains to be
  seen (log at `debug`).
- **Snag:** the first run9 sent no keys (broken escaping when generating the script with `sed`); redone with `steps.sh`.
- **Not verified:** audio (everything ran with `SDL_AUDIODRIVER=dummy`); that the sound path of `sub_830EF968` executes;
  the main menu and a level; real performance (it is only known that it presents at 60 Hz).

# 2026-11-19 (night): First visible frame of `eden` with a real GPU (build machine)
**Result: 3 PNG screenshots with real content**, presented via headless gamescope (Xwayland with DRI3). Only path 1 was tried; paths 2 and 3 were not needed.
- **Image `eden-recomp:run`** (`containers/run.Dockerfile`): `FROM eden-recomp:build` + `gamescope weston xwayland grim vulkan-tools x11-apps imagemagick x11-utils xdotool` (Ubuntu 26.04 repos). Build ~6 min. Snags: (a) the first `docker build .` sent the whole working folder (game assets) as context and stalled → rebuilt with `docker build -t ... - < Dockerfile` (no context); (b) gamescope installs into `/usr/games` (outside PATH), it has to be added, and `gamescopereaper` is also looked up through PATH.
- **Prior validation with `vkcube`** inside gamescope: `DISPLAY=:0`, screenshot of 85 KB / 7050 colors → the path presents and captures. Capture with `gamescopectl screenshot <path>` (`import -window root` fails; gamescope's PipeWire is not available, and is not needed).
- **eden run (run7):** script `work/shots/run7.sh`; log `work/build/run7.log`, 26,575 lines. The warning `No DRI3 support` went from 12 → **0** in eden's log.
```
docker run --rm --shm-size=3g --device /dev/dri --group-add 44 --group-add 990 --user $(id -u):$(id -g) \
 -m 6g --cpus 4 -v $PWD/work/build:/b -v $PWD/work/game:/assets:ro -v $PWD/work/shots:/c -v $PWD/work/shots/run7.sh:/run7.sh:ro \
 -w /b eden-recomp:run timeout 100 bash /run7.sh
```
  (run7.sh: `PATH+=:/usr/games`, `gamescope --backend headless -W 1280 -H 720 -w 1280 -h 720 -- bash -c "./eden --title.game_root=/assets --gpu.driver=vulkan & ...; gamescopectl screenshot /c/eden_<t>s.png"` at 30/45/60 s using `$SECONDS`.)
- **Screenshots** (`work/shots/`, 1280x720, kept on the build machine): `eden_30s.png` 778,613 B; `eden_45s.png` 777,864 B; `eden_60s.png` 1,608,447 B (1.53 MiB). ImageMagick statistics: 64,242 / 64,640 / 154,475 distinct colors; non-black pixels (>3%) 64% / 65% / 83%. **I could not view the images** (only an 8x4 grid of mean colors). Reading of the grid: 30 s = predominantly cyan/turquoise (top-left corner #1BF7EF, the rest dark greenish), a different scene from the 60 s one; 60 s = dark olive background with a light beige area in the center (#CDC2AA) → another scene (centered image/logo). It is drawn content, not black: the description of concrete shapes remains visually unverified.
- **Telling "black because nothing is presented" from "it draws black":** the former is ruled out (vkcube capturable, DRI3 warning absent from the log, 64–83% non-black pixels).
- **Log by distinct message:** 26,378× `W gpu Texture fetch constant (...) has "invalid" type! ... xenos.allow_invalid_fetch_constants=true`; 73× `W kernel unimplemented: XFileSectorInformation`; 5× `vk_xwayland_wait_ready` warning; the rest: Vulkan info (RADV RX 9070 XT, 740M, llvmpipe).
- **Pending / hypothesis:** the flood of `invalid fetch constant` (~60 Hz, same value `02000000 1D0D0054 ...`) suggests a badly described texture; try `--xenos.allow_invalid_fetch_constants=true` (not tried here). Verify the screenshots visually.
- Leftover test files in `work/shots/`: `t1.sh`, `t1_gs.png` (vkcube). Nothing was deleted.

# Early log — 2026-11-19

## 2026-11-19 (night): GPU warnings, the SDK's capture options and the 27 s (static analysis)
Deliverable: `docs/analysis/gpu-startup.md` + `tools/analysis/find_bytes.py` and `tools/test/xwd_to_png.py`.
Plan vs. reality: the 4 points were answered, but **point 3 (the 27 s) stayed a hypothesis** and **I corrected myself once**: the
first version proposed capturing with `Xvfb -fbdir`; on reading this log I saw it had already been measured that Mesa does not
present under Xvfb (no DRI3), so that capture would come out black. I corrected it in a second revision.
- **Texture warning:** it comes from `src/gpu/xenos/pipeline/texture/cache.cpp:695` of the SDK. What is "invalid" are the 2 low
  bits of word 0 (`type` = 0, 2 is required). The 2 constants are **real textures**: A = DXT5 256x256 at 0x1D0F0000 (mips at
  0x1D0E0000, 9 levels), B = DXT3 64x64 at 0x1D108000 (mips at 0x1D100000, 7 levels). They are neither video nor garbage. The
  SDK **does not discard the draw**: it leaves the texture unbound and it samples (0,0,0,0) (`cache.cpp:302-307`,
  `vulkan/texture_cache.cpp:96-97,601-614`). **Recommendation: enable `--gpu.xenos.allow_invalid_fetch_constants=true`** (the
  `xenos.…` alias works but warns).
- **"async placeholder draw":** with asynchronous shader compilation, a draw whose pipeline is not ready is skipped and that
  frame is not presented (`vulkan/command_processor.cpp:2154-2168`, `:3641-3643`). The warning is emitted only once per
  process. Benign; for screenshots use `--gpu.xenos.async_shader_compilation=false`.
- **SDK options:** table with name, default value and file:line in the document (§2.3). Device: `gpu.vulkan.device`.
  Log: `log.level`, `log.categories.<cat>`. **There is no frame dump, capture or GPU trace**, nor off-screen presentation;
  RenderDoc is half hooked up (it loads the API, nobody calls it). Seeing a frame still depends on the headless-presentation
  work (entry above).
- **The main thread's stack** is `CRT → main → frame loop → Present (sub_82E65F58) → Swap (sub_82E658D0) → wait for the GPU
  (sub_82E58A00) → wait loop with a 5 s detector (sub_82E5DF40)`. It is D3D's normal throttle: each `Swap` waits for the
  previous frame. That is, at 35 s the game **was already presenting frames**. The `WAIT_REG_MEM` of that path: register
  0x1973 (`AVIVO_D1SCL_UPDATE`) `& 1 == 0`, and memory `*(dev+11028)+4 == 1` and then `== 0` (waits for a CPU callback), all
  with wait 0x100.
- **Stubs:** 39 imports are stubs in rexglue; a stub returns **without touching `r3`** (`include/rex/ppc/hook.h:80-84`), so the
  game receives its first argument as the result. Proposed order by how much they get in the way: Kinect (`XamNui*`),
  `XamShowNui*` dialogs, `LDIDecompress`, profile. WMV and XMA do not go through stubs.
- Base command (local container, read-only): `container run --rm -m 6G -c 4 -v "$PWD/tools:/r/tools:ro"
  -v "$PWD/work:/r/work:ro" -v "$PWD/work/game:/assets:ro" <rexglue-tool image> bash -c '<command>'`; full list at the end of
  the document.
- **Failed / half done:** the local rexglue-tool image does not ship Xvfb, so `xwd_to_png.py` was only tested with a synthetic
  XWD (correct colors) and with invalid inputs (rc=2).
- **NOT verified:** that with the option the 2 textures look right; which game function leaves `type` at 0; **the cause of the
  27 s** (hypotheses: black frames from earlier on; a Kinect/profile wait; logo videos); which stubs are hit during startup;
  that `dev+11024` is the `SCRATCH_ADDR` block; that `--log.level=debug` logs every import. The 5 commands for the build side
  are at the end of the document.
- Rollback: delete the analysis branch (it did not touch the codegen output, the SDK or the manifest).

## 2026-11-19 (night): First run with a real GPU (Vulkan)
It was not in the plan for this round (it was "later"); I tried it because it was a single command and the
`eden-recomp:build` image already shipped RADV.
- Command (build machine): the usual run command plus `--device /dev/dri --group-add 44 --group-add 990`, `xvfb-run -a -s "-screen 0 1280x720x24"` and `--gpu.driver=vulkan`; output in `work/build/run6.log`.
- Observed: `rc=124` (cut by the 60 s `timeout`, no abort). Device chosen: `AMD Radeon RX 9070 XT (RADV GFX1201)`, Vulkan 1.4.
  Startup 23:58:36 (container time, UTC); first draw 23:59:03 (**27 s later**); from then on 26,396 warnings
  `Texture fetch constant (...) has "invalid" type!` at a 60 Hz rate, with only 2 distinct constants. Once:
  `Skipping Vulkan frame presentation due to async placeholder draw usage in this frame`.
- **What was NOT achieved:** seeing a frame. Mesa warns 12 times `vulkan: No DRI3 support detected - required for presentation`:
  Xvfb does not present. I do not know yet whether what it draws is correct, black or garbage.
- Follow-ups opened: 3 PNG screenshots with headless presentation (may create the `eden-recomp:run` image), and an analysis
  of the texture warnings, the SDK's capture options and the 27 s.
- The four analyses below were closed with evidence and their branches merged.

## 2026-11-19 (night): Why `ThreadStop` ends in `std::terminate` (reading the SDK and lld/libgcc)
Deliverable: `docs/analysis/threadstop.md` + `tools/build/check_eh_frame_hdr.py`.
Plan vs. reality: the 4 points were done. Reading the lld and libgcc sources was not planned, and it is what gave the answer. The cause had already been measured and patched in parallel while I was writing (entries below); this contributes the **why** and the **root fix**.
- **Root cause (read in sources, not measured by me):** the SDK compiles everything with `-mcmodel=large` (`cmake/rexglue_target.cmake:111-128`) and forces lld, looking for `ld.lld-20` before `ld.lld` (`:142`). The build machine linked with **lld 21**. In `lld/ELF/Writer.cpp` of `release/21.x` there is a new rank `RF_LARGE_EXEC` ("Place readonly .ltext before .lrodata") that puts `.ltext` **before** `.eh_frame_hdr`; in `release/20.x` it does not exist and `.ltext` ends up after, next to `.text`. The table is sorted by `uint32_t pcRel` (`SyntheticSections.{h,cpp}`, `getFdeData`) and libgcc reads it as `signed` and bails out with `if (pc < table[0]...) return NULL` (`libgcc/unwind-dw2-fde-dip.c`, gcc-15). That is why upstream (lld 20) does not suffer from it.
- **Proposed root fix (NOT tested):** link with lld 20 (`apt-get install lld-20` in `containers/build.Dockerfile` + `cmake -UREXGLUE_LLD`, relink SDK and game). The `sort_eh_frame_hdr.py` post-step already in the build works just the same; with lld 20 it would be redundant.
- **A clue the backtrace already gave:** the `rethrow_exception` in `OnTerminate` is inside a `try { } catch (...)` in the same function (`src/base/crash.cpp:171-177`) and it also ended in `terminate`: if not even a local `catch (...)` catches, the unwinder cannot walk that `.so`. That ruled out typeinfo and `noexcept` without running anything.
- **Answers to the questions asked:** (1) `Execute` calls `func(*ctx, base)` (`kernel_thread.cpp:669`); the codegen emits `[[clang::musttail]]` (`src/codegen/builder/context.cpp:284`), which is why no guest frames remain; there is no trampoline or stack switch on Linux (the asm with CFI is macOS-only, `threading_posix.cpp:77-116`). (2) No `-fno-exceptions`/`-fno-rtti`/`-Bsymbolic`/LTO/`--gc-sections`; there **is** hidden visibility per target (`src/base/CMakeLists.txt:66`, `src/kernel/CMakeLists.txt:10-11`), so the typeinfo of `ThreadStop` is duplicated per `.so`; it is not the cause, and with libstdc++ catches across `.so` should work through name comparison (inferred, not tested). (3) `OnTerminate` does not trigger it, it suffers it. (4) Upstream: no commit between v0.11.0 and `nightly-20261117-115171b4` (13 commits) fixes this; relevant ones are `df21a403be493b07a8875ecc0310695a8a85f34b` (introduced lld and asks for lld 20, 2026-11-08), `f910cc2a16df4931bfb5759745fb6d8b1bdd136d` (changes the rethrow in `OnTerminate`; cosmetic for this case) and `5cc991734d96a4747f17cf98b07ae8cf6e912730` (GCC selection).
- **My mistake, corrected in a second revision:** the first version of the document said there were no visibility flags (a badly built grep); that was false. The first version had already been read by others: the conclusion does not change, section 2 does.
- **Snag:** with `rm -rf` of the tools' `__pycache__` I deleted a `.pyc` that was **tracked** (`xdvdfs_extract.cpython-313.pyc`); I restored it with `git checkout --`. That `.pyc` should not be in git (minor pending item: `git rm --cached` + `.gitignore`).
- **Source access:** the lld sources could not be downloaded to disk in this environment. I read them through a web fetch tool, which summarizes and quotes fragments: the lld/libgcc quotes do not come from a local copy.
- **NOT verified:** E2 (minimal reproduction with clang 21 + lld 21) and E3 (lld 20) were not run: this analysis had no access to the build machine and did no builds; nor whether Ubuntu 26.04 ships the `lld-20` package, the full diff of the 13 upstream commits (titles only), nor whether lld change `d53bf41` (Feb 2026) fixes the ordering.

## 2026-11-19 (night): `eden` NO longer aborts; `.eh_frame_hdr` fix integrated into the build
Plan vs. reality: the plan was "read the 3 analyses and, with the cause in hand, send the fix to the runtime side and the rebuild
to the build side". It ended differently: the cause was not in the runtime but in the linker, the fix was a post-link step with
a 10-line usage, and neither touching the SDK nor recompiling was needed, so it was done directly (minutes, with the logs
already at hand).

**Cause confirmed three independent ways:** gdb on the build machine (entry below: `_Unwind_Find_FDE` returns NULL,
`_URC_END_OF_STACK`), reading the lld/libgcc sources (`docs/analysis/threadstop.md`: lld 21 puts `.ltext` before
`.eh_frame_hdr` and sorts the table unsigned; libgcc reads it signed and rejects with `pc < table[0]`) and my measurement of the
table: out of order in **6 of 17 binaries** (`eden`, `librexapp.so`, `librexbase.so`, `librexkernel.so`, `librexxam.so`,
`librexxbdm.so`), always 1 break in the order (e.g. `librexkernel.so`: `0x2bf1b0, 0x2bf200, 0x2c2100, 0x83d80, ...`).

**Fix:** `tools/build/sort_eh_frame_hdr.py` re-sorts that table in the already linked binary (signed order). Idempotent, with
`--dry-run`, exits with 2 if a file is not ELF64 or uses another encoding. Integrated as the last step of
`tools/build/build.sh`, and applied to the current build:
`docker run --rm --user $(id -u):$(id -g) -m 2g --cpus 2 -v $PWD/work/build:/out -v $PWD/tools/build/sort_eh_frame_hdr.py:/s/o.py:ro eden-recomp:build bash -c "python3 -I /s/o.py /out/eden /out/*.so"`

**Observed after the fix (build machine, same usual run command, null GPU):**
- `run4.log` (60 s) and `run5.log` (45 s): `rc=124`, i.e. cut by the `timeout`; 0 lines with terminate/abort/ThreadStop. Before, it aborted at ~1 s.
- `gdb4.log` (stopped at 35 s with `pkill -INT -x eden`): 23 threads alive. The thread that used to kill the process has now finished cleanly (thread 20 is missing).
  - **Main XThread** is executing game code, not waiting: `sub_82E5DF40 ← sub_82E58A00 ← sub_82E658D0 ← sub_82E65F58 ← sub_82FB8C58 ← sub_82FB7B68 ← sub_8316DB38`.
  - **GPU Commands** (null driver) is in `CommandProcessor::ExecutePacketType3_WAIT_REG_MEM`: the game is already sending GPU commands.
  - The rest sleep in `KeDelayExecutionThread` / `NtWaitForSingleObjectEx` / `KeWaitFor*`.
- The log goes quiet after the 73 sector queries: there are no more file opens in those 60 s.

**Not verified / pending:**
- Whether the main thread advances or spins waiting for something the null driver never fulfills (a single stack sample cannot tell).
- Execution with a real GPU (Vulkan, RX 9070 XT). It is the next step.
- That linking with lld 20 (what the SDK asks for) avoids the problem: not tested; the post-step makes it unnecessary for now.
- Manifest entry `0x830EF968 = { size = 0x8 }` (proposed in `docs/analysis/thread-exit.md` §3): not applied; today there is a `REXCPU_FATAL` on the sound thread's path. It requires re-codegen and rebuild.
- Failure path of the script tested: a file that is not ELF (error saying what to do, rc=2) and a second run (17 "already sorted"). Not tested: ELF without a section table.

The two static analyses shared a single checkout (different branches, same directory): it worked because they were warned, but
one worktree per task is the better setup.
Rollback: `git checkout -- tools/build/build.sh` and rebuild (`build.sh` relinks and leaves the table as lld writes it).

## 2026-11-19 (night): Which thread exits at startup, and `XFileSectorInformation` (static analysis)
Deliverable: `docs/analysis/thread-exit.md`.
Plan vs. reality: the 5 steps were done, but **two premises of the task turned out to be false** and that changed the answer:
- **`XFileSectorInformation` is not an unimplemented import.** It is class 26 (0x1A) of `NtQueryInformationFile`; the SDK handles it and returns success (`xboxkrnl_io_info.cpp:94`); the `unimplemented` is just a `WARN` from `REX_KERNEL_STUB`. The game requests it from `sub_8316DFF8` (≈`XGetFilePhysicalSortKey`) through an I/O dispatch table in data (0x83345910; pointer at 0x8334593C), which is why the thunk 0x8330E67C shows only 1 direct caller. The value is used **only as a key to order reads** in the async loader (`sub_82FD6D38`, task `sub_82FD7118`, class `CFileDeviceThreadExecuter`); it is never validated. If it failed it would return 0xFFFFFFFF and only the order would change.
- **The thread that exits does not exit because of an error.** `ExTerminateThread` (0x8330E57C) has 2 callers in the whole PE: the XAPI thread start `sub_82E7D008` (when the thread routine returns) and `ExitThread` `sub_82E79DE0`. There is no error path. The file reader is a loop with an infinite wait: it is not the one that exits. Short-lived candidates: `sub_8304E590`, `sub_82EAC9F8`, the 4 of `sub_82EE3FF8`, and the video player `sub_8292A428`. This agrees with the gdb diagnosis (entry below): the abort comes from exception unwinding, not from the game.
- **Codegen diagnostics:** `0x830EF968` is a 2-instruction function (tail jump to `sub_830EF708`) that rexglue did not see; today it is a `REXCPU_FATAL` inside `sub_82A07E08`, which is called by the **sound command thread** (`sub_82A6F560`) → it will kill the process when that audio path is used. Proposed entry (NOT applied): `[entrypoint.functions] 0x830EF968 = { size = 0x8 }`. The `bdz` 0x831040C0/C4 → 0x831042F4 are impossible cases of a `switch` in `sub_83104058` (camera/NUI library) that point at a zero padding word; rexglue translated them as `return`. They need no entry.
- New tools in `tools/analysis/`: `xref_calls.py` (jumps and pointers to an address over the raw PE), `show_func.sh` (PPC listing of a function from the rexglue or XenonRecomp C++), `dump_words.py`, `string_at.py`, `disassemble.sh`.
- Base command (everything in a container, read-only): `container run --rm -m 6G -c 4 -v "$PWD/tools:/r/tools:ro" -v "$PWD/work:/r/work:ro" <rexglue-tool image> bash -c '<command>'`; the full list is at the end of the document.
- **Failed / half done:** `disassemble.sh` does not work: the rexglue-tool image ships neither `llvm-mc` nor an objdump for PowerPC (it exits with an explicit error). It was worked around by reading the XenonRecomp output (XenonRecomp does recognize those addresses). The scripts were run in the container, not on the host, which is what the project requires anyway.
- **NOT verified:** which exact thread exits at startup (the trace is needed: `start_address` of the `ExCreateThread` of the thread that calls `ExTerminateThread`, against the table in the document); that the manifest entry compiles cleanly (the codegen was not run); the API names are inferred from the shape of the code; the 27 queries were not matched against the ~56 files (I did not have the build machine's log).

## 2026-11-19 (night): Root cause of the `eden` abort (gdb diagnosis, no code touched)
Plan vs. reality: the 4 points were done; one extra step (gdb3d/e/fde*/hdr*) was needed to get from "unwinder returns END_OF_STACK" down to the cause.
No code, SDK or image was changed; only diagnostic files were added in `work/build/` (build machine).

**Root cause (measured):** the `.eh_frame_hdr` lookup table written by lld 21.1.8 **is not sorted the way libgcc expects it**
(binary search with `signed` int32 relative to the hdr). With the code sections in `.ltext` (large code model) *before* the hdr
and a few FDEs in `.text` *after* it, the order ends up "rel>=0 first, rel<0 after". `_Unwind_Find_FDE` returns NULL even though
the FDE exists in `.eh_frame` → `_Unwind_RaiseException` returns `_URC_END_OF_STACK` (5) → `__cxa_throw` calls
`__cxa_begin_catch` + `std::terminate`. It is neither duplicated typeinfo nor an alternate stack.

**Evidence, point by point**
1. `catch throw`: **only 1 throw** in the whole execution, and it is the one that aborts (no earlier ThreadStop was caught). Thread 20 `XThreadB1FFD6C0` (LWP 53):
   `__cxa_throw ← KernelThread::Exit ← ExTerminateThread_entry ← GuestToHostThunk ← KernelThread::Execute ← _S_invoke<Create()::$_0> ← PosixCondition::ThreadStartRoutine ← libc`.
   `info sharedlibrary`/`info threads` (24 threads) in `gdb3.log`. Note: the first attempt (`gdb3_first_attempt.log`) had a mistake of mine: `break std::terminate` did not resolve and its `commands` overwrote those of the catchpoint; fixed with `break _ZSt9terminatev` + `set breakpoint pending on`.
2. At the throw: `$rsp=0x7fffb1ffc990` (in `__cxa_throw`; `0x7fffb1ffc980` in terminate), thread `0x7fffb1ffd6c0`; mapping `0x7fffb0ffd000-0x7fffb4000000 rw-p` (~48 MiB): **a normal pthread stack** (TCB at the top), not sigaltstack nor a custom stack. `info frame` in `gdb3.log`.
3. `_Unwind_RaiseException` + `finish`: **eax = 5 (_URC_END_OF_STACK)**; it returns to `__cxa_throw+68`, next instruction `call __cxa_begin_catch` and then `call std::terminate` (`gdb3c.log`).
   Tracing `_Unwind_Find_FDE` (`gdb3d.log`): it is queried for `_Unwind_RaiseException+65`, `__cxa_throw+67`, `KernelThread::Exit+78` and **stops there** (it never asks for the frame of ExTerminateThread_entry). With condition `pc==0x7ffff7bc774e` (Exit+78) → `finish` → **rax = NULL** (`gdb3e.log`).
4. `readelf` (`readelf3.log`): `_ZTIN3rex10ThreadStopE` is **LOCAL HIDDEN in librexkernel.so (0x2ce2e8) and in librexbase.so (0x2779d0)** (duplicated typeinfo, not exported; `eden` does not have it). True, but **not the cause**: the unwinder does not even get to compare types in the handler search (phase 1 dies earlier because of the missing FDE). It could be a separate problem if some `throw` crossed .so boundaries; not tested.
   - The FDE of Exit **does exist** in `.eh_frame` (`pc=001c7700...001c774f`, `llvm-dwarfdump --eh-frame`, `fde4.log`) and **is** in the hdr table (idx 5570) → it is not missing, the table is badly sorted.
   - `hdr2.py` (`hdr3b.log`): `signed_sorted=False` in `librexkernel.so` (3 entries with rel≥0 ahead of 6176 with rel<0), `librexbase.so` (3 ahead of 3718) and **`eden` (46581 rel≥0 ahead of 29 rel<0)**; `librexppc.so` (only `.text` before the hdr) is correctly sorted. That is: **any exception thrown from code in `eden` or in the .so files with `.ltext` fails the same way**, not only ThreadStop.

**NOT verified:** (a) that unsigned order is lld's rule (inferred from the table, I did not read its source); (b) that reordering sections or `-fuse-ld=bfd/gold` fixes it (not tested, the build was not touched); (c) why the build uses `.ltext` (large code model, flag `l`) — it comes from the build flags, not investigated.

**Proposed follow-up for the runtime side** (in this order of preference, each to be tested with the same gdb3c): 1) link `eden` and the .so files with another linker (bfd/gold, if the image ships it; otherwise a decision about installing it in the image) and repeat; 2) see whether lld has an option/version that sorts signed, or force `.text`/`.init`/`.fini` to sit before the hdr (linker script/section order) so that there are no FDEs with rel≥0; 3) if the SDK does not need the large model in the small .so files (kernel/base), remove it there; `eden` itself has 46581 rel≥0 FDEs because of the guest code, so for `eden` only 1 or 2 apply; 4) runtime alternative: register `.eh_frame` with `__register_frame_info` at startup (libgcc looks there first; not tested).

Files in `work/build/` on the build machine: `gdb3.log`, `gdb3_first_attempt.log`, `gdb3b.log`, `gdb3c.log`, `gdb3d.log`, `gdb3e.log`, `readelf3.log`, `fde3.log`, `fde3b.log`, `fde3c.log`, `fde4.log`, `hdr3.log`, `hdr3b.log`; scripts `gdb3{a..e}.cmds`, `run_gdb.sh`, `readelf.sh`, `fde*.sh`, `hdr*.py` (untracked).

## 2026-11-19 (afternoon): Real build on the build machine; the game BOOTS and executes recompiled code
Plan vs. reality: the plan was 5 steps (rsync, fix 3 diagnostics, full build, headless boot, measure). Step 4 was
reached; step 5 stays open because the boot aborts (see below). 1 of the 3 diagnostics was fixed (the other 2 did not
prevent compiling).
- **Build machine:** Ubuntu 26.04 x86_64, 12 threads, 14 GB, RX 9070 XT, clang 21.1.8, Docker.
  A dedicated working folder (code + the extracted game data, 2.3 GB, now `work/game/`; nothing else was touched).
- Image `eden-recomp:build` (`containers/build.Dockerfile`: ubuntu:26.04 + clang-21, lld-21 with an `ld.lld` link, rexglue deps, xvfb, mesa-vulkan, gdb). Build: `tools/build/build.sh` (own `--user`, `-m 7g --cpus 6`, `ninja -j4`).
- **Open decision 2 resolved**: clang 21 without patches or third-party binaries; the 2 local SDK tweaks are NO longer needed (the SDK on the build machine is the clean copy).
- Errors seen and their fix: (1) the SDK asks for `ld.lld` (symlink in the image); (2) submodules without `.git` after rsync; (3) `REXGLUE_ENABLE_PERF_COUNTERS=OFF` breaks the link of `rexglue` → leave it ON; (4) CMake cache with an old path.
- **Codegen diagnostic fixed**: `sub_830ED250` cut at 0x830ED3CC → "use of undeclared label" (2 errors). Fix in the manifest: `[entrypoint.functions] 0x830ED250 = { size = 0x19C }` (`game/eden_manifest.toml`). Remaining: `Unresolved b 0x830EF968 from 0x82A07E20` and 2 `bdz` outside a function (831040C0/C4); they did not block the build.
- **Build result: 1,234 steps, 0 errors; `work/build/eden` = 56 MB x86-64 ELF.**
- **Headless boot** (`xvfb-run`, `--title.game_root=/assets --gpu.driver=null`, `SDL_AUDIODRIVER=dummy`): 1) `ui.driver` requires a window → a virtual X is needed; 2) SIGBUS on the first guest write → it was Docker's 64 MB `/dev/shm`; solved with `--shm-size=3g`; 3) now the game opens ~56 files from `game:\` (fonts), 2,250 `MmAllocatePhysicalMemoryEx`, 22 threads, 27 `unimplemented` imports (mostly `XFileSectorInformation`) and **aborts**.
- **Current blocker**: a guest thread calls `ExTerminateThread` → `KernelThread::Exit` throws `rex::ThreadStop`; the `catch` is in the same `.so` (kernel_thread.cpp:464/554) but the exception ends in `std::terminate` straight from `__cxa_throw` (search phase finds no handler). Verified: `.eh_frame`/`PT_GNU_EH_FRAME` tables present in the 3 libraries, all with libstdc++/libgcc_s (no mixing with libc++), no visible `noexcept` in the chain. NOT solved; there is no upstream issue (searched "ThreadStop", "terminate"). Next: try the SDK's 0.11.0.13 nightly, gdb with `catch throw` and `info sharedlibrary` to see whether typeinfo/unwinder fails, and find out why a game thread exits so early (an effect of the unimplemented `XFileSectorInformation`?).
- Not verified: real video/audio (`null` GPU), the build machine's display was not used, real Vulkan not tested.
- Logs: `work/build/run{1,2,3}.log`, `gdb{1,2}.log` on the build machine.

## 2026-11-19: Game inventory, measuring XenonRecomp and rexglue, feasibility document
Plan vs. reality: the plan was XenonRecomp+XenosRecomp. It ended up being **rexglue-sdk** as the main path, because the
game ships static D3D9 and compiles HLSL at runtime (XenosRecomp is no longer needed) and rexglue ships the whole runtime.
- Verified the previous entry's claims: `build/XenonRecomp/*` are aarch64 ELFs that run in the container; `VERSIONS.md` tells the truth (commits match `git rev-parse`).
- Image copied from the user's own disc image (zip of 6,265,337,434 B, size checked against the source); ISO 7,838,695,424 B. Extracted with our own extractor `tools/extract/xdvdfs_extract.py` in a container (2.3 GB, now `work/game/`).
- `default.xex` loaded with XenonUtils: 218 imports, `.text` 10.4 MB (2.6 M instr), entry 0x82FB7B58. Custom engine (not UE3), Lua 5.1.2, static D3D9 + HLSL in `shader.bin`, ASF/WMV video, XMA, Kinect (`XamNui*` imports).
- XenonAnalyse: **0 jump tables** (743 bctr). XenonRecomp: 3.7 s, 65,843 functions, 9,793 unrecognized instr (0.38 %), syntax check 1 error in 259 files. Addresses of helpers `__savegprlr_14` etc. found by pattern (`tools/analysis/find_helpers.py`).
- rexglue-sdk v0.11.0 cloned and **built from source** (rexglue-tool experiment image; clang 19 with 2 local tweaks, see VERSIONS.md). `rexglue codegen`: 47 s, 46,579 functions, 186 switch, 3 diagnostics; syntax check 2 errors in 177 files. 179/218 imports implemented, 39 stubs (Kinect, profile, LDI*, etc.).
- DXC from source: cloned v1.9.2609; build in a container (`containers/experiments/build_dxc.sh`): **it compiled completely** (971/971 steps, 0 failures, `build/dxc/lib/libdxcompiler.so`, linux-arm64). That is: the source-only route for XenosRecomp exists and works; what is missing is pointing XenosRecomp's CMake at that library (NOT done, because XenosRecomp is not on the critical path).
- Feasibility document written: `docs/FEASIBILITY.md`.
- Also: a repository holding only scripts, our own tools and docs (nothing from the game), and `docs/analysis/boot-flow.md` (diagram from boot to menu, static analysis). XDVDFS extractor hardened against path traversal.
- Failures/snags: the first `container run` of XenonRecomp segfaulted because the TOML's `file_path` is concatenated with the TOML's directory (use relative paths); the rexglue build failed twice (missing dependencies in the image; `PERF_COUNTERS=OFF` breaks the link) and the DXC one once (source mounted read-only).
- NOT verified: that the rexglue C++ compiles/links/boots; Windows/ROG Ally; real use of LDI*/WMV/Kinect.

## 2026-11-19: Tools cloned and XenonRecomp built
- Verified via the GitHub API and raw files (curl): XenonRecomp and XenosRecomp exist, MIT, not renamed; XenosRecomp active (14 Nov 2026), XenonRecomp quiet since Aug 2025. ReXGlue exists as a runtime.
- Clones in a local tools folder (see VERSIONS.md). Repository initialized with the Containerfile, the build script and VERSIONS.md.
- Image and build executed with the commands of `containers/experiments/build_xenonrecomp.sh` but **by hand**: the script itself could not be run in this environment, so **it is not tested end to end**. Real commands: `container build -m 6G -c 4 -t <xenonrecomp image> -f containers/experiments/xenonrecomp.Containerfile containers/experiments` and `container run --rm -m 6G -c 4 -v <XenonRecomp checkout>:/src:ro -v build/XenonRecomp:/out <xenonrecomp image> bash -c 'cmake -S /src -B /out -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build /out -j4'` (34/34 steps OK).
- XenosRecomp stopped on purpose because of dxc-bin (prebuilt binaries). Planned: build it; result: no.
- Tests: XenonTests contains no .cpp, so there are no tests or examples to run. It was only verified that both binaries start and print their usage.
- Disk: tools 201 MB, build 31 MB, plus the container image. No changes on the host outside the project folder.
