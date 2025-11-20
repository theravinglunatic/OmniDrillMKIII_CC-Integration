-- modules/state_manager.lua (Pocket Primary)
-- State persistence and management

local StateManager = {}
local Config = require("modules.config")

-- ========== State Management ==========
function StateManager.loadState(systemState)
    if fs.exists(Config.STATE_FILE) then
        -- Purge legacy oversized state files
        local ok, size = pcall(fs.getSize, Config.STATE_FILE)
        if ok and size and size > Config.MAX_STATE_SIZE then
            print(string.format("[STATE] %s too large (%d bytes) - purging", Config.STATE_FILE, size))
            pcall(fs.delete, Config.STATE_FILE)
            return false
        end
        local file = fs.open(Config.STATE_FILE, "r")
        if file then
            local data = textutils.unserialise(file.readAll())
            file.close()
            if data then
                for k, v in pairs(data) do
                    if systemState[k] ~= nil then
                        systemState[k] = v
                    end
                end
                return true
            end
        end
    end
    return false
end

function StateManager.saveState(systemState)
    -- Build a lightweight state, excluding heavy/transient fields
    local persist = {}
    for k, v in pairs(systemState) do
        if k ~= "scanData" and k ~= "vaultItems" then
            persist[k] = v
        end
    end
    local file = fs.open(Config.STATE_FILE, "w")
    if file then
        file.write(textutils.serialise(persist))
        file.close()
        return true
    end
    return false
end

-- ========== Metrics Management ==========
function StateManager.loadMetrics(persistentMetrics)
    if fs.exists(Config.METRICS_FILE) then
        local file = fs.open(Config.METRICS_FILE, "r")
        if file then
            local data = textutils.unserialise(file.readAll())
            file.close()
            if data then
                for k, v in pairs(data) do
                    persistentMetrics[k] = v
                end
                return true
            end
        end
    end
    persistentMetrics.sessionStart = os.clock()
    persistentMetrics.systemReboots = (persistentMetrics.systemReboots or 0) + 1
    return false
end

function StateManager.saveMetrics(persistentMetrics)
    local file = fs.open(Config.METRICS_FILE, "w")
    if file then
        local currentTime = os.clock()
        if persistentMetrics.sessionStart > 0 then
            persistentMetrics.totalUptime = persistentMetrics.totalUptime + (currentTime - persistentMetrics.sessionStart)
            persistentMetrics.sessionStart = currentTime
        end
        file.write(textutils.serialise(persistentMetrics))
        file.close()
        return true
    end
    return false
end

-- ========== Initialization ==========
function StateManager.initialize()
    local systemState = {}
    for k, v in pairs(Config.initialState) do
        systemState[k] = v
    end

    local persistentMetrics = {}
    for k, v in pairs(Config.initialMetrics) do
        persistentMetrics[k] = v
    end

    StateManager.loadState(systemState)
    StateManager.loadMetrics(persistentMetrics)

    return systemState, persistentMetrics
end

return StateManager
