;-----------------------------------------------------------------------------
; quest2 - 회전을 부드럽게 하는 시험 (quest.rom 의 실제 렌더러를 그대로 쓴다)
;
; 첫 판은 매 프레임 진짜 광선을 쏘는, quest.rom 과 완전히 다른 프로그램이었다.
; 둘째 판은 반성해서 RenderDungeon 을 그대로 가져다 쓰고 두 baked 그림 사이를
; 화면에서 밀어 넣는 "wipe" 로 부드러움을 흉내 냈는데, 그건 회전이 아니라
; 옆으로 미는 화면 전환일 뿐이었다 - 카메라가 실제로 도는 중간 각도가 화면에
; 하나도 없었다.
;
; 이번 판은 둘을 합친다.
;
;   - **가만히 있거나 이동했을 때**: quest.asm 의 RenderDungeon 을 한 글자도
;     안 바꾸고 그대로 쓴다. 벽 그림, 원근, 통로 판정 전부 quest.rom 그대로다.
;     questconst.asm/questdata.asm 도 그대로 include 한다.
;
;   - **90도 도는 중간의 8프레임만**: 진짜로 광선을 쏜다. 그 각도는 카디널
;     4방향 사이라서 애초에 구워 둘 수 없기 때문이다(quest.rom 의 벽 모양이
;     상수인 것은 "칸 단위 + 90도 회전"일 때뿐이다 - 중간 각도에서는 상수가
;     아니다). 이 8프레임은 텍스처 없이 3단계 명암만 쓴다 - 시간이 없어서다.
;     회전이 끝나면 정확히 카디널 각도로 떨어지고, 그 마지막 한 장은 다시
;     RenderDungeon(구운 렌더러)으로 그려서 텍스처가 있는 정확한 그림으로
;     마무리한다.
;
; 8프레임(11.25도씩)인 이유는 gfx/quest2_gen.py 의 TURN_STEP 주석 참고 -
; 256(2의 거듭제곱) 안에서 "10도"에 가장 가까운, 곱셈 없이 표를 바로 찾을 수
; 있는 값이다.
;-----------------------------------------------------------------------------

    DEVICE NOSLOT64K

    include "src/questconst.asm"

;--- 입출력 포트 ---------------------------------------------------------------
VDP_DATA    equ 0x98
VDP_ADDR    equ 0x99
VDP_PAL     equ 0x9A
PPI_ROW     equ 0xAA
PPI_COL     equ 0xA9

;--- 키 (8행: bit7 오른쪽, bit6 아래, bit5 위, bit4 왼쪽) ----------------------
KEY_RIGHT   equ 7
KEY_DOWN    equ 6
KEY_UP      equ 5
KEY_LEFT    equ 4

MAP_W       equ 16
BLACK_BYTE  equ COL_BLACK * 17

;--- 작업용 RAM ----------------------------------------------------------------
    ORG 0xC000
RamStart:
Vars:
posX        ds 1
posY        ds 1
facing      ds 1                ; 0=북 1=동 2=남 3=서 - 카디널일 때만 뜻이 있다
keyState    ds 1
prevKey     ds 1
needDraw    ds 1
curY        ds 1
addrOk      ds 1
resumeX     ds 1
blockDepth  ds 1
frontH      ds 1
frontX      ds 1
frontW      ds 1
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

    ORG 0xC100

; 회전 애니메이션용
turnAngle   ds 1                ; 0~255. 회전 중에만 뜻이 있다.
turnDir     ds 1                ; +1 오른쪽 / -1 왼쪽 (부호 있는 바이트)
turnFramesLeft ds 1              ; 0 이면 회전 중이 아니다

