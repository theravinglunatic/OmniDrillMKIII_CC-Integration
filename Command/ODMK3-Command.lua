-- ODMK3-Command.lua (Pocket Primary)
-- Primary Command & Control running on a pocket computer
-- Combines operator UI with network authority and watchdog duties

-- ========== Load Modules ==========
local Config = require("modules.config")
local StateManager = require("modules.state_manager")
local NetworkHandler = require("modules.network_handler")

-- ========== State Initialization ==========
local systemState, persistentMetrics = StateManager.initialize()

-- ========== Utilities ==========
local function debugPrint(msg)
	if Config.DEBUG then print("[DEBUG] " .. msg) end
end

local function openWirelessModem()
	return NetworkHandler.openAllModems()
end

-- Relative rotation helper for cardinal facing
local function rotateCardinal(current, delta)
	if type(current) ~= "string" then return nil end
	local order = { "N", "E", "S", "W" }
	local idx = nil
	local map = { N = 1, E = 2, S = 3, W = 4 }
	idx = map[current]
	if not idx then return nil end
	local newIdx = ((idx - 1 + delta) % 4) + 1
	return order[newIdx]
end

-- Next vertical orientation in cycle F -> U -> D -> F
local function nextVertical(current)
	if current == "F" then return "U" end
	if current == "U" then return "D" end
	return "F"
end

-- ========== Service Hosting ==========
local function hostService()
	pcall(function()
		rednet.host(Config.PROTOCOL, "odmk3-command-center")
	end)
end

-- ========== UI (Pocket) ==========
local C = Config.colors

local currentPage = 1  -- 1=Movement, 2=Collection, 3=Vault
local totalPages = 3
local buttons = {}
local layoutVaultPage -- forward declaration

local function clearButtons()
	buttons = {}
end

local function addButton(id, label, x1, y1, x2, y2, bg)
	table.insert(buttons, {
		id = id, label = label,
		x1 = x1, y1 = y1, x2 = x2, y2 = y2,
		bg = bg or C.btnBg, fg = C.btnFg, hot = false
	})
end

local function pointInButton(b, x, y)
	return x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2
end

