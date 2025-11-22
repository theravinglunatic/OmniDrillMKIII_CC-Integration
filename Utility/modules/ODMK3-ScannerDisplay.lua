-- ODMK3-ScannerDisplay.lua
-- Geo Scanner display for Omni-Drill MKIII cabin
-- Receives scan data from relay and displays on monitor
-- Automatic-only display (manual controls removed)
-- Based on geo_sonar.lua visualization system

local PROTOCOL = "Omni-DrillMKIII"
local NAME = "odmk3-scanner-display"
local RELAY_NAME = "odmk3-geo-scanner-relay"
local CARDINAL_READER_NAME = "odmk3-cardinal-reader"
local VERT_READER_NAME = "odmk3-vert-reader"
local SECRET = ""

-- Display settings
local ScannerCfg = require("modules.scanner_config")
local ScannerCache = require("modules.scanner_cache")
local ScannerRender = require("modules.scanner_render")
local ScannerUtils = require("modules.scanner_utils")
local ScannerOrientation = require("modules.scanner_orientation")

-- Display settings (with config fallbacks)
local DEFAULT_RADIUS = (ScannerCfg.ui and ScannerCfg.ui.defaultRadius) or 12
local DEFAULT_SLICE_THICK = (ScannerCfg.ui and ScannerCfg.ui.defaultSliceThick) or 1
local DEFAULT_SLICE_OFFSET = (ScannerCfg.ui and ScannerCfg.ui.defaultSliceOffset) or -2
local DEFAULT_VIEW = (ScannerCfg.ui and ScannerCfg.ui.defaultView) or "front"  -- "top" (XZ), "front" (XY), "side" (ZY)
local LEGEND_ROWS = (ScannerCfg.layout and ScannerCfg.layout.legendRows) or 3

-- Auto-cycling settings
local AUTO_CYCLE_ENABLED = (ScannerCfg.auto and ScannerCfg.auto.cycle and ScannerCfg.auto.cycle.enabled) ~= false
local AUTO_CYCLE_INTERVAL = (ScannerCfg.auto and ScannerCfg.auto.cycle and ScannerCfg.auto.cycle.intervalSec) or 0.5
local AUTO_SCAN_INTERVAL = (ScannerCfg.auto and ScannerCfg.auto.scan and ScannerCfg.auto.scan.intervalSec) or 0
local HAZARD_BLINK_INTERVAL = (ScannerCfg.auto and ScannerCfg.auto.hazardBlinkIntervalSec) or 0.25
local AGE_REFRESH_INTERVAL = (ScannerCfg.auto and ScannerCfg.auto.ageRefreshIntervalSec) or 1

-- Direction-based display settings
local DIRECTION_SETTINGS = (ScannerCfg.directionSettings) or {
    N = {view = "front", minOffset = -12, maxOffset = -2},
    W = {view = "side",  minOffset = -12, maxOffset = -2},
    F = {view = "front", minOffset = -12, maxOffset = -2},
    D = {view = "top",   minOffset = -12, maxOffset = -2},
    E = {view = "side",  minOffset = 2,  maxOffset = 12},
    S = {view = "front", minOffset = 2,  maxOffset = 12},
    U = {view = "top",   minOffset = 2,  maxOffset = 12},
}
-- Colors (matching geo_sonar.lua) now customizable via config
local BG_COLOR = (ScannerCfg.colors and ScannerCfg.colors.BG) or colors.black
local FRAME_COLOR = (ScannerCfg.colors and ScannerCfg.colors.FRAME) or colors.gray
local POINT_COLOR = (ScannerCfg.colors and ScannerCfg.colors.POINT) or colors.gray
local ORE_COLOR = (ScannerCfg.colors and ScannerCfg.colors.ORE) or colors.orange
local FLUID_COLOR = (ScannerCfg.colors and ScannerCfg.colors.FLUID) or colors.lightBlue
local WOOD_COLOR = (ScannerCfg.colors and ScannerCfg.colors.WOOD) or colors.brown
local MARK_FG = (ScannerCfg.colors and ScannerCfg.colors.MARK_FG) or colors.red
local MARK_BG = (ScannerCfg.colors and ScannerCfg.colors.MARK_BG) or colors.black
local MARK_CHAR = (ScannerCfg.ui and ScannerCfg.ui.mark and ScannerCfg.ui.mark.char) or "X"
local STATUS_COLOR = (ScannerCfg.colors and ScannerCfg.colors.STATUS) or colors.white
local ERROR_COLOR = (ScannerCfg.colors and ScannerCfg.colors.ERROR) or colors.red
local HEADER_BG = (ScannerCfg.colors and ScannerCfg.colors.headerBG) or colors.yellow
local HEADER_FG = (ScannerCfg.colors and ScannerCfg.colors.headerFG) or colors.black

