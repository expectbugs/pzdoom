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
    -- LWJGL key codes follow keyboard scan codes, NOT alphabetical order!
    -- Verified from: javap -cp projectzomboid.jar org.lwjglx.input.Keyboard
    KEY_MAP[Keyboard.KEY_A] = 97   -- 'a'
    KEY_MAP[Keyboard.KEY_B] = 98   -- 'b'
    KEY_MAP[Keyboard.KEY_C] = 99   -- 'c'
    KEY_MAP[Keyboard.KEY_D] = 100  -- 'd'
    KEY_MAP[Keyboard.KEY_E] = 101  -- 'e'
    KEY_MAP[Keyboard.KEY_F] = 102  -- 'f'
    KEY_MAP[Keyboard.KEY_G] = 103  -- 'g'
    KEY_MAP[Keyboard.KEY_H] = 104  -- 'h'
    KEY_MAP[Keyboard.KEY_I] = 105  -- 'i'
    KEY_MAP[Keyboard.KEY_J] = 106  -- 'j'
    KEY_MAP[Keyboard.KEY_K] = 107  -- 'k'
    KEY_MAP[Keyboard.KEY_L] = 108  -- 'l'
    KEY_MAP[Keyboard.KEY_M] = 109  -- 'm'
    KEY_MAP[Keyboard.KEY_N] = 110  -- 'n'
    KEY_MAP[Keyboard.KEY_O] = 111  -- 'o'
    KEY_MAP[Keyboard.KEY_P] = 112  -- 'p'
    KEY_MAP[Keyboard.KEY_Q] = 113  -- 'q'
    KEY_MAP[Keyboard.KEY_R] = 114  -- 'r'
    KEY_MAP[Keyboard.KEY_S] = 115  -- 's'
    KEY_MAP[Keyboard.KEY_T] = 116  -- 't'
    KEY_MAP[Keyboard.KEY_U] = 117  -- 'u'
    KEY_MAP[Keyboard.KEY_V] = 118  -- 'v'
    KEY_MAP[Keyboard.KEY_W] = 119  -- 'w'
    KEY_MAP[Keyboard.KEY_X] = 120  -- 'x'
    KEY_MAP[Keyboard.KEY_Y] = 121  -- 'y'
    KEY_MAP[Keyboard.KEY_Z] = 122  -- 'z'

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
-- User data directory for deployed DOOM binary and custom WADs.
--
local function getUserDir()
    return Core.getMyDocumentFolder() .. getFileSeparator() .. "PZDOOM"
end

--
-- Find a .dat file in the mod's media/doom/ directory.
-- Handles uncertainty about what getDir() returns.
--
local function findModDat(filename)
    local sep = getFileSeparator()
    local modInfo = getModInfoByID("PZDOOM")
    if not modInfo then return nil end

    local dir = modInfo:getDir()
    if dir then
        local p = dir .. sep .. "media" .. sep .. "doom" .. sep .. filename
        if PZFB.fileSize(p) > 0 then return p end
        p = dir .. sep .. "42" .. sep .. "media" .. sep .. "doom" .. sep .. filename
        if PZFB.fileSize(p) > 0 then return p end
    end

    local ok, vdir = pcall(function() return modInfo:getVersionDir() end)
    if ok and vdir then
        local p = vdir .. sep .. "media" .. sep .. "doom" .. sep .. filename
        if PZFB.fileSize(p) > 0 then return p end
    end

    return nil
end

--
-- Auto-deploy binaries from mod .dat files to ~/Zomboid/PZDOOM/ on first run.
-- Workshop blocks .exe/.dll/.sh, so binaries ship as .dat and get copied here.
--
local function deployBinaries()
    local sep = getFileSeparator()
    local destDir = getUserDir()

    local files
    if isWindows() then
        files = {
            { dat = "pzdoom_win.dat", dest = "pzdoom.exe" },
            { dat = "SDL2.dat",       dest = "SDL2.dll" },
            { dat = "SDL2_mixer.dat", dest = "SDL2_mixer.dll" },
        }
    else
        files = {
            { dat = "pzdoom.dat", dest = "pzdoom" },
        }
    end

    for _, f in ipairs(files) do
        local destPath = destDir .. sep .. f.dest
        if PZFB.fileSize(destPath) <= 0 then
            -- Not yet deployed — find the .dat in the mod folder and copy
            local srcPath = findModDat(f.dat)
            if srcPath then
                print("[PZDOOM] Deploying " .. f.dat .. " -> " .. destPath)
                PZFB.copyFile(srcPath, destPath)
            end
        end
    end
end

--
-- Find the DOOM binary path.
-- Auto-deploys from mod .dat files if not already present.
--
local function findBinary()
    local binaryName = isWindows() and "pzdoom.exe" or "pzdoom"
    local userPath = getUserDir() .. getFileSeparator() .. binaryName

    -- Already deployed?
    if PZFB.fileSize(userPath) > 0 then
        return userPath
    end

    -- Try auto-deploy from mod's .dat files
    deployBinaries()

    -- Check again
    if PZFB.fileSize(userPath) > 0 then
        return userPath
    end

    return nil
end

--
-- Find all available WAD files.
-- Scans bundled WADs from mod directory + user WADs from ~/Zomboid/PZDOOM/.
-- Returns table of {name=, path=} entries.
--
function PZDOOMGame.findWads()
    local wads = {}
    local seen = {}
    local sep = getFileSeparator()

    local function scanDir(dirPath)
        if not dirPath then return end
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

    -- Bundled WADs from mod directory (delivered via Workshop)
    local modInfo = getModInfoByID("PZDOOM")
    if modInfo then
        local dir = modInfo:getDir()
        if dir then
            scanDir(dir .. sep .. "media" .. sep .. "doom")
            scanDir(dir .. sep .. "42" .. sep .. "media" .. sep .. "doom")
        end
        local ok, vdir = pcall(function() return modInfo:getVersionDir() end)
        if ok and vdir then
            scanDir(vdir .. sep .. "media" .. sep .. "doom")
        end
    end

    -- User WADs from ~/Zomboid/PZDOOM/
    scanDir(getUserDir())

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
    local args = '-iwad "' .. wadPath .. '"'
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
