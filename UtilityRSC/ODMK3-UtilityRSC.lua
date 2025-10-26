-- ODMK3-UtilityRSC.lua
-- Rotation Speed Controller interface for Omni-Drill MKIII
-- Controls rotation speed based on cardinal direction
-- Computer 40 with RSC on right face

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""
local RSC_SIDE = "right"
local CARDINAL_READER_NAME = "odmk3-cardinal-reader"

-- Speed settings by direction
local SPEED_MAP = {
    N = 128,   -- North: 128 RPM
    E = 128,   -- East: 128 RPM
    S = -128,  -- South: -128 RPM
    W = -128   -- West: -128 RPM
}

-- ========== State Variables ==========
local currentCardinal = "N"  -- Current cardinal direction

-- ========== Network Setup ==========
local function openAllModems()
    local opened = false
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if peripheral.call(side, "isWireless") then
                rednet.open(side)
                opened = true
                print("Opened wireless modem on " .. side)
            end
        end
    end
    return opened
end

-- ========== Peripheral Setup ==========
local function findRSC()
    local peripheralType = peripheral.getType(RSC_SIDE)
    print("Peripheral type on " .. RSC_SIDE .. ": " .. tostring(peripheralType))
    
    -- Try wrapping regardless of type name (Create mod peripherals have varying names)
    if peripheralType then
        return peripheral.wrap(RSC_SIDE)
    end
    return nil
end

-- ========== Speed Control Functions ==========
local function updateSpeed(rsc, direction)
    local targetSpeed = SPEED_MAP[direction]
    if targetSpeed then
        rsc.setTargetSpeed(targetSpeed)
        print(string.format("Set speed to %d RPM for direction %s", targetSpeed, direction))
    end
end

local function handleFacingMessage(rsc, message)
    if message.type == "facing" and message.name == CARDINAL_READER_NAME and message.facing then
        local newDirection = message.facing
        if currentCardinal ~= newDirection then
            print(string.format("Direction changed: %s -> %s", currentCardinal, newDirection))
            currentCardinal = newDirection
            updateSpeed(rsc, currentCardinal)
            return true
        else
            -- Even if direction hasn't changed, update speed on first message
            updateSpeed(rsc, currentCardinal)
            return true
        end
    end
    return false
end

-- ========== Main Function ==========
local function main()
    print("ODMK3 Utility RSC starting...")
    
    -- Startup delay to allow other systems to initialize
    print("Waiting for network initialization...")
    sleep(0.1)
    
    -- Initialize networking
    if not openAllModems() then
        error("No wireless modem found!")
    end
    
    -- Find the Rotation Speed Controller
    local rsc = findRSC()
    if not rsc then
        error("No peripheral found on " .. RSC_SIDE)
    end
    
    print("Rotation Speed Controller online")
    print("")
    
    -- Request initial cardinal direction and wait for response
    print("Requesting initial direction...")
    rednet.broadcast({ cmd = "queryFacing", secret = SECRET }, PROTOCOL)
    
    -- Wait for initial facing response (with timeout)
    local timeout = os.startTimer(3)
    local gotInitialFacing = false
    
    while not gotInitialFacing do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, message, protocol = p1, p2, p3
            if protocol == PROTOCOL and type(message) == "table" then
                if SECRET == "" or message.secret == SECRET then
                    if handleFacingMessage(rsc, message) then
                        gotInitialFacing = true
                        os.cancelTimer(timeout)
                        print(string.format("Initial direction: %s", currentCardinal))
                    end
                end
            end
        elseif event == "timer" and p1 == timeout then
            print("Timeout waiting for initial direction, using default: " .. currentCardinal)
            updateSpeed(rsc, currentCardinal)
            break
        end
    end
    
    print("Monitoring for direction changes...")
    print("")
    
    -- Periodic status broadcast timer
    local statusTimer = os.startTimer(10)
    
    -- Main event loop
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, message, protocol = p1, p2, p3
            if protocol == PROTOCOL and type(message) == "table" then
                -- Check secret if configured
                if SECRET == "" or message.secret == SECRET then
                    handleFacingMessage(rsc, message)
                end
            end
            
        elseif event == "timer" and p1 == statusTimer then
            -- Periodically query for current direction
            rednet.broadcast({ cmd = "queryFacing", secret = SECRET }, PROTOCOL)
            statusTimer = os.startTimer(10)
        end
        
        -- Uncomment to display current speed periodically
        -- if event == "timer" and p1 == monitorTimer then
        --     local speed = rsc.getTargetSpeed()
        --     print(string.format("Current Target Speed: %.2f RPM", speed))
        --     monitorTimer = os.startTimer(5)
        -- end
        
        sleep(0.05)
    end
end

-- ========== Startup ==========
main()
