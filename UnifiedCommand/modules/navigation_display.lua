-- modules/navigation_display.lua
-- Navigation scanner pixel map rendering with auto-cycling

local NavigationDisplay = {}
local Config = require("modules.config")

-- Monitor reference (set by init)
local navigationMonitor = nil

-- Cycling state variables (matching legacy ODMK3-ScannerDisplay.lua pattern)
local currentDirection = "N"  -- Active direction for display settings
local cycleMinOffset = -12
local cycleMaxOffset = -2
local cycleDirection = -1  -- -1 for descending (negative), 1 for ascending (positive)

-- Direction-based display settings (from ODMK3-ScannerDisplay.lua)
local DIRECTION_SETTINGS = {
    -- Negative range directions use -2 .. -12
    N = {view = "front", minOffset = -12, maxOffset = -2},  -- North: FRONT (XY), -2 to -12
    W = {view = "side",  minOffset = -12, maxOffset = -2},  -- West: SIDE (ZY), descends -2 -> -12
    F = {view = "front", minOffset = -12, maxOffset = -2},  -- Front (default)
    D = {view = "top",   minOffset = -12, maxOffset = -2},  -- Down: TOP (XZ)
    -- Positive range directions use 2 .. 12
    E = {view = "side",  minOffset = 2,  maxOffset = 12},   -- East: SIDE (ZY)
    S = {view = "front", minOffset = 2,  maxOffset = 12},   -- South: FRONT (XY)
    U = {view = "top",   minOffset = 2,  maxOffset = 12},   -- Up: TOP (XZ)
}

-- ========== Initialization ==========
function NavigationDisplay.init(monitor)
    navigationMonitor = monitor
    return navigationMonitor ~= nil
end

-- ========== Scanner Rendering Utilities ==========
local function classifyColor(name, tags)
    if name:find("lava") or name:find("water") or (tags and tags["minecraft:fluid"]) then
        return Config.CC.lightBlue
    elseif name:find("ore") or (name:find(":deepslate_") and name:find("ore")) then
        return Config.CC.orange
    elseif name:find("log") or name:find("wood") then
        return Config.CC.brown
    else
        return Config.CC.gray
    end
end

local VIEW_DEF = {
    top   = {U="x", V="z", W="y"},
    front = {U="x", V="y", W="z"},
    side  = {U="z", V="y", W="x"},
}

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
    return { x = math.floor((min.x + max.x) / 2 + 0.5), y = math.floor((min.y + max.y) / 2 + 0.5), z = math.floor((min.z + max.z) / 2 + 0.5) }
end

local function buildMap(blocks, viewKey, sliceThick, sliceOffset)
    local vd = VIEW_DEF[viewKey] or VIEW_DEF.top
    local C = centerFromBlocks(blocks)
    local half = math.floor((sliceThick - 1) / 2)
    local wMin = C[vd.W] + sliceOffset - half
    local wMax = C[vd.W] + sliceOffset + (sliceThick - 1 - half)
    local pts = {}
    local prio = {[Config.CC.orange]=3, [Config.CC.lightBlue]=2, [Config.CC.brown]=1, [Config.CC.gray]=0}
    for _, b in ipairs(blocks) do
        local wv = b[vd.W]
        if wv >= wMin and wv <= wMax then
            local du = b[vd.U] - C[vd.U]
            local dv = b[vd.V] - C[vd.V]
            local key = du .. "," .. dv
            local col = classifyColor(b.name or "", b.tags or {})
            if not pts[key] or prio[col] > prio[pts[key]] then
                pts[key] = col
            end
        end
    end
    return pts, C
end

-- ========== Slice Cycling Functions ==========
-- Cycle to next slice based on current direction (matches legacy scanner exactly)
function NavigationDisplay.cycleSlice(systemState)
    if not systemState.scanData then
        return systemState.sliceOffset  -- No data, don't cycle
    end

    -- Use the persistent module-level cycling state
    if currentDirection == "W" or currentDirection == "D" then
        -- Descend from -2 to -12
        systemState.sliceOffset = systemState.sliceOffset + cycleDirection  -- cycleDirection is -1
        if systemState.sliceOffset < cycleMinOffset then
            -- cycleMinOffset is -12, wrap to -2 (cycleMaxOffset)
            systemState.sliceOffset = cycleMaxOffset
        end
    else
        -- Default ascending behavior
        systemState.sliceOffset = systemState.sliceOffset + cycleDirection  -- cycleDirection is 1
        local actualMin = math.min(cycleMinOffset, cycleMaxOffset)
        local actualMax = math.max(cycleMinOffset, cycleMaxOffset)
        if systemState.sliceOffset > actualMax then
            systemState.sliceOffset = actualMin
        elseif systemState.sliceOffset < actualMin then
            systemState.sliceOffset = actualMax
        end
    end

    return systemState.sliceOffset
