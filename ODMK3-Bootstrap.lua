-- ODMK3-Bootstrap.lua
-- Disposable bootstrap: fetches startup.lua from GitHub, installs, and reboots

-- Repository settings
local REPO = "theravinglunatic/OmniDrillMKIII_CC-Integration"
local BRANCH = "experimental"
local USER_AGENT = { ["User-Agent"] = "ODMK3-Bootstrap/1.0" }

-- Build the preferred and fallback raw URLs
local function url_refs(branch)
  return "https://raw.githubusercontent.com/" .. REPO .. "/refs/heads/" .. branch .. "/startup.lua"
end
local function url_flat(branch)
  return "https://raw.githubusercontent.com/" .. REPO .. "/" .. branch .. "/startup.lua"
end

local function fetch(url)
  local ok, handle = pcall(function() return http.get(url, USER_AGENT) end)
  if not ok or not handle then return nil end
  local body = handle.readAll()
  handle.close()
  return body
end

local function install_startup(content)
  local f = fs.open("startup.lua", "w")
  if not f then return false end
  f.write(content)
  f.close()
  return true
end

local function main()
  if not http then
    print("Bootstrap: HTTP API disabled. Enable http in ComputerCraft config.")
    return
  end

  local body = fetch(url_refs(BRANCH))
  if not body or body == "" then
    print("Bootstrap: refs/heads failed; trying flat branch URL...")
    body = fetch(url_flat(BRANCH))
  end

  if not body or body == "" then
    print("Bootstrap: Failed to download startup.lua from branch '" .. BRANCH .. "'.")
    print("Check network connectivity and http.whitelist for raw.githubusercontent.com")
    return
  end

  if not install_startup(body) then
    print("Bootstrap: Could not write startup.lua")
    return
  end

  print("Bootstrap: startup.lua installed from '" .. BRANCH .. "'. Rebooting...")
  sleep(0.2)
  os.reboot()
end

main()
