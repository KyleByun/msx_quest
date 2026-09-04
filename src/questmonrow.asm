;-----------------------------------------------------------------------------
; 대열 - 무리를 여러 마리로 보여 주고, 칠 상대를 고르게 한다 (SCREEN 8 전용)
;
; 예전에는 무리가 몇 마리든 던전 창 한가운데에 그림 **한 장**을 놓았다. 셋이
; 나와도 화면은 한 마리였고, "GOBLIN 2 를 쳤다" 는 기록만으로 짐작해야 했다.
;
; 이제 n 마리가 나오면 한 마리를 줄여 나란히 놓는다. 넷까지는 한 줄이고 다섯이면
; 한 줄에 19 픽셀이 되어 알아볼 수 없으므로 3 칸 x 2 줄로 세운다.
;
; **배치는 여기서 계산하지 않는다.** gfx/quest_geom.py 의 mon_layout 이 정본이고
; quest_rules.py 가 마릿수별 표(MonSprW / MonColsTab / MonTopTab / MonStepTab)로
; 구워 준다. Z80 은 나눗셈이 비싸기도 하지만, 그보다 그리는 쪽과 고르는 쪽이 각자
; 계산하면 반드시 어긋나기 때문이다.
;
; 줄인 그림도 실행 중에 만들지 않고 미리 구워 둔다 - 원본이 64x64 라 파이썬에서
; 줄이면 곱게 줄고, Z80 은 늘 하던 대로 찍기만 하면 된다. MonSprTab 이
; (종류, 마릿수) -> (뱅크, 주소) 를 준다.
;
; **칸은 무리가 만들어질 때 정해지고 끝까지 그대로다.** 죽은 놈의 자리는 비워
; 두고 뒤엣것을 당겨오지 않는다. 당겨오면 기록창의 "GOBLIN 3" 이 가리키는 칸이
; 라운드마다 달라져서 어느 놈을 쳤는지 알 수 없게 된다. MsgAddMonName 은 칸
; 번호 + 1 을 찍고 여기도 칸 번호대로 놓으므로, 둘이 늘 같은 것을 가리킨다.
;
; 칸마다 종류가 다를 수 있다(층이 깊으면 두 종류가 섞인다). 그래서 그림도 무리의
; MonKind 가 아니라 **그 칸의 M_TYPE** 을 보고 고른다.
;
; 화살표는 고른 놈 머리 위에 찍는다. 옮길 때마다 던전을 다시 그리면 느리므로,
; 화살표가 지나다니는 띠(VIEW_W x ARROW_H)를 화면 밖 VRAM 으로 옮겨 두고 옮길
; 때마다 되돌린다. 두 줄일 때는 줄마다 띠의 y 가 다르므로, 옮기기 전에 **지금
; 떠 둔 띠부터 되돌리고** 새 줄의 띠를 뜬다.
;-----------------------------------------------------------------------------

ARROW_COL   equ 0xFC            ; GRB332 로 노랑 (G 7, R 7, B 0). 던전에 없는 색이다.

; 화살표 밑그림을 옮겨 둘 화면 밖 VRAM 의 줄 번호.
; 정면 벽 픽셀(FRONT_VY 부터 FRONT_PIX_LEN 바이트) 뒤에 두어야 한다.
SAVE_VY     equ 300
    ASSERT SAVE_VY >= FRONT_VY + (FRONT_PIX_LEN + VRAM_ROW - 1) / VRAM_ROW

; 칼질하는 동안 칸을 통째로 떠 둘 자리. 화살표 띠(SAVE_VY, ARROW_H 줄) 뒤에
; 놓는다. 칸은 최대 72x72 이지만 96 까지 잡아 둔다 - mon_layout 이 바뀌어도
; 여기서 걸리지 않게.
SLASH_VY    equ 310
SLASH_MAXW  equ 96
    ASSERT SLASH_VY >= SAVE_VY + ARROW_H
    ASSERT SLASH_VY + SLASH_MAXW <= 512         ; VRAM 128KB = 512 줄
    ASSERT MON_SCALE_N <= MON_N
    ASSERT ARROW_W <= VIEW_W / MON_MAX_COLS

