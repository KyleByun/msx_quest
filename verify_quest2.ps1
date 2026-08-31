# Builds, boots quest2.rom headless, and saves a screenshot after a few
# emulated seconds. See verify.ps1 for the general pattern.
param(
    [double] $Seconds = 8,
    [string] $Out     = "$PSScriptRoot\build\quest2.png"
)
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

& "$PSScriptRoot\build_quest2.ps1"
if ($LASTEXITCODE -ne 0) { throw "build failed" }

$outTcl = $Out.Replace('\', '/')
$script = "$PSScriptRoot\build\verify_quest2.tcl"
$tcl = @"
after time $Seconds {
    screenshot -raw -size auto "$outTcl"
    exit
}
"@
[System.IO.File]::WriteAllText($script, $tcl, (New-Object System.Text.UTF8Encoding($false)))

if (Test-Path $Out) { Remove-Item $Out }

$proc = Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -PassThru -ArgumentList @(
    '-machine', $MSX_MACHINE,
    '-cart',    "`"$PSScriptRoot\build\quest2.rom`"",
    '-script',  "`"$script`""
)
if ($proc.ExitCode -ne 0) { throw "openMSX failed with exit code $($proc.ExitCode)" }

if (-not (Test-Path $Out)) { throw "no screenshot produced - the emulator exited early?" }
Write-Host "screenshot: $Out"
