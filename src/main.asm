;-----------------------------------------------------------------------------
; MSX2 종스크롤 슈팅 데모 - Zanac 스타일
;
; 0x4000에 매핑되는 16KB 카트리지 ROM. 매퍼도 슬롯 전환도 없음.
;
; 화면    : SCREEN 5 (GRAPHIC 4), 256x212, 커스텀 팔레트 16색
; 스크롤  : 하드웨어. VDP R#23으로 VRAM 페이지 256라인 전체를 스크롤
; 스프라이트: 하드웨어 모드 2 (스캔라인당 색 하나)
; 사운드  : PSG - 격추 시 노이즈, 피격 시 떨어지는 톤
; 그래픽  : gfx/convert.py가 Zanac 참고 PNG에서 생성
;
; 이 데모의 주제는 처리량이다. 배경 스크롤은 VDP가 공짜로 해주고,
; CPU는 곧 나타날 픽셀 라인 하나(128바이트)만 찍어낸다.
; 움직이는 것은 전부 하드웨어 스프라이트라, 프레임당 비용은 게임 로직에
; 작은 VRAM 전송 하나를 더한 정도다. CPU 사용량은 HUD에 숫자로 표시된다.
;
; 주의: 이것은 ROM이다. 자기 수정 코드를 쓸 수 없고, 변하는 값은 전부
; 페이지 3 RAM에 둔다.
;-----------------------------------------------------------------------------

    DEVICE NOSLOT64K

    include "src/gfxconst.asm"

;--- 입출력 포트 ---------------------------------------------------------------
VDP_DATA    equ 0x98
VDP_ADDR    equ 0x99
VDP_PAL     equ 0x9A
PPI_ROW     equ 0xAA            ; 키보드 행 선택 (하위 4비트)
PPI_COL     equ 0xA9            ; 키보드 열 읽기 (0이면 눌림)
PSG_ADDR    equ 0xA0
PSG_DATA    equ 0xA1

;--- VRAM 배치 -----------------------------------------------------------------
; 페이지 0(0x0000-0x7FFF)은 256라인 전부가 비트맵이고, 순환 스크롤 버퍼로
; 쓴다. 그래서 스프라이트 테이블을 페이지 0에 둘 수 없다 - 어떤 스크롤
; 위치에서는 화면에 그림으로 표시되어 버린다. 그래서 페이지 1에 둔다.
; 이 데모가 표준 MSX2의 VRAM 128KB를 필요로 하는 이유가 이것이다.
BITMAP      equ 0x0000
SPRCOL      equ 0x9400          ; 32슬롯 x 16바이트 (모드 2 색 테이블)
SPRATTR     equ 0x9600          ; 32슬롯 x 4바이트 (= SPRCOL + 512로 고정)
SPRPAT      equ 0x9800          ; 16x16 패턴 하나당 32바이트

VRAM_LINES   equ 256
; 스크롤 값은 매 프레임 감소한다. 표시 창이 VRAM 위쪽으로 올라가므로
; 지형은 아래로 흐르고, 플레이어가 전진하는 그림이 된다.
; 새 내용은 창 위쪽 (scroll - DRAW_BEHIND)에 쓴다. 화면에 들어오기 12라인
; 전이고 아래로 빠져나간 지 31라인 뒤라, 항상 확보되는 화면 밖 44라인
; 안에 들어간다.
DRAW_BEHIND  equ 13
START_SCROLL equ DRAW_BEHIND + 1

;--- 오브젝트 개수 상한 --------------------------------------------------------
; 하드웨어 스프라이트 32개를 전부 쓰고 있고 HUD가 13개를 가져가므로,
; 남는 것이 이만큼이다. MAX_EN은 보스의 셀 예산이기도 하다.
; (아래 MAX_EN 주석 참고)
; MAX_EN은 난이도 램프의 상한(BASE_ENEMIES + MAX_LEVEL = 9)과, 이 슬롯을
; 빌려 쓰는 거대보스 양쪽이 정한다. 따라서 보스 격자가 이 값을 넘으면
; 안 된다.
MAX_PB      equ 4               ; 자기 총알
MAX_EN      equ 9               ; 적기 - 보스의 셀 예산이기도 하다
MAX_EB      equ 4               ; 적 총알

;--- 스프라이트 슬롯 배치 ------------------------------------------------------
; 모드 2는 한 스캔라인에 8개까지만 그리고 나머지는 슬롯 순서대로 조용히
; 버린다. 그래서 HUD를 맨 앞 슬롯에 배치했다. 우선순위가 가장 높아서
; 절대 사라지지 않고, 그 줄이 붐비면 게임 오브젝트가 대신 밀린다.
; 
;
; HUD를 두 줄로 나눈 것은 13개를 한 줄에 몰면 8개 제한에 걸려 다섯 개가
; 조용히 잘리기 때문이다:
;     1번 줄 (HUD_Y)    스코어 6 + 게이지 1        = 7개
;     2번 줄 (METER_Y)  "F" + fps 2 + "C" + cpu 2 = 6개
;
; 스코어와 게이지를 윗줄에 같이 둬서 Y가 맞는다. 아래의 계측 줄은
; "0"키를 누를 때까지 보이지 않는다.
;
; 두 띠에는 HUD 외에 아무것도 들어오지 못한다. 적기와 보스는 PLAY_TOP
; 아래에서만 나오고, 자기 총알은 거기 닿으면 사라진다. 계측 줄을 꺼도
; 이 경계는 그대로라, 토글할 때 플레이 영역이 움찔거리지 않는다.
; 
SLOT_SCORE  equ 0               ; 6자리
SLOT_ENERGY equ 6               ; 게이지 1개, 스코어와 같은 줄
SLOT_FLABEL equ 7
SLOT_FPS    equ 8               ; 2자리
SLOT_CLABEL equ 10
SLOT_CPU    equ 11              ; 2자리
SLOT_PLAYER equ 13              ; 평면 2장, 반드시 인접해야 한다
SLOT_PB     equ 15
SLOT_EN     equ SLOT_PB + MAX_PB    ; 적기, 또는 보스의 셀
SLOT_EB     equ SLOT_EN + MAX_EN
NUM_SLOTS   equ SLOT_EB + MAX_EB    ; = 32. 슬롯을 전부 쓴다

SPR_END_Y   equ 216             ; 스프라이트 목록의 끝을 의미
SPR_HIDE_Y  equ 213             ; 화면 아래 밖. 단 216은 아니어야 한다

;--- HUD 배치 좌표 -------------------------------------------------------------
; 글자는 16x16 칸의 좌상단에 5x7로 그리므로 간격은 6px이고,
; 칸끼리 겹쳐도 문제없다.
; 배경이 세로로 스크롤하므로 어떤 X도 결국 모든 맵 행을 만난다. 항상
; 비어 있는 열은 없다는 뜻이다. 그래서 맵 전체에 대해 19px 구간이 어두운
; 비율을 재서 골랐다. x=6은 77%, x=48은 76%인데, 얼핏 자연스러워 보이는
; x=30은 48%밖에 안 된다 - 요새 기둥에 정확히 걸치기 때문이다.
; 자세한 것은 README의 분석 참고.
HUD_Y       equ 3               ; 1번 줄: 스코어와 게이지
METER_Y     equ 19              ; 2번 줄: F와 C 계측 표시
FPS_X       equ 6
CPU_X       equ 48
GLYPH_STEP  equ 6
LABEL_GAP   equ 7               ; 라벨에서 첫 숫자까지의 간격
ENERGY_X    equ 232
SCORE_DIGITS equ 6
; 가운데 정렬: 6자리 x 6px = 폭 36
SCORE_X     equ (256 - SCORE_DIGITS * GLYPH_STEP) / 2
ENERGY_MAX  equ 32              ; 16열짜리 게이지 하나에 표시. 한 열이 2포인트
PLAY_TOP    equ 36              ; 나머지는 전부 HUD 두 줄 아래에 머문다

;--- 게임 규칙 -----------------------------------------------------------------
PLAYER_SPEED equ 2
PLAYER_X_MAX equ 240
PLAYER_Y_MIN equ PLAY_TOP
PLAYER_Y_MAX equ 190
FIRE_PERIOD  equ 8              ; 자동 발사. 입력 없이도 데모가 돌아가도록
ENEMY_KILL_Y equ 200            ; SPR_END_Y에 닿기 훨씬 전에 소멸시킨다
PB_SPEED     equ 6
EB_SPEED     equ 2
HIT_FLASH    equ 48             ; 피격 후 무적 프레임 수
DMG_BULLET   equ 3
DMG_CRASH    equ 6
GAMEOVER_TIME equ 200

;--- 난이도 --------------------------------------------------------------------
; level은 512프레임(약 8.5초)마다 오르고 7에서 멈춘다. 동시 적기 수를
; 늘리고, 생성 간격과 발사 간격을 함께 줄인다.
MAX_LEVEL    equ 7
BASE_ENEMIES equ 2
BASE_SPAWN   equ 48
BASE_FIRE    equ 90