; HL = 표, C = 색인 -> A = 그 바이트. HL, B 파괴.
TabByte:
    ld b, 0
    add hl, bc
    ld a, (hl)
    ret

;-----------------------------------------------------------------------------
; 이번 무리의 배치를 정한다. A = 칸 수.
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
    ld (MonRowN), a
    dec a
    ld c, a                     ; C = 표 색인 (마릿수 - 1)
    ld hl, MonSprW
    call TabByte
    ld (MonRowW), a
    ld hl, MonColsTab
    call TabByte
    ld (MonRowCols), a
    ld hl, MonTopTab
    call TabByte
    ld (MonRowTop), a
    ld hl, MonStepTab
    call TabByte
    ld (MonRowStep), a
    ld hl, MonLeftTab
    call TabByte
    ld (MonRowLeft), a
    ld a, (MonRowN)
    ret

;-----------------------------------------------------------------------------
; A = 칸 번호 -> MonSelCol / MonSelRow.
; 칸 수가 1~4 뿐이라 나눗셈 대신 빼기로 센다.
;-----------------------------------------------------------------------------
SlotColRow:
    ld c, 0
    ld hl, MonRowCols
.div:
    cp (hl)
    jr c, .done
    sub (hl)
    inc c
    jr .div
.done:
    ld (MonSelCol), a
    ld a, c
    ld (MonSelRow), a
    ret

;-----------------------------------------------------------------------------
; MonSelCol / MonSelRow -> MonRowX / MonRowY (그 칸의 왼쪽 위).
;-----------------------------------------------------------------------------
CellXY:
    ld a, (MonRowW)
    ld e, a
    ld a, (MonSelCol)
    ld h, a
    call Mult8                  ; HL = 열 * 폭
    ld a, (MonRowLeft)          ; 칸이 창보다 좁으면(한 마리) 가운데로 밀려 있다
    add a, l
    ld (MonRowX), a
    ld a, (MonRowStep)
    ld e, a
    ld a, (MonSelRow)
    ld h, a
    call Mult8                  ; HL = 줄 * 줄간격
    ld a, (MonRowTop)
    add a, l
    ld (MonRowY), a
    ret

;-----------------------------------------------------------------------------
; A = 종류. 지금 대열 크기에 맞는 그림을 0xA000 창에 걸고 HL 에 준다.
; 색인은 종류 * MON_SCALE_N + (마릿수 - 1), 한 칸이 MON_SCALE_ST 바이트.
;-----------------------------------------------------------------------------
MonSprPtr:
    ld h, a
    ld e, MON_SCALE_N * MON_SCALE_ST
    call Mult8
    ld a, (MonRowN)
    dec a
    ld c, a
    add a, a
    add a, c                    ; * 3
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
    call MonRowSize
    xor a
    ld (MonRowI), a
.each:
    ld a, (MonRowI)
    call MonPtr
    ld a, (hl)                  ; M_TYPE - 칸마다 종류가 다를 수 있다
    inc hl
    ld c, (hl)                  ; M_HP
    inc c
    dec c
    jr z, .skip                 ; 쓰러진 놈은 자리만 비워 둔다
    cp MONSTER_N                ; 종류가 표 밖이면 안 그린다 (값이 깨져도 안전하게)
    jr nc, .skip
    call MonSprPtr
    ld (MonRowPtr), hl
    ld a, (MonRowI)
    call SlotColRow
    call CellXY
    call DrawOneMon
.skip:
    ld hl, MonRowI
    inc (hl)
    ld a, (MonRowN)
    cp (hl)
    jr nz, .each

    ld a, SPR_FIRSTBK           ; 창을 기본 뱅크로 되돌린다
    ld (ASC8_P3), a
    jp DrawAllHpDots            ; 발아래 HP 게이지

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

