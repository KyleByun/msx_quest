;-----------------------------------------------------------------------------
; 파티원 상태 화면 - 오른쪽 양피지 창에 한 사람씩 보여준다
;
; 1~6 키로 그 번호의 사람을, 좌우 화살표로 앞뒤 사람으로 넘긴다. 6 에서
; 오른쪽은 1 로, 1 에서 왼쪽은 6 으로 돌아간다. 같은 번호를 다시 누르거나
; 스페이스를 누르면 닫힌다.
;
; 미니맵과 같은 자리(양피지)를 쓰므로 둘은 서로를 끈다. 전투 중에는 그 자리가
; 전투 기록 차지라 열지 않는다.
;
; **줄 간격이 여기만 다르다.** 전투 기록은 MSG_DY(8) 로 흐르는데, 그 값은
; MsgScroll 의 VDP 명령 기하에 박혀 있어서 2 의 거듭제곱이어야 한다. 이 화면은
; 스크롤하지 않으므로 그 제약이 없고, 한글이 8 줄을 다 쓰기 때문에 8 로 두면
; 줄끼리 붙어 읽기 어렵다. 그래서 STAT_DY = 9 로 한 픽셀 띄운다.
;-----------------------------------------------------------------------------

STAT_DY     equ 9                   ; 이 화면만의 줄 간격 (기록창은 MSG_DY = 8)
STAT_ROWS   equ 11                  ; 마지막 줄 8 + 10*9 = 98, +8 = 106 < 111
STAT_X2     equ MSG_X + 8 * FONT_W  ; 두 칸짜리 줄의 오른쪽 자리

; 입력이 어느 단계에 있는가. ESC 로 한 단계씩 물러난다.
MODE_PAGE   equ 0               ; 쪽/사람 넘기기
MODE_CURSOR equ 1               ; 목록에서 하나 고르기
MODE_ACTION equ 2               ; 장착·사용 / 전달 / 버리기
MODE_GIVE   equ 3               ; 누구에게 줄지 번호 입력

ACT_EQUIP   equ 0
ACT_GIVE    equ 1
ACT_DROP    equ 2
ACT_N       equ 3
STAT_MENUROW equ 10             ; 동작 메뉴가 앉는 줄 (맨 아래)

;-----------------------------------------------------------------------------
; 상태 화면을 켜거나 끈다. A = 보여줄 사람 번호(0~5).
;
; 이미 그 사람을 보고 있으면 닫는다 - 같은 숫자를 두 번 누르면 닫히는 셈이다.
;-----------------------------------------------------------------------------
ToggleStat:
    ld b, a
    ld a, (StatOn)
    or a
    jr z, .open                 ; 닫혀 있으면 연다
    ld a, (StatWho)
    cp b
    jr nz, .show                ; 다른 사람이면 그 사람으로 갈아 끼운다
    jp CloseStat
.open:
    ld a, 1
    ld (StatOn), a
    ld a, (MapOn)               ; 미니맵과 같은 자리를 쓴다
    or a
    jr z, .show
    xor a
    ld (MapOn), a
.show:
    ld a, b
    ld (StatWho), a
    xor a
    ld (StatMode), a            ; 사람이 바뀌면 커서는 접는다
    call StatClampPage
    jp DrawStat

; 마법 쪽을 보다가 캐스터가 아닌 사람으로 넘어가면 첫 쪽으로 되돌린다.
StatClampPage:
    call StatCountPages
    ld a, (StatPage)
    ld hl, StatPages
    cp (hl)
    ret c
    xor a
    ld (StatPage), a
    ret

;-----------------------------------------------------------------------------
; StatPageDelta - A = 0 이면 다음 쪽, 1 이면 이전 쪽. 끝에서 돌아 감는다.
;
; 쪽 수는 사람마다 다르다 - 마법을 쓰는 직업만 네 번째(마법) 쪽이 있다.
;-----------------------------------------------------------------------------
StatPageDelta:
    ld (StatDir), a             ; StatCountPages 가 Mult8 을 거쳐 B 를 뭉갠다
    call StatCountPages
    ld a, (StatDir)
    ld b, a
    ld a, (StatPage)
    bit 0, b
    jr nz, .prev
    inc a
    ld hl, StatPages
    cp (hl)
    jr c, .go
    xor a                       ; 마지막 쪽에서 아래 -> 첫 쪽
    jr .go