-- Debug configuration
local DEBUG = (ScannerCfg.debug and ScannerCfg.debug.enabled) or false

-- Overlay single-character labels on ore pixels
local SHOW_ORE_LABELS = (ScannerCfg.ui and ScannerCfg.ui.showOreLabels) ~= false

-- ========== State Variables ==========
local monitor = nil
local currentData = nil
local currentRadius = DEFAULT_RADIUS
local sliceThick = DEFAULT_SLICE_THICK
local sliceOffset = DEFAULT_SLICE_OFFSET
local currentView = DEFAULT_VIEW
local lastScanTime = 0
local lastScanGameTicks = 0          -- in-game ticks when last scan completed
local scanInProgress = false
local lastError = nil
local relayOnline = false
local lastStatusResponseTime = 0        -- ms since epoch of last status response
local scanRequestTime = 0               -- ms since epoch of last scan request
local relayCooldownMs = 0               -- last reported cooldown from relay (ms)
local pendingScanTimer = nil            -- timer id for deferred scan after cooldown
local pendingScanEta = 0                -- ms epoch when pending scan will fire
local waitingCooldown = false           -- UI status flag
local newScanBtn = nil                  -- New Scan disabled (unused)
-- Cached aggregates for right pane (legend, POIs, hazards)
local sidePaneCache = nil

-- Auto-cycling state
local autoCycleEnabled = AUTO_CYCLE_ENABLED  -- Direction-aware cycling
local currentCardinal = "N"  -- Current cardinal direction (N/E/S/W)
local currentVertical = "F"  -- Current vertical direction (F/U/D)
local currentDirection = "N" -- Active direction for display settings
local cycleMinOffset = -12
local cycleMaxOffset = -2
local cycleDirection = -1  -- -1 for going down (negative), 1 for going up (positive)

-- ========== Debug Utilities ==========
local function debugPrint(msg)
    if DEBUG then
        print("[DEBUG] " .. msg)
    end
end

-- ========== Network Setup ==========
local function openAllModems()
    local ok, cfg = pcall(require, "modules.config")
    if ok and type(cfg) == "table" and type(cfg.openAllModems) == "function" then
        local opened = cfg.openAllModems()
        if opened then return true end
        -- fall through to local scan if not opened
    end
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

-- (Monitor drawing helpers moved into modules.scanner_render)

-- ========== Data Processing (from geo_sonar.lua) ==========
-- Compute and cache side-pane aggregates (legend ore counts, POIs, hazards)
local function recomputeSidePaneCache()
    local params = {
        currentData = currentData,
        currentView = currentView,
        sliceThick = sliceThick,
        cycleMinOffset = cycleMinOffset,
        cycleMaxOffset = cycleMaxOffset,
        VIEW_DEF = ScannerUtils.VIEW_DEF,
        classifyColorFn = function(name, tags)
            return ScannerUtils.classifyColor(name, tags, ScannerCfg, POINT_COLOR)
        end,
        oreLabelFromNameFn = ScannerUtils.oreLabelFromName,
        centerFromBlocksFn = ScannerUtils.centerFromBlocks,
        axisValFn = ScannerUtils.axisVal,
        ORE_COLOR = ORE_COLOR,
        matchRuleFn = ScannerUtils.matchRule,
        poiRules = ScannerCfg.poiRules,
        hazardRules = ScannerCfg.hazardRules,
    }
    sidePaneCache = ScannerCache.recompute(params)
end

-- In-game time helpers
local function formatGameAge(lastTicks)
    return ScannerUtils.formatGameAge(lastTicks)
end