;--- 보스 ----------------------------------------------------------------------
MIDBOSS_FRAME  equ 7200         ; 60Hz 기준 2분
GIANTBOSS_FRAME equ 14400       ; 4분
; MBOSS_COLS/ROWS와 GBOSS_COLS/ROWS는 gfxconst.asm에서 온다. 원본을 자르는
; gfx/convert.py가 격자 모양을 소유하기 때문이다. 한 번 이 값을 여기에도
; 따로 뒀다가 실제로 어긋난 적이 있다. 3x3으로만 잘린 보스를 게임이 3x4로
; 그리려다 보스 패턴을 넘어 숫자 글리프까지 침범하고, 스프라이트 슬롯
; 범위도 넘어 썼다. 아래 단언이 그것을 빌드 실패로 만든다.
    ASSERT MBOSS_COLS * MBOSS_ROWS <= MAX_EN, mid-boss needs more slots than MAX_EN
    ASSERT GBOSS_COLS * GBOSS_ROWS <= MAX_EN, giant boss needs more slots than MAX_EN
MBOSS_HP     equ 40
GBOSS_HP     equ 90
BOSS_Y       equ PLAY_TOP + 4

;--- 사운드 --------------------------------------------------------------------
SFX_HIT_LEN  equ 30
SFX_EXP_LEN  equ 15

;--- 작업용 RAM ----------------------------------------------------------------
; 페이지 3은 모든 MSX에서 RAM이고, 카트리지 INIT이 돌 때 이미 매핑되어 있다.
    ORG 0xC000
Vars:
playerX     ds 1
playerY     ds 1
playerFrame ds 1
hitFlash    ds 1
scroll      ds 1
mapRow      ds 1
tileLine    ds 1
fireTimer   ds 1
spawnTimer  ds 1
keyState    ds 1
yBias       ds 1
hideY       ds 1
level       ds 1
energy      ds 1
gameState   ds 1                ; 0이면 진행 중, 1이면 게임 오버
overTimer   ds 1
bossActive  ds 1                ; 0이면 없음, 1이면 중간보스, 2면 거대보스
bossX       ds 1
bossY       ds 1
bossVX      ds 1
bossHP      ds 1
bossFire    ds 1
bossCols    ds 1                ; 한 행당 셀 수. 보스가 나올 때 정해진다
bossCells   ds 1                ; 전체 셀 수
bossColIdx  ds 1                ; 셀을 배치하는 동안의 열 커서
midDone     ds 1
giantDone   ds 1
sfxTone     ds 1
sfxNoise    ds 1
energyColour ds 1               ; 캐시. 값이 바뀔 때만 게이지 색을 다시 쓴다
demoMode    ds 1                ; 어트랙트 모드 자동 조종. 키를 한 번 누르면 영구히 꺼진다
keyRow0     ds 1                ; 숫자 키. 보스 호출과 계측 토글에 쓴다
prevRow0    ds 1                ; 직전 프레임 값. 에지 트리거로 만들기 위한 것
hudMeters   ds 1                ; fps/cpu 줄 표시 여부. "0"을 누르기 전까지 꺼져 있다
idleCount   ds 2                ; vblank 대기에서 측정한 여유 시간 단위
lateCount   ds 1                ; 마감을 놓친 프레임 수. fps 집계 구간마다 초기화
fpsTimer    ds 1
cpuTimer    ds 1
fpsTens     ds 1
fpsUnits    ds 1
cpuTens     ds 1
cpuUnits    ds 1
cpuPct      ds 1
fpsVal      ds 1
cpuColour   ds 1                ; energyColour와 같은 방식의 캐시
fpsColour   ds 1
frameCount  ds 2
rngState    ds 2
score       ds SCORE_DIGITS     ; BCD. 바이트당 한 자리, 높은 자리가 앞

ResetStart:                     ; 아래쪽은 재시작할 때 전부 0으로 지운다
pbActive    ds MAX_PB
pbX         ds MAX_PB
pbY         ds MAX_PB

enActive    ds MAX_EN
enX         ds MAX_EN
enY         ds MAX_EN
enVX        ds MAX_EN
enType      ds MAX_EN
enFire      ds MAX_EN

ebActive    ds MAX_EB
ebX         ds MAX_EB
ebY         ds MAX_EB
ebVX        ds MAX_EB
ResetEnd:

; 스프라이트 속성을 여기서 조립한 뒤 한 덩어리로 VRAM에 보낸다. VDP가
; 절반만 갱신된 테이블을 읽지 않게 하기 위해서다.
sprShadow   ds 32 * 4
VarsEnd:

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

    call InitVdp                ; 이 시점에는 화면 출력이 꺼져 있다
    call UploadPalette
    call ClearBitmap
    call UploadSpritePatterns
    call InitGameState
    call PrefillBackground
    call InitSpriteColours
    call InitPsg

    ld a, START_SCROLL
    ld (scroll), a
    ld c, 23
    call WriteVdpReg

    ld a, 0x42                  ; 화면 켜기, 16x16 스프라이트, VDP 인터럽트 끔
    ld c, 1
    call WriteVdpReg

;-----------------------------------------------------------------------------
; 메인 루프.
;
; 프레임의 여유 시간은 vblank 대기 루프 안에서 재고, HUD에 퍼센트로
; 표시한다. 예전에는 작업하는 동안 border를 빨갛게 칠해서 보여줬는데,
; 지금은 숫자 표시가 그 역할을 대신한다.
;-----------------------------------------------------------------------------
MainLoop:
    call WaitVBlankMeasured

    ld a, (gameState)
    or a
    jr nz, .over

    call ScrollBackground       ; R#23 갱신과 새 픽셀 라인 한 줄
    call ReadInput
    call CheckHotKeys
    call DemoControl
    call UpdatePlayer
    call UpdatePlayerBullets
    call UpdateEnemies
    call UpdateBoss
    call UpdateEnemyBullets
    call Collisions
    call AdvanceTime
    jr .draw
.over:
    call UpdateGameOver
.draw:
    call UpdateSound
    call UpdateEnergyColour
    call UpdateMeters
    call UpdateHudColours
    call BuildSprites
    call UploadSprites
    jp MainLoop

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
    out (VDP_ADDR), a
    ld a, c
    or 0x80
    out (VDP_ADDR), a
    inc c
    djnz .loop
    ret

VdpRegs:
    db 0x06                     ; R#0  GRAPHIC 4 모드
    db 0x02                     ; R#1  일단 화면 끔, 16x16 스프라이트
    db 0x1F                     ; R#2  비트맵 페이지 0을 0x00000에
    db 0xFF                     ; R#3  (G4에서는 미사용)
    db 0x03                     ; R#4  (G4에서는 미사용)
    ; R#5/R#11은 '색' 테이블의 시작 주소를 정한다. 속성 테이블은 항상 그보다
    ; 512바이트 위다. 0x2F는 페이지 내 0x1400, R#11=1은 페이지 1을 뜻한다.
    db 0x2F                     ; R#5  스프라이트 색 테이블 0x9400
    db 0x13                     ; R#6  스프라이트 패턴 제너레이터 0x9800
    db 0x00                     ; R#7  배경(border) 색
    db 0x08                     ; R#8  VR=1 (VRAM 128K), 스프라이트 켬
    db 0x80                     ; R#9  212라인
    db 0x00                     ; R#10
    db 0x01                     ; R#11 스프라이트 속성 테이블 상위 비트
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
    db 0x00                     ; R#23 수직 스크롤 오프셋
VdpRegsEnd:

; V9938 팔레트는 프로그래밍 가능하다. 색 하나당 2바이트로 (R<<4)|B, 그다음 G,
; 채널당 3비트다. 항목은 gfx/convert.py가 원본 그림에서 골라낸다.
UploadPalette:
    xor a
    ld c, 16
    call WriteVdpReg            ; R#16 = 팔레트 포인터를 0으로
    ld hl, PaletteData
    ld b, 32
.loop:
    ld a, (hl)
    inc hl
    out (VDP_PAL), a
    nop
    djnz .loop
    ret

ClearBitmap:
    ld hl, BITMAP
    call SetVramWrite
    xor a
    ld d, 128                   ; 128 x 256 = 32768바이트 = 256라인
.outer:
    ld b, 0
.inner:
    out (VDP_DATA), a
    nop
    djnz .inner
    dec d
    jr nz, .outer
    ret

UploadSpritePatterns:
    ld hl, SPRPAT
    call SetVramWrite
    ld hl, SpritePatterns
    ld de, SPR_PAT_COUNT * 32
.loop:
    ld a, (hl)
    inc hl
    out (VDP_DATA), a
    dec de
    ld a, d
    or e
    jr nz, .loop
    ret

;-----------------------------------------------------------------------------
; 스프라이트 색 테이블
;
; 색이 바뀌지 않는 슬롯은 한 번만 쓴다. 자기의 두 평면은 뱅킹할 때마다
; 라인별 색이 다른 패턴으로 바뀌므로 매 프레임 다시 쓴다. 적기 슬롯은
; 생성될 때, 보스 셀은 보스가 나타날 때 쓴다.
; 
;-----------------------------------------------------------------------------
InitSpriteColours:
    ; 글자 슬롯은 전부 흰색으로 시작한다. 스코어, 라벨 두 개, fps/cpu 숫자가
    ; 같은 색을 쓴다. 계측 표시는 UpdateHudColours가 나중에 다시 칠하고,
    ; 그 사이의 게이지는 코드에서 색을 정한다.
    ld b, SCORE_DIGITS
    ld c, SLOT_SCORE
