# Why `throw rex::ThreadStop` ends in `std::terminate` (rexglue-sdk v0.11.0, Linux x86_64)

2026-11-19. **Static** analysis (reading the SDK in `work/rexglue-sdk`, tag v0.11.0 = `a3e1d826`, and the public
sources of lld and libgcc). The game was not run and nothing was compiled: items marked **[verified]** were read at
the cited file:line; items marked **[inferred]** are deductions and come with their experiment.

## Short answer

**Main hypothesis (H1): this is not a bug in the SDK or in the game, it is the linker.** The build on the build
machine linked with **lld 21** (symlink `ld.lld` → lld-21); the SDK expects **lld 20**
(`find_program(REXGLUE_LLD NAMES ld.lld-20 ld.lld)`). With `-mcmodel=large` (which the SDK imposes on every binary on
Linux x86_64) code goes to `.ltext`, and lld 21 changed where it places that section: **before** `.eh_frame_hdr`. The
lookup table of `.eh_frame_hdr` stores 32-bit offsets relative to the section itself; lld sorts them **unsigned** and
libgcc searches them **signed**. If the binary has code on both sides (`.ltext` before, `.text` after), the table is
out of order as far as libgcc is concerned, and libgcc answers "no FDE" for every PC in `.ltext` →
`_Unwind_RaiseException` returns `_URC_END_OF_STACK` → `__cxa_throw` calls `std::terminate`. The `catch` exists and is
correct; the unwinder never gets to see it.

Proposed fix (build side, without touching the SDK): **link with lld 20**. Confirm first with E1 (10 seconds).

**Corroboration that showed up while this was being written (not a measurement made for this document):** a parallel
gdb investigation left `tools/build/sort_eh_frame_hdr.py` in the shared tree, whose header says it **measured**
exactly this on 2026-11-19 in `eden`, `librexkernel.so` and `librexbase.so`: "LLD 21.1.8 leaves a small .text AFTER
.eh_frame_hdr and writes the table with those entries at the beginning (unsorted) … `_Unwind_Find_FDE` returns NULL".
Both investigations reached the same point by two routes (one by measuring, the other by reading sources), which
raises H1 from "high" to practically confirmed. What this document adds is the **why** and the **root fix**: it is not
link-time chance but a change from lld 20 → 21 in where `.ltext` goes, combined with an unsigned sort; upstream does
not suffer from it because it uses lld 20. That script reorders the table after linking: it works as a patch, but it
has to be applied to **every** binary after **every** link (including the `librex*.so` modules that are loaded at
runtime); with lld 20 the problem does not occur.

## What the backtrace already said (and it rules out almost everything else)

`abort <- OnTerminate <- std::terminate <- std::rethrow_exception <- OnTerminate <- std::terminate <- __cxa_throw <- KernelThread::Exit`

- `OnTerminate` (`src/base/crash.cpp:167-185`) does `std::rethrow_exception(active)` **inside a `try` with
  `catch (...)` in the same function** (crash.cpp:171-177) [verified]. That rethrow also ended in `std::terminate`.
  A `catch (...)` does not compare typeinfo and there is no intermediate frame: if not even that one is reached, **the
  unwinder cannot walk frames of `librexbase.so`** [inferred]. The same happens to the first throw with
  `librexkernel.so`.
- In libstdc++, `__cxa_throw` and `rethrow_exception` only call `std::terminate` directly when
  `_Unwind_RaiseException` **returns** (failed search phase). A violated `noexcept` would look different: the
  terminate would come from the personality/landing pad of the offending frame, not from `__cxa_throw` [inferred from
  the ABI].
- That is why duplicated/hidden typeinfo, `noexcept`, destructors and `REX_ASSERT` are ruled out (see the table
  below).

## The four questions

