"""quest.asm 의 렌더러를 파이썬으로 똑같이 돌려 본다.

면 상태를 정하는 규칙(quest.asm 의 BuildVisibility)과 그 상태로 픽셀을 고르는
규칙(RenderDungeon 의 이중 블록 처리)을 그대로 옮겨 두었다. 픽셀 자체도 ROM 과
같은 굽기 함수에서 가져온다. 그래서 이 그림과 에뮬레이터 화면이 다르면 둘 중
하나가 틀린 것이고, 회귀를 바로 알 수 있다.

다른 점은 하나뿐이다. 여기서는 16색으로 줄이지 않고 원래 색 그대로 그린다.
"""
from PIL import Image
import quest_geom as G
import quest_tex as T
import quest_convert as C
from quest_map import MAP

DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]      # 북 동 남 서

IDM, RGB = C.build_maps()                       # ROM 에 들어가는 것과 같은 굽기


def is_wall(mx, my):
    if my < 0 or my >= len(MAP) or mx < 0 or mx >= len(MAP[my]):
        return True
    return MAP[my][mx] == '#'


def visibility(px, py, facing):
    """BuildVisibility 와 같은 규칙으로 면 상태를 정한다."""
    fx, fy = DIRS[facing]
    lx, ly = DIRS[(facing + 3) & 3]
    rx, ry = DIRS[(facing + 1) & 3]

    block = G.MAXD + 1
    for k in range(1, G.MAXD + 1):
        if is_wall(px + fx * k, py + fy * k):
            block = k
            break

    vis = {C.CENTRE_ID: "skip" if block <= G.MAXD else "black"}
    for j in range(G.NSEG):
        base = j * 4
        if j >= block:                          # 정면 벽이 덮는다
            vis[base + 0] = vis[base + 1] = "skip"
            vis[base + 2] = vis[base + 3] = "skip"
            continue
        cx, cy = px + fx * j, py + fy * j
        vis[base + 0] = vis[base + 1] = "tex"   # 천장, 바닥
        vis[base + 2] = "wall" if is_wall(cx + lx, cy + ly) else "open"
        vis[base + 3] = "wall" if is_wall(cx + rx, cy + ry) else "open"
    return vis, block


def render(px, py, facing):
    im = Image.new("RGB", (G.VIEW_W, G.VIEW_H), (0, 0, 0))
    d = im.load()
    vis, block = visibility(px, py, facing)

    for yy in range(G.VIEW_H):                  # 1단계: 통로
        for xx in range(G.VIEW_W):
            st = vis[IDM[yy][xx]]
            if st == "skip":
                continue                        # 2단계에서 정면 벽이 덮는다
            if st == "black":
                continue
            if st == "open":                    # 이중 블록의 둘째
                j = IDM[yy][xx] // 4
                d[xx, yy] = T.bake_open(j, G.VIEW_X + xx, G.VIEW_Y + yy)
            else:                               # 단일 블록 또는 이중 블록의 첫째
                d[xx, yy] = RGB[yy][xx]

    if block <= G.MAXD:                         # 2단계: 정면 벽
        l, t, r, b = G.RECT[block]
        l &= ~1                                 # 변환기와 같은 바이트 정렬.
        r = (r + 1) & ~1                        # 안 맞추면 좌우 한 줄이 어긋난다
        for y in range(t, b + 1):
            for x in range(l, r):
                if (G.VIEW_X <= x < G.VIEW_X + G.VIEW_W and
                        G.VIEW_Y <= y < G.VIEW_Y + G.VIEW_H):
                    d[x - G.VIEW_X, y - G.VIEW_Y] = T.bake_front(block, x, y)
    return im


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "preview_walk.png"
    shots = [(1, 13, 0), (1, 12, 0), (1, 11, 0), (1, 11, 1), (1, 11, 1), (1, 11, 1)]
    S = 2
    W, H = G.VIEW_W * S, G.VIEW_H * S
    sheet = Image.new("RGB", (len(shots) * (W + 4), H), (30, 30, 30))
    for i, (x, y, f) in enumerate(shots):
        sheet.paste(render(x, y, f).resize((W, H), Image.NEAREST), (i * (W + 4), 0))
    sheet.save(out)
    print("미리보기:", out, shots)
