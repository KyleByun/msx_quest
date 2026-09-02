# SCREEN 8 (GRAPHIC 7) 로 옮길 만한지 잰다. src/questprobe.asm / gfx/questprobe.py 참고.
#
# 재는 것은 대역폭 하나다. 화면을 켜 둔 채 CPU 가 VRAM 을 만질 수 있는 최소
# 간격이 얼마인지, 그 간격에서 96x96 던전 뷰 한 장이 몇 ms 인지.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    $env:PYTHONIOENCODING = "utf-8"

    & "$PSScriptRoot\build_questprobe.ps1"

    $work = "$PSScriptRoot\build\s8"
    New-Item -ItemType Directory -Force $work | Out-Null
    Remove-Item "$work\probe.txt", "$work\vram.bin" -ErrorAction SilentlyContinue

    & uv run python "$PSScriptRoot\gfx\questprobe.py" tcl $work
    if ($LASTEXITCODE -ne 0) { throw "tcl 생성 실패" }

    Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
        '-machine', $MSX_MACHINE,
        '-cart',    "`"$PSScriptRoot\build\questprobe.rom`"",
        '-romtype', 'normal',
        '-script',  "`"$work\probe.tcl`"") | Out-Null
    if (-not (Test-Path "$work\vram.bin")) { throw "VRAM 덤프가 안 나왔습니다" }

    # 견줄 값 - 지금 SCREEN 5 의 던전 한 장이 몇 ms 인가. 옆에 있어야 결정이 된다.
    # 여기서 quest.rom 을 다시 빌드하지는 않는다 - 타진용 스크립트가 본 산출물을
    # 건드리면 안 된다. 없으면 그냥 건너뛰고, 그 칸만 빠진 채로 나머지를 낸다.
    if (-not (Test-Path "$PSScriptRoot\build\quest.rom")) {
        Write-Host "build/quest.rom 이 없어 견줄 값은 건너뜁니다 (build_quest.ps1 을 먼저 돌리세요)"
    }
    else {
    Remove-Item "$work\ref.txt" -ErrorAction SilentlyContinue
    # 재는 지도는 gfx/quest_sides.py 에서 가져온다. 그쪽이 quest_convert 를 타고
    # PIL 을 부르므로 pillow 가 필요하다.
    & uv run --with pillow python "$PSScriptRoot\gfx\questprobe.py" reftcl $work
    if ($LASTEXITCODE -ne 0) { throw "ref.tcl 생성 실패" }
    Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
        '-machine', $MSX_MACHINE,
        '-cart',    "`"$PSScriptRoot\build\quest.rom`"",
        '-romtype', 'ASCII8',
        '-script',  "`"$work\ref.tcl`"") | Out-Null
    }

    & uv run python "$PSScriptRoot\gfx\questprobe.py" check $work
    if ($LASTEXITCODE -ne 0) { throw "SCREEN 8 타진 실패 - 위 표를 보세요" }
}
finally {
    Pop-Location
}
