;-----------------------------------------------------------------------------
; MSX2 던전 탐험 - Bard`s Tale / Wizardry 형태
;
; 128KB 카트리지 ROM, ASCII8 매퍼.
;
;   뱅크 0~2  0x4000-0x9FFF 에 고정. 코드와 실행 중 늘 필요한 자료.
;   뱅크 3~4  0xA000-0xBFFF 에 번갈아 건다. 몬스터 그림.
;
; 몬스터 그림 여섯 장이 8,338 바이트라 32KB 로는 모자랐다.
;
; 화면  : SCREEN 5 (GRAPHIC 4), 256x212, 팔레트 16색을 배경과 던전이 공유
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

    DEVICE NOSLOT64K

    include "src/questconst.asm"
    include "src/questrules.asm"

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
BLACK_BYTE  equ COL_BLACK * 17  ; 같은 색 두 픽셀 (0x11 을 곱하는 것과 같다)

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
frontH      ds 1
frontX      ds 1
frontW      ds 1
cellX       ds 1                ; 지금 보고 있는 구간의 칸
cellY       ds 1
cellX2      ds 1                ; 그 한 칸 앞 (옆면은 두 칸을 다 봐야 정해진다)
cellY2      ds 1
VarsEnd:

; 면 번호로 바로 찾을 수 있게 페이지 경계에 둔다.
; ld d,Vis>>8 / ld e,면번호 / ld a,(de) 세 줄이면 상태가 나온다.
    ORG 0xC100
Vis         ds 32

; 글자 찍기용
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
TurnHero    ds 1                ; 이번 라운드에서 다음에 칠 영웅
TurnMon     ds 1                ; 다음에 칠 몬스터
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

; 파티와 몬스터.
;
; ExpandTbl 은 페이지 머리에 둔다. PutChar 가 니블 값으로 표를 볼 때 하위
; 바이트만 바꾸면 되기 때문이다(글자 한 줄마다 네 번 본다).
; Party 는 0xC220 이라 32 로 나누어떨어진다. 사람 번호 * 32 를 하위 바이트에
; 더할 때 자리 올림이 나지 않는다.
    ORG 0xC200
ExpandTbl   ds 32
Party       ds PARTY_N * PARTY_STRIDE
Monsters    ds MON_N * MON_STRIDE

; 실행 시간 맵 생성의 결과 지도. 1=벽, 0=통로. IsWall 이 여기를 본다.
; RamEnd 뒤에 두면 Init 의 0 지우기에서 빠지므로 RamEnd 앞에 둔다.
MapDataRam  ds MAP_W * MAP_W

; 미니맵 한 행分 (questmap.asm). 맵 한 칸 = 3바이트.
MiniMapRow  ds MAP_W * 3
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
    call UploadPalette
    call UnpackBg               ; 압축한 배경을 VRAM 에 푼다

    ld hl, RamStart             ; 작업 영역 **전체**를 0 으로
    ld de, RamStart + 1
    ld bc, RamEnd - RamStart - 1
    ld (hl), 0
    ldir

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

    call MakeParty
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
    ld a, (MapOn)
    or a
    ret z
    jp DrawMap

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
    db 0x06                     ; R#0  GRAPHIC 4 모드
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
; 자료는 뱅크 5 에 따로 있다(questbgbank.asm). 0xA000 창을 잠깐 그쪽으로 돌렸다가
; 끝나면 몬스터 그림 뱅크로 되돌린다 - 안 되돌리면 첫 전투에서 그림 자리에서
; 배경 바이트를 읽는다. 끝 판정도 주소가 아니라 길이로 한다.
;-----------------------------------------------------------------------------
BG_BANK     equ 5
BG_END      equ 0xA000 + BG_RLE_LEN

UnpackBg:
    ld a, BG_BANK
    ld (ASC8_P3), a             ; 0xA000-0xBFFF = 배경 뱅크
    ld hl, 0
    call SetVramWrite
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
    ld a, h
    cp BG_END >> 8
    jr nz, .loop
    ld a, l
    cp BG_END & 0xFF
    jr nz, .loop
    ld a, 3
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
    ld hl, RunData
    ld a, VIEW_Y
    ld (curY), a
.line:
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
    cp VIS_WALL3
    jr z, .wall3                ; 그다음이 벽면 - 옆칸은 대개 벽이다
    cp VIS_OPEN3
    jr z, .open3
    cp VIS_GAP3
    jr z, .gap3
    cp VIS_BLACK
    jr z, .black
    cp VIS_SKIP
    jr z, .skip1
    ; VIS_SKIP3 - 삼중 블록을 셋 다 건너뛴다. 두 개를 여기서 밀고 나머지
    ; 하나는 .skip1 -> .advance 가 민다.
    ld a, b
    add a, l
    ld l, a
    jr nc, $ + 3                ; inc h 한 바이트를 건너뛴다
    inc h
    ld a, b
    add a, l
    ld l, a
    jr nc, $ + 3
    inc h
    jp .skip1

.draw1:                         ; 단일 블록 (천장/바닥)
    ld a, (addrOk)              ; CheckAddr 인라인 - 핫 패스라 call 값이 아깝다
    or a
    call z, ResumeAddr
.t1:
    outi                        ; 16
    nop                         ;  4
    jp nz, .t1                  ; 10  -> 합 30 T-state
    jp .run                     ; outi 가 이미 HL 을 끝까지 밀었다

.wall3:                         ; 0 번(비스듬한 벽면)을 그리고 1, 2 번은 건너뛴다
    ld a, (addrOk)
    or a
    call z, ResumeAddr
    push bc
.t2:
    outi
    nop
    jp nz, .t2
    pop bc
    ld a, b                     ; 1 번 건너뛰기
    add a, l
    ld l, a
    jr nc, $ + 3
    inc h
    jr .advance                 ; 2 번은 .advance 가 민다

.open3:                         ; 1 번(대각선 앞칸의 정면)을 그린다
    ld a, b                     ; 0 번 건너뛰기
    add a, l
    ld l, a
    jr nc, $ + 3
    inc h
    ld a, (addrOk)
    or a
    call z, ResumeAddr
    push bc
.t3:
    outi
    nop
    jp nz, .t3
    pop bc
    jr .advance                 ; 2 번은 .advance 가 민다

.gap3:                          ; 2 번(뚫린 채 이어지는 바닥/천장)을 그린다
    ld a, b                     ; 0 번 건너뛰기
    add a, l
    ld l, a
    jr nc, $ + 3
    inc h
    ld a, b                     ; 1 번 건너뛰기
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
DrawFront:
    ld a, (blockDepth)
    cp MAXD + 1
    ret nc                      ; 끝까지 안 막혔으면 할 일이 없다

    call FrontPtr               ; HL = 그 깊이의 정면 벽 데이터
    ld a, (hl)                  ; startY
    inc hl
    ld (curY), a
    ld a, (hl)                  ; 높이
    inc hl
    ld (frontH), a
    ld a, (hl)                  ; xByte
    inc hl
    ld (frontX), a
    ld a, (hl)                  ; 바이트폭
    inc hl
    ld (frontW), a
.line:
    push hl
    ld a, (curY)                ; VRAM 주소 = y*128 + xByte
    ld h, a
    ld l, 0
    srl h
    rr l
    ld a, (frontX)
    ld e, a
    ld d, 0
    add hl, de
    call SetVramWrite
    pop hl

    ld a, (frontW)
    ld b, a
    ld c, VDP_DATA
.wr:
    outi
    nop
    jp nz, .wr

    ld a, (curY)
    inc a
    ld (curY), a
    ld a, (frontH)
    dec a
    ld (frontH), a
    jp nz, .line
    ret

; A = blockDepth (1..MAXD) -> HL = 그 깊이의 정면 벽 데이터
FrontPtr:
    dec a
    add a, a
    ld l, a
    ld h, 0
    ld de, FrontPtrs
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
    ld h, a
    ld l, 0
    srl h
    rr l
    ld de, VIEW_X / 2
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
    ld h, a
    ld l, 0
    srl h
    rr l
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
;   VIS_WALL3 / VIS_OPEN3 / VIS_GAP3 / VIS_SKIP3 : 좌우 벽 (SideVis 참고)
;-----------------------------------------------------------------------------
BuildVisibility:
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
    ld a, VIEW_X / 2
    ld (resumeX), a
    ld a, (blockDepth)
    cp MAXD + 1
    jr nc, .centreopen

    call FrontPtr
    inc hl
    inc hl
    ld a, (hl)                  ; xByte
    inc hl
    add a, (hl)                 ; + 바이트폭 = 사각형의 오른쪽 끝
    ld (resumeX), a

    ld a, VIS_SKIP              ; 한가운데는 정면 벽이 덮는다
    jr .setcentre
.centreopen:
    ld a, VIS_BLACK             ; 끝까지 안 막혔으면 어둠
.setcentre:
    ld c, CENTRE_ID
    call SetVis

    ld b, 0                     ; 구간마다 네 면의 상태를 정한다
.each:
    ld a, b
    ld hl, blockDepth
    cp (hl)
    jr c, .openseg              ; 이 구간은 아직 막히기 전

    ld a, b                     ; 막힌 칸부터 안쪽은 전부 정면 벽이 덮는다
    call SegBase
    ld c, a
    ld a, VIS_SKIP
    call SetVis                 ; 천장
    inc c
    call SetVis                 ; 바닥
    inc c
    ld a, VIS_SKIP3             ; 좌우는 블록이 셋이라 셋 다 건너뛴다
    call SetVis
    inc c
    call SetVis
    jr .eachnext

.openseg:
    ld a, b
    call SegBase
    ld c, a
    ld a, VIS_TEX
    call SetVis                 ; 천장
    inc c
    ld a, VIS_TEX
    call SetVis                 ; 바닥

    ; 옆면은 이 칸과 그 한 칸 앞을 함께 봐야 정해지므로 둘 다 미리 담아 둔다.
    ld a, b
    call CellAhead              ; 구간 j 의 칸
    ld a, d
    ld (cellX), a
    ld a, e
    ld (cellY), a
    ld a, b
    inc a
    call CellAhead              ; 그 한 칸 앞 - 대각선을 보기 위한 것
    ld a, d
    ld (cellX2), a
    ld a, e
    ld (cellY2), a

    ld a, 3                     ; 왼쪽 (facing - 1)
    call SideVis
    push af
    ld a, b
    call SegBase
    add a, 2
    ld c, a
    pop af
    call SetVis

    ld a, 1                     ; 오른쪽 (facing + 1)
    call SideVis
    push af
    ld a, b
    call SegBase
    add a, 3
    ld c, a
    pop af
    call SetVis

.eachnext:
    inc b
    ld a, b
    cp NSEG
    jp c, .each
    ret

; A = 회전량 (1 = 오른쪽, 3 = 왼쪽) -> A = 그쪽 옆면의 상태. BC 보존.
;
; 옆칸 하나만 봐서는 그릴 그림이 정해지지 않는다. 광선이 그 자리를 지나 z = j+1
; 평면에서 만나는 것은 **대각선 앞칸**(옆으로 1, 앞으로 j+1)이기 때문이다.
;
;   옆칸이 벽                       -> VIS_WALL3  비스듬한 벽면
;   옆칸 뚫림, 대각선 앞칸이 벽     -> VIS_OPEN3  그 칸의 정면
;   둘 다 뚫림                      -> VIS_GAP3   바닥/천장만 이어진다
;
; 한때 앞의 두 경우만 있었다. 그러면 광장 한가운데에 섰을 때 화면 좌우 끝에
; 있지도 않은 벽이 그려진다 - 옆칸 하나만 보고 두 칸의 결과를 그린 탓이다.
SideVis:
    push bc
    ld c, a                     ; 회전량을 남겨 둔다
    ld a, (cellX)
    ld d, a
    ld a, (cellY)
    ld e, a
    ld a, c
    call NeighbourCell
    call IsWall
    ld a, VIS_WALL3
    jr nz, .done                ; 옆이 벽이면 여기서 끝이다
    ld a, (cellX2)              ; 뚫렸으면 대각선 앞칸을 마저 본다
    ld d, a
    ld a, (cellY2)
    ld e, a
    ld a, c
    call NeighbourCell
    call IsWall
    ld a, VIS_OPEN3
    jr nz, .done
    ld a, VIS_GAP3
.done:
    pop bc
    ret

; A = 구간 번호 j -> A = 그 구간의 면 번호 시작값 j*4. BC 보존.
SegBase:
    add a, a
    add a, a
    ret

; A = 상태, C = 면 번호. Vis[C] 에 넣는다. BC 보존.
SetVis:
    push hl
    ld h, Vis >> 8
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
    push bc                     ; ToggleMap 은 DrawMap 을 거치며 BC 를 부순다. 새로
    call ToggleMap              ; 눌린 키 비트가 C 에 있으므로 반드시 지켜야 한다 -
    pop bc                      ; 안 그러면 M 을 누를 때 제멋대로 걷거나 돈다.
.nomap:

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
    include "src/questruledata.asm"
    include "src/questtext.asm"
    include "src/questmath.asm"
    include "src/questparty.asm"
    include "src/questfight.asm"
    include "src/questmon.asm"
    include "src/questlevel.asm"
    include "src/questmap.asm"
    include "src/questdata.asm"

; 본체는 뱅크 0~2 (0x4000-0x9FFF) 다. 그림 뱅크는 questspr*.asm 이 따로 만들고
; build_quest.ps1 이 이어 붙여 128KB 로 만든다.
    ds 0xA000 - $, 0xFF
    SAVEBIN "build/questmain.bin", 0x4000, 0x6000
