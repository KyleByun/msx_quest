"""gfx/title.json -> 타이틀 화면 자료 (그림 뱅크 + 글).

**빌드에 --title 을 주었을 때만 부른다.** 안 주면 그림도 코드도 롬에 안 들어가고
부팅하면 바로 게임이다. 테스트할 때 타이틀을 매번 넘기지 않으려는 것이다.

그림이 왜 롬을 키우나
  256x144 짜리 넉 장이 RLE 로 13 뱅크다. 디더링된 픽셀 아트라 같은 바이트가
  이어지는 자리가 드물어서, 색을 8 가지로 줄여도 10 뱅크였다(재 봤다). zlib
  같은 제대로 된 LZ 를 써도 5 뱅크라 Z80 해독기를 새로 짤 값어치가 없다.
  게임이 14 뱅크를 쓰므로 128KB(16 뱅크)에는 못 넣는다.

  ASCII8 은 뱅크 번호가 8 비트라 2MB 까지 간다. 256KB 로 올리면 32 뱅크가 되고
  27 뱅크를 쓴다. openMSX 에서 뱅크 20 과 31 을 걸어 읽어 확인했다.

글자는 quest_msg.py 가 굽는 폰트를 그대로 쓴다. 여기 쓴 한글도 그쪽이 함께
구워 넣으므로(quest_msg 가 title.json 을 같이 훑는다) 폰트에 없어서 안 나오는
일은 없다.
"""
import io
import json
import os
import sys

from PIL import Image

import quest_convert as C
import quest_msg as M
from quest_pal import to332

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
JSON = os.path.join(HERE, "title.json")
SPRITES = os.path.join(HERE, "sprites")

SCREEN_W = 256
SCREEN_H = 212
MARGIN = 8                  # 글 왼쪽 여백
PRE = "quest8"              # 타이틀은 SCREEN 8 판에만 있다


def load():
    return json.load(io.open(JSON, encoding="utf-8"))


def check(doc, index):
    """폭과 자리를 본다. 어긋나면 전부 모아서 한 번에 알린다.

    타이틀은 SCREEN 8 에만 있고 거기에는 픽셀 오라클이 없다. 안 막으면 글이
    화면 밖으로 나간 것을 눈으로 보다가 알게 된다.
    """
    cfg = doc["config"]
    bad = []
    if not 0 < cfg["image_h"] < SCREEN_H:
        bad.append("image_h 가 %d 다. 1..%d 이어야 한다." % (cfg["image_h"], SCREEN_H - 1))
    maxpx = SCREEN_W - MARGIN * 2
    mcfg = json.load(io.open(M.JSON, encoding="utf-8"))["config"]
    for n, sc in enumerate(doc["screens"]):
        p = os.path.join(SPRITES, sc["img"] + ".png")
        if not os.path.exists(p):
            bad.append("%d 번째 그림 %s.png 가 gfx/sprites/ 에 없다" % (n + 1, sc["img"]))
        y = cfg["text_y"] + len(sc["lines"]) * cfg["line_h"]
        if y > SCREEN_H:
            bad.append("%s 의 글이 %d 줄이라 화면(%d) 을 넘는다 (마지막 줄 끝 y=%d)"
                       % (sc["img"], len(sc["lines"]), SCREEN_H, y))
        for ln in sc["lines"]:
            for lang in M.LANGS:
                w = M.width_px(ln[lang], mcfg)
                if w > maxpx:
                    bad.append("%s [%s] %r 이 %d 픽셀이다 (자리 %d)"
                               % (sc["img"], lang, ln[lang], w, maxpx))
                try:
                    M.encode(ln[lang], index)
                except SystemExit as e:
                    bad.append(str(e))
    return bad


def bake_image(path, h):
    """그림 하나 -> RLE. SCREEN 8 이라 한 바이트가 한 픽셀(GRB332)이다."""
    im = Image.open(path).convert("RGB").resize((SCREEN_W, h), Image.LANCZOS)
    px = im.load()
    raw = bytes(to332(px[x, y]) for y in range(h) for x in range(SCREEN_W))
    return C.rle(raw), len(raw)


