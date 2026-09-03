;-----------------------------------------------------------------------------
; 대열 - 무리를 여러 마리로 보여 주고, 칠 상대를 고르게 한다 (SCREEN 8 전용)
;
; 예전에는 무리가 몇 마리든 던전 창 한가운데에 그림 **한 장**을 놓았다. 셋이
; 나와도 화면은 한 마리였고, "GOBLIN 2 를 쳤다" 는 기록만으로 짐작해야 했다.
;
; 이제 n 마리가 나오면 한 마리를 VIEW_W/n 폭으로 줄여 나란히 놓는다. 줄인
; 그림은 실행 중에 만들지 않고 gfx/quest_sprite.py 가 미리 구워 둔다 - 원본이
; 64x64 라 파이썬에서 줄이면 곱게 줄고, Z80 은 늘 하던 대로 찍기만 하면 된다.
; MonSprTab 이 (종류, 마릿수) -> (뱅크, 주소) 를 준다.
;
; **칸은 무리가 만들어질 때 정해지고 끝까지 그대로다.** 죽은 놈의 자리는 비워
; 두고 뒤엣것을 당겨오지 않는다. 당겨오면 기록창의 "GOBLIN 3" 이 가리키는 칸이
; 라운드마다 달라져서 어느 놈을 쳤는지 알 수 없게 된다. MsgAddMonName 은 칸
; 번호 + 1 을 찍고 여기도 칸 번호대로 놓으므로, 둘이 늘 같은 것을 가리킨다.
;
; 화살표는 고른 놈 머리 위에 찍는다. 옮길 때마다 던전을 다시 그리면 느리므로,
; 화살표가 지나다니는 띠(VIEW_W x ARROW_H)를 처음에 화면 밖 VRAM 으로 옮겨 두고
; 옮길 때마다 되돌린다. HMMM 두 번이라 눈에 안 띈다.
;-----------------------------------------------------------------------------

ARROW_W     equ 12
ARROW_H     equ 6
ARROW_GAP   equ 2               ; 화살표 끝과 머리 사이
ARROW_COL   equ 0xFC            ; GRB332 로 노랑 (G 7, R 7, B 0). 던전에 없는 색이다.

; 화살표 밑그림을 옮겨 둘 화면 밖 VRAM 의 줄 번호.
; 정면 벽 픽셀(FRONT_VY 부터 FRONT_PIX_LEN 바이트) 뒤에 두어야 한다.
SAVE_VY     equ 300
    ASSERT SAVE_VY >= FRONT_VY + (FRONT_PIX_LEN + VRAM_ROW - 1) / VRAM_ROW
    ASSERT MON_SCALE_N <= MON_N
    ASSERT ARROW_W <= VIEW_W / MON_SCALE_N

;-----------------------------------------------------------------------------
; 이번 무리를 몇 칸으로 세울지 정한다. A = 칸 수, MonRowW = 한 칸의 폭.
;
; 값이 깨져 칸 수가 표 밖으로 나가면 한 마리로 본다. 그래야 없는 크기의 그림을
; 찾지 않는다.
;-----------------------------------------------------------------------------
MonRowSize:
    ld a, (MonCount)
    or a
    jr z, .one
    cp MON_SCALE_N + 1
    jr c, .ok
.one:
    ld a, 1
.ok:
    ld c, a                     ; C = 칸 수
    dec a
    ld hl, MonSprW
    call AddA
    ld a, (hl)
    ld (MonRowW), a
    ld a, c
    ret

;-----------------------------------------------------------------------------
; A = 칸 수. 그 크기의 그림을 0xA000 창에 걸고 HL 에 자료 첫 주소를 준다.
; 색인은 종류 * MON_SCALE_N + (칸 수 - 1) 이고 한 칸이 MON_SCALE_ST 바이트다.
;-----------------------------------------------------------------------------
MonSprPtr:
    dec a
    ld c, a
    ld a, (MonKind)
    ld h, a
    ld e, MON_SCALE_N * MON_SCALE_ST
    call Mult8
    ld a, c                     ; + (칸 수 - 1) * 3
    add a, a
    add a, c
    call AddA
    ld de, MonSprTab
    add hl, de
    ld a, (hl)
    ld (ASC8_P3), a             ; 그림이 든 뱅크를 창에 건다
    inc hl
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ret

