; gfx/quest_gear.py 가 생성한 파일입니다. 직접 고치지 마세요.
; 수치를 고치려면 gfx/items.json 을 고치세요.

ITEM_N       equ 19
ITEM_STRIDE  equ 4
I_SLOT       equ 0                 ; 어디에 차는가 (0 이면 쓰는 것)
I_A          equ 1                 ; 무기 개수 / 방어구 AC / 물약 크기
I_B          equ 2                 ; 무기 면 / 물약 효과 종류
I_TWOH       equ 3                 ; 양손이면 방패를 못 든다

SLOT_USE     equ 0
SLOT_WEAPON  equ 1
SLOT_SHIELD  equ 2
SLOT_ARMOUR  equ 3
SLOT_HELM    equ 4
EQUIP_N      equ 4

EFF_NONE     equ 0
EFF_HP       equ 1
EFF_MP       equ 2

INV_N        equ 10                ; 가방 칸
INV_EMPTY    equ 0xFF
GEAR_STRIDE  equ 16                ; 2 의 거듭제곱이라 색인이 시프트로 끝난다
G_INV        equ 0                 ; 가방 10 칸
G_EQUIP      equ 10                 ; 자리마다 '가방 몇 번째' (없으면 INV_EMPTY)

KIT_STRIDE   equ 11
CLSW_STRIDE  equ 7
