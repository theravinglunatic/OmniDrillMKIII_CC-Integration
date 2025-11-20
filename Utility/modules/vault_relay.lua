-- modules/vault_relay.lua (Onboard Utility #1)
local Config = require("modules.config")

local VaultRelay = {}

local NAME = "odmk3-utility-display"
local POLL_INTERVAL = 3
local CHUNK_SIZE = 120

local function broadcast(message)
  rednet.broadcast(message, Config.PROTOCOL)
end

local function djb2(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + string.byte(s, i)) % 4294967296
  end
  return tostring(h)
end

local function serializeForHash(map)
  local names = {}
  for n in pairs(map) do table.insert(names, n) end
  table.sort(names)
  local parts = {}
  for _, n in ipairs(names) do table.insert(parts, n .. "=" .. tostring(map[n])) end
  return table.concat(parts, ";")
end

local function findVault()
  if peripheral.getType("right") == "create_target" then
    return peripheral.wrap("right")
  end
  return peripheral.find("create_target")
end

local function computeItemsMap(vault)
  -- CC:C Bridge create_target is a display peripheral, not inventory
  -- It receives text lines from Display Link + Smart Observer
  -- Parse lines like: "minecraft:stone x64" or "64x minecraft:stone"
  local lines = vault.dump and vault.dump()
  if type(lines) ~= "table" then return {}, 0 end
  
  local map, total = {}, 0
  for _, line in ipairs(lines) do
    if line and line ~= "" then
      -- Try multiple patterns for item count parsing
      -- Pattern 1: "item_name x123" or "item_name 123"
      local name, count = line:match("^(.-)%s+x?(%d+)%s*$")
      if not name then
        -- Pattern 2: "123x item_name" or "123 item_name"
        count, name = line:match("^(%d+)x?%s+(.-)%s*$")
      end
      if not name then
        -- Pattern 3: just "item_name" (assume count 1)
        name = line:match("^(.-)%s*$")
        count = "1"
      end
      
      if name and name ~= "" then
        name = name:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
        local cnt = tonumber(count) or 1
        if cnt > 0 then
          map[name] = (map[name] or 0) + cnt
          total = total + cnt
        end
      end
    end
  end
  return map, total
end

local function sendInventory(map, total)
  local names = {}
  for n in pairs(map) do table.insert(names, n) end
  table.sort(names)
  local distinct = #names
  local ts = os.epoch("utc")
  local hash = djb2(serializeForHash(map))

  if distinct <= CHUNK_SIZE then
    broadcast({ type = "vaultInventory", items = map, total = total, distinct = distinct, ts = ts, hash = hash, secret = Config.SECRET })
    return
  end
  local part, acc, count = 1, {}, 0
  local totalParts = math.ceil(distinct / CHUNK_SIZE)
  for _, n in ipairs(names) do
    acc[n] = map[n]
    count = count + 1
    if count >= CHUNK_SIZE then
      broadcast({ type = "vaultInvChunk", part = part, total = totalParts, items = acc, total = total, distinct = distinct, ts = ts, hash = hash, secret = Config.SECRET })
      part, acc, count = part + 1, {}, 0
    end
  end
  if count > 0 then
    broadcast({ type = "vaultInvChunk", part = part, total = totalParts, items = acc, total = total, distinct = distinct, ts = ts, hash = hash, secret = Config.SECRET })
  end
end

function VaultRelay.start()
  print("ODMK3 Utility: Vault Relay starting...")
  if Config.openAllModems() then pcall(function() rednet.host(Config.PROTOCOL, NAME) end) end
  local lastHash, lastVault = nil, nil
  while true do
    local vault = findVault()
    if vault then
      -- Ensure target is properly sized (Smart Observer typically sends compact data)
      pcall(function() vault.resize(32, 32) end)
      
      local map, total = computeItemsMap(vault)
      local distinct = 0
      for _ in pairs(map) do distinct = distinct + 1 end
      
      if Config.DEBUG then
        print(string.format("[%s] Parsed %d distinct items, %d total", os.date("%H:%M:%S"), distinct, total))
      end
      
      local sig = djb2(serializeForHash(map))
      if sig ~= lastHash then
        sendInventory(map, total)
        lastHash, lastVault = sig, true
        print(string.format("[%s] Sent vault inventory (%d items, %d distinct)", os.date("%H:%M:%S"), total, distinct))
      else
        -- heartbeat every ~10s
        if (os.clock() % 10) < (POLL_INTERVAL - 0.01) and lastVault then
          broadcast({ type = "vaultInventory", items = map, total = total, distinct = distinct, ts = os.epoch("utc"), hash = sig, secret = Config.SECRET })
        end
      end
    else
      if lastVault ~= false then
        print("Waiting for create_target on right...")
        lastVault = false
      end
    end
    sleep(POLL_INTERVAL)
  end
end

return VaultRelay
