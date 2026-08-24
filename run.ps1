# Builds, then launches the ROM in openMSX interactively.
# The script returns when you close the emulator.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

& "$PSScriptRoot\build.ps1"
if ($LASTEXITCODE -ne 0) { throw "build failed" }

# Start-Process -Wait, not "&": the call operator does not wait for
# GUI-subsystem binaries like openmsx.exe.
Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
    '-machine', $MSX_MACHINE,
    '-cart',    "`"$PSScriptRoot\build\game.rom`""
)
