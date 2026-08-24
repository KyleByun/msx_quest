# Assembles src/main.asm into build/game.rom (16KB MSX cartridge image).
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force "$PSScriptRoot\build" | Out-Null

    & $SJASMPLUS --msg=war --sym="build/game.sym" --lst="build/game.lst" "src/main.asm"
    if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed with exit code $LASTEXITCODE" }

    $rom = Get-Item "$PSScriptRoot\build\game.rom"
    Write-Host "built: $($rom.FullName) ($($rom.Length) bytes)"
}
finally {
    Pop-Location
}
