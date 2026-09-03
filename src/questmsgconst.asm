; gfx/quest_msg.py 가 생성한 파일입니다. 직접 고치지 마세요.
; 글을 고치려면 gfx/message.json 을 고치고 다시 빌드하세요.

HAN_BASE     equ 0x5B                ; 이 값 이상이면 한글 글리프 번호다
HAN_ESC_BYTE equ 0xFF                ; 이 바이트는 안 찍는다 - 다음 글자에 얹는다
HAN_ESC      equ 164               ; 탈출한 글자의 번호는 여기서부터
HAN_ESC_BIAS equ 1                 ; 둘째 바이트에 더해 둔 값 (0 을 피한다)
HANGUL_ADV   equ 8                 ; 한글 한 칸 (영문은 FONT_W = 6)
HAN_N        equ 180                ; 구워 넣은 한글 글자 수
MSG_N        equ 45
LANG_EN      equ 0
LANG_KO      equ 1
LANG_DEFAULT equ LANG_KO

MSG_APPEAR     equ 0
MSG_CMD_ATTACK equ 1
MSG_CMD_DEFEND equ 2
MSG_CMD_FLEE   equ 3
MSG_CRIT       equ 4
MSG_DIES       equ 5
MSG_DOWN       equ 6
MSG_FLED       equ 7
MSG_GUARDS     equ 8
MSG_HIT        equ 9
MSG_LOST       equ 10
MSG_MENU_OFF   equ 11
MSG_MENU_ON    equ 12
MSG_MISS       equ 13
MSG_NO_FLEE    equ 14
MSG_ROUND      equ 15
MSG_SPACE      equ 16
MSG_ST_AC      equ 17
MSG_ST_ATK     equ 18
MSG_ST_CHA     equ 19
MSG_ST_CON     equ 20
MSG_ST_DEX     equ 21
MSG_ST_DMG     equ 22
MSG_ST_DROP    equ 23
MSG_ST_EMPTY   equ 24
MSG_ST_EQUIP   equ 25
MSG_ST_EQUIPCMD equ 26
MSG_ST_GIVE    equ 27
MSG_ST_HP      equ 28
MSG_ST_INT     equ 29
MSG_ST_ITEMS   equ 30
MSG_ST_LV      equ 31
MSG_ST_MAGIC   equ 32
MSG_ST_MP      equ 33
MSG_ST_NONE    equ 34
MSG_ST_SHIELD  equ 35
MSG_ST_SKILL   equ 36
MSG_ST_STR     equ 37
MSG_ST_TOWHO   equ 38
MSG_ST_USECMD  equ 39
MSG_ST_WEAPON  equ 40
MSG_ST_WIS     equ 41
MSG_ST_YES     equ 42
MSG_SURGES     equ 43
MSG_WON        equ 44

MONNAME_LEN  equ 12

SKILLNAME_LEN equ 10

CLASSNAME_LEN equ 11

RACENAME_LEN equ 9

WEAPONNAME_LEN equ 13
