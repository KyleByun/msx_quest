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

;-----------------------------------------------------------------------------
; 화면 밖 VRAM 에 떠 두는 자리 - 화살표 밑그림과, 칼질하는 동안의 칸.
;
; **줄이 아니라 x 로 정면 벽 그림을 피한다.** 정면 벽은 깊이별 사각형을 세로로
; 쌓아 두어 FRONT_VY 부터 FRONT_ROWS 줄을 차지하는데, 폭은 FRONT_MAXW 뿐이라
; 그 오른쪽이 줄마다 통째로 빈다. 거기 놓으면 겹치지 않으면서 줄도 안 쓴다.
;
; 예전에는 줄로 피하려고 FRONT_PIX_LEN / VRAM_ROW 로 정면 벽의 끝 줄을 셌다.
; 정면 벽이 한 줄 256 바이트를 꽉 채운다고 본 셈인데 진짜 폭은 FRONT_MAXW 라,
; 30 줄로 본 것이 실제로는 154 줄이었다. 그래서 화살표 띠(300)와 칼질 칸(310)이
; 정면 벽 그림 **위에** 얹혔고, 전투를 한 번 하고 나면 막다른 길의 벽에 그때
; 떠 둔 몬스터가 박혀 보였다. 다시 그려도 그대로였다 - 그리기가 빠뜨린 것이
; 아니라 오려 붙일 원본이 망가진 것이라서.
;-----------------------------------------------------------------------------
SCRATCH_X   equ 128             ; 정면 벽 그림 오른쪽
EFX_MAXH    equ 96              ; 칸은 최대 72 지만 mon_layout 이 바뀌어도 되게
EFX_MAXW    equ EFX_MAXH + SHAKE_DX             ; 흔들리는 폭까지 넣어 짓는다

; 연출용 작업대. 흔들린 그림을 여기서 지어 화면에 한 번에 얹는다.
EFX_VY      equ FRONT_VY
SAVE_VY     equ EFX_VY + EFX_MAXH               ; 화살표 밑그림

    ASSERT SCRATCH_X >= FRONT_MAXW              ; 정면 벽 그림과 x 가 안 겹친다
    ASSERT SCRATCH_X + EFX_MAXW <= VRAM_ROW     ; 한 줄 안에 들어간다
    ASSERT SCRATCH_X + VIEW_W <= VRAM_ROW
    ASSERT SAVE_VY + ARROW_H <= 512             ; VRAM 128KB = 512 줄
    ASSERT MON_SCALE_N <= MON_N
    ASSERT ARROW_W <= VIEW_W / MON_MAX_COLS

;-----------------------------------------------------------------------------
; 던전 뷰포트의 뒷면 (더블버퍼링)
;
; 던전도 몬스터도 화면이 아니라 여기에 그리고, 다 되면 HMMM 한 번으로 화면에
; 옮긴다. 그리는 과정이 안 보이는 것이 첫째지만, 더 큰 것은 **지운 자리를
; 되살릴 밑그림이 늘 있다**는 것이다. 흔들기나 떠오르는 숫자처럼 잠깐 덮었다가
; 되돌려야 하는 연출은 여기서 오려 오면 끝난다.
;
; x 를 뷰포트와 **같게** 두는 것이 요령이다. 그러면 화면에 그리던 코드를 한 줄도
; 안 고치고 y 만 옮겨서 그대로 뒷면에 그린다 (RowAddr 의 DrawYOfs).
;
;   BACK   던전 + 몬스터를 합성한 것. 연출을 되돌릴 때 여기서 오려 온다.
;   CLEAN  몬스터를 얹기 **전**의 던전만. 흔들 때 있던 자리를 지우려면 필요하다.
;          전투 중에만 뜬다 - 뷰포트 한 장을 옮기는 값이 싸지 않다.
;-----------------------------------------------------------------------------
BACK_VY     equ 410
CLEAN_X     equ VIEW_X + VIEW_W
BACK_YOFS   equ BACK_VY - VIEW_Y             ; 화면 y -> 뒷면 y
    ASSERT BACK_VY >= FRONT_END_VY           ; 정면 벽 그림 아래에 둔다
    ASSERT BACK_VY + VIEW_H <= 512
    ASSERT CLEAN_X + VIEW_W <= VRAM_ROW      ; 두 장이 한 줄에 나란히 들어간다
    ASSERT BACK_VY >= 256                    ; 뒷면은 통째로 A16 = 1 쪽에 있다

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
; 뒷면에 합성해서 화면에 얹기
;=============================================================================