.digits:
    push bc
    ld a, c
    ld c, PAT_DIGIT0
    call SetSlotColour
    pop bc
    inc c
    djnz .digits

    ld b, 6                     ; 라벨 + 숫자 2자리, 두 벌
    ld c, SLOT_FLABEL
.meters:
    push bc
    ld a, c
    ld c, PAT_DIGIT0
    call SetSlotColour
    pop bc
    inc c
    djnz .meters

    ld b, MAX_PB
    ld c, SLOT_PB
.pb:
    push bc
    ld a, c
    ld c, PAT_PBULLET_A
    call SetSlotColour
    pop bc
    inc c
    djnz .pb

    ld b, MAX_EB
    ld c, SLOT_EB
.eb:
    push bc
    ld a, c
    ld c, PAT_EBULLET_A
    call SetSlotColour
    pop bc
    inc c
    djnz .eb
    ret

; 게이지는 패턴에 박힌 색을 쓸 수 없다. 팔레트에서 초록 계열이라고는
; 요새 타일과 같은 올리브 하나뿐이라 게이지가 배경에 묻혀버렸다. 그래서
; 코드에서 색을 칠하고, 그 색으로 남은 양까지 알려준다.
; 
UpdateEnergyColour:
    ld a, (energy)
    cp 21
    ld b, 4                     ; 흰색 - 여유 있음
    jr nc, .decided
    cp 9
    ld b, 6                     ; 주황 - 줄어드는 중
    jr nc, .decided
    ld b, 11                    ; 빨강 - 위험
.decided:
    ld a, (energyColour)
    cp b
    ret z
    ld a, b
    ld (energyColour), a
    ld a, SLOT_ENERGY
    ; 아래로 이어짐

; A = 슬롯 번호, B = 색 번호. 그 슬롯의 16라인을 한 가지 색으로 채운다.
FillSlotColour:
    push bc
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, SPRCOL
    add hl, de
    call SetVramWrite
    pop bc
    ld a, b
    ld b, 16
.loop:
    out (VDP_DATA), a
    nop
    djnz .loop
    ret

; A = 슬롯 번호, C = 패턴 번호. 그 패턴의 색 16바이트를 해당 슬롯의
; 색 테이블 항목으로 복사한다. BC, DE, HL을 파괴한다.
SetSlotColour:
    push bc
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; 슬롯 번호 * 16
    ld de, SPRCOL
    add hl, de
    call SetVramWrite
    pop bc
    ld h, 0
    ld l, c
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; 패턴 번호 * 16
    ld de, SpriteColours
    add hl, de
    ld b, 16
.loop:
    ld a, (hl)
    inc hl
    out (VDP_DATA), a
    djnz .loop
    ret

;-----------------------------------------------------------------------------
; 배경
;
; R#23 하나로 VDP가 256라인 전부를 공짜로 스크롤해 주므로, 프레임마다
; 할 일은 곧 화면에 들어올 픽셀 라인 하나뿐이다. 128바이트, 약 3.7k
; T-state로 수직 귀선 기간 안에 여유 있게 끝난다.
;-----------------------------------------------------------------------------
; VRAM 256라인을 전부 채운다. VRAM 라인이 내려가는 동안 맵 라인은 전진하는데,
; 게임 중에도 같은 관계가 유지된다. 위로 갈수록 월드 좌표가 커진다.
PrefillBackground:
    ld e, 0
    ld b, 0                     ; 256회 반복
.loop:
    push bc
    push de
    call DrawLineTo
    call AdvanceMapLine
    pop de
    pop bc
    dec e
    djnz .loop
    ret

ScrollBackground:
    ld a, (scroll)
    dec a
    ld (scroll), a
    ld c, 23
    call WriteVdpReg            ; 스크롤은 하드웨어가 한다

    ; 그릴 대상은 방금 R#23에 쓴 값에서 계산한다. 별도 카운터를 돌리면
    ; 프레임이 한 번이라도 밀렸을 때 어긋나서 화면이 영구히 찢어진다.
    ; 
    ld a, (scroll)
    sub DRAW_BEHIND
    ld e, a
    call DrawLineTo
    jp AdvanceMapLine

; E = 채울 VRAM 라인. 현재 (mapRow, tileLine)에서 가져온다.
DrawLineTo:
    ld h, e
    ld l, 0
    srl h
    rr l                        ; HL = 라인 * 128
    call SetVramWrite

    ld a, (tileLine)
    add a, a
    add a, a
    add a, a
    ld c, a                     ; C = tileLine * 8. 이 라인 동안 상수

    ld a, (mapRow)
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; mapRow * MAP_COLS (16)
    ld de, TileMap
    add hl, de
    ex de, hl                   ; DE -> 이 행의 타일 번호들

    ld b, MAP_COLS
.col:
    ; TileData가 256바이트 정렬이라 타일의 픽셀 행 주소를 8비트 연산만으로
    ; 구할 수 있다. tile*128 = (tile>>1)*256 + (tile&1)*128
    ld a, (de)
    inc de
    srl a                       ; A = tile>>1, 캐리 = tile&1
    add a, TileData >> 8
    ld h, a
    ld a, 0
    rra                         ; 타일 번호가 홀수면 A = 0x80, 아니면 0
    add a, c                    ; + tileLine*8
    ld l, a

    ; 8바이트 = 16픽셀 = 타일 하나 폭의 픽셀 행. NOP은 VRAM 쓰기 간격을
    ; 29 T-state 이상으로 유지하기 위한 것으로, 화면이 켜져 있는 동안
    ; 비트맵 모드에서 V9938이 요구하는 값이다.
    ld a, (hl) : out (VDP_DATA), a : inc hl : nop
    ld a, (hl) : out (VDP_DATA), a : inc hl : nop
    ld a, (hl) : out (VDP_DATA), a : inc hl : nop
    ld a, (hl) : out (VDP_DATA), a : inc hl : nop
    ld a, (hl) : out (VDP_DATA), a : inc hl : nop
    ld a, (hl) : out (VDP_DATA), a : inc hl : nop
    ld a, (hl) : out (VDP_DATA), a : inc hl : nop
    ld a, (hl) : out (VDP_DATA), a : nop

    djnz .col
    ret

AdvanceMapLine:
    ld hl, tileLine
    inc (hl)
    ld a, (hl)
    cp 16
    ret c
    ld (hl), 0
    ld hl, mapRow
    inc (hl)
    ld a, (hl)
    cp MAP_ROWS
    ret c
    ld (hl), 0
    ret

;-----------------------------------------------------------------------------
; 입력 - MSX 키 매트릭스 8행: bit7 오른쪽, bit6 아래, bit5 위, bit4 왼쪽.
; 매트릭스는 반전되어 읽히므로 여기서 뒤집는다. 1이면 눌린 상태.
;-----------------------------------------------------------------------------
KEY_RIGHT   equ 7
KEY_DOWN    equ 6
KEY_UP      equ 5
KEY_LEFT    equ 4

ReadInput:
    in a, (PPI_ROW)
    and 0xF0                    ; 상위 비트는 카세트/LED 제어용이므로 보존한다
    or 8
    out (PPI_ROW), a
    in a, (PPI_COL)
    cpl
    ld (keyState), a
    ; 0행은 숫자 키다. bit0이 "0", bit1이 "1", bit2가 "2".
    in a, (PPI_ROW)
    and 0xF0                    ; 0행 선택
    out (PPI_ROW), a
    in a, (PPI_COL)
    cpl
    ld (keyRow0), a

    ld a, (keyState)
    and (1 << KEY_LEFT) | (1 << KEY_RIGHT) | (1 << KEY_UP) | (1 << KEY_DOWN)
    ret z
    xor a
    ld (demoMode), a            ; 사람이 조작 중이다. 자동 조종을 멈춘다
    ret

;-----------------------------------------------------------------------------
; 숫자 키 단축키. 전부 0행에서 에지 트리거로 읽는다:
;   "0"  fps/cpu 표시 줄을 켜고 끈다
;   "1"  중간보스를 부른다
;   "2"  거대보스를 부른다
;
; 레벨이 아니라 에지로 읽는 이유: 보스 키를 누르고 있으면 매 프레임 다시
; 생성되어 체력이 깎이지 않고, 토글은 깜빡이게 된다.
;
; 키로 부른 보스는 등장 완료로 표시해서, 같은 판에서 시간 트리거로 또
; 나오지 않게 한다.
;-----------------------------------------------------------------------------
KEY_0       equ 0
KEY_1       equ 1
KEY_2       equ 2

CheckHotKeys:
    ld a, (keyRow0)
    ld b, a
    ld a, (prevRow0)
    cpl
    and b                       ; 이번 프레임에 새로 눌린 비트
    ld c, a
    ld a, b
    ld (prevRow0), a

    bit KEY_0, c
    jr z, .not0
    ld a, (hudMeters)
    xor 1
    ld (hudMeters), a
.not0:
    bit KEY_1, c
    jr z, .not1
    ld a, 1
    ld (midDone), a
    jp SpawnBoss                ; A = 1
.not1:
    bit KEY_2, c
    ret z
    ld a, 1
    ld (giantDone), a
    ld a, 2
    jp SpawnBoss