; 광선 계산용 임시 (회전 중에만 쓴다)
RayOX       ds 2                ; 광선들의 시작점 (Q8.8, 칸 한가운데)
RayOY       ds 2
RayAngle    ds 1                ; 지금 쏘는 열의 각도
StepXVal    ds 1
StepYVal    ds 1
RayPX       ds 2                ; 지금 광선이 행진 중인 위치
RayPY       ds 2
RayStep     ds 1
PrevCellX   ds 1                ; 마지막으로 서 있던(통로) 칸 - 벽돌 무늬 방향 판정용
PrevCellY   ds 1
ColCount    ds 1
ColPtr      ds 2
ColHeight   ds 1
ColColor    ds 1
ColTop      ds 1
ColU        ds 1                ; 벽에서 가로 texel 좌표 (0~15)
WallRow     ds 1                ; 벽 안에서 몇 번째 줄인지 (0부터, 세로 texel 은 &15)
WallPtr     ds 2                ; 벽 채우기 중 지금 쓸 자리

; 작업 버퍼. 열(광선) 하나가 세로로 이어진 96바이트, 줄 하나가 48바이트다.
; VRAM 은 줄 단위로만 주소가 이어지는데 광선은 열 단위로 채워야 해서, 램에
; 다 채운 뒤 한 번에 옮긴다(BlitFrame).
RayBuf      ds (VIEW_W / 2) * VIEW_H     ; 48 * 96 = 4608
BlitSrc     ds 2
BlitRow     ds 1
BlitRowsLeft ds 1
; 면 상태 표. 면 번호로 바로 짚을 수 있게 페이지 머리에 둔다. VisPost 는 Vis 의
; 바로 다음 페이지라 inc d 한 번으로 옮겨 간다. (quest.asm 과 같은 구조인데,
; 여기는 RayBuf 가 0xC500 을 차지하고 있어서 그 뒤에 둔다.)
    ORG 0xD400
Vis         ds 64
    ORG 0xD500
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
    call SelectPage2

    call InitVdp
    call UploadPalette
    call UnpackBg

    ld hl, RamStart
    ld de, RamStart + 1
    ld bc, RamEnd - RamStart - 1
    ld (hl), 0
    ldir

    ld a, 1                      ; 시작 위치 - quest.rom 과 같은 자리
    ld (posX), a
    ld a, 13
    ld (posY), a
    ld a, 1
    ld (needDraw), a

    ld a, 0x40
    ld c, 1
    call WriteVdpReg

;-----------------------------------------------------------------------------
; 메인 루프
;
; 회전 중(turnFramesLeft>0)이면 매 프레임 각도를 한 걸음 밀고 그 각도로 광선을
; 쏜다. 마지막 걸음에서 facing 을 새 카디널로 맞추고, 구운 렌더러로 한 번 더
; 그려서 텍스처가 있는 정확한 그림으로 마무리한다. 회전 중이 아니면 여느
; quest.rom 처럼 필요할 때만 통째로 다시 그린다.
;-----------------------------------------------------------------------------
MainLoop:
    call WaitVBlank

    ld a, (turnFramesLeft)
    or a
    jr z, .checkdraw

    ld a, (turnDir)
    bit 7, a
    jr nz, .turnleft
    ld a, (turnAngle)
    add a, TURN_STEP
    jr .gotangle
.turnleft:
    ld a, (turnAngle)
    sub TURN_STEP
.gotangle:
    ld (turnAngle), a
    call RayCastFrame
    call BlitFrame

    ld a, (turnFramesLeft)
    dec a
    ld (turnFramesLeft), a
    jr nz, .input

    ld a, (turnDir)               ; 다 돌았다 - facing 을 새 카디널로 맞춘다
    bit 7, a
    jr nz, .factleft
    ld a, (facing)
    inc a
    and 3
    ld (facing), a
    jr .factdone
.factleft:
    ld a, (facing)
    dec a
    and 3
    ld (facing), a
.factdone:
    call RenderDungeon             ; 구운 렌더러로 마지막 한 장 - 텍스처 있는
    jr .input                      ; 정확한 그림으로 마무리한다

.checkdraw:
    ld a, (needDraw)
    or a
    jr z, .input
    xor a
    ld (needDraw), a
    call RenderDungeon

