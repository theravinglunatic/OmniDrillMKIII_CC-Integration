-- ODMK3-CardinalRotater.lua
-- Receives setFacing commands, consults Reader (or local redstone) to know current facing, rotates minimal degrees.
-- Rotation API assumed similar to SGS examples: rotate(angle[, directionSign]) where directionSign -1 = opposite direction.

local PROTOCOL       = "Omni-DrillMKIII"
local NAME           = "odmk3-cardinal-rotater"
local SECRET         = "" -- optional shared secret
local READER_NAME    = "odmk3-cardinal-reader"  -- source of facing updates
local ROTATE_PERIPH  = nil  -- set explicit peripheral name with rotate() if desired
local QUERY_INTERVAL = 5

-- Debug configuration
local DEBUG_ASSUME_FACING = false    -- If true, assumes North facing when CardinalReader not found
local DEBUG_ASSUMED_FACING = "N"     -- The facing to assume when DEBUG_ASSUME_FACING is true

-- Map facing order clockwise
local ORDER = {"N","E","S","W"}
local INDEX = { N=1, E=2, S=3, W=4 }

local function openWireless()
	for _, side in ipairs(rs.getSides()) do
		if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
			if not rednet.isOpen(side) then rednet.open(side) end
			return true
		end
	end
	return false
end

local function findRotator()
	if ROTATE_PERIPH then
		local p = peripheral.wrap(ROTATE_PERIPH)
		if p and type(p.rotate)=="function" then return p end
	end
	for _, n in ipairs(peripheral.getNames()) do
		local p = peripheral.wrap(n)
		if type(p)=="table" and type(p.rotate)=="function" then return p end
	end
	return nil
end

local function currentFacingFromRedstone()
	if redstone.getInput("front") then return "N" end
	if redstone.getInput("left") then return "E" end
	if redstone.getInput("back") then return "S" end
	if redstone.getInput("right") then return "W" end
	return nil
end

-- Start with unknown facing until detected via redstone or network
local lastFacing = nil
local facingConfirmed = false

local function broadcastFacing(f)
	rednet.broadcast({ type="facing", name=NAME, facing=f, secret=SECRET }, PROTOCOL)
end

-- Request current facing from CardinalReader
local function queryCardinalFacing()
	print("Requesting current cardinal facing")
	rednet.broadcast({
		name = READER_NAME,
		cmd = "queryFacing",
		secret = SECRET
	}, PROTOCOL)
end

local function computeRotation(from, to)
	if from == to then return 0, 1, "none" end
	local fi = INDEX[from]; local ti = INDEX[to]
	if not fi or not ti then return 0,1,"invalid" end
	
	print("Computing rotation from " .. from .. " to " .. to)
	local diff = (ti - fi) % 4  -- 0..3 steps clockwise (90° each)
	print("Difference: " .. diff)
	
	if diff == 1 then 
		print("Rotating +90 degrees clockwise")
		return 90, 1, "+90" 
	elseif diff == 2 then 
		print("Rotating 180 degrees")
		return 180, 1, "180" 
	elseif diff == 3 then 
		print("Rotating -90 degrees (counter-clockwise)")
		return 90, -1, "-90" 
	end
	
	return 0,1,"none"
end

local function rotateTo(rotator, target)
	local before = lastFacing
	if not before then
		print("Error: Can't rotate - current facing unknown")
		return false, nil, nil, "current facing unknown"
	end
	
	print("Attempting to rotate from " .. before .. " to " .. target)
	local degrees, dirSign, action = computeRotation(before, target)
	
	if degrees == 0 then
		print("No rotation needed, already facing " .. target)
		return true, before, before, action
	end
	
	print("Will rotate " .. degrees .. " degrees, direction: " .. (dirSign == 1 and "clockwise" or "counter-clockwise"))
	
	local success = false
	
	-- For 180 degree rotations, try different approaches
	if degrees == 180 then
		print("Executing 180 degree rotation")
		
		-- First attempt: Try a direct 180 rotation
		local ok1 = pcall(function() rotator.rotate(180) end)
		os.sleep(1)
		
		if ok1 then
			print("Direct 180 degree rotation attempt completed")
			success = true
		else
			-- Second attempt: Try two separate 90 degree rotations with longer pause
			print("Direct rotation failed, trying sequential 90 degree rotations")
			
			local ok2 = pcall(function()
				rotator.rotate(90)
				os.sleep(1.5) -- Longer delay between rotations
				rotator.rotate(90)
				os.sleep(1)
			end)
			
			if ok2 then
				print("Sequential 90 degree rotations completed")
				success = true
			end
		end
	else
		-- Regular 90 degree rotation
		local ok = pcall(function()
			if dirSign == -1 then 
				print("Executing 90 degree counter-clockwise rotation")
				rotator.rotate(90, -1) 
			else 
				print("Executing 90 degree clockwise rotation")
				rotator.rotate(90) 
			end
			os.sleep(1) -- Added sleep to ensure rotation completes
		end)
		
		success = ok
	end
	
	if not success then
		print("Rotation failed to complete successfully")
		return false, before, before, "rotation failed" 
	end
	
	-- Update facing logically
	local bi = INDEX[before]
	local steps
	if degrees == 180 then 
		steps = 2 
	elseif dirSign == -1 then 
		steps = -1 
	else 
		steps = 1 
	end
	
	local ni = ((bi - 1 + steps) % 4) + 1
	lastFacing = ORDER[ni]
	print("Rotation complete, new facing: " .. lastFacing)
	
	-- Try to verify rotation success
	print("Checking redstone sensors to verify rotation...")
	local rf = currentFacingFromRedstone()
	if rf and rf ~= lastFacing then
		print("WARNING: Rotation verification failed! Sensors indicate " .. rf .. " instead of " .. lastFacing)
		lastFacing = rf -- Trust the sensors over the calculated position
		return true, before, lastFacing, "corrected-" .. action
	end
	
	return true, before, lastFacing, action
