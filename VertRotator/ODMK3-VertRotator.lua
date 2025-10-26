-- ODMK3-VertRotator.lua
-- Receives setFacing commands for vertical orientation, consults VertReader (or local redstone) 
-- to know current orientation, rotates minimal degrees.
-- Rotation API assumed similar to SGS examples: rotate(angle[, directionSign]) where directionSign -1 = opposite direction.

local PROTOCOL       = "Omni-DrillMKIII"
local NAME           = "odmk3-vert-rotater"
local SECRET         = "" -- optional shared secret
local READER_NAME    = "odmk3-vert-reader"  -- source of orientation updates
local CARDINAL_READER_NAME = "odmk3-cardinal-reader" -- source of cardinal direction
local ROTATE_PERIPH  = nil  -- set explicit peripheral name with rotate() if desired
local QUERY_INTERVAL = 5

-- Debug options
local DEBUG = false                      -- Enable debug messages
local DEBUG_ASSUME_ORIENTATION = false  -- If true, assumes Forward orientation when VertReader not found
local DEBUG_ASSUMED_ORIENTATION = "F"   -- The orientation to assume when DEBUG_ASSUME_ORIENTATION is true

-- Map orientation - F (forward), U (up), D (down)
local ORDER = {"F","U","D"} -- Forward, Up, Down
local INDEX = { F=1, U=2, D=3 }

local function debugPrint(msg)
    if DEBUG then
        print("[DEBUG] " .. msg)
    end
end

local function openWireless()
for _, side in ipairs(rs.getSides()) do
if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
if not rednet.isOpen(side) then rednet.open(side) end
return true
end
end
return false
end

local function findRotator()
if ROTATE_PERIPH then
local p = peripheral.wrap(ROTATE_PERIPH)
if p and type(p.rotate)=="function" then return p end
end
for _, n in ipairs(peripheral.getNames()) do
local p = peripheral.wrap(n)
if type(p)=="table" and type(p.rotate)=="function" then return p end
end
return nil
end

local function currentOrientationFromRedstone()
if redstone.getInput("front") then return "F" end  -- Forward
if redstone.getInput("bottom") then return "U" end  -- Up (using bottom side)
if redstone.getInput("top") then return "D" end  -- Down (using top side)
return nil
end

-- Start with unknown orientation until detected via redstone or network
local lastOrientation = nil
local orientationConfirmed = false
local cardinalDirection = nil  -- Track cardinal direction (N, E, S, W)

local function broadcastOrientation(o)
rednet.broadcast({ type="orientation", name=NAME, orientation=o, secret=SECRET }, PROTOCOL)
end

-- Request current orientation from VertReader
local function queryVertOrientation()
    print("Requesting current vertical orientation")
    rednet.broadcast({
        name = READER_NAME,
        cmd = "queryOrientation",
        secret = ""
    }, PROTOCOL)
end

-- Request current cardinal direction from CardinalReader
local function queryCardinalDirection()
    print("Requesting current cardinal direction")
    rednet.broadcast({
        name = CARDINAL_READER_NAME,
        cmd = "queryFacing",
        secret = ""
    }, PROTOCOL)
end

local function computeRotation(from, to)
if from == to then return 0, 1, "none" end
local fi = INDEX[from]; local ti = INDEX[to]
if not fi or not ti then return 0, 1, "invalid" end

print("Computing rotation from " .. from .. " to " .. to)

-- Get direction sign based on cardinal direction
-- When facing South or West, reverse the rotation direction
local reverseRotation = (cardinalDirection == "S" or cardinalDirection == "W")
if reverseRotation then
    if cardinalDirection == "S" then
        print("Machine is facing South - reversing vertical rotation direction")
    elseif cardinalDirection == "W" then
        print("Machine is facing West - reversing vertical rotation direction")
    end
end

-- Special cases for vertical rotation
if from == "F" and to == "U" then
    local dirSign = reverseRotation and 1 or -1
    print("Rotating from Forward to Up (" .. (dirSign == -1 and "-" or "+") .. "90 degrees)")
    return 90, dirSign, (dirSign == -1 and "-" or "+") .. "90" 
elseif from == "F" and to == "D" then
    local dirSign = reverseRotation and -1 or 1
    print("Rotating from Forward to Down (" .. (dirSign == 1 and "+" or "-") .. "90 degrees)")
    return 90, dirSign, (dirSign == 1 and "+" or "-") .. "90"