.prev:
    dec a
    jp p, .go
    ld a, (StatPages)           ; 첫 쪽에서 위 -> 마지막 쪽
    dec a
.go:
    ld (StatPage), a
    xor a
    ld (StatMode), a            ; 쪽이 바뀌면 커서는 접는다
    jp DrawStat

; 이 사람의 쪽 수를 센다. 캐스터면 마법 쪽이 하나 더 있다.
StatCountPages:
    ld a, (StatWho)
    call PartyPtr
    ld de, P_CLASS
    add hl, de
    ld a, (hl)
    call ClassPtr
    ld de, C_CASTER
    add hl, de
    ld a, (hl)
    or a
    ld a, 3
    jr z, .set
    ld a, 4
.set:
    ld (StatPages), a
    ret

CloseStat:
    xor a
    ld (StatOn), a
    ld (StatMode), a
    jp MsgClear                 ; 빈 양피지로 돌아간다

;-----------------------------------------------------------------------------
; 앞/뒤 사람으로. A = 0 이면 다음, 1 이면 이전. 끝에서 돌아 감는다.
;-----------------------------------------------------------------------------
StatNext:
    ld b, a
    ld a, (StatWho)
    bit 0, b
    jr nz, .prev
    inc a
    cp PARTY_N
    jr c, .go
    xor a                       ; 6 번에서 오른쪽 -> 다시 1 번
    jr .go
.prev:
    dec a
    jp p, .go
    ld a, PARTY_N - 1           ; 1 번에서 왼쪽 -> 6 번
.go:
    ld (StatWho), a
    jp DrawStat

;-----------------------------------------------------------------------------
; StatWho 번째 사람을 양피지에 그린다.
;
; 아직 없는 것을 지어내지 않는다. 장비와 소지품 체계가 게임에 없으므로
; 소지품 줄은 '없음' 으로 둔다. 무장 상태로 보여 줄 수 있는 참된 값은
; 전투가 실제로 굴리는 피해 주사위(P_DCNT d P_DSIDE + P_DMOD) 다.
;-----------------------------------------------------------------------------
DrawStat:
    call WaitVdpCmd
    call MsgClear
    ld a, (StatPage)
    or a
    jr z, DrawStatPage
    dec a
    jp z, DrawWeaponPage
    dec a
    jp z, DrawItemPage
    jp DrawMagicPage

DrawStatPage:
    ld a, (StatWho)
    call PartyPtr
    ld (StatPtr), hl

    xor a
    ld (StatRow), a

    ; --- 1 BLOODCRANE ----------------------------------------------------
    call StatLine
    ld a, (StatWho)
    inc a
    ld b, 1
    call PutNumR
    ld a, ' '
    call PutChar
    ld hl, (StatPtr)
    ld b, NAME_LEN
    call PutStrN

    ; --- 인간 전사 LV 3 ---------------------------------------------------
    call StatLine
    ld de, P_RACE
    call StatField              ; A = 종족 번호
    ld h, a
    ld e, RACENAME_LEN
    call Mult8
    ld de, (RaceNameTab)
    add hl, de
    call PutStr
    ld a, ' '
    call PutChar
    call StatClass              ; HL = 직업 이름
    call PutStr
    ld a, ' '
    call PutChar
    ld a, MSG_ST_LV
    call MsgText
    call PutStr
    ld de, P_LEVEL
    call StatField
    ld b, 2
    call PutNumR

    call StatBlank

    ; --- HP  30/ 30 -------------------------------------------------------
    ld a, MSG_ST_HP
    ld de, P_HP
    ld hl, P_MAXHP
    call StatPair

    ; --- MP   4/  4 -------------------------------------------------------
    ld a, MSG_ST_MP
    ld de, P_SPL
    ld hl, P_MAXSPL
    call StatPair

    ; --- 방어 15   공격 +4 ------------------------------------------------
    call StatLine
    ld a, MSG_ST_AC
    ld de, P_AC
    call StatLabelNum
    ld b, STAT_X2
    call StatCol2
    ld a, MSG_ST_ATK
    ld de, P_ATK
    call StatLabelNum

    ; --- 피해 1D8+2 -------------------------------------------------------
    call StatLine
    ld a, MSG_ST_DMG
    call StatLabel
    ld de, P_DCNT
    call StatField
    ld b, 1
    call PutNumR
    ld a, 'D'
    call PutChar
    ld de, P_DSIDE
    call StatField
    ld b, 1                     ; 붙여 찍는다 - PutNumR 은 자리보다 길면 그냥 찍는다
    call PutNumR
    ld de, P_DMOD               ; 0 이면 붙이지 않는다
    call StatField
    or a
    jr z, .nomod
    ld a, '+'
    call PutChar
    ld de, P_DMOD
    call StatField
    ld b, 1
    call PutNumR
