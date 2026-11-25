# Which thread ends at startup and what the game expects from `XFileSectorInformation`

2026-11-19 · static analysis.
**Static analysis only**: the game was not executed. Inputs: `default.pe` (the decrypted PE),
`work/project/generated/default/*.cpp` (rexglue, 46,579 functions), the XenonRecomp output `*.cpp` (65,843
functions) and the source of `work/rexglue-sdk` v0.11.0. Nothing was modified in the generated output, the SDK or the
manifest.

Every statement is marked **[V]** (verified, with the command that proves it at the end) or **[I]** (inferred).

## Summary in five lines

1. **Ending a thread is the normal path, not an error.** `ExTerminateThread` is only called from two places in the
   game, and both are the ordinary CRT/XAPI exit: the thread startup (when the thread routine does `return`) and
   `ExitThread`. There is no error path that calls the thunk. **[V]**
2. **`XFileSectorInformation` is not an import**: it is information class 26 (0x1A) of `NtQueryInformationFile`, and
   **the SDK already implements it** (it returns success and a 4-byte value); it only prints `unimplemented` as a
   warning. **[V]**
3. The game uses that value **only as a key to sort reads** by physical position on the disc. It does not validate
   it, does not change path and does not abort if it fails. **It is not the reason a thread ends.** **[V]**
4. The thread that reads files is a loop that does not end by itself (it waits on an event with an infinite timeout).
   The thread that ends is a different one; there are 6 short-lived candidates, and which one exactly **can only be
   known with a trace**. **[I]**
5. Of the 3 codegen diagnostics, **one is a real risk** (a `REXCPU_FATAL` in the sound thread) and is fixed with one
   manifest line; the other two are dead code and need nothing.

Conclusion for the current blocker: the abort is **the failure to propagate `rex::ThreadStop`** (see
`threadstop.md`), not something the game does wrong. Even if `XFileSectorInformation` gets "fixed", any thread that
ends will trigger it again.

## 1. Who calls `ExTerminateThread` (thunk 0x8330E57C)

Search over the raw PE, independent of what the codegen recognized: 2 direct branches and 0 pointers in data. **[V]**

| Site | Function | What it is |
|---|---|---|
| 0x82E7D060 | `sub_82E7D008` | **XAPI thread startup** (what `CreateThread` passes to `ExCreateThread` as `xapi_thread_startup`). It notifies a list of callbacks (`sub_82E7C980(1)`), calls the real thread routine through a pointer, saves what it returned, notifies again (`sub_82E7C980(0)`) and calls `ExTerminateThread(returned value)`. |
| 0x82E79E00 | `sub_82E79DE0` | **`ExitThread(code)`**: `sub_82E7C980(0)` and `ExTerminateThread(code)`. |

`sub_82E7C980` walks, under a critical section (0x83345940), a list of registered callbacks (head at 0x8334595C) and
calls them with 1 when the thread is born and 0 when it dies. **[V]** (Probably notifications of the
`XapiThreadNotifyRoutine`/TLS kind. **[I]**)

### Creation chain

`CreateThread` = `sub_82E7A490` → `sub_82E7CAC0` → `ExCreateThread` (thunk 0x8330E6FC), always with
`xapi_thread_startup = 0x82E7D008`. There are 12 calls to `CreateThread` and one direct call to `ExCreateThread` from
`sub_83106608` (camera/NUI library): that one passes `xapi_thread_startup = 0` and the routine `sub_83105E60`, so
that thread ends by `return` straight into the kernel, without going through the thunk. **[V]**

### Thread routines and how they end