;-----------------------------------------------------------------------------
; 던전 한 장. **던전을 그리는 자리는 여기 하나뿐이다** - 다른 데서 RenderDungeon
; 을 부르면 뒷면이 화면과 어긋나고, 그러면 연출을 되돌릴 때 지난 그림이 되살아난다.
;
; 전투 중에만 CLEAN 사본을 뜬다. 몬스터를 흔들려면 그 자리를 지울 바탕이 있어야
; 하는데, 걸어 다닐 때는 몬스터가 없어 BACK 이 곧 바탕이다.
;-----------------------------------------------------------------------------
ComposeView:
    call BackOn
    call RenderDungeon
    ld a, (BattleOn)
    or a
    jr z, .nomon
    call CleanSave              ; 몬스터를 얹기 전의 던전을 따로 떠 둔다
    call DrawMonsterRow
.nomon:
    call BackOff                ; **중간에 빠져나가면 안 된다** - A16 이 선 채로
    ld hl, CmdBlitBack          ; 나가면 오른쪽 양피지 글자가 뒷면에 찍힌다
    jp SendWaitCmd

; 그리는 면을 뒷면으로 / 화면으로 돌린다.
BackOn:
    ld a, BACK_YOFS & 0xFF
    ld (DrawYOfs), a
    ld a, 0x04
    ld (DrawA16), a
    ld hl, BACK_YOFS
    ld (CmdYOfs), hl
    ret

BackOff:
    xor a
    ld (DrawYOfs), a
    ld (DrawA16), a
    ld hl, 0
    ld (CmdYOfs), hl
    ret

CleanSave:
    ld hl, CmdCleanSave
; HL = 15 바이트 명령 블록. 보내고 끝날 때까지 기다린다.
SendWaitCmd:
    ld a, 32
    ld (CmdFirst), a
    ld b, 15
    call SendVdpCmd
    jp WaitVdpCmd

; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
CmdBlitBack:                    ; 뒷면 -> 화면
    dw VIEW_X
    dw BACK_VY
    dw VIEW_X
    dw VIEW_Y
    dw VIEW_W
    dw VIEW_H
    db 0
    db 0
    db 0xD0                     ; HMMM

CmdCleanSave:                   ; 뒷면(아직 던전뿐) -> 몬스터 없는 사본
    dw VIEW_X
    dw BACK_VY
    dw CLEAN_X
    dw BACK_VY
    dw VIEW_W
    dw VIEW_H
    db 0
    db 0
    db 0xD0                     ; HMMM


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
    jp ComposeView

; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
CmdBandSave:                    ; 화면 -> 화면 밖
    dw VIEW_X
    dw 0                        ; SY <- ArrowY
    dw SCRATCH_X
    dw SAVE_VY
    dw VIEW_W
    dw ARROW_H
    db 0
    db 0
    db 0xD0                     ; HMMM

CmdBandRestore:                 ; 화면 밖 -> 화면
    dw SCRATCH_X
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
HITNUM_W    equ FONT_W * 3      ; "-99" 세 글자가 나아가는 폭
; 지울 때는 이보다 넓어야 한다. 글자 비트맵은 8 도트인데 FONT_W 는 **다음
; 글자까지의 간격**이라 마지막 글자가 두 도트 더 나간다. 처음에 이걸 놓쳐서
; 숫자가 지나간 자리에 오른쪽 두 줄이 남았다.
HITNUM_ERW  equ FONT_W * 2 + 8
HITNUM_MAX  equ 99              ; 세 자리가 되면 지울 칸을 넘는다
; 떠오르는 속도. 처음에는 두 도트씩 두 프레임(여섯 장, 0.19 초)이었는데 너무
; 빨라 읽을 틈이 없었다. 한 도트씩 세 프레임이면 열한 장, 0.55 초로 천천히 뜬다.
HITNUM_RISE equ 10              ; 몇 도트 떠오르는가
HITNUM_STEP equ 1               ; 한 장에 몇 도트
HITNUM_HOLD equ 3               ; 한 장을 몇 프레임 두는가

