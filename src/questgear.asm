;-----------------------------------------------------------------------------
; 장비와 소지품
;
; 파티 기록(Party, 32 바이트)은 건드리지 않고 나란한 배열을 하나 더 둔다.
; 기록을 늘리면 PARTY_STRIDE 가 32(2 의 거듭제곱)를 벗어나 색인이 시프트로
; 끝나지 않는다.
;
;   G_INV    가방 INV_N 칸. 품목 번호. 빈 칸은 INV_EMPTY
;   G_EQUIP  차는 자리 넷(무기/방패/갑옷/투구). "가방 몇 번째" 를 담는다
;
; 자리가 다르면 함께 찰 수 있고(칼 + 방패 + 갑옷 + 투구), 자리가 같으면 함께
; 못 찬다(칼과 도끼). 새로 차면 그 자리에 있던 것이 저절로 벗겨진다.
;
; 수치는 quest_sena.md 에서 왔고 gfx/quest_gear.py 가 굽는다.
;-----------------------------------------------------------------------------

; A = 사람 번호 -> HL = 그 사람의 장비 자료
GearPtr:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; * 16
    ld de, PartyGear
    add hl, de
    ret

; A = 품목 번호 -> HL = ItemTable 의 그 줄
ItemPtr:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl                  ; * 4
    ld de, ItemTable
    add hl, de
    ret

; A = 사람, B = 가방 칸 -> A = 품목 번호 (빈 칸이면 INV_EMPTY)
InvItem:
    call GearPtr
    ld e, b
    ld d, 0
    add hl, de
    ld a, (hl)
    ret

; A = 품목 번호 -> A = 그 품목을 차는 자리 (0 이면 쓰는 것)
ItemSlot:
    cp INV_EMPTY
    ret z
    call ItemPtr
    ld a, (hl)
    ret

; A = 사람, C = 자리(1~4) -> HL = 그 자리의 G_EQUIP 칸
EquipSlotPtr:
    call GearPtr
    ld de, G_EQUIP - 1
    add hl, de
    ld e, c
    ld d, 0
    add hl, de
    ret

; A = 사람, B = 가방 칸 -> 차고 있으면 Z
IsEquipped:
    call GearPtr
    ld de, G_EQUIP
    add hl, de
    ld c, EQUIP_N
.loop:
    ld a, (hl)
    cp b
    ret z
    inc hl
    dec c
    jr nz, .loop
    or 0xFF                     ; 못 찾았다. **여기서 NZ 를 직접 만든다** -
    ret                         ; 그냥 ret 하면 dec c 의 Z 가 나가 다 찬 것이 된다

;-----------------------------------------------------------------------------
; StartParty - 파티 전원에게 처음 짐을 넣고 기본 장비를 차게 한다.
;-----------------------------------------------------------------------------
StartParty:
    xor a
.who:
    ld (GearWho), a
    call PartyPtr
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    ld h, a                     ; 직업별 처음 짐 한 줄
    ld e, KIT_STRIDE
    call Mult8
    ld de, StartKit
    add hl, de
    ld (GearTmp), hl

    ld a, (GearWho)             ; 가방과 찬 자리를 모두 비운다
    call GearPtr
    push hl
    ld b, GEAR_STRIDE
.clr:
    ld (hl), INV_EMPTY
    inc hl
    djnz .clr
    pop de

    ld hl, (GearTmp)            ; 처음 짐을 옮긴다
    ld b, INV_N
.copy:
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    djnz .copy

    ; 가방을 훑어 자리마다 **처음 나오는 것**을 찬다. 처음 짐이 무기 목록 +
    ; 방패 + 갑옷 차례라 무기는 목록 맨 앞(그 직업의 주 무기)이 걸린다.
    xor a
    ld (GearIdx), a
