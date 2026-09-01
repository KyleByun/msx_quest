;-----------------------------------------------------------------------------
; 오른쪽 양피지 위의 Diablo 식 미니맵
;
; MapDataRam의 한 칸을 6x6 픽셀로 확대한다. 16x16이라 96x96이 되고,
; 메시지 창(102x104) 안에 맞는다. 벽은 회색, 통로는 검정이고, 내 자리에는
; 바라보는 방향 화살표를 파란색으로 얹는다(DrawHero). 한 맵 행을 48바이트만
; RAM에 만들고 여섯 스캔라인에 반복 전송하므로 4,608바이트짜리 별도 화면
; 버퍼는 필요 없다.
;-----------------------------------------------------------------------------

MINIMAP_X       equ 144          ; 셀 하나 3바이트(6픽셀) * 16 = 96x96
MINIMAP_Y       equ 10
MINIMAP_CELL    equ 6            ; 한 칸의 픽셀 높이
MINIMAP_ROW_BYTES equ MAP_W * 3  ; 한 맵 행의 바이트 수 (셀당 3)

MINIMAP_WALL_BYTE  equ COL_SHADE * 17   ; 회색 두 픽셀
MINIMAP_FLOOR_BYTE equ COL_BLACK * 17   ; 검정 두 픽셀

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
    ld a, MINIMAP_FLOOR_BYTE
    jr z, .store
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
    jp DrawHero

;-----------------------------------------------------------------------------
; 내 위치 - 지도의 내 칸에 바라보는 방향 화살표를 얹는다
;
; 예전에는 지도 왼쪽 위에 나침반을 따로 그렸다. 자리도 잡아먹고, 방향을 알려면
; 지도에서 눈을 떼야 했다. 내 칸에 바로 그리면 "어디에 있고 어디를 보는가"가
; 한 번에 읽힌다.
;
; 그 나침반은 애초에 제대로 그려지지도 않았다. 방향별 패턴 주소가 2바이트씩
; 늘어선 표인데 facing*4 로 짚고 있어서, 북쪽만 맞고 동쪽은 남쪽 모양이 나오고
; 남/서는 표 밖을 읽어 엉뚱한 VRAM 자리에 낙서를 했다. 화면 구석의 작은 그림이라
; 오래 눈치채지 못했다.
;
; 화살표 모양은 gfx/quest_convert.py 가 북쪽 하나만 적고 나머지 셋을 돌려서
; 만든다. 색은 COL_HERO(파랑) - 지도가 회색과 검정뿐이라 눈에 바로 띈다.
;-----------------------------------------------------------------------------
DrawHero:
    ld a, (facing)              ; 표 항목이 주소 2바이트씩이다
    add a, a
    ld e, a
    ld d, 0
    ld hl, HeroArrowPtr
    add hl, de
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a                     ; HL = 그 방향의 패턴

    ld a, (posX)                ; 바이트 x = (MINIMAP_X + posX*6) / 2
    ld b, a
    add a, a
    add a, b                    ; posX * 3
    add a, MINIMAP_X / 2
    ld (HeroXb), a

    ld a, (posY)                ; 화면 y = MINIMAP_Y + posY*6
    ld b, a
    add a, a
    add a, b
    add a, a                    ; posY * 6
    add a, MINIMAP_Y
    ld d, a

    ld b, MINIMAP_CELL
.line:
    push bc
    push hl
    ld a, (HeroXb)
    ld e, a
    ld a, d
    call RowAddrB
    call SetVramWrite
    pop hl
    ld b, MINIMAP_CELL / 2      ; 6 픽셀 = 3 바이트
    ld c, VDP_DATA
.wr:
    outi
    nop
    jp nz, .wr
    pop bc
    inc d
    djnz .line
    ret
