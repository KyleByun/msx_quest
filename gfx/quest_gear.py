"""gfx/items.json -> src/questgeardata.asm + src/questgearconst.asm

**수치를 고치려면 gfx/items.json 을 고친다.** 이 파일은 그것을 롬 표로 펼치고
검사만 한다. 예전에는 표가 이 파일 안의 파이썬 리터럴이었다.

무기든 방패든 물약이든 **한 표**에 들어간다. 롬에도 표가 하나뿐이고(ItemTable)
`I_SLOT` 이 그것을 어디에 차는지 정한다. 파일을 무기/아이템으로 나누지 않은
이유는, 품목 번호가 가방(G_INV)에 그대로 들어가서 두 파일을 합치는 순서가 곧
번호가 되기 때문이다.

  자리가 다르면 함께 찰 수 있다 (칼 + 방패 + 갑옷 + 투구).
  자리가 같으면 함께 못 찬다 (칼과 도끼).

이름(한글/영문)은 gfx/message.json 에 있다. quest_msg.py 가 이 파일의 차례를
그대로 읽어 이름 표를 굽는다 - 두 곳에 따로 적으면 한쪽만 고쳤을 때 어긋난다.

**검사가 이 파일의 일이다.** SCREEN 8 에는 픽셀 오라클이 없어서, JSON 을 손으로
고치다 어긋나면 화면을 눈으로 보다가 발견하게 된다. 그래서 값이 바이트에
들어가는지, 없는 열쇠를 가리키는지를 여기서 막는다.
"""
import json
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

JSON = os.path.join(HERE, "items.json")

# 차는 자리. 0 은 차는 것이 아니라 쓰는 것(소모품)이다.
SLOT_USE, SLOT_WEAPON, SLOT_SHIELD, SLOT_ARMOUR, SLOT_HELM = range(5)
EQUIP_N = 4                         # 무기/방패/갑옷/투구
SLOT_NAME = {"use": SLOT_USE, "weapon": SLOT_WEAPON, "shield": SLOT_SHIELD,
             "armour": SLOT_ARMOUR, "helm": SLOT_HELM}

# 소모품의 효과 종류
EFF_NONE, EFF_HP, EFF_MP = 0, 1, 2
EFF_NAME = {"none": EFF_NONE, "hp": EFF_HP, "mp": EFF_MP}

# 무기 계열 - 맞았을 때 어떤 자국이 나는가를 정한다.
#
# **0 이 칼이다.** 기록이 0 으로 비어 있어도 칼자국이 나게 해서, 계열을 안 넣은
# 무기나 초기화를 빠뜨린 자리가 표 밖을 짚지 않게 한다.
FAM_BLADE, FAM_POLE, FAM_BOW = 0, 1, 2
FAM_NAME = {"blade": FAM_BLADE, "polearm": FAM_POLE, "bow": FAM_BOW}