.equip:
    ld a, (GearIdx)
    ld b, a
    ld a, (GearWho)
    call InvItem
    cp INV_EMPTY
    jr z, .next
    call ItemSlot
    or a
    jr z, .next                 ; 소모품은 차지 않는다
    ld c, a
    ld a, (GearWho)
    call EquipSlotPtr
    ld a, (hl)
    cp INV_EMPTY
    jr nz, .next                ; 그 자리는 이미 찼다
    ld a, (GearIdx)
    ld (hl), a
.next:
    ld hl, GearIdx
    inc (hl)
    ld a, (hl)
    cp INV_N
    jr c, .equip

    ld a, (GearWho)
    call ApplyGear
    ld a, (GearWho)
    inc a
    cp PARTY_N
    jp c, .who
    ret

;-----------------------------------------------------------------------------
; EquipInv - A = 사람, B = 가방 칸. 그것을 찬다.
;
; 같은 자리에 있던 것은 저절로 벗겨진다. 양손 무기를 차면 방패도 벗는다.
;-----------------------------------------------------------------------------
EquipInv:
    ld (GearWho), a
    ld a, b
    ld (GearIdx), a
    ld a, (GearWho)
    call InvItem
    cp INV_EMPTY
    ret z
    ld (GearItem), a
    call ItemSlot
    or a
    ret z                       ; 소모품은 차는 것이 아니다
    ld c, a
    ld a, (GearWho)
    call EquipSlotPtr
    ld a, (GearIdx)
    ld (hl), a

    ld a, (GearItem)            ; 양손이면 방패를 벗는다
    call ItemPtr
    ld de, I_TWOH
    add hl, de
    ld a, (hl)
    or a
    jr z, .done
    ld c, SLOT_SHIELD
    ld a, (GearWho)
    call EquipSlotPtr
    ld (hl), INV_EMPTY
.done:
    ld a, (GearWho)
    jp ApplyGear

;-----------------------------------------------------------------------------
; DropInv - A = 사람, B = 가방 칸. 버린다. 차고 있었으면 먼저 벗는다.
;-----------------------------------------------------------------------------
DropInv:
    ld (GearWho), a
    ld a, b
    ld (GearIdx), a

    ld a, (GearWho)
    call GearPtr
    ld de, G_EQUIP
    add hl, de
    ld c, EQUIP_N
.unequip:
    ld a, (hl)
    cp b
    jr nz, .skip
    ld (hl), INV_EMPTY
.skip:
    inc hl
    dec c
    jr nz, .unequip

    ld a, (GearWho)
    call GearPtr
    ld a, (GearIdx)
    ld e, a
    ld d, 0
    add hl, de
    ld (hl), INV_EMPTY
    ld a, (GearWho)
    jp ApplyGear

;-----------------------------------------------------------------------------
; GiveInv - A = 주는 사람, B = 가방 칸, C = 받는 사람.
; 받는 쪽 가방이 꽉 찼으면 아무 일도 안 한다.
;-----------------------------------------------------------------------------
GiveInv:
    ld (GearWho), a
    ld a, b
    ld (GearIdx), a
    ld a, c
    ld (GearTo), a
    cp PARTY_N
    ret nc
    ld a, (GearWho)
    cp c
    ret z                       ; 자기 자신에게는 뜻이 없다

    ld a, (GearIdx)
    ld b, a
    ld a, (GearWho)
    call InvItem
    cp INV_EMPTY
    ret z
    ld (GearItem), a

    ld a, (GearTo)              ; 받는 쪽 빈 칸을 찾는다
    call GearPtr
    ld b, INV_N
.find:
    ld a, (hl)
    cp INV_EMPTY
    jr z, .got
    inc hl
    djnz .find
    ret                         ; 가방이 꽉 찼다
.got:
    ld a, (GearItem)
    ld (hl), a

    ld a, (GearIdx)             ; 준 쪽에서 지운다 (차고 있었으면 벗겨진다)
    ld b, a
    ld a, (GearWho)
    call DropInv
    ld a, (GearTo)
    jp ApplyGear

