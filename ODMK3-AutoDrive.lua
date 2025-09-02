-- ODMK3-AutoDrive.lua
-- Automatically initiates movement when enabled, checking for safety signal first
-- Receives commands from GUI to toggle auto-drive mode
-- Only sends move command when redstone safety signal is present on back face

local NAME = "odmk3-auto-drive"
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""  -- Keep empty to disable, or match with other components
local DEBUG = true  -- Set to false to disable debug messages
local CHECK_INTERVAL = 0.5  -- How often to check safety signal when auto-drive is enabled

-- State tracking
local autoEnabled = false
local lastMoveTime = 0
local lastMoveSuccess = true
local vaultFull = false  -- Track auxiliary vault status
local MIN_MOVE_INTERVAL = 0.5  -- Minimum seconds between move commands
local MOVE_TIMEOUT = 10      -- Maximum seconds to wait for move acknowledgment

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

-- Function to check if it's safe to move (redstone signal present on back AND vault not full)
local function isSafeToMove()
    local signal = redstone.getInput("back")
    local safetySignal = signal and not vaultFull
    
    if not signal then
        debugPrint("Safety check: UNSAFE - no redstone signal (back=" .. tostring(signal) .. ")")
    elseif vaultFull then
        debugPrint("Safety check: UNSAFE - vault full, waiting for space")
    else
        debugPrint("Safety check: SAFE (back=" .. tostring(signal) .. ", vault=" .. (vaultFull and "FULL" or "OK") .. ")")
    end
    
    return safetySignal
end

-- Function to initiate movement by sending command to DriveController
local function initiateMove()
    local currentTime = os.clock()
    -- Check time since last move to prevent spam
    if currentTime - lastMoveTime < MIN_MOVE_INTERVAL then
        debugPrint("Move command skipped - too soon since last move")
        return false
    end
    
    debugPrint("Sending move command to DriveController")
    rednet.broadcast({
        name = "odmk3-drive-controller",
        cmd = "move",
        secret = SECRET
    }, PROTOCOL)
    
    lastMoveTime = currentTime
    lastMoveSuccess = false  -- Reset until we get acknowledgment
    return true
end

-- Function to send status update
local function broadcastStatus()
    rednet.broadcast({
        type = "autoStatus",
        name = NAME,
        enabled = autoEnabled,
        safe = isSafeToMove(),
        secret = SECRET
    }, PROTOCOL)
end

-- Function to toggle auto-drive mode
local function toggleAutoMove(enabled, activeTimer)
    local wasEnabled = autoEnabled
    autoEnabled = enabled
    debugPrint("Auto-Drive mode set to: " .. (autoEnabled and "ON" or "OFF"))
    
    -- Send status update immediately without delay
    broadcastStatus()
    
    -- If turning on, initiate first check
    if autoEnabled and not wasEnabled then
        debugPrint("Starting auto-drive timer")
        -- Return a new timer to check soon
        return os.startTimer(0.5)  -- Give a bit more time for initial check
    end
    
    -- If turning off and we have an active timer, cancel it
    if not autoEnabled and wasEnabled and activeTimer then
        debugPrint("Cancelling auto-drive timer")
        os.cancelTimer(activeTimer)
        return nil
    end
    
    return activeTimer
end