; A = 맞은 칸, B = 깎인 피해.
FloatHitNum:
    ld c, a
    ld a, b
    cp HITNUM_MAX + 1
    jr c, .fits
    ld a, HITNUM_MAX
.fits:
    ld (HitDmg), a
    ld a, c
    push af
    call MonRowSize             ; 칸 크기는 마릿수에서 나온다
    pop af
    call SlotColRow
    call CellXY                 ; MonRowX/Y = 그 칸의 왼쪽 위

    ld a, (MonRowW)             ; 가로는 칸 가운데
    srl a
    ld hl, MonRowX
    add a, (hl)
    sub HITNUM_W / 2
    ; 뷰포트 안으로 밀어 넣는다. 칸이 좁으면 가운데 맞춘 자리가 밖으로 나가고,
    ; 그러면 오른쪽 양피지에 빨간 자국이 남는다. 칸 폭은 MonSprW 가 정하므로
    ; 어셈블 때 따질 수가 없다.
    cp VIEW_X + VIEW_W - HITNUM_ERW + 1
    jr c, .lx
    ld a, VIEW_X + VIEW_W - HITNUM_ERW
.lx:
    cp VIEW_X
    jr nc, .gotx
    ld a, VIEW_X
.gotx:
    ld (HitNumX), a

    ld a, (MonRowW)             ; 세로는 몸 한가운데
    srl a
    ld hl, MonRowY
    add a, (hl)
    sub FONT_H / 2
    ld (HitNumY), a

    sub VIEW_Y                  ; 뷰포트 위로는 안 나간다
    cp HITNUM_RISE
    jr c, .rise
    ld a, HITNUM_RISE
.rise:
    ld (HitNumLeft), a
    xor a
    ld (HitNumGap), a
    call HitNumBuild            ; 글자는 한 번만 짓는다

.loop:
    call HitNumBlit             ; 작업대 -> 화면 (통짜 사각형)
    ld a, (HitNumGap)
    or a
    call nz, HitNumTrail        ; 위로 뜨면서 아래에 빈 줄을 메운다
    ld b, HITNUM_HOLD
.wait:
    push bc
    call WaitVBlank
    pop bc
    djnz .wait

    ld a, (HitNumLeft)
    or a
    jp z, HitNumErase           ; 다 올랐으면 지우고 끝 (jr 사거리를 넘는다)
    cp HITNUM_STEP
    jr nc, .full
    ld b, a                     ; 남은 것이 한 걸음보다 적다
    jr .move
.full:
    ld b, HITNUM_STEP
.move:
    ld a, (HitNumLeft)
    sub b
    ld (HitNumLeft), a
    ld a, (HitNumY)
    sub b
    ld (HitNumY), a
    ld a, b
    ld (HitNumGap), a
    jr .loop

;-----------------------------------------------------------------------------
; "-N" 을 화면 밖 작업대에 **한 번만** 짓는다.
;
; 예전에는 걸음마다 화면에서 지우고 CPU 로 다시 찍었다. 재 보니 지우고 다시
; 찍기까지 25 ms - 한 프레임(16.7 ms)보다 길어서, 걸음마다 숫자가 없는 화면이
; 한 장씩 나갔다. 멈춰 놓고 보면 멀쩡한데 움직이면 깜빡이던 것이 이것이다.
;
; 글자는 바탕까지 칠하는 **통짜 사각형**이라(PutChar 가 배경색을 함께 찍는다)
; 한 번 지어 두면 옮길 때는 그대로 오려 붙이면 된다. 화면에 가는 것은 다 지은
; 사각형뿐이라 빈 순간이 없고, 걸음마다 드는 값도 25 ms 에서 1 ms 아래로 준다.
;-----------------------------------------------------------------------------
HitNumBuild:
    ld a, EFX_VY & 0xFF         ; TextY 0 이 작업대의 첫 줄이 되게
    ld (DrawYOfs), a
    ld a, 0x04                  ; 작업대는 줄 256 위에 있다
    ld (DrawA16), a
    ld b, SCRATCH_X
    ld c, 0
    call SetPos
    ld a, HITNUM_COL
    ld b, COL_BLACK
    call SetColours
    ld a, '-'
    call PutChar
    ld a, (HitDmg)
    ld b, 2
    call PutNumR
    xor a
    ld (DrawYOfs), a
    ld (DrawA16), a
    ret

