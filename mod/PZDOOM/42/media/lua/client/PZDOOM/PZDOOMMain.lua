--
-- PZDOOMMain.lua — PZDOOM entry point
--
-- Hooks into the world object context menu to add "Play DOOM" on TVs.
-- TV detection pattern verified from ISRadioAndTvMenu.lua:7 and ISHutchMenu.lua.
--

require "PZDOOM/PZDOOMWindow"

PZDOOMMain = {}

--
-- Context menu hook: add "Play DOOM" when right-clicking a TV
-- Callback signature verified from ISWorldObjectContextMenu.lua:209
-- Pattern verified from ISHutchMenu.lua:3
--
function PZDOOMMain.onContext(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    -- Check PZFB availability
    if not PZFB or not PZFB.isAvailable() then return end

    -- Look for a TV in the clicked objects
    for _, object in ipairs(worldobjects) do
        -- TV = IsoWaveSignal without RadioItemID moddata
        -- Verified from ISRadioAndTvMenu.lua:7
        if instanceof(object, "IsoWaveSignal") and object:getSprite()
           and not object:getModData().RadioItemID then
            local playerObj = getSpecificPlayer(player)
            context:addOption("Play DOOM", playerObj, PZDOOMMain.openDoom)
            return  -- only add once even if multiple TVs in click area
        end
    end
end

--
-- Open the DOOM window (called from context menu)
-- context:addOption callback receives (target, param1, ...) where target=playerObj
--
function PZDOOMMain.openDoom(playerObj)
    PZDOOMWindow.open()
end

-- Register context menu hook
Events.OnFillWorldObjectContextMenu.Add(PZDOOMMain.onContext)

-- Startup diagnostic
Events.OnGameStart.Add(function()
    if PZFB and PZFB.isAvailable() then
        print("[PZDOOM] PZFB available (v" .. tostring(PZFB.getVersion()) .. "). Ready to play DOOM!")
    else
        print("[PZDOOM] WARNING: PZFB not available. Install PZFB mod and deploy class files.")
    end
end)
