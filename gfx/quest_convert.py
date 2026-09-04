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
from quest_pal import PAL333, COL_HERO, nearest as _nearest, to332
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

# --------------------------------------------------------------------------
# 화면 모드 - SCREEN 5 (4bpp) 인가 SCREEN 8 (8bpp) 인가
# --------------------------------------------------------------------------
# 굽는 기하와 런 구조는 두 모드가 똑같다. 다른 것은 **픽셀 하나가 몇 바이트인가**
# 뿐이라, 색을 바이트로 바꾸는 자리 한 곳(pack2)과 폭을 세는 자리 한 곳(BPB)만
# 갈라 두면 나머지는 그대로 돈다. 파일을 두 벌로 복사하지 않는 이유다.
#
#   SCREEN 5  한 바이트에 픽셀 둘. 팔레트 16색에 맞춰 양자화한다.
#   SCREEN 8  한 바이트에 픽셀 하나. 팔레트가 없고 색이 GRB332 로 못박혀 있어서
#             256색을 그대로 쓴다 - 양자화도 예약 색도 필요 없다.
BPP = 4
BPB = 1                     # 픽셀 두 개가 몇 바이트인가 (4bpp=1, 8bpp=2)


def set_bpp(bpp):
    global BPP, BPB
    assert bpp in (4, 8), bpp
    BPP, BPB = bpp, 1 if bpp == 4 else 2


def pack2(pal, c0, c1):
    """가로로 이웃한 픽셀 두 개 -> 바이트 목록. 모드에 따라 1 개나 2 개."""
    if BPP == 4:
        return [(nearest(pal, c0) << 4) | nearest(pal, c1)]
    return [to332(c0), to332(c1)]


def colval(pal_or_i, i=None):
    """팔레트 번호 -> 그 모드의 픽셀 값. 4bpp 는 번호, 8bpp 는 GRB332 값."""
    return pal_or_i if BPP == 4 else to332(to888(PAL333[pal_or_i]))


def fillbyte(i):
    """그 색으로 한 바이트를 채울 때 쓰는 값."""
    return colval(i) * 17 if BPP == 4 else colval(i)


