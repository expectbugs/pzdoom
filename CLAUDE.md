# PZDOOM — DOOM in Project Zomboid: Development Rules

## RULE ZERO: Verify Before Execute

***NEVER run commands based on guesses or assumptions. Before any PZ Lua API call, read the actual PZ source for correct function signatures. Before any Java class modification, verify the method exists and its signature matches. Before any GL call, verify the constant values. One correct approach beats three failed attempts.***

***NEVER GUESS. ALWAYS VERIFY. ALWAYS check the real source.***

## Critical: Source Code Verification

- **B42 client source (AUTHORITATIVE):** `/home/user/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid/media/lua/`
- **PZ Java jar:** `/home/user/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid/projectzomboid.jar`
- **DO NOT USE the Dedicated Server source** at `/opt/steamcmd/` — it is STALE, OUTDATED, and WRONG for Build 42.
- **Verified Workshop mods** at: `/home/user/.local/share/Steam/steamapps/workshop/content/108600/`

## System Environment

- **Machine:** beardos — Gentoo Linux, OpenRC, RTX 3090, 32GB RAM
- **Python 3.13** — use `./venv/bin/python` (no system pip)
- **Java 25 JDK:** `/usr/lib64/openjdk-25/bin/javac` and `/usr/lib64/openjdk-25/bin/java`
- **Java 21 JDK (system default):** `/usr/bin/javac` — DO NOT USE for PZ compilation
- **PZ Install:** `/home/user/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid/`
- **PZ bundled JRE:** `<PZ Install>/jre64/` — Zulu JDK 25, no javac
- **PZ launch config:** `<PZ Install>/ProjectZomboid64.json` — classpath `[".","projectzomboid.jar"]`, `-Xmx3072m`
- **PZFB project:** `~/pzfb/` — the framebuffer library this mod depends on
- **PZVP project:** `~/pzvp/` — video player mod (reference implementation for PZFB streaming)

## What This Project Is

A Project Zomboid mod that lets players play DOOM in-game using PZFB (Video Framebuffer) for rendering and PZFBInputPanel for keyboard capture. A headless DOOM source port runs as an external process, piping raw video frames to Java via stdout and receiving keyboard input via stdin.

## Architecture Overview

```
[DOOM Source Port] ←stdin (keys)── [Java: Process stdin writer]
       │
       │ stdout (raw RGBA frames)
       ▼
[Java: Ring Buffer] → [PZFB Texture] → [ISCollapsableWindow]
       │
       │ stderr (audio PCM — optional)
       ▼
[FMOD RAWPlayData or WAV pipe]
```