### 1. How does `Execute()` get straight to an import thunk? Are there trampolines or a stack switch?
- `KernelThread::Execute` calls `func(*ctx, base)` (`src/kernel/kernel_thread.cpp:669`), where `func` is the guest
  startup function (`xapi_thread_startup` or `start_address`, kernel_thread.cpp:619-638) [verified].
- The codegen emits final calls as `REX_MUSTTAIL return fn(ctx, base);` (`src/codegen/builder/context.cpp:284`,
  `control_flow.cpp:154`; `REX_MUSTTAIL` = `[[clang::musttail]]`, `include/rex/platform.h:154-155`) [verified]. The
  guest startup ends by calling `ExTerminateThread` (which does not return), so its frames no longer exist when the
  import runs: that is why the backtrace jumps from `Execute` to `GuestToHostThunk<ExTerminateThread_entry>`
  [inferred; not disassembled]. Consequence: **every guest thread that ends normally goes through this throw**; a
  thread "ending early" is not an anomaly in itself.
- The import is `extern "C" __imp__ExTerminateThread` → `GuestToHostThunk<...>` (`REX_EXPORT` = `REX_HOOK`,
  `include/rex/ppc/hook.h:52-55,132`, `src/kernel/xboxkrnl/xboxkrnl_threading.cpp:129-133,1622`) →
  `KernelThread::Exit` (`[[noreturn]]`, `include/rex/kernel/object/kernel_thread.h:195`) →
  `throw rex::ThreadStop{exit_code}` (kernel_thread.cpp:546). The `catch` is in the lambda of `Create`
  (kernel_thread.cpp:462-466), **same file as the throw** [verified].
- Nothing breaks the stack: `rex::InitializeSEHThread()` only zeroes a `thread_local`
  (`include/rex/ppc/seh.h:161-163`, `src/ppc/seh_posix.cpp:31-33`); `HostCallDepth` is a counter with a destructor
  (seh.h:100-104); fibers use `makecontext/swapcontext` only when creating/switching fibers
  (`src/base/fiber_posix.cpp:50,62`) and `ConvertCurrentThread` only does `getcontext` (fiber_posix.cpp:28-36), it
  does not switch stacks; `sigaltstack` belongs only to the crash reporter (`src/base/crash_posix.cpp:413-424`); the
  only assembly with CFI (`rex_redirect_trampoline`, `src/base/threading_posix.cpp:77-116`) is macOS-only [verified].
  The gdb backtrace is contiguous up to `ThreadStartRoutine`, consistent with this.

### 2. Compile and link flags
Search in `CMakeLists.txt`, `cmake/`, `src/`, `include/` [verified, with grep]:
- **Not present**: `-fno-exceptions`, `-fno-rtti`, `-Bsymbolic`, LTO/`INTERPROCEDURAL`, `--gc-sections`, `--icf`,
  `-static-libgcc`, `-static-libstdc++`, `--unwindlib`, `__register_frame`, `_Unwind_*`.
- **Present** (global, `CMakeLists.txt:143-160`): PIC, `-fno-strict-aliasing -ffp-model=strict -fno-char8_t`, and
  the part that matters: **`-mcmodel=large` + `-msse4.1`** (`cmake/rexglue_target.cmake:111-128`) and **forced linking
  with lld** via `--ld-path=` (`rexglue_target.cmake:138-159`, which looks for `ld.lld-20` first and `ld.lld` second).
  Projects additionally get `-Wl,--no-relax` (rexglue_target.cmake:172). The recompiled code adds
  `-fasynchronous-unwind-tables` (`cmake/rexglue_recomp_options.cmake:126`).
- **Hidden visibility per target** (correction: the first version of this document said there was none): every
  library is declared with `CXX_VISIBILITY_PRESET hidden` + `VISIBILITY_INLINES_HIDDEN ON`
  (`src/base/CMakeLists.txt:66`, `src/kernel/CMakeLists.txt:10-11`, `src/ppc/CMakeLists.txt:21`, and an audit
  enforces it: `cmake/rexglue_link_audit.cmake:262-264`). `rex::ThreadStop` (`include/rex/platform/thread.h:356-358`)
  carries no export macro, so **its typeinfo ends up hidden and duplicated in every `.so`** — this matches the
  `readelf` output of the parallel gdb investigation (`_ZTIN3rex10ThreadStopE` LOCAL HIDDEN in librexkernel and
  librexbase).
