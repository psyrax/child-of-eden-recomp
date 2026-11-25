# Execution of the first level (Matrix): from the menu to the end of the level

2026-11-20. The goal was an execution diagram of the first level.
It brings together what is already measured in `docs/analysis/boot-flow.md`, `docs/analysis/vr-stage0.md` through
`vr-stage4.md`, `docs/analysis/xma-audio-crash.md` and the bot runs on the build machine, plus a new inventory of the
data under `stage/matrix/` and of the class names (RTTI) in the executable.

Marks: **[V]** seen in the code, the data or a log; **[I]** inferred; **[?]** undetermined.
In the diagrams, solid arrow = [V]; dotted arrow = [I].

## 1. From the menu to the level

```mermaid
flowchart TD
    M["Main menu<br/>stage 'zero' (ZeroMenuCtrl sub_82DEB858)"]
    M -->|"Dive, Matrix is chosen"| J["jumpStage sub_82D88F88<br/>CStageManagerImpl switches stage"]
    J --> S["Stage 'matrix' (entry in common/StageList.param)"]
    S --> C1["Data group loading (CDataGroup)<br/>stage/matrix/common: stage.dg.xml_, config.dg.xml_, path.dg.xml_"]
    C1 --> C2["Parameters: Stage.param and areaNStage.param<br/>(540 .param files in the level)"]
    C1 --> C3["Camera paths: path00..NN.bin per area<br/>(the level is on rails)"]
    C1 --> C4["Videos used as textures (.wmv, 32)<br/>and Lua 5.1 scripts (19)"]
    C2 -.-> L["Layer tree<br/>CEdenLayer → CStageLayer → CAreaLayer → CBlockLayer"]
    C3 -.-> L
    C4 -.-> L
    L -.-> A1["Area 1 running: the level starts"]
```

| Step | Evidence |
|---|---|
| Menu and `jumpStage` | [V] `docs/analysis/boot-flow.md` (xrefs to the menu strings and to the stage switch) |
| `matrix` is a stage | [V] `common/StageList.param`: boot, select, test, sample, zero, **matrix**, beauty, evolution, passion, journey, modelviewer, enemy, player, hope |
| Data groups | [V] `stage/matrix/common/stage.dg.xml_` (XML with `<DataGroup>` and `<File … load="True/False">`), `path.dg.xml_` (13 paths: 3 for area 1, 1 for area 2, 8 for area 5, 1 for area 6) |
| Layers | [V] the classes `Main::Layer::CStageManagerImpl`, `CEdenLayer`, `CStageLayer`, `CAreaLayer`, `CBlockLayer` and `Main::Layer::Sequence::CAreaElementWork`, `CBlockElementWork` exist. [I] the nesting order comes from the names and from the data being laid out as `stage/<level>/area/<area>/block/<block>`; it has not been followed in the code |
| Path in execution | [V] run `run15`: `Return` (START) at 33 s, `X` at 40 s, `A` at 46 s, and the level is already visible at 62 s |

## 2. Structure of the level

```mermaid
flowchart LR
    A1["Area 1<br/>scripts MatrixFireWall*.Lua (6)<br/>3 paths, 1 block"]
    A2["Area 2<br/>background scripts (4)<br/>1 path, 1 block"]
    A3["Area 3<br/>no script or path of its own<br/>3 blocks"]
    A5["Area 5<br/>8 paths, 21 blocks<br/>(block1_1 … block6_6)"]
    A6["Area 6<br/>scripts MatrixMemoryGear*.Lua (8)<br/>Key1..Key4 and Phase3, 1 path"]
    A1 -.-> A2 -.-> A3 -.-> A5 -.-> A6
    A6 -.->|"CCheckStageClearMission"| R["CResultMenuTask<br/>results and save"]
    A1 -.->|"life at 0<br/>CCheckPlayerMission"| G["CGameOverMenuTask"]
    A5 -.-> G
    A6 -.-> G
```

- [V] The areas that exist on disc are **1, 2, 3, 5 and 6** (there is no area 4). Counts of scripts, paths and blocks:
  listing of `stage/matrix/area/`.
- [V] Area 1 carries the `MatrixFireWall` scripts (with variants `Worm`, `Uni`, `JF`, `Fcount`, `ParamLink`) and area 6
  the `MatrixMemoryGear` ones (four `Key`, `Phase3`, `Phase3_Worm`); the class `CGearMainUnit` exists in the
  executable.
- [I] The order 1 → 2 → 3 → 5 → 6 comes from the numbering. [I] That FireWall and MemoryGear are the bosses comes from
  their names and from their having phases; it has not been seen in execution which area corresponds to what the
  tester calls the "second boss".
- [V] `Main::Mission::CCheckPlayerMission`, `CCheckStageClearMission`, `Main::Menu::CGameOverMenuTask` and
  `CResultMenuTask` exist.
