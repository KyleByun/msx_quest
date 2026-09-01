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
from quest_pal import PAL333, COL_HERO, nearest as _nearest
from quest_map import MAP

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# 참고 스크린샷 그대로의 배경. 원래는 OneDrive 의 원본을 매번 읽었는데 그 파일이
# 사라지면 빌드가 통째로 멈춘다. 이미 16색으로 정한 결과를 프로젝트 안에 정본으로
# 넣어 두었다. 256x212 이고 팔레트에 있는 색만 쓴다.
SRC = os.path.join(HERE, "quest_bg.png")

# 굽기용 면 번호(build_maps 안에서만 쓴다): j*4 + {0=천장,1=바닥,2=좌,3=우}
GEOM_CENTRE = G.NSEG * 4


def geom_is_side(sid):
    return sid != GEOM_CENTRE and (sid % 4) >= 2


# --------------------------------------------------------------------------
# 런에 붙는 면 번호
# --------------------------------------------------------------------------
# 옆면은 광선이 그 자리를 지나 **어느 평면에서 벽을 만나는가**에 따라 그림이
# 달라진다. 만날 수 있는 평면은 z = j+1 부터 z = NSEG 까지다. 그래서 옆면 런은
# 블록을 이렇게 갖는다.
#
#   블록 0        옆칸이 벽             -> 비스듬한 벽면
#   블록 1..K-j   평면 k 에서 만남      -> bake_front(k)   (k = j+1..K)
#   마지막 블록   끝까지 안 만남        -> 바닥/천장만 이어진다
#
# 여기서 K 는 **그 스캔라인에서 벽면이 보일 수 있는 가장 깊은 평면**이다. 평면
# z=k 의 벽은 화면에서 |dy| < HALF[k] 안에만 보이므로, 소실선에서 멀어질수록 K 가
# 작아지고 블록도 줄어든다. |dy| >= HALF[j+1] 인 줄은 블록이 둘뿐이다.
#
# 런은 이미 스캔라인 단위이고 이 띠 경계는 가로선이므로, **런을 쪼갤 필요 없이
# 면 번호만 띠마다 다르게 주면 된다.** 그러면 블록 수가 면 번호로 정해져서
# 렌더러가 실행 중에 셀 것이 없다.
#
#   0 .. 2N-1     구간 j 의 천장(j*2), 바닥(j*2+1)      단일 블록
#   2N            한가운데                              단일 블록
#   2N+1 .. 2N+10 좌우 벽의 '띠 바깥' (f = j*2+side)    블록 2 개
#   그 뒤         좌우 벽의 '띠 안' (f, K)              블록 2 + (K-j) 개
#
# f 마다 띠 안 번호가 K = j+1..NSEG 순으로 이어져 있어서, 어셈블리 쪽에서 시작
# 번호 하나와 K 를 세는 것만으로 전부 짚을 수 있다.
NFACE = G.NSEG * 2                              # 좌우 벽 면의 개수
CENTRE_ID = G.NSEG * 2
OUTER0 = CENTRE_ID + 1                          # 띠 바깥 번호의 시작
BAND0 = OUTER0 + NFACE                          # 띠 안 번호의 시작