def load():
    """items.json -> (품목, 클래스별 무기, 방패 여부, 차례, 설정).

    품목은 (열쇠, 자리, A, B, 양손) 다섯 짜리로 펼친다.

      무기   A = 피해 개수, B = 면
      방어구 A = AC 보너스,  B = 0
      소모품 A = 효과 크기,  B = 효과 종류
    """
    doc = json.load(io.open(JSON, encoding="utf-8"))
    bad, items = [], []
    for n, it in enumerate(doc["items"]):
        key = it.get("key", "(이름 없음 %d 번째)" % n)
        slot = SLOT_NAME.get(it.get("slot"))
        if slot is None:
            bad.append("%s 의 slot %r 이 %s 중에 없다"
                       % (key, it.get("slot"), "/".join(sorted(SLOT_NAME))))
            continue
        if slot == SLOT_WEAPON:
            a, b = it.get("dice", [0, 0])
        elif slot == SLOT_USE:
            a, b = it.get("amount", 0), EFF_NAME.get(it.get("effect", "none"), -1)
            if b < 0:
                bad.append("%s 의 effect %r 이 %s 중에 없다"
                           % (key, it.get("effect"), "/".join(sorted(EFF_NAME))))
        else:
            a, b = it.get("ac", 0), 0
        for label, v in (("A", a), ("B", b)):
            if not isinstance(v, int) or not 0 <= v <= 255:
                bad.append("%s 의 %s 가 %r 이다. 한 바이트에 들어가야 한다." % (key, label, v))
        fam = FAM_NAME.get(it.get("family", "blade"))
        if fam is None:
            bad.append("%s 의 family %r 이 %s 중에 없다"
                       % (key, it.get("family"), "/".join(sorted(FAM_NAME))))
            fam = FAM_BLADE
        elif slot != SLOT_WEAPON and it.get("family"):
            bad.append("%s 는 무기가 아닌데 family 가 붙어 있다" % key)
        items.append((key, slot, a, b, 1 if it.get("two_handed") else 0, fam))

    seen = set()
    for key, _, _, _, _, _ in items:
        if key in seen:
            bad.append("품목 열쇠 %s 가 두 번 나온다" % key)
        seen.add(key)
    if len(items) >= 0xFF:
        bad.append("품목이 %d 개다. 가방의 빈 칸 표시가 0xFF 라 255 개 미만이어야 한다."
                   % len(items))

    weapons, shields, order = {}, {}, []
    for c in doc["classes"]:
        key = c["key"]
        order.append(key)
        weapons[key] = c["weapons"]
        shields[key] = 1 if c.get("shield") else 0
        if not c["weapons"]:
            bad.append("%s 에 무기가 하나도 없다. 맨 앞이 처음 차는 무기다." % key)
    if bad:
        sys.exit("gfx/items.json 이 어긋났습니다:\n  " + "\n  ".join(bad))
    return items, weapons, shields, order, doc["config"]


ITEMS, CLASS_WEAPONS, CLASS_SHIELD, CLASS_ORDER, CONFIG = load()

# 처음 갖고 시작하는 것 - 무기 목록 뒤에 붙는다.
START_EXTRA = CONFIG["start_extra"]
INV_N = CONFIG["inv_n"]             # 가방 칸
GEAR_STRIDE = CONFIG["gear_stride"]  # 가방 10 + 찬 자리 4 + 여유 2 (2 의 거듭제곱)


