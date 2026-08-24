# MSX2 롬 두 개를 sjasmplus 로 빌드하기

한 저장소에서 성격이 다른 MSX2 카트리지 롬 두 개를 만듭니다.

| | `game.rom` | `quest.rom` |
|---|---|---|
| 무엇 | Zanac 풍 종스크롤 슈팅 | Bard's Tale 풍 1인칭 던전 |
| 크기 | **16KB** | **128KB** (ASCII8 매퍼) |
| 진입 | `src/main.asm` | `src/quest.asm` |
| 어셈블 횟수 | 1 번 | **3 번 + 이어 붙이기** |
| 화면 | SCREEN 5 + 하드웨어 스크롤 + 스프라이트 | SCREEN 5 + 미리 구운 원근 그림 |
| 초점 | 60fps 를 놓치지 않는 처리량 | 이동할 때의 쾌적함 |

둘 다 Z80 어셈블리로 쓰고, **그래픽과 표는 파이썬이 빌드 시점에 굽습니다.** 자세한 내용은 각각 [`README.md`](../README.md), [`README_quest.md`](../README_quest.md) 에 있습니다. 이 문서는 **어떤 환경에서 어떻게 빌드하는가**만 다룹니다.

---

## 1. 준비물

| 도구 | 버전 | 하는 일 |
|---|---|---|
| **sjasmplus** | 1.23.1 (win) | Z80 크로스 어셈블러 |
| **openMSX** | 21.0 | MSX2 에뮬레이터. 실행과 자동 검증 |
| **uv** | 0.11.16 | 파이썬 실행 (그래픽·표 생성) |
| **PowerShell** | 5.1 (Windows 기본) | 빌드 스크립트 |

파이썬 쪽은 `pillow` 하나만 씁니다. `uv run --with pillow python ...` 이면 가상환경을 따로 만들지 않아도 됩니다.

### 도구는 저장소 밖에 둡니다

```
D:\my\8bit\msx\tools\
    sjasmplus\sjasmplus-1.23.1.win\sjasmplus.exe
    openmsx\openmsx.exe
```

경로는 `tools.ps1` 한 곳에만 적혀 있고 나머지 스크립트가 그것을 읽습니다. 다른 MSX 프로젝트와 도구를 같이 쓰려는 것입니다.

```powershell
# tools.ps1
$ToolsRoot  = "D:\my\8bit\msx\tools"
$SJASMPLUS  = Join-Path $ToolsRoot "sjasmplus\sjasmplus-1.23.1.win\sjasmplus.exe"
$OPENMSX    = Join-Path $ToolsRoot "openmsx\openmsx.exe"
$MSX_MACHINE = "C-BIOS_MSX2"

foreach ($t in @($SJASMPLUS, $OPENMSX)) {
    if (-not (Test-Path $t)) { throw "tool not found: $t" }
}
```

> **기종은 `C-BIOS_MSX2`** 를 씁니다. openMSX 에 딸려 오는 공개 BIOS 라서 실기 롬 파일이 없어도 됩니다. 다만 **C-BIOS 는 RAM 을 0 으로 채우고 시작합니다.** 실기나 blueMSX 는 그렇지 않습니다 — 이것 때문에 한 번 크게 당했습니다(아래 5-5).

## 2. 폴더 구조

```
test/
  src/            어셈블리 원본
    main.asm          슈팅 게임 (16KB 롬)
    gfxconst.asm      \ convert.py 가 만든다
    gfxdata.asm       /
    quest.asm         던전 게임 (128KB 롬)
    quest*.asm        던전 게임의 나머지 (아래 참고)
  gfx/            파이썬 생성기
  doc/            이 문서들
  build/          결과물 (.rom, .sym, .lst)
  tools.ps1       도구 경로
  build.ps1       game.rom 빌드
  build_quest.ps1 quest.rom 빌드
  run.ps1         빌드 후 창 띄우기
  verify.ps1      빌드 후 헤드리스로 화면 저장
  verify_quest.ps1
```

`quest.rom` 쪽은 파일이 여럿입니다.

| 파일 | 내용 |
|---|---|
| `quest.asm` | 본체. 나머지를 `include` 한다 |
| `questconst.asm` / `questdata.asm` | 배경·벽면·맵. `quest_convert.py` 생성 |
| `questrules.asm` / `questruledata.asm` | D&D 표와 폰트. `quest_rules.py` 생성 |
| `questtext.asm` | 글자 찍기, 메시지 창 |
| `questmath.asm` | 곱셈·나눗셈 ([`z80_mult_div.md`](z80_mult_div.md)) |
| `questparty.asm` / `questfight.asm` / `questmon.asm` | 파티 생성, 전투, 몬스터 그림 |
| `questspr0.asm` / `questspr1.asm` | 몬스터 그림 뱅크. **따로 어셈블한다** |

