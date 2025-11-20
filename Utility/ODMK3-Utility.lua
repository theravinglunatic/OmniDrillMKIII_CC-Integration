-- ODMK3-Utility.lua
-- Onboard Utility orchestrator: delegates to modules

local Config = require("modules.config")
local VaultRelay = require("modules.vault_relay")

local function main()
  Config.openAllModems()
  VaultRelay.start()
end

main()