; 작업대의 글자를 (HitNumX, HitNumY) 에 얹는다.
HitNumBlit:
    call HitNumCmd
    ld a, SCRATCH_X
    ld (CmdBuf + 0), a          ; SX
    ld hl, EFX_VY
    ld (CmdBuf + 2), hl         ; SY
    ld a, (HitNumY)
    ld (CmdBuf + 6), a          ; DY
    ld a, FONT_H
    ld (CmdBuf + 10), a         ; NY
    ld hl, CmdBuf
    jp SendWaitCmd

; 글자가 뜨면서 아래에 남는 줄(HitNumGap)을 BACK 에서 메운다.
HitNumTrail:
    call HitNumCmd
    ld a, (HitNumY)
    add a, FONT_H
    ld (CmdBuf + 6), a          ; DY
    call HitNumSrcY             ; SY = 뒷면의 같은 줄
    ld a, (HitNumX)
    ld (CmdBuf + 0), a          ; SX
    ld a, (HitNumGap)
    ld (CmdBuf + 10), a         ; NY
    ld hl, CmdBuf
    jp SendWaitCmd

; 마지막 자리를 BACK 에서 덮어 사라지게 한다.
HitNumErase:
    call HitNumCmd
    ld a, (HitNumX)
    ld (CmdBuf + 0), a          ; SX
    ld a, (HitNumY)
    ld (CmdBuf + 6), a          ; DY
    call HitNumSrcY
    ld a, FONT_H
    ld (CmdBuf + 10), a         ; NY
    ld hl, CmdBuf
    jp SendWaitCmd

; CmdBuf+6 의 화면 y 를 뒷면의 y 로 옮겨 SY 에 넣는다.
HitNumSrcY:
    ld a, (CmdBuf + 6)
    ld l, a
    ld h, 0
    ld de, BACK_YOFS
    add hl, de
    ld (CmdBuf + 2), hl
    ret

; 세 명령의 공통 부분. DX 와 NX 는 어느 쪽이든 같다.
HitNumCmd:
    xor a
    ld (CmdBuf + 1), a
    ld (CmdBuf + 5), a
    ld (CmdBuf + 7), a
    ld (CmdBuf + 9), a
    ld (CmdBuf + 11), a
    ld (CmdBuf + 12), a         ; CLR
    ld (CmdBuf + 13), a         ; ARG
    ld a, (HitNumX)
    ld (CmdBuf + 4), a          ; DX
    ld a, HITNUM_ERW
    ld (CmdBuf + 8), a          ; NX
    ld a, 0xD0                  ; HMMM
    ld (CmdBuf + 14), a
    ret

;-----------------------------------------------------------------------------
; 맞은 몬스터를 한 번 흔든다. 크리티컬이면 좌우로 한 번씩.
;
; 있던 자리는 CLEAN(몬스터 없는 던전)에서 오려 지우고, 어긋난 자리에 그림만 다시
; 찍는다. 끝나면 BACK 에서 띠를 통째로 되돌린다 - 그래야 띠에 걸친 옆 칸
; 몬스터까지 함께 제자리로 온다.
;
; 흔드는 폭은 칸이 뷰포트를 벗어나지 않는 만큼으로 줄인다. 네 칸이 들어차면
; 양끝 칸은 바깥쪽으로 갈 자리가 없어 그쪽으로는 안 흔들린다.
;-----------------------------------------------------------------------------
; 맞은 순간 움찔하는 폭과 뜸.
;
; 처음에는 8 도트로 밀고 두 프레임(0.03 초)만 두었더니 튕기듯 지나가 타격감이
; 없었다. 지금은 밀려난 자리에 0.08 초 머물고, **반쯤 돌아온 자리를 한 번 더**
; 거쳐 제자리로 온다. 그 중간 자리가 있어야 되돌아오는 것이지 갑자기 사라졌다
; 나타나는 것으로 안 보인다.
SHAKE_DX    equ 10              ; 밀려나는 최대 폭
SHAKE_HOLD  equ 5               ; 밀려난 자리를 두는 프레임
SHAKE_BACK  equ 2               ; 반쯤 돌아온 자리를 두는 프레임

