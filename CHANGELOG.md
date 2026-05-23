# Changelog

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
