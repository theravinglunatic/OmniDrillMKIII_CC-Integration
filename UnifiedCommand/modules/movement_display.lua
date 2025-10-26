-- modules/movement_display.lua
-- Movement controls rendering and input handling

local MovementDisplay = {}
local Config = require("modules.config")

-- Monitor reference (set by init)
local movementMonitor = nil

-- Hitboxes for movement grid
local movementButtons = {}

-- ========== Initialization ==========
function MovementDisplay.init(monitor)
    movementMonitor = monitor
    if movementMonitor then
        movementMonitor.setTextScale(0.9)
        movementMonitor.setBackgroundColor(Config.colors.bg)
        movementMonitor.clear()
    end
    return movementMonitor ~= nil
end

-- ========== Drawing Utilities ==========
local function fillRect(mon, x1, y1, x2, y2, bg)
    mon.setBackgroundColor(bg)
    for y = y1, y2 do
        mon.setCursorPos(x1, y)
        mon.write(string.rep(" ", math.max(0, x2 - x1 + 1)))
    end
end

local function writeCentered(mon, x1, y1, x2, y2, text, fg, bg)
    local w = x2 - x1 + 1
    local h = y2 - y1 + 1
    local cx = x1 + math.floor((w - #text) / 2)
    local cy = y1 + math.floor(h / 2)
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    mon.setCursorPos(cx, cy)
    mon.write(text)
end

-- ========== Drawing Functions ==========
function MovementDisplay.draw(systemState)
    if not movementMonitor then return end
    
    local mon = movementMonitor
    local w, h = mon.getSize()

    -- Clear entire monitor
    mon.setBackgroundColor(Config.colors.bg)
    mon.clear()

    -- Title bar across full width
    mon.setCursorPos(1, 1)
    mon.setBackgroundColor(Config.colors.title)
    mon.setTextColor(Config.colors.bg)
    local titleText = "MOVEMENT"
    local titlePadding = math.floor((w - #titleText) / 2)
    mon.write(string.rep(" ", w))
    mon.setCursorPos(1 + titlePadding, 1)
    mon.write(titleText)

    -- Build large 3x3 grid
    movementButtons = {}
    local cols, rows = 3, 3
    local gap = 1
    local areaX1, areaX2 = 1, w
    local areaY1, areaY2 = 3, h - 2
    local areaW = areaX2 - areaX1 + 1
    local areaH = areaY2 - areaY1 + 1
    local btnW = math.max(4, math.floor((areaW - gap * (cols + 1)) / cols))
    local btnH = math.max(3, math.floor((areaH - gap * (rows + 1)) / rows))
    local startX = areaX1 + gap
    local startY = areaY1 + math.floor((areaH - (rows * btnH + (rows - 1) * gap)) / 2)

    local function addBtn(id, col, row, label, color)
        local x1 = startX + (col - 1) * (btnW + gap)
        local y1 = startY + (row - 1) * (btnH + gap)
        local x2 = x1 + btnW - 1
        local y2 = y1 + btnH - 1
        table.insert(movementButtons, { id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
        fillRect(mon, x1, y1, x2, y2, color)
        writeCentered(mon, x1, y1, x2, y2, label, Config.colors.bg, color)
    end

    -- Layout similar to legacy OnboardCommand
    addBtn("U", 1, 1, "UP", Config.colors.warning)
    addBtn("N", 2, 1, "NORTH", Config.colors.good)
    addBtn("M", 3, 1, "MOVE", Config.colors.accent)
    addBtn("W", 1, 2, "WEST", Config.colors.good)
    addBtn("F", 2, 2, "FRONT", Config.colors.btnBg)
    addBtn("E", 3, 2, "EAST", Config.colors.good)
    addBtn("D", 1, 3, "DOWN", Config.colors.warning)
    addBtn("S", 2, 3, "SOUTH", Config.colors.good)
    addBtn("A", 3, 3, "AUTO", systemState.autoDriveEnabled and Config.colors.danger or Config.colors.alt)

    -- Status line
    mon.setCursorPos(1, h)
    mon.setBackgroundColor(Config.colors.bg)
    mon.setTextColor(Config.colors.text)
    local status = systemState.pendingTarget
    if not status then
        local cardinalNames = {N="NORTH", E="EAST", S="SOUTH", W="WEST"}
        local verticalNames = {F="FRONT", U="UP", D="DOWN"}
        local cardinalFull = cardinalNames[systemState.currentCardinal] or systemState.currentCardinal
        local verticalFull = verticalNames[systemState.currentVertical] or systemState.currentVertical
        status = "Facing: " .. cardinalFull .. "/" .. verticalFull
    end
    mon.write(status:sub(1, w))
end

-- ========== Input Handling ==========
function MovementDisplay.handleTouch(systemState, x, y)
    if not movementMonitor then return false end
    
    -- Find which button was touched
    for _, b in ipairs(movementButtons) do
        if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            local id = b.id
            local command = nil
            
            if id == "M" then
                command = { name = "odmk3-drive-controller", cmd = "move", secret = Config.SECRET }
                systemState.pendingTarget = "MOVE"
            elseif id == "A" then
                command = { name = "odmk3-auto-drive", cmd = "toggle", secret = Config.SECRET }
                systemState.pendingTarget = "AUTO"
            elseif id == "U" or id == "D" or id == "F" then
                -- Vertical rotator expects setFacing with target=F/U/D
                command = { name = "odmk3-vert-rotater", cmd = "setFacing", target = id, secret = Config.SECRET }
                systemState.pendingTarget = id
            else
                -- Cardinal rotator expects setFacing with target=N/E/S/W
                command = { name = "odmk3-cardinal-rotater", cmd = "setFacing", target = id, secret = Config.SECRET }
                systemState.pendingTarget = id
            end
            
            return true, command  -- Return true and network command
        end
    end
    
    return false
end

-- ========== Utilities ==========
function MovementDisplay.isMovementArea(x)
    -- With full monitor, all touches are movement area
    return true
end

return MovementDisplay
