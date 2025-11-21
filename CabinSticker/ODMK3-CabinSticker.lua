-- ODMK3-CabinSticker.lua
-- Controls Create Sticker peripheral for cabin indicator
-- Sticker on left face, wireless modem on right face

local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""
local NAME = "odmk3-cabin-sticker"
local STICKER_SIDE = "left"
local DEBUG = true  -- Set true for verbose debug output

local function debugPrint(msg)
	if DEBUG then
		print("[DEBUG] " .. msg)
	end
end

local function openWirelessModem()
	local opened = false
	for _, side in ipairs(rs.getSides()) do
		if peripheral.getType(side) == "modem" then
			local isWireless = false
			pcall(function() isWireless = peripheral.call(side, "isWireless") end)
			if isWireless then
				if not rednet.isOpen(side) then
					pcall(function() rednet.open(side) end)
				end
				opened = true
				debugPrint("Wireless modem open on side: " .. side)
			end
		end
	end
	if not opened then debugPrint("No wireless modem opened this pass") end
	return opened
end

local function getSticker()
	local t = peripheral.getType(STICKER_SIDE)
	if not t then return nil end
	debugPrint("Sticker peripheral type detected: " .. tostring(t))
	return peripheral.wrap(STICKER_SIDE)
end

local function broadcastStatus(sticker)
	local okExtended = false
	local extended = false
	if sticker and sticker.isExtended then
		local ok, val = pcall(sticker.isExtended)
		if ok and type(val) == "boolean" then okExtended = true extended = val end
	end
	rednet.broadcast({
		type = "cabinStickerStatus",
		name = NAME,
		extended = okExtended and extended or nil,
		secret = SECRET
	}, PROTOCOL)
	if okExtended then
		debugPrint("Broadcast status; extended=" .. tostring(extended))
	else
		debugPrint("Broadcast status; sticker state unknown (peripheral missing or method unavailable)")
	end
end

local function handleCommand(sticker, msg)
	if msg.name == NAME and (msg.cmd == "retract" or msg.cmd == "extend") then
		if SECRET ~= "" and msg.secret ~= SECRET then return false end
		if not sticker then
			print("Sticker peripheral missing; cannot execute command")
			return false
		end
		local action = msg.cmd
		local fn = (action == "retract") and sticker.retract or sticker.extend
		if type(fn) == "function" then
			local ok, res = pcall(fn)
			print(string.format("Sticker %s %s", action, ok and "OK" or ("FAILED: " .. tostring(res))))
			debugPrint("Command executed: " .. action .. "; success=" .. tostring(ok))
		else
			print("Sticker method not available for action: " .. action)
			debugPrint("Method not available for action: " .. action)
		end
		broadcastStatus(sticker)
		return true
	elseif msg.name == NAME and msg.cmd == "status" then
		debugPrint("Status command received; broadcasting current state")
		broadcastStatus(sticker)
		return true
	end
	return false
end

local function main()
	print("Cabin Sticker controller starting...")
	print("DEBUG mode: " .. (DEBUG and "ON" or "OFF"))
	if not openWirelessModem() then
		print("No wireless modem found; retrying...")
		debugPrint("Entering modem retry loop")
		while not openWirelessModem() do sleep(2) end
	end
	local sticker = getSticker()
	if not sticker then
		print("Sticker peripheral not found on side '" .. STICKER_SIDE .. "'. Will continue listening and retry.")
		debugPrint("Sticker peripheral missing at startup")
	end
	pcall(function() rednet.host(PROTOCOL, NAME) end)
	debugPrint("Hosting rednet service (if supported) under name: " .. NAME)
	broadcastStatus(sticker)
	while true do
		local sender, msg, proto = rednet.receive(PROTOCOL, 2)
		if sender and proto == PROTOCOL and type(msg) == "table" then
			local handled = handleCommand(sticker, msg)
			if handled then
				-- Refresh sticker reference in case it was placed late
				sticker = sticker or getSticker()
				if sticker then debugPrint("Sticker peripheral reference confirmed/updated") end
			end
		else
			-- periodic status heartbeat
			debugPrint("Heartbeat interval reached; broadcasting status")
			broadcastStatus(sticker)
		end
	end
end

main()
