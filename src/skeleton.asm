;-----------------------------------------------------------------------------
; MSX2 최소 예제 - SCREEN 5 (GRAPHIC 4) + 스프라이트 모드 2
;
; 0x4000(페이지 1)에 매핑되는 16KB 카트리지 ROM. 매퍼도 슬롯 전환도 없음.
; BIOS 호출 대신 VDP를 직접 제어한다. openMSX에 내장된 C-BIOS가 MSX BIOS를
; 일부만 구현하고 있기 때문이다.
;
; 빌드: build.ps1   실행: run.ps1   창 없이 확인: verify.ps1
;-----------------------------------------------------------------------------

    DEVICE NOSLOT64K

;--- VDP 입출력 포트 (모든 MSX에서 동일) ---------------------------------------
VDP_DATA    equ 0x98            ; VRAM 데이터 읽기/쓰기
VDP_ADDR    equ 0x99            ; 레지스터/주소 쓰기, 상태 읽기
VDP_PALETTE equ 0x9A            ; 팔레트 데이터
VDP_REGIND  equ 0x9B            ; 레지스터 간접 접근

;--- SCREEN 5 VRAM 배치, 페이지 0 ----------------------------------------------
; 비트맵이 라인당 128바이트 x 212라인 = 0x6A00바이트이므로, 0x7400부터의
; 스프라이트 테이블은 그 위에 안전하게 자리잡는다.
BITMAP_BASE equ 0x0000
SPR_COLOUR  equ 0x7400          ; 스프라이트 모드 2 색 테이블 (스프라이트당 16바이트)
SPR_ATTR    equ 0x7600          ; 스프라이트 속성 테이블 (스프라이트당 4바이트)
SPR_PATTERN equ 0x7800          ; 스프라이트 패턴 제너레이터 (16x16 하나당 32바이트)

SCR_W_BYTES equ 128             ; 256픽셀 / 바이트당 2픽셀
SCR_LINES   equ 212

SPR_END_Y   equ 216             ; 스프라이트 목록을 끝내는 Y 값

;--- 이동 한계 (화면 크기에서 16x16 스프라이트를 뺀 값) ------------------------
X_LIMIT     equ 241             ; 유효한 X는 0..240
Y_LIMIT     equ 197             ; 유효한 Y는 0..196

;--- 작업용 RAM ----------------------------------------------------------------
; 페이지 3(0xC000-0xFFFF)은 모든 MSX에서 RAM이고, 카트리지 INIT이 돌 때
; 이미 매핑되어 있다. 0xF380 위쪽은 BIOS 작업 영역이다.
sprX        equ 0xC000
sprY        equ 0xC001
dirX        equ 0xC002
dirY        equ 0xC003

STACK_TOP   equ 0xF380

    ORG 0x4000

;-----------------------------------------------------------------------------
; 카트리지 ROM 헤더 (16바이트)
;-----------------------------------------------------------------------------
    db "AB"                     ; ROM 식별자
    dw Init                     ; INIT   - 진입점. 부팅 시 호출된다
    dw 0                        ; STATEMENT - BASIC CALL 처리기 (미사용)
    dw 0                        ; DEVICE - 장치 확장 (미사용)
    dw 0                        ; TEXT   - BASIC 프로그램 본문 (미사용)
    ds 6, 0                     ; 예약 영역

;-----------------------------------------------------------------------------
; 진입점
;-----------------------------------------------------------------------------
Init:
    di                          ; vblank를 폴링해서 쓰므로 인터럽트를 끈다
    ld sp, STACK_TOP

    call InitScreen5            ; 이 시점에는 아직 화면 출력이 꺼져 있다
    call FillBands
    call InitSprite

    ld a, 120
    ld (sprX), a
    ld a, 90
    ld (sprY), a
    ld a, 1
    ld (dirX), a
    ld a, 1
    ld (dirY), a

    ld a, 0x42                  ; 화면 켜기, 16x16 스프라이트, VDP 인터럽트 끔
    ld c, 1
    call WriteVdpReg

MainLoop:
    call WaitVBlank
    call MoveSprite
    call UpdateSpriteAttr
    jr MainLoop

;-----------------------------------------------------------------------------
; InitScreen5 - VDP 레지스터 R#0..R#23을 쓴다
;-----------------------------------------------------------------------------
InitScreen5:
    ld hl, Screen5Regs
    ld c, 0                     ; 레지스터 번호
    ld b, Screen5RegsEnd - Screen5Regs