.input:
    call ReadInput
    call HandleInput
    jr MainLoop

;-----------------------------------------------------------------------------
; 입력
;
; 회전 중에는 새 입력을 받지 않는다. 왼쪽/오른쪽은 이제 즉시 다시 그리는 대신
; 회전 애니메이션을 시작한다. 위/아래는 quest.rom 과 완전히 같다 - 칸 단위
; 즉시 이동.
;-----------------------------------------------------------------------------
ReadInput:
    in a, (PPI_ROW)
    and 0xF0
    or 8
    out (PPI_ROW), a
    in a, (PPI_COL)
    cpl
    ld (keyState), a
    ret

HandleInput:
    ld a, (keyState)
    ld b, a
    ld a, (prevKey)
    cpl
    and b
    ld c, a
    ld a, b
    ld (prevKey), a

    ld a, (turnFramesLeft)
    or a
    ret nz                        ; 회전 중이면 아무 것도 받지 않는다

    bit KEY_LEFT, c
    jr z, .noleft
    ld a, -1
    ld (turnDir), a
    jr .starttturn
.noleft:
    bit KEY_RIGHT, c
    jr z, .noright
    ld a, 1
    ld (turnDir), a
    jr .starttturn
.noright:
    bit KEY_UP, c
    jr z, .nofwd
    ld a, 1
    call CellAhead
    call IsWall
    ret nz
    ld a, d
    ld (posX), a
    ld a, e
    ld (posY), a
    ld a, 1
    ld (needDraw), a
    ret
.nofwd:
    bit KEY_DOWN, c
    ret z
    ld a, (facing)
    push af
    add a, 2
    and 3
    ld (facing), a
    ld a, 1
    call CellAhead
    pop af
    ld (facing), a
    call IsWall
    ret nz
    ld a, d
    ld (posX), a
    ld a, e
    ld (posY), a
    ld a, 1
    ld (needDraw), a
    ret

.starttturn:
    ld a, (facing)                ; 지금 카디널 각도에서 시작한다
    add a, a
    add a, a
    add a, a
    add a, a
    add a, a
    add a, a                      ; facing * 64
    ld (turnAngle), a
    ld a, QUARTER / TURN_STEP
    ld (turnFramesLeft), a
    ret

;-----------------------------------------------------------------------------
; 회전 중간 각도 한 프레임을 쏜다. quest.rom 에 없던, 이 판에만 있는 코드다.
;
; 광선 48개(뷰포트 96픽셀 / 2). 열 c(0~47)의 각도는 (turnAngle-24+c) - 뺄셈
; 한 번 하고 나면 열마다 1씩 더하기만 하면 된다(각도 표가 256바이트 페이지에
; 맞춰 있어서 덧셈도 없이 다음 바이트를 보면 된다).
;
; 한 걸음 = 1/8칸을 (StepXTable[각도], StepYTable[각도])만큼 더해 가며 최대
; MAXSTEPS(120, = 15칸)번 걷는다. 벽이면(MapData - questdata.asm, quest.asm
; 과 같은 지도다) 멈추고, 걸은 수로 높이와 밝기를 표에서 바로 찾는다.
;-----------------------------------------------------------------------------
RayCastFrame:
    ld a, (posX)
    ld h, a
    ld l, 128                    ; 칸 한가운데 (+0.5칸, Q8.8)
    ld (RayOX), hl
    ld a, (posY)
    ld h, a
    ld l, 128
    ld (RayOY), hl

    ld a, (turnAngle)
    sub 24
    ld (RayAngle), a

    ld hl, RayBuf
    ld (ColPtr), hl
    ld a, 48
    ld (ColCount), a

.col:
    ld a, (RayAngle)              ; --- 이 열의 방향 ---
    ld l, a
    ld h, StepXTable >> 8
    ld a, (hl)
    ld (StepXVal), a
    ld h, StepYTable >> 8
    ld a, (hl)
    ld (StepYVal), a

    ld hl, (RayOX)                ; --- 내 칸 한가운데서 다시 시작 ---
    ld (RayPX), hl
    ld hl, (RayOY)
    ld (RayPY), hl
    xor a
    ld (RayStep), a
    ld a, (posX)                  ; 벽돌 방향 판정의 시작점 - 내가 선 칸
    ld (PrevCellX), a
    ld a, (posY)
    ld (PrevCellY), a

