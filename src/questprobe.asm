;-----------------------------------------------------------------------------
; SCREEN 8 (GRAPHIC 7) 타진용 롬 - quest.rom 을 옮길 만한지 재 본다.
;
; quest.asm 은 SCREEN 5 (GRAPHIC 4, 한 바이트에 두 픽셀) 로 되어 있다. SCREEN 8
; 은 한 바이트가 한 픽셀이라 화면 자료가 그대로 두 배가 되고, VRAM 주소 계산은
; 오히려 간단해진다(y*256 + x). 그 정도는 종이에서 다 나온다.
;
; **종이에서 안 나오는 것은 대역폭 하나뿐이다.** GRAPHIC 6/7 은 VDP 가 한 줄에
; 두 배를 읽어 가서, 화면을 켜 둔 채로는 CPU 가 VRAM 을 만질 틈이 그만큼 줄어든
; 다고 알려져 있다. 그 최소 간격이 얼마인지에 따라 96x96 던전 뷰를 옮기는 데
; 드는 시간이 한 프레임이 되기도 하고 여덟 프레임이 되기도 한다. 그러면 옮길
; 만한 일인지 아닌지가 통째로 갈린다. 그래서 외워서 쓰지 않고 **잰다.**
;
; 재는 방법 - outi 뒤에 넣는 nop 수를 여섯 가지로 두고, 같은 그림을 각자 그린다.
;
;   변형  한 바이트에 드는 T   3.58MHz 기준
;    0    18 + 0  + 11 =  29     8.1 us
;    1    18 + 5  + 11 =  34     9.5 us   <- 지금 SCREEN 5 에서 쓰는 간격
;    2    18 + 15 + 11 =  44    12.3 us
;    3    18 + 30 + 11 =  59    16.5 us
;    4    18 + 50 + 11 =  79    22.1 us
;    5    18 + 80 + 11 = 109    30.5 us
;    6    outi 만 늘어놓기      19.4     5.4 us  <- 대조군. 이건 깨져야 한다
;
; T 는 MSX 의 M1 대기까지 넣은 값이다(명령어를 읽을 때마다 1 T 씩 더 든다).
; outi 는 ED 접두라 M1 이 둘이라 16+2, nop 은 4+1, jp 는 10+1.
;
; 변형 6 이 있는 이유 - "안 깨졌다"는 결과는 **에뮬레이터가 그 고장을 흉내내지
; 않아서**일 수도 있다. 확실히 너무 빠른 간격을 하나 넣어 두고, 그것이 깨지는지
; 본다. 그것마저 멀쩡하면 이 측정은 아무 말도 못 하는 것이다.
;
; 간격이 모자라면 VDP 가 쓰기를 **조용히 흘린다.** 화면만 봐서는 모른다. 그래서
;   - 먼저 온 화면을 POISON(0xFF) 으로 지우고,
;   - 0..95 로 커지는 그라데이션을 그린다(0xFF 와 절대 안 겹친다),
;   - 나중에 VRAM 을 되읽어 흘린 바이트를 센다.
; 화면을 찍어서는 안 되고 되읽어야 한다.
;
; 화면 배치
;   y   0..195  변형 일곱 개의 띠, 하나에 28 줄 (x 0..95)
;   y 196..203  지금 팔레트 16색을 GRB332 로 옮긴 견본
;   y 204..211  256색 전부
;   x 136..151, y 8..15 / 24..31  명령 엔진 좌표 확인용 사각형 두 개
;
; 시간은 롬 안에서 재지 않는다. BlitStart / BlitEnd 에 브레이크포인트를 걸고
; openMSX 의 machine_info time 을 빼면 된다 - 그쪽이 정확하고 코드도 안 는다.
;
; 이 롬은 quest.rom 과 아무것도 나눠 쓰지 않는다. 매퍼도 안 쓰는 16KB 짜리다.
;-----------------------------------------------------------------------------

    DEVICE NOSLOT64K

VDP_DATA    equ 0x98
VDP_ADDR    equ 0x99
VDP_CMD     equ 0x9B

