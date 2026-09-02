; gfx/quest_gear.py 가 생성한 파일입니다. 직접 고치지 마세요.

; --- 품목: 자리, A, B, 양손 ---
ItemTable:
    db 1,  1, 4, 0      ; 0 DAGGER
    db 1,  1, 6, 0      ; 1 SHORTSWORD
    db 1,  1, 8, 0      ; 2 LONGSWORD
    db 1,  2, 6, 1      ; 3 GREATSWORD
    db 1,  1, 6, 0      ; 4 MACE
    db 1,  1, 8, 0      ; 5 WARHAMMER
    db 1,  1, 6, 0      ; 6 STAFF
    db 1,  1, 8, 0      ; 7 HWANDO
    db 1,  1, 8, 1      ; 8 GUKGUNG
    db 1,  1, 8, 1      ; 9 LONGBOW
    db 1,  1, 8, 1      ; 10 LIGHT_XBOW
    db 1,  1, 6, 0      ; 11 HAND_XBOW
    db 2,  2, 0, 0      ; 12 SHIELD
    db 3,  1, 0, 0      ; 13 LEATHER
    db 3,  3, 0, 0      ; 14 CHAINMAIL
    db 4,  1, 0, 0      ; 15 HELMET
    db 0, 10, 1, 0      ; 16 POTION_HP
    db 0,  5, 2, 0      ; 17 POTION_MP
    db 0,  0, 0, 0      ; 18 PORTAL

; --- 클래스가 쥘 수 있는 무기. 맨 앞이 처음 차는 것 ---
ClassWeapons:
    db 2, 3, 5, 4, 1, 9, INV_EMPTY   ; FIGHTER
    db 0, 1, 11, 10, 6, INV_EMPTY, INV_EMPTY   ; ROGUE
    db 6, 0, 10, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY   ; WIZARD
    db 4, 5, 6, 10, INV_EMPTY, INV_EMPTY, INV_EMPTY   ; CLERIC
    db 7, 8, 1, 0, INV_EMPTY, INV_EMPTY, INV_EMPTY   ; MUSA

; --- 처음 갖고 시작하는 짐 ---
StartKit:
    db 2, 3, 5, 4, 1, 9, 12, 13, 16, INV_EMPTY, INV_EMPTY
        ; FIGHTER: LONGSWORD, GREATSWORD, WARHAMMER, MACE, SHORTSWORD, LONGBOW, SHIELD, LEATHER, POTION_HP
    db 0, 1, 11, 10, 6, 13, 16, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY
        ; ROGUE: DAGGER, SHORTSWORD, HAND_XBOW, LIGHT_XBOW, STAFF, LEATHER, POTION_HP
    db 6, 0, 10, 13, 16, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY
        ; WIZARD: STAFF, DAGGER, LIGHT_XBOW, LEATHER, POTION_HP
    db 4, 5, 6, 10, 12, 13, 16, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY
        ; CLERIC: MACE, WARHAMMER, STAFF, LIGHT_XBOW, SHIELD, LEATHER, POTION_HP
    db 7, 8, 1, 0, 13, 16, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY, INV_EMPTY
        ; MUSA: HWANDO, GUKGUNG, SHORTSWORD, DAGGER, LEATHER, POTION_HP

