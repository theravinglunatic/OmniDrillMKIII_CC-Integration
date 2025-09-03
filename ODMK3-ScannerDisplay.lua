-- ODMK3-ScannerDisplay.lua
-- Geo Scanner display for Omni-Drill MKIII cabin
-- Receives scan data from relay and displays on monitor
-- Based on geo_sonar.lua visualization system

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local NAME = "odmk3-scanner-display"
local RELAY_NAME = "odmk3-geo-scanner-relay"
local SECRET = ""

-- Display settings
local DEFAULT_RADIUS = 12
local DEFAULT_SLICE_THICK = 3
local DEFAULT_SLICE_OFFSET = 0
local DEFAULT_VIEW = "top"  -- "top" (XZ), "front" (XY), "side" (ZY)
local LEGEND_ROWS = 3
local AUTO_SCAN_INTERVAL = 30  -- seconds, 0 to disable

-- Colors (matching geo_sonar.lua)
local BG_COLOR = colors.black
local FRAME_COLOR = colors.gray
local POINT_COLOR = colors.lime
local ORE_COLOR = colors.orange
local FLUID_COLOR = colors.lightBlue
local WOOD_COLOR = colors.brown
local MARK_FG = colors.red     -- "you are here" marker
local MARK_BG = colors.black
local MARK_CHAR = "X"
local STATUS_COLOR = colors.white
local ERROR_COLOR = colors.red

-- Debug configuration
local DEBUG = false

-- ========== State Variables ==========
local monitor = nil
local currentData = nil
local currentRadius = DEFAULT_RADIUS
local sliceThick = DEFAULT_SLICE_THICK
local sliceOffset = DEFAULT_SLICE_OFFSET
local currentView = DEFAULT_VIEW
local lastScanTime = 0
local scanInProgress = false
local lastError = nil
local relayOnline = false

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

-- ========== Monitor Discovery and Setup ==========
local function findMonitor()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "monitor" then
            debugPrint("Found monitor on " .. side)
            return peripheral.wrap(side)
        end
    end
    return nil
end

local function setupMonitor()
    monitor = findMonitor()
    if not monitor then
        error("No monitor found! Attach an Advanced Monitor.")
    end
    
    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(BG_COLOR)
    monitor.clear()
    return true
end

-- ========== Monitor Drawing Functions ==========
local function mclear()
    monitor.setBackgroundColor(BG_COLOR)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

local function mwriteXY(x, y, text, fg, bg)
    if fg then monitor.setTextColor(fg) end
    if bg then monitor.setBackgroundColor(bg) end
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local function fillRect(x1, y1, x2, y2, bg)
    monitor.setBackgroundColor(bg)
    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        monitor.write(string.rep(" ", x2 - x1 + 1))
    end
end

local function drawBox(x1, y1, x2, y2, fg)
    monitor.setTextColor(fg)
    for x = x1, x2 do
        monitor.setCursorPos(x, y1)
        monitor.write("-")
        monitor.setCursorPos(x, y2)
        monitor.write("-")
    end
    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        monitor.write("|")
        monitor.setCursorPos(x2, y)
        monitor.write("|")
    end
end

-- ========== Data Processing (from geo_sonar.lua) ==========
local function classifyColor(name, tags)
    if name:find("lava") or name:find("water") or (tags and tags["minecraft:fluid"]) then
        return FLUID_COLOR
    elseif name:find("ore") or (name:find(":deepslate_") and name:find("ore")) then
        return ORE_COLOR
    elseif name:find("log") or name:find("wood") then
        return WOOD_COLOR
    else
        return POINT_COLOR
    end
end

local VIEW_DEF = {
    top   = {U="x", V="z", W="y", name="TOP (XZ)"},
    front = {U="x", V="y", W="z", name="FRONT (XY)"},
    side  = {U="z", V="y", W="x", name="SIDE (ZY)"},
}

local function axisVal(b, axis)
    return b[axis]
end

local function centerFromBlocks(blocks)
    local min = {x=1e9, y=1e9, z=1e9}
    local max = {x=-1e9, y=-1e9, z=-1e9}
    for _, b in ipairs(blocks) do
        if b.x < min.x then min.x = b.x end
        if b.x > max.x then max.x = b.x end
        if b.y < min.y then min.y = b.y end
        if b.y > max.y then max.y = b.y end
        if b.z < min.z then min.z = b.z end
        if b.z > max.z then max.z = b.z end
    end
    return {
        x = math.floor((min.x + max.x) / 2 + 0.5),
        y = math.floor((min.y + max.y) / 2 + 0.5),
        z = math.floor((min.z + max.z) / 2 + 0.5),
    }
end

