-- modules/config.lua (Onboard Utility #1)
local Config = {}

-- Network
Config.PROTOCOL = "Omni-DrillMKIII"
Config.SECRET = ""
Config.DEBUG = false

-- Persistence
Config.STATE_FILE = "command_state"
Config.METRICS_FILE = "metrics"
Config.MAX_STATE_SIZE = 256 * 1024 -- purge if file grows beyond 256KB

-- Initial state for pocket command center
Config.initialState = {
  currentCardinal = "N",
  currentVertical = "F",
  autoDriveEnabled = false,
  collectNatBlocksEnabled = false,
  collectBuildBlocksEnabled = false,
  collectRawOreEnabled = false,
  cabinLowered = false,
  vaultItems = {},
  vaultScroll = 0,
  _navDirty = false
}

-- Initial metrics
Config.initialMetrics = {
  totalMoves = 0,
  totalRotations = 0,
  totalUptime = 0,
  systemReboots = 0,
  sessionStart = 0
}

-- Color palette for UI
Config.colors = {
  bg = colors.black,
  text = colors.white,
  title = colors.gray,
  btnBg = colors.gray,
  btnFg = colors.white,
  btnHi = colors.orange,
  accent = colors.orange,
  alt = colors.blue,
  good = colors.green,
  danger = colors.red,
  inactive = colors.lightGray
}

function Config.openAllModems()
  local opened = false
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      if peripheral.call(side, "isWireless") then
        if not rednet.isOpen(side) then rednet.open(side) end
        opened = true
        if Config.DEBUG then print("[NET] Opened modem on " .. side) end
      end
    end
  end
  return opened
end

function Config.debugPrint(msg)
  if Config.DEBUG then print("[DEBUG] " .. tostring(msg)) end
end

return Config
