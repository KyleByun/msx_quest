# build/questprobe.rom (SCREEN 8 타진용) 을 만들고 창으로 띄운다. 에뮬레이터를 닫으면
# 돌아온다. 재는 것은 verify_questprobe.ps1 이 하고, 이건 눈으로 보는 용도다.
#
# 매퍼 없는 16KB 카트리지라 -romtype normal 을 준다.
#
# 화면에서 볼 것
#   위쪽 x 0..95   간격을 달리해 그린 띠 일곱 개 (0..95 그라데이션이라 줄무늬)
#   x 136 근처     명령 엔진(HMMV / HMMM) 으로 칠한 빨간 사각형 둘
#   아래 8 줄 x2   지금 팔레트 16색을 GRB332 로 옮긴 견본 / 256색 전부
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

& "$PSScriptRoot\build_questprobe.ps1"

# Start-Process -Wait 를 쓴다. & 는 openmsx.exe 같은 GUI 실행 파일을 안 기다린다.
Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
    '-machine', $MSX_MACHINE,
    '-cart',    "`"$PSScriptRoot\build\questprobe.rom`"",
    '-romtype', 'normal'
)
