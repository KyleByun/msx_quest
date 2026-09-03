;----------------------------------------------------------------------------
; 이 파일은 gfx/quest_rules.py 가 만든다. 직접 고치지 말 것.
;
; D&D 규칙 자료를 D:/my/python/dnd 에서 가져와 표로 펼쳤다. Z80 에서 곱셈과
; 나눗셈을 피하려는 것이다. 특히 능력치 보정은 (점수-10)//2 인데 파이썬의
; 내림 나눗셈이라 음수 쪽이 -1, -2 로 떨어지고, BAB 의 average 는
; int(레벨*0.75) 라 레벨 1 에서 0 이다. 둘 다 흉내 내면 틀리기 쉬워 표로 굽는다.
;----------------------------------------------------------------------------

; --- 파티 기록 (한 명 32 바이트) ---------------------------------------
PARTY_N      equ 6
PARTY_STRIDE equ 32                 ; 2 의 거듭제곱이라 색인이 시프트로 끝난다
P_NAME       equ 0               ; 이름 12 글자
P_CLASS      equ 12 
P_RACE       equ 13 
P_STR        equ 14 
P_DEX        equ 15 
P_CON        equ 16 
P_INT        equ 17 
P_WIS        equ 18 
P_CHA        equ 19 
P_LEVEL      equ 20 
P_HP         equ 21 
P_MAXHP      equ 22 
P_AC         equ 23 
P_ATK        equ 24 
P_DCNT       equ 25 
P_DSIDE      equ 26 
P_DMOD       equ 27 
P_SPL        equ 28 
P_MAXSPL     equ 29 
P_GUARD      equ 30 
NAME_LEN     equ 12

; --- 몬스터 기록 (한 마리 4 바이트) -------------------------------------
; 종류 번호만 들고 나머지는 ROM 표에서 본다. 전투 중에 변하는 것은 HP 뿐이다.
MON_N        equ 5
MON_STRIDE   equ 4
M_TYPE       equ 0
M_HP         equ 1
M_MAXHP      equ 2
M_PAD        equ 3

; --- 하단 파티 칸 배치 (배경의 머리글 위치에 맞췄다) ---------------------
ROW_Y0       equ 152               ; 첫 줄 y
ROW_DY       equ 10                ; 8(글자 높이) + 2 dot. 줄 사이가 붙어 보여서 늘렸다.
                                    ; 마지막 줄(6번)이 y=202~209, 그 아래 y=210 부터 패널 테두리다 - 꼭 맞는다.
COL_NUM      equ 2                 ; 번호
COL_NAME     equ 10                ; 이름 (12 글자). 번호 바로 뒤라서 1 dot 띄운다.
                                    ; x 는 짝수여야 한다(TextAddr 가 바이트 단위로 찍는다) - 2px 가 최소 단위.
COL_AC       equ 108               ; 이하 세 글자씩 오른쪽 맞춤
COL_HIT      equ 132
COL_PTS      equ 162
COL_SPL      equ 190
COL_SPTS     equ 214
COL_CL       equ 240               ; 직업 약자 두 글자

; --- 오른쪽 메시지 칸 ---------------------------------------------------
MSG_X        equ 136
MSG_Y        equ 8
MSG_DY       equ 8                 ; 2 의 거듭제곱이라 곱셈이 시프트로 끝난다
MSG_ROWS     equ 13                ; 라운드 머리글 + 영웅 6 + 몬스터 5 + 여유
MSG_W        equ 17                ; 한 줄 글자 수 (136 + 17*6 = 238)
; 창을 위아래로 나눈다. 위는 전투 기록이 흘러가고 아래는 명령 메뉴다.
; 명령을 한 줄에 둘씩 놓아 메뉴가 3 줄이면 되므로 기록이 10 줄을 쓴다.
LOG_ROWS     equ 10
MENU_ROW     equ LOG_ROWS
MENU_ROWS    equ MSG_ROWS - LOG_ROWS

