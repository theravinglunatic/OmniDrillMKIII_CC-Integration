-- ODMK3-OnboardCommand.lua
-- Omni-Drill MKIII: Onboard Command Center for 3x3 Monitor
-- Provides same functionality as the wireless pocket GUI but optimized for monitor display

-- ========== config ==========
local TITLE      = "OMNI-DRILL MKIII COMMAND CENTER"
local BTN_FG     = colors.white
local BTN_BG     = colors.blue
local BTN_BG_ALT = colors.brown      -- for vertical (Up/Down) buttons
local BTN_BG_HI  = colors.cyan
local BG         = colors.black
local TITLE_FG   = colors.yellow
local TITLE_BG   = colors.gray
local STATUS_FG  = colors.lightGray
local STATUS_BG  = colors.gray

-- networking config
local PROTOCOL      = "Omni-DrillMKIII"
local ROTATER_NAME  = "odmk3-cardinal-rotater"  -- target listener name
local SECRET        = ""  -- optional shared secret
local NET_OK        = false
local pendingTarget = nil      -- direction (N/E/S/W) awaiting ack
local lastStatusMsg = nil      -- last status / ack text
local lastFacing    = nil      -- last known facing from reader/rotater
local lastNetError  = nil
local autoDriveEnabled = false -- Track auto-drive state

-- Collection state (will be loaded from file and synced with controllers)
local collectNatBlocksEnabled = nil -- Track natural blocks collection state
local collectBuildBlocksEnabled = nil -- Track build blocks collection state  
local collectRawOreEnabled = nil -- Track raw ore collection state

-- State persistence
local STATE_FILE = "onboard_state"

-- Monitor configuration
local monitor = nil
local MONITOR_WIDTH = 25   -- 3x3 monitor blocks = 25 characters wide
local MONITOR_HEIGHT = 15  -- 3x3 monitor blocks = 15 characters tall
local monitorHealthTimer = nil

-- Page management
local currentPage = 1  -- 1 = Movement, 2 = Collection Controls
local totalPages = 2

-- ========== monitor utils ==========
local function findMonitor()
    monitor = peripheral.find("monitor")
    if monitor then
        MONITOR_WIDTH, MONITOR_HEIGHT = monitor.getSize()
        return true
    end
    return false
end

-- ========== state persistence ==========
local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        if file then
            local data = file.readAll()
            file.close()
            
            if data and data ~= "" then
                local success, state = pcall(textutils.unserialise, data)
                if success and state then
                    collectNatBlocksEnabled = state.collectNatBlocksEnabled
                    collectBuildBlocksEnabled = state.collectBuildBlocksEnabled
                    collectRawOreEnabled = state.collectRawOreEnabled
                    autoDriveEnabled = state.autoDriveEnabled or false
                    print("[STATE] Loaded state from file")
                    return true
                end
            end
        end
    end
    
    -- Default states if no file exists
    collectNatBlocksEnabled = true
    collectBuildBlocksEnabled = true
    collectRawOreEnabled = true
    autoDriveEnabled = false
    print("[STATE] Using default state")
    return false
end

local function saveState()
    local state = {
        collectNatBlocksEnabled = collectNatBlocksEnabled,
        collectBuildBlocksEnabled = collectBuildBlocksEnabled,
        collectRawOreEnabled = collectRawOreEnabled,
        autoDriveEnabled = autoDriveEnabled
    }
    
    local file = fs.open(STATE_FILE, "w")
    if file then
        file.write(textutils.serialise(state))
        file.close()
        print("[STATE] Saved state to file")
        return true
    end
    return false
end

local function queryCollectionStates()
    if not NET_OK then return end
    
    print("[STATE] Querying collection controllers for current states...")
    
    -- Query all collection controllers for their current states
    rednet.broadcast({
        name = "odmk3-collect-nat-blocks",
        cmd = "status",
        secret = ""
    }, PROTOCOL)
    
    rednet.broadcast({
        name = "odmk3-collect-build-blocks", 
        cmd = "status",
        secret = ""
    }, PROTOCOL)
    
    rednet.broadcast({
        name = "odmk3-collect-raw-ore",
        cmd = "status", 
        secret = ""
    }, PROTOCOL)
end

