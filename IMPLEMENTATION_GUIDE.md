# PZDOOM Implementation Guide

Everything a fresh Claude Code instance needs to implement DOOM inside Project Zomboid using the PZFB framebuffer library.

## Prerequisites Already Done

1. **PZFB (Video Framebuffer)** is published on Steam Workshop (ID 3698742271) and provides:
   - Pixel-level framebuffer rendering via patched `zombie.core.Color` class
   - Full input capture via `PZFBInputPanel` (keyboard, mouse, gamepad, action mapping)
   - External process execution that works inside Steam's pressure-vessel container
   - FMOD audio API (direct, bypasses PZ sound bank system)
   - Source: `~/pzfb/` — GitHub: https://github.com/expectbugs/pzfb

2. **PZVP (Zomboid Video Player)** is a working reference implementation that:
   - Streams ffmpeg's stdout into a ring buffer → GL texture at real-time speeds
   - Handles audio via FMOD with seeking support
   - Has a complete UI with ISCollapsableWindow, controls, file picker
   - Source: `~/pzvp/` — GitHub: https://github.com/expectbugs/pzvp

## What Needs to Be Built

### 1. DOOM Source Port Selection

Need a DOOM source port that can:
- Run headless (no window / no X11)
- Output raw RGBA frames to stdout
- Accept keyboard input from stdin
- Be compiled on Gentoo Linux
- Ideally: output audio to stdout/stderr or a pipe

**Candidates to research:**
- **Chocolate Doom** — faithful original engine, may support headless with patches
- **crispy-doom** — enhanced Chocolate Doom
- **doomgeneric** — specifically designed for "DOOM on anything" ports, has a minimal platform abstraction layer. This is probably the best candidate — it was literally made for embedding DOOM into things.
  - GitHub: https://github.com/ozkl/doomgeneric
  - Provides `DG_DrawFrame()`, `DG_GetKey()`, `DG_SleepMs()`, `DG_GetTicksMs()`, `DG_SetWindowTitle()` — you implement these functions
  - A `doomgeneric_stdout` or `doomgeneric_pipe` backend that writes frames to stdout and reads keys from stdin would be ideal
- **fbDoom** — framebuffer-based DOOM port, outputs to Linux framebuffer device

**Key research:** Check if `doomgeneric` exists in package managers or needs manual compilation. Check if a stdout/stdin backend already exists. If not, writing one is maybe 50-100 lines of C.

### 2. PZFB Java Additions (Color.java)

The streaming video pipeline from PZVP can be largely reused. The key NEW requirement is **bidirectional I/O** — writing to the process's stdin for keyboard input.

#### New Java method needed: `fbProcessWriteInput`
```java
// Write bytes to the running process's stdin
// Used for sending keyboard events to DOOM
public static boolean fbProcessWriteInput(byte[] data) {
    // Write to _fbStreamVideoProc.getOutputStream()
    // Needs to be thread-safe
}
```

Or alternatively, a higher-level method:
```java
// Send a key event to the running process
// action: 1=press, 0=release
// keycode: DOOM-specific key code
public static void fbGameSendKey(int keycode, int action) {
    // Write structured key event to process stdin
    // Format depends on the DOOM port's stdin protocol
}
```

#### Potential PZFB changes:
- Modify `fbStreamStart` or create `fbGameStart` for bidirectional process I/O
- The existing `buildHostProcess()` already handles pressure-vessel — reuse it
- The existing ring buffer and `fbStreamFrame()` work as-is for receiving video frames
- Need to add `Process.getOutputStream()` access for stdin writing

### 3. Input Translation Layer

PZFBInputPanel v2.0 provides `onPZFBKeyDown`/`onPZFBKeyUp` callbacks with LWJGL key codes (`Keyboard.KEY_*`). DOOM uses its own key codes. A mapping table is needed.

