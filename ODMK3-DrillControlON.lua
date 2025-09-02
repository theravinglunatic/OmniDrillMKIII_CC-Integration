-- ODMK3-DrillControlON.lua
-- Controls the drill by emitting a redstone pulse on the back side when triggered
-- Listens for commands from DriveController and activates drill before movement

local NAME = "odmk3-drill-control"
local PROTOCOL = "Omni-DrillMKIII"  -- Same protocol as other components
local SECRET = ""                  -- Keep empty to disable, or match with other components
local PULSE_DURATION = 0.3         -- Duration of the pulse in seconds
local DEBUG = true                 -- Set to false to disable debug messages

-- Function to emit a redstone pulse
local function pulseDrill()
    if DEBUG then print("[DEBUG] Activating drill - sending ON pulse") end
    
    -- Output redstone signal on the back side
    redstone.setOutput("back", true)
    sleep(PULSE_DURATION)
    redstone.setOutput("back", false)
    
    if DEBUG then print("[DEBUG] Drill activation pulse complete") end
    return true
end

-- Utility: open any connected modems (wired or wireless)
local function openAllModems()
	for _, side in ipairs(rs.getSides()) do
		if peripheral.getType(side) == "modem" then
			if not rednet.isOpen(side) then
				pcall(function() rednet.open(side) end)
				if DEBUG then print("[DEBUG] Opened modem on " .. side) end
			end
		end
	end
end

-- Main function to listen for activation commands
local function main()
    openAllModems()
    
    print("ODMK3-DrillControlON initialized")
    if DEBUG then print("[DEBUG] Listening for activation commands on protocol: " .. PROTOCOL) end
    
    while true do
        local event, sender, message, protocol = os.pullEvent("rednet_message")
        
        -- Check if this is a valid activation message
        if protocol == PROTOCOL and type(message) == "table" then
            -- Verify secret if needed
            if SECRET ~= "" and message.secret ~= SECRET then
                -- ignore messages with wrong secret
                if DEBUG then print("[DEBUG] Received message with invalid secret") end
            elseif message.name == NAME and message.cmd == "activate" then
                -- Handle activation command
                if DEBUG then print("[DEBUG] Received activation command from " .. tostring(sender)) end
                pulseDrill()
            end
        end
    end
end

-- Start the main function
main()