.nomod:

    ; --- 능력치 여섯. 한 줄에 둘씩 ----------------------------------------
    ; 빈 줄을 여기 하나 더 두면 마지막 줄이 양피지 아래끝을 넘는다
    ; (8 + 11*9 = 107, 글자 높이 8 -> 115 > 111).
    ld a, MSG_ST_STR
    ld de, P_STR
    ld hl, (P_DEX << 8) | MSG_ST_DEX
    call StatAbil
    ld a, MSG_ST_CON
    ld de, P_CON
    ld hl, (P_INT << 8) | MSG_ST_INT
    call StatAbil
    ld a, MSG_ST_WIS
    ld de, P_WIS
    ld hl, (P_CHA << 8) | MSG_ST_CHA
    call StatAbil

    ; --- 소지품 없음 ------------------------------------------------------
    ; 장비와 소지품 체계가 아직 없다. 지어내지 않고 빈 것으로 둔다.
    call StatLine
    ld a, MSG_ST_ITEMS
    call MsgText
    call PutStr
    ld a, ' '
    call PutChar
    ld a, MSG_ST_NONE
    call MsgText
    jp PutStr

;-----------------------------------------------------------------------------
; 다음 줄로 내려가 색을 잡는다. StatRow 를 하나 올린다.
;-----------------------------------------------------------------------------
StatLine:
    push af
    push bc
    push de
    push hl
    ld a, (StatRow)
    ld b, a
    add a, a
    add a, a
    add a, a
    add a, b                    ; 줄 번호 * 9
    add a, MSG_Y
    ld c, a
    ld b, MSG_X
    call SetPos
    ld a, COL_BLACK
    ld b, COL_CREAM
    call SetColours
    ld hl, StatRow
    inc (hl)
    pop hl
    pop de
    pop bc
    pop af
    ret

StatBlank:
    ld hl, StatRow
    inc (hl)
    ret

; B = x. 같은 줄 안에서 자리만 옮긴다.
StatCol2:
    ld a, b
    ld (TextX), a
    ret

; DE = 칸 번호 -> A = 그 사람의 그 값
StatField:
    push hl
    ld hl, (StatPtr)
    add hl, de
    ld a, (hl)
    pop hl
    ret

; A = 메시지 번호. 이름을 찍고 공백 하나.
StatLabel:
    call MsgText
    call PutStr
    ld a, ' '
    jp PutChar

; A = 이름 번호, DE = 칸 번호. "이름 값" 을 찍는다.
StatLabelNum:
    push de
    call StatLabel
    pop de
    call StatField
    ld b, 2
    jp PutNumR

; A = 이름 번호, DE = 지금 값 칸, HL = 최대 값 칸. "이름  4/  4" 한 줄.
StatPair:
    push hl
    push de
    push af
    call StatLine
    pop af
    call StatLabel
    pop de
    call StatField
    ld b, 3
    call PutNumR
    ld a, '/'
    call PutChar
    pop de                      ; 최대값 칸
    call StatField
    ld b, 3
    jp PutNumR

; A = 왼쪽 이름 번호, DE = 왼쪽 칸, H = 오른쪽 칸, L = 오른쪽 이름 번호
StatAbil:
    push hl
    push de
    push af
    call StatLine
    pop af
    call StatLabel
    pop de
    call StatField
    ld b, 2
    call PutNumR
    ld b, STAT_X2
    call StatCol2
    pop hl
    push hl
    ld a, l
    call StatLabel
    pop hl
    ld e, h
    ld d, 0
    call StatField
    ld b, 2
    jp PutNumR

; HL = 이 사람의 직업 이름 (지금 말로)
StatClass:
    ld de, P_CLASS
    call StatField
    ld h, a
    ld e, CLASSNAME_LEN
    call Mult8
    ld de, (ClassNameTab)
    add hl, de
    ret