elseif from == "U" and to == "F" then
    local dirSign = reverseRotation and -1 or 1
    print("Rotating from Up to Forward (" .. (dirSign == 1 and "+" or "-") .. "90 degrees)")
    return 90, dirSign, (dirSign == 1 and "+" or "-") .. "90"
elseif from == "U" and to == "D" then
    local dirSign = reverseRotation and -1 or 1
    print("Rotating from Up to Down (180 degrees" .. (reverseRotation and " reversed" or "") .. ")")
    return 180, dirSign, "180" .. (reverseRotation and "-rev" or "")
elseif from == "D" and to == "F" then
    local dirSign = reverseRotation and 1 or -1
    print("Rotating from Down to Forward (" .. (dirSign == -1 and "-" or "+") .. "90 degrees)")
    return 90, dirSign, (dirSign == -1 and "-" or "+") .. "90"
elseif from == "D" and to == "U" then
    local dirSign = reverseRotation and 1 or -1
    print("Rotating from Down to Up (180 degrees" .. (reverseRotation and "" or " reversed") .. ")")
    return 180, dirSign, "180" .. (dirSign == -1 and "-rev" or "")
end

return 0, 1, "none" -- Default
end

local function rotateTo(rotator, target)
local before = lastOrientation
if not before then
print("Error: Can't rotate - current orientation unknown")
return false, nil, nil, "current orientation unknown"
end

print("Attempting to rotate from " .. before .. " to " .. target)
local degrees, dirSign, action = computeRotation(before, target)

if degrees == 0 then
print("No rotation needed, already at " .. target)
return true, before, before, action
end

print("Will rotate " .. degrees .. " degrees, direction: " .. (dirSign == 1 and "clockwise" or "counter-clockwise"))

local success = false

-- For 180 degree rotations, try different approaches
if degrees == 180 then
print("Executing 180 degree rotation")

-- First attempt: Try a direct 180 rotation
local ok1 = pcall(function() rotator.rotate(180, dirSign) end)
os.sleep(1)

if ok1 then
print("Direct 180 degree rotation attempt completed")
success = true
else
-- Second attempt: Try two separate 90 degree rotations with longer pause
print("Direct rotation failed, trying sequential 90 degree rotations")

local ok2 = pcall(function()
rotator.rotate(90, dirSign)
os.sleep(1.5) -- Longer delay between rotations
rotator.rotate(90, dirSign)
os.sleep(1)
end)

if ok2 then
print("Sequential 90 degree rotations completed")
success = true
end
end
else
-- Regular 90 degree rotation
local ok = pcall(function()
if dirSign == -1 then 
print("Executing 90 degree counter-clockwise rotation")
rotator.rotate(90, -1) 
else 
print("Executing 90 degree clockwise rotation")
rotator.rotate(90) 
end
os.sleep(1) -- Added sleep to ensure rotation completes
end)

success = ok
end

if not success then
print("Rotation failed to complete successfully")
return false, before, before, "rotation failed" 
end

-- Update orientation logically based on the rotation performed
lastOrientation = target
print("Rotation complete, new orientation: " .. lastOrientation)

-- Try to verify rotation success
print("Checking redstone sensors to verify rotation...")
local ro = currentOrientationFromRedstone()
if ro and ro ~= lastOrientation then
print("WARNING: Rotation verification failed! Sensors indicate " .. ro .. " instead of " .. lastOrientation)
lastOrientation = ro -- Trust the sensors over the calculated position
return true, before, lastOrientation, "corrected-" .. action
end

return true, before, lastOrientation, action
end

local function sendAck(to, ok, before, after, action, err, target)
rednet.send(to, { type="rotateAck", ok=ok, before=before, after=after, action=action, err=err, targetDir=target, name=NAME, secret=SECRET }, PROTOCOL)
end

local function main()
if not openWireless() then
print("No wireless modem found; abort.")
return
end
local rotator = findRotator()
if not rotator then
print("No peripheral with rotate() found; running in simulation.")
end

-- Try to detect orientation from redstone first
local rsOrientation = currentOrientationFromRedstone()
if rsOrientation then
    lastOrientation = rsOrientation
    orientationConfirmed = true
    print("Vertical Rotator online. Initial orientation from redstone: " .. lastOrientation)
elseif DEBUG_ASSUME_ORIENTATION then
    lastOrientation = DEBUG_ASSUMED_ORIENTATION
    orientationConfirmed = true
    print("DEBUG MODE: Assuming " .. DEBUG_ASSUMED_ORIENTATION .. " orientation")
    print("Vertical Rotator online. Initial orientation (assumed): " .. lastOrientation)
