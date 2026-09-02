;-----------------------------------------------------------------------------
; 글자 찍기
;
; 폰트는 한 줄이 8 비트인 1bpp 다. 화면은 4bpp(한 바이트에 두 픽셀)이라 펼쳐야
; 하는데, 니블 하나(픽셀 넷)를 두 바이트로 바꾸는 표를 RAM 에 만들어 두고 본다.
; 표는 32 바이트뿐이고 글자색/바탕색이 바뀔 때만 다시 만든다.
;
; 글자는 6 픽셀 간격으로 찍지만 실제로는 8 픽셀을 쓴다. 오른쪽 두 칸은 다음
; 글자가 덮으므로 겹쳐도 된다. 간격이 짝수라 x 가 늘 짝수로 남고, 덕분에 바이트
; 경계에 딱 맞아 시프트가 한 번도 필요 없다.
;
; 화면이 켜져 있는 동안 돌기 때문에 VRAM 쓰기 간격 29 T-state 를 지켜야 한다.
; 짧은 구간에는 nop 을 넣어 맞췄다. 아래 주석의 숫자가 그 계산이다.
;-----------------------------------------------------------------------------

; 니블 -> 픽셀 바이트 표를 만든다. (TextFg, TextBg) 를 보고 채운다.
;
; 니블 하나가 픽셀 넷이다. SCREEN 5 는 한 바이트에 픽셀이 둘이라 니블당 두
; 바이트(표 32 바이트), SCREEN 8 은 하나라 니블당 네 바이트(표 64 바이트)다.
; 8bpp 쪽이 훨씬 짧다 - 픽셀을 상위 니블로 미는 시프트가 통째로 없어진다.
BuildExpand:
    ld hl, ExpandTbl
    ld c, 0                     ; 니블 값 0~15
.nib:
    ld a, c
    rlca
    rlca
    rlca
    rlca                        ; 니블을 상위로 올려 rlca 로 왼쪽부터 꺼낸다
    ld e, a
    IFDEF SCREEN8
    ld b, 4                     ; 픽셀 넷 = 바이트 넷
.px:
    ld a, e
    rlca
    ld e, a
    jr nc, .off
    ld a, (TextFg)
    jr .put
.off:
    ld a, (TextBg)
.put:
    ld (hl), a
    inc hl
    djnz .px
    ELSE
    ld b, 2                     ; 바이트 둘
.byte:
    push bc
    ld d, 0
    ld b, 2                     ; 한 바이트에 픽셀 둘
.px:
    sla d
    sla d
    sla d
    sla d                       ; 앞서 넣은 픽셀을 상위 니블로 민다
    ld a, e
    rlca                        ; 다음 픽셀 비트를 캐리로
    ld e, a
    jr nc, .off
    ld a, (TextFg)
    jr .put
.off:
    ld a, (TextBg)
.put:
    or d
    ld d, a
    djnz .px
    ld (hl), d
    inc hl
    pop bc
    djnz .byte
    ENDIF
    inc c
    ld a, c
    cp 16
    jr nz, .nib
    ret

; A = 글자색, B = 바탕색. 표까지 다시 만든다.
SetColours:
    ld (TextFg), a
    ld a, b
    ld (TextBg), a
    jp BuildExpand

; B = x (짝수), C = y
SetPos:
    ld a, b
    ld (TextX), a
    ld a, c
    ld (TextY), a
    ret

; A = y, E = x(픽셀)  ->  HL = VRAM 주소
TextAddr:
    call RowAddr
    push hl
    ld a, e
    call XToByte
    ld e, a
    ld d, 0
    pop hl
    add hl, de
    ret

;-----------------------------------------------------------------------------
; A = 글자 하나를 (TextX, TextY) 에 찍고 TextX 를 FONT_W 만큼 민다.
;-----------------------------------------------------------------------------
; 한 바이트가 곧 한 칸이다. 0x80 이상이면 한글이고, 그 아래는 ASCII 다.
; 둘 다 8x8 1bpp 비트맵이라 아래 찍는 고리는 그대로 함께 쓴다 - 다른 것은
; 비트맵을 어디서 가져오는가와 몇 픽셀 나아가는가 둘뿐이다.
PutChar:
    cp HAN_BASE
    jr c, .latin

    sub HAN_BASE                ; 한글 - 번호 * 8 + HanFont
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, HanFont
    add hl, de
    ld a, HANGUL_ADV
    jr .got