-- ========== Display Rendering ==========
local function renderMapArea()
    local p = {
        currentData = currentData,
        currentView = currentView,
        sliceThick = sliceThick,
        sliceOffset = sliceOffset,
        currentRadius = currentRadius,
        FRAME_COLOR = FRAME_COLOR,
        BG_COLOR = BG_COLOR,
        MARK_FG = MARK_FG,
        MARK_BG = MARK_BG,
        MARK_CHAR = MARK_CHAR,
        SHOW_ORE_LABELS = SHOW_ORE_LABELS,
        buildMapFn = function(data, view, thick, offset)
            local pts, _ = ScannerUtils.buildMap(data, view, thick, offset, ScannerCfg, SHOW_ORE_LABELS, {
                ORE_COLOR = ORE_COLOR,
                FLUID_COLOR = FLUID_COLOR,
                WOOD_COLOR = WOOD_COLOR,
                POINT_COLOR = POINT_COLOR,
            })
            return pts
        end,
        uvToPixelFn = ScannerUtils.uvToPixel,
    }
    ScannerRender.renderMapArea(monitor, p)
end

local function renderSidePane()
    local p = {
        currentData = currentData,
        currentView = currentView,
        BG_COLOR = BG_COLOR,
        HEADER_BG = HEADER_BG,
        HEADER_FG = HEADER_FG,
        STATUS_COLOR = STATUS_COLOR,
        ERROR_COLOR = ERROR_COLOR,
        VIEW_DEF = ScannerUtils.VIEW_DEF,
        formatGameAgeFn = formatGameAge,
        lastScanGameTicks = lastScanGameTicks,
        lastError = lastError,
        scanInProgress = scanInProgress,
        relayOnline = relayOnline,
        waitingCooldown = waitingCooldown,
        pendingScanEta = pendingScanEta,
        relayCooldownMs = relayCooldownMs,
    }
    ScannerRender.renderSidePane(monitor, p, sidePaneCache or {legendCounts={}, poiFound={}, hazardFound={}}, ScannerCfg)
end

-- Lightweight refresh: only update hazard blinking lines using cache
local function renderHazardBlinkUpdate()
    local p = {
        BG_COLOR = BG_COLOR,
        STATUS_COLOR = STATUS_COLOR,
    }
    ScannerRender.renderHazardBlinkUpdate(monitor, p, sidePaneCache or {hazardFound={}}, ScannerCfg)
end

local function renderScanData()
    if not monitor or not currentData then return end
    -- Only clear and redraw both panes when explicitly asked
    renderMapArea()
    renderSidePane()
end

local function renderNoData()
    if not monitor then return end
    ScannerRender.renderNoData(monitor, {
        BG_COLOR = BG_COLOR,
        STATUS_COLOR = STATUS_COLOR,
        ERROR_COLOR = ERROR_COLOR,
        relayOnline = relayOnline,
        scanInProgress = scanInProgress,
        scanRequestTime = scanRequestTime,
        lastError = lastError,
        lastStatusResponseTime = lastStatusResponseTime,
    })
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
    scanRequestTime = os.epoch("utc")
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

local function requestOrientationData()
    debugPrint("Requesting orientation data")
    rednet.broadcast({
        cmd = "queryFacing",
        secret = SECRET
    }, PROTOCOL)
    rednet.broadcast({
        cmd = "queryOrientation",
        secret = SECRET
    }, PROTOCOL)
end