.loop:
    ld a, (hl)
    inc hl
    out (VDP_ADDR), a           ; 값을 먼저 쓰고...
    ld a, c
    or 0x80                     ; ...그다음 0x80 | 레지스터 번호
    out (VDP_ADDR), a
    inc c
    djnz .loop
    ret

Screen5Regs:
    db 0x06                     ; R#0  M5=0 M4=1 M3=1 -> GRAPHIC 4
    db 0x02                     ; R#1  일단 화면 끔, 16x16 스프라이트
    db 0x1F                     ; R#2  비트맵 시작 = 0x00000 (페이지 0)
    db 0xFF                     ; R#3  색 테이블 하위 (G4에서는 미사용)
    db 0x03                     ; R#4  패턴 제너레이터 (G4에서는 미사용)
    db 0xEF                     ; R#5  스프라이트 색 테이블 0x7400, 속성 0x7600
    db 0x0F                     ; R#6  스프라이트 패턴 제너레이터 = 0x7800
    db 0x00                     ; R#7  테두리 색
    db 0x08                     ; R#8  VR=1 (VRAM 64Kx8), 스프라이트 켬
    db 0x80                     ; R#9  LN=1 -> 212라인
    db 0x00                     ; R#10 색 테이블 상위
    db 0x00                     ; R#11 스프라이트 속성 테이블 상위
    db 0x00                     ; R#12
    db 0x00                     ; R#13
    db 0x00                     ; R#14 VRAM 주소 A16-A14
    db 0x00                     ; R#15 상태 레지스터 선택 = S#0
    db 0x00                     ; R#16
    db 0x00                     ; R#17
    db 0x00                     ; R#18
    db 0x00                     ; R#19
    db 0x00                     ; R#20
    db 0x00                     ; R#21
    db 0x00                     ; R#22
    db 0x00                     ; R#23 수직 스크롤 오프셋
Screen5RegsEnd:

;-----------------------------------------------------------------------------
; FillBands - 비트맵 전체에 16라인짜리 가로 색 띠를 그린다
;
; VRAM 주소 카운터가 17비트 전체에 걸쳐 자동 증가하므로, 27136바이트를
; 쓰는 동안 주소는 한 번만 설정하면 된다.
;-----------------------------------------------------------------------------
FillBands:
    ld hl, BITMAP_BASE
    call SetVramWrite
    ld d, SCR_LINES             ; 남은 라인 수
    ld e, 0                     ; 현재 라인
.line:
    ld a, e
    rrca
    rrca
    rrca
    rrca
    and 0x0F                    ; 색 = 라인 / 16
    ld b, a
    rlca
    rlca
    rlca
    rlca
    or b                        ; 상하위 니블에 같은 색 = 2픽셀
    ld c, a
    ld b, SCR_W_BYTES
.byte:
    ld a, c
    out (VDP_DATA), a
    nop                         ; VRAM 쓰기 간격을 29 T-state 이상으로 유지
    djnz .byte
    inc e
    dec d
    jr nz, .line
    ret

;-----------------------------------------------------------------------------
; InitSprite - 패턴과 라인별 색을 올리고 속성 테이블을 정리한다
;-----------------------------------------------------------------------------
InitSprite:
    ld hl, SpritePattern
    ld de, SPR_PATTERN
    ld b, SpritePatternEnd - SpritePattern
    call BlockToVram

    ld hl, SpriteColours
    ld de, SPR_COLOUR
    ld b, SpriteColoursEnd - SpriteColours
    call BlockToVram

    ; 스프라이트 0은 UpdateSpriteAttr가 매 프레임 그린다. 스프라이트 1에는
    ; 목록 종료 표시를 넣어 나머지 30개가 표시되지 않게 한다.
    ld hl, SPR_ATTR + 4
    call SetVramWrite
    ld a, SPR_END_Y
    out (VDP_DATA), a
    ret

