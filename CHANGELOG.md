# Changelog

## 0.3.0 — 2026-10-15

Status-bar fix, the real cause of the old demo crash, and PZFB 1.8 session safety.
Works with PZFB 1.7.x (legacy behaviour); **PZFB 1.8.0 recommended**. Existing
users get the new binaries automatically (see the redeploy fix below).

### Fixed
- **Doomguy's face and the red keycard / skull keys were never drawn.** Since
  0.1.1 the status-bar multi-icon widgets were clamped to two icons as a crash
  work-around, which blanked the face (42 patches) and keys 3–6. Every widget now
  knows its own icon count (face 42, arms 2, keys 6) and bounds-checks against it.
  Verified: face drawn in 100 % of status-bar frames across a 420 s attract-mode
  run (was 30.8 %, then a crash); IDKFA shows all three skull keys and a full
  yellow ARMS panel.
- **The real cause of the demo-playback crash** (0.2.1 still segfaulted 49 s into
  DEMO1 on Linux). Upstream doomgeneric makes `boolean` a **1-byte** type on
  Linux, but id's `st_stuff.c` binds the ARMS widgets to
  `(int *) &plyr->weaponowned[i+1]` — reading four flags as one int (pistol +
  shotgun = 257) and indexing far outside the icon table. `boolean` is int-sized
  again, the arms widgets read a proper `int` shadow array, and `V_DrawPatch`
  ignores NULL patches. Windows never crashed (4-byte enum there) but had the
  blank face/keys.
- **Windows: DOOM's startup text no longer leaks into the frame pipe.** The old
  `_dup2(stderr, stdout)` silently failed under Wine/Proton, so the 1.6 KB
  banner went down the frame pipe and every frame was shifted/blue. `stdout` is
  now `freopen()`'d to NUL/`/dev/null` first thing in `main()`; frames use the
  saved fd as before.
- **Bundled binaries are really redeployed** to `~/Zomboid/PZDOOM/` when the mod
  version changes. 0.2.1's "redeploy on version bump" never ran for existing
  users because `findBinary()` returned early whenever a binary existed — so
  0.2.1's BMI2 fix never reached people who already had `pzdoom.exe`. A
  version stamp (`~/Zomboid/Lua/PZDOOM_deployed_version.txt`) now drives it.
- Closing the DOOM window really removes it (B42's `ISCollapsableWindow:close()`
  only hides) and releases the input panel's keyboard hooks and listeners
  (`cleanup()` on PZFB 1.8, the panel's own `close()` on 1.7).
- "Play DOOM" is offered on televisions only (`IsoTelevision`); placed radios
  also matched before.

### Changed
- **Only stops what it started.** DOOM is launched with `PZFB.gameStartArgs`
  (argv, no quoting) and keeps the PZFB 1.8 session id; closing the window calls
  a stop scoped to that id, so an unused or finished DOOM window can no longer
  kill a running PZEMU game or PZVP video. If another PZFB mod takes over the
  shared slot, the window says so instead of showing foreign frames. On PZFB
  1.7.x: legacy stop, but only if DOOM actually started in this window.
- DOOM exits as soon as PZFB closes its stdin (PZFB 1.8 graceful stop) — no
  more waiting for the force-kill.
- A DOOM window that is stopped/errored no longer polls PZFB's global game
  status (it could display another mod's frames into its 320×200 texture).

### Build
- `doom/patches/0001…0004*.patch` are committed; `doom/build.sh` clones upstream
  `ozkl/doomgeneric` pinned to `3b1d530`, applies the patches idempotently
  ("already applied" is fine, a conflict says `--reset`), copies
  `doom/src/` in, builds Linux and/or Windows (`--windows`, `--all`), refuses any
  binary containing BMI2 instructions, and `--install` writes
  `pzdoom.dat` / `pzdoom_win.dat` into the mod. A fresh clone now builds the
  shipped binaries (the old script needed files that weren't in the repo).
  MinGW SDL2 2.30.12 / SDL2_mixer 2.8.1 dev packages are downloaded on demand.
- Both binaries baseline x86-64, BMI2 count 0 / 0.
- Verified: Linux build byte-identical from a fresh clone; Windows binary run
  under Wine through a Win32-pipe parent (frames aligned, keys accepted, exits
  1 ms after stdin EOF). Real Windows and in-game runs pending.

## 0.2.1 — 2026-05-23

Fixes a crash on older CPUs.

### Fixed
- **CRITICAL:** The Windows DOOM binary crashed immediately on launch
  (`STATUS_ILLEGAL_INSTRUCTION`, reported as exit code 1073741795) on CPUs
  without BMI2 — Intel pre-Haswell (pre-2013) and AMD pre-Excavator (pre-2015).
  `pzdoom.exe` contained BMI2 instructions (`shlx`/`shrx`) pulled in from the
  cross-compiler's runtime library; it is now built entirely against a baseline
  `x86-64` target and runs on any 64-bit x86 CPU.
- `deployBinaries()` now redeploys the bundled binaries on a mod version bump.
  Previously they were copied to `~/Zomboid/PZDOOM/` only on first run, so a
  Workshop update couldn't replace a stale `pzdoom.exe` — affected players
  would have had to delete it manually. Now the binary fix above propagates
  automatically.

## 0.2.0 — 2026-04-14

### Fixed
- Windows WAD paths containing spaces are now quoted correctly

## 0.1.1 — 2026-04-07

Bug fixes and Windows support.

### Fixed
- **CRITICAL:** DOOM's printf output no longer corrupts the frame pipe (stdout redirected to /dev/null, frames use saved fd)
- **CRITICAL:** Letter key mapping now works correctly (LWJGL scan codes are not alphabetical — each key mapped individually)
- Partial stdin read no longer corrupts key event stream (buffered across calls with proper EAGAIN/EOF handling)
- Makefile no longer defines -DLINUX/-DNORMALUNIX when cross-compiling for Windows
- Removed unused variable in WAD picker

### Improved
- WAD/binary path resolution tries getDir() and getVersionDir() with multiple path constructions
- Paths with spaces are detected and skipped (prefer ~/Zomboid/PZDOOM/ which has no spaces)

### Added
- Windows x86_64 binary (pzdoom.exe) cross-compiled with MinGW
- Bundled SDL2.dll and SDL2_mixer.dll for Windows

## 0.1.0 — 2026-04-06

Initial release.

- Play DOOM inside Project Zomboid by right-clicking any TV
- Custom doomgeneric backend (doomgeneric_pz.c) for stdout/stdin I/O
- Raw RGBA frame streaming at 320x200 via PZFB ring buffer
- Keyboard input via PZFBInputPanel with MODE_FOCUS + SCROLL LOCK toggle
- ESC releases exclusive lock AND pauses DOOM simultaneously
- SDL2_mixer audio (DOOM handles its own sound effects and music)
- WAD file picker with auto-detection from mod folder and ~/Zomboid/PZDOOM/
- Bundled WADs: doom1.wad (shareware), freedoom1.wad, freedoom2.wad
- Linux x86_64 binary included
