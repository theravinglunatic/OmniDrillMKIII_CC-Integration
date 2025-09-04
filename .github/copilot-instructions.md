# Omni-Drill MKIII ComputerCraft Integration

## System Architecture

This is a **ComputerCraft Lua distributed control system** for a Minecraft Create mod drilling contraption. The system consists of **~20 interconnected computers** that communicate via rednet protocol `"Omni-DrillMKIII"` to coordinate movement, drilling, collection, and scanning operations.

### Core Communication Pattern

```lua
-- Standard networking setup
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""  -- Optional authentication
rednet.broadcast({ name = "target-component", cmd = "command", secret = "" }, PROTOCOL)
```

### Component Categories

1. **User Interfaces** (computers 0, 25, 23):
   - `ODMK3-CommandCenter.lua` - Handheld pocket computer GUI with state persistence
   - `ODMK3-OnboardCommand.lua` - 3x3 monitor touchscreen GUI with boot server access
   - `OmniDrill-Monitor.lua` - Status display with persistent metrics and vault monitoring

2. **Movement Controllers** (computers 15, 17, 14, 13):
   - `ODMK3-DriveController.lua` - Main movement via redstone pulses with vault safety
   - `ODMK3-DriveShift.lua` - Orientation-based drive direction control  
   - `ODMK3-GantryShift.lua` - Gantry direction based on orientation
   - `ODMK3-GantryAction.lua` - Sequenced Gearshift peripheral control with redstone triggers

3. **Orientation System** (computers 9, 10, 11, 12):
   - `ODMK3-CardinalReader.lua` - Reads cardinal direction (N/E/S/W) from redstone
   - `ODMK3-VertReader.lua` - Reads vertical orientation (F/U/D) from redstone
   - `ODMK3-CardinalRotator.lua` - Controls cardinal rotation via Create peripherals
   - `ODMK3-VertRotator.lua` - Controls vertical rotation via Create peripherals

4. **Collection Controllers** (computers 26, 27, 28):
   - `ODMK3-CollectNatBlocks.lua` - Natural blocks collection via redstone to Create funnels
   - `ODMK3-CollectBuildBlocks.lua` - Build blocks collection via redstone to Create funnels
   - `ODMK3-CollectRawOre.lua` - Raw ore collection via redstone to Create funnels

5. **Automation & Utilities** (computers 22, 20, 21, 25):
   - `ODMK3-AutoDrive.lua` - Automated movement timing with safety checks
   - `ODMK3-AuxVaultThreshold.lua` - Vault capacity monitoring via redstone sensors
   - `ODMK3-DrillControlON.lua` - Drill activation via redstone pulse
   - `ODMK3-BootServer.lua` - Network deployment system with role-based script distribution

6. **Scanning & Display**:
   - `ODMK3-ScannerDisplay.lua` - Geological scanner visualization with direction-aware cycling

## Critical Design Patterns

### State Synchronization with Startup Coordination
GUIs maintain authoritative state with file persistence, but controllers implement startup delays to prevent race conditions:

```lua
-- Controller startup pattern with 1-second delay
sleep(1.0)  -- Wait before querying GUI state
rednet.broadcast({ name = "odmk3-command-center", cmd = "queryState", type = "natBlocks" }, PROTOCOL)

-- GUI state persistence pattern  
local function saveState()
    local state = { collectNatBlocksEnabled = enabled, ... }
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialise(state))
    file.close()
end
```

Controllers query GUIs at startup and implement periodic status broadcasts (every 10s) to maintain synchronization after machine movements.

### Redstone Integration with Create Mod
```lua
-- Collection control: enabled = no signal (allows), disabled = signal (blocks)
redstone.setOutput("bottom", not collectionEnabled)

-- Movement control: brief pulses trigger Create contraption
redstone.setOutput("back", true)
sleep(0.3)
redstone.setOutput("back", false)

-- Vault safety: block movement when vault full
if vaultFull then
    sendMoveAck(false, "vault full - movement blocked")
    return
end
```

### Orientation-Based Control
Controllers monitor both cardinal (N/E/S/W) and vertical (F/U/D) orientation to determine appropriate redstone outputs for mechanical components:

```lua
-- Drive shift control based on orientation
if currentCardinal == "W" and currentVertical == "U" then
    shouldEmitSignal = true  -- West-Up orientation detected
end
```

### Direction-Aware Scanner Display
Scanner automatically switches view modes and slice ranges based on machine orientation:

```lua
-- Direction-based display settings
local DIRECTION_SETTINGS = {
    N = {view = "front", minOffset = -12, maxOffset = -2},  -- North: descending -2 to -12
    E = {view = "side",  minOffset = 2,   maxOffset = 12},  -- East: ascending 2 to 12
    D = {view = "top",   minOffset = -12, maxOffset = -2},  -- Down: descending
}
```

## Development Workflows

### Deployment System
Use the centralized boot server for script deployment:
1. Configure boot server: `ODMK3-BootServer.lua` on computer with advanced monitor
2. Set client roles: each computer runs `startup.lua` and selects role
3. Deploy updates: `download` from GitHub, then `push(all)` to deploy

### Testing Components
1. Use `DEBUG = true` flags for verbose logging
2. Test network connectivity with `SECRET = ""` (disable auth)
3. Monitor startup synchronization logs for race conditions
4. Verify state persistence after machine movements

### State Management Debugging
- Check `command_state`/`onboard_state` files for GUI state
- Monitor controller startup logs for state query responses
- Verify periodic status broadcasts every 10 seconds
- Test toggle commands work bidirectionally between GUIs and controllers

## Key Integration Points

### Create Mod Peripherals
```lua
-- Sequenced Gearshift for precise movements
local gearshift = peripheral.find("sequencedGearshift")
gearshift.move(DISTANCE, direction)  -- 1 = forward, -1 = backward

-- Target Block for vault inventory monitoring
local vault = peripheral.find("create_target")

-- Redstone control for Create components
redstone.setOutput("bottom", signal)  -- Controls Create item funnels
```

### ComputerCraft Patterns
- **Monitors**: 3x3 advanced monitors with `monitor_touch` events for GUIs
- **Pocket Computers**: Advanced (color) required for command center GUI
- **Modems**: Auto-detect wireless modems: `peripheral.getType(side) == "modem"`
- **Event Loops**: Handle `rednet_message`, `monitor_touch`, `timer`, `redstone` events

### Error Handling & Race Conditions
- **Startup Coordination**: 1-second delays before state queries prevent race conditions
- **Periodic Synchronization**: Status broadcasts every 10 seconds maintain state consistency  
- **Graceful Degradation**: Default to enabled state when GUI unreachable
- **Peripheral Reconnection**: Retry logic for Create mod component connections

### Network Message Types
- **Targeted Commands**: Use `name` field matching (`msg.name == MY_NAME`)
- **Status Broadcasts**: Periodic state announcements (`type = "natBlocksStatus"`)
- **State Queries**: Startup synchronization (`cmd = "queryState"`)
- **Safety Signals**: Vault status, orientation updates for movement control

Always verify state synchronization after machine movements - this is the most common source of bugs in distributed systems.
