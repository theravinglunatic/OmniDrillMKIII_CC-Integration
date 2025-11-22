-- ODMK3-Utility.lua
-- Onboard Utility orchestrator: delegates to modules

local Config = require("modules.config")
local VaultRelay = require("modules.vault_relay")

local function main()
  Config.openAllModems()
  -- Prefer scanner display module when present; fall back to vault relay
  local okScanner, ScannerDisplay = pcall(require, "modules.ODMK3-ScannerDisplay")
  if okScanner and ScannerDisplay then
    if type(ScannerDisplay) == "function" then
      ScannerDisplay()
    elseif type(ScannerDisplay.main) == "function" then
      ScannerDisplay.main()
    else
      print("ScannerDisplay module loaded but has no runnable entry; falling back to vault relay")
      VaultRelay.start()
    end
  else
    VaultRelay.start()
  end
end

main()