- Game over, from static analysis on 2026-11-20 (read in the listing, **not executed yet**): the player's life is an
  integer at `object+1332` (0..10000, 2000 per petal, starts at 6000); `sub_82D07F00` subtracts from it on a hit; when
  it reaches 0 the player sends message 5, `CCheckPlayerMission` (`sub_82D5AFD0`) emits 18, the level handler
  `sub_82D89E98` sets bit 0 of `+3548` and `sub_82D8A8D8` creates `CGameOverMenuTask` (`sub_82935538`). Message 19
  sets bit 1 (results). [?] Whether there is another game-over route that does not go through life.
- [?] Nobody has finished the level in the port: the bot dies around minute 5 and neither results nor a save have been
  seen.

## 3. One frame of the level: threads and who calls whom

```mermaid
flowchart TD
    subgraph JUEGO["Main game thread (recompiled code)"]
        E["Input<br/>XInputGetState → reticle<br/>(reticle object, position at +696/+700)"]
        T["Framework tasks (QE::Base::Task::CTask)<br/>layers, Lua scripts, enemies, missions"]
        SC["Scene: sub_829EDEBC<br/>sets world, view and projection with sub_82FC09A8"]
        D["Drawing: sub_82FC0A48 per object (world),<br/>sub_82FBFAB0 uploads constants,<br/>sub_82D1A488 draws the reticle"]
        RB["Commands to the GPU ring buffer (Vd*)"]
        E --> T --> SC --> D --> RB
    end
    subgraph AUD["Game audio thread"]
        X1["sub_82E84FE8: copies the state of each voice<br/>to its XMA context (lock 0x83345AC0)"]
        X2["sub_82E84650 creates / sub_82E84760 releases contexts<br/>≈ 900 creations in 3 min of level"]
    end
    subgraph ARCH["File reading thread"]
        F["Reads data from the disc during the level"]
    end
    subgraph RT["Runtime (rexglue-sdk, native)"]
        GC["'GPU Commands' thread<br/>interprets the Xenos ring buffer"]
        PC["Pipeline cache<br/>translates shaders and creates pipelines (first appearance = stutter)"]
        SW["IssueSwap → Vulkan → screen<br/>(the stutter diagnostic is measured here)"]
        XM["XMA decoder (320 contexts) → SDL3 audio"]
        ST["'Vulkan Storage writer' thread<br/>saves the shader cache to disk"]
        GC --> PC --> SW
        PC --> ST
    end
    RB --> GC
    T -->|"sounds"| X2
    X1 --> XM
    T -->|"requests data"| F
```

| Piece | Evidence |
|---|---|
| Reticle | [V] `vr-stage4.md`: object with virtual table `0x8237F560`, position at `+696/+700`, drawing `sub_82D1A488` |
| Scene and matrices | [V] `vr-stage0.md` §1: `sub_82FC09A8` (26 calls) sets world/view/projection; `sub_82FC0A48` (228 calls) only the world; `vr-stage4.md`: the caller of the level's scene is `sub_829EDEBC` |
| Tasks | [V] `QE::Base::Task::CTask` exists. [I] that layers, scripts and enemies run as tasks in that order: the step between `main` and the `StageManager` goes through virtual calls and has not been traced |
| Audio | [V] `xma-audio-crash.md`: stack of the crash and counts from runs 300–302 |
| File reading | [V] a separate thread emits the `XFileSectorInformation` warnings (997 in one session on the handheld) |
| GPU and cache | [V] `GPU Commands` thread (a crash in it was fixed earlier), the SDK's `pipeline_cache.cpp`, log line `Created 152 graphics pipelines from Vulkan storage` |
| Kinect | [V] the Kinect thread exists (`vr-stage0.md` §2) but in controller mode it does not take part |

## 4. What was measured over time

```mermaid
flowchart LR
    t0["0 s<br/>startup"] --> t1["≈ 27 s<br/>first frame"] --> t2["33–46 s<br/>START, X, A"] --> t3["62 s<br/>level on screen"]
    t3 --> t4["72 s<br/>the bot starts playing"] --> t5["≈ 5 min<br/>the bot dies"]
    t3 -.-> t6["8 min 39 s (handheld, real player)<br/>second boss: crash of 2026-11-20"]
```

- [V] 27 s to the first frame: `gpu-startup.md`. [V] 33–62 s: `run15`. [V] bot: `tools/test/run.sh <N> … b72-1260`.
- [V] 8 min 39 s: core dump `133834` from the handheld (XMA audio crash, already patched). [?] The new crash reported
  by the tester after that patch ("framerate at 30 and a crash after a challenge") has not been diagnosed: the
  handheld's logs are missing.
- Stutters measured in 2 min 46 s of level: 25 with the shader cache empty, 3 with the cache full (runs 303/304).

## 5. What this document does NOT claim
- The real order of the areas and where each boss falls (only inferred from names and numbers).
- The exact order of the tasks within a frame.
- Anything after minute 5 on the build machine: no run gets that far.
