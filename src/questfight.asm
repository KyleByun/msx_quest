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
    ld a, (MonKind)             ; 이름은 MonsterTable 이 아니라 말별 표에 있다
    ld h, a
    ld e, MONNAME_LEN
    call Mult8
    ld de, (MonNameTab)
    add hl, de
    jp MsgAddStr                ; 이름 표는 0 으로 끝난다

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

    ld a, (AtkMode)             ; 특수 명령이면 이번 한 방만 손본다
    or a
    call nz, ApplyMode

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
    ld a, MSG_HIT
    jr z, .word
    ld a, MSG_CRIT
.word:
    call MsgText
    call MsgAddStr
    ld a, (TmpDmg)
    call MsgAddNum
    call MsgFlush
    jp DamageMonster
.miss:
    ld a, MSG_MISS
    call MsgText
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
    ld a, MSG_DIES
    call MsgText
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
    inc hl                      ; P_GUARD 가 바로 뒤 - 방어 중이면 더한다
    add a, (hl)
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
    ld a, MSG_HIT
    jr z, .word
    ld a, MSG_CRIT
.word:
    call MsgText
    call MsgAddStr
    ld a, (TmpDmg)
    call MsgAddNum
    call MsgFlush
    jp DamageHero
.miss:
    ld a, MSG_MISS
    call MsgText
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
    ld a, MSG_DOWN
    call MsgText
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
;-----------------------------------------------------------------------------
; 라운드 하나.
;
; 민첩이 행동 횟수를 정한다(quest_sena.md 의 전투방식).
;
;   행동 횟수 = floor(내 민첩 / 이 전장의 최저 민첩)
;
; 그래서 한 라운드는 **여러 바퀴**로 돈다. 첫 바퀴에는 모두가 한 번씩 치고,
; 둘째 바퀴에는 행동 횟수가 2 이상인 것만 다시 친다. 아무도 못 움직이는 바퀴가
; 나오면 라운드가 끝난다.
;
; 바퀴 안에서는 예전처럼 우리 편 하나 / 상대 하나로 번갈아 간다. 오른쪽 창에
; 주고받는 것이 그대로 흘러가는 것이 이 화면의 전부라, 순서를 바꾸면 읽기가
; 나빠진다. 빠른 쪽은 뒤쪽 바퀴에서 한 번 더 나오는 것으로 드러난다.
;-----------------------------------------------------------------------------
BattleRound:
    ld a, MSG_ROUND
    call MsgText
    call MsgAddStr
    ld a, (RoundNo)
    call MsgAddNum
    call MsgFlush
    call CalcActs               ; 이 라운드의 행동 횟수를 정한다
    xor a
    ld (FleeDone), a
    ld a, 1
    ld (ActPass), a

.pass:
    xor a
    ld (TurnHero), a
    ld (TurnMon), a
    ld (PassActed), a

.turn:
    ld a, (TurnHero)            ; 우리 편 한 명
    cp PARTY_N
    jr nc, .nohero
    ld hl, ActHero              ; 이번 바퀴에 움직일 차례인가
    call AddA
    ld a, (ActPass)
    cp (hl)
    jr z, .heroacts
    jr nc, .heroskip
.heroacts:
    ld a, 1
    ld (PassActed), a
    ld a, (TurnHero)            ; 내 차례가 왔으니 방어 태세를 푼다
    call PartyPtr
    ld de, P_GUARD
    add hl, de
    ld (hl), 0
    ld a, (TurnHero)            ; 쓰러진 사람에게는 묻지 않는다
    call PartyPtr
    ld de, P_HP
    add hl, de
    ld a, (hl)
    or a
    jr z, .heroskip
    ld a, (TurnHero)
    call AskCommand             ; A = 고른 명령, MenuHero = 그 사람
    call DoCommand
    ld a, (FleeDone)
    or a
    jp nz, .roundend            ; 도망쳤으면 남은 차례는 없다
    call CountMonsters
    or a
    jr z, .won
.heroskip:
    ld hl, TurnHero
    inc (hl)