; 16x16 공. 0-15바이트가 왼쪽 절반(0-15행), 16-31이 오른쪽 절반이다.
SpritePattern:
    db 0x03, 0x0F, 0x1F, 0x3F, 0x7F, 0x7F, 0xFF, 0xFF
    db 0xFF, 0xFF, 0x7F, 0x7F, 0x3F, 0x1F, 0x0F, 0x03
    db 0xC0, 0xF0, 0xF8, 0xFC, 0xFE, 0xFE, 0xFF, 0xFF
    db 0xFF, 0xFF, 0xFE, 0xFE, 0xFC, 0xF8, 0xF0, 0xC0
SpritePatternEnd:

; 스프라이트 모드 2는 라인마다 색을 따로 준다. 행당 1바이트.
SpriteColours:
    db 15, 15, 15, 15           ; 흰색
    db 14, 14, 14, 14           ; 회색
    db  9,  9,  9,  9           ; 밝은 빨강
    db  8,  8,  8,  8           ; 중간 빨강
SpriteColoursEnd:

;-----------------------------------------------------------------------------
; MoveSprite - 프레임당 1픽셀 이동, 화면 끝에서 방향을 뒤집는다
;-----------------------------------------------------------------------------
MoveSprite:
    ld a, (dirX)
    ld b, a
    ld a, (sprX)
    add a, b
    ld (sprX), a
    cp X_LIMIT                  ; 0 아래로 내려가 255로 감기는 경우도 함께 걸러진다
    jr c, .xdone
    ld a, b
    neg
    ld (dirX), a
.xdone:
    ld a, (dirY)
    ld b, a
    ld a, (sprY)
    add a, b
    ld (sprY), a
    cp Y_LIMIT
    jr c, .ydone
    ld a, b
    neg
    ld (dirY), a
.ydone:
    ret

;-----------------------------------------------------------------------------
; UpdateSpriteAttr - 스프라이트 0의 속성 4바이트를 쓴다
;-----------------------------------------------------------------------------
UpdateSpriteAttr:
    ld hl, SPR_ATTR
    call SetVramWrite
    ld a, (sprY)
    out (VDP_DATA), a
    nop
    ld a, (sprX)
    out (VDP_DATA), a
    nop
    xor a
    out (VDP_DATA), a           ; 패턴 번호 (16x16은 4의 배수)
    nop
    xor a
    out (VDP_DATA), a           ; 스프라이트 모드 2에서는 미사용
    ret

;-----------------------------------------------------------------------------
; WaitVBlank - 상태 레지스터 S#0의 수직 귀선 플래그를 폴링한다
;
; S#0은 읽으면 플래그가 지워지므로 인터럽트를 끈 상태로 돌려야 한다.
; 인터럽트 핸들러가 상태를 먼저 읽으면 플래그를 가로채 버린다.
;-----------------------------------------------------------------------------
WaitVBlank:
    in a, (VDP_ADDR)
    and 0x80
    jr z, WaitVBlank
    ret

;-----------------------------------------------------------------------------
; BlockToVram - HL(ROM)에서 DE(VRAM)로 B바이트를 복사한다
;-----------------------------------------------------------------------------
BlockToVram:
    push hl
    ld h, d
    ld l, e
    call SetVramWrite
    pop hl
.loop:
    ld a, (hl)
    inc hl
    out (VDP_DATA), a
    djnz .loop
    ret

;-----------------------------------------------------------------------------
; SetVramWrite - VDP를 VRAM 주소 HL의 쓰기 모드로 맞춘다
; HL은 보존, A와 C는 파괴. A16 = 0(VRAM 64K 미만)을 전제로 한다.
;-----------------------------------------------------------------------------
SetVramWrite:
    ld a, h
    rlca
    rlca
    and 0x03                    ; A15, A14
    ld c, 14
    call WriteVdpReg
    ld a, l
    out (VDP_ADDR), a           ; A7-A0
    ld a, h
    and 0x3F
    or 0x40                     ; A13-A8과 쓰기 활성화 비트
    out (VDP_ADDR), a
    ret

;-----------------------------------------------------------------------------
; WriteVdpReg - VDP 레지스터 C에 A를 쓴다
;-----------------------------------------------------------------------------
WriteVdpReg:
    out (VDP_ADDR), a
    ld a, c
    or 0x80
    out (VDP_ADDR), a
    ret

;-----------------------------------------------------------------------------
; 경로는 현재 작업 디렉터리 기준이다. build.ps1이 어셈블러를 부르기 전에
; 프로젝트 루트로 옮겨 준다.
    SAVEBIN "build/skeleton.rom", 0x4000, 0x4000