.march:
    ld a, (StepXVal)              ; RayPX += 부호 확장한 StepXVal
    ld e, a
    ld d, 0
    bit 7, e
    jr z, .sx1
    ld d, 0xFF
.sx1:
    ld hl, (RayPX)
    add hl, de
    ld (RayPX), hl

    ld a, (StepYVal)
    ld e, a
    ld d, 0
    bit 7, e
    jr z, .sy1
    ld d, 0xFF
.sy1:
    ld hl, (RayPY)
    add hl, de
    ld (RayPY), hl

    ld a, (RayStep)
    inc a
    ld (RayStep), a
    cp MAXSTEPS + 1
    jr nc, .hit                   ; 너무 멀다 - 못 만난 것으로 치고 멈춘다

    ld hl, (RayPX)                ; 정수 칸 번호 = Q8.8 의 상위 바이트 그대로
    ld d, h
    ld hl, (RayPY)
    ld e, h
    ld a, d
    cp MAP_W
    jr nc, .hit                   ; 맵 밖 (음수도 부호 없는 비교라 여기 걸린다)
    ld a, e
    cp MAP_W
    jr nc, .hit
    ld a, e
    add a, a
    add a, a
    add a, a
    add a, a                      ; y*16
    add a, d
    ld l, a
    ld h, 0
    ld bc, MapData
    add hl, bc
    ld a, (hl)
    or a
    jr nz, .hit                   ; 벽 - D,E 가 그 칸이다
    ld a, d                       ; 통로 - "마지막으로 서 있던 칸"을 갱신하고 계속
    ld (PrevCellX), a
    ld a, e
    ld (PrevCellY), a
    jp .march

.hit:
    ; --- 벽돌이 어느 쪽으로 이어지는지: 칸이 가로(X)로 바뀌며 부딪혔으면
    ; 세로 벽(동/서쪽 면)이라 벽을 따라가는 좌표는 y 이고, 세로(Y)로 바뀌며
    ; 부딪혔으면 벽을 따라가는 좌표는 x 다. Q8.8 의 낮은 바이트가 그 칸 안에서
    ; 0~255 로 재는 소수부라서, 위 4비트만 떼면 0~15 texel 좌표가 된다.
    ld a, d
    ld hl, PrevCellX
    cp (hl)
    jr nz, .xcross
    ld a, (RayPX)
    jr .gotu
.xcross:
    ld a, (RayPY)
.gotu:
    and 0xF0
    rrca
    rrca
    rrca
    rrca
    ld (ColU), a

    ld a, (RayStep)
    cp MAXSTEPS + 1
    jr c, .gotstep
    ld a, MAXSTEPS
.gotstep:
    ld l, a
    ld h, HeightTable >> 8
    ld a, (hl)
    ld (ColHeight), a
    ld h, ColorTable >> 8
    ld a, (hl)
    ld (ColColor), a

    ; --- 채우기: 천장 -> 벽 -> 바닥. 세 구간을 한 포인터로 이어서 돈다 ---
    ld hl, (ColPtr)
    ld de, 48

    ld a, (ColHeight)
    srl a
    ld b, a                       ; b = height/2
    ld a, HALF_H
    sub b
    ld (ColTop), a                ; top = HALF_H - height/2 (천장 줄 수)
    or a
    jr z, .noceil
    ld b, a
.ceilloop:
    ld (hl), COL_CEIL_B
    add hl, de
    djnz .ceilloop