local function buildMap(blocks, viewKey, sliceThick, sliceOffset)
    local vd = VIEW_DEF[viewKey]
    if not vd then vd = VIEW_DEF.top end
    local C = centerFromBlocks(blocks)

    -- slice window along W
    local half = math.floor((sliceThick - 1) / 2)
    local wMin = C[vd.W] + sliceOffset - half
    local wMax = C[vd.W] + sliceOffset + (sliceThick - 1 - half)

    local pts = {}
    local prio = {[ORE_COLOR]=3, [FLUID_COLOR]=2, [WOOD_COLOR]=1, [POINT_COLOR]=0}
    for _, b in ipairs(blocks) do
        local w = axisVal(b, vd.W)
        if w >= wMin and w <= wMax then
            local du = axisVal(b, vd.U) - C[vd.U]
            local dv = axisVal(b, vd.V) - C[vd.V]
            local key = du .. "," .. dv
            local col = classifyColor(b.name or "", b.tags or {})
            if not pts[key] or prio[col] > prio[pts[key]] then
                pts[key] = col
            end
        end
    end
    return pts, C
end

local function uvToPixel(du, dv, gx1, gy1, gx2, gy2, radius)
    local gw, gh = gx2 - gx1 + 1, gy2 - gy1 + 1
    local nx = (du / radius + 1) / 2    -- 0..1
    local ny = (dv / radius + 1) / 2
    local px = gx1 + math.floor(nx * (gw - 1) + 0.5)
    local py = gy1 + math.floor(ny * (gh - 1) + 0.5)
    return px, py
end

-- ========== Display Rendering ==========
local function renderScanData()
    if not monitor or not currentData then
        return
    end
    
    mclear()
    local w, h = monitor.getSize()
    local usableH = h - LEGEND_ROWS

    drawBox(1, 1, w, usableH, FRAME_COLOR)

    local pts, C = buildMap(currentData, currentView, sliceThick, sliceOffset)
    local vd = VIEW_DEF[currentView]
    local viewName = vd.name

    local gx1, gy1 = 2, 2
    local gx2, gy2 = w - 1, usableH - 1

    -- paint cells by sampling each display pixel -> nearest (dU,dV)
    for py = gy1, gy2 do
        for px = gx1, gx2 do
            local gw, gh = gx2 - gx1 + 1, gy2 - gy1 + 1
            local nx = (px - gx1) / math.max(gw - 1, 1) * 2 - 1
            local ny = (py - gy1) / math.max(gh - 1, 1) * 2 - 1
            local du = math.floor(nx * currentRadius + 0.5)
            local dv = math.floor(ny * currentRadius + 0.5)
            local key = du .. "," .. dv
            local c = pts[key]
            if c then
                monitor.setBackgroundColor(c)
                monitor.setCursorPos(px, py)
                monitor.write(" ")
            end
        end
    end

    -- "You are here" marker at (dU=0,dV=0)
    local mx, my = uvToPixel(0, 0, gx1, gy1, gx2, gy2, currentRadius)
    monitor.setTextColor(MARK_FG)
    monitor.setBackgroundColor(MARK_BG)
    monitor.setCursorPos(mx, my)
    monitor.write(MARK_CHAR)

    -- Legend/status
    local y = usableH + 1
    fillRect(1, y, w, h, BG_COLOR)
    
    -- Status line 1: View and parameters
    mwriteXY(1, y, string.format("%s  R:%d  Slice:%d  Off:%d", 
        viewName, currentRadius, sliceThick, sliceOffset), STATUS_COLOR, BG_COLOR)
    
    -- Status line 2: Scan info
    local scanAge = os.epoch("utc") - lastScanTime
    local ageText = lastScanTime > 0 and string.format("Age:%ds", math.floor(scanAge/1000)) or "No data"
    local blockCount = currentData and #currentData or 0
    mwriteXY(1, y + 1, string.format("Blocks:%d  %s  Relay:%s", 
        blockCount, ageText, relayOnline and "Online" or "Offline"), STATUS_COLOR, BG_COLOR)
        
    -- Status line 3: Controls or error
    if lastError then
        mwriteXY(1, y + 2, "ERROR: " .. lastError, ERROR_COLOR, BG_COLOR)
    elseif scanInProgress then
        mwriteXY(1, y + 2, "Scanning...", colors.yellow, BG_COLOR)
    else
        mwriteXY(1, y + 2, "R=Rescan  W/S=Offset  A/D=Thick  V=View  Q=Quit", colors.lightGray, BG_COLOR)
    end
end

