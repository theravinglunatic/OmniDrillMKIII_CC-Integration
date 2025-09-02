-- ODMK3-AuxVaultThreshold.lua
-- Monitors auxiliary vault capacity and broadcasts safety signal
-- When redstone signal is present on bottom face, broadcasts "vault full" signal
-- to prevent drilling system from moving until vault has space

local NAME = "odmk3-aux-vault-threshold"
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""  -- Keep empty to disable, or match with other components
local DEBUG = true  -- Set to false to disable debug messages
local CHECK_INTERVAL = 1.0  -- How often to check vault status (seconds)

-- State tracking
local lastVaultFull = false

-- Utility: debug print function
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

-- Utility: open any connected modems (wired or wireless)
local function openAllModems()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then
                pcall(function() rednet.open(side) end)
                debugPrint("Opened modem on " .. side)
            end
        end
    end
end

-- Function to check if vault is full (redstone signal on bottom, left, or right)
local function isVaultFull()
    local bottom = redstone.getInput("bottom")
    local left = redstone.getInput("left")
    local right = redstone.getInput("right")
    
    -- Vault is full if ANY of these sides has a signal
    local signal = bottom or left or right
    
    if DEBUG and signal then
        local sources = {}
        if bottom then table.insert(sources, "bottom") end
        if left then table.insert(sources, "left") end
        if right then table.insert(sources, "right") end
        debugPrint("Vault full signal from: " .. table.concat(sources, ", "))
    end
    
    return signal
end

-- Function to broadcast vault status
local function broadcastVaultStatus(vaultFull)
    local message = {
        type = "vaultStatus",
        name = NAME,
        vaultFull = vaultFull,
        secret = SECRET
    }
    
    rednet.broadcast(message, PROTOCOL)
    debugPrint("Broadcasted vault status: " .. (vaultFull and "FULL" or "AVAILABLE"))
end

-- Main function
local function main()
    -- Initialize networking
    openAllModems()
    print("ODMK3-AuxVaultThreshold initialized")
    debugPrint("Monitoring vault threshold on bottom, left, and right redstone inputs")
    
    -- Initial status broadcast
    local vaultFull = isVaultFull()
    lastVaultFull = vaultFull
    broadcastVaultStatus(vaultFull)
    
    -- Set up periodic checking timer
    local checkTimer = os.startTimer(CHECK_INTERVAL)
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "redstone" then
            -- Redstone signal changed, check vault status
            local vaultFull = isVaultFull()
            if vaultFull ~= lastVaultFull then
                debugPrint("Vault status changed: " .. (vaultFull and "FULL" or "AVAILABLE"))
                lastVaultFull = vaultFull
                broadcastVaultStatus(vaultFull)
            end
            
        elseif event == "timer" and param1 == checkTimer then
            -- Periodic check
            local vaultFull = isVaultFull()
            if vaultFull ~= lastVaultFull then
                debugPrint("Vault status changed (periodic): " .. (vaultFull and "FULL" or "AVAILABLE"))
                lastVaultFull = vaultFull
                broadcastVaultStatus(vaultFull)
            end
            
            -- Set next timer
            checkTimer = os.startTimer(CHECK_INTERVAL)
            
        elseif event == "rednet_message" then
            local sender, message, protocol = param1, param2, param3
            
            -- Handle status requests
            if protocol == PROTOCOL and type(message) == "table" then
                if message.name == NAME and message.cmd == "status" then
                    debugPrint("Status request received, broadcasting current status")
                    broadcastVaultStatus(lastVaultFull)
                end
            end
        end
    end
end

-- Start the main function
main()
