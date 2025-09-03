-- ODMK3-DriveHelper.lua
-- Monitors redstone signal on back face and outputs a delayed pulse on front face

-- ========== Configuration ==========
local DEBUG = false                    -- Enable debug output
local INPUT_SIDE = "back"            -- Side to monitor for input signal
local OUTPUT_SIDE = "front"          -- Side to output the pulse
local DELAY_SECONDS = 1.2            -- Delay between input and output pulse
local PULSE_LENGTH = 0.1             -- How long the output pulse should last

-- ========== State Tracking ==========
local lastInputState = false

-- ========== Utilities ==========
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

-- Function to generate a redstone pulse
local function pulse(side, duration)
    redstone.setOutput(side, true)
    debugPrint("Set redstone output on " .. side .. " to ON")
    os.sleep(duration)
    redstone.setOutput(side, false)
    debugPrint("Set redstone output on " .. side .. " to OFF")
end

-- ========== Main Function ==========
local function main()
    print("ODMK3-DriveHelper initialized")
    debugPrint("Monitoring redstone signal on " .. INPUT_SIDE)
    debugPrint("Will output pulses on " .. OUTPUT_SIDE)
    
    -- Initialize output to OFF
    redstone.setOutput(OUTPUT_SIDE, false)
    debugPrint("Initialized redstone output on " .. OUTPUT_SIDE .. " to OFF")
    
    -- Check if there's already a signal at startup
    local initialState = redstone.getInput(INPUT_SIDE)
    lastInputState = initialState
    
    if initialState then
        debugPrint("Redstone signal already active on " .. INPUT_SIDE .. " at startup")
        debugPrint("Waiting " .. DELAY_SECONDS .. " seconds before sending pulse")
        os.sleep(DELAY_SECONDS)
        pulse(OUTPUT_SIDE, PULSE_LENGTH)
    end
    
    -- Main loop
    while true do
        local currentState = redstone.getInput(INPUT_SIDE)
        
        -- If signal changes from OFF to ON
        if currentState and not lastInputState then
            debugPrint("Redstone signal detected on " .. INPUT_SIDE)
            debugPrint("Waiting " .. DELAY_SECONDS .. " seconds before sending pulse")
            os.sleep(DELAY_SECONDS)
            pulse(OUTPUT_SIDE, PULSE_LENGTH)
        end
        
        lastInputState = currentState
        os.sleep(0.05) -- Small sleep to prevent CPU hogging
    end
end

-- ========== Startup ==========
main()