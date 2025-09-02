# Omni-Drill MKIII Deployment System

A push-based deployment system for the Omni-Drill MKIII ComputerCraft distributed control system. This allows you to deploy all scripts from GitHub to their respective computers automatically.

## Quick Start

### 1. Set Up the Boot Server (Master Computer)

1. Choose one computer to be your master deployment server
2. Set its label: `label set odmk3-boot-server`
3. Download and run the boot server:
   ```lua
   shell.run("wget", "https://raw.githubusercontent.com/theravinglunatic/OmniDrillMKIII_CC-Integration/main/ODMK3-BootServer.lua", "startup.lua")
   reboot
   ```

### 2. Set Up All Other Computers

For each computer in your system:

1. **Set the computer label** according to its role:
   ```lua
   label set <computer-name>
   ```

2. **Run the quick setup script**:
   ```lua
   shell.run("wget", "https://raw.githubusercontent.com/theravinglunatic/OmniDrillMKIII_CC-Integration/main/ODMK3-QuickSetup.lua", "setup.lua")
   shell.run("setup.lua")
   ```

The quick setup will automatically download and install the deployment client, then reboot the computer.

### 3. Deploy All Scripts

1. On the boot server, select option "1. Deploy All Scripts"
2. The system will:
   - Download all scripts from GitHub
   - Discover all computers on the network
   - Deploy the appropriate script to each computer
   - Show deployment status

### 4. Restart All Computers

After deployment, select option "6. Restart All Computers" to restart all computers with their new scripts.

## Computer Labels and Their Scripts

| Computer Label | Script File | Role |
|---|---|---|
| **User Interfaces** |
| `odmk3-command-center` | `ODMK3-CommandCenter.lua` | Handheld pocket computer GUI |
| `odmk3-onboard-command` | `ODMK3-OnboardCommand.lua` | 3x3 monitor touchscreen GUI |
| `odmk3-monitor` | `OmniDrill-Monitor.lua` | Status display with metrics |
| **Movement Controllers** |
| `odmk3-drive-controller` | `ODMK3-DriveController.lua` | Main movement via redstone pulses |
| `odmk3-drive-shift` | `ODMK3-DriveShift.lua` | Orientation-based drive direction |
| `odmk3-gantry-shift` | `ODMK3-GantryShift.lua` | Gantry direction based on orientation |
| `odmk3-gantry-action` | `ODMK3-GantryAction.lua` | Sequenced Gearshift control |
| **Orientation System** |
| `odmk3-cardinal-reader` | `ODMK3-CardinalReader.lua` | Reads cardinal direction (N/E/S/W) |
| `odmk3-vert-reader` | `ODMK3-VertReader.lua` | Reads vertical orientation (F/U/D) |
| `odmk3-cardinal-rotator` | `ODMK3-CardinalRotator.lua` | Controls cardinal rotation |
| `odmk3-vert-rotator` | `ODMK3-VertRotator.lua` | Controls vertical rotation |
| **Collection Controllers** |
| `odmk3-collect-nat-blocks` | `ODMK3-CollectNatBlocks.lua` | Natural blocks collection |
| `odmk3-collect-build-blocks` | `ODMK3-CollectBuildBlocks.lua` | Build blocks collection |
| `odmk3-collect-raw-ore` | `ODMK3-CollectRawOre.lua` | Raw ore collection |
| **Automation & Utilities** |
| `odmk3-auto-drive` | `ODMK3-AutoDrive.lua` | Automated movement timing |
| `odmk3-aux-vault-threshold` | `ODMK3-AuxVaultThreshold.lua` | Vault capacity monitoring |
| `odmk3-drill-control` | `ODMK3-DrillControlON.lua` | Drill activation via redstone |
| `odmk3-drive-helper` | `ODMK3-DriveHelper.lua` | Drive system utilities |

## Boot Server Menu Options

1. **Deploy All Scripts** - Download all scripts from GitHub and deploy to appropriate computers
2. **Discover Computers** - Scan network for available computers
3. **Show Status** - Display current system status and connected computers
4. **Test GitHub Connection** - Verify internet connectivity and repository access
5. **Manual Deploy** - Deploy a specific script to a specific computer
6. **Restart All Computers** - Send restart command to all computers
7. **Exit** - Close the boot server

## Network Requirements

- All computers must have modems (wireless or wired)
- All computers must be on the same rednet network
- Boot server computer must have internet access for GitHub downloads
- All computers must use the same protocol: `"Omni-DrillMKIII"`

## Troubleshooting

### Computer Not Found During Discovery
- Check that the computer has the correct label
- Verify the computer has a modem attached
- Ensure the deployment client is running (reboot the computer)
- Check that all computers are on the same network

### GitHub Download Fails
- Verify internet connection on the boot server
- Check that the GitHub repository URL is correct
- Ensure the repository is public and accessible

### Deployment Fails
- Check that the target computer has sufficient disk space
- Verify the computer is responding to network messages
- Try manual deployment for specific computers

### Script Doesn't Start After Deployment
- Check for syntax errors in the deployed script
- Verify that all required peripherals are connected
- Check the computer's startup.lua file was written correctly

## Manual Installation (If Internet Not Available)

If GitHub access is not available, you can manually install scripts:

1. Copy the script files to each computer's disk
2. Rename the appropriate script to `startup.lua` on each computer
3. Reboot each computer

## Security

The deployment system includes an optional shared secret system:
- Set `SECRET = "your-secret-here"` in both boot server and deployment clients
- All computers must use the same secret
- Leave empty (`SECRET = ""`) to disable authentication

## Architecture

The deployment system uses the existing Omni-Drill MKIII rednet protocol for communication:
- **Protocol**: `"Omni-DrillMKIII"`
- **Discovery**: Computers respond to discovery broadcasts with their labels
- **Deployment**: Scripts are sent as rednet messages to specific computer labels
- **Status**: Deployment success/failure is reported back to the boot server

This ensures compatibility with the existing distributed control system.
