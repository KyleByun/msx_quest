;-----------------------------------------------------------------------------
; 전투 - Bard`s Tale 식으로 주고받기
;
; 판정은 D:/my/python/dnd 의 dice.py attack_roll 그대로다.
;
;   d20 을 굴린다
;   20 이면 무조건 명중이고 피해 주사위를 두 배로 굴린다
;   1 이면 무조건 빗나간다
;   그 밖에는 d20 + 공격보정 >= 상대 AC 이면 명중
;
; 진행 방식만 원본과 다르다. battlefield.py 는 영웅 전원이 움직인 뒤 몬스터
; 전원이 움직이는 격자 전술 화면이다. 여기서는 Bard`s Tale 처럼 **한 명씩
; 번갈아** 친다. 우리 편 하나, 상대 하나, 다시 우리 편 하나... 이렇게 가면
; 오른쪽 창에 주고받는 것이 그대로 흘러간다.
;
; 한 무리는 한 종류다. 그래야 그림 한 장으로 무리를 나타낼 수 있고, 실제로
; Bard`s Tale 도 그렇게 한다. 마릿수는 종류마다 정해 둔 최대치 안에서 뽑는다
; (약한 것은 떼로, 트롤 같은 것은 한 마리만).
;
; 옮기지 않은 것: battlefield.py 의 격자 이동, 주문 사거리, 몬스터 길찾기.
;-----------------------------------------------------------------------------

; A = 몬스터 번호 -> HL = 그 기록
MonPtr:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl                  ; * 4
    ld de, Monsters
    add hl, de
    ret

; A = 몬스터 종류 -> HL = MonsterTable 의 그 줄.
MonTypePtr:
    ld h, a
    ld e, MON_TSTRIDE
    call Mult8
    ld de, MonsterTable
    add hl, de
    ret

;-----------------------------------------------------------------------------
; 무리 하나 만들기. 한 종류로만 채우고 마릿수만 정한다.
;-----------------------------------------------------------------------------
MakeEncounter:
    ld c, MONSTER_N
    call RandMod
    ld (MonKind), a
    call MonTypePtr
    push hl
    ld de, T_MAXGRP
    add hl, de
    ld c, (hl)
    call RandMod
    inc a
    ld (MonCount), a
    pop hl
    ld de, T_HP
    add hl, de
    ld a, (hl)
    ld (TmpDmg), a              ; 종류의 기본 HP 를 잠시 여기 둔다

    ld b, MON_N
    ld c, 0
.each:
    push bc
    ld a, c
    call MonPtr
    ld a, (MonKind)
    ld (hl), a                  ; M_TYPE
    inc hl
    pop bc
    push bc
    ld a, (MonCount)            ; 무리 밖의 자리는 HP 0 (처음부터 없는 셈)
    cp c
    ld a, 0
    jr z, .empty
    jr c, .empty
    ld a, (TmpDmg)
.empty:
    ld (hl), a                  ; M_HP
    inc hl
    ld (hl), a                  ; M_MAXHP
    pop bc
    inc c
    djnz .each
    ret

;-----------------------------------------------------------------------------
; 공격 한 번. dice.py attack_roll 그대로.
;
; 미리 채워 둘 것: AtkBonus, TgtAc, DmgCnt, DmgSides, DmgMod
; 결과: A = 피해 (0 이면 빗나감), CritFlag = 20 이 나왔는가
;-----------------------------------------------------------------------------
DoAttack:
    xor a
    ld (CritFlag), a
    ld c, 20
    call RollDie
    ld (NatRoll), a
    cp 20
    jr z, .crit
    cp 1
    jr z, .miss

    ld hl, AtkBonus
    add a, (hl)                 ; d20 + 공격 보정
    jr c, .over
    bit 7, a
    jr nz, .miss                ; 음수로 내려가면 맞을 수 없다
.over:
    ld hl, TgtAc
    cp (hl)
    jr c, .miss
    ld a, (DmgCnt)
    ld b, a
    jr .roll

.crit:
    ld a, 1
    ld (CritFlag), a
    ld a, (DmgCnt)              ; 치명타는 주사위를 두 배로
    add a, a
    ld b, a
.roll:
    ld a, (DmgSides)
    ld c, a
    call RollDice
    ld hl, DmgMod
    add a, (hl)
    bit 7, a
    ret z
    xor a                       ; 보정이 음수여서 0 아래로 가면 0
    ret

.miss:
    xor a
    ret

;-----------------------------------------------------------------------------
; 살아 있는 것 세기
;-----------------------------------------------------------------------------
CountMonsters:
    ld b, MON_N
    ld c, 0
    ld hl, Monsters + M_HP
    ld de, MON_STRIDE
.next:
    ld a, (hl)
    or a
    jr z, .dead
    inc c
.dead:
    add hl, de
    djnz .next
    ld a, c
    ret

CountHeroes:
    ld b, PARTY_N
    ld c, 0
    ld hl, Party + P_HP
    ld de, PARTY_STRIDE
.next:
    ld a, (hl)
    or a
    jr z, .dead
    inc c
.dead:
    add hl, de
    djnz .next
    ld a, c
    ret

; 살아 있는 첫 몬스터 번호를 A 로. 없으면 캐리.
FirstMonster:
    ld b, MON_N
    ld c, 0
    ld hl, Monsters + M_HP
    ld de, MON_STRIDE
.next:
    ld a, (hl)
    or a
    jr nz, .found
    add hl, de
    inc c
    djnz .next
    scf
    ret
.found:
    ld a, c
    or a
    ret

; 살아 있는 영웅 중 아무나 번호를 A 로. 없으면 캐리.
RandomHero:
    call CountHeroes
    or a
    jr nz, .some
    scf
    ret
.some:
    ld c, a
    call RandMod                ; 살아 있는 사람 중 몇 번째
    ld c, a
    ld b, PARTY_N
    ld hl, Party + P_HP
    ld de, PARTY_STRIDE
    ld a, 0
.next:
    push af
    ld a, (hl)
    or a
    jr z, .skip
    ld a, c
    or a
    jr z, .hit
    dec c
.skip:
    pop af
    inc a
    add hl, de
    djnz .next
    scf
    ret
.hit:
    pop af
    or a
    ret

;-----------------------------------------------------------------------------
; 메시지에 몬스터 이름을 붙인다. 무리가 둘 이상이면 뒤에 번호를 단다.
; A = 몬스터 번호
;-----------------------------------------------------------------------------
; 번호 없이 종류 이름만 (무리를 소개할 때 쓴다)
MsgAddMonKind:
    ld a, (MonKind)
    call MonTypePtr
    ld de, T_NAME
    add hl, de
    ld b, 6
    jp MsgAddStrN

MsgAddMonName:
    push af
    call MsgAddMonKind
    pop af
    ld b, a
    ld a, (MonCount)
    cp 2
    ret c                       ; 한 마리뿐이면 번호를 안 단다
    ld a, b
    inc a
    jp MsgAddNum

;-----------------------------------------------------------------------------
; A = 영웅 번호. 살아 있으면 앞에 있는 몬스터를 친다.
;-----------------------------------------------------------------------------
HeroAttack:
    call PartyPtr
    ld (FightPtr), hl
    ld de, P_HP
    add hl, de
    ld a, (hl)
    or a
    ret z                       ; 쓰러진 사람은 지나간다

    call FirstMonster
    ret c
    ld (TmpType), a             ; 맞는 몬스터 번호
    call MonPtr
    ld (TgtPtr), hl

    ld hl, (FightPtr)
    ld de, P_ATK
    add hl, de
    ld a, (hl)
    ld (AtkBonus), a
    ld hl, (FightPtr)
    ld de, P_DCNT
    add hl, de
    ld a, (hl)
    ld (DmgCnt), a
    inc hl
    ld a, (hl)
    ld (DmgSides), a
    inc hl
    ld a, (hl)
    ld (DmgMod), a

    ld a, (MonKind)             ; 맞는 쪽 AC 는 표에서
    call MonTypePtr
    ld a, (hl)                  ; T_AC
    ld (TgtAc), a

    call DoAttack
    ld (TmpDmg), a

    ld hl, (FightPtr)           ; "이름 HIT 12"
    ld b, 6
    call MsgAddStrN
    ld a, (TmpDmg)
    or a
    jr z, .miss
    ld a, (CritFlag)
    or a
    ld hl, TxtHit
    jr z, .word
    ld hl, TxtCrit
.word:
    call MsgAddStr
    ld a, (TmpDmg)
    call MsgAddNum
    call MsgFlush
    jp DamageMonster
.miss:
    ld hl, TxtMiss
    call MsgAddStr
    jp MsgFlush

; TgtPtr 의 몬스터에게 TmpDmg 만큼.
DamageMonster:
    ld hl, (TgtPtr)
    inc hl                      ; M_HP
    ld a, (hl)
    ld c, a
    ld a, (TmpDmg)
    cp c
    jr c, .hurt
    ld (hl), 0                  ; 쓰러졌다
    ld a, (TmpType)
    call MsgAddMonName
    ld hl, TxtDies
    call MsgAddStr
    jp MsgFlush
.hurt:
    ld b, a
    ld a, c
    sub b
    ld (hl), a
    ret

;-----------------------------------------------------------------------------
; A = 몬스터 번호. 살아 있으면 아무 영웅이나 친다.
;-----------------------------------------------------------------------------
MonAttack:
    ld (TmpType), a
    call MonPtr
    inc hl
    ld a, (hl)                  ; M_HP
    or a
    ret z

    ld a, (MonKind)
    call MonTypePtr
    push hl
    ld de, T_STR                ; 공격 보정 = 2 + 힘 보정 (enemy.py)
    add hl, de
    ld a, (hl)
    call AbilityMod
    ld c, a
    add a, 2
    ld (AtkBonus), a
    ld a, c
    ld (DmgMod), a
    pop hl
    ld de, T_DCNT
    add hl, de
    ld a, (hl)
    ld (DmgCnt), a
    inc hl
    ld a, (hl)
    ld (DmgSides), a

    call RandomHero
    ret c
    call PartyPtr
    ld (TgtPtr), hl
    ld de, P_AC
    add hl, de
    ld a, (hl)
    ld (TgtAc), a

    call DoAttack
    ld (TmpDmg), a

    ld a, (TmpType)
    call MsgAddMonName
    ld a, (TmpDmg)
    or a
    jr z, .miss
    ld a, (CritFlag)
    or a
    ld hl, TxtHit
    jr z, .word
    ld hl, TxtCrit
.word:
    call MsgAddStr
    ld a, (TmpDmg)
    call MsgAddNum
    call MsgFlush
    jp DamageHero
.miss:
    ld hl, TxtMiss
    call MsgAddStr
    jp MsgFlush

; TgtPtr 의 영웅에게 TmpDmg 만큼.
DamageHero:
    ld hl, (TgtPtr)
    ld de, P_HP
    add hl, de
    ld a, (hl)
    ld c, a
    ld a, (TmpDmg)
    cp c
    jr c, .hurt
    ld (hl), 0
    ld hl, (TgtPtr)
    ld b, 6
    call MsgAddStrN
    ld hl, TxtDown
    call MsgAddStr
    jp MsgFlush
.hurt:
    ld b, a
    ld a, c
    sub b
    ld (hl), a
    ret

;-----------------------------------------------------------------------------
; 라운드 하나 - 한 명씩 번갈아 친다
;-----------------------------------------------------------------------------
BattleRound:
    ld hl, TxtRound
    call MsgAddStr
    ld a, (RoundNo)
    call MsgAddNum
    call MsgFlush
    xor a
    ld (TurnHero), a
    ld (TurnMon), a

.turn:
    ld a, (TurnHero)            ; 우리 편 한 명
    cp PARTY_N
    jr nc, .nohero
    push af
    call HeroAttack
    pop af
    inc a
    ld (TurnHero), a
    call CountMonsters
    or a
    jr z, .won
.nohero:
    ld a, (TurnMon)             ; 상대 한 마리
    cp MON_N
    jr nc, .nomon
    push af
    call MonAttack
    pop af
    inc a
    ld (TurnMon), a
    call CountHeroes
    or a
    jr z, .lost
.nomon:
    ld a, (TurnHero)            ; 둘 다 끝났으면 라운드 끝
    cp PARTY_N
    jr c, .turn
    ld a, (TurnMon)
    cp MON_N
    jr c, .turn

    ld a, (RoundNo)
    inc a
    ld (RoundNo), a
    jp DrawParty

.won:
    ld hl, TxtWon
    call MsgAddStr
    call MsgFlush
    call EndBattle
    jp DrawParty
.lost:
    ld hl, TxtLost
    call MsgAddStr
    call MsgFlush
    call EndBattle
    jp DrawParty

; 전투를 끝낸다. 몬스터 그림을 지우려면 던전을 다시 그려야 한다.
EndBattle:
    xor a
    ld (BattleOn), a
    ld a, 1
    ld (needDraw), a
    ret

;-----------------------------------------------------------------------------
; 전투 시작
;-----------------------------------------------------------------------------
StartBattle:
    ld a, 1
    ld (BattleOn), a
    ld (RoundNo), a
    call MakeEncounter
    call MsgClear

    ld a, (MonCount)            ; "3 GOBLIN" 처럼
    call MsgAddNum
    ld hl, TxtSpace
    call MsgAddStr
    call MsgAddMonKind
    call MsgFlush
    ld hl, TxtAppear
    call MsgAddStr
    call MsgFlush

    ld a, 1                     ; 던전을 다시 그리게 하면 메인 루프가 그 위에
    ld (needDraw), a            ; 몬스터 그림을 얹는다
    ret

TxtSpace:   db " ", 0
TxtAppear:  db "BLOCKS THE WAY", 0
TxtRound:   db "ROUND ", 0
TxtHit:     db " HIT ", 0
TxtCrit:    db " CRIT ", 0
TxtMiss:    db " MISS", 0
TxtDies:    db " DIES", 0
TxtDown:    db " DOWN", 0
TxtWon:     db "VICTORY", 0
TxtLost:    db "PARTY IS LOST", 0

;-----------------------------------------------------------------------------
; 걸어 다니다 마주치기
;
; 한 칸 옮길 때마다 굴린다. 여덟 칸에 한 번꼴이면 통로를 몇 번 돌 때마다 한 번
; 붙게 되어, 지도를 보러 다니는 재미와 전투가 적당히 섞인다.
;-----------------------------------------------------------------------------
ENCOUNTER_ODDS equ 8

RollEncounter:
    ld a, (BattleOn)
    or a
    ret nz
    ld c, ENCOUNTER_ODDS
    call RandMod
    or a
    ret nz
    call CountHeroes            ; 전멸한 파티는 더 만나지 않는다
    or a
    ret z
    jp StartBattle
