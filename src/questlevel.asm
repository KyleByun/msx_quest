;-----------------------------------------------------------------------------
; 실행 시간 던전 맵 생성
;
; NetHack 5의 일반 레벨 생성에서 필요한 뼈대만 16x16 격자에 맞춰 옮겼다.
;
;   makelevel()  -> MakeLevel
;   makerooms()  -> 빈 벽 지도에 겹치지 않는 사각 방을 반복 배치
;   makecorridors() -> 새 방을 직전 방과 L자 통로로 연결
;
; NetHack의 방 구조체, 문, 특수 레벨, 아이템/몬스터 배치는 이 화면과 게임 규칙에
; 아직 없으므로 가져오지 않는다. 모든 방을 직전 방에 연결하므로 생성이 끝난 맵은
; 언제나 시작 방에서 도달 가능하다. 계단/다음 층을 넣을 때도 MakeLevel을 다시
; 부르면 된다.
;
; MapDataRam: 1=벽, 0=통로. 렌더러의 IsWall이 이 RAM 지도를 읽는다.
;-----------------------------------------------------------------------------

; MSX2 표준 RTC의 시간(BCD 니블)과 Z80 refresh register를 섞어 xorshift의
; 초기값으로 쓴다. RTC는 배터리로 계속 가므로 재부팅해도 같은 고정 시드가 되지
; 않는다. MODE #13에 8을 써 block 0(시각)과 시계 동작을 선택한다.
RTC_ADDR    equ 0xB4
RTC_DATA    equ 0xB5

SeedRng:
    ld a, 13
    out (RTC_ADDR), a
    ld a, 8
    out (RTC_DATA), a

    ld a, 0                     ; 초의 일의 자리
    out (RTC_ADDR), a
    in a, (RTC_DATA)
    ld l, a

    ld a, 2                     ; 분의 일의 자리
    out (RTC_ADDR), a
    in a, (RTC_DATA)
    rlca
    rlca
    rlca
    rlca
    xor l
    ld l, a

    ld a, 4                     ; 시의 일의 자리
    out (RTC_ADDR), a
    in a, (RTC_DATA)
    ld h, a

    ld a, 7                     ; 일자의 일의 자리
    out (RTC_ADDR), a
    in a, (RTC_DATA)
    rlca
    rlca
    xor h
    ld h, a

    ld a, r                     ; 부팅 시점의 CPU 위상도 조금 섞는다
    xor h
    ld h, a
    ld a, h
    or l
    jr nz, .nonzero             ; xorshift는 0을 시드로 쓸 수 없다
    ld hl, 0xACE1
.nonzero:
    ld (Seed), hl
    ret

; 빈 벽 지도를 만들고 3~6개의 방을 배치한다. 방 하나가 놓일 때마다 직전 방과
; 연결하므로, NetHack makecorridors()의 가장 중요한 연결성 보장을 유지한다.
MakeLevel:
    ld hl, MapDataRam
    ld de, MapDataRam + 1
    ld bc, MAP_W * MAP_W - 1
    ld (hl), 1
    ldir

    xor a
    ld (RoomCount), a
    ld c, 4
    call RandMod
    add a, 3                    ; 목표 방 수 = 3~6
    ld (RoomTarget), a

.nextroom:
    ld a, (RoomCount)
    ld b, a
    ld a, (RoomTarget)
    cp b
    ret z

    ld a, 32                    ; 작은 16x16 맵에서 한 방을 놓아 볼 횟수
    ld (RoomAttempts), a
.try:
    call PickRoom
    call CanPlaceRoom
    jr nc, .place
    ld hl, RoomAttempts
    dec (hl)
    jr nz, .try
    ret                         ; 더 넣을 자리가 없으면 연결된 현재 맵을 쓴다

.place:
    call CarveRoom
    ld a, (RoomCount)
    or a
    jr nz, .link

    ; 첫 방의 중심이 플레이어 시작 위치다. 고정 (1,13) 위치에 벽이 생기는 일을
    ; 막고, 어떤 생성 결과에서도 정상적으로 시작하게 한다.
    ld a, (RoomCX)
    ld (posX), a
    ld (PrevRoomX), a
    ld a, (RoomCY)
    ld (posY), a
    ld (PrevRoomY), a
    jr .stored

.link:
    call LinkRooms
    ld a, (RoomCX)
    ld (PrevRoomX), a
    ld a, (RoomCY)
    ld (PrevRoomY), a
.stored:
    ld hl, RoomCount
    inc (hl)
    jr .nextroom

; 방 크기와 위치를 고른다. 외곽 한 칸은 항상 벽으로 남긴다.
PickRoom:
    ld c, 4
    call RandMod
    add a, 2                    ; 폭 2~5
    ld (RoomW), a
    ld c, 3
    call RandMod
    add a, 2                    ; 높이 2~4
    ld (RoomH), a

    ld a, 15
    ld hl, RoomW
    sub (hl)
    ld c, a
    call RandMod
    inc a
    ld (RoomX), a

    ld a, 15
    ld hl, RoomH
    sub (hl)
    ld c, a
    call RandMod
    inc a
    ld (RoomY), a
    ret

; 방과 그 주위 한 칸이 모두 벽인지 검사한다.
; 성공=carry clear, 다른 방/통로와 닿으면 carry set.
CanPlaceRoom:
    ld a, (RoomY)
    dec a
    ld c, a                     ; 검사할 현재 y
    ld a, (RoomH)
    add a, 2
    ld b, a                     ; 검사할 줄 수
