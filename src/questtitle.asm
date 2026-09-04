;-----------------------------------------------------------------------------
; 타이틀 화면 - 그림 넉 장을 차례로 보여주고 게임으로 넘어간다
;
; **빌드에 --title 을 주었을 때만 들어온다.** 안 주면 이 파일도 그림 뱅크도
; 롬에 없고 부팅하면 바로 게임이다. 테스트할 때 매번 넘기지 않으려는 것이다.
;
; 어떤 그림을 어떤 차례로, 아래에 무슨 말을 띄울지는 gfx/title.json 이 정하고
; gfx/quest_title.py 가 굽는다.
;
; 그림은 한 장이 8KB 를 넘어서 뱅크에 **걸쳐서** 들어 있다. 장마다 뱅크를 새로
; 시작하면 자투리가 장당 평균 4KB 씩 버려지기 때문이다. 그래서 원본 바이트를
; 읽는 자리를 TitleGet 한 곳으로 모으고, 거기서 0xC000 에 닿으면 다음 뱅크로
; 창을 갈아 끼운다.
;
; 푸는 동안에는 화면을 끈다. VRAM 접근 간격을 신경 쓸 필요가 없어지고(그림
; 하나가 36,864 바이트다), 다 그린 뒤에 켜므로 장면이 한 번에 바뀐다.
;-----------------------------------------------------------------------------

TITLE_PIX   equ 256 * TITLE_IMG_H       ; 한 장의 픽셀 수 (= 바이트 수)

;-----------------------------------------------------------------------------
; 타이틀 전체. 마지막 장을 넘기면 돌아간다.
;-----------------------------------------------------------------------------
ShowTitle:
    ld a, MUS_TITLE             ; 곡을 RAM 으로 옮기고 PSG 를 연다
    call PsgInit
    xor a
    ld (titleNo), a
.each:
    call TitleOne
    ld hl, titleNo
    inc (hl)
    ld a, (hl)
    cp TITLE_N
    jr c, .each
    call PsgStop                ; 안 끄면 게임이 도는 내내 울린다
    ld a, SPR_FIRSTBK           ; 창을 그림 뱅크로 되돌린다
    ld (ASC8_P3), a
    ret

;-----------------------------------------------------------------------------
; VBlank 를 기다리면서 음악을 한 프레임 돌린다. 타이틀에서 기다리는 자리는
; 전부 이것을 쓴다 - WaitVBlank 를 직접 부르면 그 동안 소리가 멎는다.
;-----------------------------------------------------------------------------
TitleFrame:
    call WaitVBlank
    jp PsgTick

;-----------------------------------------------------------------------------
; titleNo 번째 장 하나.
;-----------------------------------------------------------------------------
TitleOne:
    xor a                       ; 그리는 동안 화면을 끈다
    ld c, 1
    call WriteVdpReg

    ld a, (titleNo)             ; TitleImg 한 줄은 뱅크1 + 주소2 + 길이2 = 5
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld d, 0
    ld e, a
    add hl, de                  ; * 5
    ld de, TitleImg
    add hl, de
    ld a, (hl)                  ; 시작 뱅크
    ld (titleBank), a
    ld (ASC8_P3), a
    inc hl
    ld e, (hl)                  ; 그 뱅크 안의 주소
    inc hl
    ld d, (hl)
    push de                     ; (길이는 안 쓴다 - 픽셀 수로 센다)
    pop hl                      ; HL = 원본 포인터

    call UnpackTitleImg
    call TitleClearText

    ld a, 0x40                  ; 그림이 다 들어갔으니 켠다
    ld c, 1
    call WriteVdpReg

    ; **글은 화면을 켠 뒤에 친다.** 처음에는 켜기 전에 쳤는데 두 가지가 틀렸다 -
    ; 한 글자씩 나오는 것이 안 보이고(다 찍힌 화면이 한 번에 떴다), 화면이 꺼진
    ; 동안에는 VBlank 를 기다리는 자리에서 그대로 멈췄다.
    call TitleDrawText
    jp TitleWait

