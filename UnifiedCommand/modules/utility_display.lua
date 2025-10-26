-- modules/utility_display.lua
-- Utility monitor rendering and input handling

local UtilityDisplay = {}
local Config = require("modules.config")

-- Monitor reference (set by init)
local utilityMonitor = nil

-- ========== Initialization ==========
function UtilityDisplay.init(monitor)
    utilityMonitor = monitor
    if utilityMonitor then
        utilityMonitor.setTextScale(0.9)
        utilityMonitor.setBackgroundColor(Config.colors.bg)
        utilityMonitor.clear()
    end
    return utilityMonitor ~= nil
end

-- ========== Drawing Functions ==========
function UtilityDisplay.drawPage1(systemState, persistentMetrics)
    if not utilityMonitor then return end
    
    local mon = utilityMonitor
    local w, h = mon.getSize()
    
    -- Clear and title
    mon.setBackgroundColor(Config.colors.bg)
    mon.clear()
    mon.setBackgroundColor(Config.colors.title)
    mon.setTextColor(Config.colors.bg)
    local titleText = "OMNI-DRILL UTILITY"
    local titlePadding = math.floor((w - #titleText) / 2)
    mon.setCursorPos(1, 1)
    mon.write(string.rep(" ", w))
    mon.setCursorPos(1 + titlePadding, 1)
    mon.write(titleText)
    
    -- System metrics
    mon.setBackgroundColor(Config.colors.bg)
    mon.setTextColor(Config.colors.text)
    
    -- Row 2: Collection status
    mon.setCursorPos(1, 2)
    local collectingItems = {}
    if systemState.collectNatBlocksEnabled then table.insert(collectingItems, " NATURAL") end
    if systemState.collectBuildBlocksEnabled then table.insert(collectingItems, " BUILD") end
    if systemState.collectRawOreEnabled then table.insert(collectingItems, " ORE") end
    
    local collectionText = #collectingItems > 0 and table.concat(collectingItems, ",") or " NONE"
    mon.write("COLLECTING BLOCK TYPES: ")
    mon.setTextColor(#collectingItems > 0 and Config.colors.accent or Config.colors.warning)
    mon.write(collectionText)
    
    -- Row 3: Auto-drive
    mon.setBackgroundColor(Config.colors.bg)
    mon.setTextColor(Config.colors.text)
    mon.setCursorPos(1, 3)
    mon.write("AUTO-DRIVE:")
    mon.setTextColor(systemState.autoDriveEnabled and Config.colors.good or Config.colors.inactive)
    mon.write(systemState.autoDriveEnabled and " ON" or " OFF")
    
    -- Row 4: Vault
    mon.setBackgroundColor(Config.colors.bg)
    mon.setTextColor(Config.colors.text)
    mon.setCursorPos(1, 4)
    mon.write("VAULT:")
    mon.setTextColor(systemState.vaultFull and Config.colors.danger or Config.colors.good)
    mon.write(systemState.vaultFull and " FULL" or " OK")
    
    -- Row 5: Drill
    mon.setBackgroundColor(Config.colors.bg)
    mon.setTextColor(Config.colors.text)
    mon.setCursorPos(1, 5)
    mon.write("DRILL:")
    mon.setTextColor(systemState.drillActive and Config.colors.good or Config.colors.inactive)
    mon.write(systemState.drillActive and " ON" or " OFF")
    
    -- Row 6: Moves
    mon.setBackgroundColor(Config.colors.bg)
    mon.setTextColor(Config.colors.text)
    mon.setCursorPos(1, 6)
    mon.write("MOVES:")
    mon.setTextColor(Config.colors.accent)
    mon.write(tostring(persistentMetrics.totalMoves))
    
    -- Row 7: Facing
    mon.setCursorPos(1, 7)
    mon.setTextColor(Config.colors.text)
    mon.write("FACING:")
    mon.setTextColor(Config.colors.accent)
    local cardinalNames = {N=" NORTH ", E=" EAST ", S=" SOUTH ", W=" WEST "}
    local verticalNames = {F=" FRONT ", U=" UP ", D=" DOWN "}
    local cardinalFull = cardinalNames[systemState.currentCardinal] or systemState.currentCardinal
    local verticalFull = verticalNames[systemState.currentVertical] or systemState.currentVertical
    mon.write(" " .. cardinalFull .. "/" .. verticalFull)
    
    -- Navigation button
    mon.setCursorPos(1, h-1)
    mon.setBackgroundColor(Config.colors.btnBg)
    mon.setTextColor(Config.colors.btnFg)
    mon.write(" COLLECTION CONTROLS ")
    
    -- Status line
    mon.setCursorPos(1, h)
    mon.setBackgroundColor(Config.colors.inactive)
    mon.setTextColor(Config.colors.text)
    mon.write(string.format("%-" .. w .. "s", " Touch to switch pages"))
end

function UtilityDisplay.drawPage2(systemState)
    if not utilityMonitor then return end
    
    local mon = utilityMonitor
    local w, h = mon.getSize()
    
    -- Clear and title
    mon.setBackgroundColor(Config.colors.bg)
    mon.clear()
    mon.setBackgroundColor(Config.colors.title)
    mon.setTextColor(Config.colors.bg)
    local titleText = "CONTROLS"
    local titlePadding = math.floor((w - #titleText) / 2)
    mon.setCursorPos(1, 1)
    mon.write(string.rep(" ", w))
    mon.setCursorPos(1 + titlePadding, 1)
    mon.write(titleText)
    
    -- Collection toggles
    mon.setBackgroundColor(Config.colors.bg)
    
    -- Natural blocks
    mon.setCursorPos(1, 2)
    mon.setBackgroundColor(systemState.collectNatBlocksEnabled and Config.colors.good or Config.colors.danger)
    mon.setTextColor(Config.colors.bg)
    mon.write(" NATURAL BLOCKS: ")
    mon.write(systemState.collectNatBlocksEnabled and "ON " or "OFF")
    
    -- Build blocks
    mon.setCursorPos(1, 3)
    mon.setBackgroundColor(systemState.collectBuildBlocksEnabled and Config.colors.good or Config.colors.danger)
    mon.setTextColor(Config.colors.bg)
    mon.write(" BUILD BLOCKS:   ")
    mon.write(systemState.collectBuildBlocksEnabled and "ON " or "OFF")
    
    -- Raw ore
    mon.setCursorPos(1, 4)
    mon.setBackgroundColor(systemState.collectRawOreEnabled and Config.colors.good or Config.colors.danger)
    mon.setTextColor(Config.colors.bg)
    mon.write(" RAW ORE:       ")
    mon.write(systemState.collectRawOreEnabled and "ON " or "OFF")
    
    -- Cabin pulley
    mon.setCursorPos(1, 6)
    mon.setBackgroundColor(systemState.cabinLowered and Config.colors.good or Config.colors.danger)
    mon.setTextColor(Config.colors.bg)
    mon.write(" CABIN PULLEY:   ")
    mon.write(systemState.cabinLowered and "ON " or "OFF")
    
    -- Navigation button
    mon.setCursorPos(1, h-1)
    mon.setBackgroundColor(Config.colors.btnBg)
    mon.setTextColor(Config.colors.btnFg)
    mon.write("   MONITORING    ")
    
    -- Status line
    mon.setCursorPos(1, h)
    mon.setBackgroundColor(Config.colors.inactive)
    mon.setTextColor(Config.colors.text)
    mon.write(string.format("%-" .. w .. "s", " Touch items to toggle"))
end

-- ========== Input Handling ==========
function UtilityDisplay.handleTouch(systemState, x, y)
    if not utilityMonitor then return false end
    local w, h = utilityMonitor.getSize()
    
    if y == h-1 then
        -- Page navigation button
        systemState.utilityPage = systemState.utilityPage == 1 and 2 or 1
        return true
    end
    
    if systemState.utilityPage == 2 then
        -- Collection toggle buttons
        local command = nil
        if y == 2 then
            systemState.collectNatBlocksEnabled = not systemState.collectNatBlocksEnabled
            command = {
                name = "odmk3-collect-nat-blocks",
                cmd = "toggle",
                secret = Config.SECRET
            }
        elseif y == 3 then
            systemState.collectBuildBlocksEnabled = not systemState.collectBuildBlocksEnabled
            command = {
                name = "odmk3-collect-build-blocks", 
                cmd = "toggle",
                secret = Config.SECRET
            }
        elseif y == 4 then
            systemState.collectRawOreEnabled = not systemState.collectRawOreEnabled
            command = {
                name = "odmk3-collect-raw-ore",
                cmd = "toggle", 
                secret = Config.SECRET
            }
        elseif y == 6 then
            systemState.cabinLowered = not systemState.cabinLowered
            command = {
                name = "odmk3-cabin-pulley",
                cmd = "toggle",
                secret = Config.SECRET
            }
        end
        return true, command  -- Return true and optional network command
    end
    
    return false
end

-- ========== Public Draw Function ==========
function UtilityDisplay.draw(systemState, persistentMetrics)
    if systemState.utilityPage == 1 then
        UtilityDisplay.drawPage1(systemState, persistentMetrics)
    else
        UtilityDisplay.drawPage2(systemState)
    end
end

return UtilityDisplay
