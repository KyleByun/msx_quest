# Assembles src/quest2.asm into build/quest2.rom (32KB MSX cartridge image).
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force "$PSScriptRoot\build" | Out-Null

    & $SJASMPLUS --msg=war --sym="build/quest2.sym" --lst="build/quest2.lst" "src/quest2.asm"
    if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed with exit code $LASTEXITCODE" }

    $rom = Get-Item "$PSScriptRoot\build\quest2.rom"
    Write-Host "built: $($rom.FullName) ($($rom.Length) bytes)"
}
finally {
    Pop-Location
}