.nohero:
    ld a, (TurnMon)             ; 상대 한 마리
    cp MON_N
    jr nc, .nomon
    ld a, (ActPass)
    ld hl, ActMon
    cp (hl)
    jr z, .monacts
    jr nc, .monskip
.monacts:
    ld a, 1
    ld (PassActed), a
    ld a, (TurnMon)
    call MonAttack
    call CountHeroes
    or a
    jr z, .lost
.monskip:
    ld hl, TurnMon
    inc (hl)
.nomon:
    ld a, (TurnHero)            ; 둘 다 끝났으면 이 바퀴가 끝
    cp PARTY_N
    jp c, .turn                 ; 명령 메뉴가 끼면서 jr 사거리를 넘었다
    ld a, (TurnMon)
    cp MON_N
    jp c, .turn

    ld a, (PassActed)           ; 아무도 못 움직였으면 라운드도 끝
    or a
    jr z, .roundend
    ld hl, ActPass
    inc (hl)
    jp .pass

.roundend:
    call MenuClear              ; 명령 자리를 비워 둔다
    ld a, (RoundNo)
    inc a
    ld (RoundNo), a
    jp DrawParty

.won:
    call MenuClear
    ld a, MSG_WON
    call MsgText
    call MsgAddStr
    call MsgFlush
    call EndBattle
    jp DrawParty
.lost:
    call MenuClear
    ld a, MSG_LOST
    call MsgText
    call MsgAddStr
    call MsgFlush
    call EndBattle
    jp DrawParty

;-----------------------------------------------------------------------------
; 명령 메뉴 - 양피지 아래 세 줄
;
; 기록창 위 LOG_ROWS 줄은 전투 기록이 그대로 흘러가고, 아래 세 줄에 지금 움직일
; 사람과 고를 수 있는 명령 넷을 띄운다. 무슨 일이 있었는지 보면서 고를 수 있다.
;
; 명령은 **행동마다** 묻는다. 민첩이 높으면 한 라운드에 여러 번 나오는데, 그때마다
; 다시 고를 수 있어야 문서의 반실시간 취지에 맞는다.
;
;   0 ATTACK  일반 공격          1 DEFEND  다음 내 차례까지 AC +4
;   2 FLEE    파티 전체 후퇴 판정  3 (직업별) ClassSkill 표의 특수 명령
;
; 한 줄에 둘씩 놓아 메뉴가 세 줄(이름 + 명령 두 줄)이면 된다. 남는 세 줄은 위의
; 전투 기록이 가져간다 - 한 줄에 하나씩 놓았더니 기록이 일곱 줄뿐이었다.
;
; 입력은 커서 넷으로 고르고 스페이스로 결정한다. 여기서 눌린 것을 prevKey 에
; 바로 반영하므로, 결정한 스페이스가 밖으로 나가 라운드를 또 넘기지 않는다.
;-----------------------------------------------------------------------------
CMD_N       equ 4

; A = 영웅 번호 -> A = 고른 명령 (0..3)
AskCommand:
    ld (MenuHero), a
    xor a
    ld (MenuSel), a
    call MenuDraw
.loop:
    call WaitVBlank
    call ReadInput
    ld a, (keyState)            ; 새로 눌린 것만
    ld b, a
    ld a, (prevKey)
    cpl
    and b
    ld c, a
    ld a, b
    ld (prevKey), a

    bit KEY_SPACE, c
    jr nz, .done

    ; 메뉴가 2x2 라 커서 이동이 곧 비트 뒤집기다 - 색인의 bit0 이 열, bit1 이 줄이다.
    ; 줄도 열도 둘뿐이라 반대쪽으로 가는 것과 되돌아 감기는 것이 같은 동작이라,
    ; 위/아래를 가르지 않고 좌/우도 가르지 않는다. B 는 뒤집을 비트.
    ; (여기서 keyState 를 B 에 담았지만 위에서 prevKey 로 옮긴 뒤로는 죽은 값이다)
    ASSERT CMD_N == 4, command menu cursor assumes a 2x2 grid
    ld b, 1                     ; 좌우 = 열을 바꾼다
    bit KEY_LEFT, c
    jr nz, .move
    bit KEY_RIGHT, c
    jr nz, .move
    ld b, 2                     ; 상하 = 줄을 바꾼다
    bit KEY_UP, c
    jr nz, .move
    bit KEY_DOWN, c
    jr z, .loop
