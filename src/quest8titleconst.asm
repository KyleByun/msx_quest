; gfx/quest_title.py 가 생성한 파일입니다. 직접 고치지 마세요.
; 글과 차례를 고치려면 gfx/title.json 을 고치세요.

TITLE_N      equ 4
TITLE_IMG_H  equ 144                ; 그림이 차지하는 줄 수
TITLE_TEXT_Y equ 152
TITLE_LINE_H equ 10
TITLE_HOLD   equ 0                ; 0 이면 키를 누를 때까지
TITLE_MARGIN equ 8
TITLE_TYPE_D equ 2                ; 글자 하나마다 기다릴 프레임
TITLE_BANKS  equ 13
TITLE_LINE_N equ 12

; 그림 뱅크는 게임 뱅크 **뒤**에 붙는다. 게임 쪽 마지막이 벽면 런이다.
TITLE_BANK0  equ RUN_BANK0 + RUN_BANKS