local function handleScanResponse(msg)
    scanInProgress = false
    
    if msg.success and msg.data then
        currentData = msg.data
        currentRadius = msg.radius or currentRadius
        lastScanTime = msg.timestamp or os.epoch("utc")
        lastScanGameTicks = ScannerUtils.getGameTicks()
        lastError = nil
        print(string.format("Received scan data: %d blocks", #msg.data))
        recomputeSidePaneCache()
        renderScanData()
    else
        lastError = msg.error or "Unknown scan error"
        print("Scan failed: " .. lastError)
        renderNoData()
    end
end

local function handleStatusResponse(msg)
    relayOnline = msg.scannerAvailable
    lastStatusResponseTime = os.epoch("utc")
    if msg.cooldown ~= nil then
        relayCooldownMs = tonumber(msg.cooldown) or 0
    end
    if not relayOnline and msg.scannerAvailable == false then
        lastError = "Scanner not available"
    else
        lastError = nil
        -- If relay is online and we don't have data yet, request initial scan
        if not currentData and not scanInProgress then
            requestScan()
        end
    end
    debugPrint("Relay status: " .. (relayOnline and "online" or "offline"))
    
    if not currentData then
        renderNoData()
    end
end

-- ========== Direction-Aware Display Functions ==========
local function updateDisplaySettings()
    local settings = ScannerOrientation.computeSettings(currentCardinal, currentVertical, DIRECTION_SETTINGS)
    if settings.direction ~= currentDirection or settings.view ~= currentView
        or settings.cycleMinOffset ~= cycleMinOffset or settings.cycleMaxOffset ~= cycleMaxOffset then
        currentDirection = settings.direction
        currentView = settings.view
        cycleMinOffset = settings.cycleMinOffset
        cycleMaxOffset = settings.cycleMaxOffset
        cycleDirection = settings.cycleDirection
        sliceOffset = settings.initSliceOffset

        debugPrint(string.format("Direction changed to %s: view=%s, range=%d to %d, direction=%d",
            currentDirection, currentView, cycleMinOffset, cycleMaxOffset, cycleDirection))

        if currentData then
            recomputeSidePaneCache()
            renderScanData()
        end
    end
end

local function handleOrientationResponse(msg)
    local updated = false
    
    if msg.type == "facing" and msg.name == CARDINAL_READER_NAME and msg.facing then
        if currentCardinal ~= msg.facing then
            currentCardinal = msg.facing
            updated = true
            debugPrint("Cardinal direction updated: " .. currentCardinal)
        end
    elseif msg.type == "orientation" and msg.name == VERT_READER_NAME and msg.orientation then
        if currentVertical ~= msg.orientation then
            currentVertical = msg.orientation
            updated = true
            debugPrint("Vertical direction updated: " .. currentVertical)
        end
    end
    
    if updated then
        updateDisplaySettings()
    end
end

-- ========== Auto-Cycling Functions ==========
local function cycleSlice()
    if not autoCycleEnabled or not currentData then
        return
    end

    sliceOffset = ScannerOrientation.nextSliceOffset({
        direction = currentDirection,
        cycleMinOffset = cycleMinOffset,
        cycleMaxOffset = cycleMaxOffset,
        cycleDirection = cycleDirection,
    }, sliceOffset)

    -- Only update the map area to avoid side-pane flicker
    renderMapArea()
end

-- ========== Input Handling ==========
-- Manual key controls removed: display operates automatically

-- ========== Main Event Loop ==========
local function main()
    print("ODMK3 Scanner Display starting...")
    
    -- Initialize networking
    if not openAllModems() then
        error("No wireless modem found!")
    end
    
    -- Initialize monitor
    setupMonitor()
    
    print("Scanner Display online (Direction-aware mode)")
    print("Protocol: " .. PROTOCOL)
    print("Relay: " .. RELAY_NAME)
    
    -- Initial display
    renderNoData()
    
    -- Request initial status and orientation
    requestRelayStatus()
    requestOrientationData()
    
    -- Initialize display settings
    updateDisplaySettings()
    
    -- Auto-scan timer
    local autoScanTimer = nil
    if AUTO_SCAN_INTERVAL > 0 then
        autoScanTimer = os.startTimer(AUTO_SCAN_INTERVAL)
    end
    
    -- Auto-cycle timer
    local autoCycleTimer = nil
    if AUTO_CYCLE_INTERVAL > 0 then
        autoCycleTimer = os.startTimer(AUTO_CYCLE_INTERVAL)
    end
    -- Hazards blink timer (independent of slice cycling)
    local hazardBlinkTimer = os.startTimer(HAZARD_BLINK_INTERVAL)
    -- Age refresh timer (lightweight age line update)
    local ageRefreshTimer = os.startTimer(AGE_REFRESH_INTERVAL)
    
    -- Orientation update timer (check every 5 seconds)
    local orientationTimer = os.startTimer(5)
    -- Relay status poll timer
    local statusPollTimer = os.startTimer(10)
    -- Scan watchdog timer
    local scanWatchdogTimer = os.startTimer(6)
    
    -- Main event loop function
    local function runEventLoop()
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
                    elseif message.type == "facing" or message.type == "orientation" then
                        handleOrientationResponse(message)
                    end
                end
            end
        elseif event == "scanner_message" then
            -- Messages funneled via modules.scanner_network
            local sender, message = p1, p2
            if type(message) == "table" then
                if SECRET == "" or message.secret == SECRET then
                    if message.type == "scanResponse" and message.name == RELAY_NAME then
                        handleScanResponse(message)
                    elseif message.type == "statusResponse" and message.name == RELAY_NAME then
                        handleStatusResponse(message)
                    elseif message.type == "facing" or message.type == "orientation" then
                        handleOrientationResponse(message)
                    end
                end
            end
        elseif event == "timer" and p1 == autoScanTimer then
            -- Auto-scan
            if AUTO_SCAN_INTERVAL > 0 and relayOnline and not scanInProgress then
                requestScan()
            end
            autoScanTimer = os.startTimer(AUTO_SCAN_INTERVAL)
        elseif event == "timer" and p1 == pendingScanTimer then
            pendingScanTimer = nil
            waitingCooldown = false
            requestScan()
            
        elseif event == "timer" and p1 == autoCycleTimer then
            -- Auto-cycle slices
            if AUTO_CYCLE_INTERVAL > 0 then
                cycleSlice()
            end
            autoCycleTimer = os.startTimer(AUTO_CYCLE_INTERVAL)
            
        elseif event == "timer" and p1 == orientationTimer then
            -- Request orientation update
            requestOrientationData()
            orientationTimer = os.startTimer(5)
        elseif event == "timer" and p1 == hazardBlinkTimer then
            -- Update only blinking hazard lines; avoid heavy recompute and pane clears
            renderHazardBlinkUpdate()
            hazardBlinkTimer = os.startTimer(HAZARD_BLINK_INTERVAL)
        elseif event == "timer" and p1 == ageRefreshTimer then
            -- Update only the age text line in the side pane
            ScannerRender.renderStatusAgeUpdate(monitor, {
                BG_COLOR = BG_COLOR,
                STATUS_COLOR = STATUS_COLOR,
                formatGameAgeFn = formatGameAge,
                lastScanGameTicks = lastScanGameTicks,
            })
            ageRefreshTimer = os.startTimer(AGE_REFRESH_INTERVAL)
        elseif event == "timer" and p1 == statusPollTimer then
            -- Poll relay status periodically or if stale
            if (not relayOnline) or (not currentData) or ((os.epoch("utc") - lastStatusResponseTime) > 15000) then
                requestRelayStatus()
            end
            statusPollTimer = os.startTimer(10)
        elseif event == "timer" and p1 == scanWatchdogTimer then
            -- If scan appears hung (>10s) reset and retry
            if scanInProgress and (os.epoch("utc") - scanRequestTime) > 10000 then
                debugPrint("Scan watchdog: scan timeout, resetting state and re-requesting status")
                scanInProgress = false
                requestRelayStatus()
            elseif (not currentData) and ((os.epoch("utc") - lastStatusResponseTime) > 20000) then
                -- No data and stale status: force both
                requestRelayStatus()
                requestScan()
            end
            scanWatchdogTimer = os.startTimer(6)
            
        elseif event == "monitor_resize" then
            if currentData then
                -- Re-render both panes to fit new size; cached side data reused
                renderScanData()
            else
                renderNoData()
            end
        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Recover from monitor/modem reattachment during movement
            openAllModems()
            local newMon = findMonitor()
            if newMon and newMon ~= monitor then
                monitor = newMon
                setupMonitor()
                if currentData then
                    renderScanData()
                else
                    renderNoData()
                end
            end
        end
      end
    end

    -- Start reliable network listener in parallel
    local function runNetworkPump()
        local ok, ScannerNet = pcall(require, "modules.scanner_network")
        if ok and ScannerNet and type(ScannerNet.start) == "function" then
            ScannerNet.start(PROTOCOL, SECRET, "scanner_message", 0.5)
        else
            -- Fallback: do nothing; main loop will still handle rednet_message
            while true do os.sleep(10) end
        end
    end

    parallel.waitForAll(runNetworkPump, runEventLoop)
    
    print("Scanner Display shutting down")
end

-- ========== Startup ==========
main()