;-----------------------------------------------------------------------------
; 무리를 통째로 찍는다. 던전을 먼저 그린 뒤에 부른다.
;-----------------------------------------------------------------------------
DrawMonsterRow:
    ld a, (MonKind)
    cp MONSTER_N                ; 종류가 표 밖이면 아무것도 안 그린다
    ret nc
    call MonRowSize
    ld (MonRowN), a
    call MonSprPtr
    ld (MonRowPtr), hl

    ld a, VIEW_H                ; 세로는 가운데 - 정면에서 눈높이에 선다.
    ld hl, MonRowW              ; 바닥에 붙이면 넷일 때 발치에 몰려 보인다.
    sub (hl)
    srl a
    add a, VIEW_Y
    ld (MonRowY), a

    ld a, VIEW_X
    ld (MonRowX), a
    xor a
    ld (MonRowI), a
.each:
    ld a, (MonRowI)
    call MonPtr
    inc hl                      ; M_HP - 쓰러진 놈은 자리만 비워 둔다
    ld a, (hl)
    or a
    call nz, DrawOneMon
    ld a, (MonRowX)
    ld hl, MonRowW
    add a, (hl)
    ld (MonRowX), a
    ld hl, MonRowI
    inc (hl)
    ld a, (MonRowN)
    cp (hl)
    jr nz, .each

    ld a, SPR_FIRSTBK           ; 창을 기본 뱅크로 되돌린다
    ld (ASC8_P3), a
    ret

;-----------------------------------------------------------------------------
; MonRowPtr 의 그림을 (MonRowX, MonRowY) 에 MonRowW 칸으로 찍는다.
;
; 자료는 questmon.asm 의 DrawMonsterPic 과 같은 꼴이다 - 줄마다
; (건너뛸 바이트, 그릴 바이트, 픽셀...) 을 잇고 0xFF 로 끝난다. 다른 것은 놓는
; 자리와 크기를 밖에서 받는다는 것뿐이다.
;-----------------------------------------------------------------------------
DrawOneMon:
    ld hl, (MonRowPtr)
    ld a, (MonRowY)
    ld (SprY), a
    ld a, (MonRowW)
    ld (SprRows), a
.row:
    xor a
    ld (SprCol), a
.run:
    ld a, (hl)                  ; 건너뛸 바이트
    inc hl
    cp 0xFF
    jr z, .eol
    ld e, a
    ld a, (SprCol)
    add a, e
    ld (SprCol), a
    ld a, (hl)                  ; 그릴 바이트 수
    inc hl
    or a
    jr z, .eol                  ; 0 은 줄 끝으로 본다 (questmon.asm 참고)
    ld (SprLen), a

    push hl                     ; 자료 포인터를 지킨다
    ld a, (SprCol)
    ld hl, MonRowX
    add a, (hl)
    ld e, a
    ld a, (SprY)
    call RowAddrB
    call SetVramWrite
    pop hl

    ld a, (SprLen)
    ld b, a
    ld c, VDP_DATA
.blit:
    outi                        ; 16
    nop                         ;  4
    jp nz, .blit                ; 10  -> 30 T-state

    ld a, (SprLen)              ; 다음 런의 건너뛰기는 여기서부터
    ld b, a
    ld a, (SprCol)
    add a, b
    ld (SprCol), a
    jr .run
.eol:
    ld a, (SprY)
    inc a
    ld (SprY), a
    ld a, (SprRows)
    dec a
    ld (SprRows), a
    jr nz, .row
    ret

;=============================================================================
; 화살표
;=============================================================================

; 화살표가 지나다닐 줄을 정한다. 대열 위 ARROW_GAP 만큼 띄운 자리다.
ArrowSetup:
    call MonRowSize
    ld a, VIEW_H
    ld hl, MonRowW
    sub (hl)
    srl a
    add a, VIEW_Y
    sub ARROW_GAP + ARROW_H
    ld (ArrowY), a
    ret