else
    print("Vertical Rotator online. Warning: Orientation unknown!")
    print("Sending query to VertReader...")
    -- Don't broadcast yet since we don't know our orientation
end

-- Send initial query to readers
print("Initializing... Querying orientation readers")
queryVertOrientation()
queryCardinalDirection()

local timerId = os.startTimer(QUERY_INTERVAL)
while true do
local e, p1, p2, p3 = os.pullEvent()
if e == "timer" and p1 == timerId then
timerId = os.startTimer(QUERY_INTERVAL)
-- Check redstone signals first
local ro = currentOrientationFromRedstone()
if ro then
if not lastOrientation or ro ~= lastOrientation then
print("Orientation updated from redstone: " .. ro)
lastOrientation = ro
orientationConfirmed = true
if orientationConfirmed then broadcastOrientation(lastOrientation) end
end
end

-- Periodically ask Readers for updates
queryVertOrientation()
queryCardinalDirection()
elseif e == "rednet_message" then
local sender, msg, proto = p1, p2, p3
if proto == PROTOCOL and type(msg)=="table" then
if SECRET ~= "" and msg.secret ~= SECRET then
-- ignore
elseif msg.cmd == "setFacing" and msg.target then
-- Handle set facing requests - only process F/U/D (vertical directions)
if msg.target ~= "F" and msg.target ~= "U" and msg.target ~= "D" then
debugPrint("Ignoring non-vertical direction: " .. msg.target)
-- Don't send error ack, just ignore silently
-- Cardinal directions should be handled by CardinalRotator
else
print("Received setFacing command to " .. msg.target)
if not lastOrientation or not orientationConfirmed then
-- Can't rotate if we don't know current orientation
print("Can't rotate - current orientation unknown!")
sendAck(sender, false, nil, nil, nil, "Current orientation unknown", msg.target)
else
local ok,before,after,action
if rotator then
print("Using physical rotator peripheral")
ok,before,after,action = rotateTo(rotator, msg.target)
else
print("Using simulated rotation (no peripheral found)")
local degrees, sign, act = computeRotation(lastOrientation, msg.target)
if degrees > 0 then
print("Simulating rotation: " .. lastOrientation .. " to " .. msg.target)
ok = true; action = act; before = lastOrientation; lastOrientation = msg.target; after = lastOrientation
else
print("No rotation needed - already at target orientation")
ok = true; action = "none"; before = lastOrientation; after = lastOrientation;
end
end
print("Sending ack: " .. (ok and "success" or "failure"))
sendAck(sender, ok, before, after, action, ok and nil or action, msg.target)
if ok then broadcastOrientation(lastOrientation) end
end
end
elseif msg.cmd == "queryOrientation" then
-- Only respond if we know our orientation
if orientationConfirmed and lastOrientation then
broadcastOrientation(lastOrientation)
end
elseif msg.type == "orientation" and msg.name == READER_NAME then
-- Handle orientation updates from VertReader
if msg.orientation then
if not lastOrientation or lastOrientation ~= msg.orientation then
print("Orientation updated from Reader: " .. msg.orientation)
if lastOrientation then
print("Note: Previous orientation was " .. lastOrientation .. ", reader correction applied")
end
lastOrientation = msg.orientation
orientationConfirmed = true
broadcastOrientation(lastOrientation) -- Broadcast the corrected orientation
end
end
elseif msg.type == "facing" and msg.name == CARDINAL_READER_NAME then
-- Handle cardinal direction updates from CardinalReader
if msg.facing then
local previousCardinal = cardinalDirection
cardinalDirection = msg.facing
if previousCardinal ~= cardinalDirection then
print("Cardinal direction updated: " .. cardinalDirection)
if cardinalDirection == "S" then
print("Now facing South - vertical rotations will be reversed")
elseif cardinalDirection == "W" then
print("Now facing West - vertical rotations will be reversed")
elseif previousCardinal == "S" or previousCardinal == "W" then
print("No longer facing South/West - vertical rotations will be normal")
end
end
end
end
end
elseif e == "redstone" then
-- Immediate update on redstone change
local ro = currentOrientationFromRedstone()
if ro then
if not lastOrientation or ro ~= lastOrientation then
print("Orientation changed via redstone: " .. ro)
lastOrientation = ro
orientationConfirmed = true
broadcastOrientation(lastOrientation)
end
end
end
end
end

main()
