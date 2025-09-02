-- ODMK3-DeploymentClient.lua
-- Simple deployment client for receiving startup.lua and other scripts
-- Run this on client computers before they have startup.lua

-- ========== Configuration ==========
local DEPLOY_PROTOCOL = "ODMK3-Deploy"
local SECRET = ""
local DEBUG = true

-- ========== Utilities ==========
local function log(message)
    if DEBUG then
        print("[DEPLOY] " .. tostring(message))
    end
end

local function initNetwork()
    local modem = peripheral.find("modem")
    if not modem then
        error("No modem found! Please attach a wireless modem.")
    end
    
    if modem.isWireless and not modem.isWireless() then
        print("Warning: Using wired modem. Wireless recommended.")
    end
    
    rednet.open(peripheral.getName(modem))
    log("Network initialized on " .. peripheral.getName(modem))
    return modem
end

local function sendAck(script, success, error)
    local message = {
        cmd = "deploy_ack",
        script = script,
        success = success,
        error = error,
        role = "unassigned",
        label = os.getComputerLabel() or ("Computer #" .. os.getComputerID())
    }
    
    rednet.broadcast(message, DEPLOY_PROTOCOL)
    log("Sent ack for " .. script .. " (success: " .. tostring(success) .. ")")
end

local function handleDeployment(script, content)
    log("Received deployment for " .. script .. " (" .. #content .. " bytes)")
    
    local success, error = pcall(function()
        -- Create backup if file exists
        if fs.exists(script) then
            local backup = script .. ".bak"
            if fs.exists(backup) then
                fs.delete(backup)
            end
            fs.move(script, backup)
            log("Created backup: " .. backup)
        end
        
        -- Write new content
        local file = fs.open(script, "w")
        if not file then
            error("Could not open " .. script .. " for writing")
        end
        
        file.write(content)
        file.close()
        
        log("Successfully saved " .. script)
    end)
    
    if success then
        print("Received and saved: " .. script)
    else
        print("Error saving " .. script .. ": " .. error)
    end
    
    sendAck(script, success, error)
    return success
end

-- ========== Main Loop ==========
local function main()
    print("ODMK3 Deployment Client")
    print("Computer ID: " .. os.getComputerID())
    print("Label: " .. (os.getComputerLabel() or "Unlabeled"))
    print("=======================")
    print()
    
    local modem = initNetwork()
    print("Listening for deployments...")
    print("Press Ctrl+T to exit")
    print()
    
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, message, protocol = p1, p2, p3
            
            if protocol == DEPLOY_PROTOCOL and type(message) == "table" then
                if message.secret ~= SECRET then
                    log("Ignoring message with incorrect secret from " .. senderId)
                elseif message.cmd == "ping" then
                    -- Respond to ping
                    local response = {
                        cmd = "pong", 
                        role = "unassigned",
                        label = os.getComputerLabel() or ("Computer #" .. os.getComputerID())
                    }
                    rednet.send(senderId, response, DEPLOY_PROTOCOL)
                    print("Responded to ping from computer " .. senderId)
                    
                elseif message.cmd == "deploy" then
                    -- Direct deployment
                    handleDeployment(message.script, message.content)
                    
                elseif message.cmd == "deploy_broadcast" then
                    -- Broadcast deployment
                    handleDeployment(message.script, message.content)
                    
                    -- If we received startup.lua, offer to restart
                    if message.script == "startup.lua" then
                        print()
                        print("Received startup.lua! This computer can now restart")
                        print("to use the new startup system.")
                        print()
                        write("Restart now? (y/n): ")
                        local input = read()
                        if input:lower() == "y" or input:lower() == "yes" then
                            print("Restarting...")
                            sleep(1)
                            os.reboot()
                        else
                            print("Continuing to listen for deployments...")
                        end
                    end
                end
            end
        elseif event == "terminate" then
            print("\nShutting down deployment client...")
            break
        end
    end
end

-- ========== Startup ==========
main()
