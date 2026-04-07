--
-- PZDOOMWindow.lua — DOOM game window with framebuffer display and input capture
--
-- Contains:
--   PZDOOMGamePanel  — PZFBInputPanel subclass for rendering + keyboard capture
--   PZDOOMWadPicker  — WAD file selection panel
--   PZDOOMWelcome    — Instructions screen shown before game starts
--   PZDOOMWindow     — ISCollapsableWindow that hosts all panels
--

require "PZFB/PZFBInput"
require "PZFB/PZFBApi"
require "PZDOOM/PZDOOMGame"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local BUTTON_HGT = FONT_HGT_SMALL + 6

---------------------------------------------------------------------
-- PZDOOMGamePanel — renders DOOM frames and captures input
---------------------------------------------------------------------

PZDOOMGamePanel = PZFBInputPanel:derive("PZDOOMGamePanel")

function PZDOOMGamePanel:new(x, y, w, h, game)
    local o = PZFBInputPanel.new(self, x, y, w, h, {
        mode                  = PZFBInput.MODE_FOCUS,
        captureToggleKey      = Keyboard.KEY_SCROLL,
        escapeCloses          = false,
        escapeReleasesCapture = true,
        forceCursorVisible    = true,
        autoGrab              = false,
    })
    o.game = game
    return o
end

function PZDOOMGamePanel:onPZFBKeyDown(key)
    if self.game then
        self.game:sendKey(key, 1)
    end
end

function PZDOOMGamePanel:onPZFBKeyUp(key)
    if self.game then
        self.game:sendKey(key, 0)
    end
end

function PZDOOMGamePanel:onPZFBCaptureToggle(active)
    if not active and self.game then
        -- Leaving exclusive lock: send ESC to DOOM so it pauses
        self.game:sendKey(Keyboard.KEY_ESCAPE, 1)
        self.game:sendKey(Keyboard.KEY_ESCAPE, 0)
    end
end

function PZDOOMGamePanel:render()
    PZFBInputPanel.render(self)

    local game = self.game
    if not game then return end

    game:update()

    -- Draw status text if not running
    if game.state == "STARTING" then
        self:drawText("Starting DOOM...", 10, 10, 1, 1, 1, 0.8, UIFont.Medium)
        return
    elseif game.state == "ERROR" then
        self:drawText("Error: " .. (game.errorMsg or "unknown"), 10, 10, 1, 0.3, 0.3, 0.9, UIFont.Small)
        return
    elseif game.state == "STOPPED" then
        self:drawText("DOOM has exited.", 10, 10, 0.7, 0.7, 0.7, 0.8, UIFont.Medium)
        return
    end

    -- Draw the DOOM framebuffer scaled to fit panel (aspect-correct)
    if game.fb and PZFB.isReady(game.fb) then
        local scaleX = self.width / PZDOOMGame.DOOM_WIDTH
        local scaleY = self.height / PZDOOMGame.DOOM_HEIGHT
        local scale = math.min(scaleX, scaleY)
        local drawW = math.floor(PZDOOMGame.DOOM_WIDTH * scale)
        local drawH = math.floor(PZDOOMGame.DOOM_HEIGHT * scale)
        local drawX = math.floor((self.width - drawW) / 2)
        local drawY = math.floor((self.height - drawH) / 2)

        -- Black bars (letterbox/pillarbox)
        if drawX > 0 then
            self:drawRect(0, 0, drawX, self.height, 1, 0, 0, 0)
            self:drawRect(drawX + drawW, 0, self.width - drawX - drawW, self.height, 1, 0, 0, 0)
        end
        if drawY > 0 then
            self:drawRect(0, 0, self.width, drawY, 1, 0, 0, 0)
            self:drawRect(0, drawY + drawH, self.width, self.height - drawY - drawH, 1, 0, 0, 0)
        end

        self:drawTextureScaled(PZFB.getTexture(game.fb), drawX, drawY, drawW, drawH, 1, 1, 1, 1)
    end

    -- Show capture toggle hint
    if self:isCapturing() then
        local hint = "[Scroll Lock: lock input] [ESC: pause/unlock]"
        self:drawText(hint, 4, self.height - FONT_HGT_SMALL - 4, 0.6, 0.6, 0.6, 0.4, UIFont.Small)
    end
end

---------------------------------------------------------------------
-- PZDOOMWadPicker — WAD file selection panel
---------------------------------------------------------------------

PZDOOMWadPicker = ISPanel:derive("PZDOOMWadPicker")

function PZDOOMWadPicker:new(x, y, w, h, onSelect)
    local o = ISPanel.new(self, x, y, w, h)
    o.onSelect = onSelect
    o.wads = {}
    o.buttons = {}
    return o
end

function PZDOOMWadPicker:createChildren()
    ISPanel.createChildren(self)
    self:refresh()
end