;-----------------------------------------------------------------------------
; 가방 쪽 - 무기 쪽은 차는 것, 소지품 쪽은 쓰는 것만 늘어놓는다.
;
; 스페이스를 누르면 커서가 서고(StatMode = MODE_CURSOR), 화살표로 고른 뒤 다시
; 스페이스를 누르면 장착/사용 - 전달 - 버리기 메뉴가 뜬다. ESC 로 한 단계씩
; 물러난다.
;
; 차고 있는 것 앞에는 E 가 붙는다.
;-----------------------------------------------------------------------------
DrawWeaponPage:
    ld a, SLOT_WEAPON           ; 0 이 아닌 자리 = 차는 것
    ld (StatFilter), a
    jr DrawBag

DrawItemPage:
    ld a, SLOT_USE              ; 0 = 쓰는 것
    ld (StatFilter), a
DrawBag:
    call StatHeader
    xor a
    ld (StatIdx), a             ; 가방 칸
    ld (StatShown), a           ; 화면에 몇 줄 찍었나
.row:
    ld a, (StatIdx)
    ld b, a
    ld a, (StatWho)
    call InvItem
    cp INV_EMPTY
    jp z, .next
    ld (StatItem), a
    call ItemSlot
    ld b, a                     ; B = 이 품목의 자리
    ld a, (StatFilter)
    or a
    jr nz, .wantgear
    ld a, b                     ; 소지품 쪽은 자리 0 만
    or a
    jp nz, .next
    jr .show
.wantgear:
    ld a, b                     ; 무기 쪽은 자리 1 이상만
    or a
    jp z, .next
.show:
    call StatLine

    ld a, (StatMode)            ; 커서가 서 있으면 그 줄에 화살표
    or a
    jr z, .nocur
    ld a, (StatShown)
    ld hl, StatCur
    cp (hl)
    jr nz, .nocur
    ld a, MSG_MENU_ON
    jr .curdone
.nocur:
    ld a, MSG_MENU_OFF
.curdone:
    call MsgText
    call PutStr

    ld a, (StatIdx)             ; 차고 있으면 E
    ld b, a
    ld a, (StatWho)
    call IsEquipped
    ld a, 'E'
    jr z, .mark
    ld a, ' '
.mark:
    call PutChar
    ld a, ' '
    call PutChar

    ld a, (StatItem)            ; 이름
    ld h, a
    ld e, WEAPONNAME_LEN
    call Mult8
    ld de, (WeaponNameTab)
    add hl, de
    call PutStr

    ld a, (StatFilter)          ; 무기면 피해 주사위를 오른쪽에
    or a
    jr z, .counted
    ld a, (StatItem)
    call ItemSlot
    cp SLOT_WEAPON
    jr nz, .counted
    ld b, MSG_X + 12 * FONT_W
    call StatCol2
    ld a, (StatItem)
    call ItemPtr
    inc hl
    ld b, (hl)
    inc hl
    ld c, (hl)
    ld a, b
    ld b, 1
    push bc
    call PutNumR
    ld a, 'D'
    call PutChar
    pop bc
    ld a, c
    ld b, 1
    call PutNumR
.counted:
    ld hl, StatShown
    inc (hl)
.next:
    ld hl, StatIdx
    inc (hl)
    ld a, (hl)
    cp INV_N
    jp c, .row

    ld a, (StatShown)           ; 아무것도 없으면 그렇게 적는다
    or a
    jr nz, .menu
    call StatLine
    ld a, MSG_ST_EMPTY
    call MsgText
    call PutStr
.menu:
    ld a, (StatMode)            ; 동작 메뉴가 떠 있으면 아래에 붙인다
    cp MODE_ACTION
    jp z, DrawActionMenu
    cp MODE_GIVE
    jp z, DrawGivePrompt
    ret

;-----------------------------------------------------------------------------
; 동작 메뉴 - 장착(또는 사용) / 전달 / 버리기
;-----------------------------------------------------------------------------
DrawActionMenu:
    ld a, STAT_MENUROW
    ld (StatRow), a
    call StatLine
    xor a
    ld (StatAct), a
.row:
    ld a, (StatAct)
    ld hl, StatSel
    cp (hl)
    ld a, MSG_MENU_ON
    jr z, .mark
    ld a, MSG_MENU_OFF
.mark:
    call MsgText
    call PutStr
    ld a, (StatAct)
    or a
    jr nz, .other
    ld a, (StatFilter)          ; 첫 칸은 쪽에 따라 장착/사용
    or a
    ld a, MSG_ST_EQUIPCMD
    jr nz, .name
    ld a, MSG_ST_USECMD
    jr .name
.other:
    dec a
    ld a, MSG_ST_GIVE
    jr z, .name
    ld a, MSG_ST_DROP
