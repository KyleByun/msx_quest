;-----------------------------------------------------------------------------
; 오른쪽 양피지 위의 Diablo 식 미니맵
;
; MapDataRam의 한 칸을 6x6 픽셀로 확대한다. 16x16이라 96x96이 되고,
; 메시지 창(102x104) 안에 맞는다. 벽은 회색, 통로는 검정, 현재 위치는
; 패널색으로 표시한다. 한 맵 행을 48바이트만 RAM에 만들고 여섯 스캔라인에
; 반복 전송하므로 4,608바이트짜리 별도 화면 버퍼는 필요 없다.
;-----------------------------------------------------------------------------

MINIMAP_X       equ 144          ; 셀 하나 3바이트(6픽셀) * 16 = 96x96
MINIMAP_Y       equ 10
MINIMAP_CELL    equ 6            ; 한 칸의 픽셀 높이
MINIMAP_ROW_BYTES equ MAP_W * 3  ; 한 맵 행의 바이트 수 (셀당 3)

MINIMAP_WALL_BYTE  equ COL_SHADE * 17   ; 회색 두 픽셀
MINIMAP_FLOOR_BYTE equ COL_BLACK * 17   ; 검정 두 픽셀
MINIMAP_HERO_BYTE  equ COL_PANEL * 17   ; 현재 위치

; M 키가 새로 눌릴 때 지도 표시를 켜거나 끈다.
ToggleMap:
    ld a, (MapOn)
    xor 1
    ld (MapOn), a
    or a
    jr z, .off
    call MsgClear                ; 양피지를 비운 뒤 지도만 얹는다
    jp DrawMap
.off:
    jp MsgClear                  ; 이전 로그는 보관하지 않고 빈 양피지로 돌아간다

; 현재 RAM 지도를 양피지에 그린다. VDP 명령이 양피지를 지우는 중일 수 있으므로
; 먼저 끝날 때까지 기다린다. MapOn이 켜진 상태에서 던전이 다시 렌더돼도 이
; 루틴을 다시 불러 오버레이를 복원한다.
DrawMap:
    call WaitVdpCmd
    ld hl, MapDataRam
    xor a
    ld (MiniMapY), a
    ld a, MINIMAP_Y
    ld (MiniMapScreenY), a
    ld b, MAP_W
.maprow:
    push bc                     ; 남은 맵 행 수는 VRAM 전송 B와 분리한다
    ld de, MiniMapRow
    ld c, 0                      ; 현재 맵 x
.cell:
    ld a, (hl)
    inc hl
    or a
    jr nz, .wall

    ; 통로 위에 플레이어가 있으면 밝은 표시를 남긴다.
    ld a, (posX)
    cp c
    jr nz, .floor
    ld a, (posY)
    ld b, a
    ld a, (MiniMapY)
    cp b
    jr nz, .floor
    ld a, MINIMAP_HERO_BYTE
    jr .store
.floor:
    ld a, MINIMAP_FLOOR_BYTE
    jr .store
.wall:
    ld a, MINIMAP_WALL_BYTE
.store:
    ld (de), a                  ; 6픽셀 = 같은 색 두 픽셀 3바이트
    inc de
    ld (de), a
    inc de
    ld (de), a
    inc de
    inc c
    ld a, c
    cp MAP_W
    jr c, .cell

    push hl                     ; 다음 맵 행 포인터를 화면 전송 동안 지킨다
    ld a, (MiniMapScreenY)
    ld d, a
    ld b, MINIMAP_CELL
.scanline:
    push bc
    ld a, d
    ld e, MINIMAP_X / 2
    call RowAddrB
    call SetVramWrite
    ld hl, MiniMapRow
    ld b, MINIMAP_ROW_BYTES
    ld c, VDP_DATA
.write:
    outi
    nop
    jp nz, .write               ; 30 T-state - 화면이 켜진 V9938에도 안전
    pop bc
    inc d
    djnz .scanline
    pop hl
    pop bc
    ; HL에는 다음 지도 행 포인터가 복원돼 있다. 여기서 HL을 MiniMapY에 쓰면
    ; 둘째 행부터 작업 RAM을 지도처럼 읽게 되므로 A로만 행 번호를 갱신한다.
    ld a, (MiniMapY)
    inc a
    ld (MiniMapY), a
    ld a, (MiniMapScreenY)
    add a, MINIMAP_CELL
    ld (MiniMapScreenY), a
    djnz .maprow
    jp DrawCompass

