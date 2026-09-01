"""옆면 렌더링을 결정적으로 검증한다.

맵이 부팅마다 새로 생기므로(doc/random_map.md) 화면을 다시 찍어도 같은 그림이
안 나온다. 그래서 MapDataRam 에 알려진 지도를 직접 써 넣고 다시 그리게 한다.

두 가지를 함께 본다.

  1. Vis / VisPost 표 - BuildVisibility 가 정한 값이 모델과 글자 그대로 같은가
  2. 화면 픽셀 - **구워진 바이트를 그대로 걸어가는 흉내 렌더러**와 같은가

둘 다 봐야 하는 이유는, 화면이 우연히 맞을 수도 있고(상태가 틀렸는데 그림이
같은 경우) 표가 맞아도 런 형식이 어긋날 수도 있기 때문이다.

  uv run --with pillow python gfx/quest_sides.py tcl   <작업폴더>
  uv run --with pillow python gfx/quest_sides.py check <작업폴더>

가운데에서 verify_quest_sides.ps1 이 openMSX 를 케이스마다 한 번씩 돌린다.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import quest_geom as G
import quest_convert as C
import quest_tex as T                                    # noqa: F401  (C 가 쓴다)

# quest.sym 을 읽어 주소를 잡는다. 변수를 하나 넣기만 해도 밀리는 값들이다.
SYM = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "build", "quest.sym")

from quest_pal import PAL333 as PAL          # noqa: E402
# openMSX 는 3비트 채널을 선형이 아니라 이 표로 8비트에 편다.
LUT = [0, 43, 81, 118, 153, 187, 221, 255]
RGB888 = [tuple(LUT[v] for v in c) for c in PAL]
BLACK = PAL.index((0, 0, 0))

SHOT_OX, SHOT_OY = 32, 14                                # 320x240 안의 화면 원점
DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]                # 북 동 남 서


def syms():
    out = {}
    for line in open(SYM, encoding="utf-8"):
        if ": EQU 0x" in line:
            name, val = line.split(": EQU 0x")
            out[name] = int(val.strip(), 16)
    return out


def rect(x0, x1, y0, y1):
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


def grid_of(open_cells):
    g = [['#'] * 16 for _ in range(16)]
    for x, y in open_cells:
        g[y][x] = '.'
    return [''.join(r) for r in g]


# 화면에서 본 지도(미니맵을 되읽어 복원한 것). 폭이 3인 통로가 안쪽에서 1로
# 좁아지는 자리가 있어서, 멀리 있는 벽이 옆으로 이어져 보여야 하는 상황이 나온다.
ROOMS = [
    "################", "############...#", "########.###...#", "#######........#",
    "#######..###...#", "#...##...####.##", "#...##...###..##", "#...###..###..##",
    "#.............##", "#####....###..##", "#####....#######", "#####....#######",
    "#####....#######", "################", "################", "################"]

# 옆면의 세 갈래(옆칸이 벽 / 어느 평면에서 만남 / 끝까지 없음)를 고루 걸리게 한다.
CASES = {
    # 5x5 방 한가운데 - 옆도 그 너머도 뚫려 있다
    "plaza":  (grid_of(rect(5, 9, 5, 9)), 7, 7, 0),
    # 곧은 통로에 왼쪽 옆길 하나 - 바로 옆 평면에서 만난다
    "branch": (grid_of(rect(7, 7, 4, 9) + [(6, 6), (5, 6)]), 7, 8, 0),
    # 왼쪽만 두 칸 뚫림 - 같은 구간에서 좌우가 다르게 나와야 한다
    "asym":   (grid_of(rect(7, 7, 4, 9) + rect(5, 6, 6, 7)), 7, 8, 0),
    # 넓은 통로에서 남쪽으로 - 멀리 있는 벽이 두 칸 너머(k = j+2, j+3)에 있다.
    # 이 두 자리가 '기둥 두 개로 끊겨' 보이던 화면이다.
    "far2":   (ROOMS, 13, 3, 2),
    "far3":   (ROOMS, 13, 2, 2),
    # 막다른 곳 - 정면 벽이 화면의 절반을 차지한다. 정면 벽의 위/아래 변이
    # 천장·바닥과 만나는 자리에 흰 줄이 생기던 화면이다(2단계 정면 벽 경로).
    "dead":   (grid_of(rect(7, 7, 4, 9)), 7, 5, 0),
}


def selectors(grid, px, py, facing):
    """quest.asm 의 SideVis 와 같은 규칙. 면 f 마다 무엇이 보이는지 정한다.

    "wall" = 옆칸이 벽, 정수 k = 평면 z=k 에서 만남, None = 끝까지 없음.
    """
    def wall(x, y):
        return not (0 <= x < 16 and 0 <= y < 16) or grid[y][x] == '#'

    fx, fy = DIRS[facing]
    block = G.MAXD + 1
    for k in range(1, G.MAXD + 1):
        if wall(px + fx * k, py + fy * k):
            block = k
            break

    sel = {}
    for j in range(G.NSEG):
        for side, rot in ((0, 3), (1, 1)):
            dx, dy = DIRS[(facing + rot) & 3]
            if wall(px + fx * j + dx, py + fy * j + dy):
                sel[j * 2 + side] = "wall"
                continue
            hit = None
            for k in range(j + 1, G.NSEG + 1):
                m = G.LATERAL[j][k]
                if wall(px + fx * k + dx * m, py + fy * k + dy * m):
                    hit = k
                    break
            sel[j * 2 + side] = hit
    return sel, block


def expect_tables(grid, px, py, facing, widths):
    """BuildVisibility 가 채울 Vis / VisPost 를 그대로 계산한다."""
    sel, block = selectors(grid, px, py, facing)
    vis = [0] * C.NUM_IDS
    post = [0] * C.NUM_IDS
    vis[C.CENTRE_ID] = C.VIS_SKIP if block <= G.MAXD else C.VIS_BLACK
    for j in range(G.NSEG):
        occluded = j >= block
        vis[j * 2] = vis[j * 2 + 1] = C.VIS_SKIP if occluded else C.VIS_TEX
        for side in (0, 1):
            f = j * 2 + side
            w = widths[f]
            s = sel[f]
            if occluded:
                vis[C.OUTER0 + f] = C.VIS_SKIP2
            else:
                vis[C.OUTER0 + f] = C.VIS_WALL2 if s == "wall" else C.VIS_GAP2
            for K in range(j + 1, G.NSEG + 1):
                i = C.band_id(f, K)
                n = 2 + (K - j)
                if occluded:
                    vis[i], post[i] = C.VIS_SKIPN, n * w
                    continue
                if s == "wall":
                    idx = 0
                elif s is not None and s <= K:
                    idx = s - j
                else:
                    idx = n - 1
                vis[i] = C.VIS_OFS + idx * w
                post[i] = (n - 1 - idx) * w
    return vis, post, block


def emulate(runs, fronts, vis, post):
    """RenderDungeon 을 바이트 단위로 흉내 낸다 -> 96x96 팔레트 번호."""
    scr = [[BLACK] * G.VIEW_W for _ in range(G.VIEW_H)]
    p = 0
    for y in range(G.VIEW_H):
        xb = 0
        while True:
            sid, w = runs[p], runs[p + 1]
            p += 2
            if w == 0:
                break
            st = vis[sid]
            if st >= C.VIS_OFS:                          # 띠 안 - 상수 오프셋
                pre = st - C.VIS_OFS
                total = pre + w + post[sid]
                draw = pre
            elif st == C.VIS_SKIPN:
                pre, total, draw = 0, post[sid], None
            elif st == C.VIS_TEX:
                pre, total, draw = 0, w, 0
            elif st == C.VIS_SKIP:
                pre, total, draw = 0, w, None
            elif st == C.VIS_BLACK:
                pre, total, draw = 0, w, "black"
            elif st == C.VIS_WALL2:
                pre, total, draw = 0, 2 * w, 0
            elif st == C.VIS_GAP2:
                pre, total, draw = w, 2 * w, w
            else:                                        # VIS_SKIP2
                pre, total, draw = 0, 2 * w, None
            if draw is not None:
                for i in range(w):
                    v = (BLACK << 4) | BLACK if draw == "black" else runs[p + draw + i]
                    scr[y][(xb + i) * 2] = v >> 4
                    scr[y][(xb + i) * 2 + 1] = v & 15
            p += total
            xb += w
    return scr


def draw_front(scr, fronts, block):
    if block > G.MAXD:
        return
    blob = fronts[block - 1]
    t, h, xbyte, wb = blob[:4]
    k = 4
    for yy in range(t, t + h):
        for i in range(wb):
            v = blob[k]
            k += 1
            x = (xbyte + i) * 2 - G.VIEW_X
            scr[yy - G.VIEW_Y][x] = v >> 4
            scr[yy - G.VIEW_Y][x + 1] = v & 15


def face_widths():
    """면마다 띠 안 런의 바이트 폭. 변환기가 쓰는 값과 같아야 한다."""
    idm, _ = C.build_maps()
    out = {}
    for y in range(G.VIEW_H):
        K = C.kmax_at(G.VIEW_Y + y)
        row = idm[y]
        cur, n = row[0], 0
        runs = []
        for xb in range(0, G.VIEW_W, 2):
            if row[xb] == cur:
                n += 1
            else:
                runs.append((cur, n))
                cur, n = row[xb], 1
        runs.append((cur, n))
        for sid, n in runs:
            if C.geom_is_side(sid) and K > sid // 4:
                out[(sid // 4) * 2 + (sid % 4 - 2)] = n
    return out


def write_tcl(outdir):
    s = syms()
    for name, (grid, px, py, f) in CASES.items():
        w = ["debug write memory %d %d" % (s["MapDataRam"] + y * 16 + x,
                                           1 if grid[y][x] == '#' else 0)
             for y in range(16) for x in range(16)]
        w += ["debug write memory %d %d" % (s["posX"], px),
              "debug write memory %d %d" % (s["posY"], py),
              "debug write memory %d %d" % (s["facing"], f)]
        png = os.path.join(outdir, name + ".png").replace("\\", "/")
        # Tcl 쪽은 ASCII 로만 쓴다. openMSX 의 Tcl 은 BOM 도 한글도 잘 못 받는다.
        L = ["# %s - generated by gfx/quest_sides.py" % name,
             "after time 7 { %s }" % " ; ".join(w),
             # 마주치기가 걸리면 몬스터가 던전 위에 얹혀 가린다
             "after time 8.0 { debug write memory %d 0 ; debug write memory %d 1 }"
             % (s["BattleOn"], s["needDraw"]),
             'after time 8.4 {',
             '  set fh [open "%s" w]' % png.replace(".png", ".dump"),
             '  puts $fh "pos [debug read memory %d] [debug read memory %d]'
             ' facing [debug read memory %d]"' % (s["posX"], s["posY"], s["facing"]),
             '  set v ""',
             '  for {set i 0} {$i < %d} {incr i} '
             '{ append v "[debug read memory [expr %d + $i]] " }' % (C.NUM_IDS, s["Vis"]),
             '  puts $fh "vis $v"',
             '  set q ""',
             '  for {set i 0} {$i < %d} {incr i} '
             '{ append q "[debug read memory [expr %d + $i]] " }' % (C.NUM_IDS, s["VisPost"]),
             '  puts $fh "post $q"',
             '  close $fh',
             '}',
             'after time 8.6 { screenshot -raw -size auto "%s" }' % png,
             "after time 9.0 { exit }"]
        open(os.path.join(outdir, name + ".tcl"), "w",
             encoding="ascii", newline="\n").write("\n".join(L) + "\n")
    print("wrote %d tcl scripts to %s" % (len(CASES), outdir))


def check(outdir):
    from PIL import Image
    idm, rgbm = C.build_maps()
    runs, _, _, _ = C.build_runs(idm, rgbm, PAL)
    fronts = C.build_front(PAL)
    widths = face_widths()
    bad = 0
    for name, (grid, px, py, f) in CASES.items():
        vis, post, block = expect_tables(grid, px, py, f, widths)
        dump = open(os.path.join(outdir, name + ".dump"), encoding="utf-8").read().split("\n")
        gx, gy, gf = (int(v) for v in dump[0].replace("pos", "").replace("facing", "").split())
        gvis = [int(v) for v in dump[1].split()[1:]]
        gpost = [int(v) for v in dump[2].split()[1:]]
        pos_ok = (gx, gy, gf) == (px, py, f)
        vis_ok = gvis == vis and gpost == post

        scr = emulate(runs, fronts, vis, post)
        draw_front(scr, fronts, block)
        shot = Image.open(os.path.join(outdir, name + ".png")).convert("RGB").load()
        diff = sum(shot[SHOT_OX + G.VIEW_X + x, SHOT_OY + G.VIEW_Y + y] != RGB888[scr[y][x]]
                   for y in range(G.VIEW_H) for x in range(G.VIEW_W))
        bad += diff + (0 if pos_ok else 1) + (0 if vis_ok else 1)
        print("%-7s pos %s  표 %s  다른 픽셀 %d"
              % (name, "OK" if pos_ok else "MISMATCH %s != %s" % ((gx, gy, gf), (px, py, f)),
                 "OK" if vis_ok else "MISMATCH", diff))
        if not vis_ok:
            for i in range(C.NUM_IDS):
                if gvis[i] != vis[i] or gpost[i] != post[i]:
                    print("   면 %2d: 롬 (%3d,%3d)  모델 (%3d,%3d)"
                          % (i, gvis[i], gpost[i], vis[i], post[i]))
    print("PASS" if bad == 0 else "FAIL")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    mode, outdir = sys.argv[1], sys.argv[2]
    sys.exit(write_tcl(outdir) if mode == "tcl" else check(outdir))
