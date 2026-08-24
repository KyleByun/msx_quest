# Builds, boots the ROM in openMSX without touching it, and saves a screenshot
# after a few emulated seconds. Nothing to click - useful for checking a change
# actually renders, and for letting an agent see the result.
# C-BIOS shows its own boot logo for several seconds before it scans slots and
# calls the cartridge INIT routine, so don't drop $Seconds much below 8.
param(
    [double] $Seconds = 8,
    [string] $Out     = "$PSScriptRoot\build\screenshot.png"
)
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

& "$PSScriptRoot\build.ps1"
if ($LASTEXITCODE -ne 0) { throw "build failed" }

# openMSX runs Tcl, where backslashes are escapes - give it forward slashes.
$outTcl = $Out.Replace('\', '/')
$script = "$PSScriptRoot\build\verify.tcl"
$tcl = @"
after time $Seconds {
    screenshot -raw -size auto "$outTcl"
    exit
}
"@
# Must be BOM-less: Tcl treats a UTF-8 BOM as part of the first command and
# fails to parse the script. Out-File -Encoding utf8 writes one on PS 5.1.
[System.IO.File]::WriteAllText($script, $tcl, (New-Object System.Text.UTF8Encoding($false)))

if (Test-Path $Out) { Remove-Item $Out }

# Start-Process -Wait, not "&": openmsx.exe is a GUI-subsystem binary, and the
# call operator does not wait for those - the screenshot check would run first.
$proc = Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -PassThru -ArgumentList @(
    '-machine', $MSX_MACHINE,
    '-cart',    "`"$PSScriptRoot\build\game.rom`"",
    '-script',  "`"$script`""
)
if ($proc.ExitCode -ne 0) { throw "openMSX failed with exit code $($proc.ExitCode)" }

if (-not (Test-Path $Out)) { throw "no screenshot produced - the emulator exited early?" }
Write-Host "screenshot: $Out"
