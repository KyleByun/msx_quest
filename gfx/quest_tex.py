"""벽돌 텍스처를 만들고, 원근이 적용된 벽면을 미리 구워 둔다.

핵심은 이것이다. 칸 단위 이동에 90도 회전만 있으면 화면에 나오는 벽면의 모양이
상수이므로, 그 위에 입히는 텍스처도 상수다. 그래서 화면 좌표 -> 텍스처 좌표
변환(원근 나눗셈 포함)을 여기서 미리 다 풀어 픽셀로 구워 둔다. Z80 은 바이트를
옮기기만 하면 된다.

투영: 화면좌표 - 중심 = P * 월드좌표 / z,  P = 72
      (통로 반폭 0.5 칸이 거리 z 에서 36/z 픽셀로 보이므로 P*0.5 = 36)
"""
import quest_geom as G

P = 72.0                     # 투영 상수

# 한 칸이 텍스처 몇 픽셀인가. 이 값이 화면상 줄눈 두께를 정한다.
#
# 가장 가까운 벽은 한 칸이 화면 96 픽셀에 걸쳐 보인다. 그러므로 화면에서의
# 확대율은 96 / TEX_PER_CELL 이다. 처음에 24 로 두었더니 확대율이 4 배가 되어
# 줄눈 2 텍셀이 화면에서 8 픽셀짜리 검은 띠로 벌어졌다. 96 으로 맞추면 가장
# 가까운 벽에서 1:1 이 되고, 줄눈 1 텍셀이 화면에서도 1 픽셀이다.
TEX_PER_CELL = 96

# 원본 스크린샷의 비율(벽돌이 줄눈보다 훨씬 두껍고, 한 줄 걸러 반 칸 엇갈림)은
# 그대로 두고 크기만 위 배율에 맞춰 키웠다.
BRICK_W, BRICK_H = 24, 11
MORTAR = 1
TILE_W, TILE_H = 24, 24      # (11+1) * 2 = 24. 엇갈림까지 포함해 반복되는 단위

BRICK = (168, 168, 168)      # 원본은 (169,168,171) 로 살짝 푸른데, 그대로 두면
BRICK_TOP = (208, 208, 208)  # 양자화가 회색 계단 대신 푸른 색을 골라 얼룩이 생긴다.
BRICK_BOT = (120, 120, 120)  # 순회색으로 맞추면 팔레트의 회색 8단계에 정확히 붙는다.
GROUT = (16, 16, 16)

# 텍스처를 세로로 이만큼 밀어 둔다.
#
# 밀지 않으면 **칸 경계가 언제나 텍셀 0 번 줄에 정확히 떨어진다.** 한 칸이 텍스처
# 96 줄이고 타일이 24 줄이라 96 % 24 = 0 이기 때문이다. 그런데 0 번 줄은 벽돌
# 윗면 하이라이트(208)라, 칸 경계마다 주변보다 밝은 선이 한 줄씩 생겼다.
#
#   벽 윗변(천장과 만나는 자리) v = 0.00      -> 대각선으로 흰 선
#   바닥/천장의 칸 경계 (z 가 정수) v = 96k   -> 가로로 흰 선
#   정면 벽의 위아래 변 v = 0, 96             -> 같은 이유
#
# 세 증상이 다 같은 원인이었다. 5 만큼 밀면 경계가 벽돌 한가운데(민 회색)에
# 떨어져 아무 선도 생기지 않는다. 하이라이트/그림자/줄눈에서 각각 5, 5, 6 줄
# 떨어진 자리라 어느 쪽으로도 가깝지 않다.
#
# 미는 값을 면마다 다르게 주면 맞닿는 자리에서 벽돌 줄이 어긋난다. 그래서 벽,
# 바닥, 천장, 정면 벽이 모두 같은 값을 쓴다.
TEX_V_OFF = 5