VIEW_W      equ 96              ; 던전 뷰포트 - quest.asm 과 같은 크기
VIEW_H      equ 96
BAND_H      equ 28              ; 무결성 검사용 띠 하나의 높이
NVAR        equ 7
POISON      equ 0xFF            ; 지워 둘 색. 그라데이션(0..95)과 절대 안 겹친다
STRIP_Y     equ 196

PROBE_X     equ 136             ; 양피지 창이 시작하는 x - 실제로 쓰는 좌표다
PROBE_Y     equ 8
PROBE_W     equ 16
PROBE_H     equ 8
PROBE_COL   equ 0x1C            ; GRB332 로 새빨강 (G=0, R=7, B=0)
PROBE_DY    equ 24              ; HMMM 으로 옮겨 붙일 자리

STACK_TOP   equ 0xF380

;--- 작업용 RAM ----------------------------------------------------------------
    ORG 0xC000
RamStart:
Variant     ds 1                ; 지금 재고 있는 변형 번호 (Tcl 이 읽는다)
curY        ds 1
lineCnt     ds 1
swIdx       ds 1
LoopPtr     ds 2                ; 변형별 안쪽 고리 주소. 롬이라 코드를 못 고친다.
CmdFirst    ds 1
CmdBuf      ds 11               ; DX, DY, NX, NY, CLR, ARG, CMD
RamEnd:

;=============================================================================
    ORG 0x4000

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

    ld hl, RamStart
    ld de, RamStart + 1
    ld bc, RamEnd - RamStart - 1
    ld (hl), 0
    ldir

    call InitVdp
    ld a, 0x40                  ; 화면 켜기 - **켠 채로** 재야 뜻이 있다
    ld c, 1
    call WriteVdpReg

    call ClearAll               ; 온 화면을 POISON 으로
    call CmdProbe               ; 명령 엔진 좌표 확인

    ; 1. 시간 재기 - 변형마다 96x96 을 통째로 한 번씩
    xor a
.tloop:
    push af
    call TimeOne
    pop af
    inc a
    cp NVAR
    jr c, .tloop

    ; 1b. 같은 넓이를 **VDP 명령 엔진**에 시키면 얼마나 걸리나.
    ; Z80 이 한 바이트씩 미는 대신 VDP 가 옮기게 하면 자료를 롬이 아니라 VRAM 에
    ; 둘 수 있다(SCREEN 8 페이지 0 이 64KB 라 128KB 중 64KB 가 남는다).
    ; 그러면 롬 자리 문제가 통째로 없어진다. 될 만한 이야기인지 재 본다.
    call CmdBlitTest

    call DrawScreen             ; 2. 무결성 - 변형마다 제 띠에 BAND_H 줄
    call Canary

ProbeDone:                      ; Tcl 이 여기서 VRAM 을 통째로 덤프한다
    nop

    ; --- 아래는 덤프가 끝난 **뒤에** 한다 ------------------------------------
    ; 너무 빠른 **읽기**. 쓰기는 VDP 가 한 바이트 물고 있어 넘어갈 수도 있지만
    ; 읽기는 그럴 수가 없다. 읽기에서 걸리면 이 에뮬레이터가 이 고장을 보기는
    ; 보는 것이고, 그러면 쓰기가 안 걸린 것도 뜻이 있는 결과가 된다.
CanaryRStart:
    call CanaryRead
CanaryREnd:

    ; 명령 엔진이 도는 **중에** 같은 간격으로 쓴다. openMSX 의
    ; too_fast_vram_access 가 보는 것이 화면 표시와의 다툼이 아니라 **명령
    ; 엔진과의 다툼**일 수도 있어서, 그 경우를 따로 만들어 본다.
CanaryCStart:
    call CanaryCmd
CanaryCEnd:

    ; 같은 쓰기 카나리아를 GRAPHIC 4 에서도. G4 의 29 T 제한은 문서에 있는
    ; 값이라, 12 T 짜리 쓰기가 거기서도 안 걸리면 쓰기는 아예 안 보는 것이다.
    ;
    ; 이것을 덤프 뒤로 미룬 이유: G6/G7 은 VRAM 두 칩에 **번갈아** 담는다.
    ; 모드를 바꿨다 되돌리면 물리 배치가 달라져서 화면이 통째로 어긋난다.
    ; 덤프 전에 했다가 온 화면이 두 칸씩 밀려 나온 적이 있다.
    ld a, 0x06
    ld c, 0
    call WriteVdpReg
