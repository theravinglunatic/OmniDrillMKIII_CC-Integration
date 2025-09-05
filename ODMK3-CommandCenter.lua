-- ODMK3-CommandCenter.lua
-- Omni-Drill MKIII: Direction GUI (Pocket/Advanced)
-- v1: draw 6 buttons (N, E, S, W, U, D) and report taps.

-- ========== config ==========
local TITLE      = "Omni-Drill MKIII"
local BTN_FG     = colors.white
local BTN_BG     = colors.blue
local BTN_BG_ALT = colors.brown      -- for vertical (Up/Down) buttons
local BTN_BG_HI  = colors.cyan
local BG         = colors.black
local TITLE_FG   = colors.yellow
local TITLE_BG   = colors.gray
local STATUS_FG  = colors.lightGray
local STATUS_BG  = colors.gray
local LAYOUT     = "dpad"  -- "grid" or "dpad"

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
local STATE_FILE = "command_state"

-- Page management
local currentPage = 1  -- 1 = Movement, 2 = Collection Controls
local totalPages = 2

-- ========== utils ==========
local function centerText(y, text, fg, bg)
  local w, _ = term.getSize()
  local x = math.floor((w - #text) / 2) + 1
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.setCursorPos(x, y)
  term.clearLine()
  term.write(text)
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

local function fillRect(x1, y1, x2, y2, bg)
  term.setBackgroundColor(bg or colors.black)
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function drawBox(x1, y1, x2, y2, fg)
  term.setTextColor(fg or colors.white)
  for x = x1, x2 do
    term.setCursorPos(x, y1) term.write("-")
    term.setCursorPos(x, y2) term.write("-")
  end
  for y = y1, y2 do
    term.setCursorPos(x1, y) term.write("|")
    term.setCursorPos(x2, y) term.write("|")
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
  local bg = b.hot and BTN_BG_HI or b.bg
  if lastPressed == b.id then
    -- Intensify background for last pressed instead of drawing a border
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
  term.setTextColor(b.fg)
  for i, line in ipairs(lines) do
    term.setBackgroundColor(bg)
    local lineLen = #line
    local x = b.x1 + math.floor((w - lineLen) / 2)
    term.setCursorPos(x, firstY + i - 1)
    term.write(line)
  end
end

-- label map (cardinal + vertical) – plain text only
local FULL = {
  N="North", E="East", S="South", W="West", U="Up", D="Down", F="Forward",
  M="Move", A="AutoMove" -- action buttons (letters only per constraint)
}
-- Short labels to allow 5 uniform columns on pocket width
local SHORT = { N="N", E="E", S="S", W="W", U="Up", D="Dn", F="Fwd", M="Move", A="Auto" }

-- ========== layout functions ==========
local function drawPageHeader(w, h)
  local bottomStatus = h
  term.setBackgroundColor(BG); term.clear()
  
  -- Draw title bar
  fillRect(1, 1, w, 2, TITLE_BG)
  centerText(1, TITLE, TITLE_FG, TITLE_BG)
  
  -- Draw page indicator
  local pageText = string.format("Page %d/%d - %s", currentPage, totalPages, 
    currentPage == 1 and "Movement" or "Collection Controls")
  centerText(2, pageText, TITLE_FG, TITLE_BG)
  
  -- Status line
  term.setCursorPos(1, bottomStatus)
  term.setBackgroundColor(STATUS_BG)
  term.setTextColor(STATUS_FG)
  term.clearLine()
  term.write("Tap direction/action (Q=exit, P=page)")
  
  return 3, bottomStatus  -- return top, bottom for content area
end

local function addButtonWithColor(id, label, x1, y1, x2, y2, customColor)
  addButton(id, label, x1, y1, x2, y2)
  if customColor then
    buttons[#buttons].bg = customColor
  end
end

-- Simplified movement page layout
local function layoutMovementPage(w, h, top, bottomStatus)
  -- Simple 3x3 grid calculation
  local cols, rows = 3, 3
  local gapX, gapY = 2, 1
  local btnW = math.floor((w - 4 - (cols - 1) * gapX) / cols)  -- 2 margin each side
  local btnH = 3
  
  local totalH = rows * btnH + (rows - 1) * gapY
  local startY = top + 1 + math.floor((bottomStatus - top - 1 - totalH) / 2)
  local startX = 1 + math.floor((w - (cols * btnW + (cols - 1) * gapX)) / 2)
  
  local function addBtn(id, col, row, color)
    local x1 = startX + (col - 1) * (btnW + gapX)
    local y1 = startY + (row - 1) * (btnH + gapY)
    local label = SHORT[id] or FULL[id] or id
    addButtonWithColor(id, label, x1, y1, x1 + btnW - 1, y1 + btnH - 1, color)
  end
  
  -- Layout: 3x3 grid
  addBtn("U", 1, 1, BTN_BG_ALT)     -- Up
  addBtn("N", 2, 1, colors.green)   -- North  
  addBtn("M", 3, 1, colors.purple)  -- Move
  addBtn("W", 1, 2, colors.green)   -- West
  addBtn("F", 2, 2, BTN_BG)         -- Forward (center)
  addBtn("E", 3, 2, colors.green)   -- East
  addBtn("D", 1, 3, BTN_BG_ALT)     -- Down
  addBtn("S", 2, 3, colors.green)   -- South
  addBtn("A", 3, 3, autoDriveEnabled and colors.red or colors.purple)  -- Auto (color based on state)
end

-- Simplified utilities page layout
local function layoutUtilitiesPage(w, h, top, bottomStatus)
  local contentHeight = bottomStatus - top - 1
  local startY = top + 2
  
  -- List-style layout for collection controls
  local itemHeight = 3
  local gap = 1
  local totalItems = 3
  local listHeight = totalItems * itemHeight + (totalItems - 1) * gap
  local actualStartY = startY + math.floor((contentHeight - listHeight) / 2)
  
  local function addListItem(id, text, itemIndex, enabled)
    local y1 = actualStartY + (itemIndex - 1) * (itemHeight + gap)
    local y2 = y1 + itemHeight - 1
    
    -- Main text area (left side)
    local textX1 = 2
    local textX2 = w - 6
    addButtonWithColor(id, text, textX1, y1, textX2, y2, colors.gray)
    
    -- Status indicator box (right side)
    local boxX1 = w - 4
    local boxX2 = w - 1
    local boxColor = enabled and colors.lime or colors.red
    local boxLabel = enabled and "ON" or "OFF"
    addButtonWithColor(id .. "_STATUS", boxLabel, boxX1, y1, boxX2, y2, boxColor)
  end
  
  -- Collection control list items
  addListItem("NAT_BLOCKS", "Natural Blocks\nCollection", 1, collectNatBlocksEnabled or true)
  addListItem("BUILD_BLOCKS", "Build Blocks\nCollection", 2, collectBuildBlocksEnabled or true)
  addListItem("RAW_ORE", "Raw Ore\nCollection", 3, collectRawOreEnabled or true)
end

-- Main layout function
local function layoutButtons()
  buttons = {}
  local w, h = term.getSize()
  local top, bottom = drawPageHeader(w, h)
  
  if currentPage == 1 then
    layoutMovementPage(w, h, top, bottom)
  else
    layoutUtilitiesPage(w, h, top, bottom)
  end
end

local function redraw(status)
  local w, h = term.getSize()
  term.setBackgroundColor(BG); term.clear()
  fillRect(1, 1, w, 2, TITLE_BG)
  centerText(1, TITLE, TITLE_FG, TITLE_BG)
  for _, b in ipairs(buttons) do drawButton(b) end
  term.setCursorPos(1, h)
  term.setBackgroundColor(STATUS_BG)
  term.setTextColor(STATUS_FG)
  term.clearLine()
  local line
  if status then
    line = status
  elseif pendingTarget then
    line = "Sent "..pendingTarget.."; waiting ack"  
  elseif lastNetError then
    line = "NET ERR: "..lastNetError
  elseif not NET_OK then
    line = "Offline: tap=local only (Q exits)"
  elseif lastStatusMsg then
    line = lastStatusMsg
  elseif lastFacing then
    line = "Facing: "..lastFacing.." (tap dir)"
  else
    line = "Tap a direction (Q to exit)"
  end
  term.write(line)
end

-- ========== event loop ==========
local function openAnyWireless()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
      if not rednet.isOpen(side) then rednet.open(side) end
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
    redraw()
  elseif dir == "U" or dir == "D" or dir == "F" then
    -- Vertical directions
    pendingTarget = dir
    lastStatusMsg = nil
    rednet.broadcast({ name = VERT_ROTATER_NAME, cmd = "setFacing", target = dir, secret = "" }, PROTOCOL)
    redraw()
  end
end

local function press(id, label)
  lastPressed = id
  
  -- Movement commands (Page 1)
  if id == "N" or id == "E" or id == "S" or id == "W" or id == "U" or id == "D" or id == "F" then
    sendDirection(id)
    
  elseif id == "M" then
    if NET_OK then
      pendingTarget = "Move"
      lastStatusMsg = nil
      rednet.broadcast({ name = "odmk3-drive-controller", cmd = "move", secret = "" }, PROTOCOL)
      lastStatusMsg = "Sent Move command"
    else
      lastStatusMsg = "Cannot move: offline"
    end
    redraw()
    
  elseif id == "A" then
    if NET_OK then
      local newState = not autoDriveEnabled
      autoDriveEnabled = newState
      pendingTarget = "AutoToggle"
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
          lastStatusMsg = "Auto-Drive " .. (newState and "ON" or "OFF")
          break
        end
      end
    else
      lastStatusMsg = "Cannot auto-drive: offline"
    end
    redraw()
  
  -- Collection control commands (Page 2)
  elseif id == "NAT_BLOCKS" or id == "NAT_BLOCKS_STATUS" then
    if NET_OK then
  -- Properly invert current state (previous logic always produced false due to 'or true')
  local newState = not collectNatBlocksEnabled
  collectNatBlocksEnabled = newState
      saveState()  -- Save state when making changes
      
      rednet.broadcast({
        name = "odmk3-collect-nat-blocks",
        cmd = "toggle",
        enabled = newState,
        secret = ""
      }, PROTOCOL)
      
      -- Update button appearance for both main button and status box
      for _, b in ipairs(buttons) do
        if b.id == "NAT_BLOCKS" then
          -- Keep main button gray but update text if needed
        elseif b.id == "NAT_BLOCKS_STATUS" then
          b.bg = newState and colors.lime or colors.red
          b.label = newState and "ON" or "OFF"
        end
      end
      lastStatusMsg = "Natural Blocks Collection " .. (newState and "ENABLED" or "DISABLED")
    else
      lastStatusMsg = "Cannot toggle collection: offline"
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
      
      -- Update button appearance for both main button and status box
      for _, b in ipairs(buttons) do
        if b.id == "BUILD_BLOCKS" then
          -- Keep main button gray but update text if needed
        elseif b.id == "BUILD_BLOCKS_STATUS" then
          b.bg = newState and colors.lime or colors.red
          b.label = newState and "ON" or "OFF"
        end
      end
      lastStatusMsg = "Build Blocks Collection " .. (newState and "ENABLED" or "DISABLED")
    else
      lastStatusMsg = "Cannot toggle collection: offline"
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
      
      -- Update button appearance for both main button and status box
      for _, b in ipairs(buttons) do
        if b.id == "RAW_ORE" then
          -- Keep main button gray but update text if needed
        elseif b.id == "RAW_ORE_STATUS" then
          b.bg = newState and colors.lime or colors.red
          b.label = newState and "ON" or "OFF"
        end
      end
      lastStatusMsg = "Raw Ore Collection " .. (newState and "ENABLED" or "DISABLED")
    else
      lastStatusMsg = "Cannot toggle collection: offline"
    end
    redraw()
  
  -- Utility commands (Page 2) - consolidated with simple broadcast helper
  elseif id == "STATUS" then
    lastStatusMsg = "System Status: " .. (NET_OK and "ONLINE" or "OFFLINE") .. 
                   " | Auto: " .. (autoDriveEnabled and "ON" or "OFF") ..
                   " | Facing: " .. (lastFacing or "Unknown")
    redraw()
    
  else
    -- Handle all other utility buttons with broadcast
    local utilityCommands = {
      RESET = "reset", CONFIG = "config", DEBUG = "debug", 
      BACKUP = "backup", TEST = "test"
    }
    
    if utilityCommands[id] then
      if NET_OK then
        lastStatusMsg = "Broadcasting " .. utilityCommands[id] .. "..."
        if id == "DEBUG" then
          lastStatusMsg = "Debug: Page=" .. currentPage .. " Buttons=" .. #buttons .. 
                         " Net=" .. (NET_OK and "OK" or "FAIL")
        else
          rednet.broadcast({ name = "odmk3-system", cmd = utilityCommands[id], secret = "" }, PROTOCOL)
        end
      else
        lastStatusMsg = "Cannot " .. utilityCommands[id] .. ": offline"
      end
    else
      lastStatusMsg = "Pressed: "..(FULL[id] or id)
    end
    redraw()
  end
end

local function handleTouch(x, y, isDown)
  for _, b in ipairs(buttons) do
    if pointIn(b, x, y) then
      b.hot = isDown
      drawButton(b)
      if not isDown then press(b.id, b.label) end
    else
      if b.hot then b.hot=false; drawButton(b) end
    end
  end
end

-- message handlers
local function handleRotateAck(msg)
  if type(msg) ~= "table" then return end
  if msg.type ~= "rotateAck" and msg.type ~= "moveAck" then return end
  if SECRET ~= "" and msg.secret ~= SECRET then return end
  
  if msg.type == "rotateAck" then
    if pendingTarget and msg.targetDir and msg.targetDir ~= pendingTarget then return end
    pendingTarget = nil
    if msg.ok then
      lastFacing = msg.after or msg.targetDir or lastFacing
      lastStatusMsg = string.format("Rotated %s→%s (%s)", msg.before or '?', msg.after or msg.targetDir or '?', msg.action or 'ok')
    else
      lastStatusMsg = "Rotate failed: "..(msg.err or 'unknown')
    end
  elseif msg.type == "moveAck" then
    if pendingTarget ~= "Move" then return end
    pendingTarget = nil
    if msg.ok then
      lastStatusMsg = "Move command completed"
    else
      lastStatusMsg = "Move failed: "..(msg.err or 'unknown')
    end
  end
  
  redraw()
end

local function handleAutoDriveStatus(msg)
  if type(msg) ~= "table" or msg.type ~= "autoStatus" then return end
  if SECRET ~= "" and msg.secret ~= SECRET then return end
  
  if pendingTarget == "AutoToggle" then
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
        b.bg = colors.red  -- Indicate auto-drive is active
        if msg.safe then
          lastStatusMsg = "Auto-Drive ON (Safe to move)"
        else
          lastStatusMsg = "Auto-Drive ON (Waiting for safety signal)"
        end
      else
        b.bg = colors.purple or colors.magenta  -- Reset to default color
        lastStatusMsg = "Auto-Drive OFF"
      end
      drawButton(b)
      break
    end
  end
  
  redraw()
end

local function handleAutoDriveQuery(msg)
  if type(msg) ~= "table" or msg.type ~= "autoStateQuery" then return end
  if SECRET ~= "" and msg.secret ~= SECRET then return end
  
  -- Debug: log that we received a state query
  print("[DEBUG] Received auto-drive state query, responding with: " .. (autoDriveEnabled and "ON" or "OFF"))
  
  -- Respond with our current auto-drive state
  rednet.broadcast({
    type = "autoStateResponse",
    enabled = autoDriveEnabled,
    secret = ""
  }, PROTOCOL)
end

local function handleFacing(msg)
  if type(msg) ~= "table" then return end
  if msg.type ~= "facing" then return end
  if SECRET ~= "" and msg.secret ~= SECRET then return end
  lastFacing = msg.facing or lastFacing
  if not pendingTarget then lastStatusMsg = nil end
  redraw()
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
  
  redraw()
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

local function main()
  if not term.isColor() then
    print("This GUI needs an Advanced (color) pocket.")
    return
  end
  
  -- Load persistent state
  loadState()
  
  openAnyWireless()
  layoutButtons()
  redraw()

  -- Query states at startup to sync with actual system state
  if NET_OK then
    rednet.broadcast({
      name = "odmk3-auto-drive",
      cmd = "status",
      secret = ""
    }, PROTOCOL)
    
    -- Query collection controllers for current states
    queryCollectionStates()
    
    -- Set a timeout to reset state if no response
    local statusTimer = os.startTimer(2.0)  -- 2 second timeout
    
    -- Wait briefly for status response
    local timeout = false
    repeat
      local event, param1, param2, param3 = os.pullEvent()
      if event == "rednet_message" then
        local sender, msg, proto = param1, param2, param3
        if proto == PROTOCOL and type(msg) == "table" then
          if msg.type == "autoStatus" then
            handleAutoDriveStatus(msg)
          elseif msg.type == "natBlocksStatus" or msg.type == "buildBlocksStatus" or msg.type == "rawOreStatus" then
            handleCollectionStatus(msg)
          else
            handleStateQuery(msg)
          end
        end
      elseif event == "timer" and param1 == statusTimer then
        -- Timeout occurred, assume defaults
        autoDriveEnabled = false
        timeout = true
        break
      end
    until timeout
  end

  while true do
    local e, p1, p2, p3 = os.pullEvent()
    if e == "mouse_click" then
      local _, x, y = p1, p2, p3
      handleTouch(x, y, true)
    elseif e == "mouse_drag" then
      handleTouch(p2, p3, true)
    elseif e == "mouse_up" then
      handleTouch(p2, p3, false)
    elseif e == "term_resize" then
      layoutButtons(); redraw()
    elseif e == "key" and p1 == keys.q then
      -- quick exit
      term.setBackgroundColor(BG); term.clear(); term.setCursorPos(1,1)
      return
    elseif e == "key" and p1 == keys.p then
      -- page switch
      currentPage = currentPage + 1
      if currentPage > totalPages then currentPage = 1 end
      layoutButtons()
      redraw()
    elseif e == "rednet_message" then
      local sender, msg, proto = p1, p2, p3
      if proto == PROTOCOL then
        handleRotateAck(msg)
        handleFacing(msg)
        handleAutoDriveStatus(msg)
        handleAutoDriveQuery(msg)
        handleCollectionStatus(msg)
        handleStateQuery(msg)
      end
    end
  end
end

main()
