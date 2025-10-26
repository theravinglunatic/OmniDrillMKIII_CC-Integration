-- ODMK3-UnifiedCommand.lua (Modularized)
-- Unified Command Center for Omni-Drill MKIII
-- Combines Movement Controls and Utility Monitoring
-- Computer 21 with dual monitor setup:
--   - Back: 3x3 monitor for UTILITY (monitoring + collection controls)
--   - Left: 3x3 monitor for MOVEMENT controls

-- ========== Load Modules ==========
local Config = require("modules.config")
local StateManager = require("modules.state_manager")
local UtilityDisplay = require("modules.utility_display")
local MovementDisplay = require("modules.movement_display")
local NetworkHandler = require("modules.network_handler")

-- ========== State Initialization ==========
local systemState, persistentMetrics = StateManager.initialize()

-- ========== Monitor Discovery ==========
local function findMonitors()
    -- Find monitors by side
    local back = peripheral.wrap("back")
    local left = peripheral.wrap("left")
    
    local utilityOk = false
    local movementOk = false
    
    if back and peripheral.getType("back") == "monitor" then
        utilityOk = UtilityDisplay.init(back)
        Config.debugPrint("Found utility monitor on back")
    end
    
    if left and peripheral.getType("left") == "monitor" then
        movementOk = MovementDisplay.init(left)
        Config.debugPrint("Found movement monitor on left")
    end
    
    return utilityOk and movementOk
end

-- ========== Event Loops ==========
-- Single input dispatcher: avoids competing os.pullEvent consumers for monitor_touch
local function runMonitorInputs()
    while true do
        local _, side, x, y = os.pullEvent("monitor_touch")
        if side == "back" then
            local handled, command = UtilityDisplay.handleTouch(systemState, x, y)
            if handled then
                UtilityDisplay.draw(systemState, persistentMetrics)
                StateManager.saveState(systemState)
                if command then
                    NetworkHandler.broadcast(command)
                end
            end
        elseif side == "left" then
            local handled, command = MovementDisplay.handleTouch(systemState, x, y)
            if handled then
                MovementDisplay.draw(systemState)
                StateManager.saveState(systemState)
                if command then
                    NetworkHandler.broadcast(command)
                end
            end
        end
    end
end

local function runNetworkListener()
    while true do
        local event, senderId, message, protocol = os.pullEvent("rednet_message")
        
        if protocol == Config.PROTOCOL then
            local updated = NetworkHandler.handleMessage(systemState, message)
            
            if updated then
                -- Update displays after message handling
                UtilityDisplay.draw(systemState, persistentMetrics)
                MovementDisplay.draw(systemState)
                StateManager.saveState(systemState)
            end
        end
        sleep(0.05)
    end
end

local function runPeriodicTasks()
    local saveTimer = os.startTimer(30)
    local statusTimer = os.startTimer(10)
    local refreshTimer = os.startTimer(2)

    -- Kick off initial status queries
    NetworkHandler.broadcast({ cmd = "queryFacing", secret = Config.SECRET })
    NetworkHandler.broadcast({ cmd = "queryOrientation", secret = Config.SECRET })

    while true do
        local event, timerId = os.pullEvent("timer")

        if timerId == saveTimer then
            StateManager.saveMetrics(persistentMetrics)
            saveTimer = os.startTimer(30)

        elseif timerId == statusTimer then
            -- Poll orientation/status from readers and controllers
            NetworkHandler.broadcast({ cmd = "queryStatus", secret = Config.SECRET })
            statusTimer = os.startTimer(10)

        elseif timerId == refreshTimer then
            -- General periodic sync with other controllers
            NetworkHandler.broadcast({ cmd = "queryFacing", secret = Config.SECRET })
            NetworkHandler.broadcast({ cmd = "queryOrientation", secret = Config.SECRET })
            refreshTimer = os.startTimer(2)
        end
        sleep(0.05)
    end
end

-- ========== Main Function ==========
local function main()
    print("ODMK3 Unified Command Center starting...")
    
    if not NetworkHandler.openAllModems() then
        error("No wireless modem found!")
    end
    
    if not findMonitors() then
        error("Required monitors not found! Need monitors on back and left sides.")
    end
    
    -- Initial display
    UtilityDisplay.draw(systemState, persistentMetrics)
    MovementDisplay.draw(systemState)
    
    print("Unified Command Center online")
    print("- Utility Monitor (back): Monitoring + Collection Controls")  
    print("- Movement Monitor (left): Movement Controls")
    
    -- Run all subsystems concurrently (single process, reliable across all systems)
    parallel.waitForAll(
        runMonitorInputs,
        runNetworkListener,
        runPeriodicTasks
    )
end

-- ========== Startup ==========
main()
