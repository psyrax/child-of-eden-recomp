# Crash at the second boss of Matrix (XMA audio), stutters and diagnostics

2026-11-20. Report from a tester after playing on a ROG Ally (CachyOS): a crash further in than the previous time
(second boss of Matrix), frame drops, and a question about a diagnostic mode.
Marks: **[V]** measured; **[I]** inferred; **[?]** undetermined.

## 1. The crash [V]
- Handheld, `coredumpctl info 133834` and `logs/eden_003.log`: SIGSEGV at 8 min 39 s into the session, game thread
  `XThreadBD7F16C0` (the audio thread: it is the same one that writes the XMA registers). "unhandled title write of
  0x00000000, guest address 0x00000000". Stack: `sub_82E7D008 → sub_82EAC9F8 → sub_82EADA08 → sub_82EAD890 →
  sub_82EC4D48 → sub_82E88A28 → sub_82E84FE8`.
- `sub_82E84FE8` (the game's XMA playback library) walks the streams of a player (96-byte entries) and copies the
  pending state to the XMA context of each one (pointer at `+64`). That pointer was 0.
- Who sets it to 0: `sub_82E84760` (releases with `XMAReleaseContext` and clears the pointer) and `sub_82E84650`
  (leaves it at 0 if `XMACreateContext` fails). The game requests and returns contexts all the time (≈ 900 creations
  in 3 min of level).

### The two hypotheses and which one remained
| Hypothesis | Measurement | Result |
|---|---|---|
| The runtime's 320 contexts run out | Runs 300/301 with the bot: peak of 64 in use, almost all young (only 6 older than 20 s: the looping music). Run 302 with the cap forced to 12 (`EDEN_XMA_MAX=12`): 20+ denials and **the game does not crash** | **Ruled out**: the game handles being denied a context correctly |
| Cross-thread race: one thread releases the context while the audio thread writes to it | `sub_82E84FE8` takes the critical section `0x83345AC0`; `sub_82E84760` does **not** take it. On the console those threads almost never run at the same time; on PC they do | **The one that remains [I]**: it could not be reproduced with the bot (0 cases in 5 runs), it is infrequent |

**[?]** The number of contexts in use at the instant of the crash was not counted in the handheld's core dump (the
handheld stopped responding over the network before that was finished). It would be the direct confirmation that it
was not exhaustion.

### Fix (in `eden_hooks.cpp`, always active)
1. `sub_82E84760` (release) now runs inside the same critical section as `sub_82E84FE8`: they can no longer overlap.
2. `sub_82E84FE8`: before the original function, with the lock held, if a stream has no context its pending writes
   are discarded and a `[eden] XMA: …` line naming the stream and the player (stream without a context) is written
   to the log (capped at 40 lines).
3. Runtime (XMA audio and diagnostics patch in the SDK patch series): it counts live contexts and reports every peak
   of 16 and an exhaustion (an `XMA:` line saying no free contexts are left), which used to be silent.

Verified: runs 303–305 and 400 (binaries from the package) with no crashes, audio and game normal, 0 lines from the
guard. **Not verified:** that the crash does not happen again on the handheld; there is no way to trigger it at will.

## 2. The stutters [V]
New diagnostic in the runtime (always active): every frame that takes more than 25 ms and 1.6 times the mean is
logged as a `diag: stutter of N ms` line that also carries the mean (M) and the pipelines compiled in the meantime
(count K, T ms), and every minute a summary line `diag: last minute: ` with the fps (F), the worst frame (N ms), the
stutter count (K) and the pipeline count (P).

| Run (bot, Matrix, 2 min 46 s) | Shader cache | Stutters | Time lost |
|---|---|---|---|
| 303 | empty | 25 | 1053 ms |
| 304 | filled by run 303 | 3 | 101 ms |
| 305 | empty, `async_shader_compilation=true` (it was already the default) | 23 | 998 ms |

- Almost all the stutters carry pipelines compiled in that same frame: they are the **first appearance of each
  effect**.
- With the cache full the runtime precompiles at startup (152 pipelines in the first minute) and the level runs
  clean.
- On the handheld the cache does get saved (`cache/shaders/shareable/5553084C.xsh`, updated 01:54): what has already
  been seen should not stutter again; what is new (further into the level, other levels) will, once.
- **[?]** Not measured on the handheld: whether there are additionally stutters from another cause there (the new
  diagnostic will tell).

## 3. "Debug mode"
It already existed and is what made this diagnosis possible: every session leaves `logs/eden_00N.log` in the package
directory (with the crash report) and the system keeps the core dump (`coredumpctl`). Starting with this package the
log also carries the stutters with their cause and the state of the audio contexts. Nothing has to be enabled.

## 4. Other data from the session
- 997 `unimplemented: XFileSectorInformation` warnings (file reading thread). No known visible effect [?].
- `no mount covers 'save:\'` appears once per session before the save is mounted; the save exists
  (`user/B13EBABEBABEBABE/5553084C/00000001/eden/eden_game.dat`, last write 00:16). Nothing was saved in the session
  of the crash: **[I]** the game saves when the level ends and the crash came first.

## 5. Package
- `work/package/child-of-eden/bin/` on the build machine: `eden` changes (sha256 `2d2e020f…`; it also carries the VR
  hooks, off when no variables are set: 0 `[vr` lines in run 400), as do `librexkernel.so` (`e125dcaf…`) and
  `librexgpu-xenos-vulkan.so` (`a9a89129…`). Previous binaries kept in a `bin.prev-20261120-xma/` directory next to
  the package (`eden` `6365f596…`).
- **The handheld was not updated** (no network at the end). `tools/handheld/update_handheld.sh [--dry-run]` does it
  in one step: it requires the game to be closed, backs up `bin/` and verifies the copy; it does not touch `user/`,
  `cache/` or `logs/`.
