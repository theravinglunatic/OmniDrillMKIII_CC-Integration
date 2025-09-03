# ODMK3 Deployment System

This deployment system allows you to manage and deploy scripts to all computers in the Omni-Drill MKIII system from the central boot server.

### 1. Set Up the Boot Server/Onboard Command Center GUI

1. Place an **Advanced Computer** with a **wireless modem** as your Boot Server/Onboard Command Center GUI
2. Copy and run in terminal: `pastebin get https://pastebin.com/Ch5UtArG startup.lua`
3. Reboot `reboot` or CTRL+R
4. Select `onboard-command` as the role

### 2. Configure Client Roles

1. On each client computer, copy and run in terminal `pastebin get https://pastebin.com/Ch5UtArG startup.lua`
2. Reboot `reboot` or CTRL+R 
3. Each computer will show a role selection menu
4. Choose the appropriate role for each computer based on its function
5. The role is saved permanently (until reset)

### 3. Deploy Scripts

From the boot server:
- `download` - Download all scripts from GitHub
- `push(all)` - Deploy all scripts to all computers  
- `push(15)` - Deploy to specific computer

## Boot Server Commands

| Command | Description |
|---------|-------------|
| `download` | Download all scripts from GitHub |
| `list` | Show all available client computers |
| `roles` | Show available roles and their scripts |
| `push(all)` | Deploy all scripts to all clients |
| `push(clientId)` | Deploy script to specific client |
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
| `onboard-command` | ODMK3-OnboardCommand.lua, ODMK3-BootServer.lua | 3x3 monitor touchscreen GUI, acess Boot Server via Computer Terminal |
| `vert-reader` | ODMK3-VertReader.lua | Vertical orientation reader (F/U/D) |
| `vert-rotator` | ODMK3-VertRotator.lua | Vertical rotation controller |
| `monitor` | OmniDrill-Monitor.lua | Status display with metrics |

## Client Management

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
- Ensure the client is running `startup.lua`
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
