"""quest.rom 이 쓰는 데이터를 전부 생성한다.

  - 팔레트 16색 (배경 UI 와 던전 벽돌이 한 팔레트를 공유)
  - 배경 화면 RLE (던전 뷰포트는 비워 둔다 - 실행 중에 그린다)
  - 원근이 적용된 벽면 픽셀 (스캔라인 런에 그대로 붙여 넣는다)
  - 정면 벽 비트맵 (막다른 곳에서 보이는 면)
  - 던전 맵

기하 구조가 고정이므로 텍스처도 고정이다. 화면좌표 -> 텍스처좌표 변환(원근
나눗셈 포함)을 여기서 미리 다 풀어 픽셀로 구워 둔다. Z80 은 바이트를 옮기기만
하면 되고, outi 로 한 바이트당 30 T-state 면 끝난다.
"""
from PIL import Image
import os
import quest_geom as G
import quest_tex as T
from quest_map import MAP

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# 참고 스크린샷 그대로의 배경. 원래는 OneDrive 의 원본을 매번 읽었는데 그 파일이
# 사라지면 빌드가 통째로 멈춘다. 이미 16색으로 정한 결과를 프로젝트 안에 정본으로
# 넣어 두었다. 256x212 이고 팔레트에 있는 색만 쓴다.
SRC = os.path.join(HERE, "quest_bg.png")

CENTRE_ID = G.NSEG * 4
NUM_IDS = CENTRE_ID + 1

# 면 상태 (실행 중에 정해진다)
#
# 좌우 벽은 픽셀 블록을 두 개 갖는다. 하나는 벽일 때, 하나는 옆길이 뚫렸을 때다.
# 뚫린 자리를 검게 두면 검은 벽처럼 보여서, 옆 통로의 바닥/천장이 이어지는
# 그림을 따로 구워 두고 골라 쓴다. 천장/바닥/한가운데는 블록이 하나뿐이다.
VIS_TEX = 0         # 단일 블록, 그리기 (가장 흔하므로 0 - 분기가 제일 짧다)
VIS_SKIP = 1        # 단일 블록, 건너뛰기 (정면 벽에 가려짐)
VIS_BLACK = 2       # 단일 블록, 검정으로 채우기 (통로 끝의 어둠)
VIS_WALL2 = 3       # 이중 블록, 첫째(벽) 그리기
VIS_OPEN2 = 4       # 이중 블록, 둘째(뚫림) 그리기
VIS_SKIP2 = 5       # 이중 블록, 둘 다 건너뛰기


def is_side(sid):
    """좌벽(2) 과 우벽(3) 만 블록을 두 개 갖는다."""
    return sid != CENTRE_ID and (sid % 4) >= 2


def to888(c):
    return tuple(round(v * 255 / 7) for v in c)


def snap333(c):
    return tuple(round(v * 7 / 255) for v in c)


def nearest(pal, c):
    best, bi = None, 0
    for i, p in enumerate(pal):
        pp = to888(p)
        d = sum((pp[k] - c[k]) ** 2 for k in range(3))
        if best is None or d < best:
            best, bi = d, i
    return bi


def rle(data):
    """0x80|n = 다음 바이트를 n+1 회 반복, 그 외 n = 이어지는 n+1 바이트 그대로."""
    out = bytearray()
    i, n = 0, len(data)
    while i < n:
        run = 1
        while i + run < n and data[i + run] == data[i] and run < 128:
            run += 1
        if run >= 3:
            out.append(0x80 | (run - 1))
            out.append(data[i])
            i += run
        else:
            j, lit = i, bytearray()
            while j < n and len(lit) < 128:
                r = 1
                while j + r < n and data[j + r] == data[j] and r < 3:
                    r += 1
                if r >= 3:
                    break
                lit.append(data[j])
                j += 1
            out.append(len(lit) - 1)
            out += lit
            i = j
    return bytes(out)


def db(name, data, per=16):
    o = ["%s:" % name] if name else []
    for i in range(0, len(data), per):
        o.append("    db " + ", ".join("0x%02X" % v for v in data[i:i + per]))
    return "\n".join(o)


# --------------------------------------------------------------------------
# 면 번호 지도와 구운 픽셀
# --------------------------------------------------------------------------
# 면 번호: j*4 + {0=천장,1=바닥,2=좌,3=우}  (j = 0..NSEG-1, 0 이 내가 선 칸)
# 마지막 번호 CENTRE_ID 는 한가운데(가장 안쪽)다.

def build_maps():
    """뷰포트의 각 픽셀이 어느 면인지, 그리고 그 픽셀의 색(RGB)을 굽는다."""
    W, H = G.VIEW_W, G.VIEW_H
    idm = [[CENTRE_ID] * W for _ in range(H)]
    rgb = [[(0, 0, 0)] * W for _ in range(H)]

    def stamp(spans, sid, baker, j):
        for y, x0, x1 in spans:
            yy = y - G.VIEW_Y
            if not (0 <= yy < H):
                continue
            for x in range(max(x0, G.VIEW_X), min(x1, G.VIEW_X + W)):
                c = baker(j, x, y)
                if c is None:
                    continue
                idm[yy][x - G.VIEW_X] = sid
                rgb[yy][x - G.VIEW_X] = c

    for j in range(G.NSEG - 1, -1, -1):
        q = G.segment_quads(j)
        base = j * 4
        for k, name in enumerate(("ceil", "floor", "left", "right")):
            stamp(q[name], base + k, T.BAKERS[name], j)
    return idm, rgb


