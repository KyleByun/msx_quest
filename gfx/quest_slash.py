"""맞은 자국 세 장. 무기 계열마다 모양이 다르다. 몬스터 칸 위에 차례로 찍는다.

전에는 흰 마름모를 반지름 2/4/6 으로 세 번 키워 찍었다. 지우지 않아도 됐던
것은 뒤 프레임이 앞 프레임을 통째로 덮었기 때문이다. 자국은 그렇지 않다 -
2 번이 1 번을 안 덮고, 3 번은 오히려 옅어진다. 그래서 부르는 쪽(HitFlash)이
장마다 BACK 에서 칸을 되돌린다.

계열 셋
  blade    칼, 도, 둔기. 오른쪽 위에서 왼쪽 아래로 휜 자국.
  polearm  창, 봉. **아래서 위로** 길게 베어 지나간다 - 거의 곧고 가늘다.
  bow      활, 쇠뇌. 자국이 아니라 **화살 한 대**가 아래서 위로 날아온다.
           앞의 둘과 달리 장마다 모양이 아니라 **자리**가 바뀐다.

세 장의 뜻 (칼/창)
  1  들어가는 자국. 앞쪽 절반만, 가늘게.
  2  다 지나간 자국. 끝에서 끝까지, 제일 굵고 밝게.
  3  흩어지는 자국. 가운데가 끊기고 얇아진다.

칼은 곡선으로 긋는다. 곧은 막대는 칼보다 창에 가깝다 - 그 곧음이 창 계열의
표시가 되게 두었다.
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

N = 3                           # 몇 장인가

FAMILIES = ("blade", "polearm", "bow")

CORE = (255, 255, 255)          # 날 한가운데
EDGE = (168, 216, 255)          # 가장자리 - 옅은 하늘빛

# 획으로 긋는 계열의 설정.
#
#   pts     2차 베지에 조절점 셋. t=0 이 자국이 시작되는 쪽이다.
#   shape   장마다 (곡선의 어디부터 어디까지, 한가운데 굵기, 밝기)
#   breaks  마지막 장에서 끊어 놓을 t 범위. 흩어지는 느낌을 낸다.
STROKE = {
    "blade": {
        # 오른쪽 위 -> 왼쪽 아래. 가운데 점을 오른쪽 아래로 당겨 휘게 한다.
        "pts": ((0.92, 0.08), (0.72, 0.72), (0.08, 0.92)),
        "shape": [(0.00, 0.55, 0.10, 1.00),
                  (0.00, 1.00, 0.16, 1.00),
                  (0.35, 1.00, 0.09, 0.82)],
        "breaks": [(0.52, 0.60), (0.74, 0.80)],
    },
    "polearm": {
        # 아래 -> 위. 거의 곧게 세우고 살짝만 기울인다. 칼보다 가늘고 길다.
        "pts": ((0.70, 1.06), (0.46, 0.52), (0.30, -0.06)),
        "shape": [(0.00, 0.52, 0.055, 1.00),
                  (0.00, 1.00, 0.090, 1.00),
                  (0.48, 1.00, 0.050, 0.80)],
        "breaks": [(0.60, 0.68), (0.82, 0.88)],
    },
}

# --- 화살 ---
# 장마다 촉이 이만큼 높이에 온다 (칸 높이의 비율, 0 이 맨 위).
ARROW_AT = (0.88, 0.62, 0.38)
ARROW_LEN = 0.44                # 화살 길이 (칸 높이의 비율)
ARROW_X = 0.48                  # 날아가는 자리 - 몸 한가운데보다 살짝 왼쪽
ARROW_LEAN = 0.10               # 위로 갈수록 왼쪽으로 - 비스듬히 날아온다
SHAFT = (208, 160, 96)          # 대 - 나무빛
HEAD = (232, 240, 255)          # 촉 - 쇠빛
FLETCH = (255, 255, 255)        # 깃


def curve(t, size, pts):
    """t=0..1 -> 칸 안의 (x, y). 조절점 셋짜리 2차 베지에."""
    p0, p1, p2 = pts
    u = 1.0 - t
    x = u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0]
    y = u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]
    return x * (size - 1), y * (size - 1)


def width_at(t, t0, t1, peak):
    """자국의 굵기. 양 끝에서 뾰족하게 여윈다 - 칼자국은 끝이 가늘다."""
    if t < t0 or t > t1:
        return 0.0
    s = (t - t0) / max(t1 - t0, 1e-6)           # 이 자국 안에서의 0..1
    return peak * math.sin(math.pi * s) ** 0.6


FAMILIES = ("blade", "polearm", "bow")


def frames(size, family="blade"):
    """size x size RGBA 세 장. family 는 FAMILIES 중 하나."""
    if family == "bow":
        return arrow_frames(size)
    return stroke_frames(size, STROKE[family])


def stroke_frames(size, cfg):
    """칼/창처럼 한 번 그어 지나가는 자국."""
    out = []
    for i, (t0, t1, peak, bright) in enumerate(cfg["shape"]):
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        px = im.load()
        pk = peak * size                        # 굵기를 칸 크기에 맞춘다
        # 곡선을 촘촘히 훑으며 그 자리를 중심으로 원을 찍는다. 폴리곤을 쓰면
        # 안티에일리어싱이 붙어 반투명 픽셀이 생기는데, 스프라이트는 투명이냐
        # 아니냐 둘뿐이라 도리어 지저분해진다.
        steps = max(size * 6, 120)
        for k in range(steps + 1):
            t = t0 + (t1 - t0) * k / steps
            if i == N - 1 and any(a <= t <= b for a, b in cfg["breaks"]):
                continue                        # 끊어진 자리
            w = width_at(t, t0, t1, pk)
            if w <= 0.3:
                continue
            cx, cy = curve(t, size, cfg["pts"])
            disc(px, size, cx, cy, w, bright)
        out.append(im)
    return out


def disc(px, size, cx, cy, w, bright):
    """(cx, cy) 에 지름 w 짜리 점 하나. 한가운데는 희고 가장자리로 갈수록 하늘빛."""
    r = int(w / 2) + 1
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d = math.hypot(dx, dy)
            if d > w / 2:
                continue
            x, y = int(round(cx + dx)), int(round(cy + dy))
            if not (0 <= x < size and 0 <= y < size):
                continue
            f = min(d / max(w / 2, 1e-6), 1.0)
            c = tuple(int(round(CORE[j] + (EDGE[j] - CORE[j]) * f))
                      for j in range(3))
            px[x, y] = tuple(int(round(v * bright)) for v in c) + (255,)


def stamp(px, size, x, y, colour):
    """픽셀 하나. 스프라이트는 투명이냐 아니냐 둘뿐이라 섞지 않고 그냥 덮는다."""
    xi, yi = int(round(x)), int(round(y))
    if 0 <= xi < size and 0 <= yi < size:
        px[xi, yi] = colour + (255,)


def seg(px, size, x0, y0, x1, y1, thick, colour):
    """(x0,y0)-(x1,y1) 선분. thick 은 픽셀 수."""
    n = int(max(abs(x1 - x0), abs(y1 - y0)) * 3) + 1
    half = (thick - 1) / 2.0
    for k in range(n + 1):
        u = k / n
        x = x0 + (x1 - x0) * u
        y = y0 + (y1 - y0) * u
        o = -half
        while o <= half + 1e-6:
            stamp(px, size, x + o, y, colour)
            o += 1.0


def arrow_frames(size):
    """화살 한 대가 아래서 위로 날아온다. 장마다 모양이 아니라 자리가 바뀐다.

    칼/창은 지나간 자국이라 장마다 길이와 굵기가 달라지지만, 화살은 같은 것이
    옮겨 가는 것이라 모양을 그대로 두고 촉의 높이만 옮긴다. 세 장을 이어 보면
    아래에서 몬스터 쪽으로 날아드는 것으로 보인다.
    """
    out = []
    ln = ARROW_LEN * size                       # 화살 길이
    thick = max(1, int(round(size / 20.0)))     # 대의 굵기
    hw = max(1, int(round(size / 13.0)))        # 촉의 반폭
    hl = max(2, int(round(size / 9.0)))         # 촉의 길이
    for tip in ARROW_AT:
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        px = im.load()
        ty = tip * (size - 1)                   # 촉 끝
        by = ty + ln                            # 오늬 끝
        # 위로 갈수록 왼쪽으로 - 비스듬히 날아든다
        tx = ARROW_X * size - ARROW_LEAN * size * (1.0 - tip)
        bx = tx + ARROW_LEAN * size
        seg(px, size, tx, ty + hl, bx, by, thick, SHAFT)        # 대
        for k in range(hl + 1):                                 # 촉 - 세모
            u = k / float(hl)
            w = hw * u
            y = ty + k
            x = tx + (bx - tx) * (k / max(ln, 1e-6))
            o = -w
            while o <= w + 1e-6:
                stamp(px, size, x + o, y, HEAD)
                o += 1.0
        f = max(2, int(round(size / 12.0)))                     # 깃 둘
        seg(px, size, bx, by, bx - f, by - f, 1, FLETCH)
        seg(px, size, bx, by, bx + f, by - f, 1, FLETCH)
        out.append(im)
    return out


def preview(sizes, path):
    """세로로 크기, 가로로 계열x장을 늘어놓은 그림 한 장 - 눈으로 보려는 것."""
    pad = 4
    cols = N * len(FAMILIES)
    w = max(sizes) * cols + pad * (cols + 1)
    h = sum(sizes) + pad * (len(sizes) + 1)
    sheet = Image.new("RGBA", (w, h), (24, 24, 32, 255))
    y = pad
    for s in sizes:
        i = 0
        for fam in FAMILIES:
            for im in frames(s, fam):
                sheet.alpha_composite(im, (pad + i * (max(sizes) + pad), y))
                i += 1
        y += s + pad
    sheet.save(path)
    return path


if __name__ == "__main__":
    import quest_geom as G
    sizes = sorted({G.mon_layout(n)[2] for n in range(1, 6)}, reverse=True)
    p = preview(sizes, os.path.join(HERE, "slash_preview.png"))
    for fam in FAMILIES:
        for s in sizes:
            on = [sum(1 for y in range(s) for x in range(s) if im.load()[x, y][3])
                  for im in frames(s, fam)]
            print("%-8s %2dpx: 켜진 픽셀 %s" % (fam, s, on))
    print("미리 보기: %s" % p)