| Thread routine | Created by | What it does | How it exits |
|---|---|---|---|
| `sub_8292A428` | `sub_8292AF38` (suspended) | **Video player**: opens the file, reads the first 64 KB and enters the frame loop. Strings: `Movie file open failed %s`, `Movie 1st read start error`, `GetNextFrame Error`. | `ExitThread(0)` when the video finishes or when asked to stop. **Short-lived by design.** |
| `sub_829E65A0` | `sub_829E66E8` ← `sub_829E6BD0` | **Task queue worker**: waits on an event, takes a task and calls its virtual method 1. The file reader runs here (see §2). | `ExitThread(0)` when the "alive" byte (`this+20`) is set to 0. If it is already 0 at birth, it exits immediately. |
| `sub_82A6F560` | `sub_82A6FB08` | **Sound command thread**: 10-case `switch` over a queue of 496-byte messages, `Sleep(1)` per iteration. Calls `sub_82A07E08` (see §3). | `ExitThread(0)` when `this+740` ≠ 0. Long-lived. |
| `sub_82EAC9F8` | `sub_82EAD0A0` ← `sub_82EAD370` ← `sub_82E942A8` | **One-shot thread**: saves its id, signals an event, waits (`KeWaitForMultipleObjects`), calls its virtual method 0 once. | `return 0` → XAPI startup → `ExTerminateThread`. **Short-lived.** |
| `sub_82EE3488`, `sub_82EE34B8`, `sub_82EE34E8` (+1) | `sub_82EE3FF8` (4 threads, 64 KB stack, suspended) | Each one calls **one** virtual method (slots 144/148/152) and returns. | `return 0`. The duration depends on the method (not visible statically). |
| `sub_8304E590` | `sub_8304E618` ← `sub_830084B0` | **Polling task thread**: repeats "is the task done? / take a step / yield the CPU" until either of the two says yes. | `return`. **Short-lived by design.** |
| `sub_82D531E8` | `sub_82D53870` ← `sub_82D54010` (suspended) | **Kinect** thread (`CNatal`): creates events, opens the NUI streams and enters a wait loop. | `return` at the end of the loop. |
| `sub_82E67348` | `sub_82E67780` ← `sub_82E6C290` (64 KB stack) | Worker with `KeWaitForSingleObject`/`KeResetEvent` (system library, D3D/XAudio area). | `return`. |
| `sub_8310FBA8` | `sub_8310FED8` ← `sub_83110180` (32 KB stack) | Internal thread of the NUI/camera library. | `return`. |

### Likely path at startup **[I]**

What was observed (56 font files, 27 sector queries, 22 threads and shortly afterwards an `ExTerminateThread`) fits a
**short-lived thread that ends cleanly**: a loading task that finished (`sub_8304E590` or `sub_82EAC9F8`), one of the
four from `sub_82EE3FF8`, or the video player (`sub_8292A428`) if the first logo was already attempted and there is no
decoder. **It is not an error exit**: there is none in the binary.

What it is **not**: the file reader. That is `sub_82FD7118`, which only leaves its loop when `this+40` ≠ 0 and
between iterations waits on an event with an infinite timeout.

**Unconfirmed:** which of the candidates it is. One line of the trace settles it (see "What is left unconfirmed").

## 2. `XFileSectorInformation`

### What it really is

- It does not appear in the XEX import table (218 imports; none with that name). **[V]**
- It is `X_FILE_INFORMATION_CLASS` = **26 (0x1A)**, handled by `NtQueryInformationFile`
  (`work/rexglue-sdk/src/kernel/xboxkrnl/xboxkrnl_io_info.cpp:94`). The `unimplemented` message comes from
  `REX_KERNEL_STUB`, which is only a `WARN` (`src/kernel/stub_log.h:27`): the call **continues and returns
  success**. **[V]**
- Today the SDK writes 4 bytes with a hash of the file path, `IoStatusBlock.Information = 4` and
  `STATUS_SUCCESS`. **[V]**

### Where the game asks for it

The game does not call the thunk directly: it uses an **I/O dispatch table** in data (0x83345910 to 0x83345938, with
`NtClose`, `NtDuplicateObject`, `NtCreateFile`, `NtReadFile`, `NtReadFileScatter`, `NtQueryDirectoryFile`,
`NtQueryVolumeInformationFile`, `NtQueryInformationFile`, `NtSetInformationFile`, `NtOpenFile`,
`NtQueryFullAttributesFile`), reached through the pointer at 0x8334593C. That is why a `grep` for the thunk only finds
one caller (which uses class 14, position). **[V]**