end

local function sendAck(to, ok, before, after, action, err, target)
	rednet.send(to, { type="rotateAck", ok=ok, before=before, after=after, action=action, err=err, targetDir=target, name=NAME, secret=SECRET }, PROTOCOL)
end

local function main()
	if not openWireless() then
		print("No wireless modem found; abort.")
		return
	end
	local rotator = findRotator()
	if not rotator then
		print("No peripheral with rotate() found; running in simulation.")
	end
	
	-- Try to detect facing from redstone first
	local rsFacing = currentFacingFromRedstone()
	if rsFacing then
		lastFacing = rsFacing
		facingConfirmed = true
		print("Cardinal Rotater online. Initial facing from redstone: " .. lastFacing)
	elseif DEBUG_ASSUME_FACING then
		lastFacing = DEBUG_ASSUMED_FACING
		facingConfirmed = true
		print("DEBUG MODE: Assuming " .. DEBUG_ASSUMED_FACING .. " facing")
		print("Cardinal Rotater online. Initial facing (assumed): " .. lastFacing)
	else
		print("Cardinal Rotater online. Warning: Facing unknown!")
		print("Sending query to CardinalReader...")
		-- Don't broadcast yet since we don't know our facing
	end
	
	-- Send initial query to reader
	print("Initializing... Querying cardinal reader")
	queryCardinalFacing()
	
	local timerId = os.startTimer(QUERY_INTERVAL)
	while true do
		local e, p1, p2, p3 = os.pullEvent()
		if e == "timer" and p1 == timerId then
			timerId = os.startTimer(QUERY_INTERVAL)
			-- Check redstone signals first
			local rf = currentFacingFromRedstone()
			if rf then
				if not lastFacing or rf ~= lastFacing then
					print("Facing updated from redstone: " .. rf)
					lastFacing = rf
					facingConfirmed = true
					if facingConfirmed then broadcastFacing(lastFacing) end
				end
			end
			
			-- Periodically ask Reader for updates
			queryCardinalFacing()
		elseif e == "rednet_message" then
			local sender, msg, proto = p1, p2, p3
			if proto == PROTOCOL and type(msg)=="table" then
				if SECRET ~= "" and msg.secret ~= SECRET then
					-- ignore
				elseif msg.cmd == "setFacing" and msg.target then
					-- Handle set facing requests
					print("Received setFacing command to " .. msg.target)
					if not lastFacing or not facingConfirmed then
						-- Can't rotate if we don't know current facing
						print("Can't rotate - current facing unknown!")
						sendAck(sender, false, nil, nil, nil, "Current facing unknown", msg.target)
					else
						local ok,before,after,action
						if rotator then
							print("Using physical rotator peripheral")
							ok,before,after,action = rotateTo(rotator, msg.target)
						else
							print("Using simulated rotation (no peripheral found)")
							local degrees, sign, act = computeRotation(lastFacing, msg.target)
							if degrees > 0 then
								print("Simulating rotation: " .. lastFacing .. " to " .. msg.target)
								ok = true; action = act; before = lastFacing; lastFacing = msg.target; after = lastFacing
							else
								print("No rotation needed - already facing target direction")
								ok = true; action = "none"; before = lastFacing; after = lastFacing;
							end
						end
						print("Sending ack: " .. (ok and "success" or "failure"))
						sendAck(sender, ok, before, after, action, ok and nil or action, msg.target)
						if ok then broadcastFacing(lastFacing) end
					end
				elseif msg.cmd == "queryFacing" then
					-- Only respond if we know our facing
					if facingConfirmed and lastFacing then
						broadcastFacing(lastFacing)
					end
				elseif msg.type == "facing" and msg.name == READER_NAME then
					-- Handle facing updates from CardinalReader
					if msg.facing then
						if not lastFacing or lastFacing ~= msg.facing then
							print("Facing updated from Reader: " .. msg.facing)
							if lastFacing then
								print("Note: Previous facing was " .. lastFacing .. ", reader correction applied")
							end
							lastFacing = msg.facing
							facingConfirmed = true
							broadcastFacing(lastFacing) -- Broadcast the corrected facing
						end
					end
				end
			end
		elseif e == "redstone" then
			-- Immediate update on redstone change
			local rf = currentFacingFromRedstone()
			if rf then
				if not lastFacing or rf ~= lastFacing then
					print("Facing changed via redstone: " .. rf)
					lastFacing = rf
					facingConfirmed = true
					broadcastFacing(lastFacing)
				end
			end
		end
	end
end

main()