.move:
    ld a, (MenuSel)
    xor b
    ld (MenuSel), a
    call MenuDraw
    jr .loop
.done:
    ld a, (MenuSel)
    ret

; 메뉴를 다시 그린다. 고른 줄 앞에만 화살표를 붙인다.
MenuDraw:
    call MenuClear
    ld c, MSG_Y + MENU_ROW * MSG_DY     ; 첫 줄 - 누구 차례인가
    ld b, MSG_X
    call SetPos
    ld a, COL_BLACK
    ld b, COL_CREAM
    call SetColours
    ld a, (MenuHero)
    call PartyPtr
    ld b, NAME_LEN
    call PutStrN

    xor a
    ld (MenuIdx), a
.row:
    ld a, (MenuIdx)             ; 한 줄에 둘씩 - 줄은 색인의 절반
    srl a
    add a, MENU_ROW + 1
    add a, a
    add a, a
    add a, a                    ; * MSG_DY
    add a, MSG_Y
    ld c, a                     ; C = y
    ld a, (MenuIdx)             ; 짝수면 왼쪽 칸, 홀수면 오른쪽 칸
    and 1
    jr z, .left
    ld b, MSG_X + 9 * FONT_W
    jr .havex
.left:
    ld b, MSG_X
.havex:
    call SetPos
    ld a, COL_BLACK
    ld b, COL_CREAM
    call SetColours
    ld a, (MenuIdx)             ; 고른 줄이면 화살표
    ld hl, MenuSel
    cp (hl)
    ld a, MSG_MENU_ON
    jr z, .mark
    ld a, MSG_MENU_OFF
.mark:
    call MsgText
    call PutStr
    ld a, (MenuIdx)
    call CmdName
    call PutStr
    ld hl, MenuIdx
    inc (hl)
    ld a, (hl)
    cp CMD_N
    jr c, .row
    ret

; A = 명령 번호 -> HL = 그 이름. 3 번은 직업마다 다르다.
CmdName:
    cp 3
    jr z, .skill
    ld l, a
    ld h, 0
    ld de, CmdNames             ; 이제 메시지 번호 한 바이트씩이다
    add hl, de
    ld a, (hl)
    jp MsgText
.skill:
    ld a, (MenuHero)
    call PartyPtr
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    ld h, a
    ld e, SKILLNAME_LEN
    call Mult8
    ld de, (SkillNameTab)
    add hl, de
    ret

CmdNames:
    db MSG_CMD_ATTACK, MSG_CMD_DEFEND, MSG_CMD_FLEE


;-----------------------------------------------------------------------------
; 고른 명령을 실행한다. A = 명령 번호. 누가 하는지는 AskCommand 가 MenuHero 에
; 넣어 둔 값을 쓴다 - 명령을 A 로 받아야 부르는 쪽에서 갈아 끼울 수 있다.
;-----------------------------------------------------------------------------
DoCommand:
    ld (MenuSel), a
    or a
    jr z, .attack
    dec a
    jr z, .defend
    dec a
    jr z, .flee

    ld a, (MenuHero)            ; 직업별 특수 - 표의 효과 번호를 AtkMode 로
    call PartyPtr
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    ld h, a
    ld e, SKILL_STRIDE
    call Mult8
    ld de, ClassSkill + SK_EFF
    add hl, de
    ld a, (hl)
    ld (AtkMode), a
    cp 1                        ; 1 = 행동 폭증. 때리지 않고 차례만 늘린다.
    jr nz, .attack2
    xor a
    ld (AtkMode), a
    ld hl, ActHero
    ld a, (MenuHero)
    call AddA
    inc (hl)                    ; 이번 라운드에 한 번 더
    ld a, (MenuHero)
    call PartyPtr
    ld b, NAME_LEN
    call MsgAddStrN
    ld a, MSG_SURGES
    call MsgText
    call MsgAddStr
    jp MsgFlush