Canary4Start:
    call Canary
Canary4End:

    ; 눈으로 보라고 만든 화면이니 마지막에는 제대로 남겨 둔다. 모드를 오갔더니
    ; VRAM 배치가 어긋나 있으므로 G7 으로 되돌리고 다시 그린다.
    ld a, 0x0E
    ld c, 0
    call WriteVdpReg
    call DrawScreen

AllDone:
    jr AllDone

;-----------------------------------------------------------------------------
; VDP 명령 엔진으로 같은 넓이(96x96 = 9,216 픽셀)를 다루면 얼마나 걸리나.
;
;   HMMM  VRAM 안에서 복사 - 벽면을 미리 VRAM 에 구워 두고 오려 붙이는 방식
;   HMMV  단색 채우기      - 통로 끝의 어둠처럼 넓고 평평한 자리
;
; 둘 다 Z80 은 명령 열몇 바이트만 쏟아붓고 기다린다. 여기서는 끝날 때까지
; 기다린 시간을 재지만, 실제로는 그동안 CPU 가 딴 일을 할 수 있다는 것이 요점이다.
;-----------------------------------------------------------------------------
CmdBlitTest:
HmmmStart:
    ld hl, CmdBigCopy
    ld a, 32
    ld b, 15
    call SendCmd
    call WaitVdpCmd
HmmmEnd:                        ; 여기가 곧 HMMV 의 시작이다
    ld hl, CmdBigFill
    ld a, 36
    ld b, 11
    call SendCmd
    call WaitVdpCmd
HmmvEnd:
    ret

CmdBigCopy:                     ; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
    dw 0
    dw 100                      ; 아래쪽 아무 데나 - 내용은 상관없다
    dw 0
    dw 0
    dw VIEW_W
    dw VIEW_H
    db 0
    db 0
    db 0xD0                     ; HMMM

CmdBigFill:                     ; R#36 부터: DX, DY, NX, NY, CLR, ARG, CMD
    dw 0
    dw 0
    dw VIEW_W
    dw VIEW_H
    db 0x33
    db 0
    db 0xC0                     ; HMMV

;-----------------------------------------------------------------------------
; 눈에 보이는 화면 - 변형마다 제 띠, 그 아래 색 견본.
;
; 시간 재는 고리와 따로 두었다. 카나리아가 화면 모드를 오가면 VRAM 배치가
; 어긋나므로, 끝나고 한 번 더 불러 제대로 된 그림을 남긴다.
;-----------------------------------------------------------------------------
DrawScreen:
    call ClearAll
    call CmdProbe
    xor a
.loop:
    push af
    call BandOne
    pop af
    inc a
    cp NVAR
    jr c, .loop
    jp ColourStrip

;-----------------------------------------------------------------------------
; A = 변형 번호. 96 줄 통째로 한 번 - 이 구간의 시간을 Tcl 이 잰다.
;-----------------------------------------------------------------------------
TimeOne:
    call SetVar
    xor a
    ld (curY), a
    ld a, VIEW_H
    ld (lineCnt), a
BlitStart:                      ; 브레이크포인트 1
    call BlitLines
BlitEnd:                        ; 브레이크포인트 2
    ret

;-----------------------------------------------------------------------------
; A = 변형 번호. 제 띠에만 그린다. 되읽어서 흘린 바이트를 센다.
;-----------------------------------------------------------------------------
BandOne:
    call SetVar
    ld l, a                     ; y = 변형 * BAND_H
    ld h, 0
    ld de, BandY
    add hl, de
    ld a, (hl)
    ld (curY), a
    ld a, BAND_H
    ld (lineCnt), a
    jp BlitLines

;-----------------------------------------------------------------------------
; A = 변형 번호 -> LoopPtr. A 는 그대로 돌려준다.
;-----------------------------------------------------------------------------
SetVar:
    ld (Variant), a
    push af
    add a, a
    ld l, a
    ld h, 0
    ld de, VarTab
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (LoopPtr), de
    pop af
    ret

