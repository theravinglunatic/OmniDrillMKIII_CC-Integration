-- ODMK3-CabinPulley.lua
-- Rotation Speed Controller interface for cabin pulley system
-- Controls cabin raising/lowering based on network commands
-- Computer 41 with RSC on left face

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""
local NAME = "odmk3-cabin-pulley"
local RSC_SIDE = "left"

-- Speed settings
local SPEED_LOWERING = -128  -- Speed when lowering cabin
local SPEED_RAISING = 128    -- Speed when raising cabin

-- ========== State Variables ==========
local cabinLowered = false  -- Track cabin state (false = raised, true = lowered)

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
    
    if peripheralType then
        return peripheral.wrap(RSC_SIDE)
    end
    return nil
end

-- ========== Speed Control Functions ==========
local function updateSpeed(rsc, lowered)
    local targetSpeed = lowered and SPEED_LOWERING or SPEED_RAISING
    rsc.setTargetSpeed(targetSpeed)
    print(string.format("Set speed to %d RPM (Cabin %s)", targetSpeed, lowered and "LOWERING" or "RAISING"))
end

local function handleToggleCommand(rsc, message)
    if message.name == NAME and message.cmd == "toggle" then
        cabinLowered = not cabinLowered
        updateSpeed(rsc, cabinLowered)
        
        -- Broadcast status response
        rednet.broadcast({
            type = "cabinPulleyStatus",
            name = NAME,
            lowered = cabinLowered,
            secret = SECRET
        }, PROTOCOL)
        
        return true
    end
    return false
end

local function handleStatusQuery(rsc, message)
    if message.name == NAME and message.cmd == "status" then
        -- Respond with current status
        rednet.broadcast({
            type = "cabinPulleyStatus",
            name = NAME,
            lowered = cabinLowered,
            secret = SECRET
        }, PROTOCOL)
        return true
    end
    return false
end

-- ========== Main Function ==========
local function main()
    print("ODMK3 Cabin Pulley Controller starting...")
    
    -- Startup delay to allow network initialization
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
    
    -- Set initial speed (cabin raised)
    updateSpeed(rsc, cabinLowered)
    print(string.format("Initial state: Cabin %s", cabinLowered and "LOWERED" or "RAISED"))
    
    print("Monitoring for toggle commands...")
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
                    handleToggleCommand(rsc, message)
                    handleStatusQuery(rsc, message)
                end
            end
            
        elseif event == "timer" and p1 == statusTimer then
            -- Periodically broadcast status
            rednet.broadcast({
                type = "cabinPulleyStatus",
                name = NAME,
                lowered = cabinLowered,
                secret = SECRET
            }, PROTOCOL)
            statusTimer = os.startTimer(10)
        end
        
        sleep(0.05)
    end
end

-- ========== Startup ==========
main()

