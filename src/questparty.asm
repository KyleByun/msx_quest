;-----------------------------------------------------------------------------
; 주사위와 파티 만들기
;
; D:/my/python/dnd 의 dice.py / hero.py / race_job.py 를 옮긴 것이다. 계산식은
; 그대로 두고, Z80 에 곱셈과 나눗셈이 없어 어려운 부분만 표로 펼쳤다
; (gfx/quest_rules.py 가 questruledata.asm 을 굽는다).
;
; 옮기지 않은 것: battlefield.py 의 격자 이동, 주문 사거리, 몬스터 길찾기.
; 그것은 전술 격자 화면을 위한 것이고 여기는 Wizardry 식 한 줄 대열이다.
;-----------------------------------------------------------------------------

; 16 비트 xorshift. 씨앗이 0 이 아니면 65535 주기를 돈다.
; 결과는 HL 과 A(하위 바이트)에 둔다.
Rand16:
    ld hl, (Seed)
    ld a, h
    rra
    ld a, l
    rra
    xor h
    ld h, a
    ld a, l
    rra
    ld a, h
    rra
    xor l
    ld l, a
    xor h
    ld h, a
    ld (Seed), hl
    ld a, l
    ret

; C = n.  A = 0 ~ n-1.
;
; 8 비트 난수를 면 수로 나눈 나머지를 쓰면 256 mod n 만큼 앞쪽 값이 자주 나온다.
; d20 이면 6% 라 전투에서 티가 난다. 16 비트를 나누면 편향이 65536 mod n 이라
; 0.05% 로 떨어져서 사실상 없다.
;
; 나눗셈은 Grauw 의 Div16 을 쓴다 (questmath.asm, doc/z80_mult_div.md).
RandMod:
    ld a, c
    push af
    call Rand16                 ; HL = 난수
    ld b, h
    ld c, l
    pop af
    ld e, a
    ld d, 0                     ; BC / DE
    call Div16                  ; HL = 나머지
    ld a, l
    ret

; C = 면 수.  A = 1 ~ C.
RollDie:
    call RandMod
    inc a
    ret

; B = 개수, C = 면 수.  A = 합.
RollDice:
    ld e, 0
.next:
    push bc
    push de
    call RollDie
    pop de
    add a, e
    ld e, a
    pop bc
    djnz .next
    ld a, e
    ret

; A = 능력치 점수 -> A = 보정값(부호 있음).
;
; dice.py 는 (점수-10)//2 인데 파이썬 내림 나눗셈이라 8 이 -1, 7 이 -2 다.
; sra 로 흉내 낼 수 있지만 한 번 틀리면 찾기 어려워 표를 본다.
AbilityMod:
    ld l, a
    ld h, 0
    ld de, AbilMod
    add hl, de
    ld a, (hl)
    ret

; A = 사람 번호 -> HL = 그 사람의 기록.
PartyPtr:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; * 32
    ld de, Party
    add hl, de
    ret

; A = 직업 번호 -> HL = ClassTable 의 그 줄.
;
; 간격이 22 라 시프트만으로는 안 되고 손으로 사슬을 짜야 한다. 그렇게 하면
; 빠르지만 표의 간격이 바뀔 때 조용히 틀린다. 여기는 한 사람 만들 때 몇 번,
; 한 라운드에 몇 번 도는 자리라 Mult8 로 곱한다.
ClassPtr:
    ld h, a
    ld e, CLASS_STRIDE
    call Mult8
    ld de, ClassTable
    add hl, de
    ret

; A = 종족 번호 -> HL = RaceTable 의 그 줄.
RacePtr:
    ld h, a
    ld e, RACE_STRIDE
    call Mult8
    ld de, RaceTable
    add hl, de
    ret

;-----------------------------------------------------------------------------
; 파티 만들기
;
; battlefield.py 는 random.sample(list_classes(), 5) 로 직업이 겹치지 않게
; 뽑는다. 여기서는 여섯 명이라 열한 직업에서 여섯을 겹치지 않게 뽑는다.
; 이미 뽑은 직업은 16 비트 자리표로 기억한다.
;-----------------------------------------------------------------------------
MakeParty:
    ld hl, 0
    ld (ClassUsed), hl
    ld b, PARTY_N
    ld c, 0                     ; 사람 번호
.each:
    push bc
    ld a, c
    call MakeMember
    pop bc
    inc c
    djnz .each
    ret

