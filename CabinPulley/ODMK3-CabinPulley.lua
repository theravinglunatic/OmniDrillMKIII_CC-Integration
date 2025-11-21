-- ODMK3-CabinPulley.lua
-- Rotation Speed Controller interface for cabin pulley system
-- Controls cabin raising/lowering based on network commands
-- Computer 41 with RSC on left face

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""
local NAME = "odmk3-cabin-pulley"
local RSC_SIDE = "left"
local DEBUG = false  -- Set true for verbose debug output

local function debugPrint(msg)
    if DEBUG then
        print("[DEBUG] " .. msg)
    end
end

-- Speed settings
local SPEED_LOWERING = 128  -- Speed when lowering cabin
local SPEED_RAISING = -128    -- Speed when raising cabin

-- ========== State Variables ==========
local cabinLowered = false  -- Track cabin state (false = raised, true = lowered)
local currentVertical = "F" -- Track vertical orientation (F/U/D)

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
                        debugPrint("Opened wireless modem on " .. side)
                    else
                        debugPrint("Failed to open wireless modem on " .. side .. ": " .. tostring(err))
                    end
                else
                    opened = true
                    debugPrint("Using already-open wireless modem on " .. side)
                end
            end
        end
    end
    if not opened then debugPrint("No wireless modems opened this pass") end
    return opened
end

-- ========== Peripheral Setup ==========
local function findRSC()
    local peripheralType = peripheral.getType(RSC_SIDE)
    debugPrint("Peripheral type on " .. RSC_SIDE .. ": " .. tostring(peripheralType))
    
    if peripheralType then
        return peripheral.wrap(RSC_SIDE)
    end
    return nil
end

-- ========== Speed Control Functions ==========
local function updateSpeed(rsc, lowered)
    local targetSpeed = lowered and SPEED_LOWERING or SPEED_RAISING
    rsc.setTargetSpeed(targetSpeed)
    debugPrint(string.format("Set speed to %d RPM (Cabin %s)", targetSpeed, lowered and "LOWERING" or "RAISING"))
end

local function handleToggleCommand(rsc, message)
    if message.name == NAME and message.cmd == "toggle" then
        -- Safety: block activation while machine is facing DOWN
        if currentVertical == "D" then
            print("[BLOCK] Cabin pulley toggle ignored: machine is facing DOWN")
            -- Broadcast current status unchanged (optionally include reason)
            rednet.broadcast({
                type = "cabinPulleyStatus",
                name = NAME,
                lowered = cabinLowered,
                reason = "facing_down",
                secret = SECRET
            }, PROTOCOL)
            return true
        end
        cabinLowered = not cabinLowered
        updateSpeed(rsc, cabinLowered)
        
        -- Sequence integration with sticker + utility RSC reversal
        -- ON (lowered=true): retract sticker, wait 1s, reverse utility RSC
        -- OFF (lowered=false): reverse utility RSC, extend sticker
        if cabinLowered then
            debugPrint("Cabin lowering sequence start: retract sticker -> delay -> reverse RSC")
            rednet.broadcast({ name = "odmk3-cabin-sticker", cmd = "retract", secret = SECRET }, PROTOCOL)
            sleep(1)
            rednet.broadcast({ name = "odmk3-utility-rsc", cmd = "reverse", secret = SECRET }, PROTOCOL)
        else
            debugPrint("Cabin raising sequence start: reverse RSC -> extend sticker")
            rednet.broadcast({ name = "odmk3-utility-rsc", cmd = "reverse", secret = SECRET }, PROTOCOL)
            rednet.broadcast({ name = "odmk3-cabin-sticker", cmd = "extend", secret = SECRET }, PROTOCOL)
        end
        
        -- Broadcast status response AFTER sequence start
        rednet.broadcast({
            type = "cabinPulleyStatus",
            name = NAME,
            lowered = cabinLowered,
            secret = SECRET
        }, PROTOCOL)
        debugPrint("Toggle command processed; cabinLowered=" .. tostring(cabinLowered))
        
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

local function handleOrientation(message)
    if message.type == "orientation" and message.orientation then
        local ori = tostring(message.orientation)
        if ori == "F" or ori == "U" or ori == "D" then
            if currentVertical ~= ori then
                debugPrint("Orientation updated: " .. currentVertical .. " -> " .. ori)
                currentVertical = ori
            end
            return true
        end
    end
    return false
end

-- ========== Main Function ==========
local function main()
    print("ODMK3 Cabin Pulley Controller starting...")
    print("DEBUG mode: " .. (DEBUG and "ON" or "OFF"))
    
    -- Startup delay to allow network initialization (matching other controllers)
    debugPrint("Waiting for network initialization (1s delay)...")
    sleep(1.0)
    
    -- Initialize networking (retry until any modem opens)
    if not openAllModems() then
        print("No modem found; retrying every 2s...")
        debugPrint("Entering modem retry loop")
        while not openAllModems() do
            sleep(2)
        end
    end
    
    -- Find the Rotation Speed Controller
    local rsc = findRSC()
    if not rsc then
        error("No peripheral found on " .. RSC_SIDE)
    end
    
    print("Rotation Speed Controller online")  -- keep visible
    print("")
    
    -- Set initial speed (cabin raised)
    updateSpeed(rsc, cabinLowered)
    print(string.format("Initial state: Cabin %s", cabinLowered and "LOWERED" or "RAISED"))
    
    debugPrint("Monitoring for toggle commands...")
    print("")
    
    -- Host service name for diagnostics (optional)
    pcall(function() rednet.host(PROTOCOL, NAME) end)
    debugPrint("Hosted rednet service name (if supported): " .. NAME)

    -- Periodic status via time-based tick
    local statusInterval = 10
    local lastStatus = os.clock()

    -- Main event loop (rednet.receive-based)
    while true do
        local sender, message, protocol = rednet.receive(PROTOCOL, 1)
        if sender then
            if type(message) == "table" and (SECRET == "" or message.secret == SECRET) then
                local handled = handleOrientation(message)
                    or handleToggleCommand(rsc, message)
                    or handleStatusQuery(rsc, message)
                if handled then
                    debugPrint(string.format("Handled command from computer #%d", sender))
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
            debugPrint("Periodic status broadcast; lowered=" .. tostring(cabinLowered))
            lastStatus = os.clock()
        end
    end
end

-- ========== Startup ==========
main()

