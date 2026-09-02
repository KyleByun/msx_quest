# src/quest.asm 를 build/quest.rom (128KB ASCII8 카트리지 이미지) 으로 만든다.
#
# ROM 안에서 8KB 뱅크가 이렇게 놓인다.
#   뱅크 0~2  본체 코드와 자료   (실행 중 0x4000-0x9FFF 에 고정)
#   뱅크 3~4  몬스터 그림        (실행 중 0xA000-0xBFFF 에 번갈아)
#   뱅크 5     배경 화면 RLE      (시작할 때 한 번만 0xA000 에 불러 쓴다)
#   뱅크 6~15 빈 자리
#
# 몬스터 그림이 8,338 바이트라 32KB 로는 모자랐다. 뱅크마다 따로 어셈블해서
# 이어 붙이는 이유는, 뱅크 3, 4, 5 가 모두 0xA000 에 놓여 한 번에 어셈블할 수
# 없기 때문이다.
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools.ps1"

Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force "$PSScriptRoot\build" | Out-Null

    & $SJASMPLUS --msg=war --sym="build/quest.sym" --lst="build/quest.lst" "src/quest.asm"
    if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed with exit code $LASTEXITCODE" }

    # 0xA000 창에 걸리는 뱅크들. 순서가 곧 뱅크 번호(3 부터)다.
    # 여기 순서를 바꾸면 src/quest.asm 의 BG_BANK / FRONT_BANK 도 같이 고쳐야 한다.
    # quest8* 는 SCREEN 8 판(build_quest3.ps1)이 쓰므로 여기서는 걸러 낸다.
    $bankFiles = @(Get-ChildItem "src/questspr*.asm"       | Sort-Object Name) +
                 @(Get-ChildItem "src/questbgbank*.asm"    | Sort-Object Name) +
                 @(Get-ChildItem "src/questfrontbank*.asm" | Sort-Object Name) +
                 @(Get-ChildItem "src/questrunbank*.asm"   | Sort-Object Name)
    foreach ($f in $bankFiles) {
        & $SJASMPLUS --msg=war $f.FullName
        if ($LASTEXITCODE -ne 0) { throw "sjasmplus failed on $($f.Name)" }
    }

    $BANK = 8192
    $TOTAL = 131072
    $rom = New-Object byte[] $TOTAL

    $main = [System.IO.File]::ReadAllBytes("$PSScriptRoot\build\questmain.bin")
    if ($main.Length -ne 3 * $BANK) { throw "questmain.bin 이 $($main.Length) 바이트다 (24576 이어야 함)" }
    [Array]::Copy($main, 0, $rom, 0, $main.Length)

    $bankIndex = 3
    foreach ($f in $bankFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $bin = "$PSScriptRoot\build\$name.bin"
        $data = [System.IO.File]::ReadAllBytes($bin)
        if ($data.Length -ne $BANK) { throw "$name.bin 이 $($data.Length) 바이트다 (8192 이어야 함)" }
        [Array]::Copy($data, 0, $rom, $bankIndex * $BANK, $BANK)
        $bankIndex++
    }

    [System.IO.File]::WriteAllBytes("$PSScriptRoot\build\quest.rom", $rom)
    $used = 3 * $BANK + ($bankIndex - 3) * $BANK
    Write-Host "built: $PSScriptRoot\build\quest.rom ($TOTAL bytes, 뱅크 0~$($bankIndex-1) 사용 = $used 바이트)"
}
finally {
    Pop-Location
}
