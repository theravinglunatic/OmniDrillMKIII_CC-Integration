-- modules/scanner_network.lua
-- Reliable rednet listener that re-queues internal events

local M = {}

function M.start(protocol, secret, eventName, timeoutSec)
  eventName = eventName or "scanner_message"
  timeoutSec = timeoutSec or 0.5

  -- Ensure wireless modems are open if config helper exists
  local ok, cfg = pcall(require, "modules.config")
  if ok and type(cfg) == "table" and type(cfg.openAllModems) == "function" then
    pcall(cfg.openAllModems)
  end

  -- Optionally host service name (best-effort)
  pcall(function()
    if protocol then
      -- host with a generic name to aid diagnostics
      rednet.host(protocol, "odmk3-scanner-display")
    end
  end)

  while true do
    local sender, message, proto = rednet.receive(protocol, timeoutSec)
    if sender and type(message) == "table" then
      if (not secret) or secret == "" or message.secret == secret then
        os.queueEvent(eventName, sender, message)
      end
    end
  end
end

return M
