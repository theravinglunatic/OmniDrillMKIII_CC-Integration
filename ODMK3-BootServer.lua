-- ODMK3-BootServer.lua
-- Omni-Drill MKIII: Boot & Deployment Server
-- Pulls scripts from GitHub and deploys to client computers

-- ========== Configuration ==========
local PROTOCOL = "Omni-DrillMKIII"
local DEPLOY_PROTOCOL = "ODMK3-Deploy"
local SECRET = ""
local DEBUG = true

-- GitHub Configuration
local GITHUB_REPO = "theravinglunatic/OmniDrillMKIII_CC-Integration"
local GITHUB_BRANCH = "main"
local GITHUB_BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"

-- Available scripts and their descriptions
local AVAILABLE_SCRIPTS = {
    ["ODMK3-AutoDrive.lua"] = "Automated movement timing controller",
    ["ODMK3-AuxVaultThreshold.lua"] = "Vault capacity monitoring system",
    ["ODMK3-CardinalReader.lua"] = "Cardinal direction reader (N/E/S/W)",
    ["ODMK3-CardinalRotator.lua"] = "Cardinal rotation controller",
    ["ODMK3-CollectBuildBlocks.lua"] = "Build blocks collection controller",
    ["ODMK3-CollectNatBlocks.lua"] = "Natural blocks collection controller", 
    ["ODMK3-CollectRawOre.lua"] = "Raw ore collection controller",
    ["ODMK3-CommandCenter.lua"] = "Handheld pocket computer GUI",
    ["ODMK3-DrillControlON.lua"] = "Drill activation controller",
    ["ODMK3-DriveController.lua"] = "Main movement controller",
    ["ODMK3-DriveHelper.lua"] = "Drive helper utilities",
    ["ODMK3-DriveShift.lua"] = "Orientation-based drive control",
    ["ODMK3-GantryAction.lua"] = "Sequenced gearshift controller",
    ["ODMK3-GantryShift.lua"] = "Gantry direction controller",
    ["ODMK3-OnboardCommand.lua"] = "3x3 monitor touchscreen GUI",
    ["ODMK3-VertReader.lua"] = "Vertical orientation reader (F/U/D)",
    ["ODMK3-VertRotator.lua"] = "Vertical rotation controller",
    ["OmniDrill-Monitor.lua"] = "Status display with metrics"
}

-- Role mappings (script name -> friendly role name)
local ROLE_MAPPINGS = {
    ["ODMK3-AutoDrive.lua"] = "auto-drive",
    ["ODMK3-AuxVaultThreshold.lua"] = "vault-threshold", 
    ["ODMK3-CardinalReader.lua"] = "cardinal-reader",
    ["ODMK3-CardinalRotator.lua"] = "cardinal-rotator",
    ["ODMK3-CollectBuildBlocks.lua"] = "collect-build-blocks",
    ["ODMK3-CollectNatBlocks.lua"] = "collect-nat-blocks",
    ["ODMK3-CollectRawOre.lua"] = "collect-raw-ore",
    ["ODMK3-CommandCenter.lua"] = "command-center",
    ["ODMK3-DrillControlON.lua"] = "drill-control",
    ["ODMK3-DriveController.lua"] = "drive-controller", 
    ["ODMK3-DriveHelper.lua"] = "drive-helper",
    ["ODMK3-DriveShift.lua"] = "drive-shift",
    ["ODMK3-GantryAction.lua"] = "gantry-action",
    ["ODMK3-GantryShift.lua"] = "gantry-shift",
    ["ODMK3-OnboardCommand.lua"] = "onboard-command",
    ["ODMK3-VertReader.lua"] = "vert-reader",
    ["ODMK3-VertRotator.lua"] = "vert-rotator",
    ["OmniDrill-Monitor.lua"] = "monitor"
}

-- ========== State ==========
local scriptCache = {}
local deployedClients = {}
local modem = nil

-- ========== Utilities ==========
local function log(message)
    if DEBUG then
        print("[BOOT] " .. tostring(message))
    end
end

local function initNetwork()
    -- Find and open modem
    modem = peripheral.find("modem")
    if not modem then
        error("No modem found! Please attach a wireless modem.")
    end
    
    if modem.isWireless and not modem.isWireless() then
        error("Wired modem found, but wireless modem required!")
    end
    
    rednet.open(peripheral.getName(modem))
    log("Network initialized on " .. peripheral.getName(modem))
end

