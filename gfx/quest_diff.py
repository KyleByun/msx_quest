"""에뮬레이터 화면과 파이썬 미리보기를 픽셀 단위로 비교한다.

미리보기는 원래 색 그대로 그리므로, 변환기와 똑같은 규칙(nearest)으로 팔레트
번호를 고른 뒤 openMSX 가 화면에 내보내는 값으로 바꿔서 비교한다.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
import quest_geom as G
import quest_convert as C
import quest_preview as P

PAL333 = [(7,7,6),(7,7,5),(7,6,5),(6,6,5),(5,5,5),(5,5,3),(4,4,4),(3,3,3),
          (2,2,2),(0,0,0),(1,1,1),(6,6,6),(7,7,7),(7,6,4),(5,4,5),(5,5,2)]
# openMSX 가 V9938 의 3비트 채널을 화면에 내보낼 때 쓰는 값. 선형이 아니다.
LEVEL = [0, 43, 81, 118, 153, 187, 221, 255]
SCREEN = [tuple(LEVEL[v] for v in c) for c in PAL333]

d = sys.argv[1] if len(sys.argv) > 1 else "."
shots = [("w0",1,13,0), ("w1",1,12,0), ("w2",1,11,0), ("w3",1,11,1),
         ("w4",1,11,1), ("w5",1,11,1)]
tot = worst = 0
for n, x, y, f in shots:
    p = os.path.join(d, n + ".png")
    if not os.path.exists(p):
        continue
    emu = Image.open(p).convert("RGB").crop(
        (32+G.VIEW_X, 14+G.VIEW_Y, 32+G.VIEW_X+G.VIEW_W, 14+G.VIEW_Y+G.VIEW_H))
    pre = P.render(x, y, f)
    a, b = emu.load(), pre.load()
    diff = Image.new("RGB", (G.VIEW_W, G.VIEW_H))
    dd = diff.load()
    bad = 0
    for yy in range(G.VIEW_H):
        for xx in range(G.VIEW_W):
            want = SCREEN[C.nearest(PAL333, b[xx, yy])]
            if a[xx, yy] != want:
                bad += 1
                dd[xx, yy] = (255, 0, 0)
            else:
                dd[xx, yy] = a[xx, yy]
    diff.save(os.path.join(d, "diff_" + n + ".png"))
    tot += bad
    worst = max(worst, bad)
    print("%s (%2d,%2d) 방향%d  다른 픽셀 %4d / %d  (%.2f%%)"
          % (n, x, y, f, bad, G.VIEW_W*G.VIEW_H, 100.0*bad/(G.VIEW_W*G.VIEW_H)))
print("합계 %d, 최대 %d" % (tot, worst))

# 쓰는 법
#   uv run --with pillow python gfx/quest_diff.py <스크린샷 폴더>
# 폴더에 walk.tcl 이 남긴 w0..w5.png 가 있어야 한다.
#
# 남는 차이는 0.1~0.25% 수준이고 자리가 정해져 있다. build_runs 가 두 픽셀을 한
# 바이트에 담기 때문에, 런 경계가 바이트 한가운데 걸리면 그 바이트가 한쪽 면의
# 색으로 통일된다. 미리보기는 픽셀 단위라 그 자리에서만 갈린다. 그보다 큰 차이가
# 나오면 진짜 회귀다.
