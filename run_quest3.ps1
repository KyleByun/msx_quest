# build/quest3.rom (SCREEN 8 판) 을 만들고 창으로 띄운다.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

& "$PSScriptRoot\build_quest3.ps1"

# Start-Process -Wait 를 쓴다. & 는 openmsx.exe 같은 GUI 실행 파일을 안 기다린다.
Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
    '-machine', $MSX_MACHINE,
    '-cart',    "`"$PSScriptRoot\build\quest3.rom`"",
    '-romtype', 'ASCII8'
)
