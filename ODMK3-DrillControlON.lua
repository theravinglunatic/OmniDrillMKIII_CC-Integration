-- ODMK3-DrillControlON.lua
-- Controls the drill by emitting a redstone pulse on the back side when triggered
-- Listens for commands from DriveController and activates drill before movement

-- ========== Configuration ==========
local NAME = "odmk3-drill-control"
local PROTOCOL = "Omni-DrillMKIII"  -- Same protocol as other components
local SECRET = ""                  -- Keep empty to disable, or match with other components
local DEBUG = true                 -- Set to false to disable debug messages
local PULSE_DURATION = 0.3         -- Duration of the pulse in seconds

-- ========== Utilities ==========
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

-- Function to emit a redstone pulse
local function pulseDrill()
    debugPrint("Activating drill - sending ON pulse")
    
    -- Output redstone signal on the back side
    redstone.setOutput("back", true)
    sleep(PULSE_DURATION)
    redstone.setOutput("back", false)
    
    debugPrint("Drill activation pulse complete")
    return true
end

-- Utility: open any connected modems (wired or wireless)
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

-- ========== Main Function ==========
local function main()
    openAllModems()
    
    print("ODMK3-DrillControlON initialized")
    debugPrint("Listening for activation commands on protocol: " .. PROTOCOL)
    
    while true do
        local event, sender, message, protocol = os.pullEvent("rednet_message")
        
        -- Check if this is a valid activation message
        if protocol == PROTOCOL and type(message) == "table" then
            -- Verify secret if needed
            if SECRET ~= "" and message.secret ~= SECRET then
                -- ignore messages with wrong secret
                debugPrint("Received message with invalid secret")
            elseif message.name == NAME and message.cmd == "activate" then
                -- Handle activation command
                debugPrint("Received activation command from " .. tostring(sender))
                pulseDrill()
            end
        end
    end
end

-- ========== Startup ==========
main()