BAND_BASE = []
_acc = 0
for _f in range(NFACE):
    BAND_BASE.append(_acc)
    _acc += G.NSEG - (_f // 2)                  # K = j+1..NSEG
NUM_IDS = BAND0 + _acc


def band_id(f, K):
    j = f // 2
    return BAND0 + BAND_BASE[f] + (K - j - 1)


def kmax_at(y):
    """스캔라인 y(화면 좌표)에서 벽면이 보일 수 있는 가장 깊은 평면."""
    dy = abs(y - G.CY)
    best = 0
    for k in range(1, G.NSEG + 1):
        if G.HALF[k] > dy:
            best = k
    return best


# 면 상태 (실행 중에 정해진다). 번호가 곧 분기 순서다.
VIS_TEX = 0         # 단일 블록, 그리기 (가장 흔하므로 0 - 분기가 제일 짧다)
VIS_SKIP = 1        # 단일 블록, 건너뛰기 (정면 벽에 가려짐)
VIS_BLACK = 2       # 단일 블록, 검정으로 채우기 (통로 끝의 어둠)
VIS_WALL2 = 3       # 두 블록, 앞을 그리고 뒤를 건너뛴다 (띠 바깥, 옆칸이 벽)
VIS_GAP2 = 4        # 두 블록, 앞을 건너뛰고 뒤를 그린다 (띠 바깥, 뚫림)
VIS_SKIP2 = 5       # 두 블록, 둘 다 건너뛴다
VIS_SKIPN = 6       # n 블록, 전부 건너뛴다 (총 바이트 수는 VisPost 에)
VIS_OFS = 7         # 이 값부터: (값 - VIS_OFS) 바이트를 건너뛰고 그린다.
                    # 그린 뒤 남은 바이트 수는 VisPost 에 있다.


def to888(c):
    return tuple(round(v * 255 / 7) for v in c)


def snap333(c):
    return tuple(round(v * 7 / 255) for v in c)


# 양자화는 quest_pal 이 맡는다. UI 전용 자리(파랑)를 후보에서 빼야 하는데,
# 같은 규칙을 두 군데 적어 두면 한쪽만 틀어진다.
nearest = _nearest


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
    idm = [[GEOM_CENTRE] * W for _ in range(H)]
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
    블록이라도 폭만큼 포인터를 밀면 되므로 별도 색인이 필요 없다.

    옆면 런은 블록이 여러 개다(위의 면 번호 설명 참고). 몇 개인지는 면 번호로
    정해지므로 렌더러가 셀 것이 없다 - 다만 그 약속이 깨지면 포인터가 통째로
    어긋나므로 여기서 면 번호마다 블록 수와 폭이 하나뿐인지 확인한다.
    """
    W, H = G.VIEW_W, G.VIEW_H
    data, maxruns = [], 0
    nblk_of, width_of = {}, {}
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
        K = kmax_at(G.VIEW_Y + y)
        xb = 0
        for sid, n in runs:
            if sid == GEOM_CENTRE:
                fid, bakers = CENTRE_ID, []
            elif not geom_is_side(sid):
                fid, bakers = (sid // 4) * 2 + (sid % 4), []
            else:
                j, f = sid // 4, (sid // 4) * 2 + (sid % 4 - 2)
                if K <= j:                          # 띠 바깥 - 벽 아니면 뚫림뿐
                    fid = OUTER0 + f
                    bakers = [T.bake_side_open]
                else:
                    fid = band_id(f, K)
                    bakers = [(lambda k: lambda jj, x, yy: T.bake_front(k, x, yy))(k)
                              for k in range(j + 1, K + 1)] + [T.bake_side_open]
                    width_of.setdefault(fid, n)
                    assert width_of[fid] == n, (fid, width_of[fid], n)
            nblk = 1 + len(bakers)
            nblk_of.setdefault(fid, nblk)
            assert nblk_of[fid] == nblk, (fid, nblk_of[fid], nblk)

            data += [fid, n]
            for i in range(n):                      # 블록 0: 그 면의 그림 그대로
                x = (xb + i) * 2
                hi = nearest(pal, rgb[y][x])
                lo = nearest(pal, rgb[y][x + 1])
                data.append((hi << 4) | lo)
            for baker in bakers:
                for i in range(n):
                    x = (xb + i) * 2
                    hi = nearest(pal, baker(sid // 4, G.VIEW_X + x, G.VIEW_Y + y))
                    lo = nearest(pal, baker(sid // 4, G.VIEW_X + x + 1, G.VIEW_Y + y))
                    data.append((hi << 4) | lo)
            xb += n
        data += [0, 0]
    return data, maxruns, nblk_of, width_of


# --------------------------------------------------------------------------
# 미니맵의 내 위치 - 바라보는 방향 화살표
# --------------------------------------------------------------------------
# 지도 한 칸이 6x6 픽셀이다. 그 칸에 바로 화살표를 그리면 위치와 방향이 한 번에
# 읽힌다(지도 구석에 나침반을 따로 두면 눈을 두 군데로 옮겨야 한다).
#
# 북쪽 모양 하나만 적고 나머지는 돌려서 만든다. 손으로 네 벌을 적으면 한 벌만
# 틀려도 모르고 지나간다 - 실제로 예전 나침반 표가 그렇게 틀어져 있었다.
# 6x6 는 화살표를 그리기에 아주 좁다. 대여섯 가지를 실제 크기로 그려 놓고 보니,
# 꼬리를 V 로 판 화살촉이 방향이 제일 잘 읽혔다. 막대(줄기)를 붙이면 십자로
# 보이고, 그냥 삼각형이면 덩어리로 보인다.
ARROW_N = ["..XX..",
           ".XXXX.",
           "XXXXXX",
           "XXXXXX",
           "XX..XX",
           "X....X"]


def rot90(rows):
    n = len(rows)
    return ["".join(rows[n - 1 - x][y] for x in range(n)) for y in range(n)]


def arrow_patterns(pal):
    """방향(북동남서)별 6x6 패턴. 한 줄이 3바이트(픽셀 두 개가 한 바이트)."""
    black = pal.index((0, 0, 0))
    out, rows = [], ARROW_N
    for _ in range(4):                       # 북 -> 동 -> 남 -> 서
        blob = []
        for r in rows:
            for xb in range(0, 6, 2):
                hi = COL_HERO if r[xb] == 'X' else black
                lo = COL_HERO if r[xb + 1] == 'X' else black
                blob.append((hi << 4) | lo)
        out.append(blob)
        rows = rot90(rows)
    return out


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
    pal = PAL333                            # gfx/quest_pal.py 가 정본이다
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
    runs, maxruns, nblk_of, width_of = build_runs(idm, rgb, pal)
    assert len(width_of) == NFACE * 0 + len(set(width_of)), width_of
    print("벽면 런+픽셀: %d 바이트 (한 줄 최대 %d 런, 면 번호 %d 개)"
          % (len(runs), maxruns, NUM_IDS))
    # 면마다 띠 안 폭이 하나로 정해져야 한다. 그래야 "블록 n 개만큼 건너뛰기"가
    # 곱셈 없이 상수 오프셋이 되고, 렌더러가 세는 일 없이 더하기 한 번으로 끝난다.
    sw = []
    for f in range(NFACE):
        ids = [band_id(f, K) for K in range(f // 2 + 1, G.NSEG + 1)]
        ws = {width_of[i] for i in ids if i in width_of}
        assert len(ws) == 1, (f, ws)
        sw.append(ws.pop())
    print("면별 띠 안 폭:", sw)

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
        "OUTER0       equ %d              ; 옆면 '띠 바깥' 번호의 시작" % OUTER0,
        "BAND0        equ %d              ; 옆면 '띠 안' 번호의 시작" % BAND0,
        "",
        "; 면 상태",
        "VIS_TEX      equ %d" % VIS_TEX,
        "VIS_SKIP     equ %d" % VIS_SKIP,
        "VIS_BLACK    equ %d" % VIS_BLACK,
        "VIS_WALL2    equ %d" % VIS_WALL2,
        "VIS_GAP2     equ %d" % VIS_GAP2,
        "VIS_SKIP2    equ %d" % VIS_SKIP2,
        "VIS_SKIPN    equ %d" % VIS_SKIPN,
        "VIS_OFS      equ %d" % VIS_OFS,
        "",
        "COL_BLACK    equ %d" % BLACK,
        "COL_PANEL    equ %d" % nearest(pal, (182, 182, 182)),
        "COL_CREAM    equ %d" % nearest(pal, (255, 255, 219)),
        "COL_SHADE    equ %d" % nearest(pal, (146, 146, 146)),
        "COL_HERO     equ %d              ; 미니맵의 내 위치 (파랑)" % COL_HERO,
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
    parts.append("; 미니맵의 내 위치 화살표. 방향(북동남서)별 6x6, 한 줄 3바이트.")
    arrows = arrow_patterns(pal)
    parts.append("HeroArrowPtr:")
    for i, name in enumerate(("N", "E", "S", "W")):
        parts.append("    dw HeroArrow%s" % name)
    for name, blob in zip(("N", "E", "S", "W"), arrows):
        parts.append(db("HeroArrow%s" % name, blob, per=3))
    parts.append("")
    parts.append("; 옆면 표. f = j*2 + 쪽(0=왼쪽, 1=오른쪽), f = 0..%d" % (NFACE - 1))
    parts.append("; BuildVisibility 가 이것만으로 그 면의 띠 번호를 전부 짚는다.")
    parts.append(db("SideBandBase", [band_id(f, f // 2 + 1) for f in range(NFACE)], per=10))
    parts.append(db("SideBandCnt", [G.NSEG - f // 2 for f in range(NFACE)], per=10))
    parts.append(db("SideWidth", sw, per=10))
    parts.append("")
    parts.append("; 구간 j 의 옆면 광선이 평면 z=k 에서 지나는 칸. 색인 j*%d+k."
                 % (G.NSEG + 1))
    parts.append(db("LatTab", [G.LATERAL[j][k] for j in range(G.NSEG)
                               for k in range(G.NSEG + 1)], per=G.NSEG + 1))
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
    open(os.path.join(ROOT, "src", "questdata.asm"), "w", encoding="utf-8").write(
        "\n".join(parts) + "\n")

    # 배경은 따로 낸다. quest.rom 은 이것을 8KB 뱅크 하나에 통째로 넣어 0xA000
    # 창으로 불러 쓰고(questbgbank.asm), quest2.rom 은 본체 안에 그냥 넣는다.
    # 벽면 자료가 블록 셋으로 늘면서 본체 뱅크(0x4000-0x9FFF)가 꽉 찼기 때문이다.
    bg = ["; gfx/quest_convert.py 가 생성한 파일입니다. 직접 고치지 마세요.", "",
          "; 배경 화면 RLE %d 바이트. 끝은 BgRleEnd 대신 BG_RLE_LEN 으로도 잰다" % len(comp),
          "; (뱅크에 놓으면 링크 시점에 주소를 알 수 없다).",
          db("BgRle", list(comp)), "BgRleEnd:"]
    open(os.path.join(ROOT, "src", "questbg.asm"), "w", encoding="utf-8").write(
        "\n".join(bg) + "\n")

    total = len(runs) + ftotal + 32 + 256
    print("wrote src/questconst.asm, src/questdata.asm, src/questbg.asm")
    print("본체 뱅크 자료 %d 바이트 + 배경 뱅크 %d 바이트" % (total, len(comp)))


if __name__ == "__main__":
    main()