.row:
    push bc
    ld a, c
    add a, a
    add a, a
    add a, a
    add a, a                    ; y * 16
    ld l, a
    ld h, 0
    ld de, MapDataRam
    add hl, de
    ld a, (RoomX)
    dec a
    add a, l
    ld l, a
    ld a, (RoomW)
    add a, 2
    ld e, a                     ; 검사할 칸 수
.cell:
    ld a, (hl)
    or a
    jr z, .blocked
    inc hl
    dec e
    jr nz, .cell
    pop bc
    inc c
    djnz .row
    or a                        ; carry clear
    ret
.blocked:
    pop bc
    scf
    ret

; 고른 사각형을 바닥으로 파고, 중심 좌표를 RoomCX/RoomCY에 남긴다.
CarveRoom:
    ld a, (RoomY)
    ld c, a
    ld a, (RoomH)
    ld b, a
.row:
    push bc
    ld a, c
    add a, a
    add a, a
    add a, a
    add a, a
    ld l, a
    ld h, 0
    ld de, MapDataRam
    add hl, de
    ld a, (RoomX)
    add a, l
    ld l, a
    ld a, (RoomW)
    ld e, a
.cell:
    xor a
    ld (hl), a
    inc hl
    dec e
    jr nz, .cell
    pop bc
    inc c
    djnz .row

    ld a, (RoomW)
    srl a
    ld hl, RoomX
    add a, (hl)
    ld (RoomCX), a
    ld a, (RoomH)
    srl a
    ld hl, RoomY
    add a, (hl)
    ld (RoomCY), a
    ret

; 직전 방과 새 방을 NetHack join() + dig_corridor() 식으로 연결한다.
;
; NetHack join() 은 두 방의 상대 위치로 마주 볼 변을 정해 각 방의 가장자리에서
; 굴착을 시작한다. dig_corridor() 는 남은 거리가 먼 축부터 파 내려가 L자를
; 만든다. 여기서도 같은 순서를 쓴다. 굴착은 양 방 중심을 잇는 L자이므로
; 목적지 방을 제외한 다른 방을 관통할 여지가 예전(중심-중심 직결)보다 줄고,
; 시작점을 방 중심에 두는 대신 파는 도중 만나는 칸만 바닥으로 만든다.
;
; 어느 축부터 파는지는 거리 비교로 정한다. dig_corridor 가 "dix > diy" 일 때
; x 부터 밀었던 것과 같은 규칙이다.
LinkRooms:
    ld a, (RoomCX)
    ld hl, PrevRoomX
    sub (hl)                    ; A = 새방.x - 옛방.x (부호 있음)
    bit 7, a
    jr z, .dxpos
    neg                         ; 거리만 쓰므로 절댓값
.dxpos:
    ld b, a                     ; B = |dx|
    ld a, (RoomCY)
    ld hl, PrevRoomY
    sub (hl)
    bit 7, a
    jr z, .dypos
    neg
.dypos:
    cp b                        ; |dy| < |dx| 이면 x 축(가로)부터 먼저 판다
    jr c, .horizfirst

    ; 세로 먼저: (옛방중심x, 옛방중심y) -> (옛방중심x, 새방중심y) -> (새방중심x, 새방중심y)
    ld a, (PrevRoomY)
    ld hl, PrevRoomX
    ld b, (hl)                  ; B = x
    ld hl, RoomCY
    ld c, (hl)                  ; C = 끝 y
    call CarveV
    ld a, (RoomCY)              ; A = y  (CarveH 는 A=y, B=시작x, C=끝x)
    ld hl, PrevRoomX
    ld b, (hl)
    ld hl, RoomCX
    ld c, (hl)
    jp CarveH

.horizfirst:
    ; 가로 먼저: (옛방중심x, 옛방중심y) -> (새방중심x, 옛방중심y) -> (새방중심x, 새방중심y)
    ld a, (PrevRoomY)           ; A = y
    ld hl, PrevRoomX
    ld b, (hl)                  ; B = 시작 x
    ld hl, RoomCX
    ld c, (hl)                  ; C = 끝 x
    call CarveH
    ld a, (RoomCX)              ; A = x  (CarveV 는 A=시작y, B=x, C=끝y)
    ld hl, PrevRoomY
    ld b, (hl)
    ld hl, RoomCY
    ld c, (hl)
    jp CarveV

; A=y, B=시작 x, C=끝 x. 양 끝을 포함해 수평 통로를 판다.
CarveH:
    ld d, a
.cell:
    call SetFloor
    ld a, b
    cp c
    ret z
    jr c, .right
    dec b
    jr .cell
.right:
    inc b
    jr .cell

; A=시작 y, B=x, C=끝 y. 양 끝을 포함해 수직 통로를 판다.
CarveV:
    ld d, a
.cell:
    call SetFloor
    ld a, d
    cp c
    ret z
    jr c, .down
    dec d
    jr .cell
.down:
    inc d
    jr .cell

; D=y, B=x 위치를 바닥(0)으로 만든다. B/C/D를 보존해서 통로 루프가 쓸 수 있다.
SetFloor:
    push bc
    push de
    ld a, d
    add a, a
    add a, a
    add a, a
    add a, a
    ld l, a
    ld h, 0
    ld de, MapDataRam
    add hl, de
    ld a, b
    add a, l
    ld l, a
    xor a
    ld (hl), a
    pop de
    pop bc
    ret
