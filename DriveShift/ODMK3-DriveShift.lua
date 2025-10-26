-- ODMK3-DriveShift.lua
-- Monitors machine orientation (cardinal + vertical) and emits redstone signals
-- to reverse drive direction when needed based on current orientation.

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local NAME = "odmk3-drive-shift"
local SECRET = ""  -- optional shared secret
local DEBUG = false                  -- Enable debug output
local REDSTONE_OUTPUT_SIDES = {"left", "top", "bottom"} -- The sides where redstone signals will be output
local CHECK_INTERVAL = 1            -- How often to check for orientation updates (seconds)

-- ========== State Tracking ==========
local currentCardinal = nil  -- N, E, S, W
local currentVertical = nil  -- F, U, D
local lastSignalState = false

-- ========== Utilities ==========
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

-- Open wireless modem for communication
local function openWireless()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
            if not rednet.isOpen(side) then 
                rednet.open(side)
                debugPrint("Opened wireless modem on " .. side)
            end
            return true
        end
    end
    print("ERROR: No wireless modem found!")
    return false
end

-- Set redstone output based on current orientation
local function updateRedstoneOutput()
    if not currentCardinal or not currentVertical then
        debugPrint("Incomplete orientation data - waiting for updates")
        return
    end
    
    -- Determine if redstone signal should be emitted based on orientation
    local shouldEmitSignal = false
    
    -- When the machine is facing North-Forward or West-Forward, shifts should be OFF
    if currentCardinal == "N" and currentVertical == "F" then
        shouldEmitSignal = false
    elseif currentCardinal == "W" and currentVertical == "F" then
        shouldEmitSignal = false
    -- When the machine is facing East-Down or East-Up, Drive Shift should be ON
    elseif currentCardinal == "E" and currentVertical == "D" then
        shouldEmitSignal = true
    elseif currentCardinal == "E" and currentVertical == "U" then
        shouldEmitSignal = true
    -- When the machine is facing South-Down, Drive Shift should be OFF (changed from ON)
    elseif currentCardinal == "S" and currentVertical == "D" then
        shouldEmitSignal = false
        debugPrint("South-Down orientation detected - Drive Shift OFF")
    -- When the machine is facing West-Down, Drive Shift should be ON
    elseif currentCardinal == "W" and currentVertical == "D" then
        shouldEmitSignal = true
        debugPrint("West-Down orientation detected - Drive Shift ON")
    -- When the machine is facing West-Up, Drive Shift should be ON
    elseif currentCardinal == "W" and currentVertical == "U" then
        shouldEmitSignal = true
        debugPrint("West-Up orientation detected - Drive Shift ON")
    -- You can add more conditions here for other orientations
    end
    
    -- Only update redstone if state has changed
    if shouldEmitSignal ~= lastSignalState then
        -- Set the same signal to all output sides
        for _, side in ipairs(REDSTONE_OUTPUT_SIDES) do
            redstone.setOutput(side, shouldEmitSignal)
            debugPrint("Set redstone output on " .. side .. " to " .. 
                      (shouldEmitSignal and "ON" or "OFF"))
        end
        lastSignalState = shouldEmitSignal
    end
end

-- Request current orientation from readers
local function queryOrientation()
    debugPrint("Requesting current cardinal orientation")
    rednet.broadcast({
        name = "odmk3-cardinal-reader",
        cmd = "queryFacing",
        secret = ""
    }, PROTOCOL)
    
    debugPrint("Requesting current vertical orientation")
    rednet.broadcast({
        name = "odmk3-vert-reader",
        cmd = "queryOrientation",
        secret = ""
    }, PROTOCOL)
end

-- Check direct redstone inputs for orientation
local function checkDirectRedstoneInputs()
    -- This is a placeholder - in the future, we could add direct redstone sensing
    -- similar to how CardinalRotater does, if needed
    return nil, nil
end

-- Main function
local function main()
    if not openWireless() then
        print("Failed to open wireless modem. Exiting.")
        return
    end
    
    print("ODMK3-DriveShift initialized")
    debugPrint("Waiting for orientation data")
    
    -- Ensure no redstone output at startup on all sides
    for _, side in ipairs(REDSTONE_OUTPUT_SIDES) do
        redstone.setOutput(side, false)
        debugPrint("Initialized redstone output on " .. side .. " to OFF")
    end
    lastSignalState = false
    
    -- Check if we can get orientation directly from redstone inputs
    local directCardinal, directVertical = checkDirectRedstoneInputs()
    if directCardinal then
        currentCardinal = directCardinal
        debugPrint("Initial cardinal orientation from redstone: " .. currentCardinal)
    end
    if directVertical then
        currentVertical = directVertical
        debugPrint("Initial vertical orientation from redstone: " .. currentVertical)
    end
    
    -- Initial query to get orientation from readers
    queryOrientation()
    
    -- We need both cardinal and vertical orientation before making decisions
    debugPrint("Waiting for complete orientation data before making redstone decisions")
    
    -- Start periodic check timer but with longer interval since we also use events
    local timerId = os.startTimer(CHECK_INTERVAL)
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, message, protocol = param1, param2, param3
            
            if protocol == PROTOCOL and type(message) == "table" then
                -- Verify secret if needed
                if SECRET ~= "" and message.secret ~= SECRET then
                    -- ignore messages with wrong secret
                else
                    -- Handle cardinal facing updates
                    if message.type == "facing" and message.name == "odmk3-cardinal-reader" then
                        if message.facing ~= currentCardinal then
                            debugPrint("Cardinal orientation updated: " .. message.facing)
                            currentCardinal = message.facing
                            updateRedstoneOutput()
                        end
                    
                    -- Handle vertical orientation updates
                    elseif message.type == "orientation" and message.name == "odmk3-vert-reader" then
                        if message.orientation ~= currentVertical then
                            debugPrint("Vertical orientation updated: " .. message.orientation)
                            currentVertical = message.orientation
                            updateRedstoneOutput()
                        end
                    end
                end
            end
            
        elseif event == "redstone" then
            -- Check for direct redstone-based orientation updates
            debugPrint("Redstone event detected, checking for orientation updates")
            local directCardinal, directVertical = checkDirectRedstoneInputs()
            
            if directCardinal and directCardinal ~= currentCardinal then
                debugPrint("Cardinal orientation changed via redstone: " .. directCardinal)
                currentCardinal = directCardinal
                updateRedstoneOutput()
            end
            
            if directVertical and directVertical ~= currentVertical then
                debugPrint("Vertical orientation changed via redstone: " .. directVertical)
                currentVertical = directVertical
                updateRedstoneOutput()
            end
            
        elseif event == "timer" and param1 == timerId then
            -- We still do periodic checks but less frequently
            debugPrint("Periodic orientation check")
            queryOrientation()
            timerId = os.startTimer(CHECK_INTERVAL)
        end
    end
end

main()
