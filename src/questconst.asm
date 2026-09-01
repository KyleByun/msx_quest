; gfx/quest_convert.py 가 생성한 파일입니다. 직접 고치지 마세요.

VIEW_X       equ 16
VIEW_Y       equ 8
VIEW_W       equ 96
VIEW_H       equ 96
MAXD         equ 4
NSEG         equ 5
CENTRE_ID    equ 10
NUM_IDS      equ 51
OUTER0       equ 11              ; 옆면 '띠 바깥' 번호의 시작
BAND0        equ 21              ; 옆면 '띠 안' 번호의 시작

; 면 상태
VIS_TEX      equ 0
VIS_SKIP     equ 1
VIS_BLACK    equ 2
VIS_WALL2    equ 3
VIS_GAP2     equ 4
VIS_SKIP2    equ 5
VIS_SKIPN    equ 6
VIS_OFS      equ 7

COL_BLACK    equ 9
COL_PANEL    equ 4
COL_CREAM    equ 0
COL_SHADE    equ 6
COL_HERO     equ 14              ; 미니맵의 내 위치 (파랑)
BG_RLE_LEN   equ 6344