## 3. 빌드

> **`.\` 를 꼭 붙입니다.** PowerShell 은 현재 폴더의 스크립트를 이름만으로 실행하지 않습니다.
> `build.ps1` 이라고 치면 `CommandNotFoundException` 이 납니다. 같은 이름의 파일을 폴더에
> 심어 두고 실행되게 하는 것을 막으려는 것이라, 유닉스 셸이 `.` 을 `PATH` 에 넣지 않는 것과
> 같은 이유입니다.
>
> 실행 정책에 걸려 `running scripts is disabled` 가 나오면 이 창에서만 풀거나
> (`Set-ExecutionPolicy -Scope Process -Bypass`), 계속 쓸 것이면 사용자 단위로 한 번
> 바꿉니다 (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`).

```powershell
.\build.ps1          # src/main.asm  -> build/game.rom  (16KB)
.\build_quest.ps1    # src/quest.asm -> build/quest.rom (128KB)

.\run.ps1            # game.rom 을 창으로 실행
.\verify.ps1         # 창 없이 부팅해 build/screenshot.png 저장
.\verify_quest.ps1   # 같은 것을 quest.rom 으로
```

그래픽과 표를 다시 구울 때:

```powershell
uv run --with pillow python gfx\convert.py          # 슈팅 게임 그래픽
uv run --with pillow python gfx\quest_convert.py    # 던전 배경·벽면
uv run --with pillow python gfx\quest_rules.py      # D&D 표, 폰트, 몬스터 그림
```

생성기가 `src/*.asm` 을 덮어쓰므로, 그 파일들은 **직접 고치지 않습니다.** 맨 위에 그렇게 적어 두었습니다.

### 3-1. 16KB 롬 — 한 번에 끝난다

```powershell
& $SJASMPLUS --msg=war --sym="build/game.sym" --lst="build/game.lst" "src/main.asm"
```

| 옵션 | 뜻 |
|---|---|
| `--msg=war` | 경고까지만 표시. 진행 로그를 줄인다 |
| `--sym=` | 심볼 파일. **에뮬레이터에서 중단점을 걸 때 쓴다** |
| `--lst=` | 리스팅. 어느 주소에 무엇이 놓였는지 본다 |

`main.asm` 끝에 출력 지시가 있습니다.

```asm
    SAVEBIN "build/game.rom", 0x4000, 0x4000
```

0x4000 부터 0x4000 바이트(16KB)를 파일로 씁니다. **어셈블러가 파일을 자동으로 만들어 주지 않습니다.** 범위를 직접 고르는 이 방식이 아래 4장의 핵심입니다.

### 3-2. 128KB 롬 — 세 번 어셈블하고 이어 붙인다

```
1) src/quest.asm      -> build/questmain.bin   24KB (뱅크 0~2)
2) src/questspr0.asm  -> build/questspr0.bin    8KB (뱅크 3)
3) src/questspr1.asm  -> build/questspr1.bin    8KB (뱅크 4)
4) 세 파일을 이어 붙이고 128KB 로 채운다        -> build/quest.rom
```

**왜 한 번에 못 하는가.** ASCII8 매퍼는 8KB 뱅크를 창에 갈아 끼웁니다. 뱅크 3 과 4 는 **둘 다 실행 중에 0xA000 에 놓입니다.** 어셈블러의 주소 공간은 64KB 하나뿐이라 같은 주소에 서로 다른 내용을 둘 수 없습니다. 그래서 뱅크마다 따로 어셈블합니다.

```asm
; questspr0.asm - 생성기가 만든다
    DEVICE NOSLOT64K
    ORG 0xA000
SprGoblin:
    db 0x00, 0x0C, ...
    ...
    ds 8192 - ($ - 0xA000), 0       ; 뱅크를 8KB 로 채운다
    SAVEBIN "build/questspr0.bin", 0xA000, 8192
```

각 그림이 어느 뱅크 어디에 있는지는 **생성기가 계산해서 상수로 내보냅니다.**

```asm
SPR_BANK_0   equ 3                  ; GOBLIN
SPR_ADDR_0   equ 0xA000
SPR_BANK_1   equ 3                  ; SLIME
SPR_ADDR_1   equ 0xA34D
...
SPR_BANK_5   equ 4                  ; MIMIC
SPR_ADDR_5   equ 0xA000
```

이어 붙이는 것은 PowerShell 이 합니다. 롬 파일 안에서 8KB 단위가 곧 뱅크 번호입니다.