def main():
    idx = {it[0]: i for i, it in enumerate(ITEMS)}
    kits = {}
    for cls in CLASS_ORDER:
        kit = list(CLASS_WEAPONS[cls])
        if CLASS_SHIELD[cls]:
            kit.append("SHIELD")
        kit += START_EXTRA
        for k in kit:
            if k not in idx:
                sys.exit("%s 의 %s 가 품목 표에 없다" % (cls, k))
        if len(kit) > INV_N:
            sys.exit("%s 의 처음 짐이 %d 개다. 가방은 %d 칸." % (cls, len(kit), INV_N))
        kits[cls] = kit

    C = ["; gfx/quest_gear.py 가 생성한 파일입니다. 직접 고치지 마세요.",
         "; 수치를 고치려면 gfx/items.json 을 고치세요.",
         "",
         "ITEM_N       equ %d" % len(ITEMS),
         "ITEM_STRIDE  equ 4",
         "I_SLOT       equ 0                 ; 어디에 차는가 (0 이면 쓰는 것)",
         "I_A          equ 1                 ; 무기 개수 / 방어구 AC / 물약 크기",
         "I_B          equ 2                 ; 무기 면 / 물약 효과 종류",
         "I_TWOH       equ 3                 ; 양손이면 방패를 못 든다",
         "",
         "; 무기 계열. 맞았을 때 나는 자국이 이것으로 갈린다 (ItemFam 표).",
         "FAM_BLADE    equ %d                 ; 검, 도, 둔기" % FAM_BLADE,
         "FAM_POLE     equ %d                 ; 창, 봉 - 아래서 위로 길게" % FAM_POLE,
         "FAM_BOW      equ %d                 ; 활, 쇠뇌 - 화살이 날아온다" % FAM_BOW,
         "FAM_N        equ %d" % len(FAM_NAME),
         "",
         "SLOT_USE     equ %d" % SLOT_USE,
         "SLOT_WEAPON  equ %d" % SLOT_WEAPON,
         "SLOT_SHIELD  equ %d" % SLOT_SHIELD,
         "SLOT_ARMOUR  equ %d" % SLOT_ARMOUR,
         "SLOT_HELM    equ %d" % SLOT_HELM,
         "EQUIP_N      equ %d" % EQUIP_N,
         "",
         "EFF_NONE     equ %d" % EFF_NONE,
         "EFF_HP       equ %d" % EFF_HP,
         "EFF_MP       equ %d" % EFF_MP,
         "",
         "INV_N        equ %d                ; 가방 칸" % INV_N,
         "INV_EMPTY    equ 0xFF",
         "GEAR_STRIDE  equ %d                ; 2 의 거듭제곱이라 색인이 시프트로 끝난다" % GEAR_STRIDE,
         "G_INV        equ 0                 ; 가방 %d 칸" % INV_N,
         "G_EQUIP      equ %d                 ; 자리마다 '가방 몇 번째' (없으면 INV_EMPTY)" % INV_N,
         "",
         "KIT_STRIDE   equ %d" % (INV_N + 1),
         ]

    D = ["; gfx/quest_gear.py 가 생성한 파일입니다. 직접 고치지 마세요.",
         "",
         "; --- 품목: 자리, A, B, 양손 ---",
         "ItemTable:"]
    for name, slot, a, b, twoh, _fam in ITEMS:
        D.append("    db %d, %2d, %d, %d      ; %d %s" % (slot, a, b, twoh, idx[name], name))
    D.append("")

    # 계열은 무기에만 쓰므로 ItemTable 을 넓히지 않고 따로 둔다 - ITEM_STRIDE 가
    # 4 라야 색인이 시프트로 끝난다.
    D.append("; --- 무기 계열 (품목 번호로 바로 짚는다) ---")
    D.append("ItemFam:")
    for i in range(0, len(ITEMS), 8):
        row = ITEMS[i:i + 8]
        D.append("    db " + ", ".join(str(it[5]) for it in row)
                 + "   ; %s" % ", ".join(it[0] for it in row))
    D.append("")

    D.append("; --- 클래스가 쥘 수 있는 무기. 맨 앞이 처음 차는 것 ---")
    D.append("ClassWeapons:")
    maxw = max(len(v) for v in CLASS_WEAPONS.values())
    for cls in CLASS_ORDER:
        row = [str(idx[w]) for w in CLASS_WEAPONS[cls]]
        row += ["INV_EMPTY"] * (maxw + 1 - len(row))
        D.append("    db " + ", ".join(row) + "   ; %s" % cls)
    D.append("")
    C.append("CLSW_STRIDE  equ %d" % (maxw + 1))

    D.append("; --- 처음 갖고 시작하는 짐 ---")
    D.append("StartKit:")
    for cls in CLASS_ORDER:
        row = [str(idx[k]) for k in kits[cls]]
        row += ["INV_EMPTY"] * (INV_N + 1 - len(row))
        D.append("    db " + ", ".join(row))
        D.append("        ; %s: %s" % (cls, ", ".join(kits[cls])))
    D.append("")

    open(os.path.join(ROOT, "src", "questgearconst.asm"), "w",
         encoding="utf-8").write("\n".join(C) + "\n")
    open(os.path.join(ROOT, "src", "questgeardata.asm"), "w",
         encoding="utf-8").write("\n".join(D) + "\n")
    print("품목 %d개, 처음 짐 %s"
          % (len(ITEMS), " / ".join("%s %d" % (c, len(kits[c])) for c in CLASS_ORDER)))


if __name__ == "__main__":
    main()
