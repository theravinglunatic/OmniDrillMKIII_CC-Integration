## Sync from in-game ComputerCraft computers to "CC Integration Copy Here"

Date: 2025-11-20

Updated PowerShell sync reflecting removal of Unified/Remote command and new DriveUtility, Command, and Utility module sets:

```
$src = "C:\Users\Lunatic\AppData\Roaming\gdlauncher_carbon\data\instances\Omni-Drill CC Developer1\instance\saves\Omni-Drill MKIII CC Developer\computercraft\computer"
$dst = "C:\Users\Lunatic\OneDrive\Projects\Omni Drill MKIII\CC Integration Copy Here"
$computers = Get-ChildItem $src -Directory | Where-Object { $_.Name -ne ".github" }
foreach ($c in $computers) {
	$files = Get-ChildItem $c.FullName -File | Where-Object { $_.Name -ne "startup.lua" -and $_.Name -notmatch "^\." }
	$hasCommand = $false
	$hasUtility = $false
	foreach ($f in $files) {
		if ($f.Name -eq "ODMK3-Command.lua") { $hasCommand = $true }
		if ($f.Name -eq "ODMK3-Utility.lua" -or $f.Name -eq "ODMK3-ScannerDisplay.lua") { $hasUtility = $true }
		if ($f.Name -like "ODMK3-*.lua" -or $f.Name -like "OmniDrill-*.lua") {
			$name = $f.Name -replace '^ODMK3-', '' -replace '^OmniDrill-', '' -replace '\.lua$',''
			$target = Join-Path $dst $name
			if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
			Copy-Item $f.FullName -Destination (Join-Path $target $f.Name) -Force
			Write-Host "Copied $($f.Name) -> $name\"
		}
	}
	# Generic modules copy: if a computer hosts Command or Utility scripts and has a modules folder, copy to matching target
	$modSrc = Join-Path $c.FullName "modules"
	if (Test-Path $modSrc) {
		if ($hasCommand) {
			$commandDst = Join-Path $dst "Command"
			if (-not (Test-Path $commandDst)) { New-Item -ItemType Directory -Path $commandDst -Force | Out-Null }
			Copy-Item $modSrc -Destination $commandDst -Recurse -Force
			Write-Host "Copied Command modules"
		}
		if ($hasUtility) {
			$utilityDst = Join-Path $dst "Utility"
			if (-not (Test-Path $utilityDst)) { New-Item -ItemType Directory -Path $utilityDst -Force | Out-Null }
			Copy-Item $modSrc -Destination $utilityDst -Recurse -Force
			Write-Host "Copied Utility modules"
		}
	}
}
```

Notes:
- Skips `startup.lua` and dotfiles.
- Automatically creates component folders (e.g., `DriveUtility`, `Command`, `Utility`).
- DriveUtility replaces legacy AutoDrive (file now `ODMK3-DriveUtility.lua`).
- Command and Utility computers each use a `modules` folder; Utility also hosts `ODMK3-ScannerDisplay.lua` alongside `ODMK3-Utility.lua`.
- Unified/Remote command legacy handling removed; state files (`unified_state`, `onboard_state`, `command_state`) no longer copied.
- Safe to rerun: overwrites existing files, preserves other folders.

