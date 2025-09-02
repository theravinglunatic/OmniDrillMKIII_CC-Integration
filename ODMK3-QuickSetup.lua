-- ODMK3-QuickSetup.lua
-- Quick setup utility for deploying startup.lua to all computers

-- ========== Configuration ==========
local DEPLOY_PROTOCOL = "ODMK3-Deploy"
local SECRET = ""

-- The startup.lua content (will be read from file)
local STARTUP_SCRIPT = "startup.lua"

-- ========== Network Setup ==========
local function initNetwork()
    local modem = peripheral.find("modem")
    if not modem then
        error("No modem found! Please attach a wireless modem.")
    end
    
    if modem.isWireless and not modem.isWireless() then
        error("Wired modem found, but wireless modem required!")
    end
    
    rednet.open(peripheral.getName(modem))
    print("Network initialized on " .. peripheral.getName(modem))
end

-- ========== Deployment Functions ==========
local function deployStartupToAll()
    print("Reading startup.lua content...")
    
    if not fs.exists(STARTUP_SCRIPT) then
        error("startup.lua not found in current directory!")
    end
    
    local file = fs.open(STARTUP_SCRIPT, "r")
    if not file then
        error("Could not read startup.lua!")
    end
    
    local content = file.readAll()
    file.close()
    
    if not content or content == "" then
        error("startup.lua is empty!")
    end
    
    print("Loaded startup.lua (" .. #content .. " bytes)")
    print("Broadcasting startup.lua to all computers...")
    
    local message = {
        cmd = "deploy_broadcast",
        script = "startup.lua",
        content = content,
        secret = ""
    }
    
    rednet.broadcast(message, DEPLOY_PROTOCOL)
    print("Broadcast sent!")
    
    -- Wait for acknowledgments
    print("Waiting for responses (15 seconds)...")
    local timer = os.startTimer(15)
    local ackCount = 0
    local errors = {}
    
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, msg, protocol = p1, p2, p3
            if protocol == DEPLOY_PROTOCOL and type(msg) == "table" then
                if msg.cmd == "deploy_ack" and msg.script == "startup.lua" then
                    if msg.success then
                        ackCount = ackCount + 1
                        print("Computer " .. senderId .. ": SUCCESS")
                    else
                        table.insert(errors, "Computer " .. senderId .. ": " .. (msg.error or "unknown error"))
                        print("Computer " .. senderId .. ": ERROR - " .. (msg.error or "unknown"))
                    end
                end
            end
        elseif event == "timer" and p1 == timer then
            break
        end
    end
    
    print("\nDeployment complete!")
    print("Successful: " .. ackCount)
    if #errors > 0 then
        print("Errors: " .. #errors)
        for _, err in ipairs(errors) do
            print("  " .. err)
        end
    end
    
    print("\nNow computers will need to be restarted to use the new startup.lua")
    print("You can also run the full boot server (ODMK3-BootServer.lua) for")
    print("more advanced deployment features.")
end

-- ========== Main ==========
local function main()
    print("ODMK3 Quick Setup - Startup Deployment")
    print("======================================")
    print()
    
    initNetwork()
    
    print("This will deploy startup.lua to all computers in range.")
    print("Computers will then prompt users to select their roles.")
    print()
    write("Continue? (y/n): ")
    
    local confirm = read()
    if confirm:lower() == "y" or confirm:lower() == "yes" then
        deployStartupToAll()
    else
        print("Deployment cancelled.")
    end
end

if not term.isColor() then
    error("Advanced computer required!")
end

main()