;-----------------------------------------------------------------------------
; curY 부터 lineCnt 줄, 한 줄에 VIEW_W 바이트를 x=0 에 그린다.
;
; GRAPHIC 7 은 주소가 그냥 y*256 + x 다. GRAPHIC 4 에서 하던 "y*128 + x/2" 의
; 시프트가 통째로 없어진다 - 옮기면 여기는 오히려 짧아진다.
;-----------------------------------------------------------------------------
BlitLines:
.line:
    ld a, (curY)
    ld h, a
    ld l, 0
    call SetVramWrite
    ld hl, Gradient
    ld b, VIEW_W
    ld c, VDP_DATA
    ld de, (LoopPtr)
    call CallDE
    ld hl, curY
    inc (hl)
    ld hl, lineCnt
    dec (hl)
    jr nz, .line
    ret

; DE 로 뛴다. 돌아올 주소는 call 이 이미 쌓아 두었으므로 ret 하나면 된다.
CallDE:
    push de
    ret

;-----------------------------------------------------------------------------
; 눈금 확인용 카나리아
;
; 위의 "한 바이트도 안 흘렸다"가 **정말 괜찮아서**인지 **에뮬레이터가 그 고장을
; 안 흉내내서**인지 가려야 한다. 그러려면 어떤 화면 모드에서도 확실히 너무 빠른
; 쓰기를 하나 넣고, 그것이 걸리는지 본다.
;
; out (n),a 는 11 T + M1 대기 1 = 12 T (3.35 us) 로, outi(18 T) 보다도 짧다.
; 값이 늘 같아서 되읽기로는 흘린 것을 못 세지만, openMSX 의
; too_fast_vram_access 는 울려야 한다. 안 울리면 이 측정은 아무 말도 못 한다.
;
; 화면에 안 나오는 자리(0xE000, 212줄 = 0xD400 보다 위)에 쓴다.
;-----------------------------------------------------------------------------
Canary:
    ld hl, 0xE000
    call SetVramWrite
    ld a, 0x33
    ld b, 12                    ; 12 * 8 = 96 번
CanaryStart:
.l:
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    djnz .l
CanaryEnd:
    ret

; 명령이 도는 중에 같은 간격으로 쓴다. 채우는 자리는 화면 밖(y=212 아래)이라
; 눈에 보이는 것은 안 건드린다 - 이 롬은 마지막 화면을 찍어 보는 용도도 겸한다.
CanaryCmd:
    ld hl, CmdOffscreen
    ld a, 36
    ld b, 11
    call SendCmd                ; 기다리지 않고 돌아온다. 명령은 계속 돈다.
    ld hl, 0xE000
    call SetVramWrite
    ld a, 0x55
    ld b, 12
.l:
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    out (VDP_DATA), a
    djnz .l
    jp WaitVdpCmd

CmdOffscreen:
    dw 0
    dw 212                      ; 화면 아래 - 212 줄까지만 보인다
    dw 256
    dw 40
    db 0x55
    db 0
    db 0xC0                     ; HMMV

; 같은 것을 읽기로. VRAM 을 읽기 모드로 잡고 12 T 간격으로 빨아들인다.
CanaryRead:
    ld hl, 0
    call SetVramRead
    ld b, 12
.l:
    in a, (VDP_DATA)
    in a, (VDP_DATA)
    in a, (VDP_DATA)
    in a, (VDP_DATA)
    in a, (VDP_DATA)
    in a, (VDP_DATA)
    in a, (VDP_DATA)
    in a, (VDP_DATA)
    djnz .l
    ret

;-----------------------------------------------------------------------------
; 변형별 안쪽 고리. HL = 원본, B = 바이트 수, C = VDP_DATA.
;
; nop 은 플래그를 안 건드리므로 jp nz 는 outi 가 만든 Z 를 그대로 본다.
; ds n, 0 은 nop 을 n 개 박는 것과 같다(0x00 = nop).
;-----------------------------------------------------------------------------
VarTab:
    dw Var0, Var1, Var2, Var3, Var4, Var5, Var6