| Function | Role |
|---|---|
| `sub_8316DFF8` | Equivalent to XAPI's `XGetFilePhysicalSortKey(handle)` **[I, from its shape]**: asks for class 26 with a 4-byte buffer through the table (offset 32). If the status is negative, it translates the error (`sub_82E7B7B8`) and returns **0xFFFFFFFF**; otherwise it returns the `u32`. **[V]** |
| `sub_82FD6D38` | Loop of the asynchronous loader. For each request it opens the file, calls `sub_8316DFF8` and pushes a 12-byte record `{key, request, handle}` onto a heap (vector at `this+392`). Then it pops in key order: size, buffer allocation, read, callback and close. **[V]** |
| `sub_82FD7118` | "run" method of the task (vtable at 0x824BBFF8, next to the string `CFileDeviceThreadExecuter`): waits on the event, calls `sub_82FD6D38` and repeats until `this+40` ≠ 0. **[V]** |
| `sub_82FF8CC0` | Alternate path (queued from `sub_82FF8F18`): opens, asks for the key twice (once for the message `Queuing file %s for load, key = %d`) and queues. If the file does not open, it queues with key 0. **[V]** |

There are exactly 3 calls to `sub_8316DFF8` in the whole binary. **[V]**

### What it does if it fails

**Nothing.** The returned value is never compared with -1 or with anything else: it goes straight into the sort key.
A failure only changes the **order** in which pending files are read. There is no change of path and no thread exit.
**[V]**

The errors that are checked in that loop are different ones: file size (`File Size Get Failed!`), read
(`File load failed: %d`) and short read (`Load Size Matching Faild!`). In all three cases it calls
`sub_82FD79E8(request, 4)` (looks like "mark as failed" **[I]**), closes the file and moves on to the next one; none
of them leaves the loop or ends the thread. **[V]**

### Proposed stub

The SDK's current behavior is already functionally correct for this game. The only things worth changing:

1. **Remove the warning** (or lower it to `DEBUG`): it is not a stub, it is a valid implementation, and today it
   clutters the log with one line per file and makes it look as if something were missing.
2. **Optional:** return a key that respects the physical order when the device knows it (disc image: the file's
   starting sector); for host files, any stable value works.

