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
local SPEED_LOWERING = 128  -- Speed when lowering cabin
local SPEED_RAISING = -128    -- Speed when raising cabin

-- ========== State Variables ==========
local cabinLowered = false  -- Track cabin state (false = raised, true = lowered)

-- ========== Network Setup ==========
local function openAllModems()
    -- Wireless-only per system convention
    local opened = false
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            local isWireless = false
            pcall(function() isWireless = peripheral.call(side, "isWireless") end)
            if isWireless then
                if not rednet.isOpen(side) then
                    local ok, err = pcall(function() rednet.open(side) end)
                    if ok then
                        opened = true
                        print("Opened wireless modem on " .. side)
                    else
                        print("Failed to open wireless modem on " .. side .. ": " .. tostring(err))
                    end
                else
                    opened = true
                    print("Using already-open wireless modem on " .. side)
                end
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
    
    -- Startup delay to allow network initialization (matching other controllers)
    print("Waiting for network initialization...")
    sleep(1.0)
    
    -- Initialize networking (retry until any modem opens)
    if not openAllModems() then
        print("No modem found; retrying every 2s...")
        while not openAllModems() do
            sleep(2)
        end
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
    
    -- Host service name for diagnostics (optional)
    pcall(function() rednet.host(PROTOCOL, NAME) end)

    -- Periodic status via time-based tick
    local statusInterval = 10
    local lastStatus = os.clock()

    -- Main event loop (rednet.receive-based)
    while true do
        local sender, message, protocol = rednet.receive(PROTOCOL, 1)
        if sender then
            if type(message) == "table" and (SECRET == "" or message.secret == SECRET) then
                local handled = handleToggleCommand(rsc, message) or handleStatusQuery(rsc, message)
                if handled then
                    print(string.format("Handled command from computer #%d", sender))
                end
            end
        end

        -- Periodic status broadcast
        if os.clock() - lastStatus >= statusInterval then
            rednet.broadcast({
                type = "cabinPulleyStatus",
                name = NAME,
                lowered = cabinLowered,
                secret = SECRET
            }, PROTOCOL)
            lastStatus = os.clock()
        end
    end
end

-- ========== Startup ==========
main()