; A = 맞은 칸.
ShakeMon:
    ld (ShakeCell), a
    call MonRowSize
    ld a, (ShakeCell)
    call CellSprPtr             ; 그림과 뱅크
    ret c                       ; 쓰러졌으면 흔들 것이 없다
    ld a, (ShakeCell)
    call SlotColRow
    call CellXY
    call ShakeWidth

    ld a, (MonRowX)             ; 오른쪽 여유
    ld hl, MonRowW
    add a, (hl)
    ld b, a
    ld a, VIEW_X + VIEW_W
    sub b
    ld hl, ShakeMax
    cp (hl)
    jr c, .gotr
    ld a, (hl)
.gotr:
    ld (ShakeR), a
    ld a, (MonRowX)             ; 왼쪽 여유
    sub VIEW_X
    ld hl, ShakeMax
    cp (hl)
    jr c, .gotl
    ld a, (hl)
.gotl:
    ld (ShakeL), a

    ; 칼질이 오른쪽에서 왼쪽으로 지나가므로 맞은 놈은 **왼쪽으로** 밀린다.
    ld a, (ShakeL)
    or a
    jr nz, .left
    ld a, (ShakeR)              ; 맨 왼쪽 칸이라 왼쪽으로 갈 자리가 없다
    jr .big
.left:
    neg                         ; 왼쪽은 음수
    ld c, a
    ld a, (CritFlag)
    or a
    ld a, c
    jr z, .big
    ld b, SHAKE_HOLD            ; 치명타는 왼쪽으로 밀렸다가 오른쪽으로 되튄다
    call ShakeFrame
    ld a, (ShakeR)
.big:
    ld (ShakeBig), a
    ld b, SHAKE_HOLD
    call ShakeFrame
    ld a, (ShakeBig)            ; 반쯤 돌아온 자리를 거쳐 제자리로
    sra a                       ; sra 는 부호를 지킨다 (-10 -> -5)
    ld b, SHAKE_BACK
    call ShakeFrame
    call ShakeRestore
    ld a, SPR_FIRSTBK           ; 창을 기본 뱅크로 되돌린다
    ld (ASC8_P3), a
    ret

; 밀려날 폭을 몬스터 크기에 맞춘다.
;
; 큰 놈에게 알맞은 10 도트가 작은 놈에게는 너무 크다 - 칸이 붙어 있어서 밀린
; 만큼 옆 칸을 덮는데, 24 도트짜리를 10 도트 밀면 옆 놈이 반쯤 잘려 보인다.
; 폭의 3/16 으로 두면 크기에 상관없이 같은 비율로 움찔한다 (72 -> 13, 24 -> 4).
ShakeWidth:
    ld a, (MonRowW)
    srl a
    srl a
    srl a                       ; 폭 / 8
    ld b, a
    srl b                       ; 폭 / 16
    add a, b
    cp SHAKE_DX
    jr c, .cap
    ld a, SHAKE_DX
.cap:
    or a
    jr nz, .set
    inc a                       ; 아무리 작아도 한 도트는 움직인다
.set:
    ld (ShakeMax), a
    ret

;
; 어긋난 그림을 **화면 밖 작업대(EFX)에서 먼저 짓고** 다 된 것을 한 번에 얹는다.
; 화면에서 지우고 다시 그리면 그 사이 25 ms 동안 몬스터가 없는 화면이 보여서
; 흔들리는 것이 아니라 깜빡이는 것으로 보였다. BACK 의 칸을 통째로 어긋난 자리에
; 밀어 붙이는 방법도 해 봤는데, 칸 안의 벽까지 같이 밀려 벽돌이 어긋나 보였다.
; 짓는 동안 화면에는 제자리 그림이 그대로 있으므로 아무것도 안 보인다.
; A = 어긋남 (부호 있음), B = 몇 프레임 둘 것인가.
ShakeFrame:
    ld (ShakeCur), a
    ld a, b
    ld (ShakeHold), a
    call ShakeSpan              ; 이번 장이 닿는 띠
    call ShakeBuild             ; CLEAN 바탕 + 어긋난 그림 -> 작업대
    call ShakeShow              ; 작업대 -> 화면
    ld a, (ShakeHold)
    ld b, a
.wait:
    push bc
    call WaitVBlank
    pop bc
    djnz .wait
    ret

