# src/quest3.asm 를 build/quest3.rom (128KB ASCII8) 으로 만든다.
#
# quest.rom 의 SCREEN 8 (GRAPHIC 7) 판이다. 코드는 quest.asm 을 그대로 쓰고
# (quest3.asm 이 SCREEN8 을 define 하고 include 한다), 자료만 8bpp 로 따로 굽는다.
#
#   뱅크 0~2   본체 코드와 자료      (0x4000-0x9FFF 고정)
#   그 뒤로     몬스터 그림 -> 배경 -> 정면 벽 -> 벽면 런
#
# 뱅크 번호는 자료 크기에 따라 달라지므로 어셈블러가 계산한다
# (quest8const.asm 의 BG_BANK / FRONT_BANK / RUN_BANK0).
param(
    [switch]$Title,
    [Parameter(ValueFromRemainingArguments = $true)]$Rest
)

# --title 을 주면 타이틀 화면이 들어간다. 안 주면 부팅하자마자 게임이다
# (테스트할 때 매번 넘기지 않으려고). 그림이 13 뱅크라 롬이 256KB 가 된다.
#
# PowerShell 은 매개변수를 -Title 로만 알아본다. --title 은 남은 인자로 들어오므로
# 여기서 받아 준다 - .sh 와 같은 글자로 쓸 수 있어야 한다.
#
#   .\build_quest3.ps1 --title     둘 다 된다
#   .\build_quest3.ps1 -Title
if ($Rest -contains '--title') { $Title = $true }

