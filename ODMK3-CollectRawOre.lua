-- ODMK3-CollectRawOre.lua
-- Omni-Drill MKIII: Raw Ore Collection Controller
-- Controls redstone output to Create Item Funnel for raw ore collection

-- ========== config ==========
local PROTOCOL = "Omni-DrillMKIII"
local MY_NAME = "odmk3-collect-raw-ore"
local SECRET = ""  -- optional shared secret
local NET_OK = false

-- Collection state
local collectionEnabled = nil  -- Will be set after querying GUI at startup

-- ========== networking ==========
local function openAllModems()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then 
                rednet.open(side) 
            end
            NET_OK = true
            return true
        end
    end
    NET_OK = false
    return false
end

-- ========== redstone control ==========
local function updateRedstoneOutput()
    if collectionEnabled == nil then
        -- Don't update redstone until we know the state
        return
    end
    
    -- When collection is ENABLED (ON), no redstone signal (allows collection)
    -- When collection is DISABLED (OFF), output redstone signal (blocks collection)
    redstone.setOutput("bottom", not collectionEnabled)
    
    print(string.format("[%s] Collection %s - Redstone bottom: %s", 
        os.date("%H:%M:%S"), 
        collectionEnabled and "ENABLED" or "DISABLED",
        redstone.getOutput("bottom") and "ON" or "OFF"))
end

-- ========== message handlers ==========
local function handleToggleCommand(msg)
    if type(msg) ~= "table" then return end
    if msg.name ~= MY_NAME then return end
    if msg.cmd ~= "toggle" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    collectionEnabled = msg.enabled
    updateRedstoneOutput()
    
    -- Send status confirmation
    if NET_OK then
        rednet.broadcast({
            type = "rawOreStatus",
            enabled = collectionEnabled,
            secret = ""
        }, PROTOCOL)
    end
    
    print(string.format("[%s] Toggle command received - Collection %s", 
        os.date("%H:%M:%S"), collectionEnabled and "ENABLED" or "DISABLED"))
end

local function handleStatusQuery(msg)
    if type(msg) ~= "table" then return end
    if msg.name ~= MY_NAME then return end
    if msg.cmd ~= "status" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    -- Send current status
    if NET_OK then
        rednet.broadcast({
            type = "rawOreStatus",
            enabled = collectionEnabled,
            secret = ""
        }, PROTOCOL)
    end
    
    print(string.format("[%s] Status query received - responding with %s", 
        os.date("%H:%M:%S"), collectionEnabled and "ENABLED" or "DISABLED"))
end

-- Handle initial state response from GUI
local function handleInitialState(msg)
    if type(msg) ~= "table" then return end
    if msg.type ~= "rawOreStatus" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    if collectionEnabled == nil then
        collectionEnabled = msg.enabled
        updateRedstoneOutput()
        print(string.format("[%s] Initial state received from GUI - Collection %s", 
            os.date("%H:%M:%S"), collectionEnabled and "ENABLED" or "DISABLED"))
        return true  -- Signal that we got initial state
    end
    return false
end

-- ========== main function ==========
local function main()
    print("ODMK3 Raw Ore Collection Controller")
    print("====================================")
    
    -- Initialize networking
    openAllModems()
    
    if NET_OK then
        print("Network initialized successfully")
        
        -- Query GUI for current collection state
        print("Querying GUI for current collection state...")
        rednet.broadcast({
            name = "odmk3-command-center",
            cmd = "queryState",
            type = "rawOre",
            secret = ""
        }, PROTOCOL)
        
        -- Wait for initial state response (with timeout)
        local timeout = os.clock() + 5  -- 5 second timeout
        while collectionEnabled == nil and os.clock() < timeout do
            local event, param1, param2, param3 = os.pullEvent()
            if event == "rednet_message" then
                local sender, msg, proto = param1, param2, param3
                if proto == PROTOCOL and handleInitialState(msg) then
                    break  -- Got initial state
                end
            end
        end
        
        -- If no response, default to enabled but log warning
        if collectionEnabled == nil then
            print("WARNING: No response from GUI - defaulting to ENABLED")
            collectionEnabled = true
            updateRedstoneOutput()
        end
    else
        print("WARNING: No modem found - running in standalone mode")
        print("Defaulting to ENABLED state")
        collectionEnabled = true
        updateRedstoneOutput()
    end
    
    print("Controller ready")
    print("Collection state: " .. (collectionEnabled and "ENABLED" or "DISABLED"))
    print("Press Ctrl+T to exit")
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, msg, proto = param1, param2, param3
            if proto == PROTOCOL then
                handleToggleCommand(msg)
                handleStatusQuery(msg)
                handleInitialState(msg)  -- Continue handling state updates
            end
            
        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Modem connected/disconnected
            openAllModems()
            
        elseif event == "terminate" then
            print("Raw Ore Collection Controller shutting down")
            break
        end
    end
end

-- Start the controller
main()