;-----------------------------------------------------------------------------
; 어트랙트 모드 자동 조종.
;
; 그냥 두면 자기는 가만히 서 있다가 30초쯤 만에 격추되고, 데모는 게임
; 오버 화면에서 시간을 보낸다. 그러면 무인으로 찍는 verify.ps1 스크린샷에
; 볼 만한 장면이 거의 안 잡히고, 2분/4분 보스에도 도달하지 못한다.
; 그래서 키 입력을 흉내 내어 날아오는 총알을 피한다. 실제 키를 처음
; 누르는 순간 영구히 꺼진다.
; 
;-----------------------------------------------------------------------------
DemoControl:
    ld a, (demoMode)
    or a
    ret z
    xor a
    ld (keyState), a

    ld b, MAX_EB
    ld c, 0
.eb:
    push bc
    ld b, 0
    ld hl, ebActive
    add hl, bc
    ld a, (hl)
    or a
    jr z, .next
    ld hl, ebY
    add hl, bc
    ld a, (playerY)
    sub (hl)
    jr c, .next                 ; 이미 지나갔다
    cp 72
    jr nc, .next                ; 너무 멀리 위에 있어 신경 쓸 필요 없다
    ld hl, ebX
    add hl, bc
    ld a, (hl)
    ld hl, playerX
    sub (hl)                    ; A = 위협의 X - 자기의 X
    ld d, a
    add a, 20
    cp 40
    jr nc, .next                ; 같은 세로줄이 아니다
    ld a, d
    cp 128                      ; 128 이상이면 위협이 왼쪽에 있다는 뜻
    ld a, 1 << KEY_RIGHT
    jr nc, .steer
    ld a, 1 << KEY_LEFT
.steer:
    ld (keyState), a
    pop bc
    ret
.next:
    pop bc
    inc c
    djnz .eb
    ret

;-----------------------------------------------------------------------------
UpdatePlayer:
    ld a, 1
    ld (playerFrame), a         ; 방향키를 누르지 않았으면 가운데 프레임

    ld a, (keyState)
    ld b, a

    bit KEY_LEFT, b
    jr z, .noleft
    ld a, (playerX)
    sub PLAYER_SPEED
    jr c, .noleft
    ld (playerX), a
    xor a
    ld (playerFrame), a
.noleft:
    bit KEY_RIGHT, b
    jr z, .noright
    ld a, (playerX)
    add a, PLAYER_SPEED
    cp PLAYER_X_MAX + 1
    jr nc, .noright
    ld (playerX), a
    ld a, 2
    ld (playerFrame), a
.noright:
    bit KEY_UP, b
    jr z, .noup
    ld a, (playerY)
    sub PLAYER_SPEED
    jr c, .noup                 ; 범위 검사 전에 자리내림부터 잡는다
    cp PLAYER_Y_MIN
    jr c, .noup
    ld (playerY), a
.noup:
    bit KEY_DOWN, b
    jr z, .nodown
    ld a, (playerY)
    add a, PLAYER_SPEED
    cp PLAYER_Y_MAX + 1
    jr nc, .nodown
    ld (playerY), a
.nodown:

    ld hl, hitFlash
    ld a, (hl)
    or a
    jr z, .nohit
    dec (hl)
.nohit:

    ; 자동 발사. 입력이 전혀 없어도 화면이 채워져야 verify.ps1이 찍은
    ; 스크린샷에 날아가는 총알이 보인다.
    ld hl, fireTimer
    dec (hl)
    ret nz
    ld (hl), FIRE_PERIOD

FirePlayerBullet:
    ld hl, pbActive
    ld b, MAX_PB
    ld c, 0
.find:
    ld a, (hl)
    or a
    jr z, .got
    inc hl
    inc c
    djnz .find
    ret                         ; 총알이 전부 날아가는 중이다
.got:
    ld (hl), 1
    ld b, 0
    ld hl, pbX
    add hl, bc
    ld a, (playerX)
    ld (hl), a
    ld hl, pbY
    add hl, bc
    ld a, (playerY)
    sub 8
    ld (hl), a
    ret

;-----------------------------------------------------------------------------
UpdatePlayerBullets:
    ld b, MAX_PB
    ld c, 0
.loop:
    push bc
    ld b, 0
    ld hl, pbActive
    add hl, bc
    ld a, (hl)
    or a
    jr z, .next
    ld hl, pbY
    add hl, bc
    ld a, (hl)
    sub PB_SPEED
    jr c, .kill                 ; 화면 위로 빠져나갔다
    cp PLAY_TOP                 ; HUD 띠 안으로는 절대 들어가지 않는다
    jr c, .kill
    ld (hl), a
    jr .next
.kill:
    ld hl, pbActive
    add hl, bc
    ld (hl), 0
.next:
    pop bc
    inc c
    djnz .loop
    ret

;-----------------------------------------------------------------------------
; 적기
;-----------------------------------------------------------------------------
UpdateEnemies:
    ld a, (bossActive)
    or a
    jr nz, .nospawn             ; 보스가 적기 슬롯을 쓰고 있다
    ld hl, spawnTimer
    dec (hl)
    jr nz, .nospawn
    ld a, (level)               ; 레벨이 오를수록 생성 간격이 짧아진다
    add a, a
    add a, a
    ld b, a
    ld a, BASE_SPAWN
    sub b
    ld (hl), a
    call SpawnEnemy
.nospawn:

    ld b, MAX_EN
    ld c, 0
.loop:
    push bc
    ld b, 0
    ld hl, enActive
    add hl, bc
    ld a, (hl)
    or a
    jr z, .next

    ld hl, enY                  ; 아래로 내려온다
    add hl, bc
    ld a, (hl)
    inc a
    cp ENEMY_KILL_Y
    jr nc, .kill
    ld (hl), a

    ld hl, enX                  ; 좌우로 흐르다가 화면 끝에서 방향을 뒤집는다
    add hl, bc
    ld d, (hl)
    ld hl, enVX
    add hl, bc
    ld a, (hl)
    add a, d
    cp PLAYER_X_MAX + 1
    jr c, .xok
    ld a, (hl)
    neg
    ld (hl), a
    jr .fire                    ; 이번 프레임은 X를 그대로 둔다
.xok:
    ld hl, enX
    add hl, bc
    ld (hl), a

.fire:
    ld hl, enFire
    add hl, bc
    dec (hl)
    jr nz, .next
    call RandomFireDelay
    ld hl, enFire
    add hl, bc
    ld (hl), a
    ld hl, enX
    add hl, bc
    ld d, (hl)
    ld hl, enY
    add hl, bc
    ld e, (hl)
    call FireEnemyBullet
    jr .next

.kill:
    ld hl, enActive
    add hl, bc
    ld (hl), 0
.next:
    pop bc
    inc c
    djnz .loop
    ret

; 발사 간격을 A에 반환한다. 레벨이 높을수록 자주 쏜다.
;
; BC를 반드시 보존해야 한다. 호출하는 쪽 두 군데 모두 BC에 적기 번호를
; 담은 채로 이 루틴을 부르고, 돌아온 직후 그 BC로 배열을 인덱싱한다.
; push/pop이 없을 때는 아래 임시 계산이 B와 C를 덮어써서, 호출한 쪽이
; 발사한 적기의 X, Y를 수천 바이트 떨어진 주소에서 읽었다. 그 결과 적
; 총알이 적기가 없는 고정된 엉뚱한 좌표에서 튀어나왔다.
RandomFireDelay:
    push bc
    call Random
    and 0x1F
    ld b, a
    ld a, (level)
    add a, a
    add a, a
    add a, a                    ; level * 8
    ld c, a
    ld a, BASE_FIRE
    sub c
    add a, b
    pop bc
    ret

SpawnEnemy:
    ; 동시에 살아 있는 적기 수를 현재 레벨로 제한한다.
    ld hl, enActive
    ld b, MAX_EN
    ld c, 0                     ; C에 살아 있는 수를 센다
.tally:
    ld a, (hl)
    or a
    jr z, .notlive
    inc c
.notlive:
    inc hl
    djnz .tally
    ld a, (level)
    add a, BASE_ENEMIES
    cp MAX_EN + 1
    jr c, .capok
    ld a, MAX_EN
.capok:
    cp c
    ret z
    ret c                       ; 이 레벨의 상한에 이미 도달했다

    ld hl, enActive
    ld b, MAX_EN
    ld c, 0
.find:
    ld a, (hl)
    or a
    jr z, .got
    inc hl
    inc c
    djnz .find
    ret
.got:
    ld (hl), 1
    ld b, 0

    call Random
    and 0xE0                    ; 0..224. 스프라이트가 화면 안에 온전히 들어오도록
    ld hl, enX
    add hl, bc
    ld (hl), a

    ld hl, enY
    add hl, bc
    ld (hl), PLAY_TOP           ; HUD 띠 아래에서 등장

    call Random
    and 3
    dec a                       ; 프레임당 좌우 이동 -1..2픽셀
    ld hl, enVX
    add hl, bc
    ld (hl), a

    call Random
    call TypeOfByte
    ld hl, enType
    add hl, bc
    ld (hl), a
    push af

    call RandomFireDelay
    ld hl, enFire
    add hl, bc
    ld (hl), a

    pop af                      ; 그 슬롯에 해당 타입의 색을 넣는다
    add a, PAT_ENEMY0_A
    ld e, a
    ld a, c
    add a, SLOT_EN
    ld c, e
    jp SetSlotColour

; A를 0, 1, 2 중 하나로
TypeOfByte:
    and 3
    cp 3
    ret c
    xor a
    ret

