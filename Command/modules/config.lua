-- modules/config.lua (Onboard Utility #1)
local Config = {}

-- Network
Config.PROTOCOL = "Omni-DrillMKIII"
Config.SECRET = ""
Config.DEBUG = false

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
