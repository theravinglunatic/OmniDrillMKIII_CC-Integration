-- ODMK3-CardinalReader.lua
-- Detect machine facing from redstone inputs (front=North, left=East, back=South, right=West)
-- Periodically broadcast facing + respond to direct facing queries.

local PROTOCOL = "Omni-DrillMKIII"
local NAME     = "odmk3-cardinal-reader"
local SECRET   = ""  -- optional shared secret must match controller/rotater if set
local ROTATER_NAME = "odmk3-cardinal-rotater" -- notify rotater too

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

local function detectFacing()
	if redstone.getInput("front") then return "N" end
	if redstone.getInput("left")  then return "E" end
	if redstone.getInput("back")  then return "S" end
	if redstone.getInput("right") then return "W" end
	return nil
end

local function broadcastFacing(facing)
	rednet.broadcast({ type="facing", name=NAME, facing=facing, secret=SECRET }, PROTOCOL)
end

local function main()
	if not openWireless() then
		print("No wireless modem found; aborting.")
		return
	end
	print("Cardinal Reader online.")
	local lastFacing = detectFacing()
	if lastFacing then 
		print("Initial facing: " .. lastFacing)
		broadcastFacing(lastFacing)
	end
	
	local timerId = os.startTimer(1)
	
	while true do
		local e, p1, p2, p3 = os.pullEvent()
		
		if e == "timer" and p1 == timerId then
			-- Regular polling
			local f = detectFacing()
			if f and f ~= lastFacing then
				print("Facing changed to: " .. f)
				broadcastFacing(f)
				lastFacing = f
			end
			timerId = os.startTimer(1)
			
		elseif e == "rednet_message" then
			-- Handle queries
			local sender, msg, proto = p1, p2, p3
			if proto == PROTOCOL and type(msg)=="table" then
				if SECRET ~= "" and msg.secret ~= SECRET then
					-- ignore secret mismatch
				elseif msg.cmd == "queryFacing" then
					local f = detectFacing() or lastFacing
					if f then 
						rednet.send(sender, { type="facing", name=NAME, facing=f, secret=SECRET }, PROTOCOL)
					end
				end
			end
			
		elseif e == "redstone" then
			-- Immediate check on redstone change
			local f = detectFacing()
			if f and f ~= lastFacing then
				print("Facing changed to: " .. f)
				lastFacing = f
				broadcastFacing(f)
			end
		end
	end
end

main()
