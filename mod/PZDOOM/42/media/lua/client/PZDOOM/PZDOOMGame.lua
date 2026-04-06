--
-- PZDOOMGame.lua — DOOM process management and key translation
--
-- Manages the doomgeneric_pz process lifecycle, translates LWJGL key codes
-- to DOOM key codes, and handles frame consumption from the ring buffer.
--

require "PZFB/PZFBApi"

PZDOOMGame = {}

-- DOOM resolution (compile-time constant in doomgeneric_pz)
PZDOOMGame.DOOM_WIDTH = 320
PZDOOMGame.DOOM_HEIGHT = 200

--
-- LWJGL Keyboard.KEY_* → DOOM key code translation table
-- DOOM key codes verified from doomgeneric/doomkeys.h
-- SDL backend maps Ctrl→KEY_FIRE, Space→KEY_USE (verified from doomgeneric_sdl.c)
--
local KEY_MAP = {}

local function buildKeyMap()
    -- Arrow keys
    KEY_MAP[Keyboard.KEY_LEFT]     = 0xAC  -- KEY_LEFTARROW
    KEY_MAP[Keyboard.KEY_RIGHT]    = 0xAE  -- KEY_RIGHTARROW
    KEY_MAP[Keyboard.KEY_UP]       = 0xAD  -- KEY_UPARROW
    KEY_MAP[Keyboard.KEY_DOWN]     = 0xAF  -- KEY_DOWNARROW

    -- Action keys (matching SDL backend: Ctrl=FIRE, Space=USE)
    KEY_MAP[Keyboard.KEY_LCONTROL] = 0xA3  -- KEY_FIRE
    KEY_MAP[Keyboard.KEY_RCONTROL] = 0xA3  -- KEY_FIRE
    KEY_MAP[Keyboard.KEY_SPACE]    = 0xA2  -- KEY_USE

    -- Modifiers
    KEY_MAP[Keyboard.KEY_LSHIFT]   = 0xB6  -- KEY_RSHIFT (run)
    KEY_MAP[Keyboard.KEY_RSHIFT]   = 0xB6  -- KEY_RSHIFT
    KEY_MAP[Keyboard.KEY_LMENU]    = 0xB8  -- KEY_LALT (strafe)
    KEY_MAP[Keyboard.KEY_RMENU]    = 0xB8  -- KEY_LALT

    -- Special keys
    KEY_MAP[Keyboard.KEY_ESCAPE]   = 27    -- KEY_ESCAPE
    KEY_MAP[Keyboard.KEY_RETURN]   = 13    -- KEY_ENTER
    KEY_MAP[Keyboard.KEY_TAB]      = 9     -- KEY_TAB
    KEY_MAP[Keyboard.KEY_BACK]     = 0x7F  -- KEY_BACKSPACE
    KEY_MAP[Keyboard.KEY_PAUSE]    = 0xFF  -- KEY_PAUSE
    KEY_MAP[Keyboard.KEY_EQUALS]   = 0x3D  -- KEY_EQUALS
    KEY_MAP[Keyboard.KEY_MINUS]    = 0x2D  -- KEY_MINUS

    -- A-Z → lowercase ASCII (97-122)
    -- Keyboard.KEY_A through KEY_Z are sequential in LWJGL
    for i = 0, 25 do
        KEY_MAP[Keyboard.KEY_A + i] = 97 + i
    end

    -- Number keys → ASCII digits
    -- KEY_1 through KEY_9 are sequential, KEY_0 follows
    for i = 0, 8 do
        KEY_MAP[Keyboard.KEY_1 + i] = 49 + i  -- '1'=49 through '9'=57
    end
    KEY_MAP[Keyboard.KEY_0] = 48  -- '0'=48

    -- F1-F10 (sequential: 0x80+0x3B through 0x80+0x44)
    for i = 0, 9 do
        KEY_MAP[Keyboard.KEY_F1 + i] = 0xBB + i
    end
    -- F11 and F12 are NOT sequential with F1-F10 in DOOM
    KEY_MAP[Keyboard.KEY_F11] = 0xD7  -- 0x80+0x57
    KEY_MAP[Keyboard.KEY_F12] = 0xD8  -- 0x80+0x58

    -- Additional useful keys
    KEY_MAP[Keyboard.KEY_COMMA]    = 44   -- ','
    KEY_MAP[Keyboard.KEY_PERIOD]   = 46   -- '.'
    KEY_MAP[Keyboard.KEY_SLASH]    = 47   -- '/'
    KEY_MAP[Keyboard.KEY_SEMICOLON] = 59  -- ';'
    KEY_MAP[Keyboard.KEY_APOSTROPHE] = 39 -- '\''
    KEY_MAP[Keyboard.KEY_LBRACKET] = 91   -- '['
    KEY_MAP[Keyboard.KEY_RBRACKET] = 93   -- ']'
    KEY_MAP[Keyboard.KEY_BACKSLASH] = 92  -- '\\'
    KEY_MAP[Keyboard.KEY_GRAVE]    = 96   -- '`'
end

--
-- Detect platform for binary selection
--
local function isWindows()
    return getFileSeparator() == "\\"
end

