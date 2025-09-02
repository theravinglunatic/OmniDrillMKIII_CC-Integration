# ODMK3 Deployment System

This deployment system allows you to manage and deploy scripts to all computers in your Omni-Drill MKIII system from a central boot server.

## Quick Start

### 1. Set Up the Boot Server

1. Place an **Advanced Computer** with a **wireless modem** as your boot server
2. Copy `ODMK3-BootServer.lua` to the boot server
3. Run: `ODMK3-BootServer.lua`

### 2. Initial Client Setup (Two Options)

**Option A: Quick Setup (Recommended)**
1. Copy `ODMK3-QuickSetup.lua` to the boot server
2. Run: `ODMK3-QuickSetup.lua`
3. This will broadcast `startup.lua` to all computers in range
4. Restart all client computers

**Option B: Manual Setup**
1. On each client computer, copy `ODMK3-DeploymentClient.lua`
2. Run: `ODMK3-DeploymentClient.lua` 
3. From boot server, use: `push(all, "startup.lua")`
4. Restart client computers when prompted

### 3. Configure Client Roles

After clients restart with the new `startup.lua`:
1. Each computer will show a role selection menu
2. Choose the appropriate role for each computer based on its function
3. The role is saved permanently (until reset)

### 4. Deploy Scripts

From the boot server:
- `download` - Download all scripts from GitHub
- `push(all)` - Deploy all scripts to all computers  
- `push(all, "ODMK3-DriveController.lua")` - Deploy specific script to all
- `push(15, "ODMK3-DriveController.lua")` - Deploy to specific computer

## Boot Server Commands

| Command | Description |
|---------|-------------|
| `download` | Download all scripts from GitHub |
| `list` | Show all available client computers |
| `roles` | Show available roles and their scripts |
| `push(all)` | Deploy all scripts to all clients |
| `push(all, "script.lua")` | Deploy specific script to all clients |
| `push(clientId, "script.lua")` | Deploy script to specific client |
| `cache` | Show cached scripts |
| `help` | Show command help |
| `exit` | Exit the boot server |

## Available Roles

| Role | Script | Description |
|------|--------|-------------|
| `auto-drive` | ODMK3-AutoDrive.lua | Automated movement timing controller |
| `vault-threshold` | ODMK3-AuxVaultThreshold.lua | Vault capacity monitoring system |
| `cardinal-reader` | ODMK3-CardinalReader.lua | Cardinal direction reader (N/E/S/W) |
| `cardinal-rotator` | ODMK3-CardinalRotator.lua | Cardinal rotation controller |
| `collect-build-blocks` | ODMK3-CollectBuildBlocks.lua | Build blocks collection controller |
| `collect-nat-blocks` | ODMK3-CollectNatBlocks.lua | Natural blocks collection controller |
| `collect-raw-ore` | ODMK3-CollectRawOre.lua | Raw ore collection controller |
| `command-center` | ODMK3-CommandCenter.lua | Handheld pocket computer GUI |
| `drill-control` | ODMK3-DrillControlON.lua | Drill activation controller |
| `drive-controller` | ODMK3-DriveController.lua | Main movement controller |
| `drive-helper` | ODMK3-DriveHelper.lua | Drive helper utilities |
| `drive-shift` | ODMK3-DriveShift.lua | Orientation-based drive control |
| `gantry-action` | ODMK3-GantryAction.lua | Sequenced gearshift controller |
| `gantry-shift` | ODMK3-GantryShift.lua | Gantry direction controller |
| `onboard-command` | ODMK3-OnboardCommand.lua | 3x3 monitor touchscreen GUI |
| `vert-reader` | ODMK3-VertReader.lua | Vertical orientation reader (F/U/D) |
| `vert-rotator` | ODMK3-VertRotator.lua | Vertical rotation controller |
| `monitor` | OmniDrill-Monitor.lua | Status display with metrics |

## Client Management

### Resetting a Client Role
On any client computer, run: `startup reset`
This will:
- Clear the assigned role
- Delete downloaded scripts
- Restart the computer
- Show the role selection menu again

### Manual Script Updates
When you update scripts on GitHub:
1. Run `download` on the boot server to refresh the cache
2. Run `push(all)` to deploy updates to all computers
3. Client computers will automatically restart their scripts

## Network Requirements

- All computers need **wireless modems**
- All computers must be within wireless range of each other
- Advanced computers recommended (required for boot server)

## Troubleshooting

### Boot Server Issues
- Ensure the computer has a wireless modem attached
- Check that the GitHub repository URL is correct
- Verify internet access for downloading scripts

### Client Issues  
- If a client doesn't respond, check its wireless modem
- Ensure the client is running `startup.lua` or `ODMK3-DeploymentClient.lua`
- Check that both server and client are in wireless range

### Deployment Failures
- Use `list` command to verify clients are reachable
- Check for typos in script names (case-sensitive)
- Ensure scripts are cached with `download` before deploying

## File Structure

```
Boot Server:
- ODMK3-BootServer.lua      # Main boot server
- ODMK3-QuickSetup.lua      # Quick startup deployment
- ODMK3-DeploymentClient.lua # Manual deployment client

Client Computers:
- startup.lua               # Main client startup system
- .odmk3_role              # Saved role (hidden file)
- .odmk3_script            # Saved script name (hidden file)
- [role-script].lua        # The actual role script
```

## Security

The system includes a `SECRET` variable in both server and client scripts. Set this to the same value on all computers for basic authentication. Leave empty (`""`) to disable authentication.