def pack2i(pal, i0, i1):
    """팔레트 번호로 주어진 픽셀 두 개. 배경과 화살표처럼 이미 번호인 것에 쓴다."""
    if BPP == 4:
        return [(i0 << 4) | i1]
    return [to332(to888(pal[i0])), to332(to888(pal[i1]))]


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
    lines, maxruns = [], 0
    nblk_of, width_of = {}, {}
    for y in range(H):
        data = []
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
                    width_of.setdefault(fid, n * BPB)
                    assert width_of[fid] == n * BPB, (fid, width_of[fid], n)
            nblk = 1 + len(bakers)
            nblk_of.setdefault(fid, nblk)
            assert nblk_of[fid] == nblk, (fid, nblk_of[fid], nblk)

            data += [fid, n * BPB]
            for i in range(n):                      # 블록 0: 그 면의 그림 그대로
                x = (xb + i) * 2
                data += pack2(pal, rgb[y][x], rgb[y][x + 1])
            for baker in bakers:
                for i in range(n):
                    x = (xb + i) * 2
                    data += pack2(pal, baker(sid // 4, G.VIEW_X + x, G.VIEW_Y + y),
                                  baker(sid // 4, G.VIEW_X + x + 1, G.VIEW_Y + y))
            xb += n
        data += [0, 0]
        lines.append(data)
    return lines, maxruns, nblk_of, width_of


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
                blob += pack2i(pal, hi, lo)
        out.append(blob)
        rows = rot90(rows)
    return out


# --------------------------------------------------------------------------
# 런 자료를 8KB 뱅크로 나눈다
# --------------------------------------------------------------------------
# 본체(0x4000-0x9FFF, 뱅크 0~2)는 이미 꽉 찼는데 벽면 런만 12KB 다. 8bpp 로 가면
# 24KB 라 아예 안 들어간다. 그래서 런을 0xA000 창으로 내린다.
#
# 줄마다 **(뱅크, 주소)** 를 표에 적어 두고 줄머리에서 그것을 꺼내 쓴다. 뱅크
# 경계를 그때그때 검사하는 방법도 있지만, 그러려면 "한 줄이 뱅크에 안 걸친다"는
# 약속에다 "줄이 끝난 자리가 곧 다음 줄의 시작"이라는 약속까지 걸어야 한다.
# 남는 자리를 메우는 순간 두 번째 약속이 깨진다. 표는 96*3 = 288 바이트뿐이고
# 줄머리에서 40 T 밖에 안 드니(96 줄이면 1.1 ms) 약속을 안 거는 편이 낫다.
RUN_BANK0 = 7                                   # 3~4 그림, 5 배경, 6 정면 벽
BANK_SIZE = 8192
BANK_WIN = 0xA000


def bank_file(pre, kind, i, blob, note):
    """8KB 뱅크 하나를 감싸는 .asm 을 낸다. 뱅크 수가 모드와 자료 크기에 따라
    달라지므로 손으로 관리하지 않는다 - 한 번만 어긋나도 롬이 통째로 엉킨다."""
    # 번호에 0 을 채운다. 안 채우면 빌드 스크립트의 글자순 정렬이
    # 0,1,10,11,12,2,3.. 으로 붙여서 뱅크가 통째로 뒤섞인다. 실제로 타이틀
    # 그림이 13 뱅크가 되면서 밟았다.
    L = ["; gfx/quest_convert.py 가 생성한 파일입니다. 직접 고치지 마세요.",
         ";",
         "; %s (%d 바이트)" % (note, len(blob)),
         "",
         "    DEVICE NOSLOT64K",
         "",
         "    ORG 0x%04X" % BANK_WIN,
         db("", list(blob)),
         "",
         "    ds 0x%04X - $, 0xFF" % (BANK_WIN + BANK_SIZE),
         '    SAVEBIN "build/%s%s%02d.bin", 0x%04X, 0x%04X'
         % (pre, kind, i, BANK_WIN, BANK_SIZE)]
    open(os.path.join(ROOT, "src", "%s%s%02d.asm" % (pre, kind, i)), "w",
         encoding="utf-8").write("\n".join(L) + "\n")


def split_bg(packed):
    """배경 픽셀을 뱅크에 들어갈 만큼씩 잘라 각각 RLE 로 압축한다.

    RLE 를 통째로 한 뒤 자르면 자르는 자리가 레코드 한가운데일 수 있다. 픽셀
    쪽에서 자르면 그런 일이 없고, 뱅크마다 독립적으로 풀 수 있다 - 푸는 쪽은
    VRAM 주소를 이어서 쓰기만 하면 된다.
    """
    n = 1
    while True:
        step = -(-len(packed) // n)
        chunks = [rle(packed[i:i + step]) for i in range(0, len(packed), step)]
        if all(len(c) <= BANK_SIZE for c in chunks):
            return chunks
        n += 1


def pack_run_banks(lines):
    """줄 단위로 뱅크에 채운다. 한 줄이 뱅크에 걸치지 않게만 하면 된다 -
    줄 안에서는 포인터가 앞으로만 가므로 그 뒤로는 검사할 것이 없다."""
    banks, tab = [bytearray()], []
    for ln in lines:
        assert len(ln) <= BANK_SIZE, len(ln)
        if len(banks[-1]) + len(ln) > BANK_SIZE:
            banks.append(bytearray())
        tab.append((RUN_BANK0 + len(banks) - 1, BANK_WIN + len(banks[-1])))
        banks[-1] += bytes(ln)
    return banks, tab


# 정면 벽을 놓아 둘 화면 밖 VRAM 의 첫 줄. SCREEN 5 는 한 페이지가 256 줄이고
# 화면에 나오는 것은 212 줄뿐이라, 줄 256 부터는 페이지 1 로 아무도 안 쓴다.
# VDP 명령의 y 좌표는 10 비트(0~1023)라 거기까지 그대로 짚을 수 있다.
FRONT_VY = 256


def build_front(pal):
    """정면 벽. 픽셀을 **VRAM 에 미리 풀어 두고** 그릴 때는 VDP 에게 오려 붙이라고
    시킨다(HMMM).

    왜 이렇게 하나. 정면 벽은 깊이 1 일 때 73x73 = 5,329 픽셀로 뷰포트의 57.8%
    다. 화면에서 제일 큰 한 덩어리이고, 게다가 **사각형 하나**다. 사각형 하나는
    VDP 명령 하나로 끝나므로 런마다 명령을 보내야 하는 다른 면들과 사정이 다르다.
    잰 값으로 픽셀당 Z80 은 9.5 us, HMMM 은 4.6 us 라 깊이 1 에서 50 ms 가
    24 ms 로 준다.

    덤으로 이 픽셀은 부팅 때 한 번만 읽히므로 본체 뱅크에 있을 이유가 없다.

    돌려주는 것 셋
      pix   화면 밖 VRAM 에 그대로 올릴 픽셀. 깊이별로 세로로 쌓는다.
      cmds  깊이별 HMMM 명령 블록 (R#32 부터 SX,SY,DX,DY,NX,NY,CLR,ARG,CMD)
      up    올릴 때 쓰는 표 (바이트폭, 줄 수)
    """
    pix, cmds, up = [], [], []
    vy = FRONT_VY
    for d in range(1, G.MAXD + 1):
        l, t, r, b = G.RECT[d]
        l &= ~1
        r = (r + 1) & ~1
        w = r - l                       # 픽셀 폭 (짝수)
        bw = w // 2 * BPB               # 한 줄의 바이트 수
        h = b - t + 1
        for y in range(t, b + 1):
            for xb in range(w // 2):
                x = l + xb * 2
                pix += pack2(pal, T.bake_front(d, x, y),
                             T.bake_front(d, x + 1, y))
        cmds.append([0, 0, vy & 0xFF, vy >> 8,              # SX, SY
                     l & 0xFF, l >> 8, t & 0xFF, t >> 8,    # DX, DY
                     w & 0xFF, w >> 8, h & 0xFF, h >> 8,    # NX, NY
                     0, 0, 0xD0])                           # CLR, ARG, HMMM
        up.append([bw, h])
        vy += h
    assert vy <= 1024, vy                # 명령 y 좌표가 10 비트다
    return pix, cmds, up


def main(bpp=4):
    set_bpp(bpp)
    pre = "quest" if bpp == 4 else "quest8"
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
    # 4bpp 는 팔레트 16색에 맞춘다. 8bpp 는 팔레트가 없으니 그림 색을 그대로
    # GRB332 로 옮긴다 - 재 보니 RLE 가 8,780 에서 8,867 바이트로 87 바이트밖에
    # 안 늘었다. 이걸로 크림(0)과 흰색(12)이 GRB332 에서 겹치던 것도 없어진다.
    inside_view = lambda x, y: (G.VIEW_X - 4 <= x < G.VIEW_X + G.VIEW_W + 4 and
                                G.VIEW_Y - 4 <= y < G.VIEW_Y + G.VIEW_H + 4)
    packed = bytearray()
    if BPP == 8:
        for y in range(212):
            for x in range(256):
                packed.append(0 if inside_view(x, y) else to332(px[x, y]))
    else:
        idxbg = [[nearest(pal, px[x, y]) for x in range(256)] for y in range(212)]
        for y in range(212):
            for x in range(256):
                if inside_view(x, y):
                    idxbg[y][x] = BLACK
        for y in range(212):
            for x in range(0, 256, 2):
                packed += bytes(pack2i(pal, idxbg[y][x], idxbg[y][x + 1]))
    bgchunks = split_bg(bytes(packed))
    comp = b"".join(bgchunks)
    print("배경: 원본 %d -> RLE %d 바이트, 뱅크 %d 개"
          % (len(packed), len(comp), len(bgchunks)))

    # ---- 런 + 구운 픽셀 ----
    lines, maxruns, nblk_of, width_of = build_runs(idm, rgb, pal)
    runs = [b for ln in lines for b in ln]
    runbanks, runtab = pack_run_banks(lines)
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

    fpix, fcmds, fup = build_front(pal)
    frontbanks = [fpix[i:i + BANK_SIZE] for i in range(0, len(fpix), BANK_SIZE)]
    print("정면 벽 %d 개: 픽셀 %d 바이트(뱅크로 내려감) + 명령 %d 바이트"
          % (len(fcmds), len(fpix), len(fcmds) * 15))

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
        "; 색. 4bpp 는 팔레트 번호, 8bpp 는 GRB332 값 그대로다.",
        "; *_BYTE 는 그 색으로 한 바이트를 채울 때 쓰는 값 - 4bpp 는 같은 색",
        "; 픽셀 둘이라 17 을 곱하고, 8bpp 는 한 바이트가 한 픽셀이라 그대로다.",
        "COL_BLACK    equ %d" % colval(BLACK),
        "COL_PANEL    equ %d" % colval(nearest(pal, (182, 182, 182))),
        "COL_CREAM    equ %d" % colval(nearest(pal, (255, 255, 219))),
        "COL_SHADE    equ %d" % colval(nearest(pal, (146, 146, 146))),
        "COL_HERO     equ %d              ; 미니맵의 내 위치 (파랑)" % colval(COL_HERO),
        "BLACK_BYTE   equ %d" % fillbyte(BLACK),
        "CREAM_BYTE   equ %d" % fillbyte(nearest(pal, (255, 255, 219))),
        "SHADE_BYTE   equ %d" % fillbyte(nearest(pal, (146, 146, 146))),
        "",
        "; 화면 모드. 4bpp 는 한 바이트에 픽셀 둘, 8bpp 는 하나.",
        "BPP          equ %d" % BPP,
        "PXB          equ %d              ; 한 바이트에 든 픽셀 수" % (3 - BPB),
        "VIEW_XB      equ %d              ; 뷰포트 왼쪽의 바이트 위치"
        % (G.VIEW_X * BPB // 2),
        "VRAM_ROW     equ %d              ; 한 스캔라인의 VRAM 바이트 수"
        % (128 * BPB),
        "",
        "; 정면 벽 픽셀을 놓아 둘 화면 밖 VRAM 의 첫 줄.",
        ";",
        "; 깊이별 사각형을 **세로로 쌓아** 둔다 (UnpackFront). 그래서 차지하는",
        "; 줄 수는 FRONT_PIX_LEN/VRAM_ROW 가 아니다 - 폭이 FRONT_MAXW 뿐이라",
        "; 줄이 남고, 실제로는 그 다섯 배 가까이 쓴다. 화면 밖 VRAM 을 쓰는",
        "; 다른 자리는 FRONT_END_VY 아래에 두거나 x 를 FRONT_MAXW 뒤로 밀어야",
        "; 한다. 안 그러면 정면 벽 그림 위에 덮어써서 벽에 그 그림이 박힌다.",
        "FRONT_VY     equ %d" % FRONT_VY,
        "FRONT_PIX_LEN equ %d" % len(fpix),
        "FRONT_ROWS   equ %d                ; 깊이별 줄 수의 합" % sum(h for _, h in fup),
        "FRONT_MAXW   equ %d                ; 제일 넓은 깊이의 바이트 폭" % max(bw for bw, _ in fup),
        "FRONT_END_VY equ FRONT_VY + FRONT_ROWS",
        "",
        "; 뱅크 배치. 3 부터 그림 -> 배경 -> 정면 벽 -> 벽면 런 순서다.",
        "; 그림 뱅크 수가 모드마다 다르므로(SPR_BANKS) 숫자를 박지 않고 계산한다.",
        "; questrules.asm 을 questconst.asm 보다 **먼저** include 해야 한다.",
        "BG_BANKS     equ %d" % len(bgchunks),
        "FRONT_BANKS  equ %d" % len(frontbanks),
        "RUN_BANKS    equ %d" % len(runbanks),
        "BG_BANK      equ SPR_FIRSTBK + SPR_BANKS",
        "FRONT_BANK   equ BG_BANK + BG_BANKS",
        "RUN_BANK0    equ FRONT_BANK + FRONT_BANKS",
        "",
        "; 배경 RLE 는 뱅크마다 따로 압축했다. 뱅크별 길이.",
    ]
    for i, c in enumerate(bgchunks):
        consts.append("BG_LEN_%d     equ %d" % (i, len(c)))
    open(os.path.join(ROOT, "src", pre + "const.asm"), "w", encoding="utf-8").write(
        "\n".join(consts) + "\n")

    parts = ["; gfx/quest_convert.py 가 생성한 파일입니다. 직접 고치지 마세요.", ""]
    parts.append(db("PaletteData", pb))
    parts.append("")
    parts.append("; 스캔라인 런의 자리표. 줄마다 (뱅크, 주소 하위, 주소 상위).")
    parts.append("; 자료 자체는 뱅크 %d 부터에 있다(questrunbank*.asm)." % RUN_BANK0)
    parts.append("RunLineTab:")
    for bank, addr in runtab:
        parts.append("    db RUN_BANK0 + %d" % (bank - RUN_BANK0))
        parts.append("    dw 0x%04X" % addr)
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
    parts.append("; 정면 벽. 픽셀은 화면 밖 VRAM(줄 %d 아래)에 미리 풀어 두고," % FRONT_VY)
    parts.append("; 그릴 때는 이 HMMM 명령 하나로 오려 붙인다. 화면에서 제일 큰 한")
    parts.append("; 덩어리(깊이 1 이면 뷰포트의 57.8%)이고 사각형이라 명령 하나로 끝난다.")
    parts.append("FrontCmdPtr:")
    for d in range(1, G.MAXD + 1):
        parts.append("    dw FrontCmd%d" % d)
    for d, blk in enumerate(fcmds, 1):
        parts.append(db("FrontCmd%d" % d, blk, per=15))
    parts.append("")
    parts.append("; VRAM 에 올릴 때 쓰는 표: 깊이마다 바이트폭, 줄 수")
    parts.append(db("FrontUp", [v for pair in fup for v in pair], per=2))
    parts.append("")
    parts.append("; 배경 RLE 뱅크마다의 길이 (UnpackBg 가 순서대로 읽는다)")
    parts.append(db("BgChunkLen",
                    [v for c in bgchunks for v in (len(c) & 0xFF, len(c) >> 8)],
                    per=2))
    parts.append("")
    parts.append("; 16x16 던전 맵. 1 = 벽, 0 = 통로. 인덱스는 (y<<4)|x 라 8비트로 끝난다.")
    flat = []
    for row in MAP:
        flat += [1 if c == '#' else 0 for c in row]
    parts.append(db("MapData", flat, per=16))
    open(os.path.join(ROOT, "src", pre + "data.asm"), "w", encoding="utf-8").write(
        "\n".join(parts) + "\n")

    # 뱅크 셋. 감싸는 파일까지 전부 여기서 낸다 - 뱅크 수가 모드와 자료 크기에
    # 따라 달라져서 손으로 관리하면 반드시 어긋난다.
    for i, c in enumerate(bgchunks):
        bank_file(pre, "bgbank", i, c,
                  "배경 화면 RLE %d/%d" % (i + 1, len(bgchunks)))
    for i, c in enumerate(frontbanks):
        bank_file(pre, "frontbank", i, c,
                  "정면 벽 픽셀 %d/%d. 부팅 때 UnpackFront 가 화면 밖 VRAM"
                  "(줄 %d 아래)으로 옮긴다" % (i + 1, len(frontbanks), FRONT_VY))
    for i, blob in enumerate(runbanks):
        bank_file(pre, "runbank", i, blob,
                  "벽면 런 %d/%d. 줄마다 어느 뱅크 어디인지는 본체의"
                  " RunLineTab 에 있다" % (i + 1, len(runbanks)))

    total = len(runtab) * 3 + len(fcmds) * 15 + 32 + 256
    print("wrote src/%sconst.asm, src/%sdata.asm, 뱅크 파일 %d 개"
          % (pre, pre, len(bgchunks) + len(frontbanks) + len(runbanks)))
    print("본체 자료 %d 바이트 (런 표 %d 포함)" % (total, len(runtab) * 3))
    print("뱅크: 배경 %d 개(%d B) + 정면벽 %d 개(%d B) + 런 %d 개(%d B)"
          % (len(bgchunks), len(comp), len(frontbanks), len(fpix),
             len(runbanks), len(runs)))


if __name__ == "__main__":
    import sys
    bpp = 8 if "--bpp" in sys.argv and sys.argv[sys.argv.index("--bpp") + 1] == "8" else 4
    main(bpp)