.latin:
    sub FONT_FIRST
    jr nc, .lo
    xor a                       ; 범위 밖은 공백으로
.lo:
    cp FONT_LAST - FONT_FIRST + 1
    jr c, .ok
    xor a
.ok:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl                  ; 글자당 8 바이트
    ld de, FontData
    add hl, de                  ; HL = 이 글자의 비트맵
    ld a, FONT_W

.got:
    ld (CharAdv), a             ; 찍은 뒤 얼마나 나아갈지

    ld a, (TextY)
    ld b, a                     ; B = 지금 줄의 y
    ld c, FONT_H
.row:
    push bc
    push hl
    ld a, (TextX)
    ld e, a
    ld a, b
    call TextAddr
    call SetVramWrite
    pop hl
    ld a, (hl)                  ; 폰트 한 줄
    inc hl
    push hl
    ld c, a
    and 0xF0
    rrca
    rrca
    IFNDEF SCREEN8
    rrca                        ; 4bpp: 니블당 두 바이트라 상위 니블 * 2
    ENDIF                       ; 8bpp: 니블당 네 바이트라 상위 니블 * 4
    ld l, a
    ld h, ExpandTbl >> 8        ; 표가 페이지 머리에 있어 하위만 바꾸면 된다
    IFDEF SCREEN8
    ld b, 8                     ; 니블 둘 = 픽셀 여덟 = 바이트 여덟
    ld a, c
    and 0x0F
    add a, a
    add a, a
    ld c, a                     ; 아래 니블의 표 자리를 미리 잡아 둔다
.px:
    ld a, (hl)                  ; 7
    out (VDP_DATA), a           ; 11
    inc l                       ; 4
    ld a, b                     ; 4
    cp 5                        ; 7  - 넷을 찍었으면 아래 니블로 옮긴다
    jr nz, .same                ; 7/12
    ld l, c                     ; 4
.same:
    djnz .px                    ; 13/8  -> 한 바이트에 최소 40 T-state
    ELSE
    ld a, (hl)
    out (VDP_DATA), a           ; 11
    inc l                       ;  4
    ld a, (hl)                  ;  7
    nop                         ;  4
    nop                         ;  4  -> 30 T-state
    out (VDP_DATA), a
    ld a, c                     ;  4
    and 0x0F                    ;  7
    add a, a                    ;  4
    ld l, a                     ;  4
    ld a, (hl)                  ;  7  -> 37 T-state
    out (VDP_DATA), a
    inc l                       ;  4
    ld a, (hl)                  ;  7
    nop                         ;  4
    nop                         ;  4  -> 30 T-state
    out (VDP_DATA), a
    ENDIF
    pop hl
    pop bc
    inc b                       ; 다음 줄
    dec c
    jr nz, .row

    ld a, (CharAdv)             ; 다음 글자 자리로 - 영문 6, 한글 8
    ld hl, TextX
    add a, (hl)
    ld (hl), a
    ret

;-----------------------------------------------------------------------------
; MsgText - A = 메시지 번호  ->  HL = 지금 고른 말의 문자열
;
; 말을 바꾸는 것은 MsgTab 이 어느 표를 가리키는가 하나뿐이다. 부르는 쪽은
; 번호만 알면 되고 어느 말인지 몰라도 된다.
;-----------------------------------------------------------------------------
MsgText:
    ld l, a
    ld h, 0
    add hl, hl                  ; 표가 워드 배열이다
    ld de, (MsgTab)
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ret

;-----------------------------------------------------------------------------
; SetLang - A = LANG_EN / LANG_KO. 쓸 표를 골라 둔다.
;-----------------------------------------------------------------------------
SetLang:
    ld (Lang), a
    ld hl, LangTabEN            ; 표 다섯의 주소가 나란히 있는 표
    or a
    jr z, .set
    ld hl, LangTabKO
.set:
    ld de, MsgTab               ; MsgTab 부터 다섯 워드가 이어져 있다
    ld bc, 6 * 2
    ldir
    ret

LangTabEN:
    dw MsgTabEN, MonNameEN, SkillNameEN, ClassNameEN, RaceNameEN, WeaponNameEN
LangTabKO:
    dw MsgTabKO, MonNameKO, SkillNameKO, ClassNameKO, RaceNameKO, WeaponNameKO

