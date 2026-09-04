;-----------------------------------------------------------------------------
; PSG 음악 - 타이틀곡과 전투곡
;
; 곡은 gfx/psg_music.py 가 assets/psg/*.mp3 에서 옮긴 것이고, 채널마다
; (볼륨, 주기 하위, 주기 상위, 이어질 프레임 수) 네 바이트짜리 사건 목록이다.
; 길이 0 이 곡의 끝이다. MusTab 이 곡마다 (길이, 채널 셋의 자리) 를 준다.
;
; **곡마다 뱅크 하나를 쓰고, 시작할 때 RAM 으로 옮겨 놓고 거기서 읽는다.**
; 그림도 0xA000 창을 쓰기 때문에 곡을 창에 둔 채로 읽으면 서로 창을 뺏는다
; (음악은 타이틀 그림을 푸는 중에도 이어져야 한다). 두 곡을 한 뱅크에 이어
; 붙이지 않는 이유는 8KB 를 넘기도 하고, 곡이 경계를 넘으면 옮기는 도중에
; 뱅크를 갈아 끼워야 하기 때문이다.
;
; 프레임마다 PsgTick 을 한 번 부른다. 채널마다 남은 길이를 하나 줄이고, 0 이
; 되면 다음 사건을 읽어 PSG 레지스터에 쓴다. 대부분의 프레임은 세 번 빼는
; 것으로 끝난다. 음악이 꺼져 있으면(MusOn = 0) 바로 돌아간다 - 그래서 메인
; 루프에서 조건 없이 불러도 된다.
;
; 곡이 끝나면 채널마다 제 처음으로 돌아간다. 세 채널의 총 프레임 수가 같다는
; 것을 psg_music.py 가 **굽는 자리에서 검사하므로** 따로 돌아가도 안 어긋난다.
;-----------------------------------------------------------------------------

PSG_ADDR    equ 0xA0
PSG_DATA    equ 0xA1
MUSIC_RAM   equ 0xD000          ; RamEnd(0xC940) 위, 스택(0xF380) 아래
    ASSERT MUSIC_RAM + MUSIC_MAXLEN < STACK_TOP - 256

; A = PSG 레지스터 번호, E = 쓸 값.
WritePsg:
    out (PSG_ADDR), a
    ld a, e
    out (PSG_DATA), a
    ret

;-----------------------------------------------------------------------------
; HL = 표의 채널 자리, DE = 넣을 곳. 오프셋에 MUSIC_RAM 을 더해 절대 주소로
; 바꿔 넣고 둘 다 한 칸 나아간다.
;-----------------------------------------------------------------------------
MusAbs:
    ld c, (hl)
    inc hl
    ld b, (hl)
    inc hl
    push hl                     ; 표 자리를 지킨다
    ld hl, MUSIC_RAM
    add hl, bc
    ex de, hl                   ; HL = 넣을 곳, DE = 절대 주소
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ex de, hl                   ; DE = 다음 넣을 곳
    pop hl
    ret

;-----------------------------------------------------------------------------
; A = 곡 번호(MUS_TITLE / MUS_BATTLE). 그 곡을 RAM 으로 옮기고 처음부터 튼다.
;
; 이미 울리는 중에 불러도 된다 - 도망친 다음 걸음에 바로 또 마주칠 수 있어서
; 시작과 멈춤이 촘촘히 오간다. 그때마다 통째로 다시 깔면 그만이다.
;-----------------------------------------------------------------------------
PsgInit:
    cp MUS_N
    ret nc                      ; 없는 곡이면 아무것도 안 한다
    ld (MusSong), a
    ld h, a
    ld e, MUS_STRIDE
    call Mult8
    ld de, MusTab
    add hl, de                  ; HL = 이 곡의 줄

    ld c, (hl)                  ; 옮길 바이트 수
    inc hl
    ld b, (hl)
    inc hl
    push bc

    ld de, MusStart0            ; 채널 셋의 시작 주소를 만들어 둔다
    call MusAbs
    call MusAbs
    call MusAbs

    ld a, (MusSong)             ; 그 곡의 뱅크를 창에 건다
    add a, MUSIC_BANK
    ld (ASC8_P3), a
    ld hl, SPR_WIN              ; 0xA000
    ld de, MUSIC_RAM
    pop bc
    ldir
    ld a, SPR_FIRSTBK           ; 창을 기본 뱅크로 되돌린다 - 전투 중에 부르면
    ld (ASC8_P3), a             ; 다음에 그릴 것이 창을 그대로 쓴다

    ld hl, MusStart0            ; 읽는 자리를 처음으로
    ld de, MusPtr0
    ld bc, 6
    ldir
    xor a                       ; 남은 길이 0 = 첫 프레임에 바로 첫 사건
    ld (MusLeft0), a
    ld (MusLeft1), a
    ld (MusLeft2), a

    ld a, 7                     ; 믹서 - 톤 셋만 열고 노이즈는 닫는다
    ld e, 0x38                  ; 0 이 '켬' 이라 비트가 뒤집혀 있다
    call WritePsg
    ld a, 1
    ld (MusOn), a
    jp PsgSilence               ; 볼륨 0 으로 시작

;-----------------------------------------------------------------------------
; 소리를 끈다. 전투가 끝나거나 타이틀이 끝나면 부른다.
;-----------------------------------------------------------------------------
PsgStop:
    xor a
    ld (MusOn), a
PsgSilence:
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
; 한 프레임. 채널 셋을 차례로 본다. 음악이 꺼져 있으면 바로 돌아간다.
;-----------------------------------------------------------------------------
PsgTick:
    ld a, (MusOn)
    or a
    ret z
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
    push de                     ; 남은 길이 자리
    ld e, (hl)                  ; 포인터를 꺼낸다
    inc hl
    ld d, (hl)
    push hl                     ; 포인터의 상위 바이트 자리
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

    ; 길이 0 = 곡의 끝. 이 채널의 처음으로 돌린다. 남은 길이를 0 으로 두어
    ; 다음 프레임에 첫 사건을 읽게 한다 - 한 프레임 늦지만 안 들린다.
    ld a, c
    add a, a
    ld hl, MusStart0
    call AddA
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a                     ; HL = 이 채널의 첫 사건
    ex de, hl                   ; DE = 첫 사건
    pop hl                      ; 포인터 자리 (상위)
    ld (hl), d
    dec hl
    ld (hl), e
    pop hl                      ; 남은 길이 자리
    ld (hl), 0
    ret

.play:
    ex de, hl                   ; DE = 다음 사건, HL = 주기
    push de
    ld a, c                     ; 주기: 채널 c 의 레지스터는 2c, 2c+1
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
