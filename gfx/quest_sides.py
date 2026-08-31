"""옆면 세 상태(벽 / 대각선 앞칸의 정면 / 뚫림)를 결정적으로 검증한다.

맵이 부팅마다 새로 생기므로(doc/random_map.md) 화면을 다시 찍어도 같은 그림이
안 나온다. 그래서 MapDataRam 에 알려진 지도를 직접 써 넣고 다시 그리게 한다.

대조 상대는 quest_preview 가 아니라 **구워진 바이트를 그대로 걸어가는 흉내
렌더러**다. RunData 를 실제 순서대로 훑으며 상태에 따라 블록을 고르므로, 런
형식과 상태 기계와 2단계 정면 벽까지 통째로 걸린다. 한 픽셀이라도 다르면 잡힌다.

  uv run --with pillow python gfx/quest_sides.py tcl   <작업폴더>
  uv run --with pillow python gfx/quest_sides.py check <작업폴더>

가운데에서 verify_quest_sides.ps1 이 openMSX 를 세 번 돌린다.
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

PAL = [(7, 7, 6), (7, 7, 5), (7, 6, 5), (6, 6, 5), (5, 5, 5), (5, 5, 3), (4, 4, 4), (3, 3, 3),
       (2, 2, 2), (0, 0, 0), (1, 1, 1), (6, 6, 6), (7, 7, 7), (7, 6, 4), (5, 4, 5), (5, 5, 2)]
# openMSX 는 3비트 채널을 선형이 아니라 이 표로 8비트에 편다.
LUT = [0, 43, 81, 118, 153, 187, 221, 255]
RGB888 = [tuple(LUT[v] for v in c) for c in PAL]
BLACK = PAL.index((0, 0, 0))

SHOT_OX, SHOT_OY = 32, 14                                # 320x240 안의 화면 원점


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


# 세 상태를 각각 걸리게 하는 지도. 넷째가 있다면 여기에 한 줄 더한다.
CASES = {
    # 5x5 방 한가운데 - 옆도 대각선도 뚫려 있다 (없는 벽이 보이던 경우)
    "plaza":  (grid_of(rect(5, 9, 5, 9)), 7, 7, 0),
    # 곧은 통로에 왼쪽 옆길 하나 - 옆은 뚫렸고 대각선은 벽
    "branch": (grid_of(rect(7, 7, 4, 9) + [(6, 6), (5, 6)]), 7, 8, 0),
    # 왼쪽만 두 칸 뚫림 - 같은 구간에서 좌우가 다르게 나와야 한다
    "asym":   (grid_of(rect(7, 7, 4, 9) + rect(5, 6, 6, 7)), 7, 8, 0),
}

DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]                # 북 동 남 서


def expect_vis(grid, px, py, facing):
    """quest.asm 의 BuildVisibility 와 같은 규칙."""
    def wall(x, y):
        return not (0 <= x < 16 and 0 <= y < 16) or grid[y][x] == '#'

    fx, fy = DIRS[facing]
    block = G.MAXD + 1
    for k in range(1, G.MAXD + 1):
        if wall(px + fx * k, py + fy * k):
            block = k
            break

    vis = {C.CENTRE_ID: C.VIS_SKIP if block <= G.MAXD else C.VIS_BLACK}
    for j in range(G.NSEG):
        b = j * 4
        if j >= block:
            vis[b], vis[b + 1] = C.VIS_SKIP, C.VIS_SKIP
            vis[b + 2], vis[b + 3] = C.VIS_SKIP3, C.VIS_SKIP3
            continue
        vis[b] = vis[b + 1] = C.VIS_TEX
        cx, cy = px + fx * j, py + fy * j
        for k, rot in ((2, 3), (3, 1)):                  # 왼쪽, 오른쪽
            dx, dy = DIRS[(facing + rot) & 3]
            if wall(cx + dx, cy + dy):
                vis[b + k] = C.VIS_WALL3
            elif wall(cx + fx + dx, cy + fy + dy):
                vis[b + k] = C.VIS_OPEN3
            else:
                vis[b + k] = C.VIS_GAP3
    return vis, block


def emulate(runs, fronts, vis, block):
    """RenderDungeon 을 바이트 단위로 흉내 낸다 -> 96x96 팔레트 번호."""
    scr = [[BLACK] * G.VIEW_W for _ in range(G.VIEW_H)]
    # 상태 -> (몇 번째 블록을 그리는가, 블록이 몇 개인가). -1 은 안 그림.
    PICK = {C.VIS_TEX: 0, C.VIS_WALL3: 0, C.VIS_OPEN3: 1, C.VIS_GAP3: 2,
            C.VIS_BLACK: -2, C.VIS_SKIP: -1, C.VIS_SKIP3: -1}
    p = 0
    for y in range(G.VIEW_H):
        xb = 0
        while True:
            sid, w = runs[p], runs[p + 1]
            p += 2
            if w == 0:
                break
            n = 3 if C.is_side(sid) else 1
            draw = PICK[vis[sid]]
            for i in range(w):
                if draw == -1:
                    continue
                v = (BLACK << 4) | BLACK if draw == -2 else runs[p + draw * w + i]
                scr[y][(xb + i) * 2] = v >> 4
                scr[y][(xb + i) * 2 + 1] = v & 15
            p += n * w
            xb += w
    if block <= G.MAXD:                                  # 2단계: 정면 벽
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
    return scr


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
    runs, _ = C.build_runs(idm, rgbm, PAL)
    fronts = C.build_front(PAL)
    bad = 0
    for name, (grid, px, py, f) in CASES.items():
        vis, block = expect_vis(grid, px, py, f)
        dump = open(os.path.join(outdir, name + ".dump"), encoding="utf-8").read().split("\n")
        gx, gy, gf = (int(v) for v in dump[0].replace("pos", "").replace("facing", "").split())
        got = [int(v) for v in dump[1].split()[1:]]
        want = [vis[i] for i in range(C.NUM_IDS)]
        pos_ok = (gx, gy, gf) == (px, py, f)
        vis_ok = got == want
        shot = Image.open(os.path.join(outdir, name + ".png")).convert("RGB").load()
        exp = emulate(runs, fronts, vis, block)
        diff = sum(shot[SHOT_OX + G.VIEW_X + x, SHOT_OY + G.VIEW_Y + y] != RGB888[exp[y][x]]
                   for y in range(G.VIEW_H) for x in range(G.VIEW_W))
        bad += diff + (0 if pos_ok else 1) + (0 if vis_ok else 1)
        print("%-7s pos %s  vis %s  다른 픽셀 %d"
              % (name, "OK" if pos_ok else "MISMATCH %s != %s" % ((gx, gy, gf), (px, py, f)),
                 "OK" if vis_ok else "MISMATCH\n  got  %s\n  want %s" % (got, want), diff))
    print("PASS" if bad == 0 else "FAIL")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    mode, outdir = sys.argv[1], sys.argv[2]
    sys.exit(write_tcl(outdir) if mode == "tcl" else check(outdir))
