-- OmniDrill-Monitor.lua
-- Advanced Monitor display for Omni-Drill MKIII metrics
-- Displays real-time Create contraption and drilling system status
-- Monitor: 3 blocks tall x 7 blocks wide (21x9 characters)

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""  -- Keep empty to disable, or match with other components
local DEBUG = false  -- Set to true for debug messages
local REFRESH_RATE = 1.0  -- How often to update display (seconds)
local METRICS_FILE = "metrics"  -- Persistent metrics storage file
local VAULT_CAPACITY = 103680  -- Maximum vault capacity in items

-- ========== Monitor Configuration ==========
local monitor = peripheral.find("monitor")
local targetBlock = peripheral.find("create_target")
local MONITOR_WIDTH = 21  -- Will be updated dynamically
local MONITOR_HEIGHT = 9  -- Will be updated dynamically

-- ========== System Status Tracking ==========
local systemStatus = {
    -- Auto-Drive System
    autoDriveEnabled = false,
    autoDriveSafe = false,
    
    -- Collection Status
    collectNatBlocksEnabled = false,
    collectBuildBlocksEnabled = false,
    collectRawOreEnabled = false,
    
    -- Vault Status
    vaultFull = false,
    
    -- Drill Status
    drillActive = false,
    
    -- Movement Status
    lastMoveTime = 0,
    moveCount = 0,
    
    -- Facing Direction
    currentFacing = "Unknown",
    verticalFacing = "Unknown",  -- Don't assume Forward, wait for actual data
    
    -- Vault Item Data
    vaultItems = {},
    vaultItemCount = 0,
    
    -- Network Status
    networkActive = false,
    lastUpdate = 0,
    
    -- Blink State for "NONE" collection status
    blinkState = false,
    lastBlinkTime = 0
}

-- Persistent metrics (survive reboots)
local persistentMetrics = {
    totalMoves = 0,
    totalUptime = 0,
    sessionStart = 0,
    lastSaveTime = 0,
    drillActivations = 0,
    systemReboots = 0
}

-- Color scheme
local colorScheme = {
    bg = colors.black,
    title = colors.yellow,
    good = colors.lime,
    warning = colors.orange,
    danger = colors.red,
    inactive = colors.gray,
    text = colors.white,
    accent = colors.cyan
}

-- ========== Utilities ==========
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

-- Load persistent metrics from file
local function loadMetrics()
    if fs.exists(METRICS_FILE) then
        local file = fs.open(METRICS_FILE, "r")
        if file then
            local data = file.readAll()
            file.close()
            
            if data and data ~= "" then
                local success, metrics = pcall(textutils.unserialise, data)
                if success and metrics then
                    for key, value in pairs(metrics) do
                        if persistentMetrics[key] ~= nil then
                            persistentMetrics[key] = value
                        end
                    end
                    debugPrint("Loaded metrics: " .. persistentMetrics.totalMoves .. " total moves")
                    return true
                end
            end
        end
    end
    
    -- Initialize new metrics file
    persistentMetrics.sessionStart = os.clock()
    persistentMetrics.systemReboots = persistentMetrics.systemReboots + 1
    debugPrint("Initialized new metrics file")
    return false
end

-- Save persistent metrics to file
local function saveMetrics()
    local file = fs.open(METRICS_FILE, "w")
    if file then
        -- Update uptime before saving
        local currentTime = os.clock()
        if persistentMetrics.sessionStart > 0 then
            persistentMetrics.totalUptime = persistentMetrics.totalUptime + (currentTime - persistentMetrics.sessionStart)
            persistentMetrics.sessionStart = currentTime
        end
        persistentMetrics.lastSaveTime = currentTime
        
        file.write(textutils.serialise(persistentMetrics))
        file.close()
        debugPrint("Saved metrics to file")
        return true
    end
    return false
end

-- Update move count and save
local function recordMove()
    persistentMetrics.totalMoves = persistentMetrics.totalMoves + 1
    systemStatus.moveCount = persistentMetrics.totalMoves
    saveMetrics()
    debugPrint("Recorded move #" .. persistentMetrics.totalMoves)
