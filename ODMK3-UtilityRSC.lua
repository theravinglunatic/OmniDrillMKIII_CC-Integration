-- ODMK3-UtilityRSC.lua
-- Control a Create Rotational Speed Controller (RSC) placed on the RIGHT of this computer.
-- Requirement:
--  - Facing North or East  -> set speed to  128 RPM
--  - Facing South or West  -> set speed to -128 RPM

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local NAME     = "odmk3-utility-rsc"
local SECRET   = ""   -- optional shared secret
local DEBUG    = false -- Set true for verbose logs

-- ========== Utilities ==========
local function debugPrint(msg)
	if DEBUG then print("[DEBUG] " .. msg) end
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

-- ========== Peripheral Discovery ==========
local function findRSC()
	-- Prefer the unit on the RIGHT as specified
	local p = peripheral.wrap("right")
	if p and type(p.setTargetSpeed) == "function" then return p end

	-- Fallback: attempt by type name(s) if right wrapping failed
	local try = peripheral.find("rotational_speed_controller")
			or peripheral.find("rotation_speed_controller")
			or peripheral.find("rotationSpeedController")
	if try and type(try.setTargetSpeed) == "function" then return try end

	return nil
end

-- ========== RSC Control ==========
local rsc = findRSC()

local function applyFacingSpeed(facing)
	if not rsc then return end
	if not facing then return end

	local target
	if facing == "N" or facing == "E" then
		target = 128
	elseif facing == "S" or facing == "W" then
		target = -128
	else
		return
	end

	local ok, err = pcall(function()
		local current = nil
		if type(rsc.getTargetSpeed) == "function" then
			current = rsc.getTargetSpeed()
		end
		if current ~= target then
			rsc.setTargetSpeed(target)
			print(("RSC speed set to %d RPM (facing %s)"):format(target, facing))
		else
			debugPrint(("RSC already at %d RPM for facing %s"):format(target, facing))
		end
	end)
	if not ok then
		print("Failed to set RSC speed: " .. tostring(err))
	end
end

-- ========== Main ==========
local function main()
	if not rsc then
		print("Rotation Speed Controller not found on 'right' or attached; aborting.")
		return
	end

	if not openWireless() then
		print("No wireless modem found; listening disabled (no orientation updates).")
	end

	print("Utility RSC controller initialized")

	-- Startup sync: small delay to avoid race, then ask for current facing
	sleep(1.0)
	if rednet.isOpen() then
		debugPrint("Requesting current cardinal facing")
		rednet.broadcast({ cmd = "queryFacing", name = "odmk3-cardinal-reader", secret = SECRET }, PROTOCOL)
	end

	local timerId = os.startTimer(10) -- periodic keepalive; can be used to re-query if desired

	while true do
		local e, p1, p2, p3 = os.pullEvent()

		if e == "rednet_message" then
			local sender, msg, proto = p1, p2, p3
			if proto == PROTOCOL and type(msg) == "table" then
				if SECRET ~= "" and msg.secret ~= SECRET then
					-- ignore secret mismatch
				elseif msg.type == "facing" and msg.name == "odmk3-cardinal-reader" and msg.facing then
					debugPrint("Facing update: " .. tostring(msg.facing))
					applyFacingSpeed(msg.facing)
				end
			end

		elseif e == "timer" and p1 == timerId then
			-- Optional: re-query facing periodically to stay in sync after chunk moves
			if rednet.isOpen() then
				rednet.broadcast({ cmd = "queryFacing", name = "odmk3-cardinal-reader", secret = SECRET }, PROTOCOL)
			end
			timerId = os.startTimer(10)
		end
	end
end

-- ========== Startup ==========
main()