.attack2:
    ld a, (MenuHero)
    jp HeroAttack

.attack:
    xor a
    ld (AtkMode), a
    ld a, (MenuHero)
    jp HeroAttack

.defend:
    ld a, (MenuHero)            ; 다음 내 차례까지 AC +4
    call PartyPtr
    ld de, P_GUARD
    add hl, de
    ld (hl), 4
    ld a, (MenuHero)
    call PartyPtr
    ld b, NAME_LEN
    call MsgAddStrN
    ld a, MSG_GUARDS
    call MsgText
    call MsgAddStr
    jp MsgFlush

.flee:                          ; d20 + 민첩 보정 >= 12 면 파티가 빠져나간다
    ; **굴림을 먼저 한다.** 예전에는 민첩 보정을 C 에 담아 두고 굴렸는데 두 군데가
    ; 틀렸다. RandMod 는 면 수를 **C** 로 받는데 A 에 20 을 넣고 있었고(그래서
    ; 실제 면 수는 민첩 보정이었다 - 보정이 0 이면 0 으로 나누는 꼴), 게다가
    ; RandMod 가 BC 를 뭉개므로 뒤의 add a,c 는 난수 찌꺼기를 더하고 있었다.
    ; 실측: C=0, A=85 가 나왔다. 12 를 넘으니 도망이 거의 언제나 성공했다.
    ;
    ; PartyPtr 과 AbilityMod 는 HL 과 DE 만 쓰므로 굴림을 B 에 두면 살아남는다.
    ld c, 20
FleeRoll:                       ; 검사가 여기서 면 수를 확인한다
    call RollDie                ; A = 1..20
    ld b, a
    ld a, (MenuHero)
    call PartyPtr
    ld de, P_DEX
    add hl, de
    ld a, (hl)
    call AbilityMod
FleeTotal:
    add a, b
    cp 12
    jr c, .noflee
    ld a, MSG_FLED
    call MsgText
    call MsgAddStr
    call MsgFlush
    call EndBattle
    ld a, 1                     ; 남은 라운드를 멈춘다
    ld (FleeDone), a
    ret
.noflee:
    ld a, (MenuHero)
    call PartyPtr
    ld b, NAME_LEN
    call MsgAddStrN
    ld a, MSG_NO_FLEE
    call MsgText
    call MsgAddStr
    jp MsgFlush


; AtkMode 에 따라 이번 한 방의 값을 손본다. ClassSkill 표의 효과 번호와 같다.
;
;   2 SNEAK  피해 주사위 +1
;   3 BOLT   지능으로 때린다 (1d8 + 지능보정, MP 는 안 쓴다)
;   4 SMITE  신성 피해 +4
;   5 KI     주사위 +2, 대신 명중 -2
ApplyMode:
    cp 2
    jr z, .sneak
    cp 3
    jr z, .bolt
    cp 4
    jr z, .smite
.ki:
    ld hl, DmgCnt
    inc (hl)
    inc (hl)
    ld hl, AtkBonus
    dec (hl)
    dec (hl)
    ret
.sneak:
    ld hl, DmgCnt
    inc (hl)
    ret
.smite:
    ld hl, DmgMod
    ld a, (hl)
    add a, 4
    ld (hl), a
    ret
.bolt:
    ld a, 1
    ld (DmgCnt), a
    ld a, 8
    ld (DmgSides), a
    ld hl, (FightPtr)
    ld de, P_INT
    add hl, de
    ld a, (hl)
    call AbilityMod
    ld (DmgMod), a
    add a, 2
    ld (AtkBonus), a
    ret

; HL += A. A 파괴.
AddA:
    add a, l
    ld l, a
    ret nc
    inc h
    ret

