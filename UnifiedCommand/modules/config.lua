-- modules/config.lua
-- Configuration constants for Unified Command Center

local Config = {}

-- ========== Network Configuration ==========
Config.PROTOCOL = "Omni-DrillMKIII"
Config.SECRET = ""
Config.DEBUG = false
Config.RELAY_NAME = "odmk3-geo-scanner-relay"

-- ========== File Configuration ==========
Config.STATE_FILE = "unified_state"
Config.METRICS_FILE = "metrics"
Config.MAX_STATE_SIZE = 256 * 1024  -- bytes; purge oversized legacy state files

-- ========== Color Schemes ==========
Config.colors = {
    bg = colors.black,
    title = colors.yellow,
    good = colors.lime,
    warning = colors.orange,
    danger = colors.red,
    inactive = colors.gray,
    text = colors.white,
    accent = colors.cyan,
    btnBg = colors.blue,
    btnFg = colors.white,
    btnHi = colors.cyan,
    alt = colors.purple
}

-- Access CC's global colors table without colliding with our palette
Config.CC = _G.colors

-- ========== Initial System State ==========
Config.initialState = {
    -- Movement state
    currentFacing = "Unknown",
    verticalFacing = "Unknown",
    pendingTarget = nil,
    lastStatusMsg = nil,
    autoDriveEnabled = false,
    
    -- Collection state
    collectNatBlocksEnabled = true,
    collectBuildBlocksEnabled = true,
    collectRawOreEnabled = true,
    cabinLowered = false,
    
    -- Monitoring state
    vaultFull = false,
    drillActive = false,
    networkActive = false,
    vaultItems = {},
    vaultItemCount = 0,
    lastUpdate = 0,
    
    -- Navigation state
    scanData = nil,
    scanRadius = 12,
    sliceThick = 1,
    sliceOffset = -2,
    currentView = "front",
    scanInProgress = false,
    relayOnline = false,
    currentCardinal = "N",
    currentVertical = "F",
    
    -- UI state
    utilityPage = 1,  -- 1 = monitoring, 2 = collection
    lastPressed = nil
}

-- ========== Initial Metrics ==========
Config.initialMetrics = {
    totalMoves = 0,
    totalUptime = 0,
    sessionStart = 0,
    drillActivations = 0,
    systemReboots = 0
}

-- ========== Debug Utility ==========
function Config.debugPrint(msg)
    if Config.DEBUG then print("[DEBUG] " .. msg) end
end

return Config