;-----------------------------------------------------------------------------
; HL = RLE 원본. VRAM 0 부터 TITLE_PIX 바이트를 푼다.
;
; RLE: 0x80|n 이면 다음 바이트를 n+1 회, 그 외 n 이면 이어지는 n+1 바이트 그대로.
; 남은 길이는 **푼 픽셀 수**로 센다 - 원본 길이로 세면 뱅크를 넘을 때마다
; 포인터와 따로 놀아서 어긋나기 쉽다.
;-----------------------------------------------------------------------------
UnpackTitleImg:
    push hl
    ld hl, 0
    call SetVramWrite
    pop hl
    ld de, TITLE_PIX            ; 남은 픽셀
.loop:
    call TitleGet
    bit 7, a
    jr z, .literal
    and 0x7F                    ; 같은 바이트 반복
    inc a
    ld b, a
    ld (titleRun), a            ; 남은 픽셀에서 뺄 값. djnz 가 B 를 0 으로 만든다.
    push bc
    call TitleGet
    pop bc
.rep:
    out (VDP_DATA), a           ; 화면이 꺼져 있어 간격을 안 맞춰도 된다
    djnz .rep
    jr .more
.literal:
    inc a                       ; 이어지는 바이트를 그대로
    ld b, a
    ld (titleRun), a
.lit:
    push bc
    call TitleGet
    pop bc
    out (VDP_DATA), a
    djnz .lit
.more:
    ; 그림 한 장을 푸는 데 0.7 초쯤 걸린다. 그 동안 소리가 멎으면 장이 바뀔
    ; 때마다 음악이 끊긴다. 화면이 꺼져 있어 VBlank 를 **기다릴** 수는 없으니
    ; 지나갔는지만 보고, 지나갔으면 한 프레임 울린다.
    ;
    ; PsgTick 은 레지스터를 다 쓴다. 여기서는 HL(원본), DE(남은 픽셀), BC 가
    ; 전부 살아 있어야 하므로 통째로 밀어 둔다.
    in a, (VDP_ADDR)
    and 0x80
    jr z, .nomus
    push bc
    push de
    push hl
    call PsgTick
    pop hl
    pop de
    pop bc
.nomus:
    ld a, (titleRun)            ; 남은 픽셀 -= 이번에 쓴 수
    ld c, a
    ld a, e
    sub c
    ld e, a
    jr nc, .nb
    dec d
.nb:
    ld a, d
    or e
    jr nz, .loop
    ret

;-----------------------------------------------------------------------------
; 다음 원본 바이트를 A 로. 뱅크 끝에 닿으면 창을 갈아 끼운다.
;
; 그림 하나가 8KB 를 넘으므로 여기가 꼭 있어야 한다. 원본을 읽는 자리를 전부
; 이리로 모아 두면 경계 검사를 한 곳에서만 하면 된다.
;-----------------------------------------------------------------------------
TitleGet:
    ld a, h
    cp 0xC0
    jr nz, .ok
    ld a, (titleBank)
    inc a
    ld (titleBank), a
    ld (ASC8_P3), a
    ld hl, SPR_WIN              ; 0xA000
.ok:
    ld a, (hl)
    inc hl
    ret

;-----------------------------------------------------------------------------
; 그림 아래 글 자리를 검게 지운다 (HMMV).
;-----------------------------------------------------------------------------
TitleClearText:
    ld hl, CmdTitleClear
    ld a, 36
    ld (CmdFirst), a
    ld b, 11
    call SendVdpCmd
    jp WaitVdpCmd               ; 지우는 중에 글자를 찍으면 그 글자가 날아간다

CmdTitleClear:                  ; R#36 부터: DX, DY, NX, NY, CLR, ARG, CMD
    dw 0
    dw TITLE_IMG_H
    dw 256
    dw 212 - TITLE_IMG_H
    db BLACK_BYTE
    db 0
    db 0xC0                     ; HMMV

;-----------------------------------------------------------------------------
; 이 장의 글을 아래에 찍는다. 말(한/영)에 따라 표를 고른다.
;-----------------------------------------------------------------------------
TitleDrawText:
    ld a, COL_CREAM
    ld b, COL_BLACK
    call SetColours
    xor a
    ld (titleSkip), a           ; 장마다 새로 - 앞 장에서 건너뛴 것이 안 이어진다

    ld a, (titleNo)             ; TitleLine 한 줄은 (첫 줄, 줄 수)
    add a, a
    ld l, a
    ld h, 0
    ld de, TitleLine
    add hl, de
    ld a, (hl)                  ; 첫 줄 번호
    ld (titleLine), a
    inc hl
    ld a, (hl)
    ld (titleRows), a
    or a
    ret z

    ld a, TITLE_TEXT_Y
    ld (titleY), a
