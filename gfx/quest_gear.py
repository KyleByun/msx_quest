"""장비/소지품 표를 굽는다 -> src/questgeardata.asm + src/questgearconst.asm

quest_sena.md 의 "각 클래스별 무기 선택할수 있는 목록" 과 마을 상점 절에서 왔다.
줄이고 바꾼 것은 그 문서의 "### 실제로 롬에 들어간 것" 에 적어 두었다.

**품목 하나로 통일한다.** 무기든 방패든 물약이든 같은 표에 들어가고, `I_SLOT` 이
그것을 어디에 차는지 정한다. 파티원은 품목 번호를 담은 가방(G_INV)을 갖고,
G_EQUIP 이 자리마다 "가방 몇 번째를 차고 있나" 를 기억한다.

  자리가 다르면 함께 찰 수 있다 (칼 + 방패 + 갑옷 + 투구).
  자리가 같으면 함께 못 찬다 (칼과 도끼).

이름(한글/영문)은 gfx/message.json 에 있다. quest_msg.py 가 이 파일의 차례를
그대로 읽어 이름 표를 굽는다 - 두 곳에 따로 적으면 한쪽만 고쳤을 때 어긋난다.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# 차는 자리. 0 은 차는 것이 아니라 쓰는 것(소모품)이다.
SLOT_USE, SLOT_WEAPON, SLOT_SHIELD, SLOT_ARMOUR, SLOT_HELM = range(5)
EQUIP_N = 4                         # 무기/방패/갑옷/투구

# 소모품의 효과 종류
EFF_NONE, EFF_HP, EFF_MP = 0, 1, 2

# (열쇠, 자리, A, B, 양손)
#
#   무기   A = 피해 개수, B = 면
#   방어구 A = AC 보너스,  B = 0
#   소모품 A = 효과 크기,  B = 효과 종류
#
# 무기 수치는 quest_sena.md 의 카탈로그 표 그대로다. 다용도(1d8/양손 1d10)는
# 한손 값만 쓴다 - 손 상태를 따로 들고 있어야 해서.
ITEMS = [
    ("DAGGER",     SLOT_WEAPON, 1,  4, 0),
    ("SHORTSWORD", SLOT_WEAPON, 1,  6, 0),
    ("LONGSWORD",  SLOT_WEAPON, 1,  8, 0),
    ("GREATSWORD", SLOT_WEAPON, 2,  6, 1),
    ("MACE",       SLOT_WEAPON, 1,  6, 0),
    ("WARHAMMER",  SLOT_WEAPON, 1,  8, 0),
    ("STAFF",      SLOT_WEAPON, 1,  6, 0),
    ("HWANDO",     SLOT_WEAPON, 1,  8, 0),
    ("GUKGUNG",    SLOT_WEAPON, 1,  8, 1),
    ("LONGBOW",    SLOT_WEAPON, 1,  8, 1),
    ("LIGHT_XBOW", SLOT_WEAPON, 1,  8, 1),
    ("HAND_XBOW",  SLOT_WEAPON, 1,  6, 0),
    # 방어구. AC 보너스는 D&D 5e 의 가벼운 갑옷/방패 값을 따랐다.
    ("SHIELD",     SLOT_SHIELD, 2,  0, 0),
    ("LEATHER",    SLOT_ARMOUR, 1,  0, 0),
    ("CHAINMAIL",  SLOT_ARMOUR, 3,  0, 0),
    ("HELMET",     SLOT_HELM,   1,  0, 0),
    # 소모품. 마나 물약 5 는 quest_sena.md 의 "5 MP" 그대로,
    # 치유 물약 10 은 D&D 5e 의 potion of healing(2d4+2) 평균이다.
    ("POTION_HP",  SLOT_USE,   10, EFF_HP,   0),
    ("POTION_MP",  SLOT_USE,    5, EFF_MP,   0),
    ("PORTAL",     SLOT_USE,    0, EFF_NONE, 0),
]

# 클래스가 쥘 수 있는 무기. **맨 앞이 처음 차고 시작하는 무기**다.
CLASS_WEAPONS = {
    "FIGHTER": ["LONGSWORD", "GREATSWORD", "WARHAMMER", "MACE",
                "SHORTSWORD", "LONGBOW"],
    "ROGUE":   ["DAGGER", "SHORTSWORD", "HAND_XBOW", "LIGHT_XBOW", "STAFF"],
    "WIZARD":  ["STAFF", "DAGGER", "LIGHT_XBOW"],
    "CLERIC":  ["MACE", "WARHAMMER", "STAFF", "LIGHT_XBOW"],
    "MUSA":    ["HWANDO", "GUKGUNG", "SHORTSWORD", "DAGGER"],
}
CLASS_SHIELD = {"FIGHTER": 1, "ROGUE": 0, "WIZARD": 0, "CLERIC": 1, "MUSA": 0}
CLASS_ORDER = ["FIGHTER", "ROGUE", "WIZARD", "CLERIC", "MUSA"]

# 처음 갖고 시작하는 것 - 무기 목록 뒤에 붙는다.
START_EXTRA = ["LEATHER", "POTION_HP"]
INV_N = 10                          # 가방 칸
GEAR_STRIDE = 16                    # 가방 10 + 찬 자리 4 + 여유 2 (2 의 거듭제곱)


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
         "; 수치는 quest_sena.md 에서 왔습니다.",
         "",
         "ITEM_N       equ %d" % len(ITEMS),
         "ITEM_STRIDE  equ 4",
         "I_SLOT       equ 0                 ; 어디에 차는가 (0 이면 쓰는 것)",
         "I_A          equ 1                 ; 무기 개수 / 방어구 AC / 물약 크기",
         "I_B          equ 2                 ; 무기 면 / 물약 효과 종류",
         "I_TWOH       equ 3                 ; 양손이면 방패를 못 든다",
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
    for name, slot, a, b, twoh in ITEMS:
        D.append("    db %d, %2d, %d, %d      ; %d %s" % (slot, a, b, twoh, idx[name], name))
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
