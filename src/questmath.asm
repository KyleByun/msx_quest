;-----------------------------------------------------------------------------
; 곱셈과 나눗셈
;
; Z80 에는 곱셈도 나눗셈도 없다. 아래는 Grauw 의 정리를 그대로 옮긴 것이다.
;   https://map.grauw.nl/articles/mult_div_shifts.php
; 자세한 설명과 왜 이 형태인지는 doc/z80_mult_div.md 에 적어 두었다.
;
; 원리는 학교에서 배우는 세로셈과 같다. 곱셈은 곱하는 수의 비트를 위에서부터
; 하나씩 보면서 결과를 두 배로 밀고, 그 비트가 1 이면 곱해지는 수를 더한다.
; 나눗셈은 그 반대로 밀면서 빼 본다.
;
; 이 프로젝트에서 어디에 쓰는가
;   Mult8   스프라이트 줄 주소, 몬스터 표 색인처럼 "번호 x 간격"
;   Div8    무리 지어 나온 몬스터에게 피해를 나눌 때
;
; 반대로 일부러 안 바꾼 곳도 있다. PutNumR / MsgAddNum 의 자릿수 만들기는 10 을
; 빼면서 도는데, 세 자리라 최대 스물일곱 번이고 화면에 글자를 찍는 김에 도는
; 것이라 티가 나지 않는다. 이미 화면으로 확인해 둔 코드를 건드릴 이유가 없다.
;-----------------------------------------------------------------------------

; H x E -> HL  (8 x 8 = 16 비트)
;
; HL 을 왼쪽으로 밀면서 넘쳐 나온 비트가 1 이면 DE 를 더한다. 처음에 H 에 곱하는
; 수를 두고 L 을 0 으로 두었으므로, 미는 동안 H 의 비트가 위에서부터 하나씩
; 캐리로 빠져나오고 그 자리를 결과가 채운다. 레지스터 하나로 두 몫을 한다.
Mult8:
    ld d, 0
    ld l, d
    ld b, 8
.loop:
    add hl, hl
    jr nc, .noadd
    add hl, de
.noadd:
    djnz .loop
    ret

; A x DE -> HL  (8 x 16 = 16 비트, 넘치는 자리는 버린다)
Mult12:
    ld l, 0
    ld h, l
    ld b, 8
.loop:
    add hl, hl
    add a, a
    jr nc, .noadd
    add hl, de
.noadd:
    djnz .loop
    ret

; E / C -> A 몫, B 나머지  (8 / 8)
;
; 빼고 나서 캐리를 보고 되돌리는 "복원식"이다. 마지막에 cpl 이 붙는 이유는 몫의
; 비트가 캐리로 뒤집혀 쌓이기 때문이다.
Div8:
    xor a
    ld b, 8
.loop:
    rl e
    rla
    sub c
    jr nc, .noadd
    add a, c
.noadd:
    djnz .loop
    ld b, a
    ld a, e
    rla
    cpl
    ret

; BC / DE -> BC 몫, HL 나머지  (16 / 16)
Div16:
    ld hl, 0
    ld a, b
    ld b, 8
.loop1:
    rla
    adc hl, hl
    sbc hl, de
    jr nc, .noadd1
    add hl, de
.noadd1:
    djnz .loop1
    rla
    cpl
    ld b, a
    ld a, c
    ld c, b
    ld b, 8
.loop2:
    rla
    adc hl, hl
    sbc hl, de
    jr nc, .noadd2
    add hl, de
.noadd2:
    djnz .loop2
    rla
    cpl
    ld b, c
    ld c, a
    ret
