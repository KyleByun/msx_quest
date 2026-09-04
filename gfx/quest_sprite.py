"""몬스터 그림을 SCREEN 5 스프라이트로 굽는다.

원본은 D:/my/python/dnd/images 의 64x64 RGBA 다. 배경이 투명이라 그대로 사각형을
찍으면 던전 그림을 가린다. 그래서 줄마다 "건너뛸 바이트 / 그릴 바이트 / 픽셀"
형태로 접어 두고, 투명한 곳은 아예 건드리지 않는다. 벽면을 스캔라인 런으로 그린
것과 같은 방식이다.

한 바이트에 픽셀이 둘 들어가는데 그 둘의 투명 여부가 다를 수 있다. 그런 자리는
읽고-고치고-쓰기를 해야 해서 비싸다. 여기서는 **바이트 단위로 반올림**한다.
둘 중 하나라도 불투명하면 그 바이트를 그리고, 투명한 쪽은 옆 픽셀 색으로 채운다.
가장자리에 한 픽셀 테두리가 생기지만 이 크기에서는 보이지 않는다.
"""
import io
import os
from PIL import Image
import quest_geom as G
from quest_pal import to332

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = r"D:\my\python\dnd\images"
CACHE = os.path.join(HERE, "sprites")       # 원본이 없어질 때를 대비해 남긴다

# 그림을 화면에 얼마나 크게 찍는가. 원본은 64x64 뿐이라 여기서 키운다고 자세해
# 지지는 않지만, 던전 뷰포트가 96x96 이라 96 이면 화면을 꽉 채운다. 투명한 곳은
# 아예 안 그리므로 배경(던전)은 그대로 보인다.
#
# SCREEN 8 로 가면서 올렸다. 4bpp 에서는 64x64 여도 8,338 바이트라 뱅크 두 개를
# 썼는데, 8bpp 96x96 은 31,057 바이트로 네 개다. 그럴 자리가 생겼기 때문이다.
W = H = 64
BPP = 4
PRE = "quest"                   # 결과 파일 이름 앞머리 (8bpp 면 "quest8")

# 원본 크기. 여기서 W x H 로 늘려 쓴다.
SRC_W = SRC_H = 64


def set_mode(bpp, size, pre):
    global BPP, W, H, PRE
    assert bpp in (4, 8), bpp
    BPP, W, H, PRE = bpp, size, size, pre

# 그림 -> (표시 이름, 무리 최대). 수치는 quest_rules.py 가 monster.json 에서 준다.
#
# 무리 최대가 왜 여기까지 오는가: 두 마리가 길을 막으면 화면에 두 마리를 나란히
# 놓아야 하고, 그러려면 한 마리를 절반 폭으로 줄인 그림이 있어야 한다. 줄이는
# 것은 실행 중에 하지 않고 **여기서 미리 굽는다** - 원본이 64x64 라 여기서
# 줄이면 LANCZOS 로 곱게 줄고, Z80 은 그리기만 하면 된다.
SPRITES = [
    ("02_goblin.png", "GOBLIN", 4),
    ("03_slime.png", "SLIME", 1),
    ("04_dwarf.png", "DWARF", 4),
    ("06_troll.png", "TROLL", 1),
    ("23_cobra.png", "COBRA", 4),
    ("41_mimic.png", "MIMIC", 1),
]

ALPHA_MIN = 128         # 이보다 흐리면 투명으로 본다


def load(name):
    """원본에서 읽고 프로젝트 안에도 남긴다. 저장은 늘 원본 크기(64x64)로 한다."""
    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)
    kept = os.path.join(CACHE, name)
    src = os.path.join(SRC, name)
    if os.path.exists(src):
        im = Image.open(src).convert("RGBA")
        im.save(kept)
    else:
        im = Image.open(kept).convert("RGBA")
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    return im