function PZDOOMWadPicker:refresh()
    -- Remove old buttons
    for _, btn in ipairs(self.buttons) do
        self:removeChild(btn)
    end
    self.buttons = {}

    self.wads = PZDOOMGame.findWads()

    local y = 10 + FONT_HGT_LARGE + 8 + FONT_HGT_SMALL + 20

    if #self.wads == 0 then return end

    for i, wad in ipairs(self.wads) do
        local btnW = math.min(300, self.width - 40)
        local btnX = math.floor((self.width - btnW) / 2)
        local btn = ISButton:new(btnX, y, btnW, BUTTON_HGT + 4, wad.name, self, PZDOOMWadPicker.onWadClick)
        btn.internal = "WAD_" .. i
        btn:initialise()
        btn:instantiate()
        btn.borderColor = {r=0.7, g=0.2, b=0.2, a=0.9}
        btn.textColor = {r=1, g=0.3, b=0.3, a=1}
        btn.backgroundColor = {r=0.15, g=0.05, b=0.05, a=0.8}
        self:addChild(btn)
        table.insert(self.buttons, btn)
        y = y + BUTTON_HGT + 8
    end
end

function PZDOOMWadPicker:onWadClick(button)
    for i, wad in ipairs(self.wads) do
        if button.internal == "WAD_" .. i then
            if self.onSelect then
                self.onSelect(wad)
            end
            return
        end
    end
end

function PZDOOMWadPicker:render()
    ISPanel.render(self)

    -- Background
    self:drawRect(0, 0, self.width, self.height, 0.95, 0.1, 0.1, 0.12)

    -- Title
    local title = "Select a WAD file"
    local titleW = getTextManager():MeasureStringX(UIFont.Large, title)
    local titleX = math.floor((self.width - titleW) / 2)
    self:drawText(title, titleX, 10, 1, 0.2, 0.2, 0.95, UIFont.Large)

    -- Subtitle
    local subtitle = "Choose a DOOM WAD to play"
    local subW = getTextManager():MeasureStringX(UIFont.Small, subtitle)
    local subX = math.floor((self.width - subW) / 2)
    self:drawText(subtitle, subX, 10 + FONT_HGT_LARGE + 4, 0.7, 0.7, 0.7, 0.7, UIFont.Small)

    if #self.wads == 0 then
        local msg1 = "No WAD files found."
        local sep = getFileSeparator()
        local wadDir = Core.getMyDocumentFolder() .. sep .. "PZDOOM"
        local msg2 = "Place .wad files in:"
        local msg3 = wadDir

        local y = 10 + FONT_HGT_LARGE + 8 + FONT_HGT_SMALL + 30
        self:drawText(msg1, 20, y, 1, 1, 1, 0.8, UIFont.Medium)
        y = y + FONT_HGT_MEDIUM + 10
        self:drawText(msg2, 20, y, 0.7, 0.7, 0.7, 0.7, UIFont.Small)
        y = y + FONT_HGT_SMALL + 4
        self:drawText(msg3, 20, y, 0.5, 1, 0.5, 0.9, UIFont.Small)
    end
end

---------------------------------------------------------------------
-- PZDOOMWelcome — Instructions screen
---------------------------------------------------------------------

PZDOOMWelcome = ISPanel:derive("PZDOOMWelcome")

function PZDOOMWelcome:new(x, y, w, h, onDismiss)
    local o = ISPanel.new(self, x, y, w, h)
    o.onDismiss = onDismiss
    return o
end

function PZDOOMWelcome:onMouseDown(x, y)
    if self.onDismiss then
        self.onDismiss()
    end
    return true
end

function PZDOOMWelcome:render()
    ISPanel.render(self)

    -- Dark background
    self:drawRect(0, 0, self.width, self.height, 0.95, 0.08, 0.02, 0.02)

    local cx = self.width / 2
    local y = math.floor(self.height * 0.12)

    -- Title
    local title = "WELCOME TO DOOM"
    local titleW = getTextManager():MeasureStringX(UIFont.Large, title)
    self:drawText(title, math.floor(cx - titleW / 2), y, 1, 0.2, 0.2, 1, UIFont.Large)
    y = y + FONT_HGT_LARGE + 30

    -- Instructions
    local lines = {
        { text = "At the DOOM title screen, press Y to start a new game.",  r = 1, g = 1, b = 1 },
        { text = "",                                                         r = 0, g = 0, b = 0 },
        { text = "SCROLL LOCK  -  Lock keyboard to DOOM (for intense play)", r = 0.9, g = 0.9, b = 0.5 },
        { text = "ESC  -  Pause DOOM and unlock keyboard",                   r = 0.9, g = 0.9, b = 0.5 },
        { text = "",                                                         r = 0, g = 0, b = 0 },
        { text = "Hover the DOOM window to play, move mouse away for PZ.",   r = 0.7, g = 0.7, b = 0.7 },
    }

    for _, line in ipairs(lines) do
        if line.text ~= "" then
            local lw = getTextManager():MeasureStringX(UIFont.Medium, line.text)
            local lx = math.floor(cx - lw / 2)
            self:drawText(line.text, lx, y, line.r, line.g, line.b, 0.9, UIFont.Medium)
        end
        y = y + FONT_HGT_MEDIUM + 6
    end

    -- "Click to play" prompt
    y = math.floor(self.height * 0.78)
    local prompt = "[ Click anywhere to play ]"
    local promptW = getTextManager():MeasureStringX(UIFont.Medium, prompt)
    -- Pulse alpha for attention
    local alpha = 0.5 + 0.4 * math.sin((getTimestampMs() % 2000) / 2000 * 6.283)
    self:drawText(prompt, math.floor(cx - promptW / 2), y, 0.8, 0.8, 0.8, alpha, UIFont.Medium)