-- Main function
local function main()
    -- Initialize networking
    openAllModems()
    print("ODMK3-AutoDrive initialized")
    debugPrint("Listening for commands on protocol: " .. PROTOCOL)
    
    -- Initialize state
    lastMoveTime = os.clock()
    autoEnabled = false
    lastMoveSuccess = true
    local activeTimer = nil
    local moveTimeoutTimer = nil
    
    -- Query GUI for current auto-drive state after reboot
    debugPrint("Querying GUI for current auto-drive state...")
    rednet.broadcast({
        type = "autoStateQuery",
        name = NAME,
        secret = SECRET
    }, PROTOCOL)
    
    -- Wait briefly for response to sync state after reboot
    local queryTimeout = os.startTimer(3.0)  -- Increased to 3 second timeout
    local stateQueryComplete = false
    
    repeat
        local event, param1, param2, param3 = os.pullEvent()
        if event == "rednet_message" then
            local sender, message, protocol = param1, param2, param3
            if protocol == PROTOCOL and type(message) == "table" then
                if message.type == "autoStateResponse" and (SECRET == "" or message.secret == SECRET) then
                    if message.enabled ~= nil then
                        autoEnabled = message.enabled
                        debugPrint("Restored auto-drive state from GUI: " .. (autoEnabled and "ON" or "OFF"))
                        if autoEnabled then
                            activeTimer = os.startTimer(0.5)  -- Start checking if enabled
                        end
                        stateQueryComplete = true
                    end
                end
            end
        elseif event == "timer" and param1 == queryTimeout then
            debugPrint("State query timeout - GUI may not be running, assuming auto-drive OFF")
            debugPrint("To manually enable auto-drive, use the GUI toggle button")
            stateQueryComplete = true
        end
    until stateQueryComplete
    
    -- Query vault status from auxiliary vault threshold monitor
    debugPrint("Querying auxiliary vault status...")
    rednet.broadcast({
        name = "odmk3-aux-vault-threshold",
        cmd = "status",
        secret = SECRET
    }, PROTOCOL)
    
    -- Broadcast our current status
    broadcastStatus()
    debugPrint("Auto-Drive ready, waiting for commands")
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, message, protocol = param1, param2, param3
            
            -- Handle command messages
            if protocol == PROTOCOL and type(message) == "table" then
                -- Verify secret if needed
                if SECRET ~= "" and message.secret ~= SECRET then
                    -- ignore messages with wrong secret
                    debugPrint("Received message with invalid secret")
                elseif message.name == NAME then
                    -- Handle commands directed to us
                    if message.cmd == "toggle" then
                        activeTimer = toggleAutoMove(message.enabled, activeTimer)
                    elseif message.cmd == "status" then
                        broadcastStatus()
                    end
                elseif message.type == "moveAck" then
                    -- Movement was processed, update our timestamp and status
                    lastMoveTime = os.clock()
                    lastMoveSuccess = message.ok or false
                    
                    -- Cancel timeout timer if it exists
                    if moveTimeoutTimer then
                        os.cancelTimer(moveTimeoutTimer)
                        moveTimeoutTimer = nil
                    end
                    
                    -- Broadcast updated status
                    broadcastStatus()
                    
                    debugPrint("Received move acknowledgment: " .. 
                              (lastMoveSuccess and "SUCCESS" or "FAILED"))
                elseif message.type == "vaultStatus" then
                    -- Vault status update from auxiliary vault threshold monitor
                    local wasVaultFull = vaultFull
                    vaultFull = message.vaultFull or false
                    
                    if wasVaultFull ~= vaultFull then
                        debugPrint("Vault status changed: " .. (vaultFull and "FULL - drilling stopped" or "AVAILABLE - drilling can resume"))
                        -- Broadcast updated status to reflect new safety condition
                        broadcastStatus()
                    end
                end
            end
            
        elseif event == "timer" and param1 == activeTimer then
            activeTimer = nil
            if autoEnabled then
                -- Check if it's safe to move
                if isSafeToMove() then
                    debugPrint("Auto-Drive: Safe to move, initiating movement")
                    if initiateMove() then
                        debugPrint("Move command sent")
                        -- Set timeout for move acknowledgment
                        if moveTimeoutTimer then
                            os.cancelTimer(moveTimeoutTimer)
                        end
                        moveTimeoutTimer = os.startTimer(MOVE_TIMEOUT)
                    end
                else
                    debugPrint("Auto-Drive: Not safe to move - waiting for safety signal")
                end
                
                -- Only set next check timer if we're still in auto mode
                if autoEnabled then
                    activeTimer = os.startTimer(CHECK_INTERVAL)
                end
            end
        elseif event == "timer" and moveTimeoutTimer and param1 == moveTimeoutTimer then
            -- Move timeout occurred
            moveTimeoutTimer = nil
            debugPrint("WARNING: Move command timed out waiting for acknowledgment")
            lastMoveSuccess = false
            broadcastStatus()
        elseif event == "redstone" then
            -- Safety signal changed, broadcast update
            if autoEnabled then
                debugPrint("Redstone signal changed, updating status")
                broadcastStatus()
                
                -- If safety signal just appeared, initiate move immediately
                if isSafeToMove() then
                    debugPrint("Safety signal appeared, immediate move check")
                    local currentTime = os.clock()
                    if currentTime - lastMoveTime >= MIN_MOVE_INTERVAL and lastMoveSuccess then
                        if initiateMove() then
                            -- Set timeout for move acknowledgment
                            if moveTimeoutTimer then
                                os.cancelTimer(moveTimeoutTimer)
                            end
                            moveTimeoutTimer = os.startTimer(MOVE_TIMEOUT)
                        end
                    else
                        debugPrint("Skipping move - too soon after last move or previous move failed")
                    end
                end
            end
        end
    end
end

-- Start the main function
main()