.row:
    ld a, (titleLine)           ; 줄 번호 -> 글 주소
    add a, a
    ld l, a
    ld h, 0
    ld a, (Lang)
    or a
    ld de, TitleTextPtrEN
    jr z, .have
    ld de, TitleTextPtrKO
.have:
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    push hl

    ld a, (titleY)
    ld c, a
    ld b, TITLE_MARGIN
    call SetPos
    pop hl
    call TypeStr

    ld a, (titleY)
    add a, TITLE_LINE_H
    ld (titleY), a
    ld hl, titleLine
    inc (hl)
    ld hl, titleRows
    dec (hl)
    jr nz, .row
    ret

;-----------------------------------------------------------------------------
; HL = 0 으로 끝나는 문자열. **한 글자씩** 찍는다.
;
; PutChar 가 TextX 를 스스로 밀어 주므로 글자마다 그냥 한 번씩 부르면 된다.
; 사이에 TITLE_TYPE_D 프레임을 쉰다.
;
; 찍는 도중에 키를 누르면 titleSkip 을 세우고 **남은 글자를 한 번에** 찍는다.
; 그 표시는 장이 끝날 때까지 남는다 - 한 줄만 건너뛰고 다음 줄에서 다시 느려지면
; 누른 사람 입장에서는 안 먹은 것처럼 보인다.
;-----------------------------------------------------------------------------
TypeStr:
    ld a, (hl)
    or a
    ret z
    inc hl
    push hl
    call PutChar
    pop hl
    ld a, (titleSkip)
    or a
    jr nz, TypeStr              ; 이미 건너뛰기면 안 쉰다
    ld b, TITLE_TYPE_D
    inc b                       ; 0 이면 djnz 가 256 번 돈다
    dec b
    jr z, TypeStr
.wait:
    push bc
    push hl
    call TitleFrame
    call TitleAnyKey
    pop hl
    pop bc
    jr nz, .skip
    djnz .wait
    jr TypeStr
.skip:
    ld a, 1
    ld (titleSkip), a
    jr TypeStr

;-----------------------------------------------------------------------------
; 키를 기다린다. TITLE_HOLD 가 0 이 아니면 그 프레임 수만큼만 기다린다.
;
; 먼저 **떼기를 기다린다.** 안 그러면 한 번 누른 것이 넉 장을 통째로 넘긴다.
;-----------------------------------------------------------------------------
TitleWait:
    call TitleAnyKey
    jr nz, TitleWait            ; 아직 누르고 있으면 뗄 때까지
    ld de, 0
.wait:
    call TitleFrame
    call TitleAnyKey
    ret nz
    IF TITLE_HOLD > 0
    inc de
    ld hl, TITLE_HOLD
    or a
    sbc hl, de
    ret z
    ENDIF
    jr .wait

;-----------------------------------------------------------------------------
; 아무 키나 눌렸는가. Z 면 아무것도 안 눌림.
;
; 키보드 행 0~10 을 훑는다. 게임은 8 행(커서)과 4 행(M)만 보지만 타이틀에서는
; "아무 키나" 라 전부 봐야 한다. 행을 고르는 하위 4 비트만 바꾸고 나머지는
; 그대로 둔다 - PPI 의 다른 비트를 건드리면 슬롯 설정이 날아간다.
;-----------------------------------------------------------------------------
TitleAnyKey:
    ld b, 11                    ; 행 0..10
    ld c, 0
.row:
    in a, (PPI_ROW)
    and 0xF0
    or c
    out (PPI_ROW), a
    in a, (PPI_COL)
    cp 0xFF                     ; 0 인 비트가 눌린 키
    jr nz, .hit
    inc c
    djnz .row
    xor a                       ; 아무것도 안 눌림
    ret
.hit:
    ld a, 1
    or a
    ret