; ShakeCur 로부터 띠의 왼쪽(ShakeBX), 폭(ShakeBW), 작업대 안의 그림 자리
; (ShakeDraw) 를 낸다. 오른쪽으로 가면 왼쪽 끝이, 왼쪽으로 가면 오른쪽 끝이
; 제자리에 남으므로 띠는 어느 쪽이든 칸 + |어긋남| 이다.
ShakeSpan:
    ld a, (ShakeCur)
    bit 7, a
    jr nz, .left
    ld b, a                     ; 오른쪽으로
    ld a, (MonRowX)
    ld (ShakeBX), a
    ld a, b
    ld (ShakeDraw), a
    jr .width
.left:
    neg
    ld b, a                     ; B = |어긋남|
    ld a, (MonRowX)
    sub b
    ld (ShakeBX), a
    xor a
    ld (ShakeDraw), a
.width:
    ld a, (MonRowW)
    add a, b
    ld (ShakeBW), a
    ret

; CLEAN 에서 띠만큼 바탕을 떠 오고, 그 위에 그림을 어긋난 자리에 찍는다.
ShakeBuild:
    call EfxCmdBase
    ld a, (ShakeBX)
    add a, VIEW_W               ; CLEAN 은 뷰포트 폭만큼 오른쪽에 있다
    ld (CmdBuf + 0), a          ; SX
    ld a, (MonRowY)             ; SY = 뒷면의 같은 줄
    ld l, a
    ld h, 0
    ld de, BACK_YOFS
    add hl, de
    ld (CmdBuf + 2), hl
    ld a, SCRATCH_X
    ld (CmdBuf + 4), a          ; DX = 작업대
    ld hl, EFX_VY
    ld (CmdBuf + 6), hl         ; DY
    ld hl, CmdBuf
    call SendWaitCmd

    ; 그림은 작업대에 찍는다. y 는 EFX_VY 로, x 는 작업대 안으로 옮긴다.
    ld a, (MonRowX)
    ld (ShakeSaveX), a
    ld a, SCRATCH_X
    ld hl, ShakeDraw
    add a, (hl)
    ld (MonRowX), a
    ld a, EFX_VY & 0xFF         ; RowAddr 이 y 에 더할 값
    ld hl, MonRowY
    sub (hl)
    ld (DrawYOfs), a
    ld a, 0x04                  ; 작업대도 줄 256 위라 A16 이 있어야 한다
    ld (DrawA16), a
    call DrawOneMon
    xor a
    ld (DrawYOfs), a
    ld (DrawA16), a
    ld a, (ShakeSaveX)
    ld (MonRowX), a
    ret

; 작업대에서 화면의 띠로.
ShakeShow:
    call EfxCmdBase
    ld a, SCRATCH_X
    ld (CmdBuf + 0), a          ; SX
    ld hl, EFX_VY
    ld (CmdBuf + 2), hl         ; SY
    ld a, (ShakeBX)
    ld (CmdBuf + 4), a          ; DX
    ld a, (MonRowY)
    ld (CmdBuf + 6), a          ; DY
    ld hl, CmdBuf
    jp SendWaitCmd

; 작업대를 오가는 명령의 공통 부분 - 크기는 띠 하나로 같다.
EfxCmdBase:
    xor a
    ld (CmdBuf + 1), a
    ld (CmdBuf + 5), a
    ld (CmdBuf + 7), a
    ld (CmdBuf + 9), a
    ld (CmdBuf + 11), a
    ld (CmdBuf + 12), a         ; CLR
    ld (CmdBuf + 13), a         ; ARG
    ld a, (ShakeBW)
    ld (CmdBuf + 8), a          ; NX
    ld a, (MonRowW)
    ld (CmdBuf + 10), a         ; NY
    ld a, 0xD0                  ; HMMM
    ld (CmdBuf + 14), a
    ret

; BACK 의 칸을 화면 제자리에 되돌린다 (칼질 한 장이 끝날 때마다).
CellRestore:
    call ShakeCmdBase
    ld a, (MonRowX)
    ld (CmdBuf + 0), a          ; SX
    ld (CmdBuf + 4), a          ; DX
    ld a, (MonRowW)
    ld (CmdBuf + 8), a          ; NX
    ld hl, CmdBuf
    jp SendWaitCmd