- **Even so, typeinfo is not the cause**: (a) the `catch (...)` in `OnTerminate` did not catch either; (b) this throw
  and its catch are in the same file (kernel_thread.cpp:546 and 464), same `.so`, same typeinfo. What about throws
  that cross `.so` boundaries (e.g. `Thread::Exit` in librexbase, `threading_posix.cpp:2085`, or `GuestToHostThunk`
  instantiated in `eden`, `call.h:701,720`, caught in librexkernel)? With libstdc++, `type_info::operator==` compares
  by **name** when the pointers differ, so they should be caught [inferred from the default behavior of libstdc++;
  not tested]. With libc++ that would not hold; the SDK already requires libstdc++ (`cmake/rexglue_stdlib.cmake`).

### 3. What `OnTerminate` does
`src/base/crash.cpp:167-185`: it takes the reporting turn, tries to read the active exception with
`std::rethrow_exception` inside a `try/catch`, writes the report and calls `std::abort()`. It is installed with
`std::set_terminate` in `InstallCrashReporter` (crash.cpp:277). **It does not trigger the problem: it suffers from
it.** The second `std::terminate` in the backtrace is its own rethrow failing (that is why the report never gets
written and the abort comes out "silent"). No `noexcept`, destructor or `REX_ASSERT` on the path causes it
(`REX_ASSERT` at kernel_thread.cpp:545 does not throw).

### 4. How does upstream avoid it?
- **By using lld 20.** Linking with lld is 11 days old: commit `df21a403be493b07a8875ecc0310695a8a85f34b`
  ("build: link with lld where the large code model is used", 2026-11-08), which asks for "Clang 20 and lld 20".
  Before that they used GNU ld.
- History after v0.11.0, reviewed through the public GitHub API (`compare/a3e1d826...115171b4`, 13 commits =
  nightlies `nightly-20261116-5f06b92f` and `nightly-20261117-115171b4`): **no commit fixes thread exit or unwinding
  on Linux.** Two are tangential:
  - `f910cc2a16df4931bfb5759745fb6d8b1bdd136d` "fix(base): read the uncaught exception in the terminate handler
    without copying it": replaces the `rethrow_exception` in `OnTerminate` with a direct rethrow. It does not cure the
    cause; it only changes what the abort looks like.
  - `5cc991734d96a4747f17cf98b07ae8cf6e912730` "build: use the matching GCC install for Clang without a flag":
    libstdc++ selection; already ruled out as the cause before this analysis.
- The full diff of those 13 commits was not read (only titles, and the summary of 3); the local clone is `--depth 1`.

## H1 in detail: `.eh_frame_hdr` table left unsorted by lld 21 + `-mcmodel=large`

Chain of evidence:
1. **[verified, SDK]** Every ReXGlue binary on Linux x86_64 is compiled with `-mcmodel=large`; the SDK's own comment
   says each function goes to its own `.ltext.*` section (`cmake/rexglue_target.cmake:81-86`).
2. **[verified, lld source, branch `release/21.x`, `lld/ELF/Writer.cpp`, `getSectionRank`]** lld 21 has a new rank
   `RF_LARGE_EXEC = 1 << 10` with the comment "Place readonly .ltext before .lrodata". Resulting order:
   `.ltext` → `.lrodata` → `.rodata`/`.eh_frame_hdr`/`.eh_frame` → `.text`.
3. **[verified, `release/20.x`, same file]** lld 20 does **not** have that rank: the executable branch only sets
   `RF_EXEC`, the same for `.ltext` and `.text`; both end up **after** `.eh_frame_hdr`.