def build_runs(idm, rgb, pal):
    """줄마다 (면번호, 바이트폭, 픽셀들) 런으로. 폭 0 이 줄의 끝.

    픽셀을 런 바로 뒤에 붙여 두면 포인터 하나로 순차 처리할 수 있다. 건너뛸
    면이라도 폭만큼 포인터를 밀면 되므로 별도 색인이 필요 없다.
    """
    W, H = G.VIEW_W, G.VIEW_H
    data, maxruns = [], 0
    for y in range(H):
        row = idm[y]
        runs, cur, n = [], row[0], 0
        for xb in range(0, W, 2):
            sid = row[xb]
            if sid == cur:
                n += 1
            else:
                runs.append((cur, n))
                cur, n = sid, 1
        runs.append((cur, n))
        maxruns = max(maxruns, len(runs))
        xb = 0
        for sid, n in runs:
            data += [sid, n]
            for i in range(n):                      # 블록 1: 벽면 그대로
                x = (xb + i) * 2
                hi = nearest(pal, rgb[y][x])
                lo = nearest(pal, rgb[y][x + 1])
                data.append((hi << 4) | lo)
            if is_side(sid):                        # 블록 2: 옆길이 뚫렸을 때
                j = sid // 4
                for i in range(n):
                    x = (xb + i) * 2
                    hi = nearest(pal, T.bake_open(j, G.VIEW_X + x, G.VIEW_Y + y))
                    lo = nearest(pal, T.bake_open(j, G.VIEW_X + x + 1, G.VIEW_Y + y))
                    data.append((hi << 4) | lo)
            xb += n
        data += [0, 0]
    return data, maxruns


