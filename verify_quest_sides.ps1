# 옆면 세 상태(벽 / 대각선 앞칸의 정면 / 뚫림)를 결정적으로 검증한다.
#
# 맵이 부팅마다 새로 생기므로 화면만 다시 찍어서는 회귀를 잡을 수 없다. 여기서는
# 알려진 지도를 MapDataRam 에 직접 써 넣고 다시 그리게 한 뒤, 구워진 바이트를
# 그대로 걸어가는 흉내 렌더러와 화면을 한 픽셀씩 비교한다. 자세한 내용은
# gfx/quest_sides.py 와 README_quest.md 의 "검증 방법" 참고.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    # 파이썬 표준 출력이 콘솔 코드페이지로 나가면 한글에서 죽는다
    $env:PYTHONIOENCODING = "utf-8"

    & "$PSScriptRoot\build_quest.ps1"

    $work = "$PSScriptRoot\build\sides"
    New-Item -ItemType Directory -Force $work | Out-Null

    # quest.sym 에서 주소를 읽으므로 빌드 뒤에 만들어야 한다
    & uv run --with pillow python "$PSScriptRoot\gfx\quest_sides.py" tcl $work
    if ($LASTEXITCODE -ne 0) { throw "tcl 생성 실패" }

    foreach ($tcl in Get-ChildItem "$work\*.tcl") {
        $name = $tcl.BaseName
        Remove-Item "$work\$name.png", "$work\$name.dump" -ErrorAction SilentlyContinue
        # "&" 가 아니라 Start-Process -Wait. openmsx.exe 는 GUI 서브시스템이라
        # 호출 연산자로는 끝날 때까지 기다리지 않는다.
        Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
            '-machine', $MSX_MACHINE,
            '-cart',    "`"$PSScriptRoot\build\quest.rom`"",
            '-romtype', 'ASCII8',
            '-script',  "`"$($tcl.FullName)`"") | Out-Null
        if (-not (Test-Path "$work\$name.png")) { throw "$name : 스크린샷이 생기지 않았습니다" }
    }

    & uv run --with pillow python "$PSScriptRoot\gfx\quest_sides.py" check $work
    if ($LASTEXITCODE -ne 0) { throw "옆면 검증 실패 - 위 표를 보세요" }
}
finally {
    Pop-Location
}