Contract (same as the console's):

```c
// NtQueryInformationFile(handle, io_status, out, length, FileInformationClass = 26)
// length >= 4, otherwise: STATUS_INFO_LENGTH_MISMATCH (0xC0000004)
// out: big-endian u32 = physical sort key (starting sector/LBA; any stable value works)
// io_status->Status = STATUS_SUCCESS (0); io_status->Information = 4
// returns STATUS_SUCCESS
```

If it were ever done from the game side instead of the SDK, the hook point is `sub_8316DFF8`:
`u32 XGetFilePhysicalSortKey(u32 handle)` returning 0 (all reads stay in arrival order). Not needed today.

## 3. The three codegen diagnostics

### `Unresolved b 0x830EF968 from 0x82A07E20` — **fix**

- 0x830EF968 is a **two-instruction** function (adjusts `r4` by +80 and branches to `sub_830EF708`). It is only
  reached through a tail branch from `sub_82A07E08`; it has no `bl` and no `.pdata` entry, which is why rexglue did
  not see it (XenonRecomp does: `sub_830EF968`). It sits in the gap between `sub_830EF838` and `sub_830EF970`. **[V]**
- Effect today: rexglue emitted `REXCPU_FATAL("Unresolved call from 0x82A07E20 to 0x830EF968")` inside
  `sub_82A07E08`. That function is called by **the sound command thread** (`sub_82A6F560`) when a sound object has
  `+836` ≠ 0. In other words: **it compiles, but it will kill the process as soon as that audio path is used**.
  **[V]** that the `FATAL` is in the generated code; **[I]** that it will be reached when sound plays.
- Proposed entry:

```toml
[entrypoint.functions]
0x830EF968 = { size = 0x8 }
```

### `bdz` at 0x831040C0 and 0x831040C4 to 0x831042F4 — **no entry required**

- They are in `sub_83104058` (camera/NUI library). It is a `switch` built from a chain of seven `bdz` over the value
  returned by a device query (pointer at 0x83356020 → `PsCamDeviceRequest`). Cases 6 and 7 point to 0x831042F4.
  **[V]**
- 0x831042F4 **is not code**: it is the padding word `0x00000000` between the end of the function (0x831042F0) and
  the next one (`sub_831042F8`). They are branches the original compiler considered impossible. **[V]**
- rexglue translated them as `return`, which is harmless. In addition, `PsCamDeviceRequest` is a stub in the SDK
  (`xboxkrnl_stub.cpp:105`): with the output buffer zeroed the function exits before reaching the `bdz` chain.
  **[V]** that it is a stub; **[I]** that it returns 0 without writing the output.
- **No manifest entry applies**: declaring a function at 0x831042F4 would make the codegen translate a zero as an
  instruction. To silence the warning, the honest option would be to mark the padding as data
  (`[[entrypoint.invalid_instructions]]` with `data = 0x831042F4`, `size = 4`), but it is **not proven** that this
  removes the diagnostic, and it adds nothing functional. Recommendation: leave it.

## What is left unconfirmed

- **Which thread is the one that ends at startup.** This needs execution. Proposed follow-up for the build side: in
  the existing log (`work/build/run3.log` on the build machine) or with `gdb` on `ExTerminateThread_entry`, extract
  the `start_address` and `start_context` of the `ExCreateThread` that created the thread that ends and compare it
  with the table in §1. That tells in one line whether it was a loading task, the video player or something else.
- The API names (`XGetFilePhysicalSortKey`, `ExitThread`, `CreateThread`, XAPI startup) come from the shape of the
  code; there are no symbols.
- Which class owns each thread of `sub_82EE3FF8` and of `sub_82EAC9F8`: they go through virtual calls.
- That `[[entrypoint.invalid_instructions]]` silences the `bdz` warning, and that the 0x830EF968 entry compiles
  cleanly: **the codegen was not run** (out of scope for this analysis).
- The count of 27 queries against ~56 opened files was not reconciled: the log of the run was not available.

## Commands that prove it

Everything inside a container (the experiments image built from `containers/experiments/`, `-m 6G -c 4`), with the
repo mounted read-only. `OUT` is the directory holding `default.pe`, the rexglue project (`rex/eden`, i.e.
`work/project`) and the XenonRecomp output (`recomp`). The commands were written for Apple's `container` CLI on the
ARM Mac:

```bash
# from the repo root
# Open a shell in the container (read-only) and run the lines below in it:
container run --rm -it -m 6G -c 4 -v "$PWD/tools:/r/tools:ro" \
  -v "$OUT:/r/out:ro" "$IMAGE" bash

PE=/r/out/default.pe; PART=/r/out/rex/eden/generated/default/codegen.partition.json; H=/r/tools/analysis
# §1: callers of the ExTerminateThread thunk, of ExCreateThread and of CreateThread
python3 -I $H/xref_calls.py $PE $PART 0x8330E57C 0x8330E6FC 0x82E7A490
# §1: PPC listing of the thread routines
bash $H/show_func.sh sub_82E7D008 sub_82E79DE0 sub_829E65A0 sub_8304E590 sub_82EAC9F8
# §2: the NtQueryInformationFile thunk has only 1 direct caller and 1 pointer (the table)
python3 -I $H/xref_calls.py $PE $PART 0x8330E67C 0x8316DFF8
python3 -I $H/dump_words.py $PE 0x83345910 12
bash $H/show_func.sh sub_8316DFF8 sub_82FD6D38 sub_82FD7118 sub_82FF8CC0
python3 -I $H/string_at.py $PE 0x824C0294 0x824BC1C8 0x824BC228 0x824BC008
# §3: the diagnostics (XenonRecomp does recognize those addresses)
GEN=/r/out/recomp bash $H/show_func.sh sub_830EF968 sub_831042F4 sub_83104058
python3 -I $H/dump_words.py $PE 0x830EF968 2
python3 -I $H/dump_words.py $PE 0x831042EC 4
```

They were run without `-it`, passing each command with `bash -c '…'` to the same `container run`.

On the host, read-only: `grep -n "XFileSectorInformation" work/rexglue-sdk/src/kernel/xboxkrnl/xboxkrnl_io_info.cpp`
and `grep -n "Unresolved call" work/project/generated/default/eden_recomp.71.cpp`.

## New tools (`tools/analysis/`)

| File | Purpose |
|---|---|
| `xref_calls.py` | Direct branches and data pointers to an address, over the raw PE (finds what the codegen did not see). |
| `show_func.sh` | Compact PPC listing of a function from the generated C++ (rexglue or XenonRecomp). |
| `dump_words.py` | Dump of 32-bit words, flagging the ones that look like pointers. |
| `string_at.py` | C string at an address. |
| `disassemble.sh` | Disassembly with `llvm-mc`. **Did not work at the time of this analysis**: the experiments image did not ship `llvm-mc` (it exits with an error saying so). `show_func.sh` over the XenonRecomp output was used instead. |
