-- modules/network_handler.lua (Pocket Primary)
-- Network message handling and protocol logic

local NetworkHandler = {}
local Config = require("modules.config")
local NavigationDisplay = nil  -- Deprecated inline usage; now deferred via systemState._navDirty
local LAST_SNAPSHOT_TIME = 0
local SNAPSHOT_INTERVAL = 0.5  -- seconds between auto snapshots (debounce)
local VAULT_BUFFERS = {}  -- temp storage for chunk assembly keyed by ts

-- ========== Message Handling ==========
function NetworkHandler.handleMessage(systemState, msg)
    if type(msg) ~= "table" then return false end
    if Config.SECRET ~= "" and msg.secret ~= Config.SECRET then return false end

    local updated = false
    local orientationChanged = false

    -- Respond to controller startup state queries targeting the GUI name (compat)
    if msg.name == "odmk3-command-center" and msg.cmd == "queryState" then
        if msg.type == "natBlocks" then
            NetworkHandler.broadcast({ type = "natBlocksStatus", enabled = systemState.collectNatBlocksEnabled, secret = Config.SECRET })
        elseif msg.type == "buildBlocks" then
            NetworkHandler.broadcast({ type = "buildBlocksStatus", enabled = systemState.collectBuildBlocksEnabled, secret = Config.SECRET })
        elseif msg.type == "rawOre" then
            NetworkHandler.broadcast({ type = "rawOreStatus", enabled = systemState.collectRawOreEnabled, secret = Config.SECRET })
        end
        return false
    end

    -- Remote Desktop Support: respond to pings and state requests
    if msg.type == "remotePing" then
        NetworkHandler.broadcast({
            type = "remotePong",
            timestamp = os.clock(),
            secret = Config.SECRET
        })
        return false
    end

    if msg.type == "remoteStateRequest" then
        NetworkHandler.sendSnapshot(systemState, "remote client request")
        return false
    end

    -- Optimistic local updates when a remote issues a toggle with desired state.
    if msg.cmd == "toggle" and type(msg.enabled) == "boolean" then
        if msg.name == "odmk3-collect-nat-blocks" then
            systemState.collectNatBlocksEnabled = msg.enabled
            updated = true
        elseif msg.name == "odmk3-collect-build-blocks" then
            systemState.collectBuildBlocksEnabled = msg.enabled
            updated = true
        elseif msg.name == "odmk3-collect-raw-ore" then
            systemState.collectRawOreEnabled = msg.enabled
            updated = true
        elseif msg.name == "odmk3-auto-drive" then
            systemState.autoDriveEnabled = msg.enabled
            updated = true
        end
    end

    -- Movement responses
    if msg.type == "rotateAck" or msg.type == "moveAck" then
        systemState.pendingTarget = nil
        if msg.facing then systemState.currentCardinal = msg.facing end
        if msg.verticalAfter then systemState.currentVertical = msg.verticalAfter end
        updated = true

    -- Facing updates
    elseif msg.type == "facing" then
        if msg.facing then
            local changed = (msg.facing ~= systemState.currentCardinal)
            systemState.currentCardinal = msg.facing  -- Always assign
            if changed then
                orientationChanged = true
            end
            updated = true
        end

    -- Orientation updates
    elseif msg.type == "orientation" then
        if msg.orientation then
            local changed = (msg.orientation ~= systemState.currentVertical)
            systemState.currentVertical = msg.orientation  -- Always assign
            if changed then
                orientationChanged = true
            end
            updated = true
        end

    -- Collection status
    elseif msg.type == "natBlocksStatus" then
        systemState.collectNatBlocksEnabled = msg.enabled
        updated = true
    elseif msg.type == "buildBlocksStatus" then
        systemState.collectBuildBlocksEnabled = msg.enabled
        updated = true
    elseif msg.type == "rawOreStatus" then
        systemState.collectRawOreEnabled = msg.enabled
        updated = true

    -- Cabin pulley status
    elseif msg.type == "cabinPulleyStatus" then
        systemState.cabinLowered = msg.lowered
        updated = true

    -- Auto drive status
    elseif msg.type == "autoStatus" then
        systemState.autoDriveEnabled = msg.enabled
        updated = true

    -- Vault status (keep boolean only; no inventory here)
    elseif msg.type == "vaultStatus" then
        systemState.vaultFull = msg.full
        updated = true

    -- Scanner data
    elseif msg.type == "scanResponse" and msg.success and msg.data then
        systemState.scanData = msg.data
        systemState.scanInProgress = false
        systemState.relayOnline = true
        updated = true

    -- Scanner status
    elseif msg.type == "statusResponse" then
        systemState.relayOnline = msg.scannerAvailable
        updated = true

    -- Vault inventory (full payload)
    elseif msg.type == "vaultInventory" and type(msg.items) == "table" then
        systemState.vaultItems = msg.items
        systemState.vaultLastTs = msg.ts or os.epoch("utc")
        systemState.vaultHash = msg.hash
        updated = true

    -- Vault inventory (chunked)
    elseif msg.type == "vaultInvChunk" and type(msg.items) == "table" and type(msg.part) == "number" and type(msg.total) == "number" and msg.ts then
        local key = tostring(msg.ts)
        local buf = VAULT_BUFFERS[key]
        if not buf then
            buf = { items = {}, total = msg.total, got = {}, received = 0 }
            VAULT_BUFFERS[key] = buf
        end
        if not buf.got[msg.part] then
            buf.got[msg.part] = true
            buf.received = buf.received + 1
            -- merge items
            for name, cnt in pairs(msg.items) do
                buf.items[name] = (buf.items[name] or 0) + cnt
            end
        end
        if buf.received >= buf.total then
            systemState.vaultItems = buf.items
            systemState.vaultLastTs = msg.ts
            systemState.vaultHash = msg.hash
            VAULT_BUFFERS[key] = nil
            updated = true
        end
    end

    -- Update navigation display settings when orientation changes
    if orientationChanged then
        -- Defer actual display update to caller via periodic task to reduce contention
        systemState._navDirty = true
    end

    if updated then
        systemState.lastUpdate = os.clock()
        local now = os.clock()
        if now - LAST_SNAPSHOT_TIME >= SNAPSHOT_INTERVAL then
            LAST_SNAPSHOT_TIME = now
            NetworkHandler.sendSnapshot(systemState, "(auto)")
        end
    end

    return updated