local function renderNoData()
    if not monitor then return end
    
    mclear()
    local w, h = monitor.getSize()
    
    -- Center message
    local msg1 = "Omni-Drill MKIII Geo Scanner"
    local msg2 = relayOnline and "Press R to scan" or "Connecting to scanner relay..."
    local msg3 = lastError and ("Error: " .. lastError) or ""
    
    mwriteXY(math.floor((w - #msg1) / 2) + 1, math.floor(h / 2) - 1, msg1, STATUS_COLOR, BG_COLOR)
    mwriteXY(math.floor((w - #msg2) / 2) + 1, math.floor(h / 2), msg2, STATUS_COLOR, BG_COLOR)
    if msg3 ~= "" then
        mwriteXY(math.floor((w - #msg3) / 2) + 1, math.floor(h / 2) + 1, msg3, ERROR_COLOR, BG_COLOR)
    end
    
    -- Status at bottom
    mwriteXY(1, h, string.format("Relay: %s | R=Scan Q=Quit", 
        relayOnline and "Online" or "Offline"), colors.lightGray, BG_COLOR)
end

-- ========== Network Communication ==========
local function requestScan(radius)
    radius = radius or currentRadius
    if scanInProgress then
        debugPrint("Scan already in progress")
        return false
    end
    
    scanInProgress = true
    lastError = nil
    
    debugPrint("Requesting scan with radius " .. radius)
    rednet.broadcast({
        name = RELAY_NAME,
        cmd = "requestScan",
        radius = radius,
        secret = SECRET
    }, PROTOCOL)
    
    renderNoData()  -- Update display to show scanning status
    return true
end

local function requestRelayStatus()
    debugPrint("Requesting relay status")
    rednet.broadcast({
        name = RELAY_NAME,
        cmd = "requestStatus",
        secret = SECRET
    }, PROTOCOL)
end

local function handleScanResponse(msg)
    scanInProgress = false
    
    if msg.success and msg.data then
        currentData = msg.data
        currentRadius = msg.radius or currentRadius
        lastScanTime = msg.timestamp or os.epoch("utc")
        lastError = nil
        print(string.format("Received scan data: %d blocks", #msg.data))
        renderScanData()
    else
        lastError = msg.error or "Unknown scan error"
        print("Scan failed: " .. lastError)
        renderNoData()
    end
end

local function handleStatusResponse(msg)
    relayOnline = msg.scannerAvailable
    if not relayOnline and msg.scannerAvailable == false then
        lastError = "Scanner not available"
    else
        lastError = nil
    end
    debugPrint("Relay status: " .. (relayOnline and "online" or "offline"))
    
    if not currentData then
        renderNoData()
    end
end

-- ========== Input Handling ==========
local function handleKeypress(key)
    if key == keys.q then
        mclear()
        return false  -- Exit
    elseif key == keys.r then
        requestScan()
    elseif key == keys.w then
        sliceOffset = sliceOffset + 1
        if currentData then renderScanData() end
    elseif key == keys.s then
        sliceOffset = sliceOffset - 1
        if currentData then renderScanData() end
    elseif key == keys.d then
        sliceThick = math.min(25, sliceThick + 1)
        if currentData then renderScanData() end
    elseif key == keys.a then
        sliceThick = math.max(1, sliceThick - 1)
        if currentData then renderScanData() end
    elseif key == keys.v then
        local views = {"top", "front", "side"}
        local currentIndex = 1
        for i, view in ipairs(views) do
            if view == currentView then
                currentIndex = i
                break
            end
        end
        currentIndex = currentIndex % #views + 1
        currentView = views[currentIndex]
        if currentData then renderScanData() end
    end
    return true  -- Continue
end

-- ========== Main Event Loop ==========
local function main()
    print("ODMK3 Scanner Display starting...")
    
    -- Initialize networking
    if not openAllModems() then
        error("No wireless modem found!")
    end
    
    -- Initialize monitor
    setupMonitor()
    
    print("Scanner Display online")
    print("Protocol: " .. PROTOCOL)
    print("Relay: " .. RELAY_NAME)
    
    -- Initial display
    renderNoData()
    
    -- Request initial status
    requestRelayStatus()
    
    -- Auto-scan timer
    local autoScanTimer = nil
    if AUTO_SCAN_INTERVAL > 0 then
        autoScanTimer = os.startTimer(AUTO_SCAN_INTERVAL)
    end
    
    -- Main event loop
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, message, protocol = p1, p2, p3
            if protocol == PROTOCOL and type(message) == "table" then
                -- Check secret if configured
                if SECRET == "" or message.secret == SECRET then
                    if message.type == "scanResponse" and message.name == RELAY_NAME then
                        handleScanResponse(message)
                    elseif message.type == "statusResponse" and message.name == RELAY_NAME then
                        handleStatusResponse(message)
                    end
                end
            end
            
        elseif event == "key" then
            if not handleKeypress(p1) then
                break  -- Exit requested
            end
            
        elseif event == "timer" and p1 == autoScanTimer then
            -- Auto-scan
            if AUTO_SCAN_INTERVAL > 0 and relayOnline and not scanInProgress then
                requestScan()
            end
            autoScanTimer = os.startTimer(AUTO_SCAN_INTERVAL)
            
        elseif event == "monitor_resize" then
            if currentData then
                renderScanData()
            else
                renderNoData()
            end
        end
    end
    
    print("Scanner Display shutting down")
end

-- ========== Startup ==========
main()