local function drawButton(b)
	local bg = b.hot and C.btnHi or b.bg
	term.setBackgroundColor(bg)
	term.setTextColor(b.fg)
	for y = b.y1, b.y2 do
		term.setCursorPos(b.x1, y)
		term.write(string.rep(" ", b.x2 - b.x1 + 1))
	end
	local lines = {}
	for part in string.gmatch(b.label, "[^\n]+") do table.insert(lines, part) end
	local boxH = b.y2 - b.y1 + 1
	local boxW = b.x2 - b.x1 + 1
	local startY = b.y1 + math.floor((boxH - #lines) / 2)
	for i, line in ipairs(lines) do
		local x = b.x1 + math.floor((boxW - #line) / 2)
		term.setCursorPos(x, startY + i - 1)
		term.setBackgroundColor(bg)
		term.write(line)
	end
end

local function drawHeader()
	local w, h = term.getSize()
	term.setBackgroundColor(C.title)
	term.setTextColor(C.bg)
	term.setCursorPos(1, 1)
	term.clearLine()
	local title = "OMNI-DRILL COMMAND"
	if currentPage == 1 then
		title = "MOVEMENT"
	elseif currentPage == 2 then
		title = "CONTROLS"
	elseif currentPage == 3 then
		title = "VAULT INVENTORY"
	end
	local x = math.floor((w - #title) / 2) + 1
	term.setCursorPos(x, 1)
	term.write(title)

	term.setCursorPos(1, 2)
	term.setBackgroundColor(C.bg)
	term.setTextColor(C.good)
	term.clearLine()
	local status = "Page " .. currentPage .. "/" .. totalPages
	local sX = math.floor((w - #status) / 2) + 1
	term.setCursorPos(sX, 2)
	term.write(status)
end

local function drawFooter()
	local w, h = term.getSize()
	term.setBackgroundColor(C.bg)
	term.setTextColor(C.text)
	term.setCursorPos(1, h - 1)
	term.clearLine()
	if currentPage == 1 then
		-- Movement page: show facing
		local c = systemState.currentCardinal or "?"
		local v = systemState.currentVertical or "?"
		local facingText = "Facing: " .. tostring(c) .. "/" .. tostring(v)
		local x = math.floor((w - #facingText) / 2) + 1
		term.setCursorPos(x, h - 1)
		term.write(facingText)
	elseif currentPage == 3 then
		-- Vault page: show capacity progress bar
		local MAX_CAP = 103680
		local total = 0
		if type(systemState.vaultItems) == "table" then
			for _, cnt in pairs(systemState.vaultItems) do
				total = total + (tonumber(cnt) or 0)
			end
		end
		if total < 0 then total = 0 end
		local ratio = total / MAX_CAP
		if ratio > 1 then ratio = 1 end
		if ratio < 0 then ratio = 0 end

		-- Draw bracketed bar across the line
		local insideW = math.max(0, w - 2)
		local fill = math.floor(insideW * ratio + 0.5)
		term.setCursorPos(1, h - 1); term.write("[")
		term.setCursorPos(w, h - 1); term.write("]")
		-- Filled portion
		if insideW > 0 then
			term.setCursorPos(2, h - 1)
			term.setTextColor(C.good)
			if fill > 0 then term.write(string.rep("#", fill)) end
			-- Remainder
			term.setTextColor(C.inactive)
			if insideW - fill > 0 then
				term.write(string.rep("-", insideW - fill))
			end
		end
		-- Overlay percentage and totals centered
		local pct = math.floor((total / MAX_CAP) * 100 + 0.5)
		if pct > 100 then pct = 100 end
		if pct < 0 then pct = 0 end
		local label = string.format("%d%% %d/%d", pct, total, MAX_CAP)
		local lx = math.max(2, math.floor((w - #label) / 2) + 1)
		if lx + #label - 1 <= w - 1 then
			term.setCursorPos(lx, h - 1)
			term.setTextColor(C.text)
			term.write(label)
		end
	else
		-- Controls page: leave line clear
	end

	term.setBackgroundColor(C.inactive)
	term.setTextColor(C.text)
	term.setCursorPos(1, h)
	term.clearLine()
	term.write("Q=Prev  E=Next")
end

local function layoutMovementPage()
	local w, h = term.getSize()
	clearButtons()

	-- Content area (exclude header 2 lines and footer 2 lines)
	local contentTop = 3
	local contentBottom = h - 2
	if contentBottom <= contentTop then return end
	local contentHeight = contentBottom - contentTop + 1
	-- Allocate ~85% to D-pad and ~10% to bottom bar, clamp to fit
	local desiredDpad = math.floor(contentHeight * 0.85)
	local desiredBar = math.max(1, math.floor(contentHeight * 0.10))
	if desiredDpad + desiredBar > contentHeight then
		desiredDpad = math.max(3, contentHeight - desiredBar)
	end
	local dpadHeight = math.max(6, desiredDpad)

	-- 3x3 grid D-pad with equal-sized cells
	local cols, rows = 3, 3
	local hGap, vGap = 1, 1
	local leftMargin, rightMargin = 1, 1
	local topMargin = 0
	-- Bottom bar occupies the last ~10%
	local barHeight = math.max(1, desiredBar)
	local barTop = contentBottom - barHeight + 1

	local dpadTop = contentTop
	local dpadBottom = barTop - 1
	dpadHeight = dpadBottom - dpadTop + 1

	local usableW = w - leftMargin - rightMargin - hGap * (cols - 1)
	local cellW = math.floor(usableW / cols)
	if cellW < 6 then cellW = 6 end
	local usedW = cellW * cols + hGap * (cols - 1)
	local startX = math.floor((w - usedW) / 2) + 1

	local usableH = dpadHeight - vGap * (rows - 1) - topMargin
	local cellH = math.floor(usableH / rows)
	if cellH < 2 then cellH = 2 end
	local usedH = cellH * rows + vGap * (rows - 1)
	local startY = dpadTop + math.floor((dpadHeight - usedH) / 2)

	local function cellBounds(c, r)
		local x1 = startX + (c - 1) * (cellW + hGap)
		local y1 = startY + (r - 1) * (cellH + vGap)
		return x1, y1, x1 + cellW - 1, y1 + cellH - 1
	end

	-- Adaptive Move: whichever vertical orientation is active becomes Move
	local v = systemState.currentVertical or "?"
	local isMoveUp = (v == "U")
	local isMoveFwd = (v == "F")
	local isMoveDown = (v == "D")

	-- Place buttons into grid
	do
		local x1, y1, x2, y2 = cellBounds(2, 1) -- Up at top center
		addButton("UP", isMoveUp and "Move" or "Up", x1, y1, x2, y2, isMoveUp and C.accent or colors.brown)
	end
	do
		local x1, y1, x2, y2 = cellBounds(1, 2) -- Left
		addButton("ROT_L", "Left", x1, y1, x2, y2, colors.green)
	end
	do
		local x1, y1, x2, y2 = cellBounds(2, 2) -- Center: FWD or Move when v==F
		addButton("MOVE", isMoveFwd and "Move" or "Fwd", x1, y1, x2, y2, isMoveFwd and C.accent or C.btnBg)
	end
	do
		local x1, y1, x2, y2 = cellBounds(3, 2) -- Right
		addButton("ROT_R", "Right", x1, y1, x2, y2, colors.green)
	end
	do
		local x1, y1, x2, y2 = cellBounds(2, 3) -- Down at bottom center
		addButton("DOWN", isMoveDown and "Move" or "Down", x1, y1, x2, y2, isMoveDown and C.accent or colors.brown)
	end

	-- Bottom bar area: [FLIP] [AUTO]
	local halfW = math.floor((w - 3) / 2)
	local barX1 = 2
	local barX2 = barX1 + halfW - 1
	local barX3 = barX2 + 2
	local barX4 = w - 1

	addButton("FLIP", "FLIP", barX1, barTop, barX2, contentBottom, colors.brown)
	addButton("AUTO", "AUTO", barX3, barTop, barX4, contentBottom, systemState.autoDriveEnabled and C.danger or C.alt)

	-- Cabin lowered warning above D-pad if space allows
	if systemState.cabinLowered then
		local warningY = contentTop - 1
		if warningY > 2 then
			term.setBackgroundColor(C.bg)
			term.setTextColor(C.danger)
			term.setCursorPos(1, warningY)
			term.clearLine()
			local warning = "CABIN LOWERED"
			local cx = math.floor((w - #warning) / 2) + 1
			term.setCursorPos(cx, warningY)
			term.write(warning)
		end
	end
end

local function layoutCollectionPage()
	local w, h = term.getSize()
	clearButtons()
	local startY = 4
	local itemH = 3
	local gap = 1

	local function collectionBtn(id, text, row, enabled)
		local y1 = startY + (row - 1) * (itemH + gap)
		local y2 = y1 + itemH - 1
		addButton(id, text, 2, y1, w - 6, y2, C.inactive)
		local statusBg = (enabled == nil) and C.inactive or (enabled and C.good or C.danger)
		local statusLabel = (enabled == nil) and "?" or (enabled and "ON" or "OFF")
		addButton(id .. "_STATUS", statusLabel, w - 4, y1, w - 1, y2, statusBg)
	end

	collectionBtn("NAT", "Natural\nBlocks", 1, systemState.collectNatBlocksEnabled)
	collectionBtn("BUILD", "Build\nBlocks", 2, systemState.collectBuildBlocksEnabled)
	collectionBtn("ORE", "Raw\nOre", 3, systemState.collectRawOreEnabled)
	collectionBtn("CABIN", "Cabin\nPulley", 4, systemState.cabinLowered)
end

local function redraw()
	term.setBackgroundColor(C.bg)
	term.clear()
	drawHeader()
	if currentPage == 1 then
		layoutMovementPage()
	elseif currentPage == 2 then
		layoutCollectionPage()
	else
		layoutVaultPage()
	end
	for _, b in ipairs(buttons) do drawButton(b) end
	drawFooter()
end

local function sendCommand(cmd)
	NetworkHandler.broadcast(cmd)
end

-- ===== VAULT scrolling helpers =====
local function getVaultItemsSorted()
	local items = {}
	if type(systemState.vaultItems) == "table" then
		for name, count in pairs(systemState.vaultItems) do
			table.insert(items, { name = name, count = tonumber(count) or 0 })
		end
		table.sort(items, function(a, b)
			if a.count == b.count then return a.name < b.name end
			return a.count > b.count
		end)
	end
	return items
end

local function getVaultPageSize()
	local _, h = term.getSize()
	local listTop, listBottom = 4, h - 3
	return math.max(1, listBottom - listTop + 1)
end

local function getVaultMaxScroll(items, pageSize)
	return math.max(0, #items - pageSize)
end

local function setVaultScroll(newScroll, items, pageSize)
	items = items or getVaultItemsSorted()
	pageSize = pageSize or getVaultPageSize()
	local maxScroll = getVaultMaxScroll(items, pageSize)
	newScroll = math.max(0, math.min(maxScroll, newScroll))
	if newScroll ~= (systemState.vaultScroll or 0) then
		systemState.vaultScroll = newScroll
		redraw()
	end
end

local function scrollVaultBy(lines)
	if currentPage ~= 3 then return end
	local items = getVaultItemsSorted()
	local pageSize = getVaultPageSize()
	setVaultScroll((systemState.vaultScroll or 0) + lines, items, pageSize)
end

local function pageVaultBy(pages)
	if currentPage ~= 3 then return end
	local items = getVaultItemsSorted()
	local pageSize = getVaultPageSize()
	setVaultScroll((systemState.vaultScroll or 0) + pages * pageSize, items, pageSize)
end

local function jumpVault(toEnd)
	if currentPage ~= 3 then return end
	local items = getVaultItemsSorted()
	local pageSize = getVaultPageSize()
	local maxScroll = getVaultMaxScroll(items, pageSize)
	setVaultScroll(toEnd and maxScroll or 0, items, pageSize)
end

function layoutVaultPage()
	local w, h = term.getSize()
	clearButtons()
	local items = getVaultItemsSorted()
	local listTop = 4
	local listBottom = h - 3
	local pageSize = math.max(1, listBottom - listTop + 1)
	local start = (systemState.vaultScroll or 0) + 1
	local finish = math.min(#items, start + pageSize - 1)

	-- Render rows (name left-aligned, count right-aligned)
	local y = listTop
	for i = start, finish do
		local it = items[i]
		term.setCursorPos(2, y)
		term.setBackgroundColor(C.bg)
		term.setTextColor(C.text)
		
		local countStr = tostring(it.count)
		local maxNameWidth = w - #countStr - 4  -- 2 for margins, 2 for spacing
		local displayName = it.name
		if #displayName > maxNameWidth then
			displayName = displayName:sub(1, maxNameWidth - 1) .. "~"
		end
		
		-- Left-align name
		term.setCursorPos(2, y)
		term.write(displayName)
		
		-- Right-align count
		term.setCursorPos(w - #countStr - 1, y)
		term.write(countStr)
		
		y = y + 1
	end

	-- Prev/Next buttons for paging
	addButton("VAULT_PREV", "< Prev", 2, h - 1, 12, h - 1, C.btnBg)
	addButton("VAULT_NEXT", "Next >", w - 12, h - 1, w - 2, h - 1, C.btnBg)
end

local function handleButtonPress(id)
	if id == "ROT_L" or id == "ROT_R" then
		if systemState.cabinLowered then return end
		local cur = systemState.currentCardinal or "N"
		local delta = (id == "ROT_L") and -1 or 1
		local nextC = rotateCardinal(cur, delta)
		if nextC then
			sendCommand({ name = "odmk3-cardinal-rotater", cmd = "setFacing", target = nextC, secret = Config.SECRET })
		end
	elseif id == "UP" then
		if systemState.cabinLowered then return end
		if systemState.currentVertical == "U" then
			sendCommand({ name = "odmk3-drive-controller", cmd = "move", secret = Config.SECRET })
		else
			sendCommand({ name = "odmk3-vert-rotater", cmd = "setFacing", target = "U", secret = Config.SECRET })
		end
	elseif id == "DOWN" then
		if systemState.cabinLowered then return end
		if systemState.currentVertical == "D" then
			sendCommand({ name = "odmk3-drive-controller", cmd = "move", secret = Config.SECRET })
		else
			sendCommand({ name = "odmk3-vert-rotater", cmd = "setFacing", target = "D", secret = Config.SECRET })
		end
	elseif id == "MOVE" then
		if systemState.cabinLowered then return end
		if systemState.currentVertical == "F" then
			sendCommand({ name = "odmk3-drive-controller", cmd = "move", secret = Config.SECRET })
		else
			sendCommand({ name = "odmk3-vert-rotater", cmd = "setFacing", target = "F", secret = Config.SECRET })
		end
	elseif id == "FLIP" then
		if systemState.cabinLowered then return end
		local curC = systemState.currentCardinal or "N"
		local target = rotateCardinal(curC, 2) -- 180° flip
		if target then
			sendCommand({ name = "odmk3-cardinal-rotater", cmd = "setFacing", target = target, secret = Config.SECRET })
		end
	elseif id == "AUTO" then
		if systemState.cabinLowered then return end
		local newState = not systemState.autoDriveEnabled
		sendCommand({ name = "odmk3-auto-drive", cmd = "toggle", enabled = newState, secret = Config.SECRET })
	elseif id == "NAT" or id == "NAT_STATUS" then
		local newState = not systemState.collectNatBlocksEnabled
		sendCommand({ name = "odmk3-collect-nat-blocks", cmd = "toggle", enabled = newState, secret = Config.SECRET })
	elseif id == "BUILD" or id == "BUILD_STATUS" then
		local newState = not systemState.collectBuildBlocksEnabled
		sendCommand({ name = "odmk3-collect-build-blocks", cmd = "toggle", enabled = newState, secret = Config.SECRET })
	elseif id == "ORE" or id == "ORE_STATUS" then
		local newState = not systemState.collectRawOreEnabled
		sendCommand({ name = "odmk3-collect-raw-ore", cmd = "toggle", enabled = newState, secret = Config.SECRET })
	elseif id == "CABIN" or id == "CABIN_STATUS" then
		sendCommand({ name = "odmk3-cabin-pulley", cmd = "toggle", secret = Config.SECRET })
	elseif id == "VAULT_PREV" then
		pageVaultBy(-1)
	elseif id == "VAULT_NEXT" then
		pageVaultBy(1)
	end
end

local function handleTouch(x, y, isDown)
	for _, b in ipairs(buttons) do
		if pointInButton(b, x, y) then
			b.hot = isDown
			drawButton(b)
			if not isDown then handleButtonPress(b.id) end
		elseif b.hot then
			b.hot = false
			drawButton(b)
		end
	end
end

-- ========== Event Loops ==========
local function runUI()
	redraw()
	while true do
		local event, p1, p2, p3 = os.pullEvent()
		if event == "mouse_click" then
			handleTouch(p2, p3, true)
		elseif event == "mouse_up" then
			handleTouch(p2, p3, false)
		elseif event == "mouse_scroll" then
			-- p1: -1 up, 1 down
			if currentPage == 3 then
				scrollVaultBy(p1)
			end
		elseif event == "key" then
			-- Page switching
			if p1 == keys.e then
				currentPage = currentPage % totalPages + 1
				if currentPage == 1 then
					-- Quick on-demand orientation sync before drawing Movement page
					NetworkHandler.broadcast({ cmd = "queryFacing", secret = Config.SECRET })
					NetworkHandler.broadcast({ cmd = "queryOrientation", secret = Config.SECRET })
					local t0, wait = os.clock(), 0.4
					while os.clock() - t0 < wait do
						local sender, message, protocol = rednet.receive(Config.PROTOCOL, 0.1)
						if sender and type(message) == "table" then
							local wasUpdated = NetworkHandler.handleMessage(systemState, message)
							if wasUpdated and (message.type == "facing" or message.type == "orientation") then
								-- Footer can be redrawn incrementally
								drawFooter()
							end
						end
					end
				end
				redraw()
			elseif p1 == keys.q then
				currentPage = (currentPage - 2 + totalPages) % totalPages + 1
				if currentPage == 1 then
					NetworkHandler.broadcast({ cmd = "queryFacing", secret = Config.SECRET })
					NetworkHandler.broadcast({ cmd = "queryOrientation", secret = Config.SECRET })
					local t0, wait = os.clock(), 0.4
					while os.clock() - t0 < wait do
						local sender, message, protocol = rednet.receive(Config.PROTOCOL, 0.1)
						if sender and type(message) == "table" then
							local wasUpdated = NetworkHandler.handleMessage(systemState, message)
							if wasUpdated and (message.type == "facing" or message.type == "orientation") then
								drawFooter()
							end
						end
					end
				end
				redraw()
			-- Vault scrolling keys
			elseif currentPage == 3 and p1 == keys.up then
				scrollVaultBy(-1)
			elseif currentPage == 3 and p1 == keys.down then
				scrollVaultBy(1)
			elseif currentPage == 3 and p1 == keys.pageUp then
				pageVaultBy(-1)
			elseif currentPage == 3 and p1 == keys.pageDown then
				pageVaultBy(1)
			elseif currentPage == 3 and p1 == keys.home then
				jumpVault(false)
			elseif currentPage == 3 and p1 == keys["end"] then
				jumpVault(true)
			end
		elseif event == "term_resize" then
			redraw()
		end
	end
end

local function runNetworkListener()
	while true do
		local sender, message, protocol = rednet.receive(Config.PROTOCOL, 0.25)
		if sender and type(message) == "table" then
			local updated = NetworkHandler.handleMessage(systemState, message)
			if updated then
				-- Skip disk writes for orientation-only updates (footer redraw only)
				if message.type ~= "facing" and message.type ~= "orientation" then
					StateManager.saveState(systemState)
				end
				if message.type == "facing" or message.type == "orientation" then
					-- On Movement page, labels depend on orientation, so redraw fully
					if currentPage == 1 then
						redraw()
					else
						drawFooter()
					end
				else
					redraw()
				end
			end
		end
		sleep(0.05)
	end
end

local function runPeriodicTasks()
	-- Wait for readers/controllers to initialize after move-induced reboots
	sleep(1.5)

	local saveTimer = os.startTimer(30)
	local statusTimer = os.startTimer(10)
	local refreshTimer = os.startTimer(2)
	local heartbeatTimer = os.startTimer(5)
	local footerTimer = os.startTimer(0.75)
	local navTimer = os.startTimer(0.5)

	-- Kick off initial status queries
	NetworkHandler.broadcast({ cmd = "queryFacing", secret = Config.SECRET })
	NetworkHandler.broadcast({ cmd = "queryOrientation", secret = Config.SECRET })
	NetworkHandler.broadcast({ cmd = "queryStatus", secret = Config.SECRET })
	
	-- Send direct queries to each controller by name to force immediate responses
	NetworkHandler.broadcast({ name = "odmk3-collect-nat-blocks", cmd = "status", secret = Config.SECRET })
	NetworkHandler.broadcast({ name = "odmk3-collect-build-blocks", cmd = "status", secret = Config.SECRET })
	NetworkHandler.broadcast({ name = "odmk3-collect-raw-ore", cmd = "status", secret = Config.SECRET })
	NetworkHandler.broadcast({ name = "odmk3-cabin-pulley", cmd = "status", secret = Config.SECRET })
	NetworkHandler.broadcast({ name = "odmk3-auto-drive", cmd = "status", secret = Config.SECRET })
	
	-- Share initial snapshot so secondary remotes render promptly
	NetworkHandler.sendSnapshot(systemState, "startup")

	while true do
		local event, id = os.pullEvent("timer")
		if id == saveTimer then
			StateManager.saveMetrics(persistentMetrics)
			saveTimer = os.startTimer(30)
		elseif id == statusTimer then
			NetworkHandler.broadcast({ cmd = "queryStatus", secret = Config.SECRET })
			statusTimer = os.startTimer(10)
		elseif id == refreshTimer then
			NetworkHandler.broadcast({ cmd = "queryFacing", secret = Config.SECRET })
			NetworkHandler.broadcast({ cmd = "queryOrientation", secret = Config.SECRET })
			-- Re-query controllers if any values still unknown
			if systemState.collectNatBlocksEnabled == nil then
				NetworkHandler.broadcast({ name = "odmk3-collect-nat-blocks", cmd = "status", secret = Config.SECRET })
			end
			if systemState.collectBuildBlocksEnabled == nil then
				NetworkHandler.broadcast({ name = "odmk3-collect-build-blocks", cmd = "status", secret = Config.SECRET })
			end
			if systemState.collectRawOreEnabled == nil then
				NetworkHandler.broadcast({ name = "odmk3-collect-raw-ore", cmd = "status", secret = Config.SECRET })
			end
			if systemState.cabinLowered == nil then
				NetworkHandler.broadcast({ name = "odmk3-cabin-pulley", cmd = "status", secret = Config.SECRET })
			end
			if systemState.autoDriveEnabled == nil then
				NetworkHandler.broadcast({ name = "odmk3-auto-drive", cmd = "status", secret = Config.SECRET })
			end
			refreshTimer = os.startTimer(2)
		elseif id == heartbeatTimer then
			NetworkHandler.broadcast({ type = "unifiedHeartbeat", ts = os.clock(), secret = Config.SECRET })
			heartbeatTimer = os.startTimer(5)
		elseif id == footerTimer then
			if currentPage == 1 then
				-- Live orientation sync via service lookup + short receive loop
				local last = systemState.lastUpdate or 0
				if os.clock() - last > 0.9 then
					local cardId = nil
					local vertId = nil
					pcall(function()
						cardId = rednet.lookup(Config.PROTOCOL, "odmk3-cardinal-reader")
						vertId = rednet.lookup(Config.PROTOCOL, "odmk3-vert-reader")
					end)
					if cardId then
						rednet.send(cardId, { cmd = "queryFacing", secret = Config.SECRET }, Config.PROTOCOL)
					else
						NetworkHandler.broadcast({ cmd = "queryFacing", secret = Config.SECRET })
					end
					if vertId then
						rednet.send(vertId, { cmd = "queryOrientation", secret = Config.SECRET }, Config.PROTOCOL)
					else
						NetworkHandler.broadcast({ cmd = "queryOrientation", secret = Config.SECRET })
					end
					local t0, wait = os.clock(), 0.4
					while os.clock() - t0 < wait do
						local sender, message, protocol = rednet.receive(Config.PROTOCOL, 0.05)
						if sender and type(message) == "table" then
							local wasUpdated = NetworkHandler.handleMessage(systemState, message)
							-- Do not save state here; footer-only update
						end
					end
				end
				drawFooter()
			end
			footerTimer = os.startTimer(0.75)
		elseif id == navTimer then
			if systemState._navDirty then
				local NavigationDisplay = require("modules.navigation_display")
				NavigationDisplay.updateDisplaySettings(systemState)
				systemState._navDirty = false
			end
			navTimer = os.startTimer(0.5)
		end
		sleep(0.05)
	end
end

-- ========== Main ==========
local function main()
	if not term.isColor() then
		print("This requires an Advanced (color) pocket computer.")
		return
	end
	if not openWirelessModem() then
		print("No wireless modem found!")
		return
	end
	hostService()
	print("Pocket Command Center online")
	parallel.waitForAll(runUI, runNetworkListener, runPeriodicTasks)
end

main()