; D = 발사 지점 X, E = 발사 지점 Y. 프레임당 1픽셀씩 자기 쪽으로 향한다.
FireEnemyBullet:
    ld hl, ebActive
    ld b, MAX_EB
    ld c, 0
.find:
    ld a, (hl)
    or a
    jr z, .got
    inc hl
    inc c
    djnz .find
    ret
.got:
    ld (hl), 1
    ld b, 0
    ld hl, ebX
    add hl, bc
    ld (hl), d
    ld hl, ebY
    add hl, bc
    ld (hl), e

    ld a, (playerX)
    sub d
    ld a, 1
    jr nc, .right
    ld a, -1
.right:
    ld hl, ebVX
    add hl, bc
    ld (hl), a
    ret

;-----------------------------------------------------------------------------
UpdateEnemyBullets:
    ld b, MAX_EB
    ld c, 0
.loop:
    push bc
    ld b, 0
    ld hl, ebActive
    add hl, bc
    ld a, (hl)
    or a
    jr z, .next

    ld hl, ebY
    add hl, bc
    ld a, (hl)
    add a, EB_SPEED
    cp ENEMY_KILL_Y
    jr nc, .kill
    ld (hl), a

    ld hl, ebX
    add hl, bc
    ld d, (hl)
    ld hl, ebVX
    add hl, bc
    ld a, (hl)
    add a, d
    cp PLAYER_X_MAX + 1
    jr nc, .kill                ; 옆으로 화면을 벗어났다
    ld hl, ebX
    add hl, bc
    ld (hl), a
    jr .next
.kill:
    ld hl, ebActive
    add hl, bc
    ld (hl), 0
.next:
    pop bc
    inc c
    djnz .loop
    ret

;-----------------------------------------------------------------------------
; 보스
;
; 보스는 적기 슬롯 전체를 가져다 쓰고, 16x16 셀의 격자로 그린다.
; 보스가 살아 있는 동안에는 일반 적기가 생성되지 않는다.
;-----------------------------------------------------------------------------
SpawnBoss:
    ; A = 1이면 중간보스, 2면 거대보스
    ld (bossActive), a
    cp 2
    jr z, .giant
    ld a, MBOSS_COLS
    ld (bossCols), a
    ld a, MBOSS_COLS * MBOSS_ROWS
    ld (bossCells), a
    ld a, MBOSS_HP
    jr .common
.giant:
    ld a, GBOSS_COLS
    ld (bossCols), a
    ld a, GBOSS_COLS * GBOSS_ROWS
    ld (bossCells), a
    ld a, GBOSS_HP
.common:
    ld (bossHP), a
    ld a, 96
    ld (bossX), a
    ld a, BOSS_Y
    ld (bossY), a
    ld a, 1
    ld (bossVX), a
    ld a, 40
    ld (bossFire), a

    ; 살아 있는 적기를 모두 지운다. 보스가 그 슬롯을 써야 한다.
    ld hl, enActive
    ld b, MAX_EN
    xor a
.clear:
    ld (hl), a
    inc hl
    djnz .clear

    ; 각 셀의 색을 그 셀이 그려질 슬롯에 넣는다.
    call BossPatternBase
    ld d, a                     ; D = 첫 패턴 번호
    ld a, (bossCells)
    ld b, a
    ld c, 0                     ; C = 셀 번호
.col:
    push bc
    push de
    ld a, c
    add a, SLOT_EN              ; A = 슬롯 번호
    ld c, d                     ; C = 패턴 번호
    call SetSlotColour
    pop de
    pop bc
    inc d
    inc c
    djnz .col
    ret

; 현재 보스의 첫 스프라이트 패턴 번호를 A에 반환한다.
BossPatternBase:
    ld a, (bossActive)
    cp 2
    ld a, PAT_MBOSS0_A
    ret nz
    ld a, PAT_GBOSS0_A
    ret

; 현재 보스의 가로 픽셀 수를 A에 반환한다.
BossWidth:
    ld a, (bossActive)
    cp 2
    ld a, MBOSS_COLS * 16
    ret nz
    ld a, GBOSS_COLS * 16
    ret

; 현재 보스의 세로 픽셀 수를 A에 반환한다.
BossHeight:
    ld a, (bossActive)
    cp 2
    ld a, MBOSS_ROWS * 16
    ret nz
    ld a, GBOSS_ROWS * 16
    ret

UpdateBoss:
    ld a, (bossActive)
    or a
    ret z

    ; 좌우로 왕복하다가 끝에서 방향을 뒤집는다
    ld a, (bossVX)
    ld b, a
    ld a, (bossX)
    add a, b
    ld (bossX), a
    ld c, a
    call BossWidth
    ld b, a
    ld a, 255
    sub b                       ; 허용되는 가장 오른쪽 X
    cp c
    jr nc, .xok
    ld a, (bossVX)
    neg
    ld (bossVX), a
.xok:

    ld hl, bossFire
    dec (hl)
    ret nz
    ld a, (level)
    add a, a
    ld b, a
    ld a, 60
    sub b
    ld (hl), a

    ; 아래쪽 가운데에서 발사. 거대보스는 한 발 더 쏜다
    call BossHeight
    ld b, a
    ld a, (bossY)
    add a, b
    sub 16
    ld e, a
    call BossWidth
    srl a
    ld b, a
    ld a, (bossX)
    add a, b
    ld d, a
    push de
    call FireEnemyBullet
    pop de
    ld a, (bossActive)
    cp 2
    ret nz
    ld a, d
    sub 20
    ld d, a
    jp FireEnemyBullet

;-----------------------------------------------------------------------------
; 충돌 판정
;
; 단순한 사각형 겹침 검사다. VDP의 충돌 플래그는 '무언가 겹쳤다'만
; 알려주고 무엇과 무엇인지는 알 수 없어서 쓸모가 없다.
; 
;
; (b - a + 절반) < 폭 관용구는 8비트 랩어라운드에서도 그대로 성립하므로
; 부호 있는 비교가 필요 없다.
;-----------------------------------------------------------------------------
Collisions:
    ld b, MAX_PB
    ld c, 0
.pb:
    push bc
    call BulletVsEnemies
    pop bc
    inc c
    djnz .pb

    call BulletsVsBoss

    ld a, (hitFlash)
    or a
    ret nz                      ; 아직 무적 시간. 피격을 무시한다

    ld b, MAX_EB
    ld c, 0
.eb:
    push bc
    call EnemyBulletVsPlayer
    pop bc
    inc c
    djnz .eb

    ; 적기와 부딪히면 총알보다 더 아프다
    ld a, (hitFlash)
    or a
    ret nz
    ld b, MAX_EN
    ld c, 0
.en:
    push bc
    call EnemyVsPlayer
    pop bc
    inc c
    djnz .en
    ret

; C = 자기 총알 번호.
BulletVsEnemies:
    ld b, 0
    ld hl, pbActive
    add hl, bc
    ld a, (hl)
    or a
    ret z
    ld hl, pbX
    add hl, bc
    ld d, (hl)
    ld hl, pbY
    add hl, bc
    ld e, (hl)

    push bc                     ; 총알 번호를 보관해 둔다
    ld b, MAX_EN
    ld c, 0
.loop:
    push bc
    ld b, 0
    ld hl, enActive
    add hl, bc
    ld a, (hl)
    or a
    jr z, .next
    ld hl, enX
    add hl, bc
    ld a, (hl)
    sub d
    add a, 12
    cp 24
    jr nc, .next
    ld hl, enY
    add hl, bc
    ld a, (hl)
    sub e
    add a, 12
    cp 24
    jr nc, .next

    ld hl, enActive             ; 명중 - 둘 다 제거
    add hl, bc
    ld (hl), 0
    call EnemyDestroyed
    pop bc
    pop bc
    ld b, 0
    ld hl, pbActive
    add hl, bc
    ld (hl), 0
    ret
.next:
    pop bc
    inc c
    djnz .loop
    pop bc
    ret

EnemyDestroyed:
    push bc
    ld a, SFX_EXP_LEN
    ld (sfxNoise), a
    ld a, 1                     ; 100점
    ld c, 3
    call AddScore
    pop bc
    ret

; 살아 있는 자기 총알 전부를 보스의 사각 영역과 비교한다.
; BossWidth/BossHeight는 A만 건드리므로 BC와 DE는 호출 뒤에도 살아 있다.
BulletsVsBoss:
    ld a, (bossActive)
    or a
    ret z
    ld b, MAX_PB
    ld c, 0
.loop:
    push bc
    ld b, 0
    ld hl, pbActive
    add hl, bc
    ld a, (hl)
    or a
    jr z, .next

    ld hl, pbX
    add hl, bc
    ld d, (hl)                  ; D = 총알 X
    ld hl, pbY
    add hl, bc
    ld e, (hl)                  ; E = 총알 Y

    call BossWidth
    srl a
    ld h, a                     ; H = 가로 절반
    ld a, (bossX)
    add a, h                    ; 보스 중심 X
    sub d
    add a, h                    ; 중심 - 총알 + 절반
    ld l, a
    ld a, h
    add a, a                    ; 전체 폭
    cp l
    jr c, .next                 ; 가로로 빗나감
    jr z, .next

    call BossHeight
    srl a
    ld h, a
    ld a, (bossY)
    add a, h
    sub e
    add a, h
    ld l, a
    ld a, h
    add a, a
    cp l
    jr c, .next                 ; 세로로 빗나감
    jr z, .next

    ld hl, pbActive             ; 명중
    add hl, bc
    ld (hl), 0
    call BossHit
