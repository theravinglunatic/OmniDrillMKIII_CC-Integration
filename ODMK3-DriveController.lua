-- ODMK3-DriveController.lua
-- Listens for move commands and emits redstone pulses directly from the computer.
-- Requirements:
-- 1. GUI (omni_gui) broadcasts { name = "odmk3-drive-controller", cmd = "move" } on protocol.
-- 2. On receipt, pulse BACK face briefly.
-- 3. On startup, pulse FRONT face once.

local NAME       = "odmk3-drive-controller"
local PROTOCOL   = "Omni-DrillMKIII"      -- Shared with GUI & other components
local SECRET     = ""                    -- Optional shared secret; leave blank to disable

-- Configuration
local MOVE_PULSE_TICKS = 0.3              -- Seconds to keep back on
local START_PULSE_TICKS = 0.25            -- Seconds for initial front pulse
local USE_PARALLEL_PULSE = false          -- If true, pulse top & bottom concurrently (not really needed)
local DEBUG = true                        -- Set to false to disable debug messages

-- State tracking
local vaultFull = false                   -- Track auxiliary vault status

-- Utility: open any connected modems (wired or wireless)
local function openAllModems()
	local modemFound = false
	for _, side in ipairs(rs.getSides()) do
		if peripheral.getType(side) == "modem" then
			if not rednet.isOpen(side) then
				pcall(function() rednet.open(side) end)
				if DEBUG then print("[DEBUG] Opened modem on " .. side) end
			end
			modemFound = true
		end
	end
	
	if not modemFound then
		print("[ERROR] No modem found! Please attach a modem to enable network communication.")
		print("[ERROR] DriveController will run in offline mode - no move commands will be received.")
		return false
	end
	
	return true
end

local function pulse(side, duration)
	if not side then return end
	if DEBUG then print("[DEBUG] Pulsing redstone on " .. side .. " for " .. tostring(duration) .. "s") end
	redstone.setOutput(side, true)
	sleep(duration or 0)
	redstone.setOutput(side, false)
	if DEBUG then print("[DEBUG] Pulse complete on " .. side) end
end

local function activateDrill()
    -- Call the DrillControlON script on computer 21
    if DEBUG then print("[DEBUG] Calling DrillControlON script") end
    
    -- Use shell command to run the script on computer 21
    local success, result = pcall(function()
        -- Send rednet message to computer 21 to activate the drill
        rednet.broadcast({
            name = "odmk3-drill-control",
            cmd = "activate",
            secret = ""
        }, PROTOCOL)
        
        -- Brief pause to allow drill to activate
        sleep(0.1)
    end)
    
    if not success then
        if DEBUG then print("[DEBUG] Failed to activate drill: " .. tostring(result)) end
    end
    
    return success
end

local function movePulse()
    -- First activate the drill
    activateDrill()
    
	if USE_PARALLEL_PULSE then
		parallel.waitForAll(
			function() pulse("back", MOVE_PULSE_TICKS) end
		)
	else
		redstone.setOutput("back", true)
		sleep(MOVE_PULSE_TICKS)
		redstone.setOutput("back", false)
	end
end

local function sendMoveAck(ok, err)
	local msg = {
		type = "moveAck",
		ok = ok and true or false,
		err = err,
		secret = (SECRET ~= "" and SECRET or nil),
	}
	rednet.broadcast(msg, PROTOCOL)
end

local function handleMessage(sender, payload, proto)
	if proto ~= PROTOCOL then return end
	if type(payload) ~= "table" then return end
	if payload.name ~= NAME then return end
	if SECRET ~= "" and payload.secret ~= SECRET then return end

	local cmd = payload.cmd
	if cmd == "move" then
		-- Check if vault is full before executing movement
		if vaultFull then
			if DEBUG then print("[DEBUG] Move command blocked - auxiliary vault is full") end
			sendMoveAck(false, "vault full - movement blocked")
			return
		end
		
		-- Execute movement pulse
		if DEBUG then print("[DEBUG] Received move command from " .. tostring(sender)) end
		local ok, err = pcall(movePulse)
		if DEBUG then print("[DEBUG] Move pulse " .. (ok and "succeeded" or "failed: " .. tostring(err))) end
		sendMoveAck(ok, ok and nil or (err or "pulse error"))
	end
end

local function startupPulse()
	pulse("front", START_PULSE_TICKS)
end

local function main()
	local hasModem = openAllModems()
	startupPulse()
	
	if not hasModem then
		print("[ERROR] Running in offline mode - manual redstone pulses only")
		print("[ERROR] Please attach a modem and restart to enable network functionality")
		-- Still run the startup pulse but skip network operations
		while true do
			local e = os.pullEvent()
			if e == "terminate" then
				break
			end
			-- Could add manual redstone controls here if needed
		end
		return
	end
	
	-- Optionally announce presence (not required)
	-- rednet.broadcast({ type="presence", role=NAME, secret=(SECRET~="" and SECRET or nil) }, PROTOCOL)
	
	-- Query vault status from auxiliary vault threshold monitor
	if DEBUG then print("[DEBUG] Querying auxiliary vault status...") end
	rednet.broadcast({
		name = "odmk3-aux-vault-threshold",
		cmd = "status",
		secret = ""
	}, PROTOCOL)
	
	if DEBUG then print("[DEBUG] " .. NAME .. " ready and listening on " .. PROTOCOL) end

	while true do
		local e, p1, p2, p3 = os.pullEvent()
		if e == "rednet_message" then
			local sender, payload, proto = p1, p2, p3
			if proto == PROTOCOL and type(payload) == "table" then
				-- Handle vault status messages
				if payload.type == "vaultStatus" and (SECRET == "" or payload.secret == SECRET) then
					local wasVaultFull = vaultFull
					vaultFull = payload.vaultFull or false
					if wasVaultFull ~= vaultFull then
						if DEBUG then print("[DEBUG] Vault status updated: " .. (vaultFull and "FULL - moves blocked" or "AVAILABLE - moves allowed")) end
					end
				else
					-- Handle other messages (move commands, etc.)
					handleMessage(sender, payload, proto)
				end
			end
		elseif e == "terminate" then
			break
		end
	end
end

main()