**Approach:** Use `PZFBInputPanel` in `MODE_EXCLUSIVE` to consume all input. Override `onPZFBKeyDown`/`onPZFBKeyUp` to translate LWJGL → DOOM key codes and send to the process. The action mapping system can also be used if gamepad support is desired later.

**PZ key codes** (verified from `org.lwjglx.input.Keyboard` in PZ's jar):
```
KEY_ESCAPE, KEY_RETURN, KEY_SPACE, KEY_TAB
KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT
KEY_LSHIFT, KEY_RSHIFT, KEY_LCONTROL, KEY_RCONTROL
KEY_LMENU (Left Alt), KEY_RMENU (Right Alt)
KEY_A through KEY_Z, KEY_1 through KEY_0
KEY_F1 through KEY_F12
```

**DOOM key codes** (from doomgeneric/doomkeys.h or similar):
```
KEY_RIGHTARROW=0xae, KEY_LEFTARROW=0xac, KEY_UPARROW=0xad, KEY_DOWNARROW=0xaf
KEY_FIRE=0x80+0x43 (Ctrl), KEY_USE=0x20 (Space), KEY_ESCAPE=27
KEY_ENTER=13, KEY_TAB=9
KEY_RSHIFT=0x80+0x36
```

The mapping needs to be verified against whichever source port is chosen.

**Future: Gamepad support** — PZFBInputPanel's gamepad callbacks (`onPZFBGamepadDown`/`onPZFBGamepadUp`, `onPZFBGamepadAxis`) can map controller input to DOOM keys. The action mapping system (`mapAction`/`isActionDown`/`getActionValue`) makes this straightforward to add later.

### 4. Audio Approach

For DOOM audio, several options (in order of complexity):

**Option A: Let DOOM handle audio directly**
If the DOOM source port can output to ALSA/PulseAudio, and the pressure-vessel container passes audio through (which it does — PZ has audio), DOOM might just play its own audio. Simplest approach. But might conflict with PZ's FMOD.

**Option B: DOOM outputs PCM to stderr, Java pipes to FMOD**
Separate stderr from stdout (already solved in PZVP). DOOM writes raw PCM audio to stderr, Java reads it and pushes to FMOD via `FMOD_System_RAWPlayData`. Needs the `CreateRAWPlaySound` parameters figured out.

**Option C: DOOM writes WAV to a temp file, FMOD loads it**
Like PZVP's audio approach. Less ideal for real-time game audio (reactive sounds).

**Option D: No audio initially**
Get video and input working first. Add audio later. This is the pragmatic approach.

### 5. DOOM WAD Files

Users need a DOOM WAD file. Options:
- **Freedoom** (freedoom.github.io) — free open-source DOOM-compatible WAD, can be bundled
- **DOOM1.WAD** — shareware, freely distributable
- **User's own WADs** — if they own DOOM on Steam, they can point to their WAD

WAD files go in `~/Zomboid/PZDOOM/` (same pattern as PZVP's video directory).

## Implementation Plan

### Phase 1: DOOM Source Port
1. Research and select source port (doomgeneric recommended)
2. Write or find a stdout/stdin backend
3. Compile on Gentoo
4. Test: `./doom -iwad DOOM1.WAD` outputs frames to stdout, reads keys from stdin
5. Verify frame format: raw RGBA, known resolution (320x200 original)

### Phase 2: Process I/O in PZFB
1. Add stdin writing capability to PZFB's Java code
2. Either extend `fbStreamStart` or create `fbGameStart(path, args, width, height)`
3. Reuse existing ring buffer + `fbStreamFrame` for video output
4. Test: launch DOOM from Java, read frames, write keys

### Phase 3: PZ Mod (Lua)
1. Create mod structure: `mod/PZDOOM/42/...`
2. WAD file picker (like PZVP's video picker)
3. ISCollapsableWindow with PZFBInputPanel for rendering + input:
      - `MODE_FOCUS` + `captureToggleKey=Keyboard.KEY_SCROLL` + `escapeCloses=false` + `escapeReleasesCapture=true`
      - Default: hover DOOM window → exclusive (play), mouse away → passive (PZ control)
      - SCROLL LOCK locks EXCLUSIVE for uninterrupted play; ESC or SCROLL LOCK releases lock
      - `onPZFBCaptureToggle(false)` sends ESC to DOOM so it pauses when control returns to PZ
4. Key mapping: PZ Keyboard.KEY_* → DOOM key codes via onPZFBKeyDown/onPZFBKeyUp callbacks
5. Game loop: render frames, send inputs, repeat

### Phase 4: Audio (optional)
1. Try Option A (DOOM handles audio directly) first
2. If audio conflicts with PZ, try Option B (RAWPlayData)
3. If RAWPlayData params can't be figured out, go with no audio

### Phase 5: Polish
1. Menu integration (start game, load save, etc.)
2. Volume control
3. Pause when PZ pauses
4. Clean shutdown (kill DOOM process on window close / game exit)

## Key Lessons from PZVP Development

These hard-won lessons apply directly to PZDOOM:

### Pressure-Vessel Container
- PZ runs inside Steam's pressure-vessel container
- Host binaries at `/usr/bin/` are invisible inside the container
- Must use PZFB's `buildHostProcess()` which uses `/run/host/lib64/ld-linux-x86-64.so.2` + LD_LIBRARY_PATH
- Must clear `LD_PRELOAD` (JVM's libjsig.so breaks child processes)
- Must NOT merge stderr with stdout for binary data streams (`redirectErrorStream(false)`, `Redirect.DISCARD` for stderr)
- The compiled DOOM binary needs to be accessible from inside the container (put it in the mod folder or ~/Zomboid/PZDOOM/)

### Ring Buffer
- Writer thread MUST wait when buffer is full (don't overwrite unread frames)
- Reader MUST advance `bufStart` after reading to free space
- Slot calculation: `frameIndex % capacity` — NOT `(frameIndex - bufStart) % capacity`
- `bufCount` and `bufStart` MUST be `volatile` for cross-thread visibility

### GL Texture Upload
- `ByteBuffer.allocateDirect()` for GL data
- Queue via `RenderThread.queueInvokeOnRenderContext()`
- Set `startTime` AFTER starting audio/game, not before, for sync
- Floor draw coordinates to prevent sub-pixel jitter: `math.floor(drawX)`, etc.

### Workshop Publishing
- Mod needs `poster.png` (1024x1024) and `icon.png` (256x256) in `42/` directory
- Workshop upload dir: `~/Zomboid/Workshop/<ModName>/` with `preview.png` (256x256, <1000KB), `workshop.txt`, and `Contents/mods/<ModName>` symlink
- Every PZFB Java change requires Workshop update before testing (Steam overwrites local Lua files)

### PZ UI
- `ISCollapsableWindow:derive()` for custom windows
- `createChildren()` is called by `instantiate()` — add child panels there
- Anchors must be set before `instantiate()`
- After `addChild()`, MUST call `resizeWidget:bringToTop()` + `resizeWidget2:bringToTop()`
- `drawTextureScaled(tex, x, y, w, h, a, r, g, b)` — alpha BEFORE rgb
- `drawText(str, x, y, r, g, b, a, font)` — alpha AFTER rgb (DIFFERENT ORDER!)

### FMOD Audio
- `FMOD_Channel_SetPosition` returns error 32 (FMOD_ERR_INVALID_POSITION) on CREATESTREAM sounds if file length was cached at load time
- `FMOD_ACCURATETIME` flag (0x2000) helps but doesn't fully solve it
- Reliable approach: reload audio after file is complete, use `audioPlayFrom(posMs)` for seeking
- `audioPlayFrom`: stop channel → PlaySound(paused=true) → SetPosition → unpause
- For real-time game audio, `RAWPlayData` (VOIP API) is the right approach but params are undocumented

### File/Font Sizes
```lua
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local BUTTON_HGT = FONT_HGT_SMALL + 6
```

## DOOM-Specific Considerations

### Input Capture Mode Design

**Decision: MODE_FOCUS + captureToggleKey (SCROLL LOCK)**

The four PZFBInputPanel modes each have problems in isolation:
- **EXCLUSIVE:** Locks out PZ entirely — can't react to zombies approaching in-game
- **FOCUS:** Mouse leaving the panel drops exclusive capture — lose control of DOOM mid-fight
- **PASSIVE:** Keys leak to PZ — character walks around while you're playing DOOM
- **SELECTIVE:** Most DOOM keys overlap PZ bindings — impractical to register them all

**Solution:** FOCUS as the base mode with SCROLL LOCK as a capture toggle key:
- **Casual play:** Hover DOOM window → exclusive, move mouse away → passive. Natural.
- **Intense play:** SCROLL LOCK locks to EXCLUSIVE. Full DOOM control, mouse position irrelevant.
- **Panic/pause:** ESC (or SCROLL LOCK) releases the lock. `onPZFBCaptureToggle(false)` callback sends ESC to DOOM, pausing it simultaneously. One keystroke: DOOM pauses AND PZ control restored.

```lua
PZFBInputPanel:new(x, y, w, h, {
    mode                  = PZFBInput.MODE_FOCUS,
    captureToggleKey      = Keyboard.KEY_SCROLL,
    escapeCloses          = false,     -- ESC is DOOM's menu key, never close
    escapeReleasesCapture = true,      -- ESC releases toggle lock (safety)
})

function panel:onPZFBCaptureToggle(active)
    if not active then
        -- Leaving EXCLUSIVE lock — also pause DOOM
        sendKeyToDoom(DOOM_KEY_ESCAPE, 1)  -- press
        sendKeyToDoom(DOOM_KEY_ESCAPE, 0)  -- release
    end
end
```

### Resolution
DOOM's original resolution is 320x200. This is TINY. Use `PZFB.create()` (NEAREST filtering, not LINEAR) for pixel-perfect rendering. Scale up in `drawTextureScaled` for the display. At 2x: 640x400. At 3x: 960x600.

### Frame Rate
DOOM runs at 35 fps (original tick rate). The ring buffer and frame timing need to account for this non-standard rate.

### Input Timing
DOOM's input is polled per-tick (35 times/sec). PZ's input events fire per-frame (~60fps) via PZFBInputPanel's `onPZFBKeyDown`/`onPZFBKeyUp`/`onPZFBKeyRepeat` callbacks. Feed key events to the DOOM process as they arrive — let the DOOM port handle its own timing and input buffering. The `onPZFBKeyRepeat` callback fires every frame while a key is held, but for DOOM we only need press/release events — ignore repeats.

### Game Speed
DOOM has its own game clock. It should NOT be tied to PZ's game speed. Use real-time (`getTimestampMs()`) for frame timing, not PZ's game time multiplier.

## File Structure

```
~/pzdoom/
├── CLAUDE.md                    # Development rules
├── IMPLEMENTATION_GUIDE.md      # This file
├── README.md                    # Public docs
├── LICENSE                      # MIT
├── doom/                        # Compiled DOOM source port binary + config
│   └── doomgeneric              # The binary (or whatever port is chosen)
├── wads/                        # Optional: bundled Freedoom WADs
└── mod/
    └── PZDOOM/
        ├── common/.gitkeep
        └── 42/
            ├── mod.info
            ├── poster.png
            ├── icon.png
            └── media/lua/client/PZDOOM/
                ├── PZDOOMMain.lua      # Entry point, keybinding
                ├── PZDOOMGame.lua      # Game process management, input translation
                └── PZDOOMWindow.lua    # UI window with framebuffer display
```