;-----------------------------------------------------------------------------
; 이 라운드의 행동 횟수를 정한다.
;
; 최저 민첩은 **살아 있는 것들만** 보고 라운드 시작에 한 번 정한 뒤 그대로 쓴다.
; 라운드 도중에 다시 재면 누가 쓰러질 때마다 남은 모두의 행동 횟수가 바뀌어서,
; 화면으로도 검증으로도 따라가기 어렵다.
;
; 나누는 값이므로 0 이면 안 된다. 살아 있는 것이 없거나 민첩이 0 이면 1 로 둔다.
; 몬스터는 한 무리가 한 종류라 민첩도 하나뿐이다.
;-----------------------------------------------------------------------------
CalcActs:
    ld a, 255
    ld (DexMin), a

    ld b, PARTY_N               ; 살아 있는 사람 중 가장 낮은 민첩
    ld c, 0
.dexhero:
    push bc
    ld a, c
    call PartyPtr
    ld de, P_HP
    add hl, de
    ld a, (hl)
    or a
    jr z, .dexhnext             ; 쓰러진 사람은 세지 않는다
    ld de, P_DEX - P_HP
    add hl, de
    ld a, (hl)
    ld hl, DexMin
    cp (hl)
    jr nc, .dexhnext
    ld (hl), a
.dexhnext:
    pop bc
    inc c
    djnz .dexhero

    call CountMonsters          ; 몬스터가 남아 있으면 그 종류의 민첩도 본다
    or a
    jr z, .havemin
    call MonDex
    ld hl, DexMin
    cp (hl)
    jr nc, .havemin
    ld (hl), a
.havemin:
    ld a, (DexMin)
    or a
    jr nz, .minok
    inc a
.minok:
    cp 255                      ; 아무도 안 남았으면 (있을 수 없지만) 1 로
    jr nz, .minok2
    ld a, 1
.minok2:
    ld (DexMin), a

    ld b, PARTY_N               ; 사람마다 민첩 / 최저민첩
    ld c, 0
.acthero:
    push bc
    ld a, c
    call PartyPtr
    ld de, P_DEX
    add hl, de
    ld e, (hl)
    call ActsFor                ; A = 행동 횟수
    pop bc
    push af                     ; 주소를 구하는 동안 A 를 지킨다.
    ld hl, ActHero              ; AddA 가 A 를 주소 계산에 쓰므로 그냥 두면
    ld a, c                     ; 횟수 대신 주소 하위 바이트가 저장된다.
    call AddA
    pop af
    ld (hl), a
    inc c
    djnz .acthero

    call MonDex                 ; 몬스터도 한 번
    ld e, a
    call ActsFor
    ld (ActMon), a
    ret

; A = 지금 무리의 민첩. HL, BC, DE 파괴.
MonDex:
    ld a, (MonKind)
    call MonTypePtr
    ld de, T_DEX
    add hl, de
    ld a, (hl)
    ret

; E = 민첩 -> A = 행동 횟수 (최소 1). BC, DE, HL 파괴.
ActsFor:
    ld a, (DexMin)
    ld c, a
    call Div8                   ; E / C -> A 몫
    or a
    ret nz
    inc a                       ; 0 번 움직이는 것은 없다
    ret

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
    ; 미니맵과 전투 기록은 **같은 양피지 자리**를 쓴다. 지도를 켜 둔 채로 싸우면
    ; 지도가 글자를 덮어 "1 TROLL" 이 "1" 만 남는다(x=144 부터 지도가 가린다).
    ; 그래서 전투가 시작되면 지도를 접는다. 전투 중에는 M 도 안 받는다.
    xor a
    ld (MapOn), a
    call MsgClear

    ld a, (MonCount)            ; "3 GOBLIN" 처럼
    call MsgAddNum
    ld a, MSG_SPACE
    call MsgText
    call MsgAddStr
    call MsgAddMonKind
    call MsgFlush
    ld a, MSG_APPEAR
    call MsgText
    call MsgAddStr
    call MsgFlush

    ld a, 1                     ; 던전을 다시 그리게 하면 메인 루프가 그 위에
    ld (needDraw), a            ; 몬스터 그림을 얹는다
    ret


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