.noceil:

    ; 벽만 벽돌 무늬를 넣는다(천장/바닥은 그대로 납작한 색). 줄마다 타일에서
    ; (v=WallRow&15, u=ColU) 칸을 보고 벽돌이면 거리색을, 줄눈이면 고정된
    ; 어두운 색을 쓴다. HL 을 세 구간에 걸쳐 이어 쓰던 것과 달리 여기서는
    ; 타일을 보는 동안 HL 을 다른 용도로 써야 해서 WallPtr 에 잠깐 맡겨 둔다.
    ld (WallPtr), hl
    xor a
    ld (WallRow), a
    ld a, (ColHeight)              ; 벽은 항상 1줄 이상이다 (표가 최소 1 을 보장)
    ld b, a
.wallloop:
    ld a, (WallRow)
    and TILE_MASK
    add a, a
    add a, a
    add a, a
    add a, a                      ; v*16
    ld c, a
    ld a, (ColU)
    add a, c
    ld l, a
    ld h, Tile >> 8
    ld a, (hl)                    ; 1=벽돌 0=줄눈
    ld c, a
    ld hl, (WallPtr)
    ld a, c
    or a
    jr nz, .brick
    ld a, MORTAR_BYTE
    jr .wallput
.brick:
    ld a, (ColColor)
.wallput:
    ld (hl), a
    add hl, de
    ld (WallPtr), hl
    ld a, (WallRow)
    inc a
    ld (WallRow), a
    djnz .wallloop
    ld hl, (WallPtr)              ; 바닥 채우기가 이어받을 자리

    ld a, 96                       ; 바닥 줄 수 = 96 - top - height
    ld c, a
    ld a, (ColTop)
    ld b, a
    ld a, c
    sub b
    ld c, a
    ld a, (ColHeight)
    ld b, a
    ld a, c
    sub b
    or a
    jr z, .nofloor
    ld b, a
.floorloop:
    ld (hl), COL_FLOOR_B
    add hl, de
    djnz .floorloop
.nofloor:

    ld hl, (ColPtr)                ; --- 다음 열 ---
    inc hl
    ld (ColPtr), hl
    ld a, (RayAngle)
    inc a
    ld (RayAngle), a
    ld a, (ColCount)
    dec a
    ld (ColCount), a
    jp nz, .col
    ret

;-----------------------------------------------------------------------------
; 작업 버퍼를 VRAM 으로 옮긴다. 버퍼가 이미 화면과 같은 순서(줄마다 48바이트)로
; 채워져 있어서, 줄마다 주소를 잡고 그대로 쏟아붓기만 하면 된다.
;-----------------------------------------------------------------------------
BlitFrame:
    ld hl, RayBuf
    ld (BlitSrc), hl
    ld a, VIEW_Y
    ld (BlitRow), a
    ld a, VIEW_H
    ld (BlitRowsLeft), a

.rows:
    ld a, (BlitRow)
    ld e, VIEW_X / 2
    call RowAddrB
    call SetVramWrite

    ld hl, (BlitSrc)
    ld b, 48
    ld c, VDP_DATA
.cols:
    outi                          ; 16
    nop                           ;  4
    jp nz, .cols                  ; 10  -> 30 T-state
    ld (BlitSrc), hl

    ld a, (BlitRow)
    inc a
    ld (BlitRow), a
    ld a, (BlitRowsLeft)
    dec a
    ld (BlitRowsLeft), a
    jr nz, .rows
    ret

; A = 절대 화면 y(0~211), E = 바이트 x. HL = VRAM 주소.
RowAddrB:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                    ; y*128
    ld a, e
    add a, l
    ld l, a
    ret nc
    inc h
    ret

;-----------------------------------------------------------------------------
; 던전 그리기 - quest.asm 의 RenderDungeon 을 그대로 옮겼다. 한 글자도
; 안 바뀌었다.
;-----------------------------------------------------------------------------
RenderDungeon:
    call BuildVisibility
    ld hl, RunData
    ld a, VIEW_Y
    ld (curY), a