.next:
    pop bc
    inc c
    djnz .loop
    ret

BossHit:
    push bc
    ld a, SFX_EXP_LEN
    ld (sfxNoise), a
    ld a, 1                     ; 명중 1회에 10점
    ld c, 4
    call AddScore
    ld hl, bossHP
    dec (hl)
    jr nz, .alive
    xor a
    ld (bossActive), a
    ld a, 5                     ; 격파에 5000점
    ld c, 1
    call AddScore
.alive:
    pop bc
    ret

; C = 적 총알 번호.
EnemyBulletVsPlayer:
    ld b, 0
    ld hl, ebActive
    add hl, bc
    ld a, (hl)
    or a
    ret z
    ld hl, ebX
    add hl, bc
    ld a, (hl)
    ld hl, playerX
    sub (hl)
    add a, 10
    cp 20
    ret nc
    ld hl, ebY
    add hl, bc
    ld a, (hl)
    ld hl, playerY
    sub (hl)
    add a, 10
    cp 20
    ret nc
    ld hl, ebActive
    add hl, bc
    ld (hl), 0
    ld a, DMG_BULLET
    jp DamagePlayer

; C = 적기 번호.
EnemyVsPlayer:
    ld b, 0
    ld hl, enActive
    add hl, bc
    ld a, (hl)
    or a
    ret z
    ld hl, enX
    add hl, bc
    ld a, (hl)
    ld hl, playerX
    sub (hl)
    add a, 13
    cp 26
    ret nc
    ld hl, enY
    add hl, bc
    ld a, (hl)
    ld hl, playerY
    sub (hl)
    add a, 13
    cp 26
    ret nc
    ld hl, enActive             ; 충돌한 적기도 함께 파괴된다
    add hl, bc
    ld (hl), 0
    call EnemyDestroyed
    ld a, DMG_CRASH
    jp DamagePlayer

; A = 피해량. 직전 피격의 무적 시간 중이면 무시한다.
DamagePlayer:
    ld b, a
    ld a, (hitFlash)
    or a
    ret nz
    ld a, HIT_FLASH
    ld (hitFlash), a
    ld a, SFX_HIT_LEN
    ld (sfxTone), a
    ld a, (energy)
    sub b
    jr nc, .ok
    xor a
.ok:
    ld (energy), a
    or a
    ret nz
    ld a, 1
    ld (gameState), a
    ld a, GAMEOVER_TIME
    ld (overTimer), a
    jp SetGameOverColours

;-----------------------------------------------------------------------------
; 스코어 - BCD 6자리. 높은 자리가 앞이다.
; C = 더할 자릿수 위치, A = 더할 값 (0..9).
;-----------------------------------------------------------------------------
AddScore:
    ld hl, score
    ld b, 0
    add hl, bc
    ld d, c                     ; D = 현재 자릿수 위치
    add a, (hl)
.loop:
    cp 10
    jr c, .store
    sub 10
    ld (hl), a
    ld a, d
    or a
    ret z                       ; 최상위 자리를 넘었다. 최대값으로 둔다
    dec d
    dec hl
    ld a, (hl)
    inc a
    jr .loop
.store:
    ld (hl), a
    ret

;-----------------------------------------------------------------------------
; 시간, 난이도, 보스 등장 판정
;-----------------------------------------------------------------------------
AdvanceTime:
    ld hl, (frameCount)
    inc hl
    ld (frameCount), hl

    ld a, h                     ; level = frameCount / 512, 상한 적용
    srl a
    cp MAX_LEVEL + 1
    jr c, .lvlok
    ld a, MAX_LEVEL
.lvlok:
    ld (level), a

    ld a, (bossActive)
    or a
    ret nz

    ld a, (midDone)
    or a
    jr nz, .checkgiant
    push hl
    ld de, MIDBOSS_FRAME
    or a
    sbc hl, de
    pop hl
    jr c, .checkgiant
    ld a, 1
    ld (midDone), a
    jp SpawnBoss

.checkgiant:
    ld a, (giantDone)
    or a
    ret nz
    push hl
    ld de, GIANTBOSS_FRAME
    or a
    sbc hl, de
    pop hl
    ret c
    ld a, 1
    ld (giantDone), a
    ld a, 2
    jp SpawnBoss

;-----------------------------------------------------------------------------
; 게임 오버 - 정지하고 스코어를 점멸시킨 뒤 새 판을 시작한다. 무인으로도
; 데모가 계속 돌아가게 하기 위해서다.
;-----------------------------------------------------------------------------
UpdateGameOver:
    ld hl, overTimer
    dec (hl)
    ret nz
    jp ResetGame

;-----------------------------------------------------------------------------
; 사운드 - PSG 채널 A는 피격 톤, 채널 B는 폭발 노이즈를 낸다. 둘 다
; 프레임마다 한 번 갱신하는 원샷 엔벨로프다.
;-----------------------------------------------------------------------------
InitPsg:
    ; MSX에서 R7은 항상 10xxxxxx여야 한다. bit7은 포트 B를 출력(조이스틱
    ; 선택)으로, bit6은 포트 A를 입력으로 유지한다. 톤 A와 노이즈 B만 켠다.
    ld a, 7
    ld e, 0xAE
    call WritePsg
    ld a, 8
    ld e, 0
    call WritePsg
    ld a, 9
    ld e, 0
    call WritePsg
    ld a, 10                    ; 채널 C는 계속 무음
    ld e, 0
    call WritePsg
    ld a, 6                     ; 노이즈 주기
    ld e, 6
    jp WritePsg

; A = PSG 레지스터 번호, E = 쓸 값.
WritePsg:
    out (PSG_ADDR), a
    ld a, e
    out (PSG_DATA), a
    ret

UpdateSound:
    ; 채널 A: sfxTone이 줄어드는 동안 음이 떨어지는 톤
    ld a, (sfxTone)
    or a
    jr z, .toneoff
    dec a
    ld (sfxTone), a
    ld b, a
    ld a, SFX_HIT_LEN
    sub b                       ; 1..30. 효과가 잦아들수록 커진다
    add a, a
    add a, a
    add a, a                    ; * 8 -> 8..240. 미세 조정 바이트 범위 안에 머문다
    ld e, a                     ; 주기가 길수록 음이 낮아지므로 톤이 떨어진다
    ld a, 0
    call WritePsg               ; R0 미세 조정
    ld a, 1
    ld e, 1
    call WritePsg               ; R1 거친 조정
    ld a, b
    srl a                       ; 잦아들면서 음량 0..15
    ld e, a
    ld a, 8
    jr .tonedone
.toneoff:
    ld a, 8
    ld e, 0
.tonedone:
    call WritePsg

    ; 채널 B: sfxNoise가 줄어드는 동안 노이즈
    ld a, (sfxNoise)
    or a
    jr z, .noiseoff
    dec a
    ld (sfxNoise), a
    ld e, a
    ld a, 9
    jr .noisedone
.noiseoff:
    ld a, 9
    ld e, 0
.noisedone:
    jp WritePsg

;-----------------------------------------------------------------------------
; 스프라이트 테이블 조립 - 32슬롯 전부를 RAM에 만들어 한 번에 전송한다.
;
; 중요한 V9938 동작: 수직 스크롤 레지스터 R#23은 비트맵뿐 아니라
; 스프라이트 평면도 함께 민다. 속성에 Y라고 적힌 스프라이트는 화면
; Y + 1 - R#23 라인에 그려지므로, 가만히 있어야 할 물체가 배경 스크롤을
; 따라 위로 흘러가 버린다. 그래서 여기서 쓰는 Y는 전부 BiasY를 거쳐
; 현재 스크롤 값을 도로 더한다.
;
; BiasY는 결과가 216이 되는 것도 막는다. 속성에서 216은 '스프라이트 목록의
; 끝'을 뜻하므로, 보정 결과가 거기 걸리면 VDP가 스캔을 멈춰 그 프레임의
; 뒤쪽 스프라이트가 전부 사라진다. 1픽셀 밀어내는 것은 눈에 안 띄지만
; 스프라이트가 사라지는 것은 눈에 띈다.
;-----------------------------------------------------------------------------
; A = 오브젝트 Y -> A = 속성에 쓸 Y. BC, DE, HL을 보존한다.
BiasY:
    push hl
    ld hl, yBias
    add a, (hl)
    pop hl
    cp SPR_END_Y
    ret nz
    dec a
    ret

; (HL)에 숨김 항목 하나를 쓰고 HL을 4 진행시킨다.
HideSlot:
    ld a, (hideY)
    ld (hl), a
    inc hl
    ld (hl), 0
    inc hl
    ld (hl), 0
    inc hl
    ld (hl), 0
    inc hl
    ret

; 항목 하나를 쓴다. E = 오브젝트 Y, D = X, A = 패턴 번호. HL을 4 진행.
PutSlot:
    push af
    ld a, e
    call BiasY
    ld (hl), a
    inc hl
    ld (hl), d
    inc hl
    pop af
    add a, a
    add a, a                    ; 패턴 번호 = 인덱스 * 4
    ld (hl), a
    inc hl
    ld (hl), 0
    inc hl
    ret

