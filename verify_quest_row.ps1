# 대열을 확인한다 - 무리를 여러 마리로 세우고 칠 상대를 고르는 것 (SCREEN 8).
#
# 던전만 그린 화면과 대열을 얹은 화면의 차이를 오라클로 쓴다. 칸마다 달라진
# 픽셀을 세면 그 칸에 몬스터가 섰는지가 나온다. gfx/quest_row.py 참고.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    $env:PYTHONIOENCODING = "utf-8"

    & "$PSScriptRoot\build_quest3.ps1"

    $work = "$PSScriptRoot\build\row"
    New-Item -ItemType Directory -Force $work | Out-Null
    # tcl 까지 지운다. 손으로 만들어 둔 것이 남아 있으면 아래 반복문이
    # 그것도 돌려 보고 결과 파일이 없다고 멈춘다.
    Remove-Item "$work\*.bin", "$work\*.txt", "$work\*.tcl", "$work\*.png" -ErrorAction SilentlyContinue

    & uv run python "$PSScriptRoot\gfx\quest_row.py" tcl $work
    if ($LASTEXITCODE -ne 0) { throw "tcl 생성 실패" }

    foreach ($tcl in Get-ChildItem "$work\*.tcl") {
        $name = $tcl.BaseName
        Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
            '-machine', $MSX_MACHINE,
            '-cart',    "`"$PSScriptRoot\build\quest3.rom`"",
            '-romtype', 'ASCII8',
            '-script',  "`"$($tcl.FullName)`"") | Out-Null
        if (-not (Test-Path "$work\$name.txt")) { throw "$name : 결과가 안 나왔습니다" }
    }

    & uv run python "$PSScriptRoot\gfx\quest_row.py" check $work
    if ($LASTEXITCODE -ne 0) { throw "대열 검증 실패 - 위 표를 보세요" }
}
finally {
    Pop-Location
}
