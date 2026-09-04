"""칼질 자국 세 장. 몬스터가 맞았을 때 칸 위에 차례로 찍는다.

전에는 흰 마름모를 반지름 2/4/6 으로 세 번 키워 찍었다. 지우지 않아도 됐던
것은 뒤 프레임이 앞 프레임을 통째로 덮었기 때문이다. 칼질은 그렇지 않다 -
2 번이 1 번을 안 덮고, 3 번은 오히려 옅어진다. 그래서 부르는 쪽(HitFlash)이
칸을 화면 밖에 떠 두었다가 프레임마다 되돌린다.

세 장의 뜻
  1  들어가는 자국. 위쪽 절반만, 가늘게.
  2  다 지나간 자국. 끝에서 끝까지, 제일 굵고 밝게.
  3  흩어지는 자국. 가운데가 끊기고 얇아진다.

곡선으로 긋는다. 곧은 막대는 칼보다 창에 가깝다.
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

N = 3                           # 몇 장인가

CORE = (255, 255, 255)          # 날 한가운데
EDGE = (168, 216, 255)          # 가장자리 - 옅은 하늘빛

# 프레임마다 (곡선의 어디부터 어디까지, 한가운데 굵기, 밝기)
#
# t 는 곡선을 따라 0(오른쪽 위) -> 1(왼쪽 아래) 이다. 2 번만 끝까지 긋는다.
SHAPE = [(0.00, 0.55, 0.10, 1.00),
         (0.00, 1.00, 0.16, 1.00),
         (0.35, 1.00, 0.09, 0.82)]

# 3 번에서 자국을 끊어 놓을 자리 (t 범위). 흩어지는 느낌을 낸다.
BREAKS = [(0.52, 0.60), (0.74, 0.80)]


def curve(t, size):
    """t=0..1 -> 칸 안의 (x, y). 오른쪽 위에서 왼쪽 아래로 휜 칼자국."""
    # 조절점 셋짜리 2차 베지에. 가운데 점을 오른쪽 아래로 당겨 휘게 한다.
    p0 = (0.92, 0.08)
    p1 = (0.72, 0.72)
    p2 = (0.08, 0.92)
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


def frames(size):
    """size x size RGBA 세 장."""
    out = []
    for i, (t0, t1, peak, bright) in enumerate(SHAPE):
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        px = im.load()
        pk = peak * size                        # 굵기를 칸 크기에 맞춘다
        # 곡선을 촘촘히 훑으며 그 자리를 중심으로 원을 찍는다. 폴리곤을 쓰면
        # 안티에일리어싱이 붙어 반투명 픽셀이 생기는데, 스프라이트는 투명이냐
        # 아니냐 둘뿐이라 도리어 지저분해진다.
        steps = max(size * 6, 120)
        for k in range(steps + 1):
            t = t0 + (t1 - t0) * k / steps
            if i == N - 1 and any(a <= t <= b for a, b in BREAKS):
                continue                        # 끊어진 자리
            w = width_at(t, t0, t1, pk)
            if w <= 0.3:
                continue
            cx, cy = curve(t, size)
            r = int(w / 2) + 1
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    d = math.hypot(dx, dy)
                    if d > w / 2:
                        continue
                    x, y = int(round(cx + dx)), int(round(cy + dy))
                    if not (0 <= x < size and 0 <= y < size):
                        continue
                    # 한가운데는 희고 가장자리로 갈수록 하늘빛
                    f = min(d / max(w / 2, 1e-6), 1.0)
                    c = tuple(int(round(CORE[j] + (EDGE[j] - CORE[j]) * f))
                              for j in range(3))
                    c = tuple(int(round(v * bright)) for v in c)
                    px[x, y] = c + (255,)
        out.append(im)
    return out


def preview(sizes, path):
    """세로로 크기, 가로로 프레임을 늘어놓은 그림 한 장 - 눈으로 보려는 것."""
    pad = 4
    w = sum(s for s in sizes) * 0 + max(sizes) * N + pad * (N + 1)
    h = sum(sizes) + pad * (len(sizes) + 1)
    sheet = Image.new("RGBA", (w, h), (24, 24, 32, 255))
    y = pad
    for s in sizes:
        for i, im in enumerate(frames(s)):
            sheet.alpha_composite(im, (pad + i * (max(sizes) + pad), y))
        y += s + pad
    sheet.save(path)
    return path


if __name__ == "__main__":
    import quest_geom as G
    sizes = sorted({G.mon_layout(n)[2] for n in range(1, 6)}, reverse=True)
    p = preview(sizes, os.path.join(HERE, "slash_preview.png"))
    for s in sizes:
        on = [sum(1 for y in range(s) for x in range(s) if im.load()[x, y][3])
              for im in frames(s)]
        print("%2dpx: 켜진 픽셀 %s" % (s, on))
    print("미리 보기: %s" % p)