```powershell
$BANK = 8192
$TOTAL = 131072
$rom = New-Object byte[] $TOTAL

$main = [System.IO.File]::ReadAllBytes("build\questmain.bin")
if ($main.Length -ne 3 * $BANK) { throw "questmain.bin 이 $($main.Length) 바이트다" }
[Array]::Copy($main, 0, $rom, 0, $main.Length)

$bankIndex = 3
foreach ($f in $sprFiles) { ... [Array]::Copy($data, 0, $rom, $bankIndex * $BANK, $BANK); $bankIndex++ }

[System.IO.File]::WriteAllBytes("build\quest.rom", $rom)
```

`questmain.bin` 이 정확히 24KB 인지 **어서션으로 확인합니다.** 본체가 24KB 를 넘으면 조용히 뱅크 3 을 밀어내서 그림이 깨집니다. 지금 본체는 23,276 / 24,576 바이트라 여유가 1,300 바이트뿐입니다.

## 4. sjasmplus 로 카트리지 롬을 만들 때 알아야 할 것

### 4-1. `DEVICE NOSLOT64K`

```asm
    DEVICE NOSLOT64K
```

sjasmplus 는 기본적으로 ZX Spectrum 을 가정합니다. 이 지시로 **뱅킹 없는 평평한 64KB 주소 공간**으로 바꿉니다. MSX 카트리지를 만들 때는 사실상 필수입니다. 두 롬 모두 첫 줄 근처에 있습니다.

### 4-2. 카트리지 헤더

MSX BIOS 는 각 슬롯의 0x4000 을 보고 `"AB"` 가 있으면 카트리지로 인식하고, 그다음 2 바이트를 초기화 진입점으로 삼아 호출합니다.

```asm
    ORG 0x4000
    db "AB"
    dw Init         ; INIT
    dw 0            ; STATEMENT
    dw 0            ; DEVICE
    dw 0            ; TEXT
    ds 6, 0
```

### 4-3. ORG 를 여러 번 쓴다 — 그런데 롬에 들어가는 것은 SAVEBIN 이 정한다

이게 다른 어셈블러에서 오면 가장 헷갈리는 부분입니다. 두 롬 모두 이런 모양입니다.

```asm
    ORG 0xC000          ; (1) 페이지 3 RAM - 변수 자리를 잡는다
Vars:
posX        ds 1
posY        ds 1
    ...

    ORG 0x4000          ; (2) 카트리지 롬
    db "AB"
    dw Init
    ...

    SAVEBIN "build/game.rom", 0x4000, 0x4000
```

**(1) 의 `ds` 는 롬에 들어가지 않습니다.** 주소만 매기고 지나갑니다. `SAVEBIN` 이 0x4000 부터 16KB 만 잘라 쓰기 때문입니다. C 로 치면 `.bss` 를 손으로 배치하는 셈입니다.

MSX 에서 이 방식이 통하는 이유는 **페이지 3(0xC000~0xFFFF)이 모든 MSX 에서 RAM 이고, 카트리지 INIT 이 돌 때 이미 매핑되어 있기** 때문입니다. 그래서 그냥 주소를 정해서 쓰면 됩니다.

여기서 파생되는 함정이 셋입니다.

**함정 1 — `db` 를 `ORG 0x4000` 앞에 두면 사라진다.**

D&D 표를 만들면서 생성 파일을 파일 맨 앞에서 `include` 했더니 화면이 잡음으로 나왔습니다. 그 시점의 주소가 0 이라 데이터가 **0x0000 에 깔렸고**, `SAVEBIN` 범위 밖이라 롬 파일에 들어가지 않았습니다. 라벨은 0x0000 근처를 가리켜서 실행 중에는 BIOS 영역을 읽었습니다.

지금은 생성기가 파일을 둘로 나눕니다. **`equ` 만 있는 파일은 맨 앞에서, `db` 가 있는 파일은 `ORG 0x4000` 뒤에서** `include` 합니다.

**함정 2 — RAM 을 나눠 잡았으면 지우는 것도 나눠 지워야 한다.**

던전 쪽은 `ORG` 를 세 번 써서 RAM 을 잡았습니다(0xC000 변수, 0xC100 면 상태와 문자열, 0xC200 파티와 몬스터). 그런데 초기화 코드는 첫 블록만 지우고 있었습니다.

```asm
    ld hl, Vars
    ld de, Vars + 1
    ld bc, VarsEnd - Vars - 1   ; 0xC000~0xC00E 만!
```

