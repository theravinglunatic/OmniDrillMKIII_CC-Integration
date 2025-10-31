## Sync from in-game ComputerCraft computers to "CC Integration Copy Here"

Date: 2025-10-26

PowerShell commands executed successfully:

```
$src = "C:\Users\Lunatic\AppData\Roaming\gdlauncher_carbon\data\instances\Omni-Drill CC Developer1\instance\saves\Omni-Drill Developer CC\computercraft\computer"
$dst = "C:\Users\Lunatic\OneDrive\Projects\Omni Drill MKIII\CC Integration Copy Here"
$computers = Get-ChildItem $src -Directory | Where-Object { $_.Name -ne ".github" }
foreach ($c in $computers) {
	$files = Get-ChildItem $c.FullName -File | Where-Object { $_.Name -ne "startup.lua" -and $_.Name -notmatch "^\." }
	foreach ($f in $files) {
		if ($f.Name -like "ODMK3-*.lua" -or $f.Name -like "OmniDrill-*.lua") {
			$name = $f.Name -replace '^ODMK3-', '' -replace '^OmniDrill-', '' -replace '\.lua$',''
			$target = Join-Path $dst $name
			if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
			Copy-Item $f.FullName -Destination (Join-Path $target $f.Name) -Force
		}
	}
	if ($c.Name -eq "21") {
		$modSrc = Join-Path $c.FullName "modules"
		$unifiedDst = Join-Path $dst "UnifiedCommand"
		if (-not (Test-Path $unifiedDst)) { New-Item -ItemType Directory -Path $unifiedDst -Force | Out-Null }
		if (Test-Path $modSrc) { Copy-Item $modSrc -Destination $unifiedDst -Recurse -Force }
		foreach ($state in "unified_state","onboard_state") {
			$sf = Join-Path $c.FullName $state
			if (Test-Path $sf) { Copy-Item $sf -Destination $unifiedDst -Force }
		}
	}
	if ($c.Name -eq "0") {
		$pcDst = Join-Path $dst "RemoteCommand"
		if (-not (Test-Path $pcDst)) { New-Item -ItemType Directory -Path $pcDst -Force | Out-Null }
		$csf = Join-Path $c.FullName "command_state"
		if (Test-Path $csf) { Copy-Item $csf -Destination $pcDst -Force }
	}
}
```

Notes:
- Skips startup.lua and dotfiles (e.g., .odmk3_role).
- Creates component folders automatically (e.g., AutoDrive, Monitor, UnifiedCommand).
- Copies UnifiedCommand/modules and state files (unified_state, onboard_state).
- Copies RemoteCommand/command_state from computer 0.