;-----------------------------------------------------------------------------
; A = 칸 번호. 그 칸 위의 띠를 화면 밖에 떠 두고 삼각형을 찍는다.
;-----------------------------------------------------------------------------
ShowArrow:
    call SlotColRow
    call CellXY                 ; MonRowX/Y = 그 칸의 왼쪽 위
    ld a, (MonRowY)
    sub ARROW_GAP + ARROW_H
    ld (ArrowY), a
    ld a, (MonRowW)             ; 칸 안에서 가운데로
    sub ARROW_W
    srl a
    ld hl, MonRowX
    add a, (hl)
    ld (ArrowX), a
    call BandSave
    ; 이어서 삼각형을 찍는다

;-----------------------------------------------------------------------------
; (ArrowX, ArrowY) 에 아래를 가리키는 삼각형을 찍는다.
; 줄마다 양쪽에서 한 픽셀씩 좁아진다 (12, 10, 8, 6, 4, 2).
;-----------------------------------------------------------------------------
DrawArrowNow:
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
; 띠의 y 만 달라지므로 틀을 RAM 으로 옮기고 그 자리에만 넣는다.
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
; 좌우는 한 칸씩, 상하는 한 줄씩(= 칸 수만큼) 옮긴다. 두 줄일 때 위아래로도
; 고를 수 있어야 하기 때문이다.
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
    ; 배치를 여기서 다시 정한다. NextLiving 은 MonRowN 을 보고 감기는데 그것을
    ; 쓰는 것은 DrawMonsterRow 다. 그리기가 아직 안 돌았으면 지난 판의 값이
    ; 남아 있어, 마지막 칸에 못 가거나 빈 칸에 화살표가 서게 된다. 지금은
    ; StartBattle 이 needDraw 를 세워 두어 늘 먼저 도는데, 그 차례에 기대지
    ; 않는 편이 낫다 - 둘 다 MonCount 에서 같은 순간에 뽑는다.
    call MonRowSize
    call FirstMonster
    ld (MonSel), a
    call ShowArrow
.loop:
    call WaitVBlank
    call PsgTick                ; 상대를 고르는 동안에도 음악이 이어져야 한다
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
    jr nz, .move
    ld a, (MonRowCols)          ; 아래 = 한 줄 아래
    bit KEY_DOWN, c
    jr nz, .move
    ld a, (MonRowCols)
    neg
    bit KEY_UP, c
    jr z, .loop
.move:
    call NextLiving
    call BandRestore            ; **먼저** 지금 떠 둔 띠를 되돌린다
    ld a, (MonSel)
    call ShowArrow              ; 그 다음에 새 줄의 띠를 뜨고 찍는다
    jr .loop
.done:
    call BandRestore
    ld a, (MonSel)
    or a                        ; 캐리를 지운다
    ret

;-----------------------------------------------------------------------------
; A = 걸음(부호 있음, -칸수..+칸수). MonSel 을 그만큼 옮기고, 그 칸이 죽었으면
; **같은 방향으로** 한 칸씩 더 가서 살아 있는 칸에 선다.
;
; 건너뛴 뒤로는 1 씩 가는 이유: 상하 걸음은 칸 수만큼인데, 그 방향으로 계속
; 칸 수만큼 더하면 칸 수와 걸음의 최대공약수에 따라 몇 칸을 영영 못 밟는다
; (4 칸에서 2 씩이면 짝수 칸만 돈다).
;
; **살아 있는 것이 하나라도 있을 때만 부른다.** 하나도 없으면 영영 돈다.
;-----------------------------------------------------------------------------
NextLiving:
    ld b, a                     ; B = 걸음
    ld a, (MonRowN)
    ld c, a                     ; C = 칸 수
    ld a, (MonSel)
    add a, b
    call WrapCell
    ld (MonSel), a
    ld a, b                     ; 이제부터는 걸음의 **부호**만 쓴다
    and 0x80
    ld b, 1
    jr z, .step
    ld b, -1
.step:
    ld a, (MonSel)
    call MonPtr
    inc hl                      ; M_HP
    ld a, (hl)
    or a
    ret nz
    ld a, (MonSel)
    add a, b
    call WrapCell
    ld (MonSel), a
    jr .step

