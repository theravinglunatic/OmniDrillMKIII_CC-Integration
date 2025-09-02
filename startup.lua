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
    ["auto-drive"] = "ODMK3-AutoDrive.lua",
    ["vault-threshold"] = "ODMK3-AuxVaultThreshold.lua", 
    ["cardinal-reader"] = "ODMK3-CardinalReader.lua",
    ["cardinal-rotator"] = "ODMK3-CardinalRotator.lua",
    ["collect-build-blocks"] = "ODMK3-CollectBuildBlocks.lua",
    ["collect-nat-blocks"] = "ODMK3-CollectNatBlocks.lua",
    ["collect-raw-ore"] = "ODMK3-CollectRawOre.lua",
    ["command-center"] = "ODMK3-CommandCenter.lua",
    ["drill-control"] = "ODMK3-DrillControlON.lua",
    ["drive-controller"] = "ODMK3-DriveController.lua",
    ["drive-helper"] = "ODMK3-DriveHelper.lua", 
    ["drive-shift"] = "ODMK3-DriveShift.lua",
    ["gantry-action"] = "ODMK3-GantryAction.lua",
    ["gantry-shift"] = "ODMK3-GantryShift.lua",
    ["onboard-command"] = "ODMK3-OnboardCommand.lua",
    ["vert-reader"] = "ODMK3-VertReader.lua",
    ["vert-rotator"] = "ODMK3-VertRotator.lua",
    ["monitor"] = "OmniDrill-Monitor.lua"
}

-- Role descriptions
local ROLE_DESCRIPTIONS = {
    ["auto-drive"] = "Automated movement timing controller",
    ["vault-threshold"] = "Vault capacity monitoring system",
    ["cardinal-reader"] = "Cardinal direction reader (N/E/S/W)",
    ["cardinal-rotator"] = "Cardinal rotation controller",
    ["collect-build-blocks"] = "Build blocks collection controller",
    ["collect-nat-blocks"] = "Natural blocks collection controller",
    ["collect-raw-ore"] = "Raw ore collection controller",
    ["command-center"] = "Handheld pocket computer GUI",
    ["drill-control"] = "Drill activation controller",
    ["drive-controller"] = "Main movement controller",
    ["drive-helper"] = "Drive helper utilities",
    ["drive-shift"] = "Orientation-based drive control",
    ["gantry-action"] = "Sequenced gearshift controller",
    ["gantry-shift"] = "Gantry direction controller", 
    ["onboard-command"] = "3x3 monitor touchscreen GUI",
    ["vert-reader"] = "Vertical orientation reader (F/U/D)",
    ["vert-rotator"] = "Vertical rotation controller",
    ["monitor"] = "Status display with metrics"
}