C-BIOS 는 RAM 이 0 으로 켜져서 우연히 돌아갔지만, blueMSX 에서는 부팅하자마자 "전투 중" 상태가 되어 조작이 먹지 않았습니다. 지금은 `RamStart` / `RamEnd` 라벨로 **전체**를 지웁니다.

**함정 3 — 남는 자리를 무엇으로 채우는가.**

`ds 0xA000 - $, 0xFF` 로 채우면 그 바이트가 SCREEN 5 에서 팔레트 15 번 픽셀 두 개입니다. 값이 깨져서 엉뚱한 곳을 그리면 **화면에 그 색 줄이 그어집니다.** 실제로 그 색 덕분에 위의 함정 2 를 찾았습니다.

### 4-4. 32KB 를 넘으면 페이지 2 를 직접 잡아야 한다

BIOS 는 `"AB"` 헤더를 보고 카트리지를 찾은 뒤 **그 슬롯을 페이지 1(0x4000~0x7FFF)에만** 넣어 줍니다. 페이지 2 는 여전히 RAM 입니다. 그래서 0x8000 위쪽 데이터를 읽으려면 직접 슬롯을 잡아야 합니다.

```asm
SelectPage2:
    in a, (0xA8)
    ld b, a
    and 0x0C                    ; 페이지 1 의 슬롯 번호 (bit 3-2)
    rlca
    rlca                        ; bit 5-4 자리로 옮긴다
    ld c, a
    ld a, b
    and 0xCF                    ; 페이지 2 자리를 비우고
    or c                        ; 같은 슬롯을 넣는다
    out (0xA8), a
    ret
```

**매퍼를 쓰든 안 쓰든 이건 따로 필요합니다.** 128KB 로 늘린 뒤에도 그대로 둡니다.

> 이것을 몰랐을 때 0x8000 위쪽이 전부 0xFF 로 읽혀서 압축 해제 루프가 무한 루프에 빠졌습니다. `-romtype` 을 이것저것 바꿔 봐도 소용없었는데, 매퍼 문제가 아니라 슬롯 문제였기 때문입니다.

### 4-5. ASCII8 매퍼 잡기

```asm
ASC8_P0     equ 0x6000          ; 0x4000-0x5FFF 를 정한다
ASC8_P1     equ 0x6800          ; 0x6000-0x7FFF
ASC8_P2     equ 0x7000          ; 0x8000-0x9FFF
ASC8_P3     equ 0x7800          ; 0xA000-0xBFFF

InitMapper:
    xor a
    ld (ASC8_P0), a             ; 뱅크 0 - 지금 여기서 돌고 있다
    inc a
    ld (ASC8_P1), a             ; 뱅크 1
    inc a
    ld (ASC8_P2), a             ; 뱅크 2
    inc a
    ld (ASC8_P3), a             ; 뱅크 3
    ret
```

롬이라 쓰기는 그냥 흘러가고 매퍼만 값을 받아 갑니다. **0x4000-0x5FFF 는 반드시 뱅크 0 이어야 합니다** — 지금 실행 중인 이 코드가 거기 있어서, 다른 뱅크로 바꾸면 그 순간 코드가 사라집니다.

## 5. 실행과 검증

### 5-1. 창으로 띄우기

```powershell
Start-Process -FilePath $OPENMSX -NoNewWindow -Wait -ArgumentList @(
    '-machine', 'C-BIOS_MSX2',
    '-cart',    "build\game.rom"
)
```

> `&` 호출 연산자가 아니라 **`Start-Process -Wait`** 를 씁니다. `openmsx.exe` 는 GUI 서브시스템 바이너리라 `&` 로 부르면 기다리지 않고 바로 돌아옵니다.

### 5-2. `-romtype` 은 `-cart` **뒤에** 온다

128KB 롬은 매퍼를 지정해 주는 편이 안전합니다.

```powershell
'-cart', 'build\quest.rom', '-romtype', 'ASCII8'
```

**순서를 바꾸면 openMSX 가 그냥 종료 코드 1 로 끝납니다.** 오류 메시지도 없어서 찾는 데 시간이 걸렸습니다.

### 5-3. 창 없이 검증하기

`-script` 로 Tcl 파일을 주면 openMSX 를 스크립트로 몰 수 있습니다. 화면 저장, 키 입력, 메모리 읽기, 중단점이 다 됩니다.

```tcl
set d "C:/temp"
proc key {t mask} {
    after time $t "keymatrixdown 8 $mask"
    after time [expr {$t+0.12}] "keymatrixup 8 $mask"
}
after time 9.0  { screenshot -raw -size auto "$d/shot.png" }
key 9.5 0x20                        ; 8행 bit5 = 위쪽 커서
after time 10.3 {
    puts [format "pos=(%d,%d)" [debug read memory 0xC000] [debug read memory 0xC001]]
}
after time 11.0 { exit }
```

