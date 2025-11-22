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
      print("[Utility] ScannerDisplay module loaded but no entry point; starting vault relay fallback")
      VaultRelay.start()
    end
  else
    print("[Utility] ScannerDisplay module absent; starting vault relay only")
    VaultRelay.start()
  end
end

main()
