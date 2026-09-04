; gfx/psg_music.py 가 만든 파일입니다. 직접 고치지 마세요.
;
; MUS_* 는 곡의 **쓰임**이지 파일 이름이 아니다. 곡을 갈아도 부르는
; 자리는 그대로 두려는 것이다.
;
; 곡마다 뱅크 하나. 음악 뱅크는 타이틀 뱅크 **앞**에 온다 - 전투곡은
; --title 을 안 준 빌드에도 있어야 한다.

MUSIC_BANKS  equ 2
MUSIC_BANK   equ RUN_BANK0 + RUN_BANKS
MUS_N        equ 2
MUS_STRIDE   equ 8                 ; 길이 + 채널 셋의 자리, 워드 넷

MUS_TITLE    equ 0                 ; title
MUS_BATTLE   equ 1                 ; Obsidian_Keep

MUSIC_MAXLEN equ 2824              ; RAM 에 잡아 둘 자리