--
-- Find the DOOM binary path
-- First checks the mod's media/doom/ directory, then ~/Zomboid/PZDOOM/
--
local function findBinary()
    local binaryName = isWindows() and "pzdoom.exe" or "pzdoom"
    local sep = getFileSeparator()

    -- Try mod directory first (where Workshop puts it)
    -- The mod's media dir is accessible via getModInfoByID
    local modInfo = getModInfoByID("PZDOOM")
    if modInfo then
        local modDir = modInfo:getDir()
        if modDir then
            local modPath = modDir .. sep .. "media" .. sep .. "doom" .. sep .. binaryName
            if PZFB.fileSize(modPath) > 0 then
                return modPath
            end
        end
    end

    -- Fallback: ~/Zomboid/PZDOOM/
    local userDir = Core.getMyDocumentFolder() .. sep .. "PZDOOM"
    local userPath = userDir .. sep .. binaryName
    if PZFB.fileSize(userPath) > 0 then
        return userPath
    end

    return nil
end

--
-- Find all available WAD files
-- Checks mod's media/doom/ and ~/Zomboid/PZDOOM/
-- Returns table of {name=, path=} entries
--
function PZDOOMGame.findWads()
    local wads = {}
    local seen = {}
    local sep = getFileSeparator()

    local function scanDir(dirPath)
        local listing = PZFB.listDir(dirPath)
        if listing == "" then return end
        for line in string.gmatch(listing, "[^\n]+") do
            local lower = string.lower(line)
            if string.sub(lower, -4) == ".wad" and not seen[lower] then
                seen[lower] = true
                table.insert(wads, {
                    name = line,
                    path = dirPath .. sep .. line,
                })
            end
        end
    end

    -- Scan mod's media/doom/ directory
    local modInfo = getModInfoByID("PZDOOM")
    if modInfo then
        local modDir = modInfo:getDir()
        if modDir then
            scanDir(modDir .. sep .. "media" .. sep .. "doom")
        end
    end

    -- Scan ~/Zomboid/PZDOOM/
    local userDir = Core.getMyDocumentFolder() .. sep .. "PZDOOM"
    scanDir(userDir)

    return wads
end

--
-- Create a new PZDOOMGame instance
--
function PZDOOMGame:new()
    local o = {}
    setmetatable(o, { __index = PZDOOMGame })
    o.state = "IDLE"          -- IDLE, STARTING, RUNNING, STOPPED, ERROR
    o.fb = nil                -- PZFB framebuffer handle
    o.currentFrame = -1       -- last displayed frame index
    o.binaryPath = nil        -- resolved binary path
    o.wadPath = nil           -- selected WAD path
    o.errorMsg = nil          -- error message for display

    -- Build key map on first use
    if not KEY_MAP[Keyboard.KEY_ESCAPE] then
        buildKeyMap()
    end

    -- Resolve binary
    o.binaryPath = findBinary()

    return o
end

--
-- Start the DOOM process with a given WAD
--
function PZDOOMGame:start(wadPath)
    self:stop()

    if not self.binaryPath then
        self.errorMsg = "DOOM binary not found"
        self.state = "ERROR"
        return
    end

    self.wadPath = wadPath
    self.currentFrame = -1

    -- Create framebuffer (NEAREST filtering for pixel-perfect DOOM)
    self.fb = PZFB.create(PZDOOMGame.DOOM_WIDTH, PZDOOMGame.DOOM_HEIGHT)

    -- Launch the process
    local args = "-iwad " .. wadPath
    PZFB.gameStart(self.binaryPath, PZDOOMGame.DOOM_WIDTH, PZDOOMGame.DOOM_HEIGHT, args)
    self.state = "STARTING"
    self.errorMsg = nil
end

--
-- Stop the DOOM process and clean up
--
function PZDOOMGame:stop()
    PZFB.gameStop()
    if self.fb then
        PZFB.destroy(self.fb)
        self.fb = nil
    end
    self.currentFrame = -1
    self.state = "IDLE"
end

--
-- Send a key event to DOOM (translates LWJGL → DOOM key code)
-- pressed: 1 for press, 0 for release
--
function PZDOOMGame:sendKey(lwjglKey, pressed)
    if self.state ~= "RUNNING" and self.state ~= "STARTING" then return end
    local doomKey = KEY_MAP[lwjglKey]
    if doomKey then
        PZFB.gameSendInput(doomKey, pressed)
    end
end

--
-- Update game state — call once per frame from render()
--
function PZDOOMGame:update()
    if self.state == "IDLE" or self.state == "ERROR" then return end

    local status = PZFB.gameStatus()

    -- Check for process exit or error
    if status >= 3 then
        if status == 4 then
            self.errorMsg = PZFB.gameError()
            self.state = "ERROR"
        else
            self.state = "STOPPED"
        end
        return
    end

    -- Transition from STARTING to RUNNING when first frame arrives
    if self.state == "STARTING" and status >= 2 then
        self.state = "RUNNING"
    end

    -- Display the latest available frame
    if not self.fb or not PZFB.isReady(self.fb) then return end

    local bufStart = PZFB.streamBufferStart()
    local bufCount = PZFB.streamBufferCount()
    if bufCount <= 0 then return end

    local latest = bufStart + bufCount - 1
    if latest ~= self.currentFrame then
        if PZFB.streamFrame(self.fb, latest) then
            self.currentFrame = latest
        end
    end
end
