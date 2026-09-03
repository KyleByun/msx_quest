# 던전 한 프레임이 창을 빠짐없이 덮는가 (SCREEN 8).
#
# 창을 표식으로 가득 채우고 다시 그린 뒤, 표식이 남은 픽셀을 센다. 남으면 그
# 자리를 아무도 안 그린 것이고, 거기에는 앞 프레임 조각이 남는다.
# 손으로 만든 통로(막힘 1~5)와 진짜 지도를 걸어 다니는 두 가지로 본다.
# gfx/quest_cover.py 참고.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    $env:PYTHONIOENCODING = "utf-8"

    & "$PSScriptRoot\build_quest3.ps1"

    $work = "$PSScriptRoot\build\cover"
    New-Item -ItemType Directory -Force $work | Out-Null
    Remove-Item "$work\*.bin", "$work\*.txt", "$work\*.tcl", "$work\*.png" `
        -ErrorAction SilentlyContinue

    & uv run python "$PSScriptRoot\gfx\quest_cover.py" tcl $work
    if ($LASTEXITCODE -ne 0) { throw "tcl 생성 실패" }
    & uv run python "$PSScriptRoot\gfx\quest_cover.py" livetcl $work
    if ($LASTEXITCODE -ne 0) { throw "live tcl 생성 실패" }

    foreach ($tcl in Get-ChildItem "$work\*.tcl") {
        Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
            '-machine', $MSX_MACHINE,
            '-cart',    "`"$PSScriptRoot\build\quest3.rom`"",
            '-romtype', 'ASCII8',
            '-script',  "`"$($tcl.FullName)`"") | Out-Null
    }

    & uv run python "$PSScriptRoot\gfx\quest_cover.py" check $work
    if ($LASTEXITCODE -ne 0) { throw "덮기 검증 실패 - 위 표를 보세요" }
    & uv run python "$PSScriptRoot\gfx\quest_cover.py" livecheck $work
    if ($LASTEXITCODE -ne 0) { throw "걸어 다니며 본 덮기 검증 실패" }
}
finally {
    Pop-Location
}