def main():
    doc = load()
    cfg = doc["config"]
    index = M.font_index()          # message.json + title.json 의 한글

    bad = check(doc, index)
    if bad:
        sys.exit("gfx/title.json 이 어긋났습니다:\n  " + "\n  ".join(bad))

    # ---- 그림을 뱅크에 담는다 ------------------------------------------
    # 한 장이 8KB 를 넘으므로 뱅크에 **걸쳐서** 담고, 푸는 쪽이 0xC000 에
    # 닿을 때마다 다음 뱅크로 넘어간다. 장마다 뱅크를 새로 시작하면 자투리가
    # 장당 평균 4KB 씩 버려진다.
    banks, blob, plan = [], bytearray(), []
    for sc in doc["screens"]:
        data, raw = bake_image(os.path.join(SPRITES, sc["img"] + ".png"),
                               cfg["image_h"])
        plan.append((sc["img"], len(blob), len(data), raw))
        blob += data
    for i in range(0, len(blob), C.BANK_SIZE):
        banks.append(blob[i:i + C.BANK_SIZE])

    # ---- 글 ------------------------------------------------------------
    lines = {lang: [] for lang in M.LANGS}      # 0 으로 끝나는 줄들
    first, count = [], []
    n = 0
    for sc in doc["screens"]:
        first.append(n)
        count.append(len(sc["lines"]))
        n += len(sc["lines"])
        for ln in sc["lines"]:
            for lang in M.LANGS:
                lines[lang].append(M.encode(ln[lang], index) + b"\x00")

    Cc = ["; gfx/quest_title.py 가 생성한 파일입니다. 직접 고치지 마세요.",
          "; 글과 차례를 고치려면 gfx/title.json 을 고치세요.",
          "",
          "TITLE_N      equ %d" % len(doc["screens"]),
          "TITLE_IMG_H  equ %d                ; 그림이 차지하는 줄 수" % cfg["image_h"],
          "TITLE_TEXT_Y equ %d" % cfg["text_y"],
          "TITLE_LINE_H equ %d" % cfg["line_h"],
          "TITLE_HOLD   equ %d                ; 0 이면 키를 누를 때까지" % cfg["hold"],
          "TITLE_MARGIN equ %d" % MARGIN,
          "TITLE_TYPE_D equ %d                ; 글자 하나마다 기다릴 프레임"
          % cfg.get("type_delay", 2),
          "TITLE_BANKS  equ %d" % len(banks),
          "TITLE_LINE_N equ %d" % n,
          "",
          "; 그림 뱅크는 게임 뱅크 **뒤**에 붙는다. 게임 쪽 마지막이 벽면 런이다.",
          "TITLE_BANK0  equ RUN_BANK0 + RUN_BANKS",
          ]

    D = ["; gfx/quest_title.py 가 생성한 파일입니다. 직접 고치지 마세요.",
         "",
         "; --- 화면마다: 시작 뱅크, 그 뱅크 안의 주소, RLE 길이 -------------",
         "; 한 장이 8KB 를 넘으므로 푸는 쪽이 0xC000 에 닿으면 다음 뱅크로 넘어간다.",
         "TitleImg:"]
    for name, off, ln, raw in plan:
        D.append("    db TITLE_BANK0 + %d" % (off // C.BANK_SIZE))
        D.append("    dw 0x%04X" % (C.BANK_WIN + off % C.BANK_SIZE))
        D.append("    dw %d          ; %s (푼 뒤 %d 바이트)" % (ln, name, raw))
    D.append("")
    D.append("; --- 화면마다 글 몇 줄째부터 몇 줄 -------------------------------")
    D.append("TitleLine:")
    for i in range(len(first)):
        D.append("    db %d, %d" % (first[i], count[i]))
    D.append("")
    for lang in M.LANGS:
        D.append("TitleTextPtr%s:" % lang.upper())
        for i in range(n):
            D.append("    dw TitleText%s_%d" % (lang.upper(), i))
        for i, b in enumerate(lines[lang]):
            D.append("TitleText%s_%d:" % (lang.upper(), i))
            D.append(M.db_str(b))
        D.append("")

    io.open(os.path.join(ROOT, "src", PRE + "titleconst.asm"), "w",
            encoding="utf-8", newline="\n").write("\n".join(Cc) + "\n")
    io.open(os.path.join(ROOT, "src", PRE + "titledata.asm"), "w",
            encoding="utf-8", newline="\n").write("\n".join(D) + "\n")
    for i, b in enumerate(banks):
        C.bank_file(PRE, "titlebank", i, b,
                    "타이틀 그림 %d/%d" % (i + 1, len(banks)))
    print("타이틀 %d 장, 그림 %d 바이트 -> %d 뱅크, 글 %d 줄 x %d 개 말"
          % (len(doc["screens"]), len(blob), len(banks), n, len(M.LANGS)))


if __name__ == "__main__":
    main()