; A = 사람 번호. 그 사람을 만든다.
;
; 기록 주소를 HL 에 들고 다니면 안 된다. RandMod 가 Rand16 을 부르고 그것이
; ld hl,(Seed) 로 HL 을 덮어쓰기 때문이다. 스택에 넣었다 빼는 것보다 이름 붙인
; 자리에 두는 편이 읽기 쉬워 MakePtr 를 쓴다.
MakeMember:
    call PartyPtr
    ld (MakePtr), hl

    call PickClass              ; 겹치지 않는 직업
    ld hl, (MakePtr)
    ld de, P_CLASS
    add hl, de
    ld (hl), a

    ld c, RACE_N                ; 종족은 겹쳐도 된다
    call RandMod
    ld hl, (MakePtr)
    ld de, P_RACE
    add hl, de
    ld (hl), a

    ld c, 3                     ; 레벨 1~3
    call RandMod
    inc a
    ld hl, (MakePtr)
    ld de, P_LEVEL
    add hl, de
    ld (hl), a

    ld hl, (MakePtr)
    call CalcStats
    ld hl, (MakePtr)
    jp MakeName

; 아직 안 쓴 직업 번호를 하나 뽑는다. A 로 돌려주고 자리표에 표시한다.
;
; 직업이 다섯인데 파티는 여섯이라 하나는 반드시 겹친다. 다 썼으면 자리표를 비워
; 다시 처음부터 뽑게 한다 - 안 비우면 빈 자리를 영영 못 찾고 맴돈다. 결과는
; **다섯 직업이 하나씩 다 나오고 여섯째만 무작위로 겹치는** 파티가 된다. 회복과
; 주문을 쓰는 직업이 빠진 파티가 나오지 않는 것이 이 게임에는 중요하다.
PickClass:
    ld hl, (ClassUsed)
    ld a, l
    and (1 << CLASS_N) - 1
    cp (1 << CLASS_N) - 1
    jr nz, .try
    ld hl, 0
    ld (ClassUsed), hl
.try:
    ld c, CLASS_N
    call RandMod
    ld e, a                     ; E = 후보
    ld hl, (ClassUsed)
    ld b, a
    inc b
    ld a, 1                     ; 후보 번호 자리의 비트를 만든다
    ld c, 0
.shift:
    dec b
    jr z, .made
    add a, a
    jr nc, .shift
    ld a, 1                     ; 8 번째를 넘으면 상위 바이트로
    inc c
    jr .shift
.made:
    ld d, a                     ; D = 비트, C = 0 이면 하위 / 1 이면 상위
    ld a, c
    or a
    jr nz, .hi
    ld a, l
    and d
    jr nz, .try                 ; 이미 썼다
    ld a, l
    or d
    ld l, a
    jr .done
.hi:
    ld a, h
    and d
    jr nz, .try
    ld a, h
    or d
    ld h, a
.done:
    ld (ClassUsed), hl
    ld a, e
    ret

;-----------------------------------------------------------------------------
; 능력치와 파생 수치. hero.py apply_class_stats 를 그대로 옮겼다.
;
;   능력치 = 10 + 직업 보정 + 종족 보정
;   max_hp = max(히트다이스, 30 + (레벨-1) * (5 + 건강 보정))
;   ac     = 12 + 민첩 보정
;   공격   = BAB(레벨, 직업 진행) + 힘 보정
;   피해   = 직업의 주사위 + 힘 보정
;
; HL = 사람 기록.
;-----------------------------------------------------------------------------
CalcStats:
    push hl
    ; --- 능력치 여섯 개 ---
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    call ClassPtr
    ld de, C_MODS
    add hl, de
    ld (TmpClassMods), hl       ; 직업 보정 여섯 개
    pop hl
    push hl
    ld de, P_RACE
    add hl, de
    ld a, (hl)
    call RacePtr                ; 종족 보정이 줄 머리에 있다
    ld (TmpRaceMods), hl
    pop hl

    push hl
    ld de, P_STR
    add hl, de
    ex de, hl                   ; DE = 쓸 자리
    ld hl, (TmpClassMods)
    ld bc, (TmpRaceMods)
    ld a, 6
.abil:
    push af
    ld a, 10
    add a, (hl)                 ; 직업 보정
    inc hl
    push hl
    ld h, b
    ld l, c
    add a, (hl)                 ; 종족 보정
    inc hl
    ld b, h
    ld c, l
    pop hl
    ld (de), a
    inc de
    pop af
    dec a
    jr nz, .abil
    pop hl

    ; --- 최대 HP ---
    push hl
    ld de, P_CON
    add hl, de
    ld a, (hl)
    call AbilityMod
    add a, 5                    ; 5 + 건강 보정
    ld c, a
    pop hl
    push hl
    ld de, P_LEVEL
    add hl, de
    ld a, (hl)
    dec a                       ; (레벨 - 1) 번 더한다
    ld b, a
    ld a, HERO_BASE_HP
    inc b                       ; djnz 가 먼저 줄이므로 하나 올려 둔다
    jr .hptest
