;-----------------------------------------------------------------------------
; MSX2 던전 탐험 - Bard`s Tale / Wizardry 형태
;
; SCREEN 8 (GRAPHIC 7) 판 - **여기가 지금 쓰는 소스다.**
;
; src/quest.asm 은 SCREEN 5 판으로 얼려 두었다(보관용). 새 코드는 이 파일에
; 넣는다. 두 파일이 공유하는 것은 아래 include 하는 하위 파일들 뿐이고,
; 그쪽은 IFDEF SCREEN8 로 두 모드를 다 받는다.
;
; SCREEN 5 판을 남겨 둔 이유가 하나 더 있다 - verify_quest_sides.ps1 의
; **픽셀 단위 오라클이 4bpp 에서만 돈다.** 파이썬 모델이 4bpp 기준이라
; SCREEN 8 화면은 아직 눈으로만 확인한다. 하위 파일을 고칠 때 quest.rom 도
; 같이 빌드해 그 검사를 돌리면 공유 코드의 회귀를 잡을 수 있다.
;

; 128KB 카트리지 ROM, ASCII8 매퍼.
;
;   뱅크 0~2  0x4000-0x9FFF 에 고정. 코드와 실행 중 늘 필요한 자료.
;   뱅크 3~4  0xA000-0xBFFF 에 번갈아 건다. 몬스터 그림.
;
; 몬스터 그림 여섯 장이 8,338 바이트라 32KB 로는 모자랐다.
;
; 화면  : SCREEN 5 (GRAPHIC 4) 또는 SCREEN 8 (GRAPHIC 7). src/quest3.asm 이
;         SCREEN8 을 define 하고 이 파일을 그대로 include 한다. 두 모드가
;         다른 곳은 "픽셀 하나가 몇 바이트인가" 하나뿐이라 IFDEF 몇 군데면
;         되고, 전투·맵 생성·파티·글자는 두 모드가 같은 코드를 쓴다.
; 던전  : 화면 좌상단 1/4 안쪽의 96x96 뷰포트
; 배경  : 참고 스크린샷을 RLE 로 압축해 넣고 부팅 때 한 번 푼다
; 벽면  : 원근이 적용된 벽돌 텍스처를 미리 구워 넣고 실행 중에는 옮기기만 한다
;
; 왜 실행 중에 레이캐스팅을 하지 않는가
;   칸 단위 이동에 90도 회전만 있으므로, 화면에 나오는 벽면의 모양은 서 있는
;   위치와 무관하게 언제나 같다. 모양이 상수면 그 위에 입히는 텍스처도 상수다.
;   그래서 화면좌표 -> 텍스처좌표 변환(원근 나눗셈 포함)을 빌드 시점에 전부 풀어
;   픽셀로 구워 두었다. 실행 중에는 "이 칸이 벽인가"만 보고 바이트를 옮긴다.
;   나눗셈도 곱셈도, 픽셀 단위 계산도 없다.
;
; 그려야 할 때만 그린다. 이동이나 회전이 없으면 메인 루프는 아무것도 하지 않는다.
;
; 주의: ROM 이다. 자기 수정 코드를 쓸 수 없고 변하는 값은 페이지 3 RAM 에 둔다.
;-----------------------------------------------------------------------------

    DEFINE SCREEN8

    DEVICE NOSLOT64K

    IFDEF SCREEN8
    include "src/quest8rules.asm"
    include "src/quest8const.asm"
    ELSE
    include "src/questrules.asm"
    include "src/questconst.asm"
    ENDIF
    include "src/questmsgconst.asm"   ; 말과 상관없이 한 벌뿐이다
    include "src/questgearconst.asm"

;--- 입출력 포트 ---------------------------------------------------------------
VDP_DATA    equ 0x98
VDP_ADDR    equ 0x99
VDP_PAL     equ 0x9A
PPI_ROW     equ 0xAA            ; 키보드 행 선택 (하위 4비트)
PPI_COL     equ 0xA9            ; 키보드 열 읽기 (0이면 눌림)

;--- 키 (8행: bit7 오른쪽, bit6 아래, bit5 위, bit4 왼쪽) ----------------------
KEY_RIGHT   equ 7
KEY_DOWN    equ 6
KEY_UP      equ 5
KEY_LEFT    equ 4
KEY_SPACE   equ 0           ; 8 행 bit0

MAP_W       equ 16              ; 맵이 16 칸 폭이라 인덱스가 (y<<4)|x 로 끝난다

;--- ASCII8 매퍼 ---------------------------------------------------------------
; 여기에 쓰면 그 창에 걸리는 8KB 뱅크가 바뀐다. ROM 이라 쓰기는 그냥 흘러가고
; 매퍼만 값을 받아 간다.
ASC8_P0     equ 0x6000          ; 0x4000-0x5FFF 를 정한다
ASC8_P1     equ 0x6800          ; 0x6000-0x7FFF
ASC8_P2     equ 0x7000          ; 0x8000-0x9FFF
ASC8_P3     equ 0x7800          ; 0xA000-0xBFFF (몬스터 그림 창)
SPR_WIN     equ 0xA000

;--- 작업용 RAM ----------------------------------------------------------------
    ORG 0xC000
RamStart:
Vars:
posX        ds 1
posY        ds 1
facing      ds 1                ; 0=북 1=동 2=남 3=서
keyState    ds 1
prevKey     ds 1
needDraw    ds 1
curY        ds 1                ; 지금 칠하고 있는 스캔라인
addrOk      ds 1                ; VRAM 주소를 이미 잡아 두었는가
resumeX     ds 1                ; 건너뛴 뒤 다시 시작할 바이트 위치
blockDepth  ds 1                ; 앞으로 몇 칸 만에 벽에 막히는가 (없으면 MAXD+1)
frontH      ds 1                ; 아래 셋은 UnpackFront 가 부팅 때만 쓴다
frontW      ds 1
frontN      ds 1
frontVram   ds 2
bgBank      ds 1                ; 배경 풀 때 쓰는 자리 (부팅 때만)
bgN         ds 1
bgLenPtr    ds 2
bgEnd       ds 2
cellX       ds 1                ; 지금 보고 있는 구간의 칸
cellY       ds 1

; 옆면 상태를 정하는 동안 쓰는 자리. BuildVisibility 는 한 프레임에 한 번만
; 도니까 레지스터를 아끼는 것보다 이름을 붙여 두는 편이 낫다 - 이 프로젝트에서
; 레지스터를 뭉갠 버그를 다섯 번 겪었다.
segJ        ds 1                ; 지금 보는 구간 번호
sideRot     ds 1                ; 3 = 왼쪽, 1 = 오른쪽
faceF       ds 1                ; 면 번호 f = j*2 + 쪽
faceW       ds 1                ; 그 면의 띠 안 런 폭 (바이트)
selK        ds 1                ; 0 = 옆칸이 벽, 1..NSEG = 그 평면에서 만남, 0xFF = 없음
scanK       ds 1                ; 지금 보고 있는 평면
bandId      ds 1                ; 지금 채우는 띠 번호
bandK       ds 1
bandCap     ds 1                ; 그릴 수 있는 블록 번호의 한계
bandLim     ds 1                ; 이 띠의 마지막 블록 번호
bandPre     ds 1                ; 그리기 전에 건너뛸 바이트
bandPost    ds 1                ; 그린 뒤 건너뛸 바이트
fdx         ds 1                ; 바라보는 쪽으로 한 칸 (한 프레임에 한 번 구한다)
fdy         ds 1
sdx         ds 1                ; 지금 보는 옆쪽으로 한 칸
sdy         ds 1
rayX        ds 1                ; 평면을 하나씩 옮겨 가며 보는 칸
rayY        ds 1
lastM       ds 1                ; 그 칸이 옆으로 몇 칸 나가 있었는가
VarsEnd:

; 글자 찍기용
    ORG 0xC100
TextX       ds 1
TextY       ds 1
TextFg      ds 1
TextBg      ds 1
NumBuf      ds 5                ; 숫자를 오른쪽부터 채운다
NumBufEnd   ds 1                ; PutNumR 이 길이를 재는 기준
Seed        ds 2                ; 난수 상태

; 파티 만들 때 쓰는 임시 자리. 스택으로 돌리면 읽기 어려워져서 이름을 붙였다.
ClassUsed   ds 2                ; 이미 뽑은 직업 자리표 (열한 직업)
NamePtr     ds 2
NamePatPtr  ds 2                ; 이름 무늬를 훑는 자리
NamePrev    ds 1                ; 방금 쓴 글자 (같은 글자가 잇따르지 않게)
NameIdx     ds 1
TmpClassMods ds 2
TmpRaceMods ds 2
TmpLevel    ds 1
TmpBab      ds 1
RowY        ds 1
RowNo       ds 1
MemPtr      ds 2
MakePtr     ds 2

; 전투용
BattleOn    ds 1
RoundNo     ds 1
CmdFirst    ds 1                ; VDP 명령 블록의 시작 레지스터 번호
MsgPos      ds 2
MsgBuf      ds 24
Lang        ds 1                ; LANG_EN / LANG_KO
numKey      ds 1                ; 0 행의 숫자 1~6
prevNum     ds 1
StatOn      ds 1                ; 파티원 상태 화면이 열려 있는가
StatWho     ds 1                ; 보고 있는 사람 번호 (0~5)
StatRow     ds 1                ; 그리는 중인 줄 번호
StatPtr     ds 2                ; 그 사람의 기록
; 장비 루틴이 쓰는 이름 붙인 자리. push/pop 으로 돌리면 짝을 눈으로 세어야 해서
; 이 프로젝트가 여러 번 당했다(MakePtr 주석 참고).
GearWho     ds 1
GearIdx     ds 1
GearItem    ds 1
GearSlot    ds 1
GearTo      ds 1
GearAmt     ds 1
GearMax     ds 1
GearAc      ds 1
GearDcnt    ds 1
GearDside   ds 1
GearPty     ds 2
GearTmp     ds 2
StatPage    ds 1                ; 0 상태 / 1 무기 / 2 소지품 / 3 마법
StatPages   ds 1                ; 이 사람의 쪽 수 (캐스터면 4)
StatMode    ds 1                ; MODE_PAGE / CURSOR / ACTION / GIVE
StatCur     ds 1                ; 목록에서 커서가 선 줄 (화면 기준)
StatSel     ds 1                ; 동작 메뉴에서 고른 줄
StatFilter  ds 1                ; 0 이면 소지품 쪽, 그 밖이면 무기 쪽
StatIdx     ds 1                ; 훑는 중인 가방 칸
StatShown   ds 1                ; 화면에 찍은 줄 수
StatItem    ds 1                ; 그 자리의 품목 번호
StatAct     ds 1                ; 동작 메뉴를 그리는 중인 줄
StatDir     ds 1                ; 쪽 넘기는 방향
StatNum     ds 1                ; 방금 눌린 숫자
escKey      ds 1                ; 7 행의 ESC
prevEsc     ds 1
; SetLang 이 ldir 로 한꺼번에 채우므로 이 다섯은 **이 차례로 붙어 있어야** 한다.
MsgTab      ds 2                ; 지금 말의 문자열 표
MonNameTab  ds 2                ; 몬스터 이름
SkillNameTab ds 2               ; 기술 이름
ClassNameTab ds 2               ; 직업 이름
RaceNameTab ds 2                ; 종족 이름
WeaponNameTab ds 2              ; 무기 이름
CharAdv     ds 1                ; 방금 찍은 글자의 폭 (영문 6 / 한글 8)
AtkBonus    ds 1
TgtAc       ds 1
DmgCnt      ds 1
DmgSides    ds 1
DmgMod      ds 1
NatRoll     ds 1
CritFlag    ds 1
FightPtr    ds 2
TgtPtr      ds 2
TgtType     ds 2
TmpDmg      ds 1
TmpType     ds 1
TmpMon      ds 2

; 몬스터 그림 찍기용
SprY        ds 1
SprRows     ds 1
SprCol      ds 1
SprLen      ds 1

; 전투 진행
MonCount    ds 1                ; 이번에 나온 마릿수
MonKind     ds 1                ; 나온 종류 (한 무리는 한 종류다)
TurnHero    ds 1                ; 이번 차례에서 다음에 칠 영웅
TurnMon     ds 1                ; 다음에 칠 몬스터

; 민첩이 정하는 행동 횟수 (quest_sena.md 의 전투방식)
DexMin      ds 1                ; 이 라운드에 싸우는 것들 중 가장 낮은 민첩
ActHero     ds PARTY_N          ; 사람마다 이번 라운드의 행동 횟수
ActMon      ds 1                ; 몬스터의 행동 횟수 (한 무리는 한 종류라 하나면 된다)
ActPass     ds 1                ; 지금 몇 번째 바퀴인가 (1 부터)
PassActed   ds 1                ; 이 바퀴에 누구라도 움직였는가

; 명령 메뉴
MenuHero    ds 1                ; 지금 명령을 고르는 사람
MenuSel     ds 1                ; 고른 줄 (0..CMD_N-1)
MenuIdx     ds 1                ; 메뉴를 그리는 동안의 줄 번호
AtkMode     ds 1                ; 이번 한 방에만 걸리는 특수 효과 (0 이면 보통)
FleeDone    ds 1                ; 도망에 성공했으면 남은 차례를 멈춘다
StepCount   ds 1                ; 마주치기 판정용 걸음 수

; 지도 표시
MapOn       ds 1                ; 0=양피지, 그 외=미니맵
mKey        ds 1                ; 4 행의 M 키 상태 (keyState 와 별도)
prevM       ds 1                ; M 의 이전 상태 - 새로 눌림 판정용

; 실행 시간 맵 생성 (questlevel.asm). MapDataRam 은 0xC200 블록 뒤쪽에 둔다.
RoomCount   ds 1
RoomTarget  ds 1
RoomAttempts ds 1
RoomW       ds 1
RoomH       ds 1
RoomX       ds 1
RoomY       ds 1
RoomCX      ds 1
RoomCY      ds 1
PrevRoomX   ds 1
PrevRoomY   ds 1
MiniMapY    ds 1                ; DrawMap 이 채우는 맵 행 번호
MiniMapScreenY ds 1             ; 지도의 현재 화면 y
HeroXb      ds 1                ; 내 위치 화살표의 바이트 x (여섯 줄 내내 같다)

; 파티와 몬스터.
;
; ExpandTbl 은 페이지 머리에 둔다. PutChar 가 니블 값으로 표를 볼 때 하위
; 바이트만 바꾸면 되기 때문이다(글자 한 줄마다 네 번 본다).
; Party 는 0xC220 이라 32 로 나누어떨어진다. 사람 번호 * 32 를 하위 바이트에
; 더할 때 자리 올림이 나지 않는다.
    ORG 0xC200
ExpandTbl   ds 16 * 4 / PXB     ; 니블 하나가 픽셀 넷. 4bpp 32, 8bpp 64 바이트
Party       ds PARTY_N * PARTY_STRIDE
Monsters    ds MON_N * MON_STRIDE

; 장비. 파티 기록(32 바이트)을 늘리지 않으려고 나란한 배열로 둔다.
PartyGear   ds PARTY_N * GEAR_STRIDE

; 미니맵 한 행分 (questmap.asm). 맵 한 칸 = 3바이트.
MiniMapRow  ds MAP_W * MINIMAP_CELL / PXB

; 실행 시간 맵 생성의 결과 지도(1=벽, 0=통로)와 가 본 자리 기록(0=아직).
;
; 둘 다 페이지 머리에 두고 **SeenRam 을 MapDataRam 바로 다음 페이지**에 놓는다.
; 색인이 (y<<4)|x 로 같으므로 ld h,MapDataRam>>8 / ld l,색인 으로 지도를 짚고
; inc h 한 번이면 같은 칸의 방문 기록으로 넘어간다. 미니맵은 한 칸마다 둘 다
; 봐야 하는데 이 배치면 주소 계산이 한 번뿐이다.
;
; RamEnd 뒤에 두면 Init 의 0 지우기에서 빠지므로 RamEnd 앞에 둔다.
    ORG 0xC600
MapDataRam  ds MAP_W * MAP_W
    ORG 0xC700
SeenRam     ds MAP_W * MAP_W

; 면 상태 표. 면 번호로 바로 짚을 수 있게 페이지 머리에 둔다.
; ld d,Vis>>8 / ld e,면번호 / ld a,(de) 세 줄이면 상태가 나온다.
;
; VisPost 는 Vis 의 **바로 다음 페이지**다. 옆면을 그린 뒤 남은 블록을 건너뛸
; 바이트 수가 거기 있는데, inc d 한 번이면 옮겨 가므로 면 번호(E)를 그대로 쓴다.
    ORG 0xC800
Vis         ds 64
    ORG 0xC900
VisPost     ds 64
RamEnd:

STACK_TOP   equ 0xF380

;=============================================================================
    ORG 0x4000

;--- 카트리지 헤더 -------------------------------------------------------------
    db "AB"
    dw Init
    dw 0
    dw 0
    dw 0
    ds 6, 0

;-----------------------------------------------------------------------------
Init:
    di
    ld sp, STACK_TOP
    call SelectPage2            ; 0x8000 위쪽 데이터를 읽으려면 이것이 먼저다
    call InitMapper

    call InitVdp                ; 이 시점에는 화면 출력이 꺼져 있다
    IFNDEF SCREEN8
    call UploadPalette          ; SCREEN 8 에는 팔레트가 없다 (색이 GRB332 고정)
    ENDIF
    call UnpackBg               ; 압축한 배경을 VRAM 에 푼다
    call UnpackFront            ; 정면 벽을 화면 밖 VRAM 에 올려 둔다

    ld hl, RamStart             ; 작업 영역 **전체**를 0 으로
    ld de, RamStart + 1
    ld bc, RamEnd - RamStart - 1
    ld (hl), 0
    ldir

    ; RAM 을 지운 **뒤에** 말을 고른다. MsgTab 이 0 이면 첫 메시지에서
    ; 0 번지를 읽는다. 지금은 무조건 LANG_DEFAULT 로 시작하고, 고르는
    ; 화면을 붙일 때 여기서 그 화면을 부르면 된다.
    ld a, LANG_DEFAULT
    call SetLang

    ; 예전에는 여기서 Vars(0xC000~0xC00E) 만 지웠다. BattleOn 같은 값은
    ; 0xC100 위쪽에 있어서 켤 때 그대로 쓰레기였다. openMSX + C-BIOS 는 RAM 이
    ; 0 으로 켜져서 우연히 돌아갔지만, blueMSX 나 실기처럼 다른 값으로 켜지는
    ; 기계에서는 BattleOn 이 0 이 아니라 부팅하자마자 "전투 중" 이 되었다.
    ; 그러면 이동 키가 전부 무시되어 멈춘 것처럼 보이고, 쓰레기 MonKind 로
    ; 몬스터 그림을 그리다가 화면에 줄이 그어졌다.

    ld a, 1                     ; 시작 위치는 MakeLevel 이 첫 방 중심으로 정한다
    ld (posX), a                ; (MakeLevel 실패 대비 기본값)
    ld a, 13
    ld (posY), a
    ld a, 1
    ld (needDraw), a

    ld a, 0x40                  ; 화면 켜기 (스프라이트는 쓰지 않는다)
    ld c, 1
    call WriteVdpReg

    call SeedRng                ; RTC + R 레지스터로 시드를 만들고
    call MakeLevel              ; NetHack 식으로 방과 통로를 파 놓는다
    call RevealAround           ; 시작 자리 둘레는 처음부터 보인다

    call MakeParty
    call StartParty             ; 처음 짐을 넣고 기본 장비를 차게 한다
    call DrawParty
    call MsgReset

;-----------------------------------------------------------------------------
; 메인 루프
;
; 던전은 이동하거나 돌아설 때만 다시 그린다. 그 외에는 키만 본다.
;-----------------------------------------------------------------------------
MainLoop:
    call WaitVBlank
    ld a, (needDraw)
    or a
    jr z, .idle
    xor a
    ld (needDraw), a
    call RenderDungeon
    ld a, (BattleOn)            ; 전투 중이면 그 위에 몬스터를 얹는다.
    or a                        ; 던전을 먼저 그려야 지난 그림이 지워진다.
    jr z, .idle
    ld a, (MonKind)
    call DrawMonsterPic
.idle:
    call ReadInput
    call HandleInput
    jr MainLoop

; ---------------------------------------------------------------------------
; 이동이 있었고 지도가 켜져 있으면 미니맵을 다시 그린다.
; ---------------------------------------------------------------------------
AfterMove:
    call RevealAround           ; 지도를 안 보고 있어도 기록은 남겨야 한다
    ld a, (MapOn)
    or a
    ret z
    jp DrawMap

;-----------------------------------------------------------------------------
; 내 자리 둘레 3x3 을 '가 봤다'로 표시한다.
;
; 미니맵은 이 기록이 있는 칸만 그린다. 이미 표시된 칸은 다시 쓰지 않는다 - 한 걸음
; 옮기면 아홉 칸 중 여섯 칸은 직전에 이미 본 자리다.
;
; 맵 밖은 부호 없는 비교 하나로 걸러진다. x 가 0 일 때 x-1 은 0xFF 가 되는데
; MAP_W 보다 크므로 그대로 걸린다.
;-----------------------------------------------------------------------------
RevealAround:
    ld a, (posY)
    dec a
    ld c, a                     ; C = 볼 줄
    ld b, 3
.row:
    ld a, c
    cp MAP_W
    jr nc, .nextrow
    push bc
    ld a, (posX)
    dec a
    ld e, a                     ; E = 볼 칸
    ld b, 3
.col:
    ld a, e
    cp MAP_W
    jr nc, .nextcol
    ld a, c
    add a, a
    add a, a
    add a, a
    add a, a                    ; y * 16
    add a, e                    ; + x
    ld l, a
    ld h, SeenRam >> 8
    ld a, (hl)
    or a
    jr nz, .nextcol             ; 이미 본 자리는 건드리지 않는다
    ld (hl), 1
.nextcol:
    inc e
    djnz .col
    pop bc
.nextrow:
    inc c
    djnz .row
    ret

;-----------------------------------------------------------------------------
; 페이지 2 를 카트리지 슬롯으로 전환
;
; 이것이 없으면 0x8000 위쪽이 전부 0xFF 로 읽힌다. MSX BIOS 는 0x4000 의 "AB"
; 헤더를 보고 카트리지를 찾은 뒤 그 슬롯을 페이지 1 에만 넣어 준다. 페이지 2 는
; 여전히 RAM 이다. 32KB ROM 은 자기 슬롯을 페이지 2 에도 직접 넣어야 한다.
;
; PPI 포트 0xA8 이 페이지별 기본 슬롯을 담는다.
;   bit 1-0 = 페이지 0, 3-2 = 페이지 1, 5-4 = 페이지 2, 7-6 = 페이지 3
; 지금 페이지 1 에 들어 있는 슬롯(= 이 ROM 이 있는 슬롯)을 그대로 페이지 2 에
; 복사한다.
;
; 확장 슬롯에 꽂힌 경우 서브슬롯까지 맞춰야 하지만, 이 코드는 기본 슬롯만
; 다룬다. 대부분의 32KB 카트리지가 쓰는 방식이다.
;-----------------------------------------------------------------------------
;-----------------------------------------------------------------------------
; ASCII8 매퍼 초기화
;
; 켜질 때 네 창이 모두 뱅크 0 을 보고 있다. 0x4000-0x5FFF 는 그대로 두어야 지금
; 실행 중인 이 코드가 사라지지 않는다. 나머지 셋만 1, 2, 3 으로 올린다.
;-----------------------------------------------------------------------------
InitMapper:
    xor a
    ld (ASC8_P0), a             ; 0x4000-0x5FFF = 뱅크 0 (지금 여기서 돌고 있다)
    inc a
    ld (ASC8_P1), a             ; 0x6000-0x7FFF = 뱅크 1
    inc a
    ld (ASC8_P2), a             ; 0x8000-0x9FFF = 뱅크 2
    inc a
    ld (ASC8_P3), a             ; 0xA000-0xBFFF = 뱅크 3 (그림 첫 뱅크)
    ret

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

;-----------------------------------------------------------------------------
; VDP 초기 설정
;-----------------------------------------------------------------------------
InitVdp:
    ld hl, VdpRegs
    ld c, 0
    ld b, VdpRegsEnd - VdpRegs
.loop:
    ld a, (hl)
    inc hl
    out (VDP_ADDR), a           ; 값을 먼저 쓰고...
    ld a, c
    or 0x80                     ; ...그다음 0x80 | 레지스터 번호
    out (VDP_ADDR), a
    inc c
    djnz .loop
    ret

VdpRegs:
    IFDEF SCREEN8
    db 0x0E                     ; R#0  GRAPHIC 7 모드 (M5,M4,M3 = 1,1,1)
    ELSE
    db 0x06                     ; R#0  GRAPHIC 4 모드 (0,1,1)
    ENDIF
    db 0x00                     ; R#1  일단 화면 끔
    db 0x1F                     ; R#2  비트맵 페이지 0 을 0x00000 에
    db 0xFF                     ; R#3  (G4 에서는 미사용)
    db 0x03                     ; R#4  (G4 에서는 미사용)
    db 0x00                     ; R#5  스프라이트 미사용
    db 0x00                     ; R#6  스프라이트 미사용
    db 0x00                     ; R#7  테두리 색
    db 0x0A                     ; R#8  VR=1(VRAM 128K), SPD=1 로 스프라이트 끔
    db 0x80                     ; R#9  212라인
    db 0x00                     ; R#10
    db 0x00                     ; R#11
    db 0x00                     ; R#12
    db 0x00                     ; R#13
    db 0x00                     ; R#14 VRAM 주소 상위
    db 0x00                     ; R#15 상태 레지스터 선택 = S#0
    db 0x00                     ; R#16
    db 0x00                     ; R#17
    db 0x00                     ; R#18
    db 0x00                     ; R#19
    db 0x00                     ; R#20
    db 0x00                     ; R#21
    db 0x00                     ; R#22
    db 0x00                     ; R#23 수직 스크롤 없음
VdpRegsEnd:

; V9938 팔레트는 색 하나당 2바이트다. (R<<4)|B, 그다음 G. 채널당 3비트.
UploadPalette:
    xor a
    ld c, 16
    call WriteVdpReg            ; R#16 = 팔레트 포인터를 0 으로
    ld hl, PaletteData
    ld b, 32
.loop:
    ld a, (hl)
    inc hl
    out (VDP_PAL), a
    nop
    djnz .loop
    ret

;-----------------------------------------------------------------------------
; 배경 풀기
;
; RLE: 0x80|n 이면 다음 바이트를 n+1 회, 그 외 n 이면 이어지는 n+1 바이트 그대로.
; 화면 전체 27136 바이트를 VRAM 0x0000 부터 채운다. 화면이 꺼져 있는 동안
; 돌기 때문에 VRAM 접근 간격은 신경 쓰지 않아도 된다.
;
; 자료는 BG_BANK 부터의 뱅크에 있다. 0xA000 창을 잠깐 그쪽으로 돌렸다가 끝나면
; 몬스터 그림 뱅크로 되돌린다 - 안 되돌리면 첫 전투에서 그림 자리에서 배경
; 바이트를 읽는다.
;
; SCREEN 8 에서는 한 화면이 54,272 바이트라 RLE 도 8KB 뱅크 하나를 넘는다.
; 그래서 **뱅크마다 따로 압축해** 두었다(생성기의 split_bg). RLE 를 통째로 한 뒤
; 자르면 자르는 자리가 레코드 한가운데일 수 있는데, 픽셀 쪽에서 자르면 그런 일이
; 없다. 푸는 쪽은 VRAM 주소를 이어서 쓰기만 하면 된다.
;-----------------------------------------------------------------------------
UnpackBg:
    ld hl, 0
    call SetVramWrite
    ld a, BG_BANK
    ld (bgBank), a
    ld hl, BgChunkLen
    ld (bgLenPtr), hl
    ld a, BG_BANKS
    ld (bgN), a
.chunk:
    ld a, (bgBank)
    ld (ASC8_P3), a
    inc a
    ld (bgBank), a
    ld hl, (bgLenPtr)           ; 이 뱅크에 든 RLE 길이
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl
    ld (bgLenPtr), hl
    ld hl, 0xA000
    add hl, de
    ld (bgEnd), hl
    ld hl, 0xA000
.loop:
    ld a, (hl)
    inc hl
    bit 7, a
    jr z, .literal
    and 0x7F                    ; 같은 바이트 반복
    ld b, a
    inc b
    ld a, (hl)
    inc hl
.rep:
    out (VDP_DATA), a
    nop
    djnz .rep
    jr .more
.literal:
    ld b, a                     ; 이어지는 바이트를 그대로
    inc b
.lit:
    ld a, (hl)
    inc hl
    out (VDP_DATA), a
    djnz .lit
.more:
    ld de, (bgEnd)
    ld a, h
    cp d
    jr nz, .loop
    ld a, l
    cp e
    jr nz, .loop
    ld a, (bgN)
    dec a
    ld (bgN), a
    jp nz, .chunk
    ld a, SPR_FIRSTBK
    ld (ASC8_P3), a             ; 그림 첫 뱅크로 되돌린다
    ret

;-----------------------------------------------------------------------------
; 정면 벽을 화면 밖 VRAM 에 올린다
;
; 정면 벽은 화면에서 제일 큰 한 덩어리(깊이 1 이면 뷰포트의 57.8%)이고 **사각형
; 하나**다. 사각형 하나는 VDP 명령 하나로 끝나므로, 픽셀을 VRAM 에 미리 풀어
; 두고 그릴 때는 HMMM 으로 오려 붙인다. 잰 값으로 픽셀당 Z80 은 9.5 us, HMMM 은
; 4.6 us 라 깊이 1 에서 50 ms 가 24 ms 로 준다.
;
; 놓는 자리는 줄 FRONT_VY(=256) 아래다. SCREEN 5 는 한 페이지가 256 줄이고 화면에
; 나오는 것은 212 줄뿐이라 그 아래는 아무도 안 쓴다. VDP 명령의 y 는 10 비트라
; 거기까지 그대로 짚는다.
;
; 화면이 꺼져 있는 동안 돌기 때문에 VRAM 접근 간격은 신경 쓸 것 없다(otir).
;-----------------------------------------------------------------------------
UnpackFront:
    ld a, FRONT_BANK
    ld (ASC8_P3), a
    ; SCREEN 8 에서 줄 256 은 VRAM 0x10000 이라 16 비트를 넘는다. 하위 16 비트만
    ; HL 에 담고 A16 은 SetVramWriteFront 가 얹는다.
    ld hl, (FRONT_VY * VRAM_ROW) & 0xFFFF
    ld (frontVram), hl
    ld hl, 0xA000               ; 픽셀
    ld de, FrontUp              ; 깊이마다 (바이트폭, 줄 수)
    ld a, MAXD
    ld (frontN), a
.depth:
    ld a, (de)
    ld (frontW), a
    inc de
    ld a, (de)
    ld (frontH), a
    inc de
.row:
    push de
    push hl
    ld hl, (frontVram)
    call SetVramWriteFront
    ld de, VRAM_ROW             ; 다음 줄
    add hl, de
    ld (frontVram), hl
    pop hl
    ld a, (frontW)
    ld b, a
    ld c, VDP_DATA
    otir
    pop de
    ld a, (frontH)
    dec a
    ld (frontH), a
    jr nz, .row
    ld a, (frontN)
    dec a
    ld (frontN), a
    jr nz, .depth
    ld a, SPR_FIRSTBK
    ld (ASC8_P3), a             ; 그림 첫 뱅크로 되돌린다
    ret

;-----------------------------------------------------------------------------
; 던전 그리기 - 1단계: 통로
;
; RunData 는 줄마다 (면번호, 바이트폭, 픽셀들) 이 이어지고 폭 0 이면 줄 끝이다.
; 픽셀이 런 바로 뒤에 붙어 있으므로 포인터 하나로 순차 처리한다. 건너뛸 면이라도
; 폭만큼 포인터를 밀면 되므로 면별 색인이 필요 없다.
;
; 안쪽 루프는 레지스터만 쓴다. 처음에는 런마다 RAM 변수를 대여섯 번 읽고 썼는데
; ld a,(nn) 하나가 13 T-state 라 런당 250 T 를 넘었고, 런이 700 개쯤 되니 그것만
; 180k T 였다. 지금은 런당 80 T 수준이다.
;   HL = 데이터 포인터   B = 폭   C = VDP 데이터 포트   D = Vis 페이지
; outi 가 HL 과 B 를 쓰므로 이 배치를 무너뜨리면 안 된다.
;
; 텍스처 전송은 outi(16) + nop(4) + jp nz(10) = 30 T-state 로, 화면이 켜져 있는
; 동안 V9938 이 요구하는 29 를 넘긴다. 단색 채우기(29)와 사실상 같은 속도다.
;-----------------------------------------------------------------------------
RenderDungeon:
    call BuildVisibility
    ld a, VIEW_Y
    ld (curY), a
.line:
    call RunLinePtr             ; HL = 이 줄의 런 자료 (뱅크도 여기서 건다)
    call LineAddr               ; 줄 첫 런은 언제나 뷰포트 왼쪽 끝에서 시작한다
    ld c, VDP_DATA              ; 줄 도는 동안 계속 유지한다
    ld d, Vis >> 8
.run:
    ld a, (hl)                  ; 면 번호
    inc hl
    ld e, a
    ld a, (hl)                  ; 바이트 폭
    inc hl
    or a
    jp z, .eol                  ; 폭 0 은 줄의 끝
    ld b, a
    ld a, (de)                  ; 그 면의 상태
    or a
    jr z, .draw1                ; VIS_TEX - 가장 흔하므로 맨 앞
    cp VIS_OFS
    jr nc, .ofs                 ; VIS_OFS 이상 = 옆면 띠 안 (상수 오프셋)
    cp VIS_WALL2
    jr z, .wall2
    cp VIS_GAP2
    jr z, .gap2
    cp VIS_SKIP
    jp z, .skip1                ; 핸들러가 멀어 jr 사거리를 넘는다
    cp VIS_BLACK
    jr z, .black
    cp VIS_SKIP2
    jp z, .skip2
    ; VIS_SKIPN - 블록을 전부 건너뛴다. 총 바이트 수가 VisPost 에 있다.
    xor a
    ld (addrOk), a
    inc d
    ld a, (de)
    dec d
    add a, l
    ld l, a
    jp nc, .run
    inc h
    jp .run

.draw1:                         ; 단일 블록 (천장/바닥/한가운데)
    ld a, (addrOk)              ; CheckAddr 인라인 - 핫 패스라 call 값이 아깝다
    or a
    call z, ResumeAddr
.t1:
    outi                        ; 16
    nop                         ;  4
    jp nz, .t1                  ; 10  -> 합 30 T-state
    jp .run                     ; outi 가 이미 HL 을 끝까지 밀었다

; 옆면 '띠 안'. 블록 수가 면 번호마다 다르지만, 띠 안에서는 런 폭이 한 값으로
; 정해져 있어서(quest_convert.py 가 확인한다) "블록 n 개 건너뛰기"가 상수
; 바이트 수가 된다. 그래서 세는 루프 없이 더하기 두 번으로 끝난다.
.ofs:
    sub VIS_OFS                 ; 앞에서 건너뛸 바이트 수
    add a, l
    ld l, a
    jr nc, $ + 3                ; inc h 한 바이트를 건너뛴다
    inc h
    ld a, (addrOk)
    or a
    call z, ResumeAddr
    push bc
.t2:
    outi
    nop
    jp nz, .t2
    pop bc
    inc d                       ; 그린 뒤 남은 바이트 수
    ld a, (de)
    dec d
    add a, l
    ld l, a
    jp nc, .run
    inc h
    jp .run

.wall2:                         ; 띠 바깥 - 앞(벽면)을 그리고 뒤는 건너뛴다
    ld a, (addrOk)
    or a
    call z, ResumeAddr
    push bc
.t3:
    outi
    nop
    jp nz, .t3
    pop bc
    jr .advance

.gap2:                          ; 띠 바깥 - 앞을 건너뛰고 뒤(뚫림)를 그린다
    ld a, b
    add a, l
    ld l, a
    jr nc, $ + 3
    inc h
    ld a, (addrOk)
    or a
    call z, ResumeAddr
.t4:
    outi
    nop
    jp nz, .t4
    jp .run                     ; 마지막 블록이라 더 밀 것이 없다

.black:                         ; 통로 끝의 어둠
    ld a, (addrOk)
    or a
    call z, ResumeAddr
    push bc
    ld a, BLACK_BYTE
.bl:
    out (VDP_DATA), a           ; 11
    nop                         ;  4
    dec b                       ;  4
    jp nz, .bl                  ; 10  -> 합 29 T-state
    pop bc
    jr .advance

.skip2:                         ; 두 블록을 다 건너뛴다 - 한 번 밀고 아래로 이어진다
    ld a, b
    add a, l
    ld l, a
    jr nc, $ + 3
    inc h
.skip1:                         ; 정면 벽에 가려진다 - 그리지 않고 지나간다
    xor a
    ld (addrOk), a
.advance:
    ld a, b                     ; HL += 폭 (블록 하나만큼)
    add a, l
    ld l, a
    jp nc, .run                 ; 분기 처리가 늘어 jr 사거리를 넘었다 (jp 가 오히려 1 T 빠르다)
    inc h
    jp .run

.eol:
    ld a, (curY)
    inc a
    ld (curY), a
    cp VIEW_Y + VIEW_H
    jp nz, .line
    ; 이어서 2단계로 넘어간다

;-----------------------------------------------------------------------------
; 던전 그리기 - 2단계: 정면 벽
;
; 앞이 막혔으면 그 거리의 정면 벽 비트맵을 통째로 붙인다. 1단계에서 가려지는
; 면들을 건너뛰었으므로 같은 자리를 두 번 그리지 않는다.
;-----------------------------------------------------------------------------
; 픽셀은 UnpackFront 가 부팅 때 화면 밖 VRAM 에 올려 두었다. 여기서는 그
; 깊이의 HMMM 명령 블록 하나를 쏟아붓기만 하면 된다 - Z80 이 미는 코드가
; 통째로 없어졌다.
;
; 끝날 때까지 기다린다. 이 뒤에 몬스터 그림이나 글자가 CPU 로 VRAM 을 만지는데,
; 명령이 도는 중에 CPU 가 VRAM 을 건드리면 둘 다 어그러진다.
DrawFront:
    ld a, (blockDepth)
    cp MAXD + 1
    ret nc                      ; 끝까지 안 막혔으면 할 일이 없다
    call FrontCmdFor            ; HL = 그 깊이의 명령 블록
    ld a, 32                    ; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
    ld (CmdFirst), a
    ld b, 15
    call SendVdpCmd
    jp WaitVdpCmd

;-----------------------------------------------------------------------------
; 이 줄의 런 자료를 짚는다. 0xA000 창에 그 뱅크를 걸고 HL 을 맞춘다.
;
; 런 자료는 본체에 안 들어간다(12KB, 8bpp 면 24KB). 줄마다 어느 뱅크 어디인지를
; RunLineTab 이 (뱅크, 주소) 로 적어 두었다. 줄 안에서는 포인터가 앞으로만
; 가므로 여기서 한 번 잡아 주면 그 줄 동안 다시 볼 것이 없다.
;
; 뱅크 경계를 그때그때 검사하는 방법도 있지만, 그러려면 "줄이 끝난 자리가 곧
; 다음 줄의 시작"이라는 약속이 필요하고 뱅크 끝의 남는 자리를 메우는 순간
; 그것이 깨진다. 표를 보는 편이 약속이 없어서 안전하다 - 96 줄에 1.1 ms 다.
;-----------------------------------------------------------------------------
RunLinePtr:
    ld a, (curY)
    sub VIEW_Y
    ld l, a
    ld h, 0
    ld d, h
    ld e, l
    add hl, hl
    add hl, de                  ; 한 줄에 3 바이트
    ld de, RunLineTab
    add hl, de
    ld a, (hl)
    ld (ASC8_P3), a             ; 그 줄의 런이 든 뱅크
    inc hl
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ret

; A = blockDepth (1..MAXD) -> HL = 그 깊이의 HMMM 명령 블록
FrontCmdFor:
    dec a
    add a, a
    ld l, a
    ld h, 0
    ld de, FrontCmdPtr
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ret

;-----------------------------------------------------------------------------
; 건너뛴 뒤 VRAM 주소를 다시 잡는다.
;
; 가려지는 구간은 화면 한가운데의 사각형(정면 벽) 하나뿐이라, 줄마다 [그림]
; [건너뜀][그림] 세 덩어리로만 나뉜다. 그래서 다시 시작할 x 는 렌더 한 번 동안
; 상수이고(resumeX), 런마다 x 를 세고 있을 필요가 없다.
;
; HL, BC, DE 를 모두 보존해야 한다 - 부르는 쪽이 outi 배치를 유지 중이다.
;-----------------------------------------------------------------------------
; 줄 첫 런의 주소. 가려지는 구간은 화면 한가운데뿐이라 줄은 언제나 왼쪽 끝에서
; 시작한다. 처음에는 이 주소와 "건너뛴 뒤 재개 주소"를 한 변수로 썼는데, 앞이
; 막힌 경우 줄 첫 런이 화면 한가운데에 그려져 통로가 통째로 사라졌다.
LineAddr:
    push hl
    push bc
    push de
    ld a, (curY)
    call RowAddr
    ld de, VIEW_XB
    add hl, de
    call SetVramWrite
    pop de
    pop bc
    pop hl
    ld a, 1
    ld (addrOk), a
    ret

ResumeAddr:
    push hl
    push bc
    push de
    ld a, (curY)
    call RowAddr
    ld a, (resumeX)
    ld e, a
    ld d, 0
    add hl, de
    call SetVramWrite
    pop de
    pop bc
    pop hl
    ld a, 1
    ld (addrOk), a
    ret

;-----------------------------------------------------------------------------
; 면 상태 정하기
;
; 지도를 여기서 한 번만 본다. 그리는 루프 안에는 지도 조회가 없다.
;   VIS_TEX   : 구워 둔 텍스처 그대로 (천장/바닥)
;   VIS_BLACK : 끝까지 안 막힌 한가운데의 어둠
;   VIS_SKIP  : 정면 벽에 가려지므로 1단계에서 건너뛴다
;   VIS_WALL2 / VIS_GAP2 / VIS_SKIP2 : 좌우 벽의 띠 바깥 (블록 두 개)
;   VIS_OFS.. / VIS_SKIPN            : 좌우 벽의 띠 안 (SideVis 참고)
;-----------------------------------------------------------------------------
BuildVisibility:
    ld a, (facing)              ; 앞으로 한 칸 가는 델타. 여기서 한 번만 구한다.
    add a, a
    ld l, a
    ld h, 0
    ld de, DirTab
    add hl, de
    ld a, (hl)
    ld (fdx), a
    inc hl
    ld a, (hl)
    ld (fdy), a

    ld a, MAXD + 1              ; 앞으로 몇 칸 만에 막히는지 찾는다
    ld (blockDepth), a
    ld b, 1
.scan:
    push bc
    ld a, b
    call CellAhead
    call IsWall
    pop bc
    jr z, .scannext
    ld a, b
    ld (blockDepth), a
    jr .scandone
.scannext:
    inc b
    ld a, b
    cp MAXD + 1
    jr c, .scan
.scandone:

    ; 줄의 왼쪽 덩어리는 언제나 뷰포트 왼쪽 끝에서 시작한다. 건너뛴 뒤 다시
    ; 시작할 x 는 정면 벽 사각형의 오른쪽 끝이다.
    ld a, VIEW_XB
    ld (resumeX), a
    ld a, (blockDepth)
    cp MAXD + 1
    jr nc, .centreopen

    ; 명령 블록에서 사각형의 오른쪽 끝을 꺼낸다. DX 가 +4, NX 가 +8 이고 둘 다
    ; 픽셀 단위라, 더해서 반으로 나누면 바이트 단위 x 가 된다.
    call FrontCmdFor
    ld de, 4
    add hl, de
    ld a, (hl)                  ; DX
    add hl, de
    add a, (hl)                 ; + NX = 사각형의 오른쪽 끝(픽셀)
    call XToByte
    ld (resumeX), a

    ld a, VIS_SKIP              ; 한가운데는 정면 벽이 덮는다
    jr .setcentre
.centreopen:
    ld a, VIS_BLACK             ; 끝까지 안 막혔으면 어둠
.setcentre:
    ld c, CENTRE_ID
    call SetVis

    xor a                       ; 구간마다 면의 상태를 정한다
    ld (segJ), a
.each:
    ld a, (segJ)
    add a, a                    ; 천장 = j*2, 바닥 = j*2+1
    ld c, a
    ld a, (segJ)
    ld hl, blockDepth
    cp (hl)
    jr c, .openseg              ; 이 구간은 아직 막히기 전

    ld a, VIS_SKIP              ; 막힌 칸부터 안쪽은 전부 정면 벽이 덮는다
    call SetVis                 ; 천장
    inc c
    call SetVis                 ; 바닥
    ld a, 3
    call SideSkip               ; 왼쪽
    ld a, 1
    call SideSkip               ; 오른쪽
    jr .eachnext

.openseg:
    ld a, VIS_TEX
    call SetVis                 ; 천장
    inc c
    call SetVis                 ; 바닥

    ld a, (segJ)                ; 옆칸을 보려면 이 구간의 칸이 필요하다
    call CellAhead
    ld a, d
    ld (cellX), a
    ld a, e
    ld (cellY), a

    ld a, 3                     ; 왼쪽 (facing - 1)
    call SideVis
    ld a, 1                     ; 오른쪽 (facing + 1)
    call SideVis

.eachnext:
    ld hl, segJ
    inc (hl)
    ld a, (hl)
    cp NSEG
    jp c, .each
    ret

;-----------------------------------------------------------------------------
; 옆면 하나
;
;   A = 회전량 (3 = 왼쪽, 1 = 오른쪽),  (segJ) = 구간 번호
;
; 옆칸 하나만 봐서는 그릴 그림이 정해지지 않는다. 광선이 그 자리를 지나
; 평면 z = k 에서 만나는 것은 **옆으로 LatTab[j][k] 칸, 앞으로 k 칸**인 칸이다.
; 그래서 k = j+1 부터 NSEG 까지 차례로 보고 처음 만나는 벽을 찾는다.
;
;   옆칸이 벽        -> 블록 0 (비스듬한 벽면)
;   평면 k 에서 만남 -> 블록 k-j (그 평면의 정면)
;   끝까지 없음      -> 마지막 블록 (바닥/천장만 이어진다)
;
; 한때 k = j+1 하나만 봤다. 그러면 광장이나 폭이 넓은 통로에서 저 멀리 이어진
; 벽이 기둥 두 개로 끊겨 보인다 - 두 칸까지만 보고 그 너머를 어둠으로 둔 탓이다.
;-----------------------------------------------------------------------------
SideVis:
    call SideFace               ; (faceF), (faceW), (bandId), (sdx), (sdy)

    ld a, (cellX)               ; 옆칸이 벽인가 = 이 구간의 칸 + 옆으로 하나
    ld hl, sdx
    add a, (hl)
    ld d, a
    ld a, (cellY)
    ld hl, sdy
    add a, (hl)
    ld e, a
    call IsWall
    ld a, 0                     ; 0 = 옆칸이 벽
    jr nz, .sel

    ; 뚫렸다. k = j+1 .. NSEG 를 차례로 본다.
    ;
    ; 평면마다 칸을 처음부터 다시 세지 않는다. k 를 하나 늘리면 앞으로 한 칸이고,
    ; 옆으로 몇 칸인지는 LatTab 이 0 아니면 1 만큼만 늘기 때문이다. 매번 다시
    ; 세던 판은 BuildVisibility 하나가 16ms 를 먹었다.
    ld a, (segJ)
    inc a
    ld (scanK), a
    call CellAhead              ; D,E = (j+1) 칸 앞
    call LatM                   ; A = 그 평면에서 옆으로 몇 칸
    ld (lastM), a
    ld b, a
.mstep:
    ld a, d
    ld hl, sdx
    add a, (hl)
    ld d, a
    ld a, e
    ld hl, sdy
    add a, (hl)
    ld e, a
    djnz .mstep
    ld a, d
    ld (rayX), a
    ld a, e
    ld (rayY), a
.scan:
    ld a, (rayX)
    ld d, a
    ld a, (rayY)
    ld e, a
    call IsWall
    ld a, (scanK)
    jr nz, .sel                 ; 여기서 만났다
    inc a
    ld (scanK), a
    cp NSEG + 1
    jr nc, .none

    ld hl, rayX                 ; 다음 평면 - 앞으로 한 칸
    ld a, (fdx)
    add a, (hl)
    ld (hl), a
    ld hl, rayY
    ld a, (fdy)
    add a, (hl)
    ld (hl), a
    call LatM                   ; 옆으로 한 칸 더 나가는 해인가
    ld hl, lastM
    ld c, a
    sub (hl)
    ld (hl), c
    or a
    jr z, .scan
    ld hl, rayX
    ld a, (sdx)
    add a, (hl)
    ld (hl), a
    ld hl, rayY
    ld a, (sdy)
    add a, (hl)
    ld (hl), a
    jr .scan
.none:
    ld a, 0xFF                  ; 볼 수 있는 데까지 아무것도 없다
.sel:
    ld (selK), a

    or a                        ; 띠 바깥은 벽이냐 뚫렸냐 둘뿐이다
    ld a, VIS_WALL2
    jr z, .outer
    ld a, VIS_GAP2
.outer:
    push af
    ld a, (faceF)
    add a, OUTER0
    ld c, a
    pop af
    call SetVis

    ; 띠 안: K = j+1 .. NSEG
    ;
    ; 그릴 블록 번호는 index = min(cap, K-j+1) 이다. cap 은 옆칸이 벽이면 0,
    ; 평면 s 에서 만나면 s-j, 끝까지 없으면 무한(0xFF)이다. K 가 하나 늘면
    ; 한계가 하나 늘고 총 바이트가 폭만큼 는다. 그러니 곱셈은 첫 띠에서 한 번만
    ; 하고, 그다음부터는 **앞이나 뒤 둘 중 하나에 폭을 더하기만** 하면 된다.
    ; 띠마다 곱셈 두 번씩 하던 판은 BuildVisibility 하나가 15ms 를 먹었다.
    ld a, (selK)
    or a
    jr z, .havecap              ; 옆칸이 벽 -> 0 번 블록
    cp 0xFF
    jr z, .havecap              ; 끝까지 없음 -> 언제나 마지막 블록
    ld hl, segJ
    sub (hl)                    ; cap = s - j
.havecap:
    ld (bandCap), a

    ld a, 2                     ; 첫 띠(K = j+1)의 한계
    ld (bandLim), a
    ld a, (bandCap)
    cp 2
    jr c, .capsmall
    ld a, 2
.capsmall:
    call MulW                   ; 앞에서 건너뛸 바이트 = min(cap,2) * 폭
    ld (bandPre), a
    ld c, a
    ld a, (faceW)               ; 첫 띠의 총 바이트 = 2 * 폭
    add a, a
    sub c
    ld (bandPost), a

    ld a, (segJ)
    inc a
    ld (bandK), a
.band:
    ld a, (bandPre)
    add a, VIS_OFS
    ld c, a
    ld a, (bandId)
    ld l, a
    ld h, Vis >> 8
    ld (hl), c
    ld h, VisPost >> 8
    ld a, (bandPost)
    ld (hl), a

    ld hl, bandK                ; 다음 띠로
    inc (hl)
    ld a, (hl)
    cp NSEG + 1
    ret nc
    ld hl, bandId
    inc (hl)
    ld hl, bandLim
    inc (hl)
    ld a, (bandCap)             ; 한계가 늘어 index 가 따라 늘 수 있는가
    cp (hl)
    jr c, .growpost             ; cap < 한계 -> index 는 그대로, 뒤가 는다
    ld hl, bandPre
    jr .grow
.growpost:
    ld hl, bandPost
.grow:
    ld a, (faceW)
    add a, (hl)
    ld (hl), a
    jr .band

;-----------------------------------------------------------------------------
; 가려진 구간의 옆면. A = 회전량. 블록을 전부 건너뛰게 해 둔다.
;-----------------------------------------------------------------------------
SideSkip:
    push bc
    call SideFace
    ld a, (faceF)
    add a, OUTER0
    ld c, a
    ld a, VIS_SKIP2
    call SetVis

    ld a, (segJ)                ; 첫 띠의 블록은 셋 - 총 3 * 폭 바이트다.
    inc a                       ; 띠가 하나 깊어질 때마다 폭만큼 늘어난다.
    ld (bandK), a
    ld a, (faceW)
    ld c, a
    add a, a
    add a, c
    ld (bandPost), a
.band:
    ld a, (bandId)
    ld l, a
    ld h, VisPost >> 8
    ld a, (bandPost)
    ld (hl), a
    ld h, Vis >> 8
    ld (hl), VIS_SKIPN

    ld hl, bandK
    inc (hl)
    ld a, (hl)
    cp NSEG + 1
    jr nc, .done
    ld hl, bandId
    inc (hl)
    ld hl, bandPost
    ld a, (faceW)
    add a, (hl)
    ld (hl), a
    jr .band
.done:
    pop bc
    ret

;-----------------------------------------------------------------------------
; A = 회전량 -> (sideRot), (faceF), (faceW), (bandId), (sdx), (sdy) 를 채운다.
; f = j*2 + 쪽 (왼쪽 0, 오른쪽 1).
;-----------------------------------------------------------------------------
SideFace:
    ld (sideRot), a
    ld hl, facing               ; 그쪽으로 한 칸 가는 델타를 미리 꺼내 둔다
    add a, (hl)
    and 3
    add a, a
    ld l, a
    ld h, 0
    ld de, DirTab
    add hl, de
    ld a, (hl)
    ld (sdx), a
    inc hl
    ld a, (hl)
    ld (sdy), a

    ld a, (segJ)
    add a, a
    ld e, a
    ld a, (sideRot)
    cp 3
    jr z, .left
    inc e                       ; 오른쪽
.left:
    ld a, e
    ld (faceF), a
    ld d, 0
    push de
    ld hl, SideWidth
    add hl, de
    ld a, (hl)
    ld (faceW), a
    pop de
    ld hl, SideBandBase
    add hl, de
    ld a, (hl)
    ld (bandId), a
    ret

;-----------------------------------------------------------------------------
; A = LatTab[(segJ)][(scanK)] - 그 평면에서 광선이 옆으로 몇 칸 나가 있는가.
;
; 화면에서 그 옆면을 채우는 광선은 평면 z=k 에서 옆으로 s*k 만큼 나가 있는데,
; 그 값이 몇 번째 칸인지는 빌드할 때 quest_geom.py 가 정해 구워 둔다.
;-----------------------------------------------------------------------------
LatM:
    push de                     ; 부르는 쪽이 칸을 D,E 에 들고 있다. 표 주소를
    ld a, (segJ)                ; 짚는 데 DE 를 쓰므로 반드시 보존한다.
    ld b, a                     ; 색인 = j*(NSEG+1) + k
    add a, a
    add a, b
    add a, a                    ; j*6
    ld c, a
    ld a, (scanK)
    add a, c
    ld l, a
    ld h, 0
    ld de, LatTab
    add hl, de
    ld a, (hl)
    pop de
    ret

; A = A * (faceW). A 는 6 이하, 폭은 9 이하라 결과가 한 바이트에 들어간다.
MulW:
    ld b, a
    xor a
    or b
    ret z
    ld a, (faceW)
    ld c, a
    xor a
.mul:
    add a, c
    djnz .mul
    ret

; A = 상태, C = 면 번호. Vis[C] 에 넣는다. BC 보존.
SetVis:
    push hl
    ld h, Vis >> 8
    ld l, c
    ld (hl), a
    pop hl
    ret

; A = 값, C = 면 번호. VisPost[C] 에 넣는다. BC 보존.
SetVisPost:
    push hl
    ld h, VisPost >> 8
    ld l, c
    ld (hl), a
    pop hl
    ret

;-----------------------------------------------------------------------------
; 맵
;-----------------------------------------------------------------------------
; A = 거리 k(1 이상). 결과 D = 칸 x, E = 칸 y.
CellAhead:
    push bc                     ; 부르는 쪽이 깊이를 B 에 들고 있는 경우가 있다.
    ld b, a                     ; 여기서 B, C 를 임시로 쓰므로 반드시 보존한다.
    ld a, (facing)
    add a, a
    ld l, a
    ld h, 0
    ld de, DirTab
    add hl, de
    ld d, (hl)                  ; dx
    inc hl
    ld e, (hl)                  ; dy
    ld a, (posX)
    ld c, b
.lx:
    add a, d
    dec c
    jr nz, .lx
    ld d, a                     ; dx 는 더 쓰지 않으므로 덮어써도 된다
    ld a, (posY)
    ld c, b
.ly:
    add a, e
    dec c
    jr nz, .ly
    ld e, a
    pop bc
    ret

; A = 회전량 (1 = 오른쪽, 3 = 왼쪽), D,E = 기준 칸. 그쪽 이웃을 D,E 에 돌려준다.
;
; 기준 칸을 RAM 이 아니라 D,E 로 받는다. SideVis 가 같은 회전량으로 두 칸(이 칸과
; 한 칸 앞)의 이웃을 잇달아 물어보기 때문이다.
NeighbourCell:
    push bc                     ; 호출하는 쪽이 구간 번호를 B 에 들고 있다
    ld b, d                     ; 기준 칸을 B,C 로 옮긴다 - DE 로 표를 짚어야 한다
    ld c, e
    ld hl, facing
    add a, (hl)                 ; facing + 회전량
    and 3
    add a, a                    ; 표 한 칸이 dx, dy 두 바이트
    ld l, a
    ld h, 0
    ld de, DirTab
    add hl, de
    ld a, b
    add a, (hl)                 ; x + dx
    ld d, a
    inc hl
    ld a, c
    add a, (hl)                 ; y + dy
    ld e, a
    pop bc
    ret

; D = x, E = y. 벽이면 NZ, 통로면 Z. 맵 밖은 벽으로 본다.
IsWall:
    push bc                     ; 주소 계산에 BC 를 쓴다. 부르는 쪽은 구간 번호나
    ld a, d                     ; 키 비트를 B/C 에 들고 있으므로 반드시 보존한다.
    cp MAP_W
    jr nc, .solid               ; 부호 없는 비교라 음수(0xFF 등)도 여기서 걸린다
    ld a, e
    cp MAP_W
    jr nc, .solid
    ld a, e
    add a, a
    add a, a
    add a, a
    add a, a                    ; y*16
    add a, d                    ; + x. 맵이 16칸 폭이라 8비트로 끝난다
    ld l, a
    ld h, 0
    ld bc, MapDataRam           ; 실행 시간 생성 지도 (questlevel.asm)
    add hl, bc
    ld a, (hl)
    or a
    pop bc                      ; pop 은 플래그를 건드리지 않는다
    ret
.solid:
    ld a, 1
    or a
    pop bc
    ret

DirTab:
    db  0, -1                   ; 북
    db  1,  0                   ; 동
    db  0,  1                   ; 남
    db -1,  0                   ; 서

;-----------------------------------------------------------------------------
; 입력
;
; 키를 누른 순간에만 한 칸 움직인다. 누르고 있어도 계속 가지 않고 옛 Wizardry
; 처럼 한 번에 한 칸씩이다.
;-----------------------------------------------------------------------------
ReadInput:
    in a, (PPI_ROW)
    and 0xF0                    ; 상위 비트는 카세트/LED 제어용이므로 보존한다
    or 8
    out (PPI_ROW), a
    in a, (PPI_COL)
    cpl                         ; 매트릭스는 반전되어 읽힌다. 1 이면 눌림
    ld (keyState), a            ; 8 행 전체 (커서 bit4-7 + 스페이스 bit0)

    in a, (PPI_ROW)             ; 4 행 = M N B , . / 등
    and 0xF0
    or 4
    out (PPI_ROW), a
    in a, (PPI_COL)
    cpl
    and 0x04                    ; bit2 = M
    ld (mKey), a

    in a, (PPI_ROW)             ; 0 행 = 0 1 2 3 4 5 6 7
    and 0xF0
    or 0
    out (PPI_ROW), a
    in a, (PPI_COL)
    cpl
    and 0x7E                    ; bit1~6 = 숫자 1~6 (bit0 은 0, bit7 은 7)
    ld (numKey), a

    in a, (PPI_ROW)             ; 7 행 = F4 F5 ESC TAB STOP BS SELECT RET
    and 0xF0
    or 7
    out (PPI_ROW), a
    in a, (PPI_COL)
    cpl
    and 0x04                    ; bit2 = ESC
    ld (escKey), a
    ret

HandleInput:
    ld a, (keyState)
    ld b, a
    ld a, (prevKey)
    cpl
    and b                       ; 이번 프레임에 새로 눌린 비트만
    ld c, a
    ld a, b
    ld (prevKey), a

    ld a, (mKey)                ; M 은 4행이라 keyState 와 별도로 새로 눌림을 본다
    ld b, a
    ld a, (prevM)
    cpl
    and b
    ld d, a
    ld a, b
    ld (prevM), a
    ld a, d
    or a
    jr z, .nomap
    ld a, (BattleOn)            ; 전투 중에는 양피지가 전투 기록 차지다
    or a
    jr nz, .nomap
    push bc                     ; ToggleMap 은 DrawMap 을 거치며 BC 를 부순다. 새로
    call ToggleMap              ; 눌린 키 비트가 C 에 있으므로 반드시 지켜야 한다 -
    pop bc                      ; 안 그러면 M 을 누를 때 제멋대로 걷거나 돈다.
.nomap:

    ld a, (numKey)              ; 1~6 은 0 행이라 따로 새로 눌림을 본다
    ld b, a
    ld a, (prevNum)
    cpl
    and b
    ld e, a
    ld a, b
    ld (prevNum), a

    ld a, (escKey)              ; ESC 는 7 행
    ld b, a
    ld a, (prevEsc)
    cpl
    and b
    ld d, a
    ld a, b
    ld (prevEsc), a

    ld a, (BattleOn)            ; 전투 중에는 양피지가 전투 기록 차지다
    or a
    jr nz, .nostat

    ld a, d                     ; --- ESC: 한 단계 물러난다 ---
    or a
    jr z, .noesc
    ld a, (StatOn)
    or a
    jr z, .noesc
    push bc
    call StatEscape
    pop bc
    ret
.noesc:

    ld a, e                     ; --- 숫자 1~6 ---
    or a
    jr z, .nonum
    ld d, 0
.scan:
    inc d
    rrca
    jr nc, .scan
    ld a, d                     ; 고리가 bit k 에서 d = k+1 로 빠져나온다
    sub 2                       ; bit1('1') -> 번호 0
    push bc
    call StatNumber             ; 전달 중이면 받는 사람, 아니면 볼 사람
    pop bc
    ret
.nonum:

    ld a, (StatOn)
    or a
    jr z, .nostat

    ld a, (StatMode)            ; --- 화살표와 스페이스는 단계마다 뜻이 다르다 ---
    or a
    jr nz, .inlist

    ld a, 0                     ; MODE_PAGE - 좌우 사람, 위아래 쪽
    bit KEY_RIGHT, c
    jr nz, .turnpage
    inc a
    bit KEY_LEFT, c
    jr nz, .turnpage
    ld a, 0
    bit KEY_DOWN, c
    jr nz, .flippage
    inc a
    bit KEY_UP, c
    jr nz, .flippage
    bit KEY_SPACE, c            ; 가방 쪽이면 커서를 세운다
    jr z, .nostat
    push bc
    call StatEnterList
    pop bc
    ret
.flippage:
    push bc
    call StatPageDelta
    pop bc
    ret                         ; **걷기로 흘려보내지 않는다**
.turnpage:
    push bc
    call StatNext
    pop bc
    ret

.inlist:                        ; MODE_CURSOR / ACTION - 화살표는 줄 고르기
    ld a, 0
    bit KEY_DOWN, c
    jr nz, .movecur
    bit KEY_RIGHT, c
    jr nz, .movecur
    inc a
    bit KEY_UP, c
    jr nz, .movecur
    bit KEY_LEFT, c
    jr nz, .movecur
    bit KEY_SPACE, c
    jr z, .nostat
    push bc
    call StatConfirm
    pop bc
    ret
.movecur:
    push bc
    call StatMoveCursor
    pop bc
    ret

.nostat:

    ld a, (BattleOn)            ; 전투 중에는 스페이스만 받는다
    or a
    jr z, .walk
    bit KEY_SPACE, c
    ret z
    jp BattleRound
.walk:
    bit KEY_SPACE, c            ; 전투가 없을 때 스페이스는 바로 걸기
    jr z, .nospace
    jp StartBattle
.nospace:

    bit KEY_LEFT, c
    jr z, .noleft
    ld a, (facing)
    dec a
    and 3
    ld (facing), a
    jr .moved
.noleft:
    bit KEY_RIGHT, c
    jr z, .noright
    ld a, (facing)
    inc a
    and 3
    ld (facing), a
    jr .moved
.noright:
    bit KEY_UP, c
    jr z, .nofwd
    ld a, 1
    call CellAhead              ; 바로 앞 칸
    call IsWall
    ret nz                      ; 벽이면 제자리
    ld a, d
    ld (posX), a
    ld a, e
    ld (posY), a
    call RollEncounter
    jr .moved
.nofwd:
    bit KEY_DOWN, c
    ret z
    ; 뒤로 한 칸 - 돌아서지 않고 물러난다.
    ; 원래 방향은 스택에 둔다. CellAhead 가 B 를 파괴하므로 B 에 담으면 안 된다.
    ld a, (facing)
    push af
    add a, 2
    and 3
    ld (facing), a              ; 잠깐 뒤를 보게 해서 앞칸 계산을 재사용한다
    ld a, 1
    call CellAhead
    pop af
    ld (facing), a              ; 방향은 곧바로 되돌린다
    call IsWall
    ret nz
    ld a, d
    ld (posX), a
    ld a, e
    ld (posY), a
.moved:
    ld a, 1
    ld (needDraw), a
    jp AfterMove                ; 지도가 켜져 있으면 미니맵도 다시 그린다

;-----------------------------------------------------------------------------
; VDP 기본 루틴
;-----------------------------------------------------------------------------
; 상태 레지스터 S#0 의 vblank 플래그를 폴링한다. 읽으면 플래그가 지워지므로
; 인터럽트를 끈 상태로 돌려야 한다.
WaitVBlank:
    in a, (VDP_ADDR)
    and 0x80
    jr z, WaitVBlank
    ret

; A = 스캔라인 y -> HL = 그 줄의 VRAM 첫 주소.
;
; SCREEN 5 는 한 줄이 128 바이트, SCREEN 8 은 256 바이트다. 8bpp 쪽이 오히려
; 짧다 - 시프트가 통째로 없어지고 "상위 = y, 하위 = 0" 이면 끝난다.
RowAddr:
    ld h, a
    ld l, 0
    IFNDEF SCREEN8
    srl h
    rr l
    ENDIF
    ret

; A = 픽셀 x -> A = 바이트 x
XToByte:
    IFNDEF SCREEN8
    srl a
    ENDIF
    ret

; 정면 벽 자리(줄 FRONT_VY 아래) 전용. SCREEN 8 에서는 그 자리가 VRAM
; 0x10000 부터라 16 비트 주소로는 못 짚는다. R#14 의 A16 비트를 얹어 준다.
SetVramWriteFront:
    ld a, h
    rlca
    rlca
    and 0x03
    IFDEF SCREEN8
    or 0x04                     ; A16 = 1
    ENDIF
    ld c, 14
    call WriteVdpReg
    ld a, l
    out (VDP_ADDR), a
    ld a, h
    and 0x3F
    or 0x40
    out (VDP_ADDR), a
    ret

; HL = VRAM 주소. 쓰기 모드로 설정한다. HL 은 보존, A 와 C 는 파괴.
SetVramWrite:
    ld a, h
    rlca
    rlca
    and 0x03
    ld c, 14
    call WriteVdpReg
    ld a, l
    out (VDP_ADDR), a
    ld a, h
    and 0x3F
    or 0x40
    out (VDP_ADDR), a
    ret

; A = 쓸 값, C = 레지스터 번호.
WriteVdpReg:
    out (VDP_ADDR), a
    ld a, c
    or 0x80
    out (VDP_ADDR), a
    ret

;-----------------------------------------------------------------------------
    IFDEF SCREEN8
    include "src/quest8ruledata.asm"
    ELSE
    include "src/questruledata.asm"
    ENDIF
    include "src/questmsgdata.asm"
    include "src/questgeardata.asm"
    include "src/questtext.asm"
    include "src/questmath.asm"
    include "src/questparty.asm"
    include "src/questfight.asm"
    include "src/questmon.asm"
    include "src/questlevel.asm"
    include "src/questmap.asm"
    include "src/questgear.asm"
    include "src/queststat.asm"
    IFDEF SCREEN8
    include "src/quest8data.asm"
    ELSE
    include "src/questdata.asm"
    ENDIF

; 본체는 뱅크 0~2 (0x4000-0x9FFF) 다. 그림 뱅크는 questspr*.asm 이 따로 만들고
; build_quest.ps1 이 이어 붙여 128KB 로 만든다.
    ds 0xA000 - $, 0xFF
    IFDEF SCREEN8
    SAVEBIN "build/quest8main.bin", 0x4000, 0x6000
    ELSE
    SAVEBIN "build/questmain.bin", 0x4000, 0x6000
    ENDIF