; --- 폰트 6x8, ASCII 32~90 ---------------------------------------------
FONT_FIRST   equ 32
FONT_LAST    equ 90
FONT_W       equ 6                 ; 다음 글자까지의 간격
FONT_H       equ 8
RACE_N       equ 7
RACE_STRIDE  equ 14
CLASS_N      equ 5
CLASS_STRIDE equ 23
C_HITDIE     equ 0
C_BAB        equ 1
C_MODS       equ 2
C_DCNT       equ 8
C_DSIDE      equ 9
C_CASTER     equ 10                ; MP 를 쓰는 직업인가
C_ABBREV     equ 11
C_NAME       equ 13
MAX_LEVEL    equ 10
SKILL_STRIDE equ 11
SK_EFF       equ 0                 ; 효과 번호
SK_NAME      equ 1                 ; 0 으로 끝나는 이름
MONSTER_N    equ 6
MON_TSTRIDE  equ 21
T_AC         equ 0
T_HP         equ 1
T_STR        equ 2
T_DCNT       equ 3
T_DSIDE      equ 4
T_MAXGRP     equ 5                 ; 한 번에 몇 마리까지 나오는가
T_DEX        equ 6                 ; 민첩 - 라운드당 행동 횟수를 정한다
T_SPRBANK    equ 7                 ; 그림이 든 ROM 뱅크
T_SPRADDR    equ 8                 ; 그 뱅크 안의 주소
T_NAME       equ 10
; --- 대열 (몬스터 여럿을 나란히) --------------------------------------
MON_SCALE_N  equ 5                 ; 한 번에 몇 마리까지 나오는가
MON_SCALE_ST equ 3                 ; 한 칸 = 뱅크 1 + 주소 2
MON_MAX_COLS equ 4                 ; 가장 많이 늘어설 때의 칸 수
ARROW_W      equ 12
ARROW_H      equ 6
ARROW_GAP    equ 2                 ; 화살표 끝과 머리 사이
DOT_N        equ 5                 ; HP 게이지 점 수 (하나가 20%)
DOT_W        equ 3
DOT_H        equ 4
DOT_GAP      equ 1
DOT_TOP      equ 2                 ; 몬스터 아랫변과 점 사이
DOT_ROW_W    equ 19                ; 점 다섯 줄의 폭
NAME_CONS_N  equ 15
NAME_VOW_N   equ 5
NAME_PAT_N   equ 6
NAME_PAT_W   equ 8

HERO_BASE_HP equ 30
HERO_BASE_AC equ 12

; --- 몬스터 그림이 어느 뱅크 어디에 있는가 -----------------------------
SPR_W        equ 96
SPR_H        equ 96
SPR_BANKS    equ 4
SPR_FIRSTBK  equ 3
SPR_BANK_0_W24 equ 3                  ; GOBLIN 24px
SPR_ADDR_0_W24 equ 0xAB6F
SPR_BANK_0_W32 equ 3                  ; GOBLIN 32px
SPR_ADDR_0_W32 equ 0xA9DB
SPR_BANK_0_W48 equ 3                  ; GOBLIN 48px
SPR_ADDR_0_W48 equ 0xA6AE
SPR_BANK_0_W72 equ 3                  ; GOBLIN 72px
SPR_ADDR_0_W72 equ 0xA000
SPR_BANK_1_W72 equ 3                  ; SLIME 72px
SPR_ADDR_1_W72 equ 0xAC62
SPR_BANK_2_W24 equ 4                  ; DWARF 24px
SPR_ADDR_2_W24 equ 0xB54D
SPR_BANK_2_W32 equ 4                  ; DWARF 32px
SPR_ADDR_2_W32 equ 0xB279
SPR_BANK_2_W48 equ 4                  ; DWARF 48px
SPR_ADDR_2_W48 equ 0xAC97
SPR_BANK_2_W72 equ 4                  ; DWARF 72px
SPR_ADDR_2_W72 equ 0xA000
SPR_BANK_3_W72 equ 5                  ; TROLL 72px
SPR_ADDR_3_W72 equ 0xA000
SPR_BANK_4_W24 equ 6                  ; COBRA 24px
SPR_ADDR_4_W24 equ 0xA8F6
SPR_BANK_4_W32 equ 6                  ; COBRA 32px
SPR_ADDR_4_W32 equ 0xA616
SPR_BANK_4_W48 equ 6                  ; COBRA 48px
SPR_ADDR_4_W48 equ 0xA000
SPR_BANK_4_W72 equ 5                  ; COBRA 72px
SPR_ADDR_4_W72 equ 0xAD29
SPR_BANK_5_W72 equ 6                  ; MIMIC 72px
SPR_ADDR_5_W72 equ 0xAAA9
; 뱅크 3: 5936 / 8192 바이트
; 뱅크 4: 5883 / 8192 바이트
; 뱅크 5: 6733 / 8192 바이트
; 뱅크 6: 6319 / 8192 바이트