end

-- Update drill activation count
local function recordDrillActivation()
    persistentMetrics.drillActivations = persistentMetrics.drillActivations + 1
    saveMetrics()
    debugPrint("Recorded drill activation #" .. persistentMetrics.drillActivations)
end

-- Utility: open any connected modems
local function openAllModems()
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if not rednet.isOpen(side) then
                pcall(function() rednet.open(side) end)
                debugPrint("Opened modem on " .. side)
            end
        end
    end
end

-- Check if monitor is available
local function checkMonitor()
    if not monitor then
        monitor = peripheral.find("monitor")
        if not monitor then
            error("No monitor found! Please attach an Advanced Monitor to the front face.")
        end
    end
    return monitor
end

-- Check if target block is available
local function checkTargetBlock()
    if not targetBlock then
        targetBlock = peripheral.find("create_target")
    end
    return targetBlock
end

-- Read vault item data from Target Block
local function updateVaultItemData()
    if not checkTargetBlock() then
        debugPrint("No Target Block found")
        return false
    end
    
    local success, result = pcall(function()
        -- Get all lines from the target block
        local lines = targetBlock.dump()
        systemStatus.vaultItems = {}
        systemStatus.vaultItemCount = 0
        
        -- Parse each line for item data
        for i, line in ipairs(lines) do
            if line and line ~= "" then
                -- Remove any leading/trailing whitespace
                line = line:match("^%s*(.-)%s*$")
                
                if line ~= "" then
                    -- Try to extract item name and count
                    -- Format might be like "Iron Ore: 1234" or "1234x Iron Ore" etc.
                    local count, item = line:match("(%d+)x?%s*(.+)")
                    if not count then
                        item, count = line:match("(.+):%s*(%d+)")
                    end
                    if not count then
                        count = line:match("(%d+)")
                        item = line:gsub("%d+", ""):match("^%s*(.-)%s*$")
                    end
                    
                    if count and item and item ~= "" then
                        count = tonumber(count) or 0
                        systemStatus.vaultItemCount = systemStatus.vaultItemCount + count
                        table.insert(systemStatus.vaultItems, {name = item, count = count})
                        debugPrint("Found item: " .. item .. " x" .. count)
                    else
                        -- If we can't parse it, just store the raw line
                        table.insert(systemStatus.vaultItems, {name = line, count = 0})
                    end
                end
            end
        end
        
        debugPrint("Total vault items: " .. systemStatus.vaultItemCount)
        return true
    end)
    
    if not success then
        debugPrint("Error reading Target Block: " .. tostring(result))
        return false
    end
    
    return result
end

-- Format collection status text
local function formatCollectionStatus()
    local collectingItems = {}
    
    if systemStatus.collectNatBlocksEnabled then
        table.insert(collectingItems, "NATURAL BLOCKS")
    end
    
    if systemStatus.collectBuildBlocksEnabled then
        table.insert(collectingItems, "BUILDING BLOCKS")
    end
    
    if systemStatus.collectRawOreEnabled then
        table.insert(collectingItems, "RAW ORE")
    end
    
    if #collectingItems == 0 then
        return "COLLECTING: NONE", true  -- Return text and isNone flag
    else
        return "COLLECTING: " .. table.concat(collectingItems, ", "), false
    end
end

-- Initialize monitor
local function initMonitor()
    if not checkMonitor() then return false end
    
    monitor.setBackgroundColor(colorScheme.bg)
    monitor.clear()
    monitor.setTextScale(0.9)  -- Larger text for better readability
    
    -- Get actual monitor size
    local width, height = monitor.getSize()
    MONITOR_WIDTH = width
    MONITOR_HEIGHT = height
    
    -- Draw title bar
    monitor.setBackgroundColor(colorScheme.title)
    monitor.setTextColor(colors.black)
    monitor.setCursorPos(1, 1)
    monitor.write(string.format("%-" .. width .. "s", " OMNI-DRILL MKIII"))
    
    return true
end