# 모르는 인자는 그냥 넘어가지 않는다. --titel 같은 오타를 조용히 무시하면
# "타이틀 넣었는데 안 나온다" 로 이어진다.
# $null 도 걸러야 한다. -Title 만 주면 $Rest 가 $null 인데, 파이프는 그것을
# 항목 하나로 흘려보내서 '모르는 인자: (빈칸)' 으로 멈췄다.
$unknown = @($Rest | Where-Object { $null -ne $_ -and $_ -ne '--title' })
if ($unknown.Count -gt 0) {
    throw "모르는 인자: $($unknown -join ' ')  (쓸 수 있는 것은 --title / -Title 뿐)"
}
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force "$PSScriptRoot\build" | Out-Null

    # 손으로 고치는 자료를 롬 표로 굽는다. 셋 다 1 초 안에 끝난다.
    #
    #   gfx/message.json  게임에 나오는 글 (한글은 달무리 8x8 을 여기서 조합한다)
    #   gfx/items.json    무기/방어구/소모품 한 표
    #   gfx/monster.json  몬스터 수치
    #
    # 값이 어긋나면 (양피지 폭을 넘거나, 한 바이트에 안 들어가거나, 없는 열쇠를
    # 가리키거나) **여기서 빌드가 멈춘다.** SCREEN 8 에는 픽셀 오라클이 없어서,
    # 안 막으면 화면을 눈으로 보다가 한참 뒤에 발견하게 된다.
    #
    # 벽면 픽셀(quest_convert.py)은 몇 분 걸리므로 여기 없다. 기하나 텍스처를
    # 고쳤을 때만 손으로 돌린다.
    foreach ($g in @(@('quest_msg.py'), @('quest_gear.py'), @('quest_rules.py', '--bpp', '8'))) {
        # $g | Select-Object -Skip 1 을 쓴다. $g[1..($n-1)] 은 인자가 없을 때
        # 1..0 이 되어 PowerShell 이 범위를 **뒤집으므로**, 스크립트 이름이
        # 자기 자신의 인자로 딸려 들어간다.
        & uv run --with pillow python "$PSScriptRoot\gfx\$($g[0])" @($g | Select-Object -Skip 1)
        if ($LASTEXITCODE -ne 0) { throw "$($g[0]) 실패" }
    }
    # 음악은 **늘** 굽는다. 전투곡은 --title 과 상관없이 울려야 한다.
    # numpy 로 mp3 를 PSG 세 채널로 옮긴다 (결과를 wav 로 들어 볼 수도 있다:
    # gfx/psg_music.py battle --wav).
    & uv run --with pillow --with numpy python "$PSScriptRoot\gfx\psg_music.py" title battle
    if ($LASTEXITCODE -ne 0) { throw "psg_music.py 실패" }
    if ($Title) {
        & uv run --with pillow python "$PSScriptRoot\gfx\quest_title.py"
        if ($LASTEXITCODE -ne 0) { throw "quest_title.py 실패" }
    }

    $defs = @()
    if ($Title) { $defs += '-DTITLE' }
    & $SJASMPLUS --msg=war @defs --sym="build/quest3.sym" --lst="build/quest3.lst" "src/quest3.asm"
    if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed with exit code $LASTEXITCODE" }

    # 0xA000 창에 걸리는 뱅크들. 이 순서가 곧 뱅크 번호(3 부터)이고,
    # quest8const.asm 의 BG_BANK / FRONT_BANK / RUN_BANK0 계산과 같아야 한다.
    $bankFiles = @(Get-ChildItem "src/quest8spr*.asm"       | Sort-Object Name) +
                 @(Get-ChildItem "src/quest8bgbank*.asm"    | Sort-Object Name) +
                 @(Get-ChildItem "src/quest8frontbank*.asm" | Sort-Object Name) +
                 @(Get-ChildItem "src/quest8runbank*.asm"   | Sort-Object Name) +
                 # 음악은 게임 뱅크 **뒤, 타이틀 앞**이다
                 # (MUSIC_BANK = RUN_BANK0 + RUN_BANKS 와 같은 차례여야 한다).
                 @(Get-ChildItem "src/quest8musicbank*.asm" | Sort-Object Name)
    if ($Title) {
        # 타이틀 그림은 그 뒤 (TITLE_BANK0 = MUSIC_BANK + MUSIC_BANKS).
        $bankFiles += @(Get-ChildItem "src/quest8titlebank*.asm" | Sort-Object Name)
    }
    foreach ($f in $bankFiles) {
        & $SJASMPLUS --msg=war $f.FullName
        if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed on $($f.Name)" }
    }

    $BANK = 8192
    # 128KB 로는 게임 14 뱅크 + 타이틀 13 뱅크가 안 들어간다. ASCII8 은 뱅크
    # 번호가 8 비트라 2MB 까지 되고, 256KB 는 openMSX 에서 확인했다.
    $TOTAL = if ($Title) { 262144 } else { 131072 }
    $rom = New-Object byte[] $TOTAL

    $main = [System.IO.File]::ReadAllBytes("$PSScriptRoot\build\quest8main.bin")
    if ($main.Length -ne 3 * $BANK) { throw "quest8main.bin 이 $($main.Length) 바이트다" }
    [Array]::Copy($main, 0, $rom, 0, $main.Length)

    $bankIndex = 3
    foreach ($f in $bankFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $data = [System.IO.File]::ReadAllBytes("$PSScriptRoot\build\$name.bin")
        if ($data.Length -ne $BANK) { throw "$name.bin 이 $($data.Length) 바이트다" }
        if (($bankIndex + 1) * $BANK -gt $TOTAL) { throw "128KB 를 넘었습니다 (뱅크 $bankIndex)" }
        [Array]::Copy($data, 0, $rom, $bankIndex * $BANK, $BANK)
        $bankIndex++
    }

    [System.IO.File]::WriteAllBytes("$PSScriptRoot\build\quest3.rom", $rom)
    $what = if ($Title) { "타이틀 있음" } else { "타이틀 없음 - 바로 게임" }
    Write-Host "built: $PSScriptRoot\build\quest3.rom ($TOTAL bytes, 뱅크 0~$($bankIndex-1) 사용, $what)"
}
finally {
    Pop-Location
}