;-----------------------------------------------------------------------------
; UseInv - A = 사람, B = 가방 칸. 소모품을 쓴다. 쓰면 없어진다.
;-----------------------------------------------------------------------------
UseInv:
    ld (GearWho), a
    ld a, b
    ld (GearIdx), a
    ld a, (GearWho)
    call InvItem
    cp INV_EMPTY
    ret z
    call ItemPtr
    ld a, (hl)
    or a
    ret nz                      ; 차는 것은 쓸 수 없다
    inc hl
    ld a, (hl)
    ld (GearAmt), a             ; 효과 크기
    inc hl
    ld a, (hl)                  ; 효과 종류
    cp EFF_HP
    jr z, .hp
    cp EFF_MP
    jr z, .mp
    ret                         ; 아직 하는 일이 없는 것(타운포털)
.hp:
    ld b, P_HP
    ld c, P_MAXHP
    jr .heal
.mp:
    ld b, P_SPL
    ld c, P_MAXSPL
.heal:
    ld a, (GearWho)
    call PartyPtr
    push hl
    ld e, c                     ; 최대값 칸
    ld d, 0
    add hl, de
    ld a, (hl)
    ld (GearMax), a
    pop hl
    ld e, b                     ; 지금값 칸
    ld d, 0
    add hl, de
    ld a, (GearAmt)
    add a, (hl)
    ld c, a
    ld a, (GearMax)
    cp c
    jr nc, .put
    ld c, a                     ; 최대를 넘지 않는다
.put:
    ld (hl), c

    ld a, (GearIdx)             ; 다 썼으니 없앤다
    ld b, a
    ld a, (GearWho)
    jp DropInv

;-----------------------------------------------------------------------------
; ApplyGear - A = 사람 번호. 찬 것을 그 사람의 수치에 반영한다.
;
;   피해 주사위 <- 찬 무기 (없으면 맨손 1d2)
;   AC          <- 12 + 민첩보정 + 찬 방어구들의 보너스
;
; 더하고 빼지 않고 늘 처음부터 다시 센다. 벗을 때 빼는 것을 잊으면 값이
; 슬금슬금 늘어나기 때문이다.
;-----------------------------------------------------------------------------
ApplyGear:
    ld (GearWho), a
    call PartyPtr
    ld (GearPty), hl

    ld a, 1                     ; 맨손 1d2
    ld (GearDcnt), a
    ld a, 2
    ld (GearDside), a
    xor a
    ld (GearAc), a

    ld a, SLOT_WEAPON
.slot:
    ld (GearSlot), a
    ld c, a
    ld a, (GearWho)
    call EquipSlotPtr
    ld a, (hl)
    cp INV_EMPTY
    jr z, .nextslot
    ld b, a
    ld a, (GearWho)
    call InvItem
    cp INV_EMPTY
    jr z, .nextslot
    call ItemPtr
    inc hl
    ld b, (hl)                  ; I_A
    inc hl
    ld c, (hl)                  ; I_B
    ld a, (GearSlot)
    cp SLOT_WEAPON
    jr nz, .armour
    ld a, b
    ld (GearDcnt), a
    ld a, c
    ld (GearDside), a
    jr .nextslot
.armour:
    ld a, (GearAc)
    add a, b
    ld (GearAc), a
.nextslot:
    ld a, (GearSlot)
    inc a
    cp SLOT_HELM + 1
    jr c, .slot

    ld hl, (GearPty)            ; 피해 주사위
    ld de, P_DCNT
    add hl, de
    ld a, (GearDcnt)
    ld (hl), a
    inc hl
    ld a, (GearDside)
    ld (hl), a

    ld hl, (GearPty)            ; AC = 12 + 민첩보정 + 방어구
    ld de, P_DEX
    add hl, de
    ld a, (hl)
    call AbilityMod
    add a, HERO_BASE_AC
    ld b, a
    ld a, (GearAc)
    add a, b
    ld b, a
    ld hl, (GearPty)
    ld de, P_AC
    add hl, de
    ld (hl), b
    ret