;-----------------------------------------------------------------------------
; A = 칸 번호. 그 칸 위에 아래를 가리키는 삼각형을 찍는다.
; 줄마다 양쪽에서 한 픽셀씩 좁아진다 (12, 10, 8, 6, 4, 2).
;-----------------------------------------------------------------------------
DrawArrow:
    ld h, a
    ld a, (MonRowW)
    ld e, a
    call Mult8                  ; HL = 칸 번호 * 칸 폭
    ld a, (MonRowW)
    sub ARROW_W
    srl a                       ; 칸 안에서 가운데로
    add a, l
    add a, VIEW_X
    ld (ArrowX), a
    ld a, (ArrowY)
    ld (SprY), a
    ld b, ARROW_H
    ld c, 0                     ; 이 줄의 들여쓰기
.row:
    push bc
    ld a, (ArrowX)
    add a, c
    ld e, a
    ld a, (SprY)
    call RowAddrB
    call SetVramWrite
    pop bc
    push bc
    ld a, ARROW_W
    sub c
    sub c
    ld b, a                     ; B = 이 줄의 픽셀 수
    ld c, VDP_DATA
    ld a, ARROW_COL
.pix:
    out (c), a                  ; 14
    nop                         ;  5
    djnz .pix                   ; 14  -> 33 T-state
    pop bc
    ld a, (SprY)
    inc a
    ld (SprY), a
    inc c
    djnz .row
    ret

;-----------------------------------------------------------------------------
; 화살표가 지나다니는 띠를 화면 밖으로 옮겨 두고(BandSave), 되돌린다(BandRestore).
;
; 띠의 y 만 무리 크기에 따라 달라지므로, 틀을 RAM 으로 옮기고 그 자리에만 넣는다.
;-----------------------------------------------------------------------------
BandSave:
    ld hl, CmdBandSave
    ld a, 2                     ; SY 자리
    jr SendBandCmd
BandRestore:
    ld hl, CmdBandRestore
    ld a, 6                     ; DY 자리

; HL = 명령 틀, A = ArrowY 를 넣을 바이트 자리.
;
; **보내고 끝날 때까지 기다린다.** SendVdpCmd 는 보내기 전에만 기다리므로, 바로
; 돌아오면 명령 엔진이 아직 도는 중에 Z80 이 같은 VRAM 에 화살표를 찍게 된다.
;
; 빼고 재 봤다. 화살표를 한 칸 옮긴 뒤 화면의 노란 픽셀이 42 개가 아니라 32 개
; 였다 - 새 삼각형은 맨 윗줄 열두 개만 남고, 옛 삼각형은 위 두 줄만 지워진 채
; 아랫줄 넷이 그대로 있었다. 되돌리기가 도는 도중에 새 삼각형을 찍은 것이다.
SendBandCmd:
    push af
    ld de, CmdBuf
    ld bc, 15
    ldir
    pop af
    ld hl, CmdBuf
    call AddA
    ld a, (ArrowY)
    ld (hl), a
    inc hl
    ld (hl), 0                  ; y 는 화면 안이라 상위 바이트는 늘 0
    ld a, 32
    ld (CmdFirst), a
    ld hl, CmdBuf
    ld b, 15
    call SendVdpCmd
    jp WaitVdpCmd

;-----------------------------------------------------------------------------
; 칠 상대를 고른다. A = 몬스터 번호, 살아 있는 것이 없으면 캐리.
;
; 살아 있는 것이 하나뿐이면 묻지 않는다 - 고를 것이 없는데 스페이스를 한 번 더
; 누르게 하면 번거롭기만 하다.
;
; 새로 눌린 키만 본다. 명령 메뉴에서 결정한 스페이스가 여기까지 흘러들면 첫
; 칸이 저절로 골라진다 - AskCommand 가 prevKey 를 남겨 두므로 그 스페이스는
; 여기서 "이미 눌려 있던 것" 이 되어 걸러진다.
;-----------------------------------------------------------------------------
PickTarget:
    call CountMonsters
    or a
    jr nz, .some
    scf
    ret