-- ========== Boot Server Deployment ==========
local function deployBootServer()
    print("Downloading and deploying Boot Server...")
    
    -- GitHub configuration for boot server download
    local GITHUB_REPO = "theravinglunatic/OmniDrillMKIII_CC-Integration"
    local GITHUB_BRANCH = "main"
    local GITHUB_BASE_URL = "https://raw.githubusercontent.com/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/"
    local BOOT_SERVER_SCRIPT = "ODMK3-BootServer.lua"
    local ONBOARD_COMMAND_SCRIPT = "ODMK3-OnboardCommand.lua"
    
    local success, err = pcall(function()
        -- Download Boot Server
        local url = GITHUB_BASE_URL .. BOOT_SERVER_SCRIPT
        log("Downloading Boot Server from: " .. url)
        
        local response = http.get(url)
        if not response then
            error("Failed to download " .. BOOT_SERVER_SCRIPT .. " from GitHub")
        end
        
        local content = response.readAll()
        response.close()
        
        if not content or content == "" then
            error("Downloaded Boot Server script is empty")
        end
        
        -- Save the boot server script
        local file = fs.open(BOOT_SERVER_SCRIPT, "w")
        if not file then
            error("Could not create boot server file")
        end
        
        file.write(content)
        file.close()
        
        log("Successfully deployed Boot Server (" .. #content .. " bytes)")
        
        -- Download Onboard Command Script
        local onboardUrl = GITHUB_BASE_URL .. ONBOARD_COMMAND_SCRIPT
        log("Downloading Onboard Command from: " .. onboardUrl)
        
        local onboardResponse = http.get(onboardUrl)
        if not onboardResponse then
            error("Failed to download " .. ONBOARD_COMMAND_SCRIPT .. " from GitHub")
        end
        
        local onboardContent = onboardResponse.readAll()
        onboardResponse.close()
        
        if not onboardContent or onboardContent == "" then
            error("Downloaded Onboard Command script is empty")
        end
        
        -- Save the onboard command script
        local onboardFile = fs.open(ONBOARD_COMMAND_SCRIPT, "w")
        if not onboardFile then
            error("Could not create onboard command file")
        end
        
        onboardFile.write(onboardContent)
        onboardFile.close()
        
        log("Successfully deployed Onboard Command (" .. #onboardContent .. " bytes)")
        
        print("Boot Server and Onboard Command deployed successfully!")
        print("Boot Server: " .. BOOT_SERVER_SCRIPT)
        print("Onboard Command: " .. ONBOARD_COMMAND_SCRIPT)
        print("Access boot server with 'boot' command after onboard command starts.")
    end)
    
    if not success then
        print("ERROR deploying scripts: " .. err)
        print("You may need to download them manually or check network connection.")
    end
end

-- ========== State Management ==========
local currentRole = nil
local currentScript = nil
local modem = nil

local function loadRole()
    if fs.exists(ROLE_FILE) then
        local file = fs.open(ROLE_FILE, "r")
        if file then
            currentRole = file.readAll()
            file.close()
            
            -- Also load the associated script name
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

local function saveRole(role)
    local file = fs.open(ROLE_FILE, "w")
    if file then
        file.write(role)
        file.close()
        
        -- Also save the script name
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
        
        -- Special handling for onboard-command: also deploy boot server
        if role == "onboard-command" then
            print("Onboard Command role selected - also deploying Boot Server...")
            deployBootServer()
        end
        
        return true
    end
    return false
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
    if script ~= ourScript and script ~= "startup.lua" then
        log("Ignoring " .. script .. " (not for our role: " .. (currentRole or "none") .. ")")
        return false
    end
    
    -- Save the script
    local success, error = pcall(function()
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
    
    -- Special handling for onboard-command: run in parallel with boot server access
    if currentRole == "onboard-command" then
        print("Onboard Command mode: Boot Server also available")
        print("Type 'boot' to access Boot Server console")
        
        parallel.waitForAny(
            function()
                -- Run the onboard command script
                local success, error = pcall(function()
                    shell.run(currentScript)
                end)
                
                if not success then
                    print("Error running onboard script: " .. error)
                    print("Script will restart in 5 seconds...")
                    sleep(5)
                end
            end,
            function()
                -- Handle boot server console access
                while true do
                    local event, param1 = os.pullEvent()
                    if event == "char" and param1 == "b" then
                        -- Check if full "boot" command
                        local input = "b" .. read()
                        if input == "boot" then
                            if fs.exists("ODMK3-BootServer.lua") then
                                print("Starting Boot Server console...")
                                shell.run("ODMK3-BootServer.lua")
                                print("Boot Server console closed. Returning to onboard command.")
                            else
                                print("Boot Server not found. Try redeploying the onboard-command role.")
                            end
                        end
                    end
                end
            end
        )
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
    currentRole = loadRole()
    if currentRole then
        currentScript = AVAILABLE_ROLES[currentRole]
    end

    -- Initialize network (non-blocking & fast)
    local hasNetwork = initNetwork()

    -- If no saved role, enter selection (one-time interactive path)
    if not currentRole then
        print("No role configured. Please select a role for this computer.")
        print()
        currentRole = selectRole()
        currentScript = AVAILABLE_ROLES[currentRole]
    else
        -- Minimal output for fast boot; only show when DEBUG enabled
        if DEBUG then
            print("Configured role: " .. currentRole .. (currentScript and (" (" .. currentScript .. ")") or ""))
        end
    end

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