-- ODMK3-CollectBuildBlocks.lua
-- Omni-Drill MKIII: Build Blocks Collection Controller
-- Controls redstone output to Create Item Funnel for build block collection

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local MY_NAME = "odmk3-collect-build-blocks"
local SECRET = ""  -- optional shared secret
local DEBUG = false  -- Set to true to enable debug messages

-- ========== State Tracking ==========
local NET_OK = false
local collectionEnabled = nil  -- Will be set after querying GUI at startup

-- ========== Persistence ==========
local STATUS_TYPE = "buildBlocksStatus"
local STATE_DIR = "collector_state"
local STATE_FILE = STATE_DIR .. "/" .. MY_NAME .. ".cfg"

local function ensureStateDir()
    if not fs.exists(STATE_DIR) then
        pcall(function() fs.makeDir(STATE_DIR) end)
    end
end

local function savePersistedState(enabled)
    ensureStateDir()
    local ok, err = pcall(function()
        local f = fs.open(STATE_FILE, "w")
        if f then
            f.write(enabled and "1" or "0")
            f.close()
        end
    end)
    if DEBUG and not ok then print("[DEBUG] savePersistedState error: " .. tostring(err)) end
end

local function loadPersistedState()
    local ok, value = pcall(function()
        if fs.exists(STATE_FILE) then
            local f = fs.open(STATE_FILE, "r")
            if not f then return nil end
            local s = f.readAll()
            f.close()
            if s == "1" then return true end
            if s == "0" then return false end
        end
        return nil
    end)
    if not ok then return nil end
    return value
end

local function broadcastStatus()
    if NET_OK then
        rednet.broadcast({ type = STATUS_TYPE, enabled = collectionEnabled, secret = "" }, PROTOCOL)
    end
end

-- ========== Utilities ==========
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

-- ========== Networking ==========
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
    
    -- If GUI doesn't include an explicit enabled flag, invert current state
    local newState
    if msg.enabled == nil then
        newState = not (collectionEnabled == true)
    else
        newState = msg.enabled and true or false
    end
    collectionEnabled = newState
    updateRedstoneOutput()
    savePersistedState(collectionEnabled)
    
    -- Send status confirmation
    if NET_OK then
        rednet.broadcast({
            type = STATUS_TYPE,
            enabled = collectionEnabled,
            secret = ""
        }, PROTOCOL)
    end
    
    print(string.format("[%s] Toggle command received - Collection %s", 
        os.date("%H:%M:%S"), collectionEnabled and "ENABLED" or "DISABLED"))
end

local function handleStatusQuery(msg)
    if type(msg) ~= "table" then return end
    -- Respond to direct status requests for this controller OR global queryStatus pings
    if not ((msg.name == MY_NAME and msg.cmd == "status") or (msg.cmd == "queryStatus")) then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    -- Send current status
    if NET_OK then
        rednet.broadcast({
            type = STATUS_TYPE,
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
    if msg.type ~= "buildBlocksStatus" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    if collectionEnabled == nil then
        collectionEnabled = msg.enabled
        updateRedstoneOutput()
        savePersistedState(collectionEnabled)
        print(string.format("[%s] Initial state received from GUI - Collection %s", 
            os.date("%H:%M:%S"), collectionEnabled and "ENABLED" or "DISABLED"))
        return true  -- Signal that we got initial state
    end
    return false
end

-- Accept snapshot from GUI as a fallback/alternative initial state source
local function handleSnapshot(msg)
    if type(msg) ~= "table" then return end
    if msg.type ~= "remoteStateSnapshot" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    if type(msg.state) ~= "table" then return end
    if collectionEnabled == nil then
        if msg.state.collectBuildBlocksEnabled ~= nil then
            collectionEnabled = msg.state.collectBuildBlocksEnabled and true or false
            updateRedstoneOutput()
            savePersistedState(collectionEnabled)
            print(string.format("[%s] Initial snapshot applied - Collection %s",
                os.date("%H:%M:%S"), collectionEnabled and "ENABLED" or "DISABLED"))
            return true
        end
    end
    return false
end

-- ========== main function ==========
local function main()
    print("ODMK3 Build Blocks Collection Controller")
    print("========================================")
    
    -- Initialize networking
    openAllModems()
    
    if NET_OK then
        print("Network initialized successfully")
        -- Apply persisted state immediately for fast boot
        local persisted = loadPersistedState()
        if persisted ~= nil then
            collectionEnabled = persisted and true or false
            updateRedstoneOutput()
            print(string.format("[%s] Applied persisted state - Collection %s",
                os.date("%H:%M:%S"), collectionEnabled and "ENABLED" or "DISABLED"))
            broadcastStatus()
        end
        -- Allow UI a moment to initialize before querying
        sleep(1.0)
        
        -- Query GUI for current collection state
        print("Querying GUI for current collection state...")
        rednet.broadcast({
            name = "odmk3-command-center",
            cmd = "queryState",
            type = "buildBlocks",
            secret = ""
        }, PROTOCOL)
        -- Also request a full snapshot for robustness (in case queryState is missed)
        rednet.broadcast({
            type = "remoteStateRequest",
            secret = ""
        }, PROTOCOL)
        
        -- Wait for initial state response (with timeout)
        local timeout = os.clock() + 5  -- 5 second timeout
        local gotInitial = false
        while collectionEnabled == nil and os.clock() < timeout do
            local event, param1, param2, param3 = os.pullEvent()
            if event == "rednet_message" then
                local sender, msg, proto = param1, param2, param3
                if proto == PROTOCOL then
                    if handleInitialState(msg) or handleSnapshot(msg) then
                        gotInitial = true
                        break
                    end
                end
            end
        end
        
        -- If no response, default to enabled but log warning
        if not gotInitial and collectionEnabled == nil then
            print("WARNING: No response from GUI - defaulting to ENABLED")
            collectionEnabled = true
            updateRedstoneOutput()
            savePersistedState(collectionEnabled)
        end
    else
        print("WARNING: No modem found - running in standalone mode")
        print("Defaulting to ENABLED state")
        collectionEnabled = true
        updateRedstoneOutput()
        savePersistedState(collectionEnabled)
    end
    
    print("ODMK3-CollectBuildBlocks initialized")
    print("Collection state: " .. (collectionEnabled and "ENABLED" or "DISABLED"))
    debugPrint("Controller ready for commands")
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, msg, proto = param1, param2, param3
            if proto == PROTOCOL then
                handleToggleCommand(msg)
                handleStatusQuery(msg)
                handleInitialState(msg)  -- Continue handling state updates
                handleSnapshot(msg)      -- Accept snapshot updates as well
            end
            
        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Modem connected/disconnected
            openAllModems()
            
        elseif event == "terminate" then
            print("Build Blocks Collection Controller shutting down")
            break
        end
    end
end

-- Start the controller
main()