def to_runs_linear(im, pal, nearest):
    """줄마다 (건너뛰기, 길이, 픽셀...) 을 이어 붙이고 0xFF 로 줄을 끝낸다.

    건너뛰기는 "직전 런이 끝난 자리부터" 센다. 그래야 실행할 때 포인터를 더하기만
    하면 되고 줄 머리를 따로 기억하지 않아도 된다.
    """
    px = im.load()
    data = []
    nb = W // 2 if BPP == 4 else W       # 한 줄의 바이트 수
    for y in range(H):
        opaque = []
        colour = []
        if BPP == 8:
            # 8bpp 는 한 바이트가 한 픽셀이라 반올림이 없다. 투명한 픽셀은
            # 정말로 건드리지 않으므로 가장자리 테두리도 안 생긴다.
            for x in range(W):
                on = px[x, y][3] >= ALPHA_MIN
                opaque.append(on)
                colour.append(to332(px[x, y][:3]) if on else 0)
        else:
            for xb in range(W // 2):
                x = xb * 2
                a0, a1 = px[x, y][3], px[x + 1, y][3]
                on = a0 >= ALPHA_MIN or a1 >= ALPHA_MIN
                opaque.append(on)
                if not on:
                    colour.append(0)
                    continue
                c0 = px[x, y][:3] if a0 >= ALPHA_MIN else px[x + 1, y][:3]
                c1 = px[x + 1, y][:3] if a1 >= ALPHA_MIN else px[x, y][:3]
                colour.append((nearest(pal, c0) << 4) | nearest(pal, c1))

        xb = 0
        prev_end = 0
        while xb < nb:
            while xb < nb and not opaque[xb]:
                xb += 1
            if xb >= nb:
                break
            start = xb
            while xb < nb and opaque[xb]:
                xb += 1
            run = xb - start
            while run > 254:                    # 한 런은 254 바이트까지
                data += [start - prev_end, 254] + colour[start:start + 254]
                prev_end = start + 254
                start += 254
                run -= 254
            data += [start - prev_end, run] + colour[start:start + run]
            prev_end = start + run
        data.append(0xFF)                       # 줄 끝
    return data


BANK_SIZE = 0x2000              # ASCII8 뱅크 하나
BANK_BASE = 0xA000              # 실행 중에 걸리는 자리
FIRST_BANK = 3                  # 0~2 는 본체 코드와 자료


def sizes_for(grp, full):
    """이 종류에게 필요한 그림 크기들. 큰 것부터.

    4bpp(SCREEN 5)는 대열을 안 쓰므로 원래 크기 하나뿐이다. 한 바이트에 픽셀이
    둘이라 폭이 홀수 바이트가 되는 크기가 생기기도 한다.
    """
    if BPP != 8:
        return [full]
    return sorted({G.mon_layout(n)[2] for n in range(1, grp + 1)}, reverse=True)


def build_banks(pal, nearest):
    """그림을 8KB 뱅크에 나눠 담는다.

    한 장이 뱅크 경계를 넘으면 그리다가 뱅크를 바꿔야 해서 복잡해진다. 그래서
    들어갈 만큼만 담고 넘치면 다음 뱅크로 통째로 넘긴다.

    종류마다 **1..무리최대 마릿수의 축소본**을 함께 굽는다. n 마리가 나오면
    한 마리를 W/n 폭으로 그려 나란히 놓는다. 실측으로 늘어나는 것은 6,849
    바이트뿐이다 - 축소본은 픽셀이 1/n^2 이고, 무리로 나오는 종류는 여섯 중
    셋(고블린/드워프/코브라)뿐이라서다.

    4bpp(SCREEN 5)는 대열을 쓰지 않으므로 원래 크기 하나만 굽는다. 한 바이트에
    픽셀이 둘이라 W/3 = 21.3 처럼 바이트로 안 떨어지는 크기가 생긴다.

    돌려주는 것: (뱅크별 asm 줄 목록, 상수 줄 목록)
    """
    global W, H
    full = W
    blobs = []                  # (라벨, 자료, 몬스터 번호, 크기)
    for i, (f, name, grp) in enumerate(SPRITES):
        for size in sizes_for(grp, full):
            W = H = size
            im = load(f)
            assert im.size == (W, H), (f, im.size)
            blobs.append(("Spr%s%d" % (name.capitalize(), size),
                          to_runs_linear(im, pal, nearest), i, size))
    W = H = full

    # 칼질 자국도 여기에 함께 담는다. 그림이라 스프라이트 뱅크가 제 자리고,
    # **뱅크 사슬을 안 건드려도 된다** - BG_BANK 부터가 SPR_BANKS 로부터
    # 이어지므로 여기서 뱅크가 하나 늘면 뒤가 저절로 밀린다.
    slash = []                  # (라벨, 자료, 크기, 몇 번째 장)
    if BPP == 8:
        import quest_slash as SL
        for size in sorted({G.mon_layout(n)[2] for n in range(1, 6)},
                           reverse=True):
            W = H = size
            for k, im in enumerate(SL.frames(size)):
                slash.append(("SlashW%dF%d" % (size, k),
                              to_runs_linear(im, pal, nearest), size, k))
        W = H = full

    banks = [[]]
    used = [0]
    place = {}                  # (몬스터 번호, 크기) -> (뱅크 번호, 주소)
    splace = {}                 # (크기, 장) -> (뱅크 번호, 주소)
    for label, data, i, size in blobs:
        if used[-1] + len(data) > BANK_SIZE:
            banks.append([])
            used.append(0)
        bi = len(banks) - 1
        place[(i, size)] = (FIRST_BANK + bi, BANK_BASE + used[bi])
        banks[bi].append("%s:                ; %s 를 %d 픽셀로  %d 바이트"
                         % (label, SPRITES[i][1], size, len(data)))
        for k in range(0, len(data), 16):
            banks[bi].append("    db " + ", ".join("0x%02X" % b for b in data[k:k + 16]))
        used[bi] += len(data)

    for label, data, size, k in slash:
        if used[-1] + len(data) > BANK_SIZE:
            banks.append([])
            used.append(0)
        bi = len(banks) - 1
        splace[(size, k)] = (FIRST_BANK + bi, BANK_BASE + used[bi])
        banks[bi].append("%s:                ; 칼질 %d 픽셀 %d 번째  %d 바이트"
                         % (label, size, k, len(data)))
        for j in range(0, len(data), 16):
            banks[bi].append("    db " + ", ".join("0x%02X" % b for b in data[j:j + 16]))
        used[bi] += len(data)

    for bi in range(len(banks)):
        banks[bi].append("    ds %d - ($ - 0x%04X), 0" % (BANK_SIZE, BANK_BASE))
        banks[bi].append('    SAVEBIN "build/%sspr%d.bin", 0x%04X, %d'
                         % (PRE, bi, BANK_BASE, BANK_SIZE))

    consts = ["SPR_W        equ %d" % full,
              "SPR_H        equ %d" % full,
              "SPR_BANKS    equ %d" % len(banks),
              "SPR_FIRSTBK  equ %d" % FIRST_BANK]
    for (i, size), (bk, ad) in sorted(place.items()):
        consts.append("SPR_BANK_%d_W%d equ %d                  ; %s %dpx"
                      % (i, size, bk, SPRITES[i][1], size))
        consts.append("SPR_ADDR_%d_W%d equ 0x%04X" % (i, size, ad))
    if splace:
        consts.append("SLASH_N      equ %d                  ; 칼질 자국 장 수"
                      % len({k for _s, k in splace}))
    for (size, k), (bk, ad) in sorted(splace.items()):
        consts.append("SLASH_BANK_W%d_F%d equ %d" % (size, k, bk))
        consts.append("SLASH_ADDR_W%d_F%d equ 0x%04X" % (size, k, ad))
    for bi in range(len(banks)):
        consts.append("; 뱅크 %d: %d / %d 바이트" % (FIRST_BANK + bi, used[bi], BANK_SIZE))
    return banks, consts


if __name__ == "__main__":
    print("이 파일은 quest_rules.py 가 불러 쓴다. 직접 실행하지 않는다.")
