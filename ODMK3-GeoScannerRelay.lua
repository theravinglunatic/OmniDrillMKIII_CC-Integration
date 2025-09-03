-- ODMK3-GeoScannerRelay.lua
-- Geo Scanner relay for Omni-Drill MKIII
-- Performs geo scans and relays data to display computers via rednet

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local NAME = "odmk3-geo-scanner-relay"
local SECRET = ""
local DEFAULT_RADIUS = 12
local SCAN_COOLDOWN_CHECK = true

-- Debug configuration
local DEBUG = false

-- ========== Debug Utilities ==========
local function debugPrint(msg)
    if DEBUG then
        print("[DEBUG] " .. msg)
    end
end

-- ========== Network Setup ==========
local function openAllModems()
    local opened = false
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if peripheral.call(side, "isWireless") then
                rednet.open(side)
                opened = true
                debugPrint("Opened wireless modem on " .. side)
            end
        end
    end
    return opened
end

-- ========== Peripheral Discovery ==========
local function findGeoScanner()
    -- Check for geo scanner on back face first (as described)
    if peripheral.getType("back") == "geoScanner" then
        debugPrint("Found geo scanner on back face")
        return peripheral.wrap("back")
    end
    
    -- Fallback: search all sides
    for _, side in ipairs(rs.getSides()) do
        local pType = peripheral.getType(side)
        if pType == "geoScanner" or pType == "geo_scanner" then
            debugPrint("Found geo scanner on " .. side)
            return peripheral.wrap(side)
        end
    end
    
    return nil
end

-- ========== Scan Operations ==========
local function performScan(scanner, radius)
    radius = radius or DEFAULT_RADIUS
    
    -- Check cooldown if available
    if SCAN_COOLDOWN_CHECK and scanner.getScanCooldown then
        local cooldown = scanner.getScanCooldown()
        if cooldown and cooldown > 0 then
            debugPrint("Scanner on cooldown for " .. cooldown .. "ms")
            sleep(cooldown / 1000)
        end
    end
    
    debugPrint("Performing scan with radius " .. radius)
    local startTime = os.clock()
    
    local success, result = pcall(function()
        return scanner.scan(radius)
    end)
    
    local scanTime = os.clock() - startTime
    
    if not success then
        print("Scan failed: " .. tostring(result))
        return nil, "Scan error: " .. tostring(result)
    end
    
    if not result then
        print("Scan returned no data")
        return nil, "No scan data returned"
    end
    
    print("Scan completed in " .. string.format("%.2f", scanTime) .. "s, found " .. #result .. " blocks")
    return result, nil
end

-- ========== Network Message Handlers ==========
local function handleScanRequest(sender, msg)
    if msg.cmd ~= "requestScan" then return end
    
    debugPrint("Received scan request from " .. sender)
    
    local scanner = findGeoScanner()
    if not scanner then
        print("No geo scanner found!")
        rednet.send(sender, {
            type = "scanResponse",
            name = NAME,
            success = false,
            error = "No geo scanner available",
            secret = SECRET
        }, PROTOCOL)
        return
    end
    
    local radius = msg.radius or DEFAULT_RADIUS
    local data, error = performScan(scanner, radius)
    
    if data then
        -- Send successful scan data
        rednet.send(sender, {
            type = "scanResponse",
            name = NAME,
            success = true,
            data = data,
            radius = radius,
            timestamp = os.epoch("utc"),
            secret = SECRET
        }, PROTOCOL)
        debugPrint("Sent scan data to " .. sender .. " (" .. #data .. " blocks)")
    else
        -- Send error response
        rednet.send(sender, {
            type = "scanResponse",
            name = NAME,
            success = false,
            error = error or "Unknown scan error",
            secret = SECRET
        }, PROTOCOL)
        print("Sent error response: " .. (error or "unknown"))
    end
end

local function handleStatusRequest(sender, msg)
    if msg.cmd ~= "requestStatus" then return end
    
    debugPrint("Received status request from " .. sender)
    
    local scanner = findGeoScanner()
    local status = {
        type = "statusResponse",
        name = NAME,
        scannerAvailable = scanner ~= nil,
        defaultRadius = DEFAULT_RADIUS,
        timestamp = os.epoch("utc"),
        secret = SECRET
    }
    
    if scanner and scanner.getScanCooldown then
        status.cooldown = scanner.getScanCooldown()
    end
    
    rednet.send(sender, status, PROTOCOL)
    debugPrint("Sent status response to " .. sender)
end

-- ========== Main Event Loop ==========
local function main()
    print("ODMK3 Geo Scanner Relay starting...")
    
    -- Initialize networking
    if not openAllModems() then
        print("ERROR: No wireless modem found!")
        return
    end
    
    -- Check for geo scanner
    local scanner = findGeoScanner()
    if scanner then
        print("Geo Scanner found and ready")
        if scanner.getScanCooldown then
            local cooldown = scanner.getScanCooldown()
            if cooldown and cooldown > 0 then
                print("Initial cooldown: " .. cooldown .. "ms")
            end
        end
    else
        print("WARNING: No geo scanner found! Will retry on requests.")
    end
    
    print("Geo Scanner Relay online - waiting for scan requests")
    print("Protocol: " .. PROTOCOL)
    print("Name: " .. NAME)
    
    -- Main event loop
    while true do
        local event, sender, message, protocol = os.pullEvent("rednet_message")
        
        if protocol == PROTOCOL and type(message) == "table" then
            -- Check secret if configured
            if SECRET ~= "" and message.secret ~= SECRET then
                debugPrint("Ignoring message with incorrect secret from " .. sender)
            else
                -- Handle different message types
                if message.cmd == "requestScan" then
                    handleScanRequest(sender, message)
                elseif message.cmd == "requestStatus" then
                    handleStatusRequest(sender, message)
                else
                    debugPrint("Unknown command: " .. tostring(message.cmd))
                end
            end
        end
    end
end

-- ========== Startup ==========
main()