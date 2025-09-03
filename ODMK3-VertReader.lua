-- ODMK3-VertReader.lua
-- Detect machine vertical orientation from redstone inputs 
-- (front=Forward, down=Up, up=Down)
-- Periodically broadcast orientation + respond to direct orientation queries.

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local NAME     = "odmk3-vert-reader"
local SECRET   = ""  -- optional shared secret must match controller/rotater if set
local DEBUG = false  -- Set to true to enable debug messages
local ROTATER_NAME = "odmk3-vert-rotater" -- notify rotater too

-- ========== Utilities ==========
local function debugPrint(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

local sides = rs.getSides()

local function openWireless()
	for _, side in ipairs(sides) do
		if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
			if not rednet.isOpen(side) then rednet.open(side) end
			return true
		end
	end
	return false
end

local function detectOrientation()
	-- For vertical orientation:
	-- Redstone on front -> Forward facing
	-- Redstone on bottom -> Up facing
	-- Redstone on top -> Down facing
	if redstone.getInput("front") then return "F" end  -- Forward
	if redstone.getInput("bottom")  then return "U" end  -- Up
	if redstone.getInput("top")    then return "D" end  -- Down
	return nil
end

local function broadcastOrientation(orientation)
	rednet.broadcast({ type="orientation", name=NAME, orientation=orientation, secret=SECRET }, PROTOCOL)
end

local function main()
	if not openWireless() then
		print("No wireless modem found; aborting.")
		return
	end
	print("Vertical Reader initialized")
	local lastOrientation = detectOrientation()
	if lastOrientation then 
		debugPrint("Initial orientation: " .. lastOrientation)
		broadcastOrientation(lastOrientation)
	else
		print("Warning: Orientation unknown!")
	end
	
	local timerId = os.startTimer(1)
	
	while true do
		local e, p1, p2, p3 = os.pullEvent()
		
		if e == "timer" and p1 == timerId then
			-- Regular polling
			local o = detectOrientation()
			if o and o ~= lastOrientation then
				print("Orientation changed to: " .. o)
				broadcastOrientation(o)
				lastOrientation = o
			end
			timerId = os.startTimer(1)
			
		elseif e == "rednet_message" then
			-- Handle queries
			local sender, msg, proto = p1, p2, p3
			if proto == PROTOCOL and type(msg)=="table" then
				if SECRET ~= "" and msg.secret ~= SECRET then
					-- ignore secret mismatch
				elseif msg.cmd == "queryOrientation" then
					local o = detectOrientation() or lastOrientation
					if o then 
						rednet.send(sender, { type="orientation", name=NAME, orientation=o, secret=SECRET }, PROTOCOL)
					end
				end
			end
			
		elseif e == "redstone" then
			-- Immediate check on redstone change
			local o = detectOrientation()
			if o and o ~= lastOrientation then
				print("Orientation changed to: " .. o)
				lastOrientation = o
				broadcastOrientation(o)
			end
		end
	end
end

-- ========== Startup ==========
main()