.hploop:
    add a, c
.hptest:
    djnz .hploop
    ld c, a                     ; C = 계산한 HP
    pop hl
    push hl
    ld de, P_CLASS              ; 히트다이스보다는 커야 한다
    add hl, de
    ld a, (hl)
    call ClassPtr
    ld a, (hl)                  ; C_HITDIE
    cp c
    jr nc, .usedie
    ld a, c
.usedie:
    pop hl
    push hl
    ld de, P_MAXHP
    add hl, de
    ld (hl), a
    dec hl                      ; P_HP 는 바로 앞이다
    ld (hl), a
    pop hl

    ; --- MP (quest_sena.md 의 주문 포인트) ---
    ;
    ; 캐스터(마법사/성직자)만 갖는다. 레벨별 표에 지능 보정을 레벨만큼 더한다 -
    ; 문서에 "지능이 높으면 레벨업 될 때 더 많은 MP" 라고만 있어서 레벨마다 한
    ; 번씩 더하는 것으로 잡았다.
    push hl
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    call ClassPtr
    ld de, C_CASTER
    add hl, de
    ld a, (hl)
    pop hl
    or a
    ld a, 0                     ; ld 는 플래그를 안 건드린다
    jr z, .setmp                ; 캐스터가 아니면 0

    push hl
    ld de, P_LEVEL
    add hl, de
    ld a, (hl)
    cp MAX_LEVEL + 1            ; 표 밖으로 나가지 않게
    jr c, .lvok
    ld a, MAX_LEVEL
.lvok:
    ld (TmpLevel), a
    pop hl
    push hl
    ld de, P_INT
    add hl, de
    ld a, (hl)
    call AbilityMod
    ld c, a                     ; C = 지능 보정 (부호 있음)
    ld a, (TmpLevel)
    ld l, a
    ld h, 0
    ld de, MpTable
    add hl, de
    ld b, (hl)                  ; B = 표의 기본 MP
    ld a, (TmpLevel)
.mploop:
    push af
    ld a, b
    add a, c
    ld b, a
    pop af
    dec a
    jr nz, .mploop
    ld a, b
    bit 7, a
    jr z, .mppos
    xor a                       ; 지능이 낮아 음수가 되면 0
.mppos:
    pop hl
.setmp:
    push hl
    ld de, P_MAXSPL
    add hl, de
    ld (hl), a
    dec hl                      ; P_SPL 이 바로 앞이다
    ld (hl), a
    pop hl

    ; --- AC = 12 + 민첩 보정 ---
    push hl
    ld de, P_DEX
    add hl, de
    ld a, (hl)
    call AbilityMod
    add a, HERO_BASE_AC
    ld c, a
    pop hl
    push hl
    ld de, P_AC
    add hl, de
    ld (hl), c
    pop hl

    ; --- 공격 보정 = BAB + 힘 보정 ---
    push hl
    ld de, P_LEVEL
    add hl, de
    ld a, (hl)
    ld (TmpLevel), a
    pop hl
    push hl
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    call ClassPtr
    ld de, C_BAB
    add hl, de
    ld a, (hl)                  ; 0 good / 1 average / 2 poor
    add a, a
    ld e, a
    ld d, 0
    ld hl, BabTables
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)                  ; DE = 그 진행의 레벨별 표
    ld a, (TmpLevel)
    ld l, a
    ld h, 0
    add hl, de
    ld a, (hl)                  ; BAB
    ld (TmpBab), a
    pop hl
    push hl
    ld de, P_STR
    add hl, de
    ld a, (hl)
    call AbilityMod
    ld hl, TmpBab
    add a, (hl)
    ld c, a                     ; 공격 보정
    pop hl
    push hl
    ld de, P_ATK
    add hl, de
    ld (hl), c
    pop hl

    ; --- 피해 주사위와 보정 ---
    push hl
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    call ClassPtr
    ld de, C_DCNT
    add hl, de
    ld c, (hl)                  ; 개수
    inc hl
    ld b, (hl)                  ; 면
    pop hl
    push hl
    ld de, P_DCNT
    add hl, de
    ld (hl), c
    inc hl
    ld (hl), b
    pop hl
    push hl
    ld de, P_STR
    add hl, de
    ld a, (hl)
    call AbilityMod
    ld c, a
    pop hl
    push hl
    ld de, P_DMOD
    add hl, de
    ld (hl), c                  ; P_SPL / P_MAXSPL 은 위의 MP 절이 이미 채웠다.
    pop hl                      ; 예전에는 여기서 0 으로 지웠는데, 그대로 두면
    ret                         ; 캐스터의 MP 를 도로 지운다.

