# build/quest3.rom (SCREEN 8, 256색 - 지금 쓰는 판) 을 만들고 창으로 띄운다.
#
#   .\run_quest3.ps1              빌드하고 띄운다 (타이틀 없음 - 바로 게임)
#   .\run_quest3.ps1 --title      타이틀까지 넣어 빌드하고 띄운다
#   .\run_quest3.ps1 --no-build   이미 만들어 둔 롬을 그대로 띄운다
#
# PowerShell 은 매개변수를 -NoBuild / -Title 로만 알아본다. --no-build 와
# --title 은 남은 인자로 들어오므로 여기서 받아 준다 - run3.sh 와 같은 글자로
# 쓸 수 있어야 한다.
param(
    [switch]$NoBuild,
    [switch]$Title,
    [Parameter(ValueFromRemainingArguments = $true)]$Rest
)

if ($Rest -contains '--no-build') { $NoBuild = $true }
if ($Rest -contains '--title')    { $Title = $true }

# 모르는 인자는 그냥 넘어가지 않는다. --titel 같은 오타를 조용히 무시하면
# "타이틀 넣었는데 안 나온다" 로 이어진다. $null 도 걸러야 한다 - 인자를
# 하나도 안 주면 $Rest 가 $null 인데 파이프가 그것을 항목 하나로 흘려보낸다.
$known = @('--no-build', '--title')
$unknown = @($Rest | Where-Object { $null -ne $_ -and $known -notcontains $_ })
if ($unknown.Count -gt 0) {
    throw "모르는 인자: $($unknown -join ' ')  (쓸 수 있는 것은 --no-build / --title)"
}

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

$rom = "$PSScriptRoot\build\quest3.rom"

if ($NoBuild) {
    # --title 은 빌드에만 쓰는 것이라 --no-build 와 같이 주면 아무 뜻이 없다.
    # 조용히 무시하면 "타이틀 켰는데 안 나온다" 가 되므로 말해 준다.
    if ($Title) {
        Write-Host "--no-build 라서 --title 은 무시합니다 (지금 있는 롬을 그대로 띄웁니다)"
    }
    if (-not (Test-Path $rom)) {
        throw "$rom 이 없습니다. --no-build 를 빼고 한 번 빌드하세요."
    }
    $len = (Get-Item $rom).Length
    Write-Host "빌드 없이 띄웁니다: $rom ($len bytes)"
}
else {
    if ($Title) { & "$PSScriptRoot\build_quest3.ps1" --title }
    else        { & "$PSScriptRoot\build_quest3.ps1" }
}

# Start-Process -Wait 를 쓴다. & 는 openmsx.exe 같은 GUI 실행 파일을 안 기다린다.
Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
    '-machine', $MSX_MACHINE,
    '-cart',    "`"$rom`"",
    '-romtype', 'ASCII8'
)
