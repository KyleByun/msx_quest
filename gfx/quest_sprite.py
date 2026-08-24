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

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = r"D:\my\python\dnd\images"
CACHE = os.path.join(HERE, "sprites")       # 원본이 없어질 때를 대비해 남긴다

W = H = 64

# 그림 -> 표시 이름. 수치는 quest_rules.py 가 monster_stats.py 에서 가져온다.
SPRITES = [
    ("02_goblin.png", "GOBLIN"),
    ("03_slime.png", "SLIME"),
    ("04_dwarf.png", "DWARF"),
    ("06_troll.png", "TROLL"),
    ("23_cobra.png", "COBRA"),
    ("41_mimic.png", "MIMIC"),
]

ALPHA_MIN = 128         # 이보다 흐리면 투명으로 본다


def load(name):
    """원본에서 읽고 프로젝트 안에도 남긴다."""
    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)
    kept = os.path.join(CACHE, name)
    src = os.path.join(SRC, name)
    if os.path.exists(src):
        im = Image.open(src).convert("RGBA")
        im.save(kept)
        return im
    return Image.open(kept).convert("RGBA")


def to_runs_linear(im, pal, nearest):
    """줄마다 (건너뛰기, 길이, 픽셀...) 을 이어 붙이고 0xFF 로 줄을 끝낸다.

    건너뛰기는 "직전 런이 끝난 자리부터" 센다. 그래야 실행할 때 포인터를 더하기만
    하면 되고 줄 머리를 따로 기억하지 않아도 된다.
    """
    px = im.load()
    data = []
    for y in range(H):
        opaque = []
        colour = []
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
        while xb < W // 2:
            while xb < W // 2 and not opaque[xb]:
                xb += 1
            if xb >= W // 2:
                break
            start = xb
            while xb < W // 2 and opaque[xb]:
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


def build_banks(pal, nearest):
    """그림을 8KB 뱅크에 나눠 담는다.

    한 장이 뱅크 경계를 넘으면 그리다가 뱅크를 바꿔야 해서 복잡해진다. 그래서
    들어갈 만큼만 담고 넘치면 다음 뱅크로 통째로 넘긴다.

    돌려주는 것: (뱅크별 asm 줄 목록, 상수 줄 목록)
    """
    blobs = []
    for f, name in SPRITES:
        im = load(f)
        assert im.size == (W, H), (f, im.size)
        blobs.append((name, to_runs_linear(im, pal, nearest)))

    banks = [[]]
    used = [0]
    place = []                  # (뱅크 번호, 주소)
    for name, data in blobs:
        if used[-1] + len(data) > BANK_SIZE:
            banks.append([])
            used.append(0)
        bi = len(banks) - 1
        place.append((FIRST_BANK + bi, BANK_BASE + used[bi]))
        banks[bi].append("Spr%s:                ; %s  %d 바이트"
                         % (name.capitalize(), name, len(data)))
        for i in range(0, len(data), 16):
            banks[bi].append("    db " + ", ".join("0x%02X" % b for b in data[i:i + 16]))
        used[bi] += len(data)

    for bi in range(len(banks)):
        banks[bi].append("    ds %d - ($ - 0x%04X), 0" % (BANK_SIZE, BANK_BASE))
        banks[bi].append('    SAVEBIN "build/questspr%d.bin", 0x%04X, %d'
                         % (bi, BANK_BASE, BANK_SIZE))

    consts = ["SPR_W        equ %d" % W,
              "SPR_H        equ %d" % H,
              "SPR_BANKS    equ %d" % len(banks),
              "SPR_FIRSTBK  equ %d" % FIRST_BANK]
    for i, (name, _) in enumerate(blobs):
        bk, ad = place[i]
        consts.append("SPR_BANK_%d   equ %d                  ; %s" % (i, bk, name))
        consts.append("SPR_ADDR_%d   equ 0x%04X" % (i, ad))
    for bi in range(len(banks)):
        consts.append("; 뱅크 %d: %d / %d 바이트" % (FIRST_BANK + bi, used[bi], BANK_SIZE))
    return banks, consts


if __name__ == "__main__":
    print("이 파일은 quest_rules.py 가 불러 쓴다. 직접 실행하지 않는다.")