.name:
    call MsgText
    call PutStr
    ld hl, StatAct
    inc (hl)
    ld a, (hl)
    cp ACT_N
    jr c, .row
    ret

;-----------------------------------------------------------------------------
; 전달 - 누구에게 줄지 번호를 묻는다
;-----------------------------------------------------------------------------
DrawGivePrompt:
    ld a, STAT_MENUROW
    ld (StatRow), a
    call StatLine
    ld a, MSG_ST_TOWHO
    call MsgText
    jp PutStr

;-----------------------------------------------------------------------------
; 마법 쪽 - 캐스터만 온다. 주문 목록이 아직 없어 MP 만 보여 준다.
;-----------------------------------------------------------------------------
DrawMagicPage:
    call StatHeader
    ld a, MSG_ST_MP
    ld de, P_SPL
    ld hl, P_MAXSPL
    call StatPair
    call StatBlank
    call StatLine
    ld a, MSG_ST_MAGIC
    call StatLabel
    ld a, MSG_ST_NONE
    call MsgText
    jp PutStr

;-----------------------------------------------------------------------------
; 어느 쪽에나 붙는 머리글 - "1 이름" 과 지금 쪽 이름
;-----------------------------------------------------------------------------
StatHeader:
    ld a, (StatWho)
    call PartyPtr
    ld (StatPtr), hl
    xor a
    ld (StatRow), a

    call StatLine
    ld a, (StatWho)
    inc a
    ld b, 1
    call PutNumR
    ld a, ' '
    call PutChar
    ld hl, (StatPtr)
    ld b, NAME_LEN
    call PutStrN

    call StatLine
    ld a, (StatPage)
    ld hl, StatPageName
    ld e, a
    ld d, 0
    add hl, de
    ld a, (hl)
    call MsgText
    jp PutStr                   ; 빈 줄을 두지 않는다 - 목록 한 줄이 아쉽다

StatPageName:
    db MSG_ST_EQUIP, MSG_ST_WEAPON, MSG_ST_ITEMS, MSG_ST_MAGIC

;-----------------------------------------------------------------------------
; 커서가 가리키는 가방 칸을 찾는다 -> B = 가방 칸, NZ 면 없음
;
; 화면에는 걸러 낸 것만 보이므로 '화면 몇 번째' 와 '가방 몇 번째' 가 다르다.
;-----------------------------------------------------------------------------
StatCursorSlot:
    xor a
    ld (StatIdx), a
    ld (StatShown), a
.loop:
    ld a, (StatIdx)
    ld b, a
    ld a, (StatWho)
    call InvItem
    cp INV_EMPTY
    jr z, .next
    call ItemSlot
    ld c, a
    ld a, (StatFilter)
    or a
    jr nz, .wantgear
    ld a, c
    or a
    jr nz, .next
    jr .hit
.wantgear:
    ld a, c
    or a
    jr z, .next
.hit:
    ld a, (StatShown)
    ld hl, StatCur
    cp (hl)
    jr nz, .bump
    ld a, (StatIdx)
    ld b, a
    xor a                       ; Z = 찾았다
    ret
.bump:
    ld hl, StatShown
    inc (hl)
.next:
    ld hl, StatIdx
    inc (hl)
    ld a, (hl)
    cp INV_N
    jr c, .loop
    or a
    ld a, 1
    or a                        ; NZ = 없음
    ret

; 지금 쪽에 보이는 줄이 몇 개인가 -> A
StatCountShown:
    xor a
    ld (StatIdx), a
    ld (StatShown), a
.loop:
    ld a, (StatIdx)
    ld b, a
    ld a, (StatWho)
    call InvItem
    cp INV_EMPTY
    jr z, .next
    call ItemSlot
    ld c, a
    ld a, (StatFilter)
    or a
    jr nz, .wantgear
    ld a, c
    or a
    jr nz, .next
    jr .hit
.wantgear:
    ld a, c
    or a
    jr z, .next
.hit:
    ld hl, StatShown
    inc (hl)
.next:
    ld hl, StatIdx
    inc (hl)
    ld a, (hl)
    cp INV_N
    jr c, .loop
    ld a, (StatShown)
    ret

;-----------------------------------------------------------------------------
; StatEscape - ESC. 한 단계 물러난다. 맨 위(MODE_PAGE)에서는 화면을 닫는다.
;-----------------------------------------------------------------------------
StatEscape:
    ld a, (StatMode)
    or a
    jp z, CloseStat
    dec a
    ld (StatMode), a
    jp DrawStat

