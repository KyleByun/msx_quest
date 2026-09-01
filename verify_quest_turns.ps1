# 민첩이 정하는 전투 행동 횟수를 확인한다 (quest_sena.md 의 전투방식).
#
# 민첩을 정해 놓고 한 라운드를 돌린 뒤, 누가 몇 번째로 쳤는지 순서 전체를
# 브레이크포인트로 받아 적어 파이썬 모델과 대조한다. gfx/quest_turns.py 참고.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    $env:PYTHONIOENCODING = "utf-8"

    & "$PSScriptRoot\build_quest.ps1"

    $work = "$PSScriptRoot\build\turns"
    New-Item -ItemType Directory -Force $work | Out-Null

    & uv run python "$PSScriptRoot\gfx\quest_turns.py" tcl $work
    if ($LASTEXITCODE -ne 0) { throw "tcl 생성 실패" }

    foreach ($tcl in Get-ChildItem "$work\*.tcl") {
        $name = $tcl.BaseName
        Remove-Item "$work\$name.txt" -ErrorAction SilentlyContinue
        Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
            '-machine', $MSX_MACHINE,
            '-cart',    "`"$PSScriptRoot\build\quest.rom`"",
            '-romtype', 'ASCII8',
            '-script',  "`"$($tcl.FullName)`"") | Out-Null
        if (-not (Test-Path "$work\$name.txt")) { throw "$name : 결과가 안 나왔습니다" }
    }

    & uv run python "$PSScriptRoot\gfx\quest_turns.py" check $work
    if ($LASTEXITCODE -ne 0) { throw "행동 횟수 검증 실패 - 위 표를 보세요" }
}
finally {
    Pop-Location
}