end

-- Update display settings based on current direction (matches legacy scanner exactly)
function NavigationDisplay.updateDisplaySettings(systemState)
    -- Determine active direction (vertical takes precedence for U/D)
    local newDirection = currentDirection
    if systemState.currentVertical == "U" or systemState.currentVertical == "D" then
        newDirection = systemState.currentVertical
    else
        newDirection = systemState.currentCardinal
    end
    
    -- Only update if direction actually changed
    if newDirection ~= currentDirection then
        currentDirection = newDirection
        local settings = DIRECTION_SETTINGS[currentDirection]
        if settings then
            systemState.currentView = settings.view
            cycleMinOffset = settings.minOffset
            cycleMaxOffset = settings.maxOffset

            -- Determine cycle direction and starting point
            -- West and Down need a descending cycle: -2 -> -12
            local actualMin = math.min(cycleMinOffset, cycleMaxOffset)
            local actualMax = math.max(cycleMinOffset, cycleMaxOffset)

            if currentDirection == "W" or currentDirection == "D" then
                cycleDirection = -1                      -- descending
                systemState.sliceOffset = cycleMaxOffset  -- start at -2 then descend
            else
                cycleDirection = 1                       -- ascending
                systemState.sliceOffset = actualMin      -- default ascending behavior
            end
        end
    end
    
    return systemState
end

-- ========== Drawing Functions ==========
function NavigationDisplay.draw(systemState)
    if not navigationMonitor then return end
    
    local mon = navigationMonitor
    local w, h = mon.getSize()
    local navStartX = math.floor(w/2) + 1
    
    -- Clear right side (navigation area)
    for y = 1, h do
        mon.setCursorPos(navStartX, y)
        mon.setBackgroundColor(Config.colors.bg)
        for x = navStartX, w do
            mon.write(" ")
        end
    end
    
    -- Title
    mon.setCursorPos(navStartX, 1)
    mon.setBackgroundColor(Config.colors.title)
    mon.setTextColor(Config.colors.bg)
    local navWidth = w - navStartX + 1
    local titleText = "NAVIGATION"
    local titlePadding = math.floor((navWidth - #titleText) / 2)
    mon.write(string.rep(" ", navWidth))  -- Fill entire width
    mon.setCursorPos(navStartX + titlePadding, 1)
    mon.write(titleText)

    -- If we have scan data, render a compact pixel map in the right half
    if systemState.scanData then
        -- Canvas bounds for the right half, expanded to use full available space
        local gx1 = navStartX
        local gy1 = 2  -- Start right after title (removed scanner status line)
        local gx2 = w
        local gy2 = h - 1  -- Expanded by two lines total (removed direction and scanner status)
        local gw, gh = gx2 - gx1 + 1, gy2 - gy1 + 1

        -- Build the slice map
        local pts = buildMap(systemState.scanData, systemState.currentView, systemState.sliceThick, systemState.sliceOffset)
        pts = pts or {}

        -- Render pixels
        local radius = systemState.scanRadius
        for py = gy1, gy2 do
            for px = gx1, gx2 do
                local nx = (px - gx1) / math.max(gw - 1, 1) * 2 - 1
                local ny = (py - gy1) / math.max(gh - 1, 1) * 2 - 1
                local du = math.floor(nx * radius + 0.5)
                local dv = math.floor(-ny * radius + 0.5)  -- flip Y
                local key = du .. "," .. dv
                local c = pts[key]
                if c then
                    mon.setBackgroundColor(c)
                    mon.setCursorPos(px, py)
                    mon.write(" ")
                end
            end
        end

        -- Simple status at bottom of right half
        mon.setBackgroundColor(Config.colors.bg)
        mon.setTextColor(Config.colors.text)
        mon.setCursorPos(navStartX, h)
        local info = string.format("Blocks:%d View:%s Offset:%d", #systemState.scanData, systemState.currentView:upper(), systemState.sliceOffset)
        mon.write(info:sub(1, w - navStartX + 1))
    else
        mon.setCursorPos(navStartX, 4)
        mon.setTextColor(Config.colors.warning)
        mon.write("No scan data")
    end
end

return NavigationDisplay