-- Format time from seconds to readable format
local function formatTime(seconds)
    if seconds < 60 then
        return string.format("%.0fs", seconds)
    elseif seconds < 3600 then
        return string.format("%.1fm", seconds / 60)
    elseif seconds < 86400 then
        return string.format("%.1fh", seconds / 3600)
    else
        return string.format("%.1fd", seconds / 86400)
    end
end

-- Format time since last update
local function formatTimeSince(timestamp)
    if timestamp == 0 then return "Never" end
    local elapsed = os.clock() - timestamp
    return formatTime(elapsed)
end

-- Convert facing code to full text
local function formatFacing(facing)
    local facingMap = {
        N = "NORTH",
        E = "EAST", 
        S = "SOUTH",
        W = "WEST",
        U = "UP",
        D = "DOWN",
        F = "FORWARD"
    }
    return facingMap[facing] or facing or "UNKNOWN"
end

-- Update redstone output based on facing direction
local function updateRedstoneOutput()
    local currentFacing = systemStatus.currentFacing
    
    -- Output redstone signal on bottom face when facing West or South
    local shouldOutput = (currentFacing == "W" or currentFacing == "S")
    
    redstone.setOutput("bottom", shouldOutput)
    
    if DEBUG then
        debugPrint("Redstone output on bottom: " .. (shouldOutput and "ON" or "OFF") .. " (facing: " .. (currentFacing or "Unknown") .. ")")
    end
end

