"""quest2 (회전 애니메이션용 실시간 광선)의 표를 굽는다.

quest.rom 은 "칸 단위 이동 + 90도 회전"이라 벽면 모양이 상수라는 점을 이용해
전부 빌드 시점에 구웠다. 가만히 서 있거나 이동한 뒤의 화면은 quest2 도 여전히
그 방식(quest.asm 의 RenderDungeon 을 그대로 가져다 쓴다) 그대로다.

이 표는 딱 한 군데, **90도 회전 중간의 8프레임**에만 쓴다. 그 프레임들은 실제
각도(카디널 사이)가 필요해서 더는 빌드 시점에 구울 수 없다 - 그래서 그 순간만
실행 중에 광선을 쏜다(Wolfenstein 식 DDA 대신 고정 보폭 행진).

색은 quest.rom 이 이미 올려 둔 16색 팔레트를 그대로 쓴다(별도 팔레트 없음).
맵도 quest.asm 의 MapData 를 그대로 본다(따로 안 만든다).
"""
import io
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# --- 각도 -------------------------------------------------------------------
# 1 바퀴 = 256 (한 바이트로 자연스럽게 감싸 돈다. 더하기/빼기가 곧 mod 256 이고,
# 표를 페이지에 맞춰 두면 H=표>>8, L=각도 로 바로 찾는다 - 곱셈이 없다).
# 90도 = 64. quest.rom 의 facing 0~3 은 angle 0/64/128/192 와 같다.
# angle=0 이 북쪽(dx=0,dy=-1)이 되도록: dx=sin(theta), dy=-cos(theta).
ANGLE_UNITS = 256
QUARTER = ANGLE_UNITS // 4          # 64

# 회전 한 프레임에 이만큼 움직인다. 64/8=8프레임, 8단위=11.25도 - "10도씩"
# 요청에 가장 가까운, 256(2의 거듭제곱) 안에서 딱 나누어떨어지는 값이다.
# 딱 10.00도로 하려면 표를 256 대신 72단위(1단위=5도)로 다시 짜야 하는데,
# 그러면 페이지 정렬 트릭(곱셈 없이 바로 찾기)을 못 쓴다. 눈으로 보면
# 11.25도와 10도의 차이는 안 보인다고 보고 이 쪽을 택했다.
TURN_STEP = 8                        # 8 단위 = 11.25도, 8프레임/90도

# --- 광선 행진 ----------------------------------------------------------------
# 한 칸을 256 단위(Q8.8 고정소수점, 상위 바이트가 칸 번호)로 재고, 한 걸음은
# 1/8 칸(=32 단위)이다. 그래서 표의 값은 signed byte 하나에 들어간다
# (|sin|,|cos| <= 1 이므로 최대 32).
STEP_FRAC_DEN = 8                    # 한 걸음 = 1/8 칸
STEP_SCALE = 256 // STEP_FRAC_DEN    # 32

# 맵이 16x16 이고 가장 긴 통로가 14칸(1번 열, 위아래로 뚫려 있다)이라
# 15칸 * 8걸음 = 120 을 최대 걸음 수로 잡는다. 이보다 멀면 벽을 못 만난 것으로
# 보고 표의 끝 값(가장 어둡고 가장 얇은 벽)을 그대로 쓴다.
MAXSTEPS = 120

# --- 벽 높이 ------------------------------------------------------------------
# quest.rom 의 원근 상수 P=72 를 그대로 쓴다("칸 반폭 0.5 가 거리 z 에서 36/z
# 픽셀로 보인다", HALF[d]=36/d). 여기서는 벽 "높이"이므로 반폭의 두 배: 72/z.
# z 는 걸음 수를 칸 단위로 바꾼 값(step/8)이므로 height = 576/step.
PROJ_K = 576
HALF_H = 48                          # VIEW_H / 2