local function downloadScript(scriptName)
    local url = GITHUB_BASE_URL .. scriptName
    log("Downloading: " .. url)
    
    local response = http.get(url)
    if not response then
        error("Failed to download " .. scriptName .. " from GitHub")
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or content == "" then
        error("Downloaded script " .. scriptName .. " is empty")
    end
    
    scriptCache[scriptName] = content
    log("Downloaded " .. scriptName .. " (" .. #content .. " bytes)")
    return content
end

local function downloadAllScripts()
    print("Downloading all scripts from GitHub...")
    local count = 0
    local total = 0
    
    for scriptName in pairs(AVAILABLE_SCRIPTS) do
        total = total + 1
    end
    
    for scriptName in pairs(AVAILABLE_SCRIPTS) do
        local success, err = pcall(function()
            downloadScript(scriptName)
            count = count + 1
            print("(" .. count .. "/" .. total .. ") " .. scriptName)
        end)
        
        if not success then
            print("ERROR downloading " .. scriptName .. ": " .. err)
        end
        sleep(0.1) -- Brief pause to avoid overwhelming GitHub
    end
    
    print("Download complete: " .. count .. "/" .. total .. " scripts cached")
    return count == total
end

-- ========== Deployment Functions ==========
local function getClientRole(clientId)
    local message = {
        cmd = "ping",
        secret = ""
    }
    
    rednet.send(clientId, message, DEPLOY_PROTOCOL)
    
    local timer = os.startTimer(3) -- 3 second timeout for role query
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, msg, protocol = p1, p2, p3
            if senderId == clientId and protocol == DEPLOY_PROTOCOL and type(msg) == "table" then
                if msg.cmd == "pong" then
                    return msg.role
                end
            end
        elseif event == "timer" and p1 == timer then
            return nil -- Timeout
        end
    end
end

local function getRoleScript(role)
    for script, mappedRole in pairs(ROLE_MAPPINGS) do
        if mappedRole == role then
            return script
        end
    end
    return nil
end

local function deployToClient(clientId, scriptName)
    -- If no script specified, auto-detect from client role
    if not scriptName then
        local role = getClientRole(clientId)
        if not role or role == "unassigned" then
            error("Client " .. clientId .. " has no assigned role. Cannot auto-deploy.")
        end
        
        scriptName = getRoleScript(role)
        if not scriptName then
            error("Unknown script for role: " .. role)
        end
        
        log("Auto-detected script " .. scriptName .. " for client " .. clientId .. " (role: " .. role .. ")")
    end
    
    if not scriptCache[scriptName] then
        error("Script " .. scriptName .. " not in cache. Run 'download' first.")
    end
    
    local message = {
        cmd = "deploy",
        script = scriptName,
        content = scriptCache[scriptName],
        secret = ""
    }
    
    log("Deploying " .. scriptName .. " to client " .. clientId)
    rednet.send(clientId, message, DEPLOY_PROTOCOL)
    
    -- Wait for acknowledgment
    local timer = os.startTimer(10) -- 10 second timeout
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, msg, protocol = p1, p2, p3
            if senderId == clientId and protocol == DEPLOY_PROTOCOL and type(msg) == "table" then
                if msg.cmd == "deploy_ack" and msg.script == scriptName then
                    if msg.success then
                        log("Successfully deployed " .. scriptName .. " to client " .. clientId)
                        return true
                    else
                        error("Client " .. clientId .. " reported deployment failure: " .. (msg.error or "unknown"))
                    end
                end
            end
        elseif event == "timer" and p1 == timer then
            error("Timeout waiting for deployment acknowledgment from client " .. clientId)
        end
    end
end

local function listClients()
    print("Scanning for available clients...")
    
    local message = {
        cmd = "ping",
        secret = ""
    }
    
    rednet.broadcast(message, DEPLOY_PROTOCOL)
    
    local timer = os.startTimer(5) -- 5 second scan
    local clients = {}
    
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, msg, protocol = p1, p2, p3
            if protocol == DEPLOY_PROTOCOL and type(msg) == "table" then
                if msg.cmd == "pong" then
                    clients[senderId] = {
                        role = msg.role or "unassigned",
                        label = msg.label or ("Computer #" .. senderId)
                    }
                end
            end
        elseif event == "timer" and p1 == timer then
            break
        end
    end
    
    if next(clients) then
        print("Available clients:")
        for id, info in pairs(clients) do
            print("  " .. id .. ": " .. info.label .. " (" .. info.role .. ")")
        end
    else
        print("No clients found.")
    end
    
    return clients
end

local function deployToAll(scriptName)
    print("Deploying role-specific scripts to all clients...")
    
    -- Get all available clients first
    local clients = listClients()
    if not next(clients) then
        error("No clients found. Make sure clients are running and connected.")
    end
    
    local ackCount = 0
    local errors = {}
    
    for clientId, clientInfo in pairs(clients) do
        local targetScript = scriptName
        
        -- If no specific script provided, use client's role script
        if not targetScript then
            if clientInfo.role == "unassigned" then
                local err = "Client " .. clientId .. " (" .. clientInfo.label .. ") has no assigned role - skipping"
                table.insert(errors, err)
                print(err)
            else
                targetScript = getRoleScript(clientInfo.role)
                if not targetScript then
                    local err = "Client " .. clientId .. " has unknown role: " .. clientInfo.role
                    table.insert(errors, err)
                    print(err)
                else
                    log("Auto-selected " .. targetScript .. " for client " .. clientId .. " (role: " .. clientInfo.role .. ")")
                end
            end
        end
        
        if targetScript then
            if not scriptCache[targetScript] then
                local err = "Script " .. targetScript .. " not in cache - skipping client " .. clientId
                table.insert(errors, err)
                print(err)
            else
                local success, deployErr = pcall(function()
                    deployToClient(clientId, targetScript)
                    ackCount = ackCount + 1
                    print("Client " .. clientId .. " (" .. clientInfo.label .. "): SUCCESS - " .. targetScript)
                end)
                
                if not success then
                    local err = "Client " .. clientId .. ": " .. deployErr
                    table.insert(errors, err)
                    print("Client " .. clientId .. ": ERROR - " .. deployErr)
                end
            end
        end
        
        sleep(0.5) -- Brief pause between deployments
    end
    
    print("Deployment complete: " .. ackCount .. " successful deployments")
    if #errors > 0 then
        print("Errors encountered:")
        for _, err in ipairs(errors) do
            print("  " .. err)
        end
    end
    
    return ackCount, errors
end

-- ========== Command Interface ==========
local function showHelp()
    print("ODMK3 Boot Server Commands:")
    print("  download                  - Download all scripts from GitHub")
    print("  list                      - List available clients")
    print("  roles                     - Show available roles/scripts")
    print("  push(all)                 - Deploy role-specific scripts to all clients")
    print("  push(all, <script>)       - Deploy specific script to all clients")
    print("  push(<clientId>)          - Deploy role script to specific client")
    print("  push(<clientId>, <script>) - Deploy specific script to specific client")
    print("  cache                     - Show cached scripts")
    print("  help                      - Show this help")
    print("  exit                      - Exit server")
    print("")
    print("Examples:")
    print("  push(all)                 - Deploy each client's role script")
    print("  push(14)                  - Deploy role script to client 14")
    print("  push(all, \"ODMK3-DriveController.lua\")")
    print("  push(15, \"ODMK3-DriveController.lua\")")
end

local function showRoles()
    print("Available roles and scripts:")
    for script, description in pairs(AVAILABLE_SCRIPTS) do
        local role = ROLE_MAPPINGS[script] or "unknown"
        print("  " .. role .. " -> " .. script)
        print("    " .. description)
    end
end

local function showCache()
    print("Cached scripts:")
    for script in pairs(scriptCache) do
        print("  " .. script .. " (" .. #scriptCache[script] .. " bytes)")
    end
end

-- ========== Global Command Functions ==========
-- These must be global so they can be called from the command line
function download()
    return downloadAllScripts()
end

function list()
    return listClients()
end

function roles()
    showRoles()
end

function push(target, scriptName)
    if target == "all" then
        if scriptName then
            -- Deploy specific script to all clients
            return deployToAll(scriptName)
        else
            -- Deploy role-specific scripts to all clients
            return deployToAll()
        end
    else
        -- Deploy to specific client (auto-detect role script if not specified)
        return deployToClient(target, scriptName)
    end
end

function cache()
    showCache()
end

function help()
    showHelp()
end

-- ========== Main Loop ==========
local function main()
    print("ODMK3 Boot Server v1.0")
    print("Initializing...")
    
    initNetwork()
    print("Server ready! Type 'help' for commands.")
    print("Recommendation: Start with 'download' to cache all scripts.")
    print()
    
    while true do
        write("boot> ")
        local input = read()
        
        if input == "exit" then
            print("Shutting down boot server...")
            break
        elseif input == "help" then
            showHelp()
        elseif input == "download" then
            download()
        elseif input == "list" then
            list()
        elseif input == "roles" then
            roles()
        elseif input == "cache" then
            cache()
        elseif input:match("^push%(") then
            -- Safe manual parser for push() syntax
            local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
            local inner = input:match("^push%((.*)%)$")
            if not inner then
                print("Invalid push syntax. Examples: push(all) | push(all, \"ODMK3-DriveController.lua\") | push(12, \"ODMK3-DriveController.lua\")")
            else
                inner = trim(inner)
                local ok, err = pcall(function()
                    if inner == "all" then
                        push("all")
                        return
                    end
                    -- Match: all, "script"  OR id, "script"  OR just id
                    local target, script = inner:match('^([^,]+)%s*,%s*"([^"]+)"$')
                    if not target then
                        target, script = inner:match("^([^,]+)%s*,%s*'([^']+)'$")
                    end
                    if not target then
                        -- Try just a single argument (client id only)
                        target = inner:match("^(%d+)$")
                        if target then
                            local id = tonumber(target)
                            if id then
                                push(id) -- Auto-deploy role script
                                return
                            end
                        end
                        error("Could not parse push arguments. Expected push(all), push(id), push(all, \"script.lua\"), or push(id, \"script.lua\").")
                    end
                    target = trim(target)
                    if target == "all" then
                        push("all", script)
                    else
                        local id = tonumber(target)
                        if not id then
                            error("Client id must be a number or 'all'")
                        end
                        push(id, script)
                    end
                end)
                if not ok then
                    print("Error: " .. err)
                end
            end
        else
            print("Unknown command: " .. input)
            print("Type 'help' for available commands.")
        end
        
        print() -- Add spacing
    end
end

-- ========== Startup ==========
if not term.isColor() then
    error("Advanced computer required for boot server!")
end

main()