;-----------------------------------------------------------------------------
; 나침반 - 미니맵 왼쪽 위 (맵 96x96 을 6x6 격자 위에 겹친다)
;
;   W   N   E   를 3x3 다이아몬드로 놓고 바라보는 방향만 패널색, 나머지는
;       S       어둡게. 글자 대신 6x6 픽셀 화살촉 모양을 쓴다.
;
; 칸 배치 (맵 좌상단, MINIMAP_X/MINIMAP_Y 기준):
;   (0,0)=W  (6,0)=N  (12,0)=E  (6,12)=S  - 각 6x6
; 바라보는 방향의 화살촉이 맵 중심(동쪽=+x)을 향하도록 방향별 6x6 패턴 4종을
; 둔다. 패턴은 4bpp 3바이트 x 6줄.
;-----------------------------------------------------------------------------

COMPASS_X   equ MINIMAP_X
COMPASS_Y   equ MINIMAP_Y

DrawCompass:
    ld a, (facing)
    add a, a
    add a, a                    ; facing * 4 (패턴 하나가 4바이트씩 6줄)
    ld e, a
    ld d, 0
    ld hl, CompassPat
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a                     ; HL = 그 방향의 패턴 주소

    ld a, (hl)                  ; 패턴 첫 바이트 = 그 방향 칸의 오프셋 (dx, dy)
    ld c, a                     ; dx*16 + dy 를 미리 구워 둔 값
    inc hl

    ld a, COMPASS_Y
    add a, c                    ; 세로 오프셋
    ld d, a
    ld b, 6                     ; 6줄
.line:
    push bc
    push hl
    ld a, d
    ld e, COMPASS_X / 2
    call RowAddrB
    call SetVramWrite
    pop hl
    ld b, 3
    ld c, VDP_DATA
.wr:
    outi
    nop
    jp nz, .wr
    pop bc
    inc d
    djnz .line
    ret

; 방향별 패턴 테이블. 각 항목: dw 패턴주소, db 위치코드, 18바이트 픽셀.
; 위치코드 = (칸dy * 16) + 칸dx. 칸은 6픽셀이므로 dx/dy 는 0, 6, 12.
; facing 0=북 1=동 2=남 3=서 (DirTab 과 같은 순서)
CompassPat:
    dw CompassN, CompassE, CompassS, CompassW

; 북쪽을 볼 때: N 칸(위, dx=6,dy=0)이 밝고 W(0,0) E(12,0) S(6,12)은 어둡다.
; 밝은 칸 = 패널색 두 픽셀, 어두운 칸 = 어두운 회색 두 픽셀.
; 화살촉은 위쪽(북)을 향하는 삼각형.
CompassN:
    db 6 * 16 + 0               ; N 칸 위치 (dx=6, dy=0)
    db 0x44, 0x40, 0x00         ; 줄1 - 중앙만 밝게
    db 0x44, 0x40, 0x00
    db 0x34, 0x43, 0x00         ; 줄3 - 조금 넓게
    db 0x23, 0x33, 0x00
    db 0x12, 0x22, 0x10
    db 0x00, 0x11, 0x10         ; 줄6 - 바닥

CompassE:
    db 12 * 16 + 0              ; E 칸 위치 (dx=12, dy=0)
    db 0x44, 0x40, 0x00
    db 0x44, 0x44, 0x00
    db 0x44, 0x44, 0x30
    db 0x44, 0x44, 0x30
    db 0x44, 0x44, 0x00
    db 0x44, 0x40, 0x00

CompassS:
    db 6 * 16 + 12              ; S 칸 위치 (dx=6, dy=12)
    db 0x00, 0x11, 0x10
    db 0x12, 0x22, 0x10
    db 0x23, 0x33, 0x00
    db 0x34, 0x43, 0x00
    db 0x44, 0x40, 0x00
    db 0x44, 0x40, 0x00

CompassW:
    db 0 * 16 + 0               ; W 칸 위치 (dx=0, dy=0)
    db 0x00, 0x04, 0x44
    db 0x00, 0x44, 0x44
    db 0x03, 0x44, 0x44
    db 0x03, 0x44, 0x44
    db 0x00, 0x44, 0x44
    db 0x00, 0x04, 0x44