# --- 밝기 ---------------------------------------------------------------------
# 텍스처는 없다(회전 중 8프레임뿐이라 시간이 없다) - 3단계 명암만으로 원근을
# 읽게 한다. 색은 quest.rom 이 이미 올려 둔 16색 팔레트에서 고른다(별도로 안
# 올린다). 팔레트는 gfx/quest_convert.py 가 고정한 값이다.
#   0(776) 1(775) 2(765) 3(665) 4(555) 5(553) 6(444) 7(333)
#   8(222) 9(000)흑 10(111) 11(666) 12(777)백 13(764) 14(545) 15(552)
SHADE_NEAR_MAX = 24                  # 3칸 이내
SHADE_MID_MAX = 64                   # 8칸 이내
COL_NEAR = 12                        # (7,7,7) 흰색에 가깝다
COL_MID = 11                         # (6,6,6)
COL_FAR = 6                          # (4,4,4)
COL_CEIL = 8                         # (2,2,2) - 천장이 바닥보다 어둡다
COL_FLOOR = 7                        # (3,3,3)

# --- 벽 텍스처 (회전 중에도 벽돌 무늬가 보이게) --------------------------------
# gfx/quest_tex.py 의 벽돌(줄눈이 가로/세로로 지나가고 한 줄 걸러 반 칸
# 엇갈리는 규격)을 흉내 낸 아주 작은 16x16 타일이다. 칸마다 벽돌(1)인지
# 줄눈(0)인지만 담는다 - 실행 중에는 그 값 하나로 "밝은 벽돌색을 쓸까 어두운
# 줄눈색을 쓸까"만 고른다.
#
# 줄눈은 늘 어둡게 고정한다(거리와 무관하게 - 실제로도 grout 은 그늘이라
# 이렇게 해도 어색하지 않다). 벽돌은 걸음 수(거리)로 이미 만들어 둔
# ColorTable 을 그대로 쓴다 - 표를 하나 더 만들 필요가 없다.
TILE_SIZE = 16
BRICK_W = 8                          # 줄눈까지 포함한 벽돌 하나의 가로 폭
MORTAR_W = 1
COURSE_H = 8                         # 벽돌 한 단의 높이(줄눈 포함)
MORTAR_H = 1
MORTAR_BYTE = 0x99                   # 팔레트 9(검정)로 고정 - 0x99 = 9,9


def build_tile():
    """Tile[16][16] - 1=벽돌, 0=줄눈. TILE_SIZE 는 2 의 거듭제곱이라 실행
    중에는 (V and 15), (U and 15) 로 바로 이 칸 안 좌표를 얻는다."""
    tile = []
    for r in range(TILE_SIZE):
        course = r // COURSE_H
        row_in_course = r % COURSE_H
        row = []
        if row_in_course >= COURSE_H - MORTAR_H:
            row = [0] * TILE_SIZE                # 가로 줄눈 - 단 전체
        else:
            offset = 0 if course % 2 == 0 else BRICK_W // 2   # 한 단 걸러 엇갈림
            for c in range(TILE_SIZE):
                col_in_brick = (c + offset) % BRICK_W
                row.append(0 if col_in_brick < MORTAR_W else 1)
        tile.append(row)
    return tile


def build_step_tables():
    """StepX[angle], StepY[angle] - 부호 있는 바이트, 한 걸음의 이동량."""
    sx, sy = [], []
    for a in range(ANGLE_UNITS):
        theta = a * 2 * math.pi / ANGLE_UNITS
        dx = math.sin(theta)
        dy = -math.cos(theta)
        vx = max(-127, min(127, round(dx * STEP_SCALE)))
        vy = max(-127, min(127, round(dy * STEP_SCALE)))
        sx.append(vx & 0xFF)
        sy.append(vy & 0xFF)
    return sx, sy


def build_height_colour_tables():
    """HeightTable[step], ColorTable[step] - 256 칸 표. step > MAXSTEPS 인
    자리는 표 끝(가장 먼 값)으로 채워, 실행 중에 "못 만남"을 따로 안 봐도 된다.
    """
    height = [0] * 256
    colour = [0] * 256
    last_h, last_c = 1, COL_FAR
    for step in range(1, 256):
        if step <= MAXSTEPS:
            h = max(1, min(96, round(PROJ_K / max(step, 6))))
            if step <= SHADE_NEAR_MAX:
                c = COL_NEAR
            elif step <= SHADE_MID_MAX:
                c = COL_MID
            else:
                c = COL_FAR
            last_h, last_c = h, c
        else:
            h, c = last_h, last_c
        height[step] = h
        colour[step] = (c << 4) | c        # 같은 색 두 픽셀
    height[0] = height[1]
    colour[0] = colour[1]
    return height, colour