def make_tile():
    """12x12 로 반복되는 벽돌 타일."""
    t = [[GROUT] * TILE_W for _ in range(TILE_H)]
    for row in range(2):                       # 벽돌 줄 두 개 (엇갈림)
        y0 = row * (BRICK_H + MORTAR)
        off = 0 if row == 0 else BRICK_W // 2   # 한 줄 걸러 반 칸 밀기
        for y in range(BRICK_H):
            for x in range(TILE_W):
                if (x + off) % BRICK_W == 0:    # 세로 줄눈
                    continue
                if y == 0:
                    t[y0 + y][x] = BRICK_TOP
                elif y == BRICK_H - 1:
                    t[y0 + y][x] = BRICK_BOT
                else:
                    t[y0 + y][x] = BRICK
    return t


TILE = make_tile()


# 텍셀 하나를 콕 집어 오면 안 된다 - 상자 평균이 필요하다
#
# 바닥과 천장에 검은 가로선이 몇 줄 생기는 문제가 있었다. 원인은 줄눈이다.
# 바닥의 텍스처 세로 좌표는 v = 96 * 36 / dy 라서, 화면에서 한 픽셀 내려갈 때
# v 가 얼마나 변하는지는 dy 에 따라 크게 달라진다.
#
#   화면 아래쪽(dy=47)  : 픽셀당 1.6 텍셀   -> 줄눈 1 텍셀이 제대로 보인다
#   지평선 근처(dy=10)  : 픽셀당 34 텍셀    -> 줄눈을 건너뛰거나 통째로 맞는다
#
# 즉 먼 바닥에서는 한 픽셀이 텍스처 수십 줄을 덮는데 그중 한 점만 집어 온다.
# 우연히 줄눈에 걸린 줄은 화면 폭 전체가 새까맣게 되고, 안 걸린 줄은 줄눈이
# 아예 없다. 그래서 매끄러운 계조 대신 검은 줄 몇 개가 뚝뚝 생긴다.
#
# 제대로 된 답은 그 픽셀이 덮는 텍셀을 전부 평균 내는 것이다(상자 필터). 먼
# 바닥은 벽돌과 줄눈이 섞인 중간 회색이 되어 부드럽게 이어지고, 가까운 바닥은
# 덮는 텍셀이 한 개뿐이라 지금처럼 또렷하다.
#
# 굽는 시점에 하는 일이므로 실행 중 비용은 0 이다. 평균을 빨리 내려고 타일의
# 누적합표를 만들어 둔다. 상자가 타일 몇 장을 걸쳐도 덧셈 네 번이면 끝난다.
def _build_sat():
    """SAT[v][u] = 타일의 [0,u) x [0,v) 구간 합 (채널별)."""
    sat = [[(0, 0, 0)] * (TILE_W + 1) for _ in range(TILE_H + 1)]
    for v in range(TILE_H):
        run = [0, 0, 0]
        for u in range(TILE_W):
            c = TILE[v][u]
            run = [run[k] + c[k] for k in range(3)]
            sat[v + 1][u + 1] = tuple(sat[v][u + 1][k] + run[k] for k in range(3))
    return sat


_SAT = _build_sat()
_TOTAL = _SAT[TILE_H][TILE_W]                   # 타일 한 장 전체 합
_ROWSUM = [_SAT[v][TILE_W] for v in range(TILE_H + 1)]   # [0,W) x [0,v)
_COLSUM = [_SAT[TILE_H][u] for u in range(TILE_W + 1)]   # [0,u) x [0,H)


def _S(u, v):
    """무한히 반복되는 타일에서 [0,u) x [0,v) 의 합. u, v 는 음수여도 된다."""
    qu, ru = divmod(u, TILE_W)
    qv, rv = divmod(v, TILE_H)
    return tuple(qu * qv * _TOTAL[k] + qu * _ROWSUM[rv][k]
                 + qv * _COLSUM[ru][k] + _SAT[rv][ru][k] for k in range(3))