BandY:
    db 0*BAND_H, 1*BAND_H, 2*BAND_H, 3*BAND_H
    db 4*BAND_H, 5*BAND_H, 6*BAND_H

Var0:                           ; 29 T
    outi
    jp nz, Var0
    ret
Var1:                           ; 34 T - 지금 SCREEN 5 에서 쓰는 간격
    outi
    nop
    jp nz, Var1
    ret
Var2:                           ; 44 T
    outi
    ds 3, 0
    jp nz, Var2
    ret
Var3:                           ; 59 T
    outi
    ds 6, 0
    jp nz, Var3
    ret
Var4:                           ; 79 T
    outi
    ds 10, 0
    jp nz, Var4
    ret
Var5:                           ; 109 T
    outi
    ds 16, 0
    jp nz, Var5
    ret

; 대조군. outi 만 늘어놓아 한 바이트에 19.4 T(5.4 us)까지 내린다. VIEW_W 가 8 의
; 배수라 딱 떨어진다. 이것까지 멀쩡하면 에뮬레이터가 이 고장을 안 흉내내는 것이고,
; 그러면 위의 "안 깨졌다"는 결과도 아무 뜻이 없다.
Var6:
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    outi
    jp nz, Var6
    ret

;-----------------------------------------------------------------------------
; 명령 엔진 좌표 확인
;
; 양피지 창(MsgClear / MsgScroll / MenuClear)은 전부 명령 엔진으로 돌아간다.
; GRAPHIC 4 에서는 CLR 한 바이트가 픽셀 **둘**이라 COL_CREAM * 17 로 써 왔다.
; GRAPHIC 7 에서 한 바이트가 한 픽셀이 맞는지, x 가 여전히 픽셀 단위인지를
; 사각형 하나 칠하고 되읽어서 확인한다. HMMM 도 같이 본다.
;-----------------------------------------------------------------------------
CmdProbe:
    ld hl, CmdFill
    ld a, 36
    ld b, 11
    call SendCmd
    ld hl, CmdCopy
    ld a, 32
    ld b, 15
    call SendCmd
    jp WaitVdpCmd

CmdFill:                        ; R#36 부터: DX, DY, NX, NY, CLR, ARG, CMD
    dw PROBE_X
    dw PROBE_Y
    dw PROBE_W
    dw PROBE_H
    db PROBE_COL
    db 0
    db 0xC0                     ; HMMV

CmdCopy:                        ; R#32 부터: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
    dw PROBE_X
    dw PROBE_Y
    dw PROBE_X
    dw PROBE_DY
    dw PROBE_W
    dw PROBE_H
    db 0
    db 0
    db 0xD0                     ; HMMM

ClearAll:
    ld hl, CmdWipe
    ld a, 36
    ld b, 11
    call SendCmd
    jp WaitVdpCmd

CmdWipe:
    dw 0
    dw 0
    dw 256
    dw 212
    db POISON
    db 0
    db 0xC0                     ; HMMV

;-----------------------------------------------------------------------------
; 눈으로 볼 견본
;
;   위 8 줄  지금 팔레트 16색을 GRB332 로 옮긴 것 (한 칸 16 픽셀)
;   아래 8 줄  256색 전부
;
; SCREEN 8 에는 팔레트가 없다. 색은 GRB332 로 못박혀 있어서 R 과 G 는 3 비트
; 그대로 옮겨 가고 B 만 3 비트에서 2 비트로 준다. 그림이 얼마나 상하는지는
; 말로 할 것이 아니라 나란히 놓고 봐야 한다.
;-----------------------------------------------------------------------------
ColourStrip:
    xor a
    ld (swIdx), a
