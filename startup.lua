-- startup.lua
-- ODMK3 Client Startup & Deployment Handler
-- Handles role selection and script deployment from boot server

-- ========== Configuration ==========
local DEPLOY_PROTOCOL = "ODMK3-Deploy"
local SECRET = ""
local DEBUG = true

-- Role storage
local ROLE_FILE = ".odmk3_role"
local SCRIPT_FILE = ".odmk3_script"

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

-- ========== State Management ==========
local currentRole = nil
local currentScript = nil
local modem = nil

local function log(message)
    if DEBUG then
        print("[CLIENT] " .. tostring(message))
    end
end

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
        return true
    end
    return false
end

-- ========== Role Selection Interface ==========
local function showRoleMenu()
    term.clear()
    term.setCursorPos(1, 1)
    print("ODMK3 Client Role Selection")
    print("Computer ID: " .. os.getComputerID())
    print("Label: " .. (os.getComputerLabel() or "Unlabeled"))
    print("=" .. string.rep("=", 40))
    print()
    
    -- Convert roles to sorted list for consistent display
    local roleList = {}
    for role in pairs(AVAILABLE_ROLES) do
        table.insert(roleList, role)
    end
    table.sort(roleList)
    
    print("Available roles:")
    for i, role in ipairs(roleList) do
        print(string.format("%2d. %-20s - %s", i, role, ROLE_DESCRIPTIONS[role] or ""))
    end
    
    print()
    print("0. Refresh (rescan for roles)")
    print()
    write("Select role (number): ")
    
    local input = read()
    local choice = tonumber(input)
    
    if choice == 0 then
        return nil -- Refresh
    elseif choice and choice >= 1 and choice <= #roleList then
        return roleList[choice]
    else
        print("Invalid selection. Please try again.")
        sleep(2)
        return nil
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
    sleep(1)
    
    local success, error = pcall(function()
        shell.run(currentScript)
    end)
    
    if not success then
        print("Error running script: " .. error)
        print("Script will restart in 5 seconds...")
        sleep(5)
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
local function main()
    -- Handle reset command
    local args = {...}
    if args[1] == "reset" then
        handleReset()
        return
    end
    
    -- Initialize network
    local hasNetwork = initNetwork()
    
    -- Load existing role or prompt for selection
    currentRole = loadRole()
    if currentRole then
        currentScript = AVAILABLE_ROLES[currentRole]
        print("Computer configured as: " .. currentRole)
        if currentScript then
            print("Associated script: " .. currentScript)
        end
    else
        print("No role configured. Please select a role for this computer.")
        print()
        currentRole = selectRole()
        currentScript = AVAILABLE_ROLES[currentRole]
    end
    
    -- Start network listener if available
    if hasNetwork then
        log("Starting network listener...")
        parallel.waitForAny(
            networkListener,
            function()
                while true do
                    runScript()
                    sleep(1) -- Brief pause before restart
                end
            end
        )
    else
        -- No network - just run the script
        while true do
            runScript()
            sleep(1)
        end
    end
end

-- ========== Startup ==========
print("ODMK3 Client Starting...")
print("Computer ID: " .. os.getComputerID())
print("Label: " .. (os.getComputerLabel() or "Unlabeled"))
print()

-- Add a small delay to allow user to see startup info
sleep(1)

main()