;-----------------------------------------------------------------------------
; HL = 0 으로 끝나는 문자열
;-----------------------------------------------------------------------------
PutStr:
    ld a, (hl)
    or a
    ret z
    inc hl
    push hl
    call PutChar
    pop hl
    jr PutStr

; HL = 문자열, B = 글자 수 (끝 표시 없이 정해진 길이)
PutStrN:
    ld a, (hl)
    inc hl
    push hl
    push bc
    call PutChar
    pop bc
    pop hl
    djnz PutStrN
    ret

; B = 글자 수만큼 공백
PutSpaces:
    push bc
    ld a, ' '
    call PutChar
    pop bc
    djnz PutSpaces
    ret

;-----------------------------------------------------------------------------
; A = 값(부호 있음), B = 자리 수. 오른쪽 맞춤으로 찍는다.
;
; 나눗셈 명령이 없으므로 10 을 빼면서 자릿수를 만든다. 값이 세 자리라 최대
; 스물일곱 번이면 끝나서 표를 둘 이유가 없다.
;-----------------------------------------------------------------------------
PutNumR:
    push bc
    ld hl, NumBufEnd
    ld (hl), 0
    ld c, 0                     ; 음수 표시
    bit 7, a
    jr z, .abs
    neg
    ld c, 1
.abs:
    ld e, a
.digit:
    ld a, e
    ld d, 0
.div:
    cp 10
    jr c, .rem
    sub 10
    inc d
    jr .div
.rem:
    add a, '0'
    dec hl
    ld (hl), a
    ld a, d
    ld e, a
    or a
    jr nz, .digit
    ld a, c
    or a
    jr z, .pad
    dec hl
    ld (hl), '-'
.pad:
    pop bc                      ; B = 자리 수
    ld a, NumBufEnd & 0xFF      ; 버퍼가 한 페이지 안에 있어 하위만 빼면 된다
    sub l
    ld c, a                     ; 만든 길이
    ld a, b
    sub c
    jr c, PutStr                ; 자리보다 길면 그냥 찍는다
    jr z, PutStr
    ld b, a
    push hl
    call PutSpaces
    pop hl
    jp PutStr


;-----------------------------------------------------------------------------
; 오른쪽 양피지에 전투 기록 찍기
;
; 한 줄을 MsgBuf 에 모았다가 한 번에 찍는다. 조각을 바로 화면에 찍으면 x 위치를
; 계속 계산해야 하는데, 버퍼에 모으면 그냥 PutStr 한 번이면 된다.
;-----------------------------------------------------------------------------

; VDP 명령이 끝나기를 기다린다.
;
; 상태 레지스터 S#2 의 bit0 가 CE(명령 실행 중)다. S#2 를 읽으려면 R#15 를 2 로
; 두어야 하는데, 읽고 나서 반드시 0 으로 되돌려야 한다. 안 그러면 다음에 VRAM
; 주소를 잡을 때 엉뚱한 상태 레지스터를 보게 된다.
WaitVdpCmd:
    ld a, 2
    ld c, 15
    call WriteVdpReg
.wait:
    in a, (VDP_ADDR)
    rrca                        ; bit0 -> 캐리
    jr c, .wait
    xor a
    ld c, 15
    jp WriteVdpReg

; HL = 명령 블록, B = 바이트 수, A = 시작 레지스터 번호.
;
; R#17 에 시작 번호를 넣고 포트 0x9B 로 쏟아부으면 레지스터가 자동으로 하나씩
; 올라간다. R#32~46 을 하나씩 쓰는 것보다 훨씬 짧다.
SendVdpCmd:
    push hl
    push bc
    call WaitVdpCmd
    pop bc
    pop hl
    ld a, (CmdFirst)
    ld c, 17
    call WriteVdpReg
    ld c, 0x9B
    otir
    ret

;-----------------------------------------------------------------------------
; 양피지 칸을 크림색으로 지운다. HMMV (고속 사각형 채우기).
;-----------------------------------------------------------------------------
MsgClear:
    ld a, 36
    ld (CmdFirst), a
    ld hl, CmdClearAll
    ld b, 11
    jp SendVdpCmd