; A = 칸 번호(한 바퀴 안에서 넘치거나 모자란 값), C = 칸 수 -> 0..C-1 로 감는다.
; 걸음이 칸 수를 넘지 않으므로 한 번 더하거나 빼면 된다.
WrapCell:
    bit 7, a
    jr z, .high
    add a, c
    ret
.high:
    cp c
    ret c
    sub c
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

;-----------------------------------------------------------------------------
; HP 게이지 - 몬스터 발아래 점 다섯
;
; 점 하나가 20% 다. 남은 점 수는 올림으로 센다 - 한 대라도 맞았으면 다섯이
; 아니고, 한 점이라도 남아 있으면 아직 살아 있다는 뜻이 되게.
;
;   빨간 점 수 = ceil(hp * 5 / 최대hp)
;
; 나눗셈 대신 최대hp 를 다섯 번까지 더해 가며 센다. 답이 0~5 뿐이라 표를 두거나
; Div16 을 부를 값이 없다.
;-----------------------------------------------------------------------------
HP_COL_FULL equ 0x1C            ; GRB332 빨강 (G 0, R 7, B 0)
HP_COL_GONE equ 0x49            ; 어두운 회색. 던전 벽돌보다 어두워 구별된다

; A = 몬스터 번호. 그 칸의 점 다섯을 찍는다.
DrawHpDots:
    ld (DotMon), a
    call SlotColRow
    call CellXY                 ; MonRowX/Y = 칸의 왼쪽 위

    ld a, (MonRowW)             ; 점 줄을 칸 안에서 가운데로
    sub DOT_ROW_W
    srl a
    ld hl, MonRowX
    add a, (hl)
    ld (DotX), a
    ld a, (MonRowY)             ; 몬스터 아랫변 + 틈
    ld hl, MonRowW
    add a, (hl)
    add a, DOT_TOP
    ld (DotY), a

    ld a, (DotMon)              ; 남은 점 수를 센다
    call MonPtr
    inc hl                      ; M_HP
    ld e, (hl)
    inc hl
    ld a, (hl)                  ; M_MAXHP
    ld (DotMax), a
    ld d, 0
    ld h, d
    ld l, e
    add hl, hl
    add hl, hl
    add hl, de                  ; HL = hp * 5
    ld d, h
    ld e, l                     ; DE = hp * 5
    ld hl, 0
    ld a, (DotMax)
    ld c, a
    ld b, 0
    xor a
    ld (DotLit), a
.count:
    ld a, h                     ; HL >= DE 면 다 셌다
    cp d
    jr c, .add
    jr nz, .done
    ld a, l
    cp e
    jr nc, .done
.add:
    add hl, bc
    ld a, (DotLit)
    inc a
    ld (DotLit), a
    cp DOT_N
    jr c, .count
.done:

    xor a
    ld (DotIdx), a
.dot:
    ld a, (DotIdx)              ; 이 점은 빨강인가 회색인가
    ld hl, DotLit
    cp (hl)
    ld a, HP_COL_FULL
    jr c, .colour
    ld a, HP_COL_GONE
.colour:
    ld (DotCol), a

    ld a, (DotIdx)              ; x = 시작 + 번호 * (폭 + 틈)
    ld h, a
    ld e, DOT_W + DOT_GAP
    call Mult8
    ld a, (DotX)
    add a, l
    ld (DotPx), a

    ld a, (DotY)
    ld (SprY), a
    ld b, DOT_H
.row:
    push bc
    ld a, (DotPx)
    ld e, a
    ld a, (SprY)
    call RowAddrB
    call SetVramWrite
    ld b, DOT_W
    ld c, VDP_DATA
    ld a, (DotCol)
.pix:
    out (c), a                  ; 14
    nop                         ;  5
    nop                         ;  5
    djnz .pix                   ; 14/9  -> 화면이 켜진 채라 29 T-state 를 지킨다
    ld hl, SprY
    inc (hl)
    pop bc
    djnz .row

    ld hl, DotIdx
    inc (hl)
    ld a, (hl)
    cp DOT_N
    jr c, .dot
    ret