end

-- ========== Network Utilities ==========
function NetworkHandler.openAllModems()
    local opened = false
    for _, side in ipairs(rs.getSides()) do
        if peripheral.getType(side) == "modem" then
            if peripheral.call(side, "isWireless") then
                rednet.open(side)
                opened = true
                if Config.DEBUG then print("[NET] Opened modem on " .. side) end
            end
        end
    end
    return opened
end

function NetworkHandler.broadcast(message)
    if Config.DEBUG and type(message) == "table" then
        local name = message.name or "(no name)"
        local cmd = message.cmd or message.type or "(no cmd)"
        Config.debugPrint("Broadcasting: " .. tostring(name) .. " | " .. tostring(cmd))
    end
    rednet.broadcast(message, Config.PROTOCOL)
end

-- ========== Snapshot Support ==========
function NetworkHandler.buildSnapshot(systemState)
    return {
        currentCardinal = systemState.currentCardinal,
        currentVertical = systemState.currentVertical,
        autoDriveEnabled = systemState.autoDriveEnabled,
        cabinLowered = systemState.cabinLowered,
        collectNatBlocksEnabled = systemState.collectNatBlocksEnabled,
        collectBuildBlocksEnabled = systemState.collectBuildBlocksEnabled,
        collectRawOreEnabled = systemState.collectRawOreEnabled,
        vaultFull = systemState.vaultFull,
        drillActive = systemState.drillActive,
        relayOnline = systemState.relayOnline
    }
end

function NetworkHandler.sendSnapshot(systemState, reason)
    local snapshot = NetworkHandler.buildSnapshot(systemState)
    NetworkHandler.broadcast({
        type = "remoteStateSnapshot",
        state = snapshot,
        secret = Config.SECRET
    })
    if Config.DEBUG then
        Config.debugPrint("Broadcasted state snapshot " .. (reason or ""))
    end
end

return NetworkHandler
