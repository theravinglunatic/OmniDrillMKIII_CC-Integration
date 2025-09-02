# Omni-Drill MKIII ComputerCraft Integration

## System Architecture

This is a **ComputerCraft Lua distributed control system** for a Minecraft Create mod drilling contraption. The system consists of **~20 interconnected computers** that communicate via rednet protocol `"Omni-DrillMKIII"` to coordinate movement, drilling, and collection operations.

### Core Communication Pattern

```lua
-- Standard networking setup
local PROTOCOL = "Omni-DrillMKIII"
local SECRET = ""  -- Optional authentication
rednet.broadcast({ name = "target-component", cmd = "command", secret = SECRET }, PROTOCOL)
```

### Component Categories

1. **User Interfaces** (computers 0, 25, 23):
   - `ODMK3-CommandCenter.lua` - Handheld pocket computer GUI
   - `ODMK3-OnboardCommand.lua` - 3x3 monitor touchscreen GUI
   - `OmniDrill-Monitor.lua` - Status display with persistent metrics

2. **Movement Controllers** (computers 15, 17, 14, 13):
   - `ODMK3-DriveController.lua` - Main movement via redstone pulses
   - `ODMK3-DriveShift.lua` - Orientation-based drive direction control
   - `ODMK3-GantryShift.lua` - Gantry direction based on orientation
   - `ODMK3-GantryAction.lua` - Sequenced Gearshift peripheral control

3. **Orientation System** (computers 9, 10, 11, 12):
   - `ODMK3-CardinalReader.lua` - Reads cardinal direction (N/E/S/W)
   - `ODMK3-VertReader.lua` - Reads vertical orientation (F/U/D)
   - `ODMK3-CardinalRotator.lua` - Controls cardinal rotation
   - `ODMK3-VertRotator.lua` - Controls vertical rotation

4. **Collection Controllers** (computers 26, 27, 28):
   - `ODMK3-CollectNatBlocks.lua` - Natural blocks collection via redstone
   - `ODMK3-CollectBuildBlocks.lua` - Build blocks collection via redstone
   - `ODMK3-CollectRawOre.lua` - Raw ore collection via redstone

5. **Automation & Utilities** (computers 22, 20, 21, 25):
   - `ODMK3-AutoDrive.lua` - Automated movement timing
   - `ODMK3-AuxVaultThreshold.lua` - Vault capacity monitoring
   - `ODMK3-DrillControlON.lua` - Drill activation via redstone pulse
   - `ODMK3-BootServer.lua` - Network boot coordination

## Critical Design Patterns

### State Synchronization
GUIs maintain authoritative state with file persistence:
```lua
-- State persistence pattern
local function saveState()
    local state = { collectNatBlocksEnabled = enabled, ... }
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialise(state))
    file.close()
end
```

Collection controllers query GUIs at startup to avoid state reset after machine movement.

### Redstone Integration with Create Mod
```lua
-- Collection control: enabled = no signal (allows), disabled = signal (blocks)
redstone.setOutput("bottom", not collectionEnabled)

-- Movement control: brief pulses trigger Create contraption
redstone.setOutput("back", true)
sleep(0.3)
redstone.setOutput("back", false)
```

### Orientation-Based Control
Controllers monitor both cardinal (N/E/S/W) and vertical (F/U/D) orientation to determine appropriate redstone outputs for mechanical components.

### Message Broadcasting vs Targeted
- **Broadcast**: Status updates, state queries (`rednet.broadcast`)
- **Targeted**: Specific commands use `name` field matching in message handlers

## Development Workflows

### Testing Components
1. Each computer folder contains startup scripts
2. Use `DEBUG = true` flags for verbose logging
3. Test network connectivity with `SECRET = ""` (disable auth)

### Adding New Controllers
1. Follow naming pattern: `ODMK3-ComponentName.lua`
2. Include standard networking setup with protocol/secret
3. Implement state persistence if maintaining toggleable state
4. Add message handlers for targeted commands

### State Management
- GUIs persist state to files (`command_state`, `onboard_state`)
- Controllers query GUI state at startup via `queryState` messages
- Always save state immediately after user actions

## Key Integration Points

### Create Mod Peripherals
- **Sequenced Gearshift**: `peripheral.find("sequencedGearshift")`
- **Target Block**: `peripheral.find("create_target")` for vault inventory
- **Redstone**: Controls Create components via computer faces

### ComputerCraft Patterns
- **Monitors**: 3x3 advanced monitors with touch events
- **Pocket Computers**: Advanced (color) required for GUIs
- **Modems**: Auto-detect wireless modems on any computer face
- **Event Loops**: Handle `rednet_message`, `monitor_touch`, `timer` events

### Error Handling
- Graceful degradation when network unavailable
- Fallback to default states when GUI unreachable
- Peripheral reconnection logic for Create mod components

Always verify state synchronization after machine movements - this is the most common source of bugs.