;-----------------------------------------------------------------------------
; 한 줄 위로 민다. HMMM (VRAM 안에서 사각형 옮기기).
;
; 오른쪽 창은 계속 흘러가야 하므로 줄을 찍기 전에 늘 한 칸 올린다. 맨 아래 줄을
; 비우고 거기에 새 줄을 찍으면 스크롤이 된다.
;
; 창 전체가 아니라 **위 LOG_ROWS 줄만** 민다. 아래 여섯 줄은 명령 메뉴 자리라
; 같이 밀면 메뉴가 위로 올라가 버린다.
;-----------------------------------------------------------------------------
MsgScroll:
    ld a, 32
    ld (CmdFirst), a
    ld hl, CmdScroll
    ld b, 15
    call SendVdpCmd
    ld a, 36
    ld (CmdFirst), a
    ld hl, CmdClearLast
    ld b, 11
    jp SendVdpCmd

; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
CmdScroll:
    dw MSG_X
    dw MSG_Y + MSG_DY
    dw MSG_X
    dw MSG_Y
    dw MSG_W * FONT_W
    dw (LOG_ROWS - 1) * MSG_DY
    db 0
    db 0
    db 0xD0                     ; HMMM

; R#36 부터: DX, DY, NX, NY, CLR, ARG, CMD
CmdClearLast:
    dw MSG_X
    dw MSG_Y + (LOG_ROWS - 1) * MSG_DY
    dw MSG_W * FONT_W
    dw MSG_DY
    db CREAM_BYTE
    db 0
    db 0xC0                     ; HMMV

; 아래쪽 명령 메뉴 영역만 지운다.
MenuClear:
    ld a, 36
    ld (CmdFirst), a
    ld hl, CmdClearMenu
    ld b, 11
    jp SendVdpCmd

CmdClearMenu:
    dw MSG_X
    dw MSG_Y + MENU_ROW * MSG_DY
    dw MSG_W * FONT_W
    dw MENU_ROWS * MSG_DY
    db CREAM_BYTE
    db 0
    db 0xC0                     ; HMMV

CmdClearAll:
    dw MSG_X
    dw MSG_Y
    dw MSG_W * FONT_W
    dw MSG_ROWS * MSG_DY
    db CREAM_BYTE
    db 0
    db 0xC0                     ; HMMV

MsgReset:
    ld hl, MsgBuf
    ld (MsgPos), hl
    ld (hl), 0
    ret

; HL = 0 으로 끝나는 문자열을 줄 버퍼에 붙인다.
MsgAddStr:
    ld de, (MsgPos)
.next:
    ld a, (hl)
    or a
    jr z, .end
    ld (de), a
    inc de
    inc hl
    jr .next
.end:
    xor a
    ld (de), a
    ld (MsgPos), de
    ret

; HL = 문자열, B = 최대 길이. 뒤에 붙은 채움 공백은 버린다.
; 이름이 12 칸 고정이라 그냥 붙이면 줄이 공백으로 늘어난다.
MsgAddStrN:
    push hl
    ld e, b
    ld d, 0
    add hl, de
    ld c, b
.back:
    dec hl
    ld a, (hl)
    cp ' '
    jr nz, .gotlen
    dec c
    jr nz, .back
.gotlen:
    pop hl
    ld a, c
    or a
    ret z
    ld b, c
    ld de, (MsgPos)
.copy:
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    djnz .copy
    xor a
    ld (de), a
    ld (MsgPos), de
    ret

; A = 값(부호 있음)을 줄 버퍼에 붙인다.
MsgAddNum:
    ld hl, NumBufEnd
    ld (hl), 0
    ld c, 0
    bit 7, a
    jr z, .abs
    neg
    ld c, 1
.abs:
    ld e, a
.digit:
    ld a, e
    ld d, 0
.div:
    cp 10
    jr c, .rem
    sub 10
    inc d
    jr .div
.rem:
    add a, '0'
    dec hl
    ld (hl), a
    ld a, d
    ld e, a
    or a
    jr nz, .digit
    ld a, c
    or a
    jr z, .out
    dec hl
    ld (hl), '-'
.out:
    jp MsgAddStr

; 모은 줄을 맨 아래에 찍는다. 그 전에 한 줄 올려서 흘러가게 한다.
MsgFlush:
    call MsgScroll
    ld c, MSG_Y + (LOG_ROWS - 1) * MSG_DY
    ld b, MSG_X
    call SetPos
    ld a, COL_BLACK
    ld b, COL_CREAM
    call SetColours
    ld hl, MsgBuf
    call PutStr
    jp MsgReset