local function recalibrateMonitor()
    if not monitor then return false end
    
    -- Reset text scale and recalibrate size
    monitor.setTextScale(0.9)
    local newWidth, newHeight = monitor.getSize()
    
    -- Force a full refresh if size changed significantly
    if math.abs(newWidth - MONITOR_WIDTH) > 2 or math.abs(newHeight - MONITOR_HEIGHT) > 2 then
        MONITOR_WIDTH, MONITOR_HEIGHT = newWidth, newHeight
        monitor.clear()
        return true -- Signal that a full redraw is needed
    end
    
    MONITOR_WIDTH, MONITOR_HEIGHT = newWidth, newHeight
    return false
end

local function centerText(y, text, fg, bg)
    if not monitor then return end
    local x = math.floor((MONITOR_WIDTH - #text) / 2) + 1
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.setCursorPos(x, y)
    for i = 1, MONITOR_WIDTH do
        monitor.write(" ")
    end
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local function fillRect(x1, y1, x2, y2, bg)
    if not monitor then return end
    monitor.setBackgroundColor(bg or colors.black)
    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        monitor.write(string.rep(" ", x2 - x1 + 1))
    end
end

-- ========== button model ==========
local buttons = {}  -- each: {id, label, x1,y1,x2,y2, bg, fg, hot}
local function addButton(id, label, x1, y1, x2, y2)
    table.insert(buttons, { id=id, label=label, x1=x1, y1=y1, x2=x2, y2=y2, bg=BTN_BG, fg=BTN_FG, hot=false })
end

local function pointIn(b, x, y)
    return x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2
end

local lastPressed -- id of last pressed button for highlight

local function drawButton(b)
    if not monitor then return end
    local bg = b.hot and BTN_BG_HI or b.bg
    if lastPressed == b.id then
        -- Intensify background for last pressed
        if bg == BTN_BG then
            bg = colors.lime
        elseif bg == BTN_BG_ALT then
            bg = colors.green
        else
            bg = colors.lime
        end
    end
    fillRect(b.x1, b.y1, b.x2, b.y2, bg)
    local w = b.x2 - b.x1 + 1
    -- Support multiline labels (split by \n) and center vertically/horizontally.
    local lines = {}
    for part in string.gmatch(b.label, "[^\n]+") do table.insert(lines, part) end
    local total = #lines
    local boxH = b.y2 - b.y1 + 1
    local firstY = b.y1 + math.floor((boxH - total) / 2)
    monitor.setTextColor(b.fg)
    for i, line in ipairs(lines) do
        monitor.setBackgroundColor(bg)
        local lineLen = #line
        local x = b.x1 + math.floor((w - lineLen) / 2)
        monitor.setCursorPos(x, firstY + i - 1)
        monitor.write(line)
    end
end

-- label map - longer labels for larger monitor
local FULL = {
    N="NORTH", E="EAST", S="SOUTH", W="WEST", U="UP", D="DOWN", F="FORWARD",
    M="MOVE", A="AUTO-DRIVE" -- action buttons
}

-- ========== layout functions ==========
local function drawPageHeader()
    if not monitor then return end
    local bottomStatus = MONITOR_HEIGHT
    monitor.setBackgroundColor(BG)
    monitor.clear()
    
    -- Draw title bar (2 lines)
    fillRect(1, 1, MONITOR_WIDTH, 3, TITLE_BG)
    centerText(1, TITLE, TITLE_FG, TITLE_BG)
    
    -- Draw page indicator
    local pageText = currentPage == 1 and "MOVEMENT CONTROLS" or "COLLECTION CONTROLS"
    centerText(2, pageText, TITLE_FG, TITLE_BG)
    
    -- Network status
    local netStatus = NET_OK and "NETWORK: ONLINE" or "NETWORK: OFFLINE"
    centerText(3, netStatus, NET_OK and colors.lime or colors.red, TITLE_BG)
    
    -- Status line at bottom
    monitor.setCursorPos(1, bottomStatus)
    monitor.setBackgroundColor(STATUS_BG)
    monitor.setTextColor(STATUS_FG)
    for i = 1, MONITOR_WIDTH do
        monitor.write(" ")
    end
    monitor.setCursorPos(1, bottomStatus)
    monitor.write("Touch screen to control")
    
    return 4, bottomStatus - 1  -- return top, bottom for content area
end

local function addButtonWithColor(id, label, x1, y1, x2, y2, customColor)
    addButton(id, label, x1, y1, x2, y2)
    if customColor then
        buttons[#buttons].bg = customColor
    end
end

-- Enhanced movement page layout for 3x3 monitor
local function layoutMovementPage(top, bottom)
    local contentHeight = bottom - top
    local contentWidth = MONITOR_WIDTH - 4  -- 2 char margins on each side
    
    -- 3x3 grid layout matching pocket computer
    local cols, rows = 3, 3
    local gapX, gapY = 2, 2
    local btnW = math.floor((contentWidth - (cols - 1) * gapX) / cols)
    local btnH = math.floor((contentHeight - (rows - 1) * gapY) / rows)
    
    local startY = top + math.floor((contentHeight - (rows * btnH + (rows - 1) * gapY)) / 2)
    local startX = 3  -- 2 char left margin + 1
    
    local function addBtn(id, col, row, color)
        local x1 = startX + (col - 1) * (btnW + gapX)
        local y1 = startY + (row - 1) * (btnH + gapY)
        local label = FULL[id] or id
        addButtonWithColor(id, label, x1, y1, x1 + btnW - 1, y1 + btnH - 1, color)
    end
    
    -- 3x3 layout matching pocket computer exactly
    addBtn("U", 1, 1, BTN_BG_ALT)     -- Up
    addBtn("N", 2, 1, colors.green)   -- North  
    addBtn("M", 3, 1, colors.purple)  -- Move
    addBtn("W", 1, 2, colors.green)   -- West
    addBtn("F", 2, 2, BTN_BG)         -- Forward (center)
    addBtn("E", 3, 2, colors.green)   -- East
    addBtn("D", 1, 3, BTN_BG_ALT)     -- Down
    addBtn("S", 2, 3, colors.green)   -- South
    addBtn("A", 3, 3, autoDriveEnabled and colors.red or colors.purple)  -- Auto-Drive (color based on state)
    
    -- Page navigation button
    local navY = startY + rows * btnH + (rows - 1) * gapY + 2
    local navW = 10
    local navX = math.floor((MONITOR_WIDTH - navW) / 2) + 1
    addButtonWithColor("PAGE", "COLLECTION", navX, navY, navX + navW - 1, navY + 2, colors.gray)
end

-- Collection controls page layout for 3x3 monitor
local function layoutCollectionPage(top, bottom)
    local contentHeight = bottom - top
    local contentWidth = MONITOR_WIDTH - 4  -- 2 char margins on each side
    
    -- List-style layout for collection controls
    local itemHeight = 4
    local gap = 2
    local totalItems = 3
    local listHeight = totalItems * itemHeight + (totalItems - 1) * gap
    local startY = top + math.floor((contentHeight - listHeight) / 2)
    local startX = 3  -- 2 char left margin + 1
    
    local function addListItem(id, text, itemIndex, enabled)
        local y1 = startY + (itemIndex - 1) * (itemHeight + gap)
        local y2 = y1 + itemHeight - 1
        
        -- Main text area (left side)
        local textX1 = startX
        local textX2 = MONITOR_WIDTH - 8  -- Leave space for status box
        addButtonWithColor(id, text, textX1, y1, textX2, y2, colors.gray)
        
        -- Status indicator box (right side)
        local boxX1 = MONITOR_WIDTH - 6
        local boxX2 = MONITOR_WIDTH - 2
        local boxColor = enabled and colors.lime or colors.red
        local boxLabel = enabled and "ON" or "OFF"
        addButtonWithColor(id .. "_STATUS", boxLabel, boxX1, y1, boxX2, y2, boxColor)
    end
    
    -- Collection control list items
    addListItem("NAT_BLOCKS", "Natural Blocks\nCollection", 1, collectNatBlocksEnabled or true)
    addListItem("BUILD_BLOCKS", "Build Blocks\nCollection", 2, collectBuildBlocksEnabled or true)
    addListItem("RAW_ORE", "Raw Ore\nCollection", 3, collectRawOreEnabled or true)
    
    -- Page navigation button
    local navY = startY + listHeight + 3
    local navW = 10
    local navX = math.floor((MONITOR_WIDTH - navW) / 2) + 1
    addButtonWithColor("PAGE", "MOVEMENT", navX, navY, navX + navW - 1, navY + 2, colors.gray)
end

-- Main layout function
local function layoutButtons()
    buttons = {}
    if not monitor then return end
    local top, bottom = drawPageHeader()
    
    if currentPage == 1 then
        layoutMovementPage(top, bottom)
    else
        layoutCollectionPage(top, bottom)
    end
end

local function updateStatusLine()
    if not monitor then return end
    local line
    if pendingTarget then
        line = "PROCESSING: " .. pendingTarget .. " - WAITING FOR RESPONSE..."
    elseif lastNetError then
        line = "NETWORK ERROR: " .. lastNetError
    elseif not NET_OK then
        line = "OFFLINE MODE - NO NETWORK CONNECTION"
    elseif lastStatusMsg then
        line = lastStatusMsg
    elseif lastFacing then
        line = "CURRENT FACING: " .. lastFacing .. " | READY FOR COMMANDS"
    else
        line = "READY - TOUCH SCREEN TO CONTROL SYSTEM"
    end
    
    monitor.setCursorPos(1, MONITOR_HEIGHT)
    monitor.setBackgroundColor(STATUS_BG)
    monitor.setTextColor(STATUS_FG)
    for i = 1, MONITOR_WIDTH do
        monitor.write(" ")
    end
    monitor.setCursorPos(1, MONITOR_HEIGHT)
    if #line > MONITOR_WIDTH then
        line = line:sub(1, MONITOR_WIDTH - 3) .. "..."
    end
    monitor.write(line)
end

local function redraw()
    if not monitor then return end
    layoutButtons()
    for _, b in ipairs(buttons) do 
        drawButton(b) 
    end
    updateStatusLine()
end

-- ========== networking ==========
local function openAllModems()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then 
                rednet.open(side) 
            end
            NET_OK = true
            return true
        end
    end
    NET_OK = false
    return false
end

local VERT_ROTATER_NAME = "odmk3-vert-rotater"  -- For vertical rotation

local function sendDirection(dir)
    if not NET_OK then return end
    
    if dir == "N" or dir == "E" or dir == "S" or dir == "W" then
        -- Cardinal directions
        pendingTarget = dir
        lastStatusMsg = nil
        rednet.broadcast({ name = ROTATER_NAME, cmd = "setFacing", target = dir, secret = "" }, PROTOCOL)
        updateStatusLine()
    elseif dir == "U" or dir == "D" or dir == "F" then
        -- Vertical directions
        pendingTarget = dir
        lastStatusMsg = nil
        rednet.broadcast({ name = VERT_ROTATER_NAME, cmd = "setFacing", target = dir, secret = "" }, PROTOCOL)
        updateStatusLine()
    end
end

local function press(id)
    lastPressed = id
    
    -- Page navigation
    if id == "PAGE" then
        currentPage = currentPage + 1
        if currentPage > totalPages then currentPage = 1 end
        redraw()
        return
    end
    
    -- Movement commands (Page 1)
    if id == "N" or id == "E" or id == "S" or id == "W" or id == "U" or id == "D" or id == "F" then
        sendDirection(id)
        
    elseif id == "M" then
        if NET_OK then
            pendingTarget = "MOVE"
            lastStatusMsg = nil
            rednet.broadcast({ name = "odmk3-drive-controller", cmd = "move", secret = "" }, PROTOCOL)
            lastStatusMsg = "MOVE COMMAND SENT"
        else
            lastStatusMsg = "CANNOT MOVE - OFFLINE"
        end
        updateStatusLine()
        
    elseif id == "A" then
        if NET_OK then
            local newState = not autoDriveEnabled
            autoDriveEnabled = newState
            pendingTarget = "AUTO-TOGGLE"
            lastStatusMsg = nil
            
            rednet.broadcast({ 
                name = "odmk3-auto-drive", 
                cmd = "toggle", 
                enabled = newState, 
                secret = "" 
            }, PROTOCOL)
            
            -- Update button appearance
            for _, b in ipairs(buttons) do
                if b.id == "A" then
                    b.bg = newState and colors.red or colors.purple
                    lastStatusMsg = "AUTO-DRIVE " .. (newState and "ENABLED" or "DISABLED")
                    break
                end
            end
        else
            lastStatusMsg = "CANNOT TOGGLE AUTO-DRIVE - OFFLINE"
        end
        redraw()
    
    -- Collection control commands (Page 2)
    elseif id == "NAT_BLOCKS" or id == "NAT_BLOCKS_STATUS" then
        if NET_OK then
            -- Fix: previously always evaluated to 'not true' (false). Now correctly invert.
            local newState = not collectNatBlocksEnabled
            collectNatBlocksEnabled = newState
            saveState()  -- Save state when making changes
            
            rednet.broadcast({
                name = "odmk3-collect-nat-blocks",
                cmd = "toggle",
                enabled = newState,
                secret = ""
            }, PROTOCOL)
            
            -- Update button appearance for status box
            for _, b in ipairs(buttons) do
                if b.id == "NAT_BLOCKS_STATUS" then
                    b.bg = newState and colors.lime or colors.red
                    b.label = newState and "ON" or "OFF"
                    break
                end
            end
            lastStatusMsg = "Natural Blocks Collection " .. (newState and "ENABLED" or "DISABLED")
        else
            lastStatusMsg = "CANNOT TOGGLE COLLECTION - OFFLINE"
        end
        redraw()
        
    elseif id == "BUILD_BLOCKS" or id == "BUILD_BLOCKS_STATUS" then
        if NET_OK then
            local newState = not collectBuildBlocksEnabled
            collectBuildBlocksEnabled = newState
            saveState()  -- Save state when making changes
            
            rednet.broadcast({
                name = "odmk3-collect-build-blocks",
                cmd = "toggle",
                enabled = newState,
                secret = ""
            }, PROTOCOL)
            
            -- Update button appearance for status box
            for _, b in ipairs(buttons) do
                if b.id == "BUILD_BLOCKS_STATUS" then
                    b.bg = newState and colors.lime or colors.red
                    b.label = newState and "ON" or "OFF"
                    break
                end
            end
            lastStatusMsg = "Build Blocks Collection " .. (newState and "ENABLED" or "DISABLED")
        else
            lastStatusMsg = "CANNOT TOGGLE COLLECTION - OFFLINE"
        end
        redraw()
    
    elseif id == "RAW_ORE" or id == "RAW_ORE_STATUS" then
        if NET_OK then
            local newState = not collectRawOreEnabled
            collectRawOreEnabled = newState
            saveState()  -- Save state when making changes
            
            rednet.broadcast({
                name = "odmk3-collect-raw-ore",
                cmd = "toggle",
                enabled = newState,
                secret = ""
            }, PROTOCOL)
            
            -- Update button appearance for status box
            for _, b in ipairs(buttons) do
                if b.id == "RAW_ORE_STATUS" then
                    b.bg = newState and colors.lime or colors.red
                    b.label = newState and "ON" or "OFF"
                    break
                end
            end
            lastStatusMsg = "Raw Ore Collection " .. (newState and "ENABLED" or "DISABLED")
        else
            lastStatusMsg = "CANNOT TOGGLE COLLECTION - OFFLINE"
        end
        redraw()
    
    else
        -- Unknown button
        lastStatusMsg = "BUTTON PRESSED: " .. (FULL[id] or id)
        updateStatusLine()
    end
    
    -- Redraw the pressed button
    for _, b in ipairs(buttons) do
        if b.id == id then
            drawButton(b)
            break
        end
    end
end

local function handleTouch(x, y)
    -- Check if touching title area (lines 1-3) for manual refresh
    if y >= 1 and y <= 3 then
        if recalibrateMonitor() then
            redraw()
        else
            -- Force a refresh even if size didn't change
            redraw()
        end
        lastStatusMsg = "DISPLAY REFRESHED"
        updateStatusLine()
        return
    end
    
    -- Handle button touches
    for _, b in ipairs(buttons) do
        if pointIn(b, x, y) then
            press(b.id)
            return
        end
    end
end

-- ========== message handlers ==========
local function handleRotateAck(msg)
    if type(msg) ~= "table" then return end
    if msg.type ~= "rotateAck" and msg.type ~= "moveAck" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    if msg.type == "rotateAck" then
        if pendingTarget and msg.targetDir and msg.targetDir ~= pendingTarget then return end
        pendingTarget = nil
        if msg.ok then
            lastFacing = msg.after or msg.targetDir or lastFacing
            lastStatusMsg = string.format("ROTATED %s→%s (%s)", 
                msg.before or '?', msg.after or msg.targetDir or '?', msg.action or 'OK')
        else
            lastStatusMsg = "ROTATION FAILED: " .. (msg.err or 'UNKNOWN ERROR')
        end
    elseif msg.type == "moveAck" then
        if pendingTarget ~= "MOVE" then return end
        pendingTarget = nil
        if msg.ok then
            lastStatusMsg = "MOVE COMMAND COMPLETED SUCCESSFULLY"
        else
            lastStatusMsg = "MOVE FAILED: " .. (msg.err or 'UNKNOWN ERROR')
        end
    end
    
    updateStatusLine()
end

local function handleAutoDriveStatus(msg)
    if type(msg) ~= "table" or msg.type ~= "autoStatus" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    if pendingTarget == "AUTO-TOGGLE" then
        pendingTarget = nil
    end
    
    -- Update our state tracking variable and save if changed
    if autoDriveEnabled ~= msg.enabled then
        autoDriveEnabled = msg.enabled
        saveState()
        print("[STATE] Updated auto-drive state and saved")
    end
    
    -- Update button state for Auto-Drive button
    for _, b in ipairs(buttons) do
        if b.id == "A" then
            if msg.enabled then
                b.bg = colors.red
                if msg.safe then
                    lastStatusMsg = "AUTO-DRIVE ENABLED (SAFE TO MOVE)"
                else
                    lastStatusMsg = "AUTO-DRIVE ENABLED (WAITING FOR SAFETY SIGNAL)"
                end
            else
                b.bg = colors.purple
                lastStatusMsg = "AUTO-DRIVE DISABLED"
            end
            drawButton(b)
            break
        end
    end
    
    updateStatusLine()
end

local function handleFacing(msg)
    if type(msg) ~= "table" then return end
    if msg.type ~= "facing" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    lastFacing = msg.facing or lastFacing
    if not pendingTarget then 
        lastStatusMsg = nil 
        updateStatusLine()
    end
end

local function handleCollectionStatus(msg)
    if type(msg) ~= "table" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    local stateChanged = false
    
    if msg.type == "natBlocksStatus" then
        if collectNatBlocksEnabled ~= msg.enabled then
            collectNatBlocksEnabled = msg.enabled
            stateChanged = true
        end
        -- Update status box button
        for _, b in ipairs(buttons) do
            if b.id == "NAT_BLOCKS_STATUS" then
                b.bg = msg.enabled and colors.lime or colors.red
                b.label = msg.enabled and "ON" or "OFF"
                drawButton(b)
                break
            end
        end
        lastStatusMsg = "Natural Blocks Collection: " .. (msg.enabled and "ON" or "OFF")
        
    elseif msg.type == "buildBlocksStatus" then
        if collectBuildBlocksEnabled ~= msg.enabled then
            collectBuildBlocksEnabled = msg.enabled
            stateChanged = true
        end
        -- Update status box button
        for _, b in ipairs(buttons) do
            if b.id == "BUILD_BLOCKS_STATUS" then
                b.bg = msg.enabled and colors.lime or colors.red
                b.label = msg.enabled and "ON" or "OFF"
                drawButton(b)
                break
            end
        end
        lastStatusMsg = "Build Blocks Collection: " .. (msg.enabled and "ON" or "OFF")
        
    elseif msg.type == "rawOreStatus" then
        if collectRawOreEnabled ~= msg.enabled then
            collectRawOreEnabled = msg.enabled
            stateChanged = true
        end
        -- Update status box button
        for _, b in ipairs(buttons) do
            if b.id == "RAW_ORE_STATUS" then
                b.bg = msg.enabled and colors.lime or colors.red
                b.label = msg.enabled and "ON" or "OFF"
                drawButton(b)
                break
            end
        end
        lastStatusMsg = "Raw Ore Collection: " .. (msg.enabled and "ON" or "OFF")
    end
    
    -- Save state whenever we receive a status update
    if stateChanged then
        saveState()
        print("[STATE] Updated state from collection controller")
    end
    
    updateStatusLine()
end

-- Handle state query requests from collection controllers
local function handleStateQuery(msg)
    if type(msg) ~= "table" then return end
    if msg.name ~= "odmk3-command-center" then return end
    if msg.cmd ~= "queryState" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    if not NET_OK then return end
    
    -- Respond with current state based on query type
    if msg.type == "natBlocks" then
        rednet.broadcast({
            type = "natBlocksStatus",
            enabled = collectNatBlocksEnabled,
            secret = ""
        }, PROTOCOL)
    elseif msg.type == "buildBlocks" then
        rednet.broadcast({
            type = "buildBlocksStatus", 
            enabled = collectBuildBlocksEnabled,
            secret = ""
        }, PROTOCOL)
    elseif msg.type == "rawOre" then
        rednet.broadcast({
            type = "rawOreStatus",
            enabled = collectRawOreEnabled,
            secret = ""
        }, PROTOCOL)
    end
end

local function handleMoveComplete(msg)
    if type(msg) ~= "table" then return end
    if msg.type ~= "moveAck" then return end
    if SECRET ~= "" and msg.secret ~= SECRET then return end
    
    -- When machine moves, recalibrate monitor after a short delay
    if msg.ok then
        sleep(0.5) -- Give time for peripheral to settle
        if recalibrateMonitor() then
            redraw() -- Full redraw if monitor size changed
        else
            updateStatusLine() -- Just update status if no size change
        end
    end
end

-- ========== main function ==========
local function main()
    -- Initialize monitor
    if not findMonitor() then
        print("ERROR: No monitor found! Please attach a monitor.")
        return
    end
    
    -- Load persistent state
    loadState()
    
    -- Initialize networking
    openAllModems()
    
    -- Initial setup
    monitor.setTextScale(0.9)  -- Slightly smaller text for 3x3 monitor
    redraw()
    
    -- Start monitor health check timer
    monitorHealthTimer = os.startTimer(30)
    
    print("Onboard Command Center initialized on " .. MONITOR_WIDTH .. "x" .. MONITOR_HEIGHT .. " monitor")
    
    -- Query states at startup to sync with actual system state
    if NET_OK then
        rednet.broadcast({
            name = "odmk3-auto-drive",
            cmd = "status",
            secret = ""
        }, PROTOCOL)
        
        -- Query collection controllers for current states
        queryCollectionStates()
        rednet.broadcast({
            name = "odmk3-collect-nat-blocks",
            cmd = "status",
            secret = ""
        }, PROTOCOL)
        
        rednet.broadcast({
            name = "odmk3-collect-build-blocks", 
            cmd = "status",
            secret = ""
        }, PROTOCOL)
    end
    
    while true do
        local event, param1, param2, param3 = os.pullEventRaw()
        
        if event == "monitor_touch" then
            local x, y = param2, param3
            handleTouch(x, y)
            
        elseif event == "rednet_message" then
            local sender, msg, proto = param1, param2, param3
            if proto == PROTOCOL then
                handleRotateAck(msg)
                handleFacing(msg)
                handleAutoDriveStatus(msg)
                handleMoveComplete(msg)
                handleCollectionStatus(msg)
                handleStateQuery(msg)
            end
            
        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Monitor connected/disconnected
            findMonitor()
            if monitor then
                redraw()
            end
            
        elseif event == "monitor_resize" then
            -- Monitor size changed
            if recalibrateMonitor() then
                redraw()
            end
            
        elseif event == "timer" then
            -- Periodic monitor health check (every 30 seconds)
            if param1 == monitorHealthTimer then
                if monitor then
                    if recalibrateMonitor() then
                        redraw()
                    end
                end
                monitorHealthTimer = os.startTimer(30)
            end
            
        elseif event == "terminate" then
            if monitor then
                monitor.setBackgroundColor(colors.black)
                monitor.clear()
                monitor.setCursorPos(1, 1)
                monitor.setTextColor(colors.white)
                monitor.write("Onboard Command Center Shutdown")
            end
            break
        end
    end
end

-- Start the system
main()