; 살아 있는 몬스터 전부의 게이지를 다시 찍는다.
DrawAllHpDots:
    ld a, (MonRowN)
    ld b, a
    xor a
    ld (DotWho), a
.each:
    push bc
    ld a, (DotWho)
    call MonPtr
    inc hl
    ld a, (hl)                  ; M_HP - 쓰러진 칸은 비워 둔다
    or a
    jr z, .skip
    ld a, (DotWho)
    call DrawHpDots
.skip:
    ld hl, DotWho
    inc (hl)
    pop bc
    djnz .each
    ret

;-----------------------------------------------------------------------------
; 맞은 티내기 - 몬스터 머리 위에 "-N" 을 검정 바탕 빨간 글씨로 찍는다.
;
; 애니메이션 없음 - 한 번 찍고 끝이다. 다음에 같은 몬스터가 맞으면 같은
; 자리에 새 값을 덮어 쓴다. PutChar 가 바탕색까지 칠하므로(SetColours 로
; COL_BLACK 배경 지정) 앞 숫자가 새 숫자보다 길어도 자릿수만큼은 지워진다 -
; 자릿수 자체를 고정폭(2 자리)으로 찍어 그 안에서는 항상 깨끗이 덮인다.
;-----------------------------------------------------------------------------
HITNUM_COL  equ 0x1C            ; 피해 숫자 색 (HP 게이지의 빨강과 같다)

; A = 맞은 칸, B = 깎인 피해.
ShowHitNum:
    ld c, a                     ; SlotColRow 가 A 를 쓰므로 칸 번호는 C 로 옮겨 둔다
    ld a, b
    ld (HitDmg), a
    ld a, c
    call SlotColRow
    call CellXY                 ; MonRowX/Y = 그 칸의 왼쪽 위

    ld a, (MonRowW)             ; 칸 가운데에서 "-99" 세 글자만큼 왼쪽으로
    srl a
    ld hl, MonRowX
    add a, (hl)
    sub FONT_W + FONT_W / 2
    ld b, a
    ld a, (MonRowY)             ; 머리 위
    sub 6
    ld c, a
    call SetPos

    ld a, HITNUM_COL
    ld b, COL_BLACK
    call SetColours
    ld a, '-'
    call PutChar
    ld a, (HitDmg)
    ld b, 2
    jp PutNumR

;-----------------------------------------------------------------------------
; 맞은 표시 - 몬스터 칸에 칼질 자국 세 장을 차례로 찍는다.
;
; 전에는 흰 마름모를 반지름 2/4/6 으로 키우며 세 번 찍었다. 지우지 않아도
; 됐던 것은 뒤 프레임이 앞 프레임을 **통째로 덮었기** 때문이다(화살표와 같은
; 수법). 칼질은 그렇지 않다 - 2 번이 1 번을 안 덮고 3 번은 오히려 옅어진다.
; 그래서 칸을 화면 밖에 떠 두었다가 장마다 되돌린다.
;
; 자국은 몬스터 그림과 **같은 꼴, 같은 크기**다. 그래서 그리는 것은
; DrawOneMon 을 그대로 쓴다 - 투명한 곳은 안 건드리므로 몬스터가 비쳐 보인다.
;
; 마지막에 칸을 되돌리므로 자국은 안 남는다. 맞았다는 표시는 발아래 HP 점과
; 머리 위 "-N" 이 계속 하고 있다 (마름모는 다음 다시 그리기까지 남았었다).
;-----------------------------------------------------------------------------
SLASH_HOLD  equ 3               ; 한 장을 몇 프레임 두는가 (셋이면 0.15 초)
    ASSERT SLASH_N == 3         ; 아래에서 3 을 곱하는 자리가 있다

; A = 맞은 칸.
HitFlash:
    call SlotColRow
    call CellXY                 ; MonRowX/Y = 그 칸의 왼쪽 위
    call SlashSave
    xor a
    call SlashFrame
    ld a, 1
    call SlashFrame
    ld a, 2
    call SlashFrame
    ld a, SPR_FIRSTBK           ; 창을 기본 뱅크로 되돌린다
    ld (ASC8_P3), a
    ret

