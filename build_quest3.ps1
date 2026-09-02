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
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force "$PSScriptRoot\build" | Out-Null

    & $SJASMPLUS --msg=war --sym="build/quest3.sym" --lst="build/quest3.lst" "src/quest3.asm"
    if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed with exit code $LASTEXITCODE" }

    # 0xA000 창에 걸리는 뱅크들. 이 순서가 곧 뱅크 번호(3 부터)이고,
    # quest8const.asm 의 BG_BANK / FRONT_BANK / RUN_BANK0 계산과 같아야 한다.
    $bankFiles = @(Get-ChildItem "src/quest8spr*.asm"       | Sort-Object Name) +
                 @(Get-ChildItem "src/quest8bgbank*.asm"    | Sort-Object Name) +
                 @(Get-ChildItem "src/quest8frontbank*.asm" | Sort-Object Name) +
                 @(Get-ChildItem "src/quest8runbank*.asm"   | Sort-Object Name)
    foreach ($f in $bankFiles) {
        & $SJASMPLUS --msg=war $f.FullName
        if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed on $($f.Name)" }
    }

    $BANK = 8192
    $TOTAL = 131072
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
    Write-Host "built: $PSScriptRoot\build\quest3.rom ($TOTAL bytes, 뱅크 0~$($bankIndex-1) 사용 = $($bankIndex * $BANK) 바이트)"
}
finally {
    Pop-Location
}
