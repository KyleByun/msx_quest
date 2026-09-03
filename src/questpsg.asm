;-----------------------------------------------------------------------------
; PSG 음악 - 타이틀 배경음
;
; **--title 빌드에만 들어온다.** 곡은 gfx/psg_music.py 가 assets/psg/title.mp3
; 에서 옮긴 것이고, 채널마다 (볼륨, 주기 하위, 주기 상위, 이어질 프레임 수)
; 네 바이트짜리 사건 목록이다. 길이 0 이 곡의 끝이다.
;
; 곡은 뱅크에 있지만 **시작할 때 RAM 으로 옮겨 놓고 거기서 읽는다.** 그림을
; 푸는 동안에도 소리가 이어져야 하는데, 그림도 0xA000 창을 쓰기 때문에 곡을
; 거기 둔 채로 읽으면 서로 창을 뺏는다. RamEnd 위(0xC940~0xF380)가 비어 있다.
;
; 프레임마다 PsgTick 을 한 번 부른다. 채널마다 남은 길이를 하나 줄이고, 0 이
; 되면 다음 사건을 읽어 PSG 레지스터에 쓴다. 대부분의 프레임은 세 번 빼는
; 것으로 끝난다.
;-----------------------------------------------------------------------------

PSG_ADDR    equ 0xA0
PSG_DATA    equ 0xA1
MUSIC_RAM   equ 0xD000          ; RamEnd(0xC940) 위, 스택(0xF380) 아래

; A = PSG 레지스터 번호, E = 쓸 값.
WritePsg:
    out (PSG_ADDR), a
    ld a, e
    out (PSG_DATA), a
    ret

;-----------------------------------------------------------------------------
; 곡을 RAM 으로 옮기고 PSG 를 연다. 그림을 풀기 전에 한 번 부른다.
;-----------------------------------------------------------------------------
PsgInit:
    ld a, MUSIC_BANK
    ld (ASC8_P3), a
    ld hl, SPR_WIN              ; 0xA000
    ld de, MUSIC_RAM
    ld bc, MUSIC_LEN
    ldir

    ; 채널마다 (포인터 2 바이트, 남은 길이 1 바이트). 길이 0 으로 두면 첫
    ; 프레임에 바로 첫 사건을 읽는다.
    ld hl, MUSIC_RAM + MUSIC_CH0
    ld (MusPtr0), hl
    ld hl, MUSIC_RAM + MUSIC_CH1
    ld (MusPtr1), hl
    ld hl, MUSIC_RAM + MUSIC_CH2
    ld (MusPtr2), hl
    xor a
    ld (MusLeft0), a
    ld (MusLeft1), a
    ld (MusLeft2), a

    ld a, 7                     ; 믹서 - 톤 셋만 열고 노이즈는 닫는다
    ld e, 0x38                  ; 0 이 '켬' 이라 비트가 뒤집혀 있다
    call WritePsg
    ld b, 3                     ; 볼륨 0 으로 시작
    ld c, 8
.mute:
    ld a, c
    ld e, 0
    call WritePsg
    inc c
    djnz .mute
    ret

;-----------------------------------------------------------------------------
; 소리를 끈다. 타이틀이 끝나면 부른다 - 안 부르면 게임이 도는 내내 울린다.
;-----------------------------------------------------------------------------
PsgStop:
    ld b, 3
    ld c, 8
.off:
    ld a, c
    ld e, 0
    call WritePsg
    inc c
    djnz .off
    ret

;-----------------------------------------------------------------------------
; 한 프레임. 채널 셋을 차례로 본다.
;-----------------------------------------------------------------------------
PsgTick:
    ld hl, MusPtr0
    ld de, MusLeft0
    ld c, 0
    call PsgChan
    ld hl, MusPtr1
    ld de, MusLeft1
    ld c, 1
    call PsgChan
    ld hl, MusPtr2
    ld de, MusLeft2
    ld c, 2
    jp PsgChan

;-----------------------------------------------------------------------------
; 채널 하나. HL = 포인터가 든 자리, DE = 남은 길이가 든 자리, C = 채널 번호.
;-----------------------------------------------------------------------------
PsgChan:
    ld a, (de)
    or a
    jr z, .next                 ; 다 썼으면 다음 사건
    dec a
    ld (de), a
    ret

.next:
    push de
    ld e, (hl)                  ; 포인터를 꺼낸다
    inc hl
    ld d, (hl)
    push hl                     ; 나중에 되돌려 놓을 자리
    ex de, hl                   ; HL = 사건

    ld a, (hl)                  ; 볼륨
    ld (MusVol), a
    inc hl
    ld e, (hl)                  ; 주기 하위
    inc hl
    ld d, (hl)                  ; 주기 상위
    inc hl
    ld b, (hl)                  ; 이어질 프레임 수
    inc hl

    ld a, b
    or a
    jr nz, .play
    ; 길이 0 = 곡의 끝. 처음으로 돌아가지 않고 그 채널만 조용히 둔다 -
    ; 세 채널의 길이가 달라서 돌리면 서로 어긋난다.
    dec hl                      ; 포인터를 끝 표시에 그대로 둔다
    dec hl
    dec hl
    dec hl
    ld b, 255                   ; 한참 뒤에 다시 여기로 온다
    ld a, 0
    ld (MusVol), a

.play:
    ex de, hl                   ; DE = 다음 사건, HL = 주기
    push de
    ; 주기: 채널 c 의 레지스터는 2c, 2c+1
    ld a, c
    add a, a
    push af
    ld e, l
    call WritePsg               ; R(2c) = 주기 하위
    pop af
    inc a
    ld e, h
    call WritePsg               ; R(2c+1) = 주기 상위
    ld a, c
    add a, 8
    ld hl, MusVol
    ld e, (hl)
    call WritePsg               ; R(8+c) = 볼륨
    pop de                      ; DE = 다음 사건

    pop hl                      ; 포인터 자리 (상위 바이트)
    ld (hl), d
    dec hl
    ld (hl), e
    pop hl                      ; HL = 남은 길이가 든 자리
    ld a, b
    dec a                       ; 이번 프레임도 한 번으로 친다
    ld (hl), a
    ret