.some:
    cp 2
    jp c, FirstMonster          ; 하나뿐이면 그것으로
    ; 칸 수를 여기서 다시 정한다. NextLiving 은 MonRowN 을 보고 감기는데 그것을
    ; 쓰는 것은 DrawMonsterRow 다. 그리기가 아직 안 돌았으면 지난 판의 값이
    ; 남아 있어, 마지막 칸에 못 가거나 빈 칸에 화살표가 서게 된다. 지금은
    ; StartBattle 이 needDraw 를 세워 두어 늘 먼저 도는데, 그 차례에 기대지
    ; 않는 편이 낫다 - 둘 다 MonCount 에서 같은 순간에 뽑는다.
    call MonRowSize
    ld (MonRowN), a
    call FirstMonster
    ld (MonSel), a
    call ArrowSetup
    call BandSave
    ld a, (MonSel)
    call DrawArrow
.loop:
    call WaitVBlank
    call ReadInput
    ld a, (keyState)            ; 새로 눌린 것만
    ld b, a
    ld a, (prevKey)
    cpl
    and b
    ld c, a
    ld a, b
    ld (prevKey), a

    bit KEY_SPACE, c
    jr nz, .done
    ld a, 1
    bit KEY_RIGHT, c
    jr nz, .move
    ld a, -1
    bit KEY_LEFT, c
    jr z, .loop
.move:
    call NextLiving
    call BandRestore
    ld a, (MonSel)
    call DrawArrow
    jr .loop
.done:
    call BandRestore
    ld a, (MonSel)
    or a                        ; 캐리를 지운다
    ret

;-----------------------------------------------------------------------------
; A = +1 또는 -1. MonSel 을 그 방향으로 옮겨 살아 있는 칸에 세운다.
; **살아 있는 것이 둘 이상일 때만 부른다.** 하나도 없으면 영영 돈다.
;-----------------------------------------------------------------------------
NextLiving:
    ld b, a
    ld a, (MonRowN)
    ld c, a
.step:
    ld a, (MonSel)
    add a, b
    cp c
    jr c, .have
    bit 7, b                    ; 끝을 넘었으면 반대쪽으로 감는다
    jr z, .first
    ld a, c
    dec a
    jr .have
.first:
    xor a
.have:
    ld (MonSel), a
    call MonPtr
    inc hl                      ; M_HP
    ld a, (hl)
    or a
    jr z, .step
    ret

;-----------------------------------------------------------------------------
; 누가 쓰러졌으면 대열을 다시 그린다.
;
; 쓰러진 자리를 지우려면 그 뒤의 던전 그림이 있어야 하는데 우리에게는 없다.
; 그래서 던전부터 다시 그린다. 한 라운드에 몇 번 없는 일이라 값이 싸다.
; 부르는 자리는 BattleRound - DamageMonster 안에서 바로 그리면 프레임 아무
; 데서나 VRAM 을 건드리게 된다.
;-----------------------------------------------------------------------------
MonDiedRedraw:
    ld a, (MonDied)
    or a
    ret z
    xor a
    ld (MonDied), a
    call WaitVBlank             ; 메인 루프와 같은 자리에서 그린다
    call RenderDungeon
    jp DrawMonsterRow

; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
CmdBandSave:                    ; 화면 -> 화면 밖
    dw VIEW_X
    dw 0                        ; SY <- ArrowY
    dw 0
    dw SAVE_VY
    dw VIEW_W
    dw ARROW_H
    db 0
    db 0
    db 0xD0                     ; HMMM

CmdBandRestore:                 ; 화면 밖 -> 화면
    dw 0
    dw SAVE_VY
    dw VIEW_X
    dw 0                        ; DY <- ArrowY
    dw VIEW_W
    dw ARROW_H
    db 0
    db 0
    db 0xD0                     ; HMMM
