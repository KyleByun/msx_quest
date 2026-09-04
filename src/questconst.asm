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

; 색. 4bpp 는 팔레트 번호, 8bpp 는 GRB332 값 그대로다.
; *_BYTE 는 그 색으로 한 바이트를 채울 때 쓰는 값 - 4bpp 는 같은 색
; 픽셀 둘이라 17 을 곱하고, 8bpp 는 한 바이트가 한 픽셀이라 그대로다.
COL_BLACK    equ 9
COL_PANEL    equ 4
COL_CREAM    equ 0
COL_SHADE    equ 6
COL_HERO     equ 14              ; 미니맵의 내 위치 (파랑)
BLACK_BYTE   equ 153
CREAM_BYTE   equ 0
SHADE_BYTE   equ 102

; 화면 모드. 4bpp 는 한 바이트에 픽셀 둘, 8bpp 는 하나.
BPP          equ 4
PXB          equ 2              ; 한 바이트에 든 픽셀 수
VIEW_XB      equ 8              ; 뷰포트 왼쪽의 바이트 위치
VRAM_ROW     equ 128              ; 한 스캔라인의 VRAM 바이트 수

; 정면 벽 픽셀을 놓아 둘 화면 밖 VRAM 의 첫 줄.
;
; 깊이별 사각형을 **세로로 쌓아** 둔다 (UnpackFront). 그래서 차지하는
; 줄 수는 FRONT_PIX_LEN/VRAM_ROW 가 아니다 - 폭이 FRONT_MAXW 뿐이라
; 줄이 남고, 실제로는 그 다섯 배 가까이 쓴다. 화면 밖 VRAM 을 쓰는
; 다른 자리는 FRONT_END_VY 아래에 두거나 x 를 FRONT_MAXW 뒤로 밀어야
; 한다. 안 그러면 정면 벽 그림 위에 덮어써서 벽에 그 그림이 박힌다.
FRONT_VY     equ 256
FRONT_PIX_LEN equ 3784
FRONT_ROWS   equ 154                ; 깊이별 줄 수의 합
FRONT_MAXW   equ 36                ; 제일 넓은 깊이의 바이트 폭
FRONT_END_VY equ FRONT_VY + FRONT_ROWS

; 뱅크 배치. 3 부터 그림 -> 배경 -> 정면 벽 -> 벽면 런 순서다.
; 그림 뱅크 수가 모드마다 다르므로(SPR_BANKS) 숫자를 박지 않고 계산한다.
; questrules.asm 을 questconst.asm 보다 **먼저** include 해야 한다.
BG_BANKS     equ 1
FRONT_BANKS  equ 1
RUN_BANKS    equ 2
BG_BANK      equ SPR_FIRSTBK + SPR_BANKS
FRONT_BANK   equ BG_BANK + BG_BANKS
RUN_BANK0    equ FRONT_BANK + FRONT_BANKS

; 배경 RLE 는 뱅크마다 따로 압축했다. 뱅크별 길이.
BG_LEN_0     equ 6344