.line:
    call LineAddr
    ld c, VDP_DATA
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
;-----------------------------------------------------------------------------
DrawFront:
    ld a, (blockDepth)
    cp MAXD + 1
    ret nc

    call FrontPtr
    ld a, (hl)
    inc hl
    ld (curY), a
    ld a, (hl)
    inc hl
    ld (frontH), a
    ld a, (hl)
    inc hl
    ld (frontX), a
    ld a, (hl)
    inc hl
    ld (frontW), a
.line:
    push hl
    ld a, (curY)
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

; 줄 첫 런의 주소.
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
; 면 상태 정하기 - quest.asm 과 완전히 같다.
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
    push bc
    ld b, a
    ld a, (facing)
    add a, a
    ld l, a
    ld h, 0
    ld de, DirTab
    add hl, de
    ld d, (hl)
    inc hl
    ld e, (hl)
    ld a, (posX)
    ld c, b
.lx:
    add a, d
    dec c
    jr nz, .lx
    ld d, a
    ld a, (posY)
    ld c, b
.ly:
    add a, e
    dec c
    jr nz, .ly
    ld e, a
    pop bc
    ret

IsWall:
    push bc
    ld a, d
    cp MAP_W
    jr nc, .solid
    ld a, e
    cp MAP_W
    jr nc, .solid
    ld a, e
    add a, a
    add a, a
    add a, a
    add a, a
    add a, d
    ld l, a
    ld h, 0
    ld bc, MapData
    add hl, bc
    ld a, (hl)
    or a
    pop bc
    ret
.solid:
    ld a, 1
    or a
    pop bc
    ret

DirTab:
    db  0, -1
    db  1,  0
    db  0,  1
    db -1,  0

;-----------------------------------------------------------------------------
; VDP 기본 루틴 - quest.asm 과 같다.
;-----------------------------------------------------------------------------
SelectPage2:
    in a, (0xA8)
    ld b, a
    and 0x0C
    rlca
    rlca
    ld c, a
    ld a, b
    and 0xCF
    or c
    out (0xA8), a
    ret

WaitVBlank:
    in a, (VDP_ADDR)
    and 0x80
    jr z, WaitVBlank
    ret

; HL = VRAM 주소. 쓰기 모드로 설정한다. HL 보존, A 와 C 파괴.
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
    db 0x06
    db 0x00
    db 0x1F
    db 0xFF
    db 0x03
    db 0x00
    db 0x00
    db 0x00
    db 0x0A
    db 0x80
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
    db 0x00
VdpRegsEnd:

UploadPalette:
    xor a
    ld c, 16
    call WriteVdpReg
    ld hl, PaletteData
    ld b, 32
.loop:
    ld a, (hl)
    inc hl
    out (VDP_PAL), a
    nop
    djnz .loop
    ret

UnpackBg:
    ld hl, 0
    call SetVramWrite
    ld hl, BgRle
.loop:
    ld a, (hl)
    inc hl
    bit 7, a
    jr z, .literal
    and 0x7F
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
    ld b, a
    inc b
.lit:
    ld a, (hl)
    inc hl
    out (VDP_DATA), a
    djnz .lit
.more:
    ld a, h
    cp BgRleEnd >> 8
    jr nz, .loop
    ld a, l
    cp BgRleEnd & 0xFF
    jr nz, .loop
    ret

;-----------------------------------------------------------------------------
    include "src/questdata.asm"
    include "src/questbg.asm"       ; quest.rom 은 이것만 따로 뱅크에 두지만
    include "src/quest2data.asm"    ; 여기는 32KB 한 덩어리라 그냥 넣는다

    ; 32KB 롬은 매퍼가 없다 - 칩 하나가 페이지 1(0x4000-0x7FFF)과 페이지
    ; 2(0x8000-0xBFFF)에 그대로 이어져 걸린다(SelectPage2 가 페이지 2 의
    ; 슬롯을 맞춰 준다). 그래서 어셈블 주소도 0xBFFF 까지 이어서 채운다.
    ds 0xC000 - $, 0xFF
    SAVEBIN "build/quest2.rom", 0x4000, 0x8000