def _Sf(u, v):
    """_S 를 실수 좌표까지 늘린 것. 정확한 값이지 근사가 아니다.

    타일은 텍셀마다 색이 일정한 계단 함수이므로, 그 이중적분 F(u,v) 는 텍셀 한
    칸 안에서 u 와 v 에 대해 겹선형이다. 그래서 네 정수 모서리를 겹선형 보간하면
    분수 좌표의 적분값이 그대로 나온다.

    이것이 중요한 이유는 이렇다. 처음에는 상자를 바깥 텍셀 경계까지 넓혀서
    평균했는데, 한 픽셀이 1.33 텍셀을 덮는 정도(가장 가까운 벽이 그렇다)에서도
    상자가 3 텍셀로 부풀어 벽돌 무늬가 뭉개졌다. 덮는 넓이만큼만 평균하면 줄눈이
    픽셀의 75% 를 차지해 충분히 진하게 남는다.
    """
    iu = int(u // 1)
    fu = u - iu
    iv = int(v // 1)
    fv = v - iv
    a = _S(iu, iv)
    b = _S(iu + 1, iv)
    c = _S(iu, iv + 1)
    d = _S(iu + 1, iv + 1)
    w0 = (1.0 - fu) * (1.0 - fv)
    w1 = fu * (1.0 - fv)
    w2 = (1.0 - fu) * fv
    w3 = fu * fv
    return tuple(a[k] * w0 + b[k] * w1 + c[k] * w2 + d[k] * w3 for k in range(3))


def texel_box(u0, u1, v0, v1):
    """[u0,u1) x [v0,v1) 넓이만큼의 평균색."""
    du = u1 - u0
    dv = v1 - v0
    if du < 1e-9:
        u1 = u0 + 1e-9
        du = 1e-9
    if dv < 1e-9:
        v1 = v0 + 1e-9
        dv = 1e-9
    s11 = _Sf(u1, v1)
    s01 = _Sf(u0, v1)
    s10 = _Sf(u1, v0)
    s00 = _Sf(u0, v0)
    n = du * dv
    return tuple(int((s11[k] - s01[k] - s10[k] + s00[k]) / n + 0.5) for k in range(3))


def texel(u, v):
    return TILE[int(v) % TILE_H][int(u) % TILE_W]


def shade(rgb, f):
    return tuple(max(0, min(255, int(c * f))) for c in rgb)


def depth_factor(z):
    """거리에 따른 밝기. 이것이 원근을 읽게 하는 가장 큰 요소다."""
    return max(0.22, min(1.0, 1.18 - 0.19 * z))


# 면마다 방향에 따른 밝기 차. 왼쪽에서 빛이 오는 것으로 친다.
FACE_GAIN = {"left": 1.0, "right": 0.68, "ceil": 0.45, "floor": 0.8, "front": 0.85}


# --- 화면 좌표 -> 텍스처 좌표 -----------------------------------------------
#
# 투영 화면좌표 - 중심 = P * 월드좌표 / z 를 면마다 역으로 푼 것이다. 픽셀 하나가
# 덮는 텍스처 범위를 알아야 하므로 (u, v) 와 거리 z 를 함께 돌려준다.

def _uv_left(x, y):
    dx = G.CX - x
    if dx <= 0:
        return None
    z = 36.0 / dx
    return z * TEX_PER_CELL, ((y - G.CY) * z / P + 0.5) * TEX_PER_CELL + TEX_V_OFF, z


def _uv_right(x, y):
    dx = x - G.CX
    if dx <= 0:
        return None
    z = 36.0 / dx
    return z * TEX_PER_CELL, ((y - G.CY) * z / P + 0.5) * TEX_PER_CELL + TEX_V_OFF, z


def _uv_floor(x, y):
    dy = y - G.CY
    if dy <= 0:
        return None
    z = 36.0 / dy
    return ((x - G.CX) * z / P + 0.5) * TEX_PER_CELL, z * TEX_PER_CELL + TEX_V_OFF, z


def _uv_ceil(x, y):
    dy = G.CY - y
    if dy <= 0:
        return None
    z = 36.0 / dy
    return ((x - G.CX) * z / P + 0.5) * TEX_PER_CELL, z * TEX_PER_CELL + TEX_V_OFF, z


# 상자 평균을 어디에 쓸 것인가
#
# 바닥과 천장에만 쓴다. 벽에는 안 쓴다.
#
# 검은 가로선이 생긴 것은 바닥과 천장이다. 거기는 화면 세로 한 픽셀이 텍스처
# 수십 줄을 덮는 자리가 생겨서 줄눈을 통째로 맞거나 통째로 건너뛴다. 벽은
# 그렇지 않다. 벽의 세로 방향은 화면 세로와 거의 1:1 이라 줄눈이 제 두께로
# 보인다. 가로 방향만 소실점 쪽에서 압축되는데, 그쪽 줄눈은 세로선이라 가로로
# 이어지는 검은 띠를 만들지 않는다.
#
# 벽에도 걸어 봤더니 벽돌 무늬가 눈에 띄게 물러졌다. 이미 봐 주신 모습이므로
# 건드리지 않는다. 고쳐 달라고 한 것만 고친다.
SMOOTH = ("floor", "ceil")


def _bake(uv, face, x, y):
    """픽셀 (x,y) 의 색. 바닥/천장은 덮는 넓이만큼 평균 낸다.

    픽셀의 네 모서리를 각각 텍스처 좌표로 옮겨 감싸는 상자를 구한다. 비스듬한
    면에서는 실제 자국이 평행사변형이지만 감싸는 상자로 충분하다.
    """
    c = uv(x, y)
    if c is None:
        return None
    if face in SMOOTH:
        corners = [uv(x + ox, y + oy) for ox in (-0.5, 0.5) for oy in (-0.5, 0.5)]
        corners = [p for p in corners if p is not None]
        us = [p[0] for p in corners]
        vs = [p[1] for p in corners]
        rgb = texel_box(min(us), max(us), min(vs), max(vs))
    else:
        rgb = texel(c[0], c[1])
    return shade(rgb, depth_factor(c[2]) * FACE_GAIN[face])


def bake_left(j, x, y):
    return _bake(_uv_left, "left", x, y)


def bake_right(j, x, y):
    return _bake(_uv_right, "right", x, y)


def bake_floor(j, x, y):
    return _bake(_uv_floor, "floor", x, y)


def bake_ceil(j, x, y):
    return _bake(_uv_ceil, "ceil", x, y)


def bake_front(d, x, y):
    """d 칸 앞의 정면 벽. 평면이 z = d 에 있으므로 나눗셈이 상수다."""
    def uv(px, py):
        return (((px - G.CX) * d / P + 0.5) * TEX_PER_CELL,
                ((py - G.CY) * d / P + 0.5) * TEX_PER_CELL + TEX_V_OFF, d)
    return _bake(uv, "front", x, y)


# 옆길이 뚫려 있을 때 그 자리에 무엇이 보이는가
#
# 광선을 따라가 보면 답이 나온다. 구간 j 의 오른쪽 벽이 없다고 하자. 그 자리를
# 지나는 광선은 화면에서 중심으로부터 dx 만큼 떨어져 있고 기울기가 s = dx/P 다.
# 벽이 있던 x = 0.5 를 z = 0.5/s 에서 지나 옆 통로로 들어간다.
#
# 그다음 무엇에 부딪히는가. 옆 통로의 바깥벽(x = 1.5)까지 가려면 z = 1.5/s 여야
# 하는데, 그 전에 z = j+1 평면을 먼저 만난다. 거기서 광선의 가로 위치는
# s*(j+1) 이고 이것은 언제나 1.0 이하다. 즉 옆 통로 안에 있다.
#
#   -> 옆길로 보이는 것은 "대각선 앞칸(옆으로 1, 앞으로 j+1)의 정면"이다.
#      정면 벽과 똑같은 z = 상수 평면이므로 원근 나눗셈도 상수다.
#
# 위아래는 어디까지인가. 광선이 천장(y = 0.5)에 닿는 것은 z = 36/|dy| 이므로,
# |dy| > 36/(j+1) 이면 벽보다 천장을 먼저 만난다. 그런데 36/(j+1) 이 바로
# HALF[j+1] 이다. 즉 경계가 정확히 깊이 j+1 사각형의 반높이다.
#
# 여기에는 전제가 하나 숨어 있다. **대각선 앞칸이 벽이어야** 그 정면이 보인다.
# 그 칸마저 뚫려 있으면 광선은 z = j+1 을 그냥 지나가는데, 그래도 밝은 벽면을
# 그려 놓으면 없는 벽이 생긴다. 광장 한가운데에서 화면 좌우 끝에 벽이 나타나던
# 것이 그 증상이었다.
#
# 그래서 z = j+1 한 평면만 보지 않고 **k = j+1 부터 NSEG 까지 차례로** 본다.
# 어느 평면에서 만나든 보이는 것은 그 평면의 정면이므로 bake_front(k) 그대로다.
# 즉 굽는 함수를 새로 만들 필요가 없다 - 평면마다 한 벌씩 구워 두고 실행 중에
# 고르기만 하면 된다(quest_convert.py 의 면 번호 설명 참고).
#
# 화면에서 그 벽이 보이는 범위는 |dy| < HALF[k] 다. 광선이 천장(y = 0.5)에 닿는
# 것이 z = 36/|dy| 이므로 |dy| > 36/k 면 벽보다 천장을 먼저 만나는데, 36/k 가 바로
# HALF[k] 이기 때문이다. 그 바깥은 아래 bake_side_open 과 같은 그림이다.
#
# 밝기는 손대지 않는다. 그래도 벽과 헷갈리지 않는데, 맞은편 벽은 정면을 향한
# 평면이라 벽돌 크기가 고르고, 옆벽은 비스듬한 평면이라 벽돌이 소실점 쪽으로
# 늘어나기 때문이다. 어둡게 하면 오히려 앞뒤가 안 맞는다. 막다른 곳의 정면
# 벽과 그 옆의 뚫린 자리는 z 가 같은 "한 평면"이라, 한쪽만 어둡게 하면 정면
# 벽 좌우에 검은 띠가 생기는데 실제로 그 칸까지 걸어가 보면 밝은 벽이다.


# 끝까지 아무것도 만나지 않을 때
#
# 광선을 막는 것이 없으므로 바닥(y = 0.5)이나 천장에 닿을 때까지 간다. 그 자리는
# z = 36/|dy| 이고, 이것이 바로 bake_floor / bake_ceil 이 이미 푸는 식이다. 즉
# **벽이 없다고 치고 바닥과 천장을 그대로 이어 그리면 된다.**
#
# 소실점에 가까울수록 z 가 커져 depth_factor 가 0.22 로 깔리므로, 바닥과 천장이
# 옆으로 쓸려 들어가다 어둠으로 사라진다. 뚫린 느낌을 만드는 것은 밝기가 아니라
# 이 "쓸려 들어가는 모양"이다.
def bake_side_open(j, x, y):
    """옆이 뚫렸고 볼 수 있는 데까지 아무 벽도 없다 - 바닥과 천장만 이어진다."""
    dy = y - G.CY
    if dy == 0:
        return (0, 0, 0)                        # 소실선 - 무한히 멀다
    c = bake_floor(j, x, y) if dy > 0 else bake_ceil(j, x, y)
    return (0, 0, 0) if c is None else c


BAKERS = {"ceil": bake_ceil, "floor": bake_floor, "left": bake_left, "right": bake_right}


if __name__ == "__main__":
    from PIL import Image
    im = Image.new("RGB", (TILE_W * 8, TILE_H * 8))
    d = im.load()
    for y in range(TILE_H * 8):
        for x in range(TILE_W * 8):
            d[x, y] = TILE[y % TILE_H][x % TILE_W]
    im.resize((TILE_W * 8 * 4, TILE_H * 8 * 4), Image.NEAREST).save(
        r"C:\Users\byunh\AppData\Local\Temp\q\tile.png")
    print("타일 %dx%d, 벽돌 %dx%d, 줄눈 %d" % (TILE_W, TILE_H, BRICK_W, BRICK_H, MORTAR))