def build_front(pal):
    """정면 벽 비트맵. d = 1..MAXD, 각각 RECT[d] 사각형을 채운다.

    형식: startY, 높이, xByte, 바이트폭, 그 뒤 픽셀
    """
    blobs = []
    for d in range(1, G.MAXD + 1):
        l, t, r, b = G.RECT[d]
        l &= ~1
        r = (r + 1) & ~1
        w = (r - l) // 2
        blob = [t, b - t + 1, l // 2, w]
        for y in range(t, b + 1):
            for xb in range(w):
                x = l + xb * 2
                hi = nearest(pal, T.bake_front(d, x, y))
                lo = nearest(pal, T.bake_front(d, x + 1, y))
                blob.append((hi << 4) | lo)
        blobs.append(blob)
    return blobs


def main():
    im = Image.open(SRC).convert("RGB")
    assert im.size == (256, 212), im.size

    idm, rgb = build_maps()

    # ---- 팔레트: 배경 UI 와 던전 벽돌을 한꺼번에 놓고 정한다 ----
    # SCREEN 5 는 화면 전체가 팔레트 하나를 공유하므로 따로 정할 수 없다.
    pool = Image.new("RGB", (256 * 212, 1))
    px = im.load()
    pix = []
    for y in range(212):
        for x in range(256):
            inside = (G.VIEW_X - 6 <= x < G.VIEW_X + G.VIEW_W + 6 and
                      G.VIEW_Y - 6 <= y < G.VIEW_Y + G.VIEW_H + 6)
            if not inside:
                pix.append(px[x, y])
    # 던전이 화면의 주인공이므로 구운 픽셀에 가중치를 준다
    dpix = [rgb[y][x] for y in range(G.VIEW_H) for x in range(G.VIEW_W)]
    for d in range(1, G.MAXD + 1):
        l, t, r, b = G.RECT[d]
        dpix += [T.bake_front(d, x, y) for y in range(t, b + 1, 2) for x in range(l, r, 2)]
    pix += dpix * 2
    pool = Image.new("RGB", (len(pix), 1))
    pool.putdata(pix)
    # 팔레트는 고정한다.
    #
    # 예전에는 여기서 중앙값 분할로 매번 다시 뽑았다. 그런데 배경 정본이 이미
    # 16색으로 정해진 그림이 되었으므로 그것을 다시 양자화하는 것은 자기를 근거로
    # 자기를 정하는 셈이다. 게다가 팔레트가 한 칸이라도 움직이면 배경 RLE 와 벽면
    # 픽셀이 전부 달라져 앞뒤 비교가 불가능해진다.
    #
    # 아래 값은 그때 뽑힌 결과 그대로다. 회색 여덟 단계가 다 들어 있어서 벽돌의
    # 명암과 옆길의 어둠을 표현하는 데 부족하지 않다.
    pal = [(7,7,6), (7,7,5), (7,6,5), (6,6,5), (5,5,5), (5,5,3), (4,4,4), (3,3,3),
           (2,2,2), (0,0,0), (1,1,1), (6,6,6), (7,7,7), (7,6,4), (5,4,5), (5,5,2)]
    _ = pix                                 # 표본은 이제 쓰지 않는다
    print("팔레트 16색 (RGB333):", " ".join("%d%d%d" % c for c in pal))
    BLACK = pal.index((0, 0, 0))

    # ---- 배경 ----
    idxbg = [[nearest(pal, px[x, y]) for x in range(256)] for y in range(212)]
    for y in range(G.VIEW_Y - 4, G.VIEW_Y + G.VIEW_H + 4):
        for x in range(G.VIEW_X - 4, G.VIEW_X + G.VIEW_W + 4):
            idxbg[y][x] = BLACK
    packed = bytearray()
    for y in range(212):
        for x in range(0, 256, 2):
            packed.append((idxbg[y][x] << 4) | idxbg[y][x + 1])
    comp = rle(bytes(packed))
    print("배경: 원본 %d -> RLE %d 바이트" % (len(packed), len(comp)))

    # ---- 런 + 구운 픽셀 ----
    runs, maxruns = build_runs(idm, rgb, pal)
    print("벽면 런+픽셀: %d 바이트 (한 줄 최대 %d 런)" % (len(runs), maxruns))

    fronts = build_front(pal)
    ftotal = sum(len(b) for b in fronts)
    print("정면 벽 %d 개: %d 바이트" % (len(fronts), ftotal))

    pb = []
    for r, g, b in pal:
        pb += [(r << 4) | b, g]

    consts = [
        "; gfx/quest_convert.py 가 생성한 파일입니다. 직접 고치지 마세요.",
        "",
        "VIEW_X       equ %d" % G.VIEW_X,
        "VIEW_Y       equ %d" % G.VIEW_Y,
        "VIEW_W       equ %d" % G.VIEW_W,
        "VIEW_H       equ %d" % G.VIEW_H,
        "MAXD         equ %d" % G.MAXD,
        "NSEG         equ %d" % G.NSEG,
        "CENTRE_ID    equ %d" % CENTRE_ID,
        "NUM_IDS      equ %d" % NUM_IDS,
        "",
        "; 면 상태",
        "VIS_TEX      equ %d" % VIS_TEX,
        "VIS_SKIP     equ %d" % VIS_SKIP,
        "VIS_BLACK    equ %d" % VIS_BLACK,
        "VIS_WALL2    equ %d" % VIS_WALL2,
        "VIS_OPEN2    equ %d" % VIS_OPEN2,
        "VIS_SKIP2    equ %d" % VIS_SKIP2,
        "",
        "COL_BLACK    equ %d" % BLACK,
        "COL_PANEL    equ %d" % nearest(pal, (182, 182, 182)),
        "COL_CREAM    equ %d" % nearest(pal, (255, 255, 219)),
        "COL_SHADE    equ %d" % nearest(pal, (146, 146, 146)),
        "BG_RLE_LEN   equ %d" % len(comp),
    ]
    open(os.path.join(ROOT, "src", "questconst.asm"), "w", encoding="utf-8").write(
        "\n".join(consts) + "\n")

    parts = ["; gfx/quest_convert.py 가 생성한 파일입니다. 직접 고치지 마세요.", ""]
    parts.append(db("PaletteData", pb))
    parts.append("")
    parts.append("; 스캔라인 런: 줄마다 (면번호, 바이트폭, 픽셀들) 이 이어지고")
    parts.append("; 폭 0 이면 줄 끝. 뷰포트 위에서 아래로 %d 줄이 연속으로 들어 있다." % G.VIEW_H)
    parts.append(db("RunData", runs))
    parts.append("")
    parts.append("; 정면 벽: 깊이 1..%d 각각 startY, 높이, xByte, 바이트폭, 픽셀" % G.MAXD)
    parts.append("FrontPtrs:")
    for d in range(1, G.MAXD + 1):
        parts.append("    dw Front%d" % d)
    for d, blob in enumerate(fronts, 1):
        parts.append(db("Front%d" % d, blob))
    parts.append("")
    parts.append("; 16x16 던전 맵. 1 = 벽, 0 = 통로. 인덱스는 (y<<4)|x 라 8비트로 끝난다.")
    flat = []
    for row in MAP:
        flat += [1 if c == '#' else 0 for c in row]
    parts.append(db("MapData", flat, per=16))
    parts.append("")
    parts.append(db("BgRle", list(comp)))
    parts.append("BgRleEnd:")
    open(os.path.join(ROOT, "src", "questdata.asm"), "w", encoding="utf-8").write(
        "\n".join(parts) + "\n")

    total = len(comp) + len(runs) + ftotal + 32 + 256
    print("wrote src/questconst.asm, src/questdata.asm")
    print("데이터 합계: %d 바이트" % total)


if __name__ == "__main__":
    main()