end

---------------------------------------------------------------------
-- PZDOOMWindow — main window
---------------------------------------------------------------------

PZDOOMWindow = ISCollapsableWindow:derive("PZDOOMWindow")

-- Singleton reference
PZDOOMWindow.instance = nil

function PZDOOMWindow:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = "DOOM"
    o.minimumWidth = 340
    o.minimumHeight = 230
    o.resizable = true
    o.game = nil
    o.gamePanel = nil
    o.wadPicker = nil
    o.welcomePanel = nil
    o.selectedWad = nil
    return o
end

function PZDOOMWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local th = self:titleBarHeight()
    local rh = self:resizeWidgetHeight()
    local panelW = self.width
    local panelH = self.height - th

    -- Create game object
    self.game = PZDOOMGame:new()

    -- Game panel (hidden until welcome screen is dismissed)
    -- CRITICAL: anchors MUST be set BEFORE instantiate (ISUIElement.lua:852-855)
    self.gamePanel = PZDOOMGamePanel:new(0, th, panelW, panelH - rh, self.game)
    self.gamePanel.anchorLeft = true
    self.gamePanel.anchorRight = true
    self.gamePanel.anchorTop = true
    self.gamePanel.anchorBottom = true
    self.gamePanel:initialise()
    self.gamePanel:instantiate()
    self.gamePanel:setVisible(false)
    self:addChild(self.gamePanel)

    -- WAD picker (visible initially)
    self.wadPicker = PZDOOMWadPicker:new(0, th, panelW, panelH, function(wad)
        self:onWadSelected(wad)
    end)
    self.wadPicker.anchorLeft = true
    self.wadPicker.anchorRight = true
    self.wadPicker.anchorTop = true
    self.wadPicker.anchorBottom = true
    self.wadPicker:initialise()
    self.wadPicker:instantiate()
    self:addChild(self.wadPicker)

    -- Welcome/instructions panel (hidden until WAD is selected)
    self.welcomePanel = PZDOOMWelcome:new(0, th, panelW, panelH, function()
        self:onWelcomeDismissed()
    end)
    self.welcomePanel.anchorLeft = true
    self.welcomePanel.anchorRight = true
    self.welcomePanel.anchorTop = true
    self.welcomePanel.anchorBottom = true
    self.welcomePanel:initialise()
    self.welcomePanel:instantiate()
    self.welcomePanel:setVisible(false)
    self:addChild(self.welcomePanel)

    -- Bring resize widgets to top (required by ISCollapsableWindow)
    if self.resizeWidget then self.resizeWidget:bringToTop() end
    if self.resizeWidget2 then self.resizeWidget2:bringToTop() end

    if not self.game.binaryPath then
        print("[PZDOOM] Warning: DOOM binary not found")
    end
end

function PZDOOMWindow:onWadSelected(wad)
    self.wadPicker:setVisible(false)
    self.selectedWad = wad
    self.welcomePanel:setVisible(true)
end

function PZDOOMWindow:onWelcomeDismissed()
    self.welcomePanel:setVisible(false)
    self.gamePanel:setVisible(true)

    -- Start DOOM
    self.game:start(self.selectedWad.path)

    -- Grab input
    self.gamePanel:grabInput()
end

function PZDOOMWindow:close()
    if self.game then
        self.game:stop()
    end
    if self.gamePanel then
        self.gamePanel:releaseInput()
    end
    PZDOOMWindow.instance = nil
    ISCollapsableWindow.close(self)
end

--
-- Open the DOOM window (singleton)
--
function PZDOOMWindow.open()
    if PZDOOMWindow.instance then
        PZDOOMWindow.instance:bringToTop()
        return
    end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local w = 660
    local h = 440
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    local window = PZDOOMWindow:new(x, y, w, h)
    window:initialise()
    window:instantiate()
    window:setResizable(true)
    window:addToUIManager()

    PZDOOMWindow.instance = window
end
