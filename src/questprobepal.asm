; gfx/questprobe.py 가 gfx/quest_pal.py 에서 만든다. 직접 고치지 말 것.
;
; SCREEN 8 에는 팔레트가 없다. 색이 GRB332 로 못박혀 있어서 R 과 G 는
; 3 비트가 그대로 가고 B 만 3 비트에서 2 비트로 준다.
Pal332:
    db 0xFF                     ;  0  RGB333 7,7,6
    db 0xFE                     ;  1  RGB333 7,7,5
    db 0xDE                     ;  2  RGB333 7,6,5
    db 0xDA                     ;  3  RGB333 6,6,5
    db 0xB6                     ;  4  RGB333 5,5,5
    db 0xB5                     ;  5  RGB333 5,5,3
    db 0x92                     ;  6  RGB333 4,4,4
    db 0x6D                     ;  7  RGB333 3,3,3
    db 0x49                     ;  8  RGB333 2,2,2
    db 0x00                     ;  9  RGB333 0,0,0
    db 0x24                     ; 10  RGB333 1,1,1
    db 0xDB                     ; 11  RGB333 6,6,6
    db 0xFF                     ; 12  RGB333 7,7,7
    db 0xDE                     ; 13  RGB333 7,6,4
    db 0x6B                     ; 14  RGB333 2,3,7
    db 0xB5                     ; 15  RGB333 5,5,2
