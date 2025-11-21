-- startup.lua
-- ODMK3 Client Startup & Deployment Handler
-- Handles role selection and script deployment from boot server

-- ========== Configuration ==========
local DEPLOY_PROTOCOL = "ODMK3-Deploy"
local SECRET = ""
local DEBUG = true  -- Set to false in production for maximum startup speed

-- Role storage
local ROLE_FILE = ".odmk3_role"
local SCRIPT_FILE = ".odmk3_script"

-- ========== Utilities ==========
local function log(message)
    if DEBUG then
        print("[CLIENT] " .. tostring(message))
    end
end

-- Available roles (friendly names mapped to script files)
local AVAILABLE_ROLES = {
    ["drive-utility"] = "ODMK3-DriveUtility.lua",
    ["vault-threshold"] = "ODMK3-AuxVaultThreshold.lua", 
    ["cardinal-reader"] = "ODMK3-CardinalReader.lua",
    ["cardinal-rotator"] = "ODMK3-CardinalRotator.lua",
    ["collect-build-blocks"] = "ODMK3-CollectBuildBlocks.lua",
    ["collect-nat-blocks"] = "ODMK3-CollectNatBlocks.lua",
    ["collect-raw-ore"] = "ODMK3-CollectRawOre.lua",
    ["portable-command"] = "ODMK3-Command.lua",
    ["drill-control"] = "ODMK3-DrillControlON.lua",
    ["drive-controller"] = "ODMK3-DriveController.lua",
    ["drive-helper"] = "ODMK3-DriveHelper.lua", 
    ["drive-shift"] = "ODMK3-DriveShift.lua",
    ["gantry-action"] = "ODMK3-GantryAction.lua",
    ["gantry-shift"] = "ODMK3-GantryShift.lua",
    ["geo-scanner-relay"] = "ODMK3-GeoScannerRelay.lua",
    ["scanner-display"] = "ODMK3-ScannerDisplay.lua",
    ["utility-display"] = "ODMK3-Utility.lua",
    ["vert-reader"] = "ODMK3-VertReader.lua",
    ["vert-rotator"] = "ODMK3-VertRotator.lua",
    ["monitor"] = "OmniDrill-Monitor.lua",
        ["utility-rsc"] = "ODMK3-UtilityRSC.lua",
    ["cabin-pulley"] = "ODMK3-CabinPulley.lua",
    ["boot-server"] = "ODMK3-BootServer.lua"
    , ["cabin-sticker"] = "ODMK3-CabinSticker.lua"
}-- Role descriptions
local ROLE_DESCRIPTIONS = {
    ["drive-utility"] = "Drive utility & movement timing controller",
    ["vault-threshold"] = "Vault capacity monitoring system",
    ["cardinal-reader"] = "Cardinal direction reader (N/E/S/W)",
    ["cardinal-rotator"] = "Cardinal rotation controller",
    ["collect-build-blocks"] = "Build blocks collection controller",
    ["collect-nat-blocks"] = "Natural blocks collection controller",
    ["collect-raw-ore"] = "Raw ore collection controller",
    ["portable-command"] = "Handheld pocket computer GUI",
    ["drill-control"] = "Drill activation controller",
    ["drive-controller"] = "Main movement controller",
    ["drive-helper"] = "Drive helper utilities",
    ["drive-shift"] = "Orientation-based drive control",
    ["gantry-action"] = "Sequenced gearshift controller",
    ["gantry-shift"] = "Gantry direction controller",
    ["geo-scanner-relay"] = "Geo scanner relay computer",
    ["utility-display"] = "Utility display + vault relay",
    ["vert-reader"] = "Vertical orientation reader (F/U/D)",
    ["vert-rotator"] = "Vertical rotation controller",
    ["utility-rsc"] = "Rotational Speed Controller utility",
    ["cabin-pulley"] = "Cabin pulley controller (raise/lower cabin)",
    ["boot-server"] = "Centralized script deployment server"
    , ["cabin-sticker"] = "Cabin sticker retract/extend controller"
}

-- (Section intentionally left blank after revert)

-- ========== State Management ==========
local currentRole, currentScript, modem = nil, nil, nil

