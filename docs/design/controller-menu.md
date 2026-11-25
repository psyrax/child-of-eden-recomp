# Design — settings menu with the controller (2026-11-20)

## Problem
The runtime's settings menu (F4) can only be opened and operated with keyboard and mouse. On the ROG Ally there is no
keyboard: nothing can be changed without editing `bin/eden.toml` or the `play.sh` options.

## What goes in and what comes out
- **Open:** START held for `ui.pad_menu_hold_ms` milliseconds (800 by default; 0 disables it) on player 1's controller.
- **Close:** a tap of START with the menu open (or F4).
- **Navigate:** D-pad and left stick move the focus and adjust values; A activates; B cancels/leaves a group; LB/RB
  adjust slower/faster (ImGui convention).
- **While it is open through the controller, the game does not receive the controller** (UI lock the runtime already
  has); on close, buttons that are still pressed do not reach the game until they are released.
- **Size:** when opened with the controller the font is scaled with the screen height (x2 at 1080p).

## Where (part of our SDK patches in `patches/sdk/`, on rexglue-sdk v0.11.0)
- `include/rex/hid/input_system.h`, `src/hid/input_system.{h,cpp}`: `GetRawState(user)`, a read that ignores the UI
  lock.
- `include/rex/ui/ui_system.h`: the `ui.pad_menu_hold_ms` setting.
- `src/ui/ui_system.cpp`, `src/ui/ui_state.h`: detection of the press in `DrawOverlays` (once per presented frame),
  toggling the `settings` overlay, controller lock while it is open.
- `src/ui/imgui_host.{h,cpp}`: `NavEnableGamepad` and translation of the controller state into ImGui keys.

## Failure cases
- No controller connected: `GetRawState` returns nothing, nothing happens.
- The held START already reached the game as START (pause, or the title's "press START"): accepted; on the title it
  advances to the menu.
- Menu closed with F4 or the mouse while it was open through the controller: the lock is released when overlays are
  synchronized.
- With the menu opened with F4 (keyboard) the previous behavior does not change: the game keeps receiving the
  controller.

## Out of scope
The game's own "Options" menu (it already exists, in the hub). Translating or redesigning the runtime's menu. An
on-screen keyboard for text fields. Updating the handheld install.

## Correction to this design (2026-11-20, after a request to make it "simple and human")
- The menu the controller opens is no longer the technical tree: it is a short list (in Spanish at the time; see
  `docs/DEVLOG.md`); the technical one stays behind "Advanced options". Changes are saved automatically.
- The held START **no longer** reaches the game (`SetStartHoldMs`): it is delivered as a tap on release if it was
  short.
- "Quit game" is added (`IUISystem::RequestQuit`), with confirmation.

The short menu was later made multilingual, with English as the default; `docs/ARCHITECTURE.md` describes the current
behavior.

## Verification
On the build machine with `tools/test/run.sh` and a virtual controller: screenshot without the menu, held START →
screenshot with the menu; D-pad down → the focus changes between screenshots; short START → menu closed and the game
responds again. And that a normal run without a long START press behaves the same as before.
