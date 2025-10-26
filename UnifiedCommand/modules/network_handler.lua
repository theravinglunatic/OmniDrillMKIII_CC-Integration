-- modules/network_handler.lua
-- Network message handling and protocol logic

local NetworkHandler = {}
local Config = require("modules.config")
local NavigationDisplay = nil  -- Lazy load to avoid circular dependency

-- ========== Message Handling ==========
function NetworkHandler.handleMessage(systemState, msg)
    if type(msg) ~= "table" then return false end
    if Config.SECRET ~= "" and msg.secret ~= Config.SECRET then return false end
    
    local updated = false
    local orientationChanged = false
    
    -- Movement responses
    if msg.type == "rotateAck" or msg.type == "moveAck" then
        systemState.pendingTarget = nil
        if msg.facing then systemState.currentFacing = msg.facing end
        if msg.verticalAfter then systemState.verticalFacing = msg.verticalAfter end
        updated = true
        
    -- Facing updates
    elseif msg.type == "facing" then
        if msg.facing and msg.facing ~= systemState.currentCardinal then
            systemState.currentFacing = msg.facing
            -- Keep NAV direction in sync too
            systemState.currentCardinal = msg.facing
            orientationChanged = true
        end
        updated = true
        
    -- Orientation updates  
    elseif msg.type == "orientation" then
        if msg.orientation and msg.orientation ~= systemState.currentVertical then
            systemState.verticalFacing = msg.orientation
            -- Keep NAV direction in sync too
            systemState.currentVertical = msg.orientation
            orientationChanged = true
        end
        updated = true
        
    -- Collection status
    elseif msg.type == "natBlocksStatus" then
        systemState.collectNatBlocksEnabled = msg.enabled
        updated = true
    elseif msg.type == "buildBlocksStatus" then
        systemState.collectBuildBlocksEnabled = msg.enabled
        updated = true
    elseif msg.type == "rawOreStatus" then
        systemState.collectRawOreEnabled = msg.enabled
        updated = true
        
    -- Cabin pulley status
    elseif msg.type == "cabinPulleyStatus" then
        systemState.cabinLowered = msg.lowered
        updated = true
        
    -- Auto drive status
    elseif msg.type == "autoStatus" then
        systemState.autoDriveEnabled = msg.enabled
        updated = true
        
    -- Vault status
    elseif msg.type == "vaultStatus" then
        systemState.vaultFull = msg.full
        updated = true
        
    -- Scanner data
    elseif msg.type == "scanResponse" and msg.success and msg.data then
        systemState.scanData = msg.data
        systemState.scanInProgress = false
        systemState.relayOnline = true
        updated = true
        
    -- Scanner status
    elseif msg.type == "statusResponse" then
        systemState.relayOnline = msg.scannerAvailable
        updated = true
    end
    
    -- Update navigation display settings when orientation changes
    if orientationChanged then
        if not NavigationDisplay then
            NavigationDisplay = require("modules.navigation_display")
        end
        NavigationDisplay.updateDisplaySettings(systemState)
    end
    
    if updated then
        systemState.lastUpdate = os.clock()
    end
    
    return updated
end

-- ========== Network Utilities ==========
function NetworkHandler.openAllModems()
    local opened = false
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if peripheral.call(side, "isWireless") then
                rednet.open(side)
                opened = true
                Config.debugPrint("Opened modem on " .. side)
            end
        end
    end
    return opened
end

function NetworkHandler.broadcast(message)
    rednet.broadcast(message, Config.PROTOCOL)
end

return NetworkHandler