BuildSprites:
    ld a, (scroll)
    ld (yBias), a
    add a, SPR_HIDE_Y           ; 쓰지 않는 스프라이트는 화면 아래로 치운다
    cp SPR_END_Y
    jr nz, .hideok
    dec a                       ; 목록 종료값과 절대 겹치지 않게 한다
.hideok:
    ld (hideY), a

    ld hl, sprShadow

    ;--- 1번 줄 가운데: 스코어 -----------------------------------------------
    ld ix, score
    ld b, SCORE_DIGITS
    ld d, SCORE_X
.scoreloop:
    push bc
    ld a, (gameState)           ; 게임 오버 화면에서는 스코어를 점멸시킨다
    or a
    jr z, .showdigit
    ld a, (overTimer)
    and 8
    jr nz, .showdigit
    call HideSlot
    jr .scorenext
.showdigit:
    ld a, (ix + 0)
    add a, PAT_DIGIT0
    ld e, HUD_Y
    call PutSlot
.scorenext:
    inc ix
    ld a, d
    add a, GLYPH_STEP
    ld d, a
    pop bc
    djnz .scoreloop

    ;--- 1번 줄 오른쪽: 에너지 게이지 ---------------------------------------
    ; 32포인트를 16열 게이지 하나로 보이므로 한 열이 2포인트다. 스코어와
    ; 같은 줄에 있고, 남은 양이 적으면 점멸한다.
    ld a, (energy)
    srl a
    ld c, a                     ; 0..16 열
    ld a, (energy)
    cp 9
    jr nc, .energyshow
    ld a, (frameCount)
    and 8
    jr nz, .energyshow
    call HideSlot
    jr .meters
.energyshow:
    ld a, c
    add a, PAT_ENERGY0
    ld d, ENERGY_X
    ld e, HUD_Y
    call PutSlot

    ;--- 2번 줄: "F" fps, "C" cpu. 켜져 있을 때만 ----------------------------
.meters:
    ld a, (hudMeters)
    or a
    jr nz, .metersshow
    call HideSlot               ; 여섯 슬롯을 화면 밖으로 치운다
    call HideSlot
    call HideSlot
    call HideSlot
    call HideSlot
    call HideSlot
    jr .player
.metersshow:
    ld a, PAT_LABEL0            ; F
    ld d, FPS_X
    ld e, METER_Y
    call PutSlot
    ld a, (fpsTens)
    add a, PAT_DIGIT0
    ld d, FPS_X + LABEL_GAP
    ld e, METER_Y
    call PutSlot
    ld a, (fpsUnits)
    add a, PAT_DIGIT0
    ld d, FPS_X + LABEL_GAP + GLYPH_STEP
    ld e, METER_Y
    call PutSlot

    ld a, PAT_LABEL1            ; C
    ld d, CPU_X
    ld e, METER_Y
    call PutSlot
    ld a, (cpuTens)
    add a, PAT_DIGIT0
    ld d, CPU_X + LABEL_GAP
    ld e, METER_Y
    call PutSlot
    ld a, (cpuUnits)
    add a, PAT_DIGIT0
    ld d, CPU_X + LABEL_GAP + GLYPH_STEP
    ld e, METER_Y
    call PutSlot

    ;--- 자기: 같은 위치의 평면 두 장을 인접 슬롯에 -------------------------
.player:
    ld a, (gameState)
    or a
    jp nz, BuildGameOver        ; 남은 슬롯은 저쪽에서 전부 채운다
    ld a, (hitFlash)
    or a
    jr z, .playerdraw
    and 4                       ; 무적 시간 동안 점멸
    jr nz, .playerhidden
.playerdraw:
    ld a, (playerFrame)
    add a, a                    ; 프레임 번호 -> 본체 평면의 패턴 번호
    ld c, a
    ld a, (playerY)
    ld e, a
    ld a, (playerX)
    ld d, a
    ld a, c
    call PutSlot
    ld a, c
    inc a                       ; 디테일 평면은 본체 평면 바로 다음이다
    call PutSlot
    jr .bullets
.playerhidden:
    call HideSlot
    call HideSlot

    ;--- 자기 총알 -----------------------------------------------------------
.bullets:
    ld b, MAX_PB
    ld c, 0
.pbloop:
    push bc
    ld b, 0
    push hl
    ld hl, pbActive
    add hl, bc
    ld a, (hl)
    pop hl
    or a
    jr nz, .pbdraw
    call HideSlot
    jr .pbdone
.pbdraw:
    push hl
    ld hl, pbY
    add hl, bc
    ld e, (hl)
    ld hl, pbX
    add hl, bc
    ld d, (hl)
    pop hl
    ld a, PAT_PBULLET_A
    call PutSlot
.pbdone:
    pop bc
    inc c
    djnz .pbloop

    ;--- 적기, 또는 보스의 셀 -----------------------------------------------
    ld a, (bossActive)
    or a
    jp nz, BuildBossCells
BuildEnemySlots:
    ld b, MAX_EN
    ld c, 0
.enloop:
    push bc
    ld b, 0
    push hl
    ld hl, enActive
    add hl, bc
    ld a, (hl)
    pop hl
    or a
    jr nz, .endraw
    call HideSlot
    jr .endone
.endraw:
    push hl
    ld hl, enY
    add hl, bc
    ld e, (hl)
    ld hl, enX
    add hl, bc
    ld d, (hl)
    ld hl, enType
    add hl, bc
    ld a, (hl)
    pop hl
    add a, PAT_ENEMY0_A
    call PutSlot
.endone:
    pop bc
    inc c
    djnz .enloop

BuildBulletSlots:
    ld b, MAX_EB
    ld c, 0
.ebloop:
    push bc
    ld b, 0
    push hl
    ld hl, ebActive
    add hl, bc
    ld a, (hl)
    pop hl
    or a
    jr nz, .ebdraw
    call HideSlot
    jr .ebdone
.ebdraw:
    push hl
    ld hl, ebY
    add hl, bc
    ld e, (hl)
    ld hl, ebX
    add hl, bc
    ld d, (hl)
    pop hl
    ld a, PAT_EBULLET_A
    call PutSlot
.ebdone:
    pop bc
    inc c
    djnz .ebloop
    ret

; 게임 오버 화면에서는 오브젝트가 전부 없으므로, 그 슬롯을 빌려 글자를
; 표시한다. 글자 여덟 개가 자기와 총알이 쓰던 슬롯에 들어가고, 그 위쪽
; 슬롯은 전부 화면 밖으로 치운다.
GAMEOVER_Y  equ 100

BuildGameOver:
    ld ix, GameOverGlyphs
    ld b, 8
.glyph:
    ld a, (ix + 0)
    add a, PAT_LET0
    ld d, (ix + 1)
    ld e, GAMEOVER_Y
    call PutSlot                ; BC, DE, IX를 보존한다
    inc ix
    inc ix
    djnz .glyph

    ld b, NUM_SLOTS - SLOT_PLAYER - 8
.hide:
    call HideSlot
    djnz .hide
    ret

; LETTER_FONT의 글자 번호(G A M E O V R), 그다음 X 좌표
GameOverGlyphs:
    db 0, 78
    db 1, 88
    db 2, 98
    db 3, 108
    db 4, 130
    db 5, 140
    db 3, 150
    db 6, 160

; 글자에 쓰는 슬롯은 원래 자기와 자기 총알의 것이므로, 메시지가 뜰 때
; 색 테이블을 흰색으로 칠하고 재시작할 때 ResetGame이 되돌린다.
; 
SetGameOverColours:
    ld b, 8
    ld c, SLOT_PLAYER
.loop:
    push bc
    ld a, c
    ld b, 4                     ; 흰색
    call FillSlotColour
    pop bc
    inc c
    djnz .loop
    ret

; 보스를 16x16 셀 격자로 적기 슬롯에 배치하고, 격자가 채우지 못한
; 나머지 슬롯은 숨긴다.
; PutSlot과 HideSlot은 BC와 DE를 보존하므로 커서가 호출 뒤에도 살아 있다.
BuildBossCells:
    call BossPatternBase
    ld c, a                     ; C = 진행 중인 패턴 번호
    ld a, (bossX)
    ld d, a
    ld a, (bossY)
    ld e, a
    xor a
    ld (bossColIdx), a
    ld a, (bossCells)
    ld b, a
.cell:
    ld a, c
    call PutSlot
    inc c
    ld a, d
    add a, 16
    ld d, a

    push hl                     ; HL은 그림자 테이블의 쓰기 커서다
    ld hl, bossColIdx
    inc (hl)
    ld a, (bossCols)
    cp (hl)
    jr nz, .keep
    ld (hl), 0                  ; Z 플래그를 건드리지 않는다
.keep:
    pop hl
    jr nz, .samerow
    ld a, (bossX)               ; 다음 셀 행의 처음으로 넘어간다
    ld d, a
    ld a, e
    add a, 16
    ld e, a
.samerow:
    djnz .cell

    ld a, (bossCells)
    ld b, a
    ld a, MAX_EN
    sub b
    jp z, BuildBulletSlots
    ld b, a
.hide:
    call HideSlot
    djnz .hide
    jp BuildBulletSlots

