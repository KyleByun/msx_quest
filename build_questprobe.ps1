# src/questprobe.asm 를 build/questprobe.rom (16KB, 매퍼 없는 카트리지) 로 만든다.
#
# quest.rom 과 아무것도 나눠 쓰지 않는 SCREEN 8 타진용 롬이다. 뱅크가 없으므로
# build_quest.ps1 처럼 이어 붙일 것도 없다.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force "$PSScriptRoot\build" | Out-Null

    # 팔레트는 gfx/quest_pal.py 가 정본이다. 손으로 옮겨 적으면 조용히 어긋난다.
    $env:PYTHONIOENCODING = "utf-8"
    & uv run python "$PSScriptRoot\gfx\questprobe.py" pal "$PSScriptRoot\build"
    if ($LASTEXITCODE -ne 0) { throw "questprobepal.asm 생성 실패" }

    & $SJASMPLUS --msg=war --sym="build/questprobe.sym" --lst="build/questprobe.lst" "src/questprobe.asm"
    if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed with exit code $LASTEXITCODE" }

    $len = (Get-Item "$PSScriptRoot\build\questprobe.rom").Length
    Write-Host "built: $PSScriptRoot\build\questprobe.rom ($len bytes)"
}
finally {
    Pop-Location
}
