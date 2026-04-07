# Changelog

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