UploadSprites:
    ; 자기의 색 테이블은 현재 뱅킹 프레임을 따라간다.
    ld a, (playerFrame)
    add a, a
    ld c, a
    ld a, SLOT_PLAYER
    push bc
    call SetSlotColour
    pop bc
    ld a, c
    inc a
    ld c, a
    ld a, SLOT_PLAYER + 1
    call SetSlotColour

    ; 32슬롯 전부에 유효한 항목이 들어 있으므로 목록 종료값을 쓸 필요가
    ; 없다. 정확히 128바이트만 내보낸다.
    ld hl, SPRATTR
    call SetVramWrite
    ld hl, sprShadow
    ld b, NUM_SLOTS * 4
.loop:
    ld a, (hl)
    inc hl
    out (VDP_DATA), a
    djnz .loop
    ret

;-----------------------------------------------------------------------------
; 게임 상태
;-----------------------------------------------------------------------------
InitGameState:
    ld hl, Vars
    ld de, Vars + 1
    ld bc, VarsEnd - Vars - 1
    ld (hl), 0
    ldir                        ; 작업 영역 전체를 0으로
    ld hl, 0xACE1               ; 0이 아니면 아무 시드나
    ld (rngState), hl
    ld a, 1
    ld (demoMode), a            ; ResetGame에서도 유지되므로 수동 조작 상태가 그대로다
    ; 아래로 이어짐

; 배경 스크롤은 건드리지 않고 판만 다시 시작한다. 스크롤이 계속 돌아가야
; 재시작이 눈에 거슬리지 않는다.
ResetGame:
    ld hl, ResetStart
    ld de, ResetStart + 1
    ld bc, ResetEnd - ResetStart - 1
    ld (hl), 0
    ldir

    ld hl, score
    ld de, score + 1
    ld bc, SCORE_DIGITS - 1
    ld (hl), 0
    ldir

    xor a
    ld (gameState), a
    ld (bossActive), a
    ld (midDone), a
    ld (giantDone), a
    ld (sfxTone), a
    ld (sfxNoise), a
    ld (level), a
    ld hl, 0
    ld (frameCount), hl

    ld a, 120
    ld (playerX), a
    ld a, 160
    ld (playerY), a
    ld a, 1
    ld (playerFrame), a
    ld a, FIRE_PERIOD
    ld (fireTimer), a
    ld a, BASE_SPAWN
    ld (spawnTimer), a
    ld a, ENERGY_MAX
    ld (energy), a
    ld a, 30
    ld (cpuTimer), a
    ld a, 60
    ld (fpsTimer), a
    xor a
    ld (lateCount), a
    ld (cpuPct), a
    ; 계측 표시를 정상값으로 초기화한다. 0으로 두면 첫 1초 동안 fps가
    ; 빨간 "00"으로 보여서 부팅부터 고장 난 것처럼 읽힌다.
    ld a, 60
    ld (fpsVal), a
    ld a, 6
    ld (fpsTens), a
    xor a
    ld (fpsUnits), a
    xor a
    ld (hitFlash), a
    dec a                       ; 0xFF: 유효한 캐시 색이 없음. 강제로 다시 쓰게 한다
    ld (energyColour), a
    jp InitSpriteColours        ; 메시지가 빌려 갔던 슬롯을 다시 칠한다

; 16비트 Galois LFSR, 탭 0xB400. 하위 바이트를 A에 반환한다.
Random:
    push hl
    ld hl, (rngState)
    srl h
    rr l
    jr nc, .skip
    ld a, h
    xor 0xB4
    ld h, a
.skip:
    ld (rngState), hl
    ld a, l
    pop hl
    ret

;-----------------------------------------------------------------------------
; VDP 기본 루틴
;-----------------------------------------------------------------------------
; vblank를 기다리면서 그 프레임에 얼마나 여유가 남았는지도 잰다.
; CPU 사용량 표시가 여기서 나온다.
;
; 상태 레지스터 S#0의 vblank 플래그를 폴링한다. S#0은 읽으면 플래그가
; 지워지므로 인터럽트를 끈 상태로 돌려야 한다. 핸들러가 먼저 읽어가면
; 플래그를 가로채 버린다.
;
; 대기 루프 한 바퀴를 정확히 597 T-state가 되도록 패딩했다:
;     inc de 6 + ld b,43 7 + djnz x43 554 + in 11 + and 7 + jr 12 = 597
; 60Hz 프레임은 3579545/60 = 59659 T-state이므로, 완전히 노는 프레임은
; 59659/597 = 99.9가 나온다. 즉 카운트가 곧 여유 퍼센트라 나눗셈이
; 필요 없다. R#9로 VDP를 60Hz 모드에 두므로 PAL 기기에서도 같다.
; 
;
; 도착했을 때 이미 플래그가 서 있으면 그 프레임은 마감을 넘긴 것이다.
; 여유는 0이고 늦은 프레임으로 세며, 그것이 fps 표시를 떨어뜨린다.
IDLE_FULL   equ 100

WaitVBlankMeasured:
    ld de, 0
    in a, (VDP_ADDR)
    and 0x80
    jr nz, .late
.spin:
    inc de
    ld b, 43
.pad:
    djnz .pad
    in a, (VDP_ADDR)
    and 0x80
    jr z, .spin
    ld (idleCount), de
    ret
.late:
    ld (idleCount), de          ; 여전히 0
    ld hl, lateCount
    inc (hl)
    ret

;-----------------------------------------------------------------------------
; HUD 계측 표시.
;
; CPU는 초당 두 번, fps는 초당 한 번 갱신한다. 더 자주 바꾸면 숫자를
; 읽을 수 없다.
;
; fps는 따로 시간을 재는 대신 놓친 마감으로 구한다. 루프가 vblank에
; 물려 있으므로 프레임을 흘리지 않는 한 항상 주사율로 돈다. 따라서
; 60에서 구간 내 늦은 프레임 수를 뺀 값이 제때 끝난 프레임 수다.
; 
;-----------------------------------------------------------------------------
UpdateMeters:
    ld hl, cpuTimer
    dec (hl)
    jr nz, .fps
    ld (hl), 30
    ld hl, (idleCount)
    ld a, h
    or a
    jr nz, .zerocpu             ; 여유가 255를 넘으면 부하 없음으로 본다
    ld a, l
    cp IDLE_FULL + 1
    jr nc, .zerocpu
    ld b, a
    ld a, IDLE_FULL
    sub b
    jr .storecpu
.zerocpu:
    xor a
.storecpu:
    cp 100
    jr c, .cpuok
    ld a, 99                    ; 표시는 두 자리다
.cpuok:
    ld (cpuPct), a
    call ByteToDigits
    ld a, d
    ld (cpuTens), a
    ld a, e
    ld (cpuUnits), a

.fps:
    ld hl, fpsTimer
    dec (hl)
    ret nz
    ld (hl), 60
    ld a, (lateCount)
    ld b, a
    ld a, 60
    sub b
    jr nc, .fpsok
    xor a
.fpsok:
    ld (fpsVal), a
    call ByteToDigits
    ld a, d
    ld (fpsTens), a
    ld a, e
    ld (fpsUnits), a
    xor a
    ld (lateCount), a
    ret

;-----------------------------------------------------------------------------
; 두 표시가 나란히 있고 평소에는 둘 다 60이라 그냥 두면 구분이 안 된다.
; 색으로 구분하면 스프라이트를 더 쓰지 않고도 값까지 함께 전달된다.
; 흰색은 정상, 주황은 빠듯함, 빨강은 문제 있음을 뜻한다.
; 
;-----------------------------------------------------------------------------
UpdateHudColours:
    ld a, (cpuPct)
    cp 90
    ld b, 11                    ; 빨강 - 곧 프레임을 놓친다
    jr nc, .cpuset
    cp 70
    ld b, 6                     ; 주황 - 여유가 얼마 없다
    jr nc, .cpuset
    ld b, 3                     ; 하늘색 - 정상. 옆의 fps 표시와
                                ; 절대 같은 색이 되지 않도록 고른 색이다
.cpuset:
    ld a, (cpuColour)
    cp b
    jr z, .fps
    ld a, b
    ld (cpuColour), a
    ld a, SLOT_CLABEL           ; 라벨과 숫자 두 자리는 슬롯이 연속이다
    call PaintReadout

.fps:
    ld a, (fpsVal)
    cp 60
    ld b, 4                     ; 흰색 - 모든 프레임이 제때 끝났다
    jr nc, .fpsset
    ld b, 11                    ; 빨강 - 프레임을 놓쳤다
.fpsset:
    ld a, (fpsColour)
    cp b
    ret z
    ld a, b
    ld (fpsColour), a
    ld a, SLOT_FLABEL
    ; 아래로 이어짐

; A = 첫 슬롯, B = 색. 계측 표시의 라벨과 숫자 두 자리를 칠한다.
PaintReadout:
    ld c, 3
.loop:
    push bc
    push af
    call FillSlotColour
    pop af
    pop bc
    inc a
    dec c
    jr nz, .loop
    ret

; A = 0..99 -> D = 십의 자리, E = 일의 자리
ByteToDigits:
    ld d, 0
.loop:
    cp 10
    jr c, .done
    sub 10
    inc d
    jr .loop
.done:
    ld e, a
    ret

; HL = VRAM 주소. 쓰기 모드로 설정한다. HL은 보존, A와 C는 파괴.
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
    include "src/gfxdata.asm"

    SAVEBIN "build/game.rom", 0x4000, 0x4000