-- Main display update
local function updateDisplay()
    if not checkMonitor() then return end
    
    -- Get current monitor size
    local width, height = monitor.getSize()
    
    -- Update title bar
    monitor.setBackgroundColor(colorScheme.title)
    monitor.setTextColor(colors.black)
    monitor.setCursorPos(1, 1)
    monitor.write(string.format("%-" .. width .. "s", " OMNI-DRILL MKIII"))
    
    -- Clear content area (keep title - now 1 row)
    monitor.setBackgroundColor(colorScheme.bg)
    for y = 2, height do
        monitor.setCursorPos(1, y)
        monitor.write(string.rep(" ", width))
    end
    
    -- Row 2: Collection Status (dedicated line)
    monitor.setBackgroundColor(colorScheme.bg)
    monitor.setCursorPos(1, 2)
    local collectionStatus, isNone = formatCollectionStatus()
    
    -- Handle blinking for "NONE" status
    if isNone then
        local currentTime = os.clock()
        -- Blink every 0.5 seconds
        if currentTime - systemStatus.lastBlinkTime >= 0.5 then
            systemStatus.blinkState = not systemStatus.blinkState
            systemStatus.lastBlinkTime = currentTime
        end
        
        if systemStatus.blinkState then
            monitor.setTextColor(colorScheme.danger)  -- Red when visible
        else
            monitor.setTextColor(colorScheme.bg)      -- Hide when blinking off
        end
    else
        monitor.setTextColor(colorScheme.accent)  -- Normal cyan for active collection
    end
    
    monitor.write(collectionStatus)
    
    local currentTime = os.clock()
    
    -- Row 3: Auto-Drive Status and Vault Status (spread across width)
    local autoStatus = systemStatus.autoDriveEnabled
    
    -- Left side: Auto status
    monitor.setBackgroundColor(colorScheme.bg)
    monitor.setTextColor(colorScheme.text)
    monitor.setCursorPos(1, 4)
    monitor.write("AUTO:")
    
    local statusColor = colorScheme.inactive
    local statusText = "OFF"
    if autoStatus then
        statusColor = colorScheme.good
        statusText = "ON"
    end
    
    monitor.setTextColor(statusColor)
    monitor.write(statusText)
    
    -- Right side: Vault status
    local vaultX = math.floor(width * 0.6)  -- Position at 60% of screen width
    monitor.setCursorPos(vaultX, 4)
    monitor.setTextColor(colorScheme.text)
    monitor.write("AUX VAULT:")
    
    local vaultStatus = not systemStatus.vaultFull
    local vaultDetails = systemStatus.vaultFull and " FULL" or " OK"
    local vaultColor = vaultStatus and colorScheme.good or colorScheme.danger
    
    monitor.setTextColor(vaultColor)
    monitor.write(vaultStatus and "ON" or "FULL")
    monitor.setTextColor(colorScheme.accent)
    monitor.write(vaultDetails)
    
    -- Row 5: Drill Status and Move Count (spread across width)
    monitor.setBackgroundColor(colorScheme.bg)
    monitor.setTextColor(colorScheme.text)
    monitor.setCursorPos(1, 5)
    monitor.write("DRILL:")
    
    local drillColor = systemStatus.drillActive and colorScheme.good or colorScheme.inactive
    monitor.setTextColor(drillColor)
    monitor.write(systemStatus.drillActive and "ON " or "OFF")
    
    -- Move counter on the right
    monitor.setTextColor(colorScheme.text)
    monitor.setCursorPos(vaultX, 5)
    monitor.write("MOVES:")
    monitor.setTextColor(colorScheme.accent)
    monitor.write(string.format("%d", persistentMetrics.totalMoves))
    
    -- Row 6: Facing Direction and System Info
    monitor.setBackgroundColor(colorScheme.bg)
    monitor.setTextColor(colorScheme.text)
    monitor.setCursorPos(1, 6)
    monitor.write("FACING:")
    monitor.setTextColor(colorScheme.accent)
    
    -- Show cardinal and vertical facing as separate components
    local cardinalFacing = formatFacing(systemStatus.currentFacing)
    local verticalFacing = formatFacing(systemStatus.verticalFacing)
    
    -- Always show both components: "NORTH, FORWARD" or "NORTH, UNKNOWN"
    local facingText = cardinalFacing .. ", " .. verticalFacing
    
    monitor.write(" " .. facingText)
    
    -- Reboots on the right
    monitor.setTextColor(colorScheme.text)
    monitor.setCursorPos(vaultX, 6)
    monitor.write("REBOOTS:")
    monitor.setTextColor(colorScheme.accent)
    monitor.write(string.format(" %d", persistentMetrics.systemReboots))
    
    -- Row 7: Performance metrics spread across width
    monitor.setBackgroundColor(colorScheme.bg)
    monitor.setTextColor(colorScheme.text)
    monitor.setCursorPos(1, 7)
    monitor.write("DRILLS:")
    monitor.setTextColor(colorScheme.good)
    monitor.write(string.format(" %d", persistentMetrics.drillActivations))
    
    -- Calculate and show moves per hour
    monitor.setTextColor(colorScheme.text)
    monitor.setCursorPos(vaultX, 7)
    local currentUptime = persistentMetrics.totalUptime + (os.clock() - persistentMetrics.sessionStart)
    if currentUptime > 60 then  -- Only show rate after 1 minute
        local movesPerHour = math.floor((persistentMetrics.totalMoves / currentUptime) * 3600)
        monitor.write("RATE:")
        monitor.setTextColor(colorScheme.accent)
        monitor.write(string.format(" %d/h", movesPerHour))
    else
        monitor.write("RATE:")
        monitor.setTextColor(colorScheme.accent)
        monitor.write(" --/h")
    end
    
    -- Only show vault inventory if we have enough vertical space
    if height >= 9 then
        -- Row 8: Vault Items Header (full width)
        monitor.setBackgroundColor(colorScheme.accent)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(1, 8)
        monitor.write(string.format("%-" .. width .. "s", " MAIN VAULT INVENTORY"))
        
        -- Row 9: Total Item Count and Capacity
        monitor.setBackgroundColor(colorScheme.bg)
        monitor.setTextColor(colorScheme.text)
        monitor.setCursorPos(1, 9)
        monitor.write("TOTAL:")
        monitor.setTextColor(colorScheme.accent)
        if systemStatus.vaultItemCount > 0 then
            monitor.write(string.format(" %d", systemStatus.vaultItemCount))
        else
            monitor.write(" --")
        end
        
        -- Row 10: Capacity percentage
        if height >= 10 then
            monitor.setBackgroundColor(colorScheme.bg)
            monitor.setTextColor(colorScheme.text)
            monitor.setCursorPos(1, 10)
            monitor.write("CAPACITY:")
            monitor.setTextColor(colorScheme.accent)
            if systemStatus.vaultItemCount > 0 then
                local capacityPercent = (systemStatus.vaultItemCount / VAULT_CAPACITY) * 100
                -- Round up to nearest thousandth of a percent
                capacityPercent = math.ceil(capacityPercent * 1000) / 1000
                
                -- Color code based on capacity
                if capacityPercent >= 90 then
                    monitor.setTextColor(colorScheme.danger)
                elseif capacityPercent >= 75 then
                    monitor.setTextColor(colorScheme.warning)
                else
                    monitor.setTextColor(colorScheme.good)
                end
                monitor.write(string.format(" %.3f%%", capacityPercent))
            else
                monitor.write(" 0.000%")
            end
        end
        
        -- Show top items if we have more vertical space
        if height >= 11 and #systemStatus.vaultItems > 0 then
            local maxItems = math.min(#systemStatus.vaultItems, height - 10)  -- Available rows for items (starting from row 11)
            
            for i = 1, maxItems do
                local row = 10 + i
                if row <= height then
                    local item = systemStatus.vaultItems[i]
                    monitor.setCursorPos(1, row)
                    monitor.setTextColor(colorScheme.text)
                    
                    -- Format item name to fit available space
                    local itemName = item.name
                    local maxNameLength = width - 12  -- Reserve space for count
                    
                    if #itemName > maxNameLength then
                        itemName = itemName:sub(1, maxNameLength - 3) .. "..."
                    end
                    
                    monitor.write(itemName)
                    
                    -- Show count on the right if we have one
                    if item.count > 0 then
                        local countStr = string.format("%d", item.count)
                        local countX = width - #countStr + 1
                        monitor.setCursorPos(countX, row)
                        monitor.setTextColor(colorScheme.accent)
                        monitor.write(countStr)
                    end
                end
            end
        end
    end
end

-- Handle incoming status messages
local function handleStatusMessage(message)
    local updated = false
    
    -- Debug: print all received messages
    debugPrint("Received message type: " .. (message.type or "nil"))
    if message.type == "facing" or message.type == "rotateAck" then
        debugPrint("  - facing: " .. (message.facing or "nil"))
        debugPrint("  - verticalFacing: " .. (message.verticalFacing or "nil"))
        debugPrint("  - after: " .. (message.after or "nil"))
        debugPrint("  - verticalAfter: " .. (message.verticalAfter or "nil"))
    elseif message.type == "orientation" then
        debugPrint("  - orientation: " .. (message.orientation or "nil"))
        debugPrint("  - name: " .. (message.name or "nil"))
    end
    
    if message.type == "autoStatus" then
        if systemStatus.autoDriveEnabled ~= message.enabled then
            systemStatus.autoDriveEnabled = message.enabled or false
            updated = true
        end
        if systemStatus.autoDriveSafe ~= message.safe then
            systemStatus.autoDriveSafe = message.safe or false
            updated = true
        end
        
    elseif message.type == "vaultStatus" then
        if systemStatus.vaultFull ~= message.vaultFull then
            systemStatus.vaultFull = message.vaultFull or false
            updated = true
        end
        
    elseif message.type == "moveAck" then
        systemStatus.lastMoveTime = os.clock()
        recordMove()  -- Record persistent move count
        updated = true
        
    elseif message.type == "facing" then
        local facingUpdated = false
        if systemStatus.currentFacing ~= message.facing then
            systemStatus.currentFacing = message.facing or "Unknown"
            facingUpdated = true
        end
        if message.verticalFacing and systemStatus.verticalFacing ~= message.verticalFacing then
            systemStatus.verticalFacing = message.verticalFacing
            facingUpdated = true
        end
        if facingUpdated then
            updated = true
            updateRedstoneOutput()  -- Update redstone when facing changes
        end
        
    elseif message.type == "rotateAck" then
        local rotateUpdated = false
        if message.after and systemStatus.currentFacing ~= message.after then
            systemStatus.currentFacing = message.after
            rotateUpdated = true
        end
        if message.verticalAfter and systemStatus.verticalFacing ~= message.verticalAfter then
            systemStatus.verticalFacing = message.verticalAfter
            rotateUpdated = true
        end
        if rotateUpdated then
            updated = true
            updateRedstoneOutput()  -- Update redstone when rotation completes
        end
        
    elseif message.type == "orientation" then
        -- Handle vertical orientation messages from Vertical Reader
        if message.orientation and systemStatus.verticalFacing ~= message.orientation then
            systemStatus.verticalFacing = message.orientation
            updated = true
            debugPrint("Updated vertical facing to: " .. message.orientation)
        end
        
    elseif message.type == "natBlocksStatus" then
        -- Handle natural blocks collection status
        if systemStatus.collectNatBlocksEnabled ~= message.enabled then
            systemStatus.collectNatBlocksEnabled = message.enabled or false
            updated = true
            debugPrint("Natural blocks collection: " .. (message.enabled and "ENABLED" or "DISABLED"))
        end
        
    elseif message.type == "buildBlocksStatus" then
        -- Handle build blocks collection status
        if systemStatus.collectBuildBlocksEnabled ~= message.enabled then
            systemStatus.collectBuildBlocksEnabled = message.enabled or false
            updated = true
            debugPrint("Build blocks collection: " .. (message.enabled and "ENABLED" or "DISABLED"))
        end
        
    elseif message.type == "rawOreStatus" then
        -- Handle raw ore collection status
        if systemStatus.collectRawOreEnabled ~= message.enabled then
            systemStatus.collectRawOreEnabled = message.enabled or false
            updated = true
            debugPrint("Raw ore collection: " .. (message.enabled and "ENABLED" or "DISABLED"))
        end
    end
    
    if updated then
        systemStatus.lastUpdate = os.clock()
        systemStatus.networkActive = true
        debugPrint("Status updated: " .. (message.type or "unknown"))
    end
end

-- Main function
local function main()
    -- Initialize
    openAllModems()
    
    -- Load persistent metrics
    loadMetrics()
    
    if not initMonitor() then
        error("Failed to initialize monitor")
    end
    
    print("OmniDrill-Monitor initialized")
    debugPrint("Monitoring system status on protocol: " .. PROTOCOL)
    debugPrint("Total moves: " .. persistentMetrics.totalMoves)
    debugPrint("System reboots: " .. persistentMetrics.systemReboots)
    
    -- Query collection status at startup
    debugPrint("Querying collection status at startup...")
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
    
    -- Initial vault data read
    updateVaultItemData()
    
    -- Set initial redstone output based on current facing
    updateRedstoneOutput()
    
    -- Initial display
    updateDisplay()
    
    -- Set up timers
    local refreshTimer = os.startTimer(REFRESH_RATE)
    local saveTimer = os.startTimer(30)  -- Save metrics every 30 seconds
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "rednet_message" then
            local sender, message, protocol = param1, param2, param3
            
            if protocol == PROTOCOL and type(message) == "table" then
                -- Verify secret if needed
                if SECRET == "" or message.secret == SECRET then
                    handleStatusMessage(message)
                end
            end
            
        elseif event == "timer" and param1 == refreshTimer then
            -- Refresh display and update vault data
            updateVaultItemData()  -- Read from Target Block
            updateDisplay()
            refreshTimer = os.startTimer(REFRESH_RATE)
            
        elseif event == "timer" and param1 == saveTimer then
            -- Periodic save of metrics
            saveMetrics()
            saveTimer = os.startTimer(30)  -- Reset save timer
            
        elseif event == "monitor_touch" then
            -- Handle monitor touches (future feature)
            debugPrint("Monitor touched at " .. param2 .. "," .. param3)
            
        elseif event == "peripheral" or event == "peripheral_detach" then
            -- Monitor connected/disconnected
            monitor = peripheral.find("monitor")
            if monitor then
                initMonitor()
                updateDisplay()
            end
        elseif event == "terminate" then
            -- Save metrics before exit
            saveMetrics()
            break
        end
    end
end

-- Start the main function
main()