; A = 몇 번째 장. 찍고, 잠깐 두고, 칸을 되돌린다.
SlashFrame:
    call SlashPtr
    call DrawOneMon
    ld b, SLASH_HOLD
.wait:
    push bc
    call WaitVBlank
    pop bc
    djnz .wait
    jp SlashRestore

;-----------------------------------------------------------------------------
; A = 몇 번째 장. 그 그림이 든 뱅크를 걸고 MonRowPtr 에 놓는다.
; 색인은 (마릿수-1) * SLASH_N + 장, 한 칸이 뱅크 1 + 주소 2 = 3 바이트.
;-----------------------------------------------------------------------------
SlashPtr:
    ld c, a
    ld a, (MonRowN)
    dec a
    ld b, a
    add a, a
    add a, b                    ; A = (마릿수-1) * 3
    add a, c                    ; + 장
    ld b, a
    add a, a
    add a, b                    ; A = 색인 * 3 (한 칸의 바이트 수)
    ld hl, SlashTab
    call AddA
    ld a, (hl)
    ld (ASC8_P3), a
    inc hl
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ld (MonRowPtr), hl
    ret

;-----------------------------------------------------------------------------
; 칸(MonRowX, MonRowY, MonRowW 사각형)을 화면 밖으로 떠 두고 되돌린다.
;
; 화살표의 BandSave 와 하는 일은 같지만 틀을 따로 둔다. 저쪽은 띠의 크기가
; 고정(VIEW_W x ARROW_H)이라 y 하나만 갈아 끼우면 되는데, 칸은 마릿수에 따라
; 24~72 로 크기까지 바뀌어 넣을 자리가 넷이다. 저쪽 코드는 화살표가 지나가는
; 길목이라 건드리지 않는다.
;-----------------------------------------------------------------------------
SlashSave:
    ld hl, CmdSlashSave
    ld a, 0                     ; SX, SY 자리
    jr SendSlashCmd
SlashRestore:
    ld hl, CmdSlashRestore
    ld a, 4                     ; DX, DY 자리

; HL = 명령 틀, A = MonRowX/Y 를 넣을 바이트 자리.
;
; BandSave 와 같이 **끝날 때까지 기다린다.** 안 기다리면 명령 엔진이 도는
; 중에 Z80 이 같은 VRAM 에 자국을 찍는다 - 화살표에서 그것을 실제로 겪었다.
SendSlashCmd:
    push af
    ld de, CmdBuf
    ld bc, 15
    ldir
    pop af
    ld hl, CmdBuf
    call AddA
    ld a, (MonRowX)
    ld (hl), a
    inc hl
    ld (hl), 0                  ; x, y 는 화면 안이라 상위 바이트는 늘 0
    inc hl
    ld a, (MonRowY)
    ld (hl), a
    inc hl
    ld (hl), 0

    ld hl, CmdBuf + 8           ; NX, NY = 칸 한 변
    ld a, (MonRowW)
    ld (hl), a
    inc hl
    ld (hl), 0
    inc hl
    ld (hl), a
    inc hl
    ld (hl), 0

    ld a, 32
    ld (CmdFirst), a
    ld hl, CmdBuf
    ld b, 15
    call SendVdpCmd
    jp WaitVdpCmd

; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
CmdSlashSave:                   ; 칸 -> 화면 밖
    dw 0                        ; SX <- MonRowX
    dw 0                        ; SY <- MonRowY
    dw 0
    dw SLASH_VY
    dw 0                        ; NX <- MonRowW
    dw 0                        ; NY <- MonRowW
    db 0
    db 0
    db 0xD0                     ; HMMM

CmdSlashRestore:                ; 화면 밖 -> 칸
    dw 0
    dw SLASH_VY
    dw 0                        ; DX <- MonRowX
    dw 0                        ; DY <- MonRowY
    dw 0                        ; NX <- MonRowW
    dw 0                        ; NY <- MonRowW
    db 0
    db 0
    db 0xD0                     ; HMMM