MSX 키보드 매트릭스 8 행: bit4 왼쪽, bit5 위, bit6 아래, bit7 오른쪽, bit0 스페이스.

이 방식으로 **"이동·회전·벽 충돌이 지도와 맞는가"를 자동으로 확인**했습니다. 눈으로 보는 대신 좌표를 메모리에서 직접 읽습니다.

### 5-4. 속도 재기

`--sym` 으로 나온 심볼에 중단점을 걸어 구간 시간을 잽니다.

```tcl
debug set_bp 0x40FB {} { set ::t0 [machine_info time] }
debug set_bp 0x4065 {} {
    puts [format "%.2f ms" [expr {([machine_info time]-$::t0)*1000}]]
}
```

던전 한 번 그리는 데 92ms 라는 숫자가 이렇게 나왔습니다. 최적화를 할 때마다 같은 방법으로 다시 재서 표로 남겼습니다.

### 5-5. C-BIOS 는 RAM 이 0 으로 켜진다

**검증 환경이 실기보다 관대하다는 것을 기억해야 합니다.** C-BIOS 는 RAM 을 0 으로 채우고 시작합니다. 초기화하지 않은 변수가 있어도 우연히 돌아갑니다.

일부러 더럽혀서 시험할 수 있습니다.

```tcl
debug set_bp 0x4010 {} {                 ; 롬의 Init 진입점
    for {set a 0xC000} {$a <= 0xC2FF} {incr a} {
        debug write memory $a 0xFF
    }
}
```

이걸로 blueMSX 에서만 나던 증상을 openMSX 에서 그대로 재현했습니다. **새 변수를 추가할 때마다 한 번씩 돌려 볼 가치가 있습니다.**

## 6. 인코딩 — PowerShell 5.1 과 한글

| 파일 | 인코딩 |
|---|---|
| `.asm` | UTF-8 **BOM 없이** |
| `.ps1` | UTF-8 **BOM 포함** |

PowerShell 5.1 은 BOM 없는 `.ps1` 을 시스템 코드페이지(한국어 윈도우면 CP949)로 읽습니다. 한글 주석이 깨지면서 따옴표 짝이 안 맞아 **파서 오류**가 납니다. BOM 을 붙이면 해결됩니다.

파이썬 생성기가 `.asm` 을 쓸 때는 `encoding="utf-8"` 을 명시합니다. 콘솔 출력이 깨지면 `PYTHONIOENCODING=utf-8 PYTHONUTF8=1` 을 붙입니다.

> PowerShell 변수는 **대소문자를 구분하지 않습니다.** `$BANK = 8192` 를 써 놓고 아래에서 `$bank = 3` 을 쓰면 같은 변수입니다. 128KB 이어 붙이기 코드가 이것 때문에 한 번 멈췄습니다.

## 7. 파이썬으로 데이터를 굽는 이유

두 게임 모두 **그림과 표를 빌드 시점에 파이썬이 계산해서 `.asm` 으로 내보냅니다.** Z80 이 실행 중에 할 일을 최대한 줄이려는 것입니다.

- 슈팅: PNG → 타일·스프라이트 패턴 (`gfx/convert.py`)
- 던전: 참고 화면 → 배경 RLE, **원근이 적용된 벽면 픽셀** (`gfx/quest_convert.py`)
- 던전: 파이썬 D&D 소스 → 능력치·직업 표, 폰트, 몬스터 그림 (`gfx/quest_rules.py`)

특히 던전 쪽은 **칸 단위 이동에 90도 회전만 있으면 화면에 나올 벽면 모양이 상수**라는 점을 이용합니다. 화면좌표 → 텍스처좌표 변환을 원근 나눗셈까지 포함해 전부 미리 풀어 픽셀로 구워 둡니다. 실행 중에는 "이 칸이 벽인가"만 보고 바이트를 옮깁니다.

생성기는 **원본이 없어져도 빌드가 멈추지 않도록** 뽑아낸 값을 저장소 안에 남깁니다. 실제로 참고 스크린샷이 OneDrive 에서 사라져 빌드가 멈춘 적이 있어서 생긴 습관입니다.

---

## 더 읽을거리

- [`README.md`](../README.md) — 슈팅 게임. 처리량, 하드웨어 스크롤, 스프라이트 한계
- [`README_quest.md`](../README_quest.md) — 던전 게임. 원근 굽기, D&D 규칙 포팅, 겪은 버그들
- [`z80_mult_div.md`](z80_mult_div.md) — Z80 곱셈·나눗셈 (Grauw 문서 정리)