; SX/DX/NX 만 빼고 채워 둔다 - 세로는 어느 쪽이든 칸 한 변으로 같다.
ShakeCmdBase:
    xor a
    ld (CmdBuf + 1), a
    ld (CmdBuf + 5), a
    ld (CmdBuf + 7), a          ; DrawFront 가 뒷면에 그리면서 여기에 1 을 남긴다
    ld (CmdBuf + 9), a
    ld (CmdBuf + 11), a
    ld (CmdBuf + 12), a         ; CLR
    ld (CmdBuf + 13), a         ; ARG
    ld a, (MonRowY)             ; SY = 뒷면의 같은 줄
    ld l, a
    ld h, 0
    ld de, BACK_YOFS
    add hl, de
    ld (CmdBuf + 2), hl
    ld a, (MonRowY)
    ld (CmdBuf + 6), a          ; DY
    ld a, (MonRowW)
    ld (CmdBuf + 10), a         ; NY
    ld a, 0xD0                  ; HMMM
    ld (CmdBuf + 14), a
    ret

; 흔들기가 지나다닌 띠를 BACK 에서 통째로 되돌린다. 띠에 걸친 옆 칸 몬스터까지
; 함께 제자리로 온다.
ShakeRestore:
    ld a, (MonRowX)
    ld hl, ShakeL
    sub (hl)
    ld (ShakeBX), a             ; 띠의 왼쪽 화면 x
    ld (CmdBuf + 0), a          ; SX (뒷면과 화면의 x 가 같다)
    call ShakeCmdBase
    ld a, (ShakeBX)
    ld (CmdBuf + 4), a          ; DX
    ld a, (MonRowW)             ; NX = 칸 + 양쪽으로 흔들린 만큼
    ld hl, ShakeL
    add a, (hl)
    ld hl, ShakeR
    add a, (hl)
    ld (CmdBuf + 8), a
    ld hl, CmdBuf
    jp SendWaitCmd

; A = 칸 -> MonRowPtr 과 뱅크를 그 칸의 그림으로 맞춘다. 못 그리면 캐리.
; DrawMonsterRow 가 칸마다 하는 일과 같다.
CellSprPtr:
    call MonPtr
    ld a, (hl)                  ; M_TYPE
    inc hl
    ld c, (hl)                  ; M_HP
    inc c
    dec c
    scf
    ret z                       ; 쓰러진 놈
    cp MONSTER_N
    ccf
    ret c                       ; 종류가 표 밖
    call MonSprPtr
    ld (MonRowPtr), hl
    or a                        ; 캐리를 지운다
    ret

; A = 칸. 발아래 게이지를 뒷면과 화면 양쪽에 찍는다. 뒷면에도 찍어야 연출을
; 되돌릴 때 옛 게이지가 되살아나지 않는다.
DrawHpDotsBoth:
    push af
    call BackOn
    pop af
    push af
    call DrawHpDots
    call BackOff
    pop af
    jp DrawHpDots

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
; A = 맞은 칸, B = 친 무기의 계열 (FAM_BLADE / FAM_POLE / FAM_BOW).
HitFlash:
    ld c, a
    ld a, b
    ld (HitFam), a
    ld a, c
    call SlotColRow
    call CellXY                 ; MonRowX/Y = 그 칸의 왼쪽 위
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
    jp CellRestore              ; BACK 에 제자리 그림이 있으니 떠 둘 것이 없다

;-----------------------------------------------------------------------------
; A = 몇 번째 장. HitFam 계열의 그 그림이 든 뱅크를 걸고 MonRowPtr 에 놓는다.
;
; 색인은 (계열 * SLASH_GRP + 마릿수-1) * SLASH_N + 장, 한 칸이 뱅크 1 + 주소 2.
; 곱셈은 더하기로 편다 - Mult8 이 B 와 D 를 깨서 여기서는 도리어 성가시다.
;-----------------------------------------------------------------------------
    ASSERT SLASH_GRP == 5       ; 아래에서 4 를 곱해 더해 5 를 만든다
SlashPtr:
    ld c, a                     ; C = 장
    ld a, (HitFam)
    ld b, a
    add a, a
    add a, a
    add a, b                    ; A = 계열 * 5 (= SLASH_GRP)
    ld b, a
    ld a, (MonRowN)
    dec a
    add a, b                    ; + (마릿수-1)
    ld b, a
    add a, a
    add a, b                    ; * 3 (= SLASH_N)
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

