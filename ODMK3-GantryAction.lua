-- ODMK3-GantryAction
-- Omni-Drill MKIII: Gantry Action Controller
-- Monitors front redstone signal and uses Sequenced Gearshift peripheral to control gantry movement

-- ========== Configuration ==========
local DEBUG = true                  -- Enable debug output
local GANTRY_DISTANCE = 11          -- Distance in meters for gantry to move
local REDSTONE_CHECK_DELAY = 0.1    -- Seconds between redstone checks
local GEARSHIFT_PERIPHERAL = nil    -- Set to specific name if needed, or leave nil to auto-detect

-- ========== State Tracking ==========
local lastRedstoneStates = {        -- Last known state of redstone inputs
    bottom = false,
    left = false,
    right = false
}
local isExecutingAction = false     -- Whether we're currently executing a movement sequence
local gearshift = nil              -- Will hold the peripheral reference

-- Function to check if any monitored redstone input is active
local function isRedstoneActive()
    return redstone.getInput("bottom") or redstone.getInput("left") or redstone.getInput("right")
end

-- Function to get current redstone states
local function getCurrentRedstoneStates()
    return {
        bottom = redstone.getInput("bottom"),
        left = redstone.getInput("left"),
        right = redstone.getInput("right")
    }
end

-- Function to detect rising edge on any monitored face
local function detectRisingEdge(currentStates, lastStates)
    for face, currentState in pairs(currentStates) do
        if currentState and not lastStates[face] then
            return true, face
        end
    end
    return false, nil
end

-- ========== Utilities ==========
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

-- Find and connect to the Sequenced Gearshift peripheral
local function findGearshift()
    -- Try by specific name first if provided
    if GEARSHIFT_PERIPHERAL then
        local p = peripheral.wrap(GEARSHIFT_PERIPHERAL)
        if p and type(p.move) == "function" then 
            debugPrint("Found gearshift peripheral by name: " .. GEARSHIFT_PERIPHERAL)
            return p 
        end
    end
    
    -- Try specific side (back)
    local p = peripheral.wrap("back")
    if p and type(p.move) == "function" then
        debugPrint("Found gearshift peripheral on back side")
        return p
    end
    
    -- Look for any peripheral with move() function
    debugPrint("Searching for any sequenced gearshift peripheral...")
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if p and type(p.move) == "function" then
            debugPrint("Found gearshift peripheral: " .. name)
            return p
        end
    end
    
    debugPrint("ERROR: No peripheral with move() function found!")
    return nil
end

local function connectToGearshift()
    gearshift = findGearshift()
    if not gearshift then
        return false
    end
    debugPrint("Successfully connected to Sequenced Gearshift peripheral")
    return true
end

-- Execute the full gantry movement sequence
local function executeGantrySequence()
    if isExecutingAction then return end  -- Prevent overlapping executions
    
    -- Try to get gearshift if we don't have it yet
    if not gearshift then
        if not connectToGearshift() then
            debugPrint("Gantry sequence aborted: No gearshift peripheral available")
            return -- Can't continue without gearshift
        end
    end
    
    -- Double check that we have a valid gearshift object with the move function
    if not gearshift or type(gearshift.move) ~= "function" then
        debugPrint("ERROR: Invalid gearshift peripheral (missing move function)")
        gearshift = nil  -- Reset so we try to reconnect next time
        return
    end
    
    isExecutingAction = true
    debugPrint("Starting gantry sequence - forward " .. GANTRY_DISTANCE .. "m then backward")
    
    -- Forward motion
    debugPrint("Moving gantry forward by " .. GANTRY_DISTANCE .. "m")
    gearshift.move(GANTRY_DISTANCE, 1) -- positive modifier for forward motion
    
    -- Wait for forward movement to complete
    while gearshift.isRunning() do
        debugPrint("Waiting for forward movement to complete...")
        sleep(0.2)
    end
    debugPrint("Forward movement complete")
    
    -- Reverse motion
    debugPrint("Moving gantry backward by " .. GANTRY_DISTANCE .. "m")
    gearshift.move(GANTRY_DISTANCE, -1) -- negative modifier for backward motion
    
    -- Wait for backward movement to complete
    while gearshift.isRunning() do
        debugPrint("Waiting for backward movement to complete...")
        sleep(1)
    end
    debugPrint("Backward movement complete")
    
    debugPrint("Gantry sequence complete")
    isExecutingAction = false
end

-- Initialize state by getting current redstone inputs
lastRedstoneStates = getCurrentRedstoneStates()

-- Try to connect to the gearshift peripheral
if connectToGearshift() then
    debugPrint("Successfully connected to Sequenced Gearshift at startup")
else
    debugPrint("WARNING: Could not connect to Sequenced Gearshift at startup")
    debugPrint("Will try to reconnect when needed")
end

-- List all connected peripherals for debugging
debugPrint("Available peripherals:")
for i, name in ipairs(peripheral.getNames()) do
    local pType = peripheral.getType(name)
    debugPrint("  - " .. name .. " (" .. pType .. ")")
end

local function formatRedstoneStates(states)
    return string.format("bottom=%s, left=%s, right=%s", 
        states.bottom and "ON" or "OFF",
        states.left and "ON" or "OFF", 
        states.right and "ON" or "OFF")
end

debugPrint("Initialized - redstone states: " .. formatRedstoneStates(lastRedstoneStates))

-- Handle case where redstone is already active at startup
if isRedstoneActive() then
    debugPrint("Redstone signal already active at startup")
    debugPrint("Executing gantry sequence after 0.2-second delay...")
    sleep(0.2) -- Short delay to allow system to fully initialize
    executeGantrySequence()
end

debugPrint("Waiting for redstone signal on bottom, left, or right faces")

-- Main loop to monitor redstone state
while true do
    local currentRedstoneStates = getCurrentRedstoneStates()
    
    -- Detect rising edge (signal went from OFF to ON on any monitored face)
    local risingEdge, triggeredFace = detectRisingEdge(currentRedstoneStates, lastRedstoneStates)
    if risingEdge then
        debugPrint("Redstone signal detected on " .. triggeredFace .. " face")
        executeGantrySequence()
    end
    
    -- Periodically check if we need to reconnect to the peripheral
    if not gearshift and math.random(1, 50) == 1 then  -- Try reconnect occasionally
        debugPrint("Attempting to reconnect to gearshift peripheral...")
        connectToGearshift()
    end
    
    lastRedstoneStates = currentRedstoneStates
    sleep(REDSTONE_CHECK_DELAY)
end
