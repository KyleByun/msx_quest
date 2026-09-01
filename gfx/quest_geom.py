"""던전 뷰의 기하 구조를 정의하고 스캔라인 스팬으로 바꾼다.

Z80 렌더러가 쓸 것과 똑같은 계산을 여기서 하므로, 어셈블리를 쓰기 전에 화면이
어떻게 나올지 확인할 수 있다.

칸 단위 이동에 90도 회전만 있으므로 화면에 나오는 벽면의 모양은 서 있는 위치와
무관하게 언제나 같다. 즉 광선을 쏘아 얻을 결과가 상수라서, 빌드 시점에 한 번
풀어 두고 실행 중에는 "이 칸이 벽인가"만 본다.
"""

VIEW_X, VIEW_Y = 16, 8          # 뷰포트 좌상단 (MSX 화면 좌표)
VIEW_W, VIEW_H = 96, 96
CX = VIEW_X + VIEW_W // 2       # 소실점
CY = VIEW_Y + VIEW_H // 2

# 경계의 반폭. HALF[0] 은 화면 가장자리(근평면)이고 HALF[j] (j>=1) 는 눈에서
# j 칸 떨어진 평면이다.
#
# HALF[1] 을 화면 가장자리보다 안쪽에 두는 것이 중요하다. 둘이 같으면 바로 앞이
# 벽일 때 화면이 벽 색 하나로 꽉 차 버린다. 12 픽셀을 남겨 두면 내가 서 있는
# 칸의 바닥/천장/옆벽이 테두리처럼 보여서, 막다른 길에서도 화면이 읽힌다.
HALF = [48, 36, 18, 12, 9, 7]

NSEG = len(HALF) - 1            # 그릴 구간 수 (0 = 내가 선 칸, 1.. = 앞칸)
MAXD = NSEG - 1                 # 앞으로 볼 수 있는 칸 수

# 경계 사각형. 세로도 같은 비율로 줄여 통로가 정사각형으로 보이게 한다.
RECT = [(CX - h, CY - h, CX + h, CY + h) for h in HALF]


def lerp(a, b, t):
    return a + (b - a) * t


def quad_spans(*pts):
    """볼록 다각형을 스캔라인 스팬으로 바꾼다.

    좌우 벽은 기울어진 변이 위아래에 있고 천장/바닥은 좌우에 있다. 변을 미리
    정해 놓고 보간하면 한쪽만 맞으므로, 스캔라인마다 모든 변과의 교점을 구해
    최소/최대를 취하는 일반적인 방법을 쓴다.

    반환: [(y, x0, x1), ...]  x1 은 포함하지 않는 끝
    """
    ys = [p[1] for p in pts]
    out = []
    n = len(pts)
    for y in range(min(ys), max(ys) + 1):
        xs = []
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % n]
            if ay == by:
                if ay == y:
                    xs.extend([ax, bx])
                continue
            lo, hi = (ay, by) if ay < by else (by, ay)
            if lo <= y <= hi:
                xs.append(lerp(ax, bx, (y - ay) / (by - ay)))
        if not xs:
            continue
        x0, x1 = int(round(min(xs))), int(round(max(xs)))
        if x1 > x0:
            out.append((y, x0, x1))
    return out


def segment_quads(j):
    """구간 j 의 천장/바닥/좌벽/우벽.

    구간 j 는 경계 RECT[j] 와 RECT[j+1] 사이이고, 눈에서 j 칸 떨어진 칸에
    해당한다. j = 0 이면 내가 서 있는 칸이다.
    """
    nl, nt, nr, nb = RECT[j]            # 가까운 쪽
    fl, ft, fr, fb = RECT[j + 1]        # 먼 쪽
    return {
        "ceil":  quad_spans((nl, nt), (nr, nt), (fr, ft), (fl, ft)),
        "floor": quad_spans((fl, fb), (fr, fb), (nr, nb), (nl, nb)),
        "left":  quad_spans((nl, nt), (fl, ft), (fl, fb), (nl, nb)),
        "right": quad_spans((fr, ft), (nr, nt), (nr, nb), (fr, fb)),
    }


def front_rect(d):
    """d 칸 앞이 벽일 때 보이는 정면. 그 칸의 앞면인 RECT[d] 사각형이다."""
    l, t, r, b = RECT[d]
    return [(y, l, r) for y in range(t, b + 1)]


# --- 옆면을 지나간 광선이 평면 z=k 에서 어느 칸에 있는가 -------------------
#
# 구간 j 의 옆면을 채우는 광선은 화면 중심에서 dx = HALF[j+1] .. HALF[j] 만큼
# 떨어져 있고 기울기가 s = dx/P 다. 평면 z=k 에서의 옆방향 위치는 s*k 이므로
# 그 범위는 [HALF[j+1]*k/P, HALF[j]*k/P] 다. 칸 m 이 [m-0.5, m+0.5] 를 차지하니
# 가운데 값을 반올림하면 그 평면에서 볼 칸이 나온다.
#
# 손으로 적지 않고 여기서 뽑는 이유는, 범위가 칸 경계에 걸치는 자리가 있어서다
# (j=0,k=3 은 정확히 1.5 에서 시작하고 j=1,k=4 는 1.0~2.0 으로 두 칸에 걸친다).
# 한 면 안에서도 픽셀마다 답이 다른데 면 하나에 칸 하나를 고르는 근사다.
P = 72.0


def lateral_at(j, k):
    """구간 j 의 옆면 광선이 평면 z=k 에서 지나는 칸 (옆으로 몇 칸)."""
    near = HALF[j + 1] * k / P
    far = HALF[j] * k / P
    return max(1, int(round((near + far) / 2.0)))


# LATERAL[j][k] - k 는 j+1 부터 NSEG 까지만 뜻이 있다
LATERAL = [[lateral_at(j, k) if j < k <= NSEG else 0 for k in range(NSEG + 1)]
           for j in range(NSEG)]


if __name__ == "__main__":
    print("뷰포트 (%d,%d) %dx%d  소실점 (%d,%d)" % (VIEW_X, VIEW_Y, VIEW_W, VIEW_H, CX, CY))
    print("구간 %d 개 (0 = 내가 선 칸), 앞으로 %d 칸까지 보인다" % (NSEG, MAXD))
    for j, r in enumerate(RECT):
        tag = "근평면" if j == 0 else "z=%d" % j
        print("  경계 %d (%-6s): x %3d..%3d  y %3d..%3d  반폭 %2d"
              % (j, tag, r[0], r[2], r[1], r[3], HALF[j]))
