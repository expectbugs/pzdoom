# Changelog

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
