# 실행 시간에 생성되는 던전이 언제나 하나로 이어져 있는지 확인한다.
#
# 한 번 부팅해서 지도를 수십 장 만든다 - MainLoop 에 브레이크포인트를 걸고 Seed 를
# 바꿔 가며 MakeLevel 을 다시 부르는 방식이다. 자세한 내용은 gfx/quest_mapcheck.py.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    $env:PYTHONIOENCODING = "utf-8"

    & "$PSScriptRoot\build_quest.ps1"

    $work = "$PSScriptRoot\build\mapcheck"
    New-Item -ItemType Directory -Force $work | Out-Null
    Remove-Item "$work\maps.txt" -ErrorAction SilentlyContinue

    # quest.sym 에서 주소를 읽으므로 빌드 뒤에 만들어야 한다
    & uv run python "$PSScriptRoot\gfx\quest_mapcheck.py" tcl $work
    if ($LASTEXITCODE -ne 0) { throw "tcl 생성 실패" }

    Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
        '-machine', $MSX_MACHINE,
        '-cart',    "`"$PSScriptRoot\build\quest.rom`"",
        '-romtype', 'ASCII8',
        '-script',  "`"$work\mapcheck.tcl`"") | Out-Null
    if (-not (Test-Path "$work\maps.txt")) { throw "지도가 하나도 안 나왔습니다" }

    & uv run python "$PSScriptRoot\gfx\quest_mapcheck.py" check $work
    if ($LASTEXITCODE -ne 0) { throw "연결성 검증 실패 - 위 지도를 보세요" }

    # 안개 걷기 - 알려진 통로를 세 걸음 걷고 드러난 칸을 센다
    Remove-Item "$work\fog.txt" -ErrorAction SilentlyContinue
    & uv run python "$PSScriptRoot\gfx\quest_mapcheck.py" fogtcl $work
    if ($LASTEXITCODE -ne 0) { throw "fog tcl 생성 실패" }

    Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
        '-machine', $MSX_MACHINE,
        '-cart',    "`"$PSScriptRoot\build\quest.rom`"",
        '-romtype', 'ASCII8',
        '-script',  "`"$work\fog.tcl`"") | Out-Null
    if (-not (Test-Path "$work\fog.txt")) { throw "안개 기록이 안 나왔습니다" }

    & uv run python "$PSScriptRoot\gfx\quest_mapcheck.py" fogcheck $work
    if ($LASTEXITCODE -ne 0) { throw "안개 검증 실패" }
}
finally {
    Pop-Location
}