### Video Pipeline (identical to PZVP)
1. DOOM source port outputs raw RGBA frames to stdout
2. Java reads frames into an in-memory ring buffer (same as PZVP's `fbStreamFrame`)
3. Lua calls `fbStreamFrame()` to upload current frame to GL texture
4. `drawTextureScaled()` renders in a UI panel

### Input Pipeline (NEW — bidirectional)
1. PZFBInputPanel (MODE_FOCUS + captureToggleKey=SCROLL LOCK) captures keyboard events via `onPZFBKeyDown`/`onPZFBKeyUp`
2. Default: FOCUS mode — exclusive when mouse hovers DOOM window, passive otherwise
3. SCROLL LOCK toggles to full EXCLUSIVE lock for uninterrupted play
4. ESC (or SCROLL LOCK again) releases the lock AND sends ESC to DOOM (pauses game) via `onPZFBCaptureToggle` callback
5. Lua sends key events to Java via a new method (e.g., `fbProcessWriteInput`)
6. Java writes to `Process.getOutputStream()` (DOOM's stdin)
7. DOOM source port reads stdin for keyboard input

### Audio Pipeline (TBD — research needed)
Options:
- DOOM source port outputs audio to a file/pipe, load via FMOD (like PZVP)
- Use FMOD's `RAWPlayData` API for real-time PCM streaming (undocumented params)
- Let the source port handle audio directly (if it can access ALSA/PulseAudio from inside pressure-vessel)

## PZFB Dependency — Complete API Reference

PZFB (Video Framebuffer, Workshop ID 3698742271) provides pixel-level framebuffer rendering.
GitHub: https://github.com/expectbugs/pzfb

### How PZFB Works
A patched `zombie.core.Color` class adds static methods for framebuffer operations. All GL calls are dispatched to PZ's render thread via `RenderThread.queueInvokeOnRenderContext()`. The patched class files must be deployed to the PZ install directory via install scripts.

### Lua API (require "PZFB/PZFBApi")

#### Framebuffer
```lua
PZFB.isAvailable()                    -- boolean: class files deployed?
PZFB.getVersion()                     -- version string
PZFB.create(width, height)            -- fb handle (NEAREST filtering, good for pixel art/games)
PZFB.createLinear(width, height)      -- fb handle (LINEAR filtering, good for video)
PZFB.isReady(fb)                      -- boolean: GL texture allocated?
PZFB.fill(fb, r, g, b, a)            -- fill solid color (0-255 each)
PZFB.loadRaw(fb, path)               -- load raw RGBA file (w*h*4 bytes)
PZFB.loadRawFrame(fb, path, idx)      -- load frame from concatenated raw file
PZFB.fileSize(path)                   -- file size in bytes (-1 if not found)
PZFB.getTexture(fb)                   -- get PZ Texture for drawTextureScaled()
PZFB.destroy(fb)                      -- free GL resources
```

#### Streaming (from PZVP — may be reusable)
```lua
PZFB.streamStart(path, qualityScale, bufferFrames) -- start ffmpeg streaming
PZFB.streamFrame(fb, frameIndex)      -- upload frame from ring buffer to texture
PZFB.streamSeek(timeSec)              -- seek (kill/restart ffmpeg)
PZFB.streamStop()                     -- stop streaming
PZFB.streamStatus()                   -- 0=idle 1=probing 2=buffering 3=ready 4=done 5=error
PZFB.streamWidth/Height/Fps/Duration/TotalFrames()
```

#### Audio (direct FMOD — bypasses sound bank system)
```lua
PZFB.audioLoad(path)                  -- load audio file (CREATESTREAM + ACCURATETIME)
PZFB.audioPlay()                      -- start playback
PZFB.audioPlayFrom(posMs)             -- stop + play from position (reliable seek)
PZFB.audioPause() / audioResume()     -- true pause/resume
PZFB.audioStop()                      -- stop and release
PZFB.audioSeek(posMs)                 -- seek (may fail on CREATESTREAM, use audioPlayFrom)
PZFB.audioSetVolume(vol)              -- 0.0-1.0
PZFB.audioGetPosition()               -- current position in ms
PZFB.audioGetLength()                 -- total length in ms
PZFB.audioIsPlaying()                 -- boolean
```

#### Utilities
```lua
PZFB.ffmpegAvailable()                -- boolean (checks via pressure-vessel if needed)
PZFB.listDir(path)                    -- newline-separated filenames
PZFB.readTextFile(path)               -- read file from any path
```

#### FMOD RAWPlayData (from PZ's VOIP system — UNDOCUMENTED but exists)
```lua
-- These are Java-level, NOT yet wrapped in PZFBApi.lua:
-- fmod.javafmod.FMOD_System_CreateRAWPlaySound(long, long, long) → long soundHandle
-- fmod.javafmod.FMOD_System_RAWPlayData(long soundHandle, byte[] data, long numBytes) → int
-- fmod.javafmod.FMOD_System_RAWPlayData(long soundHandle, short[] data, long numSamples) → int
-- fmod.javafmod.FMOD_System_SetRawPlayBufferingPeriod(long period) → long
-- fmod.javafmod.FMOD_RAWPlaySound_Release(long soundHandle) → int
-- Parameters for CreateRAWPlaySound are UNKNOWN — need empirical testing.
-- Data format: 16-bit signed little-endian PCM (verified from bytecode analysis).
-- Used by zombie.core.raknet.VoiceManager for VOIP playback.
```

### Input Capture (PZFBInputPanel) — v2.0

PZFBInputPanel is an ISPanelJoypad subclass with four capture modes, keyboard/mouse/gamepad support, and an action mapping system.

#### Capture Modes
```lua
PZFBInput.MODE_EXCLUSIVE = 1   -- Consume ALL keys, block game entirely
PZFBInput.MODE_SELECTIVE = 2   -- Consume only registered keys
PZFBInput.MODE_PASSIVE   = 3   -- Read everything, consume nothing
PZFBInput.MODE_FOCUS     = 4   -- Exclusive when mouse over panel, passive otherwise
```

#### Constructor & Lifecycle
```lua
require "PZFB/PZFBInput"

local panel = PZFBInputPanel:new(x, y, w, h, {
    mode              = PZFBInput.MODE_EXCLUSIVE,  -- default
    captureToggleKey  = nil,          -- optional Keyboard.KEY_* to lock/unlock capture
    escapeCloses      = true,         -- ESC closes panel
    escapeReleasesCapture = true,     -- ESC releases toggle (safety)
    playerNum         = 0,
    forceCursorVisible = true,
    autoGrab          = false,        -- auto-grab on createChildren
})
panel:initialise()
panel:addToUIManager()
panel:grabInput()  -- start capturing

panel:releaseInput()  -- stop capturing, release all state
panel:isCapturing()   -- boolean
panel:setMode(mode)   -- change mode at runtime
```

#### Keyboard Callbacks & Polling
```lua
function panel:onPZFBKeyDown(key) end     -- first frame of key press
function panel:onPZFBKeyRepeat(key) end   -- every frame while held
function panel:onPZFBKeyUp(key) end       -- key release

panel:isKeyDown(Keyboard.KEY_LEFT)        -- polling
panel:isModifierDown("shift")             -- checks both L+R variants ("shift", "ctrl", "alt")
```

#### Mouse Callbacks & Polling
```lua
function panel:onPZFBMouseDown(x, y, btn) end   -- btn: 0=left, 1=right, 2=middle, 2+=extra
function panel:onPZFBMouseUp(x, y, btn) end
function panel:onPZFBMouseMove(x, y, dx, dy) end -- panel-relative coords + delta
function panel:onPZFBMouseWheel(delta) end

local mx, my = panel:getMousePos()        -- panel-relative
panel:isMouseButtonDown(0)                -- 0=left, 1=right, 2=middle
```

#### Gamepad Callbacks & Polling
```lua
function panel:onPZFBGamepadDown(slot, button) end
function panel:onPZFBGamepadUp(slot, button) end
function panel:onPZFBGamepadAxis(slot, axisName, val) end  -- "leftX","leftY","rightX","rightY", -1.0 to 1.0
function panel:onPZFBGamepadTrigger(slot, side, pressed) end  -- "left"/"right"

panel:getGamepadAxis(slot, "leftX")       -- -1.0 to 1.0
panel:isGamepadDown(slot, button)
panel:isGamepadTriggerDown(slot, "left")
panel:setSlotDevice(2, "controller", 0)   -- assign controller to slot
panel:setSlotAutoAssign(2, true)          -- auto-assign on first button press
```

#### Action Mapping System
```lua
panel:mapAction("fire",  { key = Keyboard.KEY_LCONTROL })
panel:mapAction("fire",  { gamepad = Joypad.RBumper })
panel:mapAction("moveX", { axis = "leftX" })
panel:mapAction("moveX", { keyNeg = Keyboard.KEY_LEFT, keyPos = Keyboard.KEY_RIGHT })

panel:isActionDown("fire")       -- true if ANY binding active
panel:getActionValue("moveX")    -- -1.0 to 1.0 (analog-aware)
panel:unmapAction("fire")
```

#### Selective Capture (MODE_SELECTIVE only)
```lua
panel:captureKey(Keyboard.KEY_SPACE)
panel:captureKeys({Keyboard.KEY_LEFT, Keyboard.KEY_RIGHT})
panel:captureBinding("Forward")           -- follows user rebinds
panel:releaseKey(Keyboard.KEY_SPACE)
panel:releaseBinding("Forward")
panel:releaseAllCaptures()
```

#### Config Persistence
```lua
panel:saveInputConfig("pzdoom")   -- writes ~/Zomboid/Lua/PZFB_input_pzdoom.cfg
panel:loadInputConfig("pzdoom")   -- reads and applies
```

#### Automatic Cleanup
Input is automatically released on: panel close, hide, remove, player death, main menu.

Key constants (verified in B42): `KEY_ESCAPE`, `KEY_RETURN`, `KEY_SPACE`, `KEY_UP/DOWN/LEFT/RIGHT`, `KEY_LSHIFT/RSHIFT`, `KEY_LCONTROL/RCONTROL`, `KEY_TAB`, `KEY_A` through `KEY_Z`, `KEY_1` through `KEY_0`, etc. Use `Keyboard.KEY_*`.

### Drawing the framebuffer in a UI panel (verified from ISUIElement.lua:883)
```lua
-- drawTextureScaled(texture, x, y, w, h, a, r, g, b) — NOTE: alpha BEFORE rgb
function MyPanel:render()
    ISPanel.render(self)
    if fb and PZFB.isReady(fb) then
        self:drawTextureScaled(PZFB.getTexture(fb), x, y, w, h, 1, 1, 1, 1)
    end
end
```

### Low-level Java API (Color.fb* static methods)
```lua
Color.fbCreate(width, height)          -- Texture (NEAREST)
Color.fbCreateLinear(width, height)    -- Texture (LINEAR)
Color.fbIsReady(tex)                   -- boolean
Color.fbFill(tex, r, g, b, a)         -- fill solid color
Color.fbLoadRaw(tex, path)            -- load raw RGBA file
Color.fbLoadRawFrame(tex, path, idx)  -- load frame from concatenated raw
Color.fbStreamFrame(tex, frameIndex)  -- load from ring buffer
Color.fbDestroy(tex)                   -- free resources
```

## Pressure-Vessel Container (CRITICAL)

PZ runs inside Steam's pressure-vessel container. Host binaries at `/usr/bin/` are NOT visible. All external process execution MUST use the existing `buildHostProcess()` infrastructure in Color.java.

### How it works (already implemented in PZFB):
- `buildHostProcess(mergeStderr, args...)` handles everything
- Uses host's `/run/host/lib64/ld-linux-x86-64.so.2` as dynamic linker
- Sets `LD_LIBRARY_PATH` from host's `/run/host/etc/ld.so.conf` (parsed, includes followed)
- Clears `LD_PRELOAD` (JVM's `libjsig.so` breaks child processes)
- `mergeStderr=false` for binary data on stdout (raw frames)
- `mergeStderr=true` for text commands (version checks, etc.)
- Outside pressure-vessel, passes commands through unchanged

### Key lesson: stderr MUST NOT merge with stdout for binary streaming
ffmpeg/DOOM will write diagnostic text to stderr. If merged with stdout, it corrupts the raw RGBA byte stream. Use `buildHostProcess(false, ...)` and `Redirect.DISCARD` for stderr.

## PZ UI Patterns (Verified from B42 source)

### ISCollapsableWindow
```lua
local window = ISCollapsableWindow:new(x, y, width, height)
window.minimumWidth = 200
window.minimumHeight = 150
window:initialise()
window:instantiate()
window:setTitle("DOOM")
window:setResizable(true)

local th = window:titleBarHeight()  -- math.max(16, self.titleFontHgt + 1)
local rh = window:resizeWidgetHeight()  -- (BUTTON_HGT/2)+2

-- Add children AFTER initialise/instantiate
-- Anchors MUST be set before instantiate (or in :new constructor)
-- CRITICAL: after addChild(), call resizeWidget:bringToTop() and resizeWidget2:bringToTop()
```

### ISButton
```lua
-- ISButton:new(x, y, w, h, title, target, onclick)
-- Callback signature: onclick(target, button, arg1, arg2, ...)
local btn = ISButton:new(x, y, 60, BUTTON_HGT, "Start", self, self.onStartClick)
btn:initialise()
btn:instantiate()
parent:addChild(btn)
```

### Drawing functions (from ISUIElement.lua)
```lua
drawRectStatic(x, y, w, h, a, r, g, b)          -- alpha BEFORE rgb
drawRectBorderStatic(x, y, w, h, a, r, g, b)    -- alpha BEFORE rgb  
drawText(str, x, y, r, g, b, a, font)           -- alpha AFTER rgb (DIFFERENT!)
drawTextureScaled(tex, x, y, w, h, a, r, g, b)  -- alpha BEFORE rgb
```

### Events & Keyboard (from B42 source)
```lua
Events.OnGameStart.Add(function() end)
Events.OnTick.Add(function() end)       -- every frame, no params
Events.OnKeyPressed.Add(function(key) end)
getTimestampMs()                         -- real-time wall-clock ms
Core.getMyDocumentFolder()               -- ~/Zomboid
getFileSeparator()                       -- / or \
```

### ISBaseObject:derive (for subclassing)
```lua
-- ISBaseObject → ISUIElement → ISPanel → ISCollapsableWindow
-- derive() creates a new class from parent
MyPanel = ISPanel:derive("MyPanel")
```

## B42 Mod Structure

```
mod/PZDOOM/
├── common/
│   └── .gitkeep
└── 42/
    ├── mod.info          # MUST be in 42/, NOT mod root
    ├── poster.png        # MUST be in 42/, 1024x1024
    ├── icon.png          # MUST be in 42/, 256x256
    └── media/
        └── lua/client/PZDOOM/
            └── *.lua
```

### mod.info
```
name=DOOM
id=PZDOOM
require=PZFB
description=Play DOOM in Project Zomboid.
poster=poster.png
icon=icon.png
modversion=0.1.0
versionMin=42.0
```

### Workshop upload structure
```
~/Zomboid/Workshop/PZDOOM/
├── preview.png          (256x256, under 1000KB)
├── workshop.txt         (title, description, tags)
└── Contents/mods/
    └── PZDOOM → ~/pzdoom/mod/PZDOOM  (symlink)
```

### Symlink for testing
```bash
ln -s ~/pzdoom/mod/PZDOOM ~/Zomboid/mods/PZDOOM
```

## B42 PZ Lua Sandbox Limitations

- **No `io.*` or `os.*` modules.** Lua is sandboxed.
- **No `next()`, `rawget(table, number)`, `string.byte()`, `math.huge`** — Kahlua VM limitations.
- **No `string.format(%g)`, `string.gsub(str, pat, TABLE)`** — Kahlua limitations.
- **File I/O:** `getFileWriter(filename, createIfNull, append)` and `getFileReader(filename, createIfNull)` write to `~/Zomboid/Lua/` only.
- **Cannot run external processes** from Lua — must go through PZFB's Java methods.

## PZFB Workshop Update Workflow (CRITICAL)

**Every time PZFB's Java code (Color.java) is modified:**
1. Build and deploy: `cd ~/pzfb && ./build.sh --deploy`
2. Commit and push to GitHub
3. **User must update PZFB on Steam Workshop BEFORE testing** — Steam overwrites local mod files with Workshop versions on launch. The Workshop upload tool is INSIDE PZ (Main Menu → Workshop).
4. THEN restart PZ and test

The class files at `<PZ install>/zombie/core/Color*.class` are NOT overwritten by Steam (they're outside the mod folder). But the Lua files in the mod folder ARE synced from Workshop.

## User Profile

- **Name:** Adam (expectbugs)
- **System:** Gentoo Linux, OpenRC, XFCE4 desktop, RTX 3090, 32GB RAM, 4K display
- **Communication style:** Direct, casual, moves fast. Don't over-explain.
- **Key rule:** NEVER GUESS. Always verify against real source code.
