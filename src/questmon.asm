;-----------------------------------------------------------------------------
; 몬스터 그림 찍기
;
; 그림은 ASCII8 뱅크 3~4 에 들어 있고 실행 중에 0xA000 창에 걸린다. 종류마다
; 어느 뱅크 어디에 있는지는 MonsterTable 에 적혀 있다(questrules.py 가 굽는다).
;
; 자료는 줄마다 (건너뛸 바이트, 그릴 바이트, 픽셀...) 을 잇고 0xFF 로 끝난다.
; 건너뛰기는 직전 런이 끝난 자리부터 세므로 포인터를 더하기만 하면 된다.
; 투명한 곳은 아예 건드리지 않아서 뒤의 던전 그림이 그대로 보인다.
;
; 값이 깨졌을 때를 두 군데에서 막는다. 종류 번호가 표 밖이면 그냥 돌아가고,
; 길이가 0 이면 줄 끝으로 본다. 길이 0 을 그대로 두면 ld b,0 이 되어 outi 가
; 256 번 돌고, 게다가 자리가 앞으로 가지 않아 같은 자리를 끝없이 다시 그린다.
; 0 으로 채워진 빈 뱅크를 가리키면 딱 그 꼴이 되어 멈춘 것처럼 보인다.
;-----------------------------------------------------------------------------

SPR_X       equ 32              ; 던전 칸(16,8) 96x96 안에 64x64 를 가운데로
SPR_Y       equ 24

; A = y, E = x(바이트).  HL = VRAM 주소.
; TextAddr 는 x 를 픽셀로 받지만 그림은 바이트 단위라 따로 둔다.
RowAddrB:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; y * 128
    ld a, e
    add a, l
    ld l, a
    ret nc
    inc h
    ret

;-----------------------------------------------------------------------------
; A = 몬스터 종류. 던전 칸에 그 그림을 찍는다.
;-----------------------------------------------------------------------------
DrawMonsterPic:
    cp MONSTER_N                ; 종류 번호가 표 밖이면 아무것도 안 그린다.
    ret nc                      ; 값이 깨져도 엉뚱한 곳을 읽지 않게 막는다.
    call MonTypePtr
    ld de, T_SPRBANK
    add hl, de
    ld a, (hl)
    ld (ASC8_P3), a             ; 그림이 든 뱅크를 0xA000 에 건다
    inc hl
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a                     ; HL = 그림 자료

    ld a, SPR_Y
    ld (SprY), a
    ld a, SPR_H
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
    jr z, .eol                  ; 0 은 줄 끝으로 본다.
    ld (SprLen), a

    push hl                     ; 자료 포인터를 지킨다
    ld a, (SprCol)
    add a, SPR_X / 2
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

    ld a, SPR_FIRSTBK           ; 창을 기본 뱅크로 되돌린다
    ld (ASC8_P3), a
    ret