4. **[verified, `release/21.x`, `lld/ELF/SyntheticSections.{h,cpp}`, `EhFrameSection::getFdeData`]**
   `struct FdeData { uint32_t pcRel; uint32_t fdeVARel; }`; it stores `uint32_t(pc - va)` and sorts with
   `a.pcRel < b.pcRel`, i.e. **unsigned**. A PC below the section (negative) sorts to the end.
5. **[verified, gcc `releases/gcc-15`, `libgcc/unwind-dw2-fde-dip.c`, `find_fde_tail`]** libgcc declares the table
   as `signed initial_loc` (int32) and starts with `if (pc < table[0].initial_loc + data_base) return NULL;`. After
   the binary search there is no linear fallback.
6. **[inferred]** If a binary has at least one function with an FDE in normal `.text` (after the hdr: `_start` from
   `Scrt1.o` in the executable; in a `.so`, any object from `libgcc.a`/`libc_nonshared.a` or from a static library
   compiled without `-mcmodel=large`), `table[0]` is that function and **all** the `.ltext` ones fall "below" it: no
   FDE → `_URC_END_OF_STACK` → `std::terminate`. gdb does not notice because it reads `.eh_frame` directly, and
   `readelf` shows that the tables "exist", which is exactly what had been verified.

Data measured after this document was read (`docs/DEVLOG.md`, 2026-11-19 night): the table is unsorted in 6 of 17
binaries (`eden`, `librexapp`, `librexbase`, `librexkernel`, `librexxam`, `librexxbdm`). In `eden` the proportion is
the inverse of the `.so` files (46,581 entries after the hdr and 29 before): there, almost all the code is after
`.eh_frame_hdr`. Nothing survives there either: the 29 in `.ltext` fall below `table[0]`, and for the remaining 46,581
libgcc sees `pc >= table[last]` (the last entry is negative), settles on that entry, the range does not match and it
returns NULL. With the table in that state, **no** function of the binary can be found.

What is **not** verified: that `eden`, `librexkernel.so` and `librexbase.so` on the build machine really have FDEs on
both sides (it depends on which objects each link pulled in) and the exact libgcc version of Ubuntu 26.04 (gcc-15 was
read; that code has not changed in years). No report of this bug was found in LLVM (searched; the closest is issue
llvm/llvm-project#172777, closed by commit `d53bf41` from Feb 2026, which rewrites that part for `sdata8`; whether
that change fixes the ordering was not verified).

## Ranked hypotheses, each with its 1-command experiment

All of them are run on the build machine inside the `eden-recomp:build` image, from the repo root.

| # | Hypothesis | Prob. | Basis | Experiment | Prediction |
|---|---|---|---|---|---|
| H1 | `.eh_frame_hdr` table unsorted (lld 21 + `.ltext`) | high | previous section | **E1** | "BAD" in ≥1 of the 3 binaries |
| H2 | Another failure of the clang 21/lld 21 toolchain with the large model (LSDA/CIE `sdata8`) | low | same symptom if E1 comes out OK | **E2** | if E1 is OK and E2 fails: it is the toolchain, not the SDK |
| H3 | Mixed GCC/libstdc++ installs (clang picks "the newest") | very low | `CMakeLists.txt:15-28`, commit `5cc99173` | **E5** | a single version |
| H4 | `ThreadStop` typeinfo duplicated/hidden | ruled out as the cause (the duplicate does exist) | the `catch (...)` at crash.cpp:175 does not catch either; throw and catch in kernel_thread.cpp; see question 2 | — | — |
| H5 | `noexcept`/destructor/`REX_ASSERT` on the path | ruled out | terminate comes from `__cxa_throw`, not from a landing pad; `GuestToHostThunk` (call.h:695-722) is not `noexcept` | — | — |
| H6 | Trampoline/stack switch/emulated SEH | ruled out | question 1 | — | — |