;-----------------------------------------------------------------------------
; StatEnterList - 스페이스. 가방 쪽이면 커서를 세운다.
;-----------------------------------------------------------------------------
StatEnterList:
    ld a, (StatPage)
    or a
    ret z                       ; 상태 쪽에는 고를 것이 없다
    cp 3
    ret z                       ; 마법 쪽도 아직 없다
    call StatCountShown
    or a
    ret z                       ; 빈 가방
    xor a
    ld (StatCur), a
    ld a, MODE_CURSOR
    ld (StatMode), a
    jp DrawStat

;-----------------------------------------------------------------------------
; StatMoveCursor - A = 0 이면 다음, 1 이면 이전. 감아 돈다.
;-----------------------------------------------------------------------------
StatMoveCursor:
    ld (StatDir), a
    ld a, (StatMode)
    cp MODE_ACTION
    jr z, .action

    call StatCountShown         ; 목록 커서
    ld b, a
    ld a, (StatDir)
    ld hl, StatCur
    jr .move
.action:
    ld b, ACT_N                 ; 동작 메뉴 커서
    ld a, (StatDir)
    ld hl, StatSel
.move:
    or a
    jr nz, .prev
    inc (hl)
    ld a, (hl)
    cp b
    jr c, .done
    ld (hl), 0
    jr .done
.prev:
    ld a, (hl)
    or a
    jr nz, .dec
    ld a, b
    ld (hl), a
.dec:
    dec (hl)
.done:
    jp DrawStat

;-----------------------------------------------------------------------------
; StatConfirm - 스페이스. 단계에 따라 다음으로 넘어가거나 실행한다.
;-----------------------------------------------------------------------------
StatConfirm:
    ld a, (StatMode)
    cp MODE_CURSOR
    jr z, .toaction
    cp MODE_ACTION
    ret nz                      ; MODE_GIVE 는 숫자로만 받는다
    ld a, (StatSel)
    cp ACT_GIVE
    jr z, .give
    cp ACT_DROP
    jr z, .drop

    call StatCursorSlot         ; 장착 또는 사용
    ret nz
    ld a, (StatFilter)
    or a
    jr z, .use
    ld a, (StatWho)
    call EquipInv
    jr .back
.use:
    ld a, (StatWho)
    call UseInv
    jr .back
.drop:
    call StatCursorSlot
    ret nz
    ld a, (StatWho)
    call DropInv
.back:
    ld a, MODE_CURSOR           ; 목록으로 돌아간다
    ld (StatMode), a
    call StatFixCursor
    jp DrawStat
.give:
    ld a, MODE_GIVE
    ld (StatMode), a
    jp DrawStat
.toaction:
    xor a
    ld (StatSel), a
    ld a, MODE_ACTION
    ld (StatMode), a
    jp DrawStat

; 목록이 줄어들어 커서가 밖으로 나갔으면 끌어들인다.
StatFixCursor:
    call StatCountShown
    or a
    jr z, .none
    ld b, a
    ld a, (StatCur)
    cp b
    ret c
    ld a, b
    dec a
    ld (StatCur), a
    ret
.none:
    xor a
    ld (StatCur), a
    ld a, MODE_PAGE             ; 다 비었으면 커서를 접는다
    ld (StatMode), a
    ret

;-----------------------------------------------------------------------------
; StatNumber - A = 눌린 숫자(0~5).
;
; 전달을 고른 뒤라면 받는 사람이고, 그 밖에는 볼 사람이다.
;-----------------------------------------------------------------------------
StatNumber:
    ld (StatNum), a             ; StatCursorSlot 이 C 를 쓴다. 먼저 치워 둔다 -
    ld a, (StatOn)              ; C 에 두었더니 전달이 조용히 아무 일도 안 했다.
    or a
    jr z, .who
    ld a, (StatMode)
    cp MODE_GIVE
    jr nz, .who

    call StatCursorSlot         ; B = 가방 칸
    jr nz, .cancel
    ld a, (StatNum)
    ld c, a                     ; C = 받는 사람
    ld a, (StatWho)
    call GiveInv
    ld a, MODE_CURSOR
    ld (StatMode), a
    call StatFixCursor
    jp DrawStat
.cancel:
    ld a, MODE_CURSOR
    ld (StatMode), a
    jp DrawStat
.who:
    ld a, (StatNum)
    jp ToggleStat
