"""gfx/message.json -> src/questmsgdata.asm + src/questmsgconst.asm

게임에 나오는 글을 말(영문/한글)별로 굽는다. 한글은 달무리 8x8 글꼴을 **빌드할 때**
조합해서 8바이트 비트맵으로 넣는다 - 그 조합 규칙은 Z80 에 올리기에 너무 복잡하다
(../hangul 의 doc 참고). 롬이 하는 일은 번호에 8을 곱해 주소를 내는 것뿐이다.

문자열 한 바이트가 곧 한 칸이다.

    0x20~0x5A   ASCII - 기존 6x8 폰트(FontData). 6픽셀 나아간다
    0x80~0xFF   한글  - 여기서 구운 8x8 폰트(HanFont). 8픽셀 나아간다

그래서 한 문자열 안에 영문과 한글이 섞여도 된다. 쓰는 글자만 굽기 때문에
message.json 에 없는 글자는 롬에 들어가지 않는다.

폭 검사가 이 파일의 핵심이다. 오른쪽 양피지가 한 줄 102픽셀(영문 17칸)뿐인데
이름이 앞에 붙는 줄은 영문만으로도 이미 그 폭에 닿아 있다. 그래서 한글이 영문보다
넓으면 빌드를 세운다 - 안 그러면 화면을 눈으로 보다가 한 줄씩 발견하게 되고,
SCREEN 8 에는 픽셀 단위 오라클이 없다.
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import dalmoori
import quest_gear

JSON = os.path.join(HERE, "message.json")
GLYPHS = os.path.join(ROOT, "assets", "dalmoori")

# 한글 글리프 번호가 시작하는 바이트값.
#
# ASCII 는 폰트가 32~90('Z') 뿐이라 0x5B 위쪽이 통째로 비어 있다. 처음에는
# 0x80 부터 썼는데 그러면 128 자가 상한이고, 품목 이름을 넣다가 실제로 130 자에서
# 걸렸다. 0x5B 로 내리면 165 자가 되고, 한 칸이 한 바이트인 것은 그대로다.
HAN_BASE = 0x5B
# 0xFF 는 탈출 바이트다. 한 바이트로 담는 것은 0x5B~0xFE 의 164 자이고, 그보다
# 뒤 글자는 0xFF 다음에 (번호 - 164) 를 한 바이트 더 붙인다. 해독은 PutChar 이
# 걸쇠 하나로 한다 - 문자열을 훑는 자리가 넷이라 거기서 다루면 하나를 빠뜨린다.
HAN_ESC_BYTE = 0xFF
HAN_ESC = HAN_ESC_BYTE - HAN_BASE       # 164 - 한 바이트로 담기는 글자 수
HAN_MAX = HAN_ESC + 256                 # 420 자까지

LANGS = ("en", "ko")


def is_han(ch):
    return 0xAC00 <= ord(ch) <= 0xD7A3


def width_px(s, cfg):
    """문자열이 화면에서 차지하는 픽셀 폭."""
    return sum(cfg["hangul_adv"] if is_han(c) else cfg["latin_adv"] for c in s)


def entries(node):
    """message.json 의 한 묶음에서 _ 로 시작하지 않는 항목만."""
    return {k: v for k, v in node.items() if not k.startswith("_")}


def collect(doc):
    """(묶음이름, 열쇠, {en,ko,...}) 을 차례대로."""
    for group, node in doc.items():
        if group.startswith("_") or group == "config":
            continue
        for key, val in entries(node).items():
            yield group, key, val


def check(doc, cfg, index):
    """폭과 칸 크기를 본다. 어긋나면 전부 모아서 한 번에 알린다.

    칸 크기는 **글자 수가 아니라 바이트 수**로 본다. 탈출 바이트가 붙으면 한
    글자가 두 바이트가 되므로, 글자 수로 세면 칸을 넘겨 놓고도 통과한다.
    """
    bad = []
    for group, key, val in collect(doc):
        en, ko = val["en"], val["ko"]
        slot = doc[group].get("_slot")

        # 고정 칸에 들어가는 것은 바이트 수가 칸을 넘으면 안 된다.
        if slot is not None:
            for lang in LANGS:
                n = len(encode(val[lang], index))
                if n > slot:
                    bad.append("%s.%s [%s] %r 이 %d바이트다 (칸이 %d)"
                               % (group, key, lang, val[lang], n, slot))

        # 이름 뒤에 붙는 말은 영문보다 넓으면 안 된다. 영문이 이미 폭에 닿아 있다.
        wen, wko = width_px(en, cfg), width_px(ko, cfg)
        if val.get("after_name") and wko > wen:
            bad.append("%s.%s 한글이 %d픽셀로 영문 %d픽셀보다 넓다 (%r vs %r)"
                       % (group, key, wko, wen, ko, en))

        # 명령 메뉴는 한 줄에 둘이라 반 칸씩이다.
        if group == "skills" or key.startswith("cmd_"):
            for lang in LANGS:
                w = width_px(val[lang], cfg)
                if w > cfg["menu_px"]:
                    bad.append("%s.%s [%s] %r 이 %d픽셀이다 (메뉴 칸 %d)"
                               % (group, key, lang, val[lang], w, cfg["menu_px"]))
    return bad


def encode(s, index):
    """문자열 -> 롬에 들어갈 바이트열."""
    out = bytearray()
    for ch in s:
        if is_han(ch):
            n = index[ch]
            if n < HAN_ESC:
                out.append(HAN_BASE + n)
            else:
                out.append(HAN_ESC_BYTE)    # 탈출 - 다음 바이트가 나머지 번호
                out.append(n - HAN_ESC)
        elif 0x20 <= ord(ch) < HAN_BASE:
            out.append(ord(ch))
        else:
            raise SystemExit("폰트에 없는 글자: %r (U+%04X) in %r" % (ch, ord(ch), s))
    return bytes(out)


def db_bytes(data, per=16):
    out = []
    for i in range(0, len(data), per):
        out.append("    db " + ", ".join("0x%02X" % b for b in data[i:i + per]))
    return out


def db_str(data):
    """읽을 수 있는 것은 따옴표로, 한글 번호는 숫자로."""
    parts, run = [], ""
    for b in data:
        if 0x20 <= b <= 0x5A and b != ord('"'):
            run += chr(b)
        else:
            if run:
                parts.append('"%s"' % run)
                run = ""
            parts.append("0x%02X" % b)
    if run:
        parts.append('"%s"' % run)
    return "    db " + ", ".join(parts) + ", 0"


TITLE_JSON = os.path.join(HERE, "title.json")


def title_strings():
    """title.json 의 글. 없으면 빈 목록.

    타이틀은 --title 을 준 빌드에만 들어가지만, **폰트는 늘 여기 것까지 굽는다.**
    빌드 갈래마다 폰트가 달라지면 같은 글자가 다른 번호를 갖게 되고, 그러면
    타이틀 있는 롬과 없는 롬에서 questmsgdata.asm 이 서로 안 맞는다. 몇 글자
    더 굽는 값(글자당 8 바이트)이 그 혼란보다 싸다.
    """
    if not os.path.exists(TITLE_JSON):
        return []
    doc = json.load(io.open(TITLE_JSON, encoding="utf-8"))
    return [ln[lang] for sc in doc["screens"] for ln in sc["lines"]
            for lang in LANGS]


def font_index():
    """글자 -> 글리프 번호. 굽는 쪽과 쓰는 쪽이 같은 표를 봐야 한다."""
    doc = json.load(io.open(JSON, encoding="utf-8"))
    chars = {c for _g, _k, v in collect(doc) for lang in LANGS
             for c in v[lang] if is_han(c)}
    chars |= {c for s in title_strings() for c in s if is_han(c)}
    return {c: i for i, c in enumerate(sorted(chars))}


def main():
    doc = json.load(io.open(JSON, encoding="utf-8"))
    cfg = doc["config"]

    bad = check(doc, cfg, font_index())
    if bad:
        sys.exit("message.json 이 화면에 안 들어갑니다:\n  " + "\n  ".join(bad))

    # --- 쓰는 한글만 모아 굽는다 ---------------------------------------------
    # title.json 것도 함께 굽는다 (font_index 참고).
    chars = sorted(font_index())
    if len(chars) > HAN_MAX:
        sys.exit("한글이 %d자다. 탈출 바이트를 써도 %d자까지뿐이다.\n"
                 "  message.json 과 title.json 의 글을 줄여야 한다."
                 % (len(chars), HAN_MAX))

    font = dalmoori.Font(GLYPHS)
    bitmaps = [font.glyph(c) for c in chars]
    index = font_index()

    # --- 상수 (equ 뿐이라 ORG 앞에서 include 한다) ----------------------------
    ui = entries(doc["ui"]) | entries(doc["symbols"]) | entries(doc["stats"])
    ids = sorted(ui)
    C = ["; gfx/quest_msg.py 가 생성한 파일입니다. 직접 고치지 마세요.",
         "; 글을 고치려면 gfx/message.json 을 고치고 다시 빌드하세요.",
         "",
         "HAN_BASE     equ 0x%02X                ; 이 값 이상이면 한글 글리프 번호다" % HAN_BASE,
         "HAN_ESC_BYTE equ 0x%02X                ; 이 바이트는 안 찍는다 - 다음 글자에 얹는다" % HAN_ESC_BYTE,
         "HAN_ESC      equ %d               ; 탈출한 글자의 번호는 여기서부터" % HAN_ESC,
         "HANGUL_ADV   equ %d                 ; 한글 한 칸 (영문은 FONT_W = 6)" % cfg["hangul_adv"],
         "HAN_N        equ %d                ; 구워 넣은 한글 글자 수" % len(chars),
         "MSG_N        equ %d" % len(ids),
         "LANG_EN      equ 0",
         "LANG_KO      equ 1",
         "LANG_DEFAULT equ LANG_%s" % cfg["default_lang"].upper(),
         ""]
    for i, k in enumerate(ids):
        C.append("MSG_%-10s equ %d" % (k.upper(), i))

    # --- 자료 (db 라서 ORG 0x4000 뒤에 include 한다) --------------------------
    D = ["; gfx/quest_msg.py 가 생성한 파일입니다. 직접 고치지 마세요.",
         "; 글을 고치려면 gfx/message.json 을 고치고 다시 빌드하세요.",
         "",
         "; --- 달무리 8x8 한글 (%d자 x 8바이트 = %d바이트) ---" % (len(chars), len(chars) * 8),
         "; 조합은 빌드할 때 끝났다. 롬은 번호 x 8 로 주소만 낸다.",
         "HanFont:"]
    for c, bm in zip(chars, bitmaps):
        D.append("    ; %s" % c)
        D += db_bytes(bm, 8)
    D.append("")

    D.append("; --- 말별 문자열 표. MsgText 가 번호로 짚는다 ---")
    for lang in LANGS:
        D.append("MsgTab%s:" % lang.upper())
        for k in ids:
            D.append("    dw MsgTxt%s_%s" % (lang.upper(), k))
        D.append("")
    for lang in LANGS:
        for k in ids:
            s = ui[k][lang]
            D.append("MsgTxt%s_%-12s ; %r" % (lang.upper(), k + ":", s))
            D.append(db_str(encode(s, index)))
        D.append("")

    # --- 이름 표 (몬스터/기술) -----------------------------------------------
    # 이 둘은 quest_rules.py 가 굽는 표 안에 이름이 박혀 있었다. 말을 바꾸려면
    # 이름만 따로 있어야 해서 여기로 옮긴다. 차례는 quest_rules.py 의 차례와
    # 같아야 하므로 그쪽 목록을 그대로 적어 둔다.
    # 몬스터와 무기는 **정본에서 읽는다.** 여기 또 적으면 한쪽만 고쳤을 때
    # 이름과 수치가 어긋난다 - 몬스터 차례는 실제로 손으로 베껴 두고 있었다.
    import quest_rules
    ORDER = {
        "monsters": [m["name"] for m in quest_rules.load_monsters()],
        "skills": ["SURGE", "SNEAK", "BOLT", "SMITE", "KI"],
        "classes": ["FIGHTER", "ROGUE", "WIZARD", "CLERIC", "MUSA"],
        "races": ["HUMAN", "DWARF", "ELF", "GNOME",
                  "HALF-ELF", "HALF-ORC", "HALFLING"],
        # 무기는 차례가 곧 번호다. gfx/items.json 이 정본이다.
        "weapons": [it[0] for it in quest_gear.ITEMS],
    }
    LABEL = {"monsters": "MonName", "skills": "SkillName",
             "classes": "ClassName", "races": "RaceName",
             "weapons": "WeaponName"}
    for group, keys in ORDER.items():
        node = doc[group]
        slot = node["_slot"]
        missing = [k for k in keys if k not in node]
        if missing:
            sys.exit("message.json 의 %s 에 없는 것: %s" % (group, ", ".join(missing)))
        C.append("")
        C.append("%-12s equ %d" % (LABEL[group].upper() + "_LEN", slot + 1))
        for lang in LANGS:
            D.append("%s%s:" % (LABEL[group], lang.upper()))
            for k in keys:
                b = encode(node[k][lang], index)
                D.append("    ; %s" % node[k][lang])
                # 이름 뒤에 0 을 붙이고 남은 칸도 0 으로 채운다. PutStr 과
                # MsgAddStr 둘 다 0 에서 멈추므로 뒤의 채움이 딸려 나오지
                # 않는다. (칸 크기는 색인을 위해 고정이어야 한다.)
                D.append(db_str(b + bytes(slot - len(b))))
            D.append("")

    # newline="\n" 을 준다. 안 주면 윈도우에서 CRLF 로 나가서, 빌드가 생성기를
    # 돌릴 때마다 내용이 같은데도 git 에 바뀐 것으로 잡힌다.
    open(os.path.join(ROOT, "src", "questmsgconst.asm"), "w",
         encoding="utf-8", newline="\n").write("\n".join(C) + "\n")
    open(os.path.join(ROOT, "src", "questmsgdata.asm"), "w",
         encoding="utf-8", newline="\n").write("\n".join(D) + "\n")

    size = len(chars) * 8 + sum(len(encode(ui[k][l], index)) + 1
                                for l in LANGS for k in ids) + 2 * 2 * len(ids)
    print("한글 %d자, 메시지 %d개 x %d개 말 -> 약 %d바이트"
          % (len(chars), len(ids), len(LANGS), size))
    return doc, cfg, index, font, chars


if __name__ == "__main__":
    main()
