# 빌드한 뒤 창 없이 quest.rom 을 부팅해 스크린샷을 남긴다.

# -Keys 로 키 입력을 주면 이동/회전 뒤의 화면을 확인할 수 있다.

#   예:  .\verify_quest.ps1 -Keys "up,up,right,up"

param(

    [double] $Seconds = 9,

    [string] $Out     = "$PSScriptRoot\build\quest.png",

    [string] $Keys    = ""

)

$ErrorActionPreference = "Stop"



. "$PSScriptRoot\tools.ps1"



& "$PSScriptRoot\build_quest.ps1"

if ($LASTEXITCODE -ne 0) { throw "build failed" }



# MSX 키 매트릭스 8행의 커서 키 비트

$mask = @{ "left" = "0x10"; "up" = "0x20"; "down" = "0x40"; "right" = "0x80" }



$outTcl = $Out.Replace('\', '/')

$tcl = New-Object System.Text.StringBuilder

$t = $Seconds

foreach ($k in ($Keys -split ',' | Where-Object { $_ -ne "" })) {

    $m = $mask[$k.Trim().ToLower()]

    if (-not $m) { throw "unknown key '$k' (use left/right/up/down)" }

    [void]$tcl.AppendLine("after time $t { keymatrixdown 8 $m }")

    $t += 0.15

    [void]$tcl.AppendLine("after time $t { keymatrixup 8 $m }")

    $t += 0.35

}

[void]$tcl.AppendLine("after time $t { screenshot -raw -size auto `"$outTcl`" }")

[void]$tcl.AppendLine("after time $($t + 0.4) { exit }")



# BOM 없이 써야 한다. Tcl 은 UTF-8 BOM 을 첫 명령의 일부로 읽고 파싱에 실패한다.

$script = "$PSScriptRoot\build\quest_verify.tcl"

[System.IO.File]::WriteAllText($script, $tcl.ToString(), (New-Object System.Text.UTF8Encoding($false)))



if (Test-Path $Out) { Remove-Item $Out }



# "&" 가 아니라 Start-Process -Wait 를 쓴다. openmsx.exe 는 GUI 서브시스템이라

# 호출 연산자로는 끝날 때까지 기다리지 않는다.

$proc = Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -PassThru -ArgumentList @(

    '-machine', $MSX_MACHINE,

    '-cart',    "`"$PSScriptRoot\build\quest.rom`"",

    '-romtype', 'ASCII8',      # -cart 뒤에 와야 한다
    '-script',  "`"$script`""

)

if ($proc.ExitCode -ne 0) { throw "openMSX failed with exit code $($proc.ExitCode)" }

if (-not (Test-Path $Out)) { throw "스크린샷이 생기지 않았습니다 - 에뮬레이터가 일찍 끝났나?" }

Write-Host "screenshot: $Out"