local function loadRole()
    if fs.exists(ROLE_FILE) then
        local file = fs.open(ROLE_FILE, "r")
        if file then
            currentRole = file.readAll()
            file.close()
            -- Backward compatibility: migrate legacy role name
            if currentRole == "auto-drive" then
                currentRole = "drive-utility"
                local f = fs.open(ROLE_FILE, "w") if f then f.write(currentRole) f.close() end
                local sf = fs.open(SCRIPT_FILE, "w") if sf then sf.write("ODMK3-DriveUtility.lua") sf.close() end
            end
            if fs.exists(SCRIPT_FILE) then
                local scriptFile = fs.open(SCRIPT_FILE, "r")
                if scriptFile then
                    currentScript = scriptFile.readAll()
                    scriptFile.close()
                end
            end
            return currentRole
        end
    end
    return nil
end

local function fetchBootServer()
    print("Fetching boot server from GitHub...")
    local url = "https://raw.githubusercontent.com/theravinglunatic/OmniDrillMKIII_CC-Integration/refs/heads/experimental/BootServer/ODMK3-BootServer.lua"
    
    for attempt = 1, 3 do
        local success, resp = pcall(function() return http.get(url, nil, true) end)
        if success and resp then
            local content = resp.readAll()
            resp.close()
            
            if content and content ~= "" and not content:match("404: Not Found") then
                local f = fs.open("ODMK3-BootServer.lua", "w")
                if f then
                    f.write(content)
                    f.close()
                    print("Boot server downloaded successfully (" .. #content .. " bytes)")
                    shell.setAlias("boot", "ODMK3-BootServer.lua")
                    return true
                end
            end
        end
        if attempt < 3 then
            print("Retry " .. attempt .. "/3...")
            sleep(1)
        end
    end
    
    print("ERROR: Failed to fetch boot server from GitHub")
    print("Check network connectivity and HTTP API settings")
    return false
end

local function saveRole(role)
    local file = fs.open(ROLE_FILE, "w")
    if not file then return false end
    file.write(role)
    file.close()
    local script = AVAILABLE_ROLES[role]
    if script then
        local scriptFile = fs.open(SCRIPT_FILE, "w")
        if scriptFile then
            scriptFile.write(script)
            scriptFile.close()
        end
    end
    currentRole = role
    currentScript = script
    return true
end

-- ========== Role Selection Interface ==========
local function showRoleMenu()
    -- Convert roles to sorted list for consistent display
    local roleList = {}
    for role in pairs(AVAILABLE_ROLES) do
        table.insert(roleList, role)
    end
    table.sort(roleList)
    
    -- Calculate pagination
    local w, h = term.getSize()
    local headerLines = 6  -- Header + separator + blank line
    local footerLines = 4  -- Navigation + blank + prompt + blank
    local maxRolesPerPage = h - headerLines - footerLines
    
    local totalPages = math.ceil(#roleList / maxRolesPerPage)
    local currentPage = 1
    
    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("ODMK3 Client Role Selection")
        print("Computer ID: " .. os.getComputerID())
        print("Label: " .. (os.getComputerLabel() or "Unlabeled"))
        print("=" .. string.rep("=", 40))
        print()
        
        if totalPages > 1 then
            print("Available roles (Page " .. currentPage .. "/" .. totalPages .. "):")
        else
            print("Available roles:")
        end
        
        -- Calculate range for current page
        local startIdx = (currentPage - 1) * maxRolesPerPage + 1
        local endIdx = math.min(startIdx + maxRolesPerPage - 1, #roleList)
        
        -- Display roles for current page
        for i = startIdx, endIdx do
            local role = roleList[i]
            print(string.format("%2d. %s", i, role))
        end
        
        print()
        
        -- Navigation options
        local navOptions = {}
        if totalPages > 1 then
            if currentPage > 1 then
                table.insert(navOptions, "p. Previous page")
            end
            if currentPage < totalPages then
                table.insert(navOptions, "n. Next page")
            end
        end
        table.insert(navOptions, "0. Refresh (rescan for roles)")
        
        for _, option in ipairs(navOptions) do
            print(option)
        end
        
        print()
        write("Select role (number) or navigation: ")
        
        local input = read()
        
        if input:lower() == "n" and currentPage < totalPages then
            currentPage = currentPage + 1
        elseif input:lower() == "p" and currentPage > 1 then
            currentPage = currentPage - 1
        else
            local choice = tonumber(input)
            if choice == 0 then
                return nil -- Refresh
            elseif choice and choice >= 1 and choice <= #roleList then
                return roleList[choice]
            else
                print("Invalid selection. Please try again.")
                sleep(2)
            end
        end
    end
end

local function selectRole()
    while true do
        local role = showRoleMenu()
        if role then
            term.clear()
            term.setCursorPos(1, 1)
            print("Selected role: " .. role)
            print("Description: " .. (ROLE_DESCRIPTIONS[role] or "No description"))
            print("Script: " .. (AVAILABLE_ROLES[role] or "Unknown"))
            print()
            write("Confirm selection? (y/n): ")
            
            local confirm = read()
            if confirm:lower() == "y" or confirm:lower() == "yes" then
                if saveRole(role) then
                    print("Role saved successfully!")
                    print("This computer is now configured as: " .. role)
                    print()
                    print("The computer will now listen for script deployments")
                    print("from the boot server. You can also run 'reset' to")
                    print("change the role later.")
                    sleep(3)
                    return role
                else
                    print("Error saving role. Please try again.")
                    sleep(2)
                end
            else
                print("Selection cancelled. Please choose again.")
                sleep(1)
            end
        end
    end
end

-- ========== Network Functions ==========
local function initNetwork()
    modem = peripheral.find("modem")
    if not modem then
        print("Warning: No modem found. Network features disabled.")
        return false
    end
    
    if modem.isWireless and not modem.isWireless() then
        print("Warning: Wired modem found, but wireless modem recommended.")
    end
    
    rednet.open(peripheral.getName(modem))
    log("Network initialized on " .. peripheral.getName(modem))
    return true
end

local function sendDeployAck(script, success, error)
    if not modem then return end
    
    local message = {
        cmd = "deploy_ack",
        script = script,
        success = success,
        error = error,
        role = currentRole,
        label = os.getComputerLabel()
    }
    
    rednet.broadcast(message, DEPLOY_PROTOCOL)
    log("Sent deployment acknowledgment for " .. script .. " (success: " .. tostring(success) .. ")")
end

local function handleDeployment(script, content)
    log("Received deployment for " .. script)
    
    -- Check if this script matches our role
    local ourScript = AVAILABLE_ROLES[currentRole or ""]
    -- Accept role's main script, startup.lua, and unified-command modules
    local accept = false
    if script == ourScript or script == "startup.lua" then
        accept = true
    elseif currentRole == "unified-command" and script:match("^modules/[%w_%-]+%.lua$") then
        accept = true
    elseif currentRole == "portable-command" and script:match("^modules/[%w_%-]+%.lua$") then
        accept = true
    end
    if not accept then
        log("Ignoring " .. script .. " (not for our role: " .. (currentRole or "none") .. ")")
        return false
    end
    
    -- Save the script
    local success, error = pcall(function()
        -- Ensure parent directory exists, if a path is provided
        local dir = script:match("^(.*)/[^/]+$")
        if dir and dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end
        local file = fs.open(script, "w")
        if not file then
            error("Could not open file for writing")
        end
        
        file.write(content)
        file.close()
        
        log("Saved " .. script .. " (" .. #content .. " bytes)")
    end)
    
    sendDeployAck(script, success, error)
    return success
end

local function networkListener()
    while true do
        local event, p1, p2, p3 = os.pullEvent("rednet_message")
        local senderId, message, protocol = p1, p2, p3
        
        if protocol == DEPLOY_PROTOCOL and type(message) == "table" then
            if message.secret ~= SECRET then
                log("Ignoring message with incorrect secret")
            elseif message.cmd == "ping" then
                -- Respond to ping requests
                local response = {
                    cmd = "pong",
                    role = currentRole or "unassigned",
                    label = os.getComputerLabel() or ("Computer #" .. os.getComputerID())
                }
                rednet.send(senderId, response, DEPLOY_PROTOCOL)
                log("Responded to ping from " .. senderId)
                
            elseif message.cmd == "deploy" then
                -- Direct deployment to this computer
                handleDeployment(message.script, message.content)
                
            elseif message.cmd == "deploy_broadcast" then
                -- Broadcast deployment - check if it's for us
                handleDeployment(message.script, message.content)
            end
        end
    end
end

-- ========== Script Execution ==========
local function runScript()
    if not currentScript then
        print("No script assigned to this role. Waiting for deployment...")
        return
    end
    
    if not fs.exists(currentScript) then
        print("Script " .. currentScript .. " not found. Waiting for deployment...")
        return  
    end
    
    print("Starting role script: " .. currentScript)
    -- Removed startup delay for faster launch
    
    if currentRole == "utility-display" then
        -- Run scanner display and utility relay together
        print("Utility Display mode: Starting Scanner and Utility in separate tabs")
        if multishell then
            local tab1 = multishell.launch({}, "ODMK3-ScannerDisplay.lua")
            multishell.setTitle(tab1, "Scanner Display")
            local tab2 = multishell.launch({}, "ODMK3-Utility.lua")
            multishell.setTitle(tab2, "Utility Relay")
            -- Keep this shell idle while tabs run
            while true do sleep(60) end
        else
            parallel.waitForAny(
                function()
                    pcall(function() shell.run("ODMK3-ScannerDisplay.lua") end)
                end,
                function()
                    pcall(function() shell.run("ODMK3-Utility.lua") end)
                end
            )
        end
    else
        -- Standard script execution for other roles
        local success, error = pcall(function()
            shell.run(currentScript)
        end)
        
        if not success then
            print("Error running script: " .. error)
            print("Script will restart in 5 seconds...")
            sleep(5)
        end
    end
end

-- ========== Reset Command ==========
local function handleReset()
    print("Resetting computer role...")
    
    -- Remove role files
    if fs.exists(ROLE_FILE) then
        fs.delete(ROLE_FILE)
    end
    if fs.exists(SCRIPT_FILE) then
        fs.delete(SCRIPT_FILE)
    end
    
    -- Remove downloaded scripts (except startup.lua)
    for role, script in pairs(AVAILABLE_ROLES) do
        if fs.exists(script) then
            fs.delete(script)
            print("Removed " .. script)
        end
    end
    
    currentRole = nil
    currentScript = nil
    
    print("Role reset complete. Restarting...")
    sleep(2)
    os.reboot()
end

-- ========== Main Function ==========
local function main(...)
    -- Fast path: process arguments first (e.g., reset)
    local args = {...}
    if args[1] == "reset" then
        handleReset()
        return
    end

    -- Load existing role immediately (before network) to minimize time-to-script
    currentRole = loadRole(); if currentRole then currentScript = AVAILABLE_ROLES[currentRole] end
    
    -- Boot-server must fetch its own script from GitHub (cannot deploy to itself)
    if currentRole == "boot-server" then
        if not fetchBootServer() then
            print("")
            print("Boot server script is required but fetch failed.")
            if fs.exists("ODMK3-BootServer.lua") then
                print("Found local copy, using cached version.")
                print("WARNING: May be outdated.")
            else
                print("No local copy found. Cannot continue.")
                print("")
                print("Press any key to retry...")
                os.pullEvent("key")
                os.reboot()
                return
            end
        end
    end

    -- Initialize network (non-blocking & fast)
    local hasNetwork = initNetwork()

    -- If no saved role, enter selection (one-time interactive path)
    if not currentRole then
        print("No role configured. Please select a role for this computer.")
        print()
        currentRole = selectRole(); currentScript = AVAILABLE_ROLES[currentRole]
        
        -- Fetch boot-server if selected
        if currentRole == "boot-server" then
            if not fetchBootServer() and not fs.exists("ODMK3-BootServer.lua") then
                print("")
                print("ERROR: Cannot start boot-server without the script.")
                print("Press any key to reboot and try again...")
                os.pullEvent("key")
                os.reboot()
                return
            end
        end
    else
        -- Minimal output for fast boot; only show when DEBUG enabled
        if DEBUG then
            print("Configured role: " .. currentRole .. (currentScript and (" (" .. currentScript .. ")") or ""))
        end
    end
            -- No immediate validation; will wait for deployment if script missing.

    -- Start listeners / script immediately
    if hasNetwork then
        if DEBUG then log("Starting network listener...") end
        parallel.waitForAny(
            networkListener,
            function()
                while true do
                    runScript()
                    sleep(0) -- yield without artificial delay
                end
            end
        )
    else
        while true do
            runScript()
            sleep(0)
        end
    end
end

-- ========== Startup ==========
if DEBUG then
    print("ODMK3 Client Starting...")
    print("Computer ID: " .. os.getComputerID())
    print("Label: " .. (os.getComputerLabel() or "Unlabeled"))
    print()
end

main(...)