;-----------------------------------------------------------------------------
; 이름 만들기. 원본에는 이름 생성기가 없어 음절 표를 새로 넣었다.
; 앞 + 가운데 + 뒤를 붙이고 공백은 버린다. 12 칸을 공백으로 채운다.
;
; HL = 사람 기록.
;-----------------------------------------------------------------------------
MakeName:
    push hl
    ld b, NAME_LEN              ; 먼저 공백으로 채운다
    ld d, h
    ld e, l
.blank:
    ld a, ' '
    ld (de), a
    inc de
    djnz .blank
    pop hl
    ld (NamePtr), hl

    ld hl, SylHead
    ld c, SYL_HEAD_N
    ld b, SYL_HEAD_W
    call AddSyllable
    ld hl, SylMid
    ld c, SYL_MID_N
    ld b, SYL_MID_W
    call AddSyllable
    ld hl, SylTail
    ld c, SYL_TAIL_N
    ld b, SYL_TAIL_W
    call AddSyllable
    ret

; HL = 음절 표, C = 개수, B = 한 칸 길이. 하나 골라 이름 뒤에 붙인다.
AddSyllable:
    push hl
    push bc
    call RandMod                ; A = 0 ~ C-1
    pop bc
    pop hl
    ld e, b                     ; 한 칸 길이만큼 곱한다
    ld d, 0
.mul:
    or a
    jr z, .got
    add hl, de
    dec a
    jr .mul
.got:
    ld de, (NamePtr)
.copy:
    ld a, (hl)
    cp ' '
    jr z, .skip                 ; 채움 공백은 버린다
    ld (de), a
    inc de
.skip:
    inc hl
    djnz .copy
    ld (NamePtr), de
    ret


;-----------------------------------------------------------------------------
; 파티 칸 그리기
;
; 배경의 머리글(CHARACTER AC HIT PTS SPL PTS CL) 아래 여섯 줄을 채운다. 자리는
; questrules.asm 의 COL_* 이고 배경 그림에서 잰 값이다.
;-----------------------------------------------------------------------------
DrawParty:
    ld a, COL_BLACK
    ld b, COL_PANEL
    call SetColours
    ld a, ROW_Y0
    ld (RowY), a
    ld b, PARTY_N
    ld c, 0
.each:
    push bc
    ld a, c
    call DrawMember
    ld a, (RowY)
    add a, ROW_DY
    ld (RowY), a
    pop bc
    inc c
    djnz .each
    ret

; A = 사람 번호. RowY 줄에 그 사람을 찍는다.
DrawMember:
    ld (RowNo), a
    call PartyPtr
    ld (MemPtr), hl

    ld a, (RowY)                ; 번호
    ld c, a
    ld b, COL_NUM
    call SetPos
    ld a, (RowNo)
    add a, '1'
    call PutChar

    ld a, (RowY)                ; 이름
    ld c, a
    ld b, COL_NAME
    call SetPos
    ld hl, (MemPtr)
    ld b, NAME_LEN
    call PutStrN

    ld e, P_AC
    ld b, COL_AC
    call .field
    ld e, P_HP
    ld b, COL_HIT
    call .field
    ld e, P_MAXHP
    ld b, COL_PTS
    call .field
    ld e, P_SPL
    ld b, COL_SPL
    call .field
    ld e, P_MAXSPL
    ld b, COL_SPTS
    call .field

    ld a, (RowY)                ; 직업 약자
    ld c, a
    ld b, COL_CL
    call SetPos
    ld hl, (MemPtr)
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    call ClassPtr
    ld de, C_ABBREV
    add hl, de
    ld b, 2
    jp PutStrN

; E = 기록 안의 자리, B = x. 그 값을 세 칸 오른쪽 맞춤으로.
.field:
    push de
    ld a, (RowY)
    ld c, a
    call SetPos
    pop de
    ld hl, (MemPtr)
    ld d, 0
    add hl, de
    ld a, (hl)
    ld b, 3
    jp PutNumR