**E1 — confirms or rules out H1 on the real binaries** (new script, read-only):
```
python3 tools/build/check_eh_frame_hdr.py work/build/eden work/build/librexkernel.so work/build/librexbase.so
```
If it reports that the table is NOT sorted as signed (the "BAD" verdict) for any of them → H1 confirmed. If all three
say `OK` → H1 ruled out, continue with E2/E4.
Equivalent by eye: `readelf -SW work/build/librexkernel.so | grep -E ' \.(ltext|eh_frame_hdr|text) '` (H1 requires
`.ltext` at a lower address than `.eh_frame_hdr` and `.text` at a higher one).

**E2 — reproduces it outside the SDK** (4-line program; `_start` lands in `.text` and `f`/`main` in `.ltext`; it has
not been run):
```
printf '#include <cstdio>\nstruct S{int c;};\n__attribute__((noinline)) void f(){throw S{7};}\nint main(){try{f();}catch(const S&s){std::printf("caught %%d\\n",s.c);}}\n' > /tmp/t.cpp && clang++-21 -O2 -fPIC -mcmodel=large --ld-path="$(command -v ld.lld)" /tmp/t.cpp -o /tmp/t && /tmp/t; echo rc=$?
```
With H1: `terminate called after throwing an instance of 'S'`, `rc=134`. Control: remove `-mcmodel=large` →
`caught 7`.

**E3 — the fix: relink with lld 20** (the SDK prefers it on its own, `rexglue_target.cmake:142`):
```
apt-get install -y lld-20 && cmake -UREXGLUE_LLD -S . -B work/build && ninja -C work/build -j4 && python3 tools/build/check_eh_frame_hdr.py work/build/eden work/build/librexkernel.so work/build/librexbase.so
```
(This belongs in `containers/build.Dockerfile`, not done by hand; adjust `-S` to the real project directory.
`-UREXGLUE_LLD` clears the lld 21 path left in the CMake cache; **the SDK and the game** both have to be relinked,
because the `.so` files carry the bad table too. Recompiling is not needed: the link is enough.) If Ubuntu 26.04 does
not ship the `lld-20` package: build lld from the official `llvm/llvm-project` repo at tag `llvmorg-20.1.8` and record
it in `VERSIONS.md`. These do not work: `-Wl,--no-eh-frame-hdr` (libgcc requires `PT_GNU_EH_FRAME`) and GNU ld (the
SDK forces lld because of the 65,280-section limit, rexglue_target.cmake:81-86).

**E4 — watch the unwinder give up live** (if E1 came out OK and the search had to continue):
```
gdb -batch -ex 'catch throw' -ex run -ex 'break _Unwind_Find_FDE' -ex continue -ex continue -ex finish --args work/build/eden --title.game_root=/assets --gpu.driver=null
```
`Value returned ... 0x0` for a PC in `librexkernel.so` = no FDE (the 1st call is from libgcc_s, the 2nd from
libstdc++; one more `continue`+`finish` may be needed). The parallel gdb investigation already did this: a single
throw in the run and `rax = NULL` for `KernelThread::Exit+78` (`gdb3e.log` on the build machine).

**E5 — rules out H3**: `clang++-21 -v -x c++ -E /dev/null 2>&1 | grep -E 'Selected GCC|Candidate'`

## External sources consulted (read-only)
- `https://api.github.com/repos/rexglue/rexglue-sdk/{commits,tags,compare/...}` (history and tags).
- `raw.githubusercontent.com/llvm/llvm-project/release/{20.x,21.x}/lld/ELF/{Writer.cpp,SyntheticSections.cpp,SyntheticSections.h}`.
- `raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-15/libgcc/unwind-dw2-fde-dip.c`.
- Issue `llvm/llvm-project#172777`.
The lld/libgcc quotes were obtained with a web reading tool (it summarizes and quotes fragments), not from a local
copy of the file: E1/E2 should back them up before they are taken as fact.