def db_bytes(vals):
    return "    db " + ", ".join(str(v) for v in vals)


def main():
    sx, sy = build_step_tables()
    height, colour = build_height_colour_tables()
    tile = build_tile()

    L = []
    A = L.append
    A("; 이 파일은 gfx/quest2_gen.py 가 만든다. 직접 고치지 말 것.")
    A(";")
    A("; 90도 회전 애니메이션 프레임에만 쓰는 표. 곱셈/나눗셈이 필요한 sin/cos 와")
    A("; 원근 나눗셈을 전부 빌드 시점에 풀어서, 실행 중에는 표를 두 번 보는")
    A("; 것으로 끝난다(각도 -> 한 걸음 이동량, 걸음 수 -> 높이/밝기). 팔레트와")
    A("; 맵은 quest.asm 것을 그대로 쓴다 - 여기서 다시 굽지 않는다.")
    A("")
    A("ANGLE_UNITS  equ %d               ; 1 바퀴. 8비트라 덧셈이 곧 mod 256" % ANGLE_UNITS)
    A("QUARTER      equ %d                ; 90도" % QUARTER)
    A("TURN_STEP    equ %d                 ; 한 프레임에 도는 양 (11.25도)" % TURN_STEP)
    A("MAXSTEPS     equ %d              ; 이보다 멀면 벽을 못 만난 것으로 본다" % MAXSTEPS)
    A("HALF_H       equ %d               ; VIEW_H / 2 - 벽 조각을 세로 가운데 맞춤" % HALF_H)
    A("COL_CEIL_B   equ 0x%02X            ; 천장 - 같은 색 두 픽셀" % ((COL_CEIL << 4) | COL_CEIL))
    A("COL_FLOOR_B  equ 0x%02X            ; 바닥" % ((COL_FLOOR << 4) | COL_FLOOR))
    A("MORTAR_BYTE  equ 0x%02X            ; 줄눈 - 거리와 무관하게 고정" % MORTAR_BYTE)
    A("TILE_MASK    equ 0x%02X             ; 16x16 이라 and 로 칸 안 좌표를 얻는다" % (TILE_SIZE - 1))
    A("")
    A("; --- 각도 -> 한 걸음 이동량 (부호 있는 바이트, Q8.8 의 1/8칸) -----------")
    A("; 256 바이트 정확히 - 페이지에 맞춰 두면 H=표>>8, L=각도 로 바로 찾는다.")
    A("    ALIGN 256")
    A("StepXTable:")
    for i in range(0, 256, 16):
        A(db_bytes(sx[i:i + 16]))
    A("    ALIGN 256")
    A("StepYTable:")
    for i in range(0, 256, 16):
        A(db_bytes(sy[i:i + 16]))
    A("")
    A("; --- 걸음 수 -> 벽 높이 / 색 (256 바이트, 둘 다 페이지 정렬) ------------")
    A("    ALIGN 256")
    A("HeightTable:")
    for i in range(0, 256, 16):
        A(db_bytes(height[i:i + 16]))
    A("    ALIGN 256")
    A("ColorTable:")
    for i in range(0, 256, 16):
        A(db_bytes(colour[i:i + 16]))
    A("")
    A("; --- 벽돌 타일 16x16 (1=벽돌 0=줄눈) -----------------------------------")
    A("; 256 바이트 정확히 - 페이지에 맞춰 두면 H=Tile>>8, L=v*16+u 로 바로 찾는다.")
    A("    ALIGN 256")
    A("Tile:")
    for row in tile:
        A(db_bytes(row))
    A("")

    out = os.path.join(ROOT, "src", "quest2data.asm")
    with io.open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print("wrote src/quest2data.asm (%d 줄)" % len(L))
    print("  MAXSTEPS=%d, 걸음당 %.3f 칸, 회전 프레임당 %.2f 도, 90도에 %d 프레임"
          % (MAXSTEPS, 1.0 / STEP_FRAC_DEN, TURN_STEP * 360.0 / ANGLE_UNITS,
             QUARTER // TURN_STEP))


if __name__ == "__main__":
    main()