.sw:
    ld a, (swIdx)
    add a, a
    add a, a
    add a, a
    add a, a                    ; x = 칸 번호 * 16
    ld (CmdBuf + 0), a
    xor a
    ld (CmdBuf + 1), a
    ld a, STRIP_Y
    ld (CmdBuf + 2), a
    xor a
    ld (CmdBuf + 3), a
    ld a, 16
    ld (CmdBuf + 4), a
    xor a
    ld (CmdBuf + 5), a
    ld a, 8
    ld (CmdBuf + 6), a
    xor a
    ld (CmdBuf + 7), a
    ld a, (swIdx)
    ld e, a
    ld d, 0
    ld hl, Pal332
    add hl, de
    ld a, (hl)
    ld (CmdBuf + 8), a          ; CLR
    xor a
    ld (CmdBuf + 9), a          ; ARG
    ld a, 0xC0
    ld (CmdBuf + 10), a         ; HMMV
    ld hl, CmdBuf
    ld a, 36
    ld b, 11
    call SendCmd
    ld hl, swIdx
    inc (hl)
    ld a, (hl)
    cp 16
    jr c, .sw
    call WaitVdpCmd

    ld a, STRIP_Y + 8
    ld (curY), a
    ld a, 8
    ld (lineCnt), a
.ramp:
    ld a, (curY)
    ld h, a
    ld l, 0
    call SetVramWrite
    ld hl, Ramp256
    ld b, 0                     ; 0 이면 256 회 돈다
    ld c, VDP_DATA
.r:
    outi
    ds 16, 0                    ; 여기는 재는 데가 아니라 넉넉히 준다
    jp nz, .r
    ld hl, curY
    inc (hl)
    ld hl, lineCnt
    dec (hl)
    jr nz, .ramp
    ret

;-----------------------------------------------------------------------------
; VDP 기본 루틴 - quest.asm 과 같다
;-----------------------------------------------------------------------------
; HL = 명령 블록, A = 시작 레지스터 번호, B = 바이트 수
SendCmd:
    ld (CmdFirst), a
    push hl
    push bc
    call WaitVdpCmd
    pop bc
    pop hl
    ld a, (CmdFirst)
    ld c, 17
    call WriteVdpReg
    ld c, VDP_CMD
    otir
    ret

; S#2 의 bit0 가 CE. 읽고 나서 R#15 를 반드시 0 으로 되돌린다.
WaitVdpCmd:
    ld a, 2
    ld c, 15
    call WriteVdpReg
.wait:
    in a, (VDP_ADDR)
    rrca
    jr c, .wait
    xor a
    ld c, 15
    jp WriteVdpReg

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

; HL = VRAM 주소. 읽기 모드로 설정한다. 쓰기와 달리 마지막 바이트의 bit6 이 0.
SetVramRead:
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

; 모드 비트는 R#0 의 M5,M4,M3 (bit3..1) 과 R#1 의 M2,M1 (bit4,3) 이다.
;   GRAPHIC 4 (SCREEN 5)  M5,M4,M3 = 0,1,1 -> R#0 = 0x06
;   GRAPHIC 7 (SCREEN 8)  M5,M4,M3 = 1,1,1 -> R#0 = 0x0E
VdpRegs:
    db 0x0E                     ; R#0  GRAPHIC 7 모드
    db 0x00                     ; R#1  일단 화면 끔
    db 0x1F                     ; R#2  비트맵 페이지 0 을 0x00000 에
    db 0xFF                     ; R#3
    db 0x03                     ; R#4
    db 0x00                     ; R#5  스프라이트 미사용
    db 0x00                     ; R#6
    db 0x00                     ; R#7  테두리 색. G7 에서는 팔레트가 아니라 GRB332
    db 0x0A                     ; R#8  VR=1(VRAM 128K), SPD=1 로 스프라이트 끔
    db 0x80                     ; R#9  212라인
    db 0x00                     ; R#10
    db 0x00                     ; R#11
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
    db 0x00                     ; R#23 수직 스크롤 없음
VdpRegsEnd:

;-----------------------------------------------------------------------------
; 자료
;-----------------------------------------------------------------------------
; 한 줄짜리 원본. 값이 픽셀마다 달라야 흘린 바이트가 눈에 띈다 - 단색으로 채우면
; 빠뜨려도 되읽어서 알 수가 없다.
Gradient:
    ; 0 .. VIEW_W-1
    dup VIEW_W
    db $ - Gradient
    edup

Ramp256:
    dup 256
    db $ - Ramp256
    edup

    include "src/questprobepal.asm"

    ds 0x8000 - $, 0xFF
    SAVEBIN "build/questprobe.rom", 0x4000, 0x4000
