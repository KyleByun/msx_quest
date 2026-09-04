"""D&D 규칙 자료를 asm 표로 굽는다.

정본이 둘로 나뉘어 있다.

  종족 / 직업 / BAB   D:/my/python/dnd (진짜 D&D 규칙). 원본이 없으면
                      gfx/quest_rules.json 에 남겨 둔 값을 쓴다.
  몬스터 수치         **gfx/monster.json**. 손으로 고치는 정본이다.

몬스터를 옮긴 이유: AC/HP/민첩은 D&D 충실도가 아니라 이 게임의 균형이고,
무리 크기와 그림 자리는 애초에 D&D 에 없는 값이다. 예전에는 dnd 에서 매 빌드마다
끌어와 quest_rules.json 에 캐시했는데, 그래서 손으로 고쳐도 다음 빌드에 덮였다.

  uv run python gfx/quest_rules.py --seed-monsters

로 dnd 에서 다시 뽑을 수 있다(monster.json 을 덮는다). 새 몬스터를 들일 때만 쓴다.

원래 머리말:


가져오는 것
  race_job.py      RACE_DATA, CLASS_DATA, calc_base_attack_bonus
  dice.py          ability_modifier  (표로 펼쳐서 굽는다)
  hero.py          apply_class_stats 의 직업별 능력치 보정
  enemy.py         apply_type 의 몬스터별 피해 주사위
  monster_stats.py 몬스터 기본 수치

Z80 에서 나눗셈을 피하려고 계산식을 전부 표로 펼친다. ability_modifier 는
(점수-10)//2 인데 파이썬의 내림 나눗셈이라 음수에서 -1, -2 로 떨어진다. 표로
구우면 부호 처리를 매번 신경 쓸 필요가 없다. BAB 도 마찬가지다 - "average" 가
int(레벨*0.75) 라서 레벨 1 에서 1 이 아니라 0 이다. 반올림으로 흉내 내면 틀린다.

원본이 없어져도 빌드가 멈추지 않도록 뽑아낸 값을 quest_rules.json 에 남긴다.
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DND = r"D:\my\python\dnd"
SNAPSHOT = os.path.join(HERE, "quest_rules.json")

# 화면에 넣는 직업 여섯이 고르게 뽑히도록 원본의 열한 직업을 전부 쓴다.
PARTY_N = 6
MON_N = 5           # battlefield.py 가 다섯 마리를 뽑는다

# 나오는 몬스터는 그림이 있는 것으로 정한다.
#
# battlefield.py 의 monster_pool 은 Goblin/Orc/Skeleton/Ogre/Wolf/Dark Knight
# 인데, images 폴더에 있는 그림 여섯 장과 겹치는 것이 Goblin 하나뿐이다. 그림이
# 없는 몬스터를 내보내면 화면이 비므로, **그림에 맞춰 몬스터를 고르고 수치는
# monster_stats.py 에서 가장 가까운 것을 가져온다.** 정확히 맞는 것과 빌려 온
# 것을 아래 표에 그대로 적어 둔다.
#
#   화면 이름   수치 출처                 맞음?
#   GOBLIN      Goblin                    정확
#   SLIME       Ochre Jelly               같은 우즈 계열
#   DWARF       Guard                     도끼와 방패를 든 보병
#   TROLL       Troll                     정확
#   COBRA       Giant Poisonous Snake     정확
#   MIMIC       Doppelganger              변장해서 덮치는 것
# 씨앗을 뽑을 때만 쓴다 (--seed-monsters). 게임 수치의 정본은 gfx/monster.json 이다.
MONSTER_POOL = [
    ("GOBLIN", "Goblin", "02_goblin.png"),
    ("SLIME", "Ochre Jelly", "03_slime.png"),
    ("DWARF", "Guard", "04_dwarf.png"),
    ("TROLL", "Troll", "06_troll.png"),
    ("COBRA", "Giant Poisonous Snake", "23_cobra.png"),
    ("MIMIC", "Doppelganger", "41_mimic.png"),
]

# 피해 주사위는 enemy.py apply_type 을 따른다. 거기서 따로 정하지 않은 종류는
# 기본값 1d6 이 그대로 남는다. Goblin 은 명시적으로 1d6 이므로 여섯 종류 모두
# 1d6 이다. 세기 차이는 힘 보정(2 + 힘 보정)과 HP 에서 난다.
MON_DEFAULT_DAMAGE = (1, 6)
MON_DAMAGE = {"Goblin": (1, 6)}

# quest_sena.md 의 다섯 직업.
#
# 히트 다이스는 **문서(D&D 5판)** 를 따른다. race_job.py 는 다른 판이라 도적 d6,
# 마법사 d4 로 값이 다르다. BAB 진행은 원본 그대로 가져오고, 무사는 D&D 에 없는
# 직업이라 전사급(d10, good)으로 둔다.
#
# 능력치 보정은 hero.py apply_class_stats 의 방식(기본 10 에 더한다) 그대로다.
#
#   이름, 히트다이스, BAB, 약자, 캐스터, 능력치 보정, 피해 주사위
GAME_CLASSES = [
    ("FIGHTER", 10, "good",    "FI", 0, {"str": 6, "con": 4, "dex": 2}, (1, 10)),
    ("ROGUE",    8, "average", "RO", 0, {"dex": 8, "str": 2},           (1, 6)),
    ("WIZARD",   6, "poor",    "WI", 1, {"int": 8},                     (1, 6)),
    ("CLERIC",   8, "average", "CL", 1, {"wis": 6, "con": 4, "str": 4}, (1, 8)),
    ("MUSA",    10, "good",    "MU", 0, {"str": 4, "dex": 6},           (1, 10)),
]

# 주문 포인트. quest_sena.md 의 표(D&D 5e DMG p.288 변형 규칙)를 그대로 옮겼다.
# 색인이 레벨이므로 0 번은 쓰지 않는다.
MP_BY_LEVEL = [0, 4, 6, 14, 17, 27, 32, 38, 44, 57, 64]
MAX_LEVEL = len(MP_BY_LEVEL) - 1

# 직업별 특수 명령. quest_sena.md 의 명령 목록 중 **지금 있는 자료만으로 되는
# 것** 하나씩을 골랐다. 아이템/장비/상태이상은 그 체계 자체가 아직 없다.
#
#   SURGE  행동 폭증  - 이번 라운드에 한 번 더 움직인다
#   SNEAK  암습       - 피해 주사위 한 개 추가
#   BOLT   소마법     - MP 를 안 쓰고 지능으로 때린다 (마법사의 물리 공격은 약하다)
#   SMITE  신성 강타  - 물리 공격에 신성 피해를 더한다
#   KI     일도양단   - 주사위 두 개 추가, 대신 맞히기 어렵다
#
# 효과 번호는 questfight.asm 의 AtkMode 와 같다.
CLASS_SKILL = {
    "FIGHTER": ("SURGE", 1),
    "ROGUE":   ("SNEAK", 2),
    "WIZARD":  ("BOLT",  3),
    "CLERIC":  ("SMITE", 4),
    "MUSA":    ("KI",    5),
}

HERO_BASE_HP = 30       # constants.py
HERO_BASE_AC = 12       # constants.py

ABIL = ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]

# 이름 만들기. 원본에는 이름 생성기가 없다.
#
# 자음으로 시작하고 모음이 사이사이 들어가는 5~7 글자로 만든다 (godor, dalia 꼴).
# 무늬(C = 자음, V = 모음)를 하나 고르고 그 길이만큼 글자를 뽑는 방식이라
# **길이가 무늬로 정해진다** - 음절을 이어 붙이던 예전 방식은 3~12 글자로
# 들쭉날쭉했다.
NAME_CONS = "BDFGHKLMNPRSTVZ"     # 발음이 꼬이는 C J Q W X Y 는 뺐다
NAME_VOWELS = "AEIOU"
NAME_PATTERNS = [
    "CVCVC",        # 5  godor, dalir
    "CVCVV",        # 5  dalia
    "CVVCVC",       # 6  gaidor
    "CVCVCV",       # 6  dalira
    "CVCVVC",       # 6  dalias
    "CVCVCVC",      # 7  dalirok
]
NAME_PAT_W = max(len(p) for p in NAME_PATTERNS) + 1



def load_rules():
    """원본에서 뽑아 오고, 안 되면 남겨 둔 값을 쓴다."""
    if os.path.isdir(DND):
        sys.path.insert(0, DND)
        try:
            import race_job
            import monster_stats
            data = {
                "races": [
                    {"name": n,
                     "mods": [r["ability_modifiers"][a] for a in ABIL],
                     "speed": r["base_speed_ft"]}
                    for n, r in race_job.RACE_DATA.items()
                ],
                "classes": [
                    {"name": n, "hit_die": c["hit_die"], "bab": c["bab_progression"]}
                    for n, c in race_job.CLASS_DATA.items()
                ],
                "bab": {p: [race_job.calc_base_attack_bonus(l, p) for l in range(0, 21)]
                        for p in ("good", "average", "poor")},
            }
            with io.open(SNAPSHOT, "w", encoding="utf-8", newline="\n") as f:
                json.dump(data, f, ensure_ascii=False, indent=1)
            print("규칙을 %s 에서 가져왔다" % DND)
            return data
        finally:
            sys.path.pop(0)
    print("원본이 없어 %s 를 쓴다" % SNAPSHOT)
    return json.load(io.open(SNAPSHOT, encoding="utf-8"))


MONSTERS_JSON = os.path.join(HERE, "monster.json")


def seed_monsters():
    """dnd 에서 몬스터 수치를 다시 뽑아 gfx/monster.json 을 덮어쓴다.

    **평소에는 부르지 않는다.** monster.json 이 정본이라, 손으로 맞춰 둔 값이
    여기서 날아간다. 새 몬스터를 들일 때만 쓰고 그 뒤에 손으로 다듬는다.
    """
    if not os.path.isdir(DND):
        sys.exit("원본이 없습니다: %s" % DND)
    sys.path.insert(0, DND)
    try:
        import monster_stats
    finally:
        sys.path.pop(0)
    out = []
    for shown, src, img in MONSTER_POOL:
        st = monster_stats.MONSTER_STATS[src]
        cnt, sides = MON_DAMAGE.get(src, MON_DEFAULT_DAMAGE)
        hp = st["hp"]
        # 무리 크기. Bard`s Tale 처럼 약한 것은 떼로, 센 것은 하나만 나오게
        # 한다. 트롤(84) 이 셋 나오면 스무 라운드가 걸린다.
        out.append({"key": shown, "img": img, "ac": st["ac"], "hp": hp,
                    "str": st["strength"], "dex": st["dexterity"],
                    "dice": [cnt, sides],
                    "group_max": max(1, min(4, 60 // max(1, hp))),
                    "dnd_src": src})
    doc = json.load(io.open(MONSTERS_JSON, encoding="utf-8"))
    doc["monsters"] = out
    with io.open(MONSTERS_JSON, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    print("%s 에서 몬스터 %d 종을 다시 뽑아 %s 를 덮었습니다."
          % (DND, len(out), MONSTERS_JSON))


def load_monsters():
    """gfx/monster.json 이 정본이다. 수치가 바이트에 들어가는지 여기서 막는다."""
    doc = json.load(io.open(MONSTERS_JSON, encoding="utf-8"))
    mons, bad, seen = [], [], set()
    for n, m in enumerate(doc["monsters"]):
        key = m.get("key", "(이름 없음 %d 번째)" % n)
        if key in seen:
            bad.append("몬스터 열쇠 %s 가 두 번 나온다" % key)
        seen.add(key)
        cnt, sides = m.get("dice", [0, 0])
        vals = [("ac", m.get("ac")), ("hp", m.get("hp")), ("str", m.get("str")),
                ("dex", m.get("dex")), ("dice 개수", cnt), ("dice 면", sides),
                ("group_max", m.get("group_max"))]
        for label, v in vals:
            if not isinstance(v, int) or not 0 <= v <= 255:
                bad.append("%s 의 %s 가 %r 이다. 한 바이트에 들어가야 한다."
                           % (key, label, v))
        if not os.path.exists(os.path.join(HERE, "sprites", m.get("img", ""))):
            bad.append("%s 의 그림 %r 이 gfx/sprites/ 에 없다" % (key, m.get("img")))
        mons.append({"name": key, "img": m["img"], "src": m.get("dnd_src", "?"),
                     "ac": m["ac"], "hp": m["hp"],
                     "str": m["str"], "dex": m["dex"],
                     "dcnt": cnt, "dside": sides, "grp": m["group_max"]})
    if bad:
        sys.exit("gfx/monster.json 이 어긋났습니다:\n  " + "\n  ".join(bad))
    return mons


def abil_mod(score):
    """dice.py 의 ability_modifier. 파이썬 내림 나눗셈이라 8 -> -1, 7 -> -2."""
    return (score - 10) // 2


def pad(sname, n):
    s = sname.upper()[:n]
    return s + " " * (n - len(s))


def db_str(s):
    return "    db " + ", ".join(str(ord(c)) for c in s)


def db_sbytes(vals):
    """부호 있는 값을 0~255 로."""
    return "    db " + ", ".join(str(v & 0xFF) for v in vals)


# 팔레트는 gfx/quest_pal.py 가 정본이다. 예전에는 여기에 같은 값을 다시 적어
# 두고 "quest_convert.py 와 같아야 한다"는 주석만 달았는데, 한쪽만 고치면 조용히
# 어긋난다.
import quest_geom as G
from quest_geom import VIEW_W
from quest_pal import PAL333


def to888(c):
    return tuple(round(v * 255 / 7) for v in c)


# 양자화 규칙은 quest_pal 이 정본이다 - UI 전용 자리(파랑)를 후보에서 뺀다.
from quest_pal import nearest as nearest_idx


SPR_HDR = """; 이 파일은 gfx/quest_rules.py 가 만든다. 직접 고치지 말 것.
;
; 몬스터 그림 뱅크 %d. ASCII8 매퍼의 8KB 뱅크 하나이며 실행 중에는 0xA000 에
; 걸린다. 그림 여섯 장이 32KB 에 안 들어가서 ROM 을 128KB 로 늘렸다.
    DEVICE NOSLOT64K
    ORG 0xA000
"""


# 화면 모드. 아래 __main__ 이 인자를 보고 정한다.
#   4bpp  SCREEN 5. 몬스터는 64x64, 팔레트 16색을 여섯 마리가 나눠 쓴다.
#   8bpp  SCREEN 8. 몬스터는 96x96(던전 뷰포트를 꽉 채운다), 색은 각자 GRB332.
#
# 원본 그림이 64x64 뿐이라 키운다고 자세해지지는 않는다. 큰 것은 색이다 -
# 재 보니 원본 63색이 16색 팔레트에서는 14색으로 뭉개지고 GRB332 에서는 45색으로
# 남는다. 여섯 마리가 열여섯 칸을 나눠 쓰던 것이 없어진다.
BPP = 4
SPR_SIZE = 64
PRE = "quest"


def main():
    R = load_rules()
    import quest_font as F

    R["monsters"] = load_monsters()      # 정본은 gfx/monster.json

    L = []                  # 상수 - quest.asm 맨 앞에서 include
    D = []                  # 표 - ROM 데이터 자리에서 include
    cur = [L]

    def A(line):
        cur[0].append(line)

    def to_data():
        cur[0] = D

    def to_const():
        cur[0] = L

    A(";" + "-" * 76)
    A("; 이 파일은 gfx/quest_rules.py 가 만든다. 직접 고치지 말 것.")
    A(";")
    A("; D&D 규칙 자료를 D:/my/python/dnd 에서 가져와 표로 펼쳤다. Z80 에서 곱셈과")
    A("; 나눗셈을 피하려는 것이다. 특히 능력치 보정은 (점수-10)//2 인데 파이썬의")
    A("; 내림 나눗셈이라 음수 쪽이 -1, -2 로 떨어지고, BAB 의 average 는")
    A("; int(레벨*0.75) 라 레벨 1 에서 0 이다. 둘 다 흉내 내면 틀리기 쉬워 표로 굽는다.")
    A(";" + "-" * 76)
    A("")

    # ---- 메모리 배치 ----
    A("; --- 파티 기록 (한 명 32 바이트) ---------------------------------------")
    A("PARTY_N      equ %d" % PARTY_N)
    A("PARTY_STRIDE equ 32                 ; 2 의 거듭제곱이라 색인이 시프트로 끝난다")
    fields = ["P_NAME", "P_CLASS", "P_RACE", "P_STR", "P_DEX", "P_CON", "P_INT",
              "P_WIS", "P_CHA", "P_LEVEL", "P_HP", "P_MAXHP", "P_AC", "P_ATK",
              "P_DCNT", "P_DSIDE", "P_DMOD", "P_SPL", "P_MAXSPL", "P_GUARD",
              "P_WFAM"]
    NAME_LEN = 12
    off = 0
    for f in fields:
        A("%-12s equ %-3d" % (f, off) + ("             ; 이름 %d 글자" % NAME_LEN if f == "P_NAME" else ""))
        off += NAME_LEN if f == "P_NAME" else 1
    A("NAME_LEN     equ %d" % NAME_LEN)
    A("")
    A("; --- 몬스터 기록 (한 마리 4 바이트) -------------------------------------")
    A("; 종류 번호만 들고 나머지는 ROM 표에서 본다. 전투 중에 변하는 것은 HP 뿐이다.")
    A("MON_N        equ %d" % MON_N)
    A("MON_STRIDE   equ 4")
    A("M_TYPE       equ 0")
    A("M_HP         equ 1")
    A("M_MAXHP      equ 2")
    A("M_PAD        equ 3")
    A("")

    # ---- 화면 배치 ----
    A("; --- 하단 파티 칸 배치 (배경의 머리글 위치에 맞췄다) ---------------------")
    A("ROW_Y0       equ 152               ; 첫 줄 y")
    A("ROW_DY       equ 10                ; 8(글자 높이) + 2 dot. 줄 사이가 붙어 보여서 늘렸다.\n"
      "                                    ; 마지막 줄(6번)이 y=202~209, 그 아래 y=210 부터 패널 테두리다 - 꼭 맞는다.")
    A("COL_NUM      equ 2                 ; 번호")
    A(("COL_NAME     equ 10                ; 이름 (%d 글자). 번호 바로 뒤라서 1 dot 띄운다.\n"
       "                                    ; x 는 짝수여야 한다(TextAddr 가 바이트 단위로 찍는다) - 2px 가 최소 단위.")
      % NAME_LEN)
    A("COL_AC       equ 108               ; 이하 세 글자씩 오른쪽 맞춤")
    A("COL_HIT      equ 132")
    A("COL_PTS      equ 162")
    A("COL_SPL      equ 190")
    A("COL_SPTS     equ 214")
    A("COL_CL       equ 240               ; 직업 약자 두 글자")
    A("")
    A("; --- 오른쪽 메시지 칸 ---------------------------------------------------")
    A("MSG_X        equ 136")
    A("MSG_Y        equ 8")
    A("MSG_DY       equ 8                 ; 2 의 거듭제곱이라 곱셈이 시프트로 끝난다")
    A("MSG_ROWS     equ 13                ; 라운드 머리글 + 영웅 6 + 몬스터 5 + 여유")
    A("MSG_W        equ 17                ; 한 줄 글자 수 (136 + 17*6 = 238)")
    A("; 창을 위아래로 나눈다. 위는 전투 기록이 흘러가고 아래는 명령 메뉴다.")
    A("; 명령을 한 줄에 둘씩 놓아 메뉴가 3 줄이면 되므로 기록이 10 줄을 쓴다.")
    A("LOG_ROWS     equ 10")
    A("MENU_ROW     equ LOG_ROWS")
    A("MENU_ROWS    equ MSG_ROWS - LOG_ROWS")
    A("")

    # ---- 폰트 ----
    A("; --- 폰트 6x8, ASCII %d~%d ---------------------------------------------"
      % (F.FIRST, F.LAST))
    A("FONT_FIRST   equ %d" % F.FIRST)
    A("FONT_LAST    equ %d" % F.LAST)
    A("FONT_W       equ %d                 ; 다음 글자까지의 간격" % F.CELL_W)
    A("FONT_H       equ %d" % F.CELL_H)
    to_data()
    A("; --- 폰트 6x8 ---------------------------------------------------------")
    A("FontData:")
    fd = F.font_data()
    for i in range(0, len(fd), 16):
        A("    db " + ", ".join("0x%02X" % b for b in fd[i:i + 16]))
    A("")

    # ---- 능력치 보정표 ----
    A("; --- 능력치 보정 (dice.py ability_modifier). 점수 0~31 ------------------")
    A("AbilMod:")
    A(db_sbytes([abil_mod(s) for s in range(32)]))
    A("")

    # ---- BAB 표 ----
    A("; --- 기본 공격 보정 (race_job.py calc_base_attack_bonus). 레벨 0~20 -----")
    for p in ("good", "average", "poor"):
        A("Bab%s:" % p.capitalize())
        A("    db " + ", ".join(str(v) for v in R["bab"][p]))
    A("BabTables:")
    A("    dw BabGood, BabAverage, BabPoor")
    A("")

    # ---- 종족표 ----
    A("; --- 종족 (race_job.py RACE_DATA) --------------------------------------")
    A("; 능력치 보정 6 개(부호 있음) + 이름 8 글자")
    to_const()
    A("RACE_N       equ %d" % len(R["races"]))
    A("RACE_STRIDE  equ 14")
    to_data()
    A("RaceTable:")
    for r in R["races"]:
        A("    ; %s" % r["name"])
        A(db_sbytes(r["mods"]))
        A(db_str(pad(r["name"], 8)))
    A("")

    # ---- 직업표 ----
    A("; --- 직업 (quest_sena.md 의 다섯. BAB 만 race_job.py 에서 온다) ---------")
    A("; 히트다이스, BAB 진행(0 good/1 average/2 poor), 능력치 보정 6,")
    A("; 피해 주사위 개수/면, 캐스터 여부, 약자 2, 이름 10")
    to_const()
    A("CLASS_N      equ %d" % len(GAME_CLASSES))
    A("CLASS_STRIDE equ 23")
    A("C_HITDIE     equ 0")
    A("C_BAB        equ 1")
    A("C_MODS       equ 2")
    A("C_DCNT       equ 8")
    A("C_DSIDE      equ 9")
    A("C_CASTER     equ 10                ; MP 를 쓰는 직업인가")
    A("C_ABBREV     equ 11")
    A("C_NAME       equ 13")
    A("MAX_LEVEL    equ %d" % MAX_LEVEL)
    A("SKILL_STRIDE equ 11")
    A("SK_EFF       equ 0                 ; 효과 번호")
    A("SK_NAME      equ 1                 ; 0 으로 끝나는 이름")
    to_data()
    A("ClassTable:")
    babmap = {"good": 0, "average": 1, "poor": 2}
    for name, die, bab, ab, caster, bon, dmg in GAME_CLASSES:
        mods = [bon.get(k, 0) for k in ("str", "dex", "con", "int", "wis", "cha")]
        A("    ; %s" % name)
        A("    db %d, %d" % (die, babmap[bab]))
        A(db_sbytes(mods))
        A("    db %d, %d" % dmg)
        A("    db %d" % caster)
        A(db_str(ab))
        A(db_str(pad(name, 10)))
    A("")
    A("; 레벨별 최대 MP (quest_sena.md). 색인이 레벨이라 0 번은 안 쓴다.")
    A("MpTable:")
    A("    db " + ", ".join(str(v) for v in MP_BY_LEVEL))
    A("")
    A("; 직업별 특수 명령 - 효과 번호(AtkMode) + 이름 9 글자 + 끝표시 0")
    A("; 이름을 0 으로 끝내지 않으면 PutStr 이 다음 줄까지 읽어 버린다.")
    A("ClassSkill:")
    for name, _d, _b, _a, _c, _bon, _dmg in GAME_CLASSES:
        sk, eff = CLASS_SKILL[name]
        A("    db %d" % eff + "   ; %s" % name)
        A(db_str(pad(sk, 9)) + ", 0")
    A("")

    # ---- 몬스터표 ----
    A("; --- 몬스터. 수치를 고치려면 gfx/monster.json 을 고치세요. -------------")
    A("; AC, HP, 힘, 피해 개수/면, 무리 최대, 민첩, 그림, 이름 11")
    to_const()
    A("MONSTER_N    equ %d" % len(R["monsters"]))
    A("MON_TSTRIDE  equ 21")
    A("T_AC         equ 0")
    A("T_HP         equ 1")
    A("T_STR        equ 2")
    A("T_DCNT       equ 3")
    A("T_DSIDE      equ 4")
    A("T_MAXGRP     equ 5                 ; 한 번에 몇 마리까지 나오는가")
    A("T_DEX        equ 6                 ; 민첩 - 라운드당 행동 횟수를 정한다")
    A("T_SPRBANK    equ 7                 ; 그림이 든 ROM 뱅크")
    A("T_SPRADDR    equ 8                 ; 그 뱅크 안의 주소")
    A("T_NAME       equ 10")
    to_data()
    A("MonsterTable:")
    for i, m in enumerate(R["monsters"]):
        A("    ; %-6s  <- monster.json (dnd 원본 %s)" % (m["name"], m.get("src", "?")))
        A("    db %d, %d, %d, %d, %d, %d, %d" % (m["ac"], min(255, m["hp"]), m["str"],
                                                 m["dcnt"], m["dside"], m["grp"],
                                                 m["dex"]))
        # 한 마리일 때 쓰는 그림. 8bpp 는 대열이 정하는 폭(창의 75%)이고,
        # 4bpp 는 대열을 안 써서 원본 크기 그대로다.
        w1 = G.mon_layout(1)[2] if BPP == 8 else SPR_SIZE
        A("    db SPR_BANK_%d_W%d" % (i, w1))
        A("    dw SPR_ADDR_%d_W%d" % (i, w1))
        A(db_str(pad(m["name"], 11)))
    A("")

    # ---- 대열 ----
    #
    # 무리를 창에 어떻게 세우는지는 gfx/quest_geom.py 의 mon_layout 이 정본이고,
    # 여기서는 그것을 마릿수별 표로 펴서 굽기만 한다. Z80 은 나눗셈이 비싸서
    # "다섯 마리면 3 칸 2 줄" 같은 계산을 실행 중에 하고 싶지 않고, 무엇보다
    # 그리는 쪽과 고르는 쪽이 각자 계산하면 어긋난다.
    #
    # 4bpp 는 대열을 쓰지 않으므로 표를 내지 않는다 (quest_sprite.py 참고).
    if BPP == 8:
        maxgrp = max(m["grp"] for m in R["monsters"])
        bad = []
        for n in range(1, maxgrp + 1):
            cols, rows, w, top, step = G.mon_layout(n)
            band = G.ARROW_H + G.ARROW_GAP
            if VIEW_W % cols:
                bad.append("%d 마리는 %d 칸인데 창 폭 %d 가 안 나눠떨어진다"
                           % (n, cols, VIEW_W))
            if n > 1 and top - band < G.VIEW_Y:
                bad.append("%d 마리일 때 화살표가 창 위로 %d 픽셀 넘어간다"
                           % (n, G.VIEW_Y - (top - band)))
            bottom = top + (rows - 1) * step + w + G.DOT_STRIP
            if bottom > G.VIEW_Y + G.VIEW_H:
                bad.append("%d 마리일 때 대열(+점 띠)이 창 아래로 %d 픽셀 넘어간다"
                           % (n, bottom - (G.VIEW_Y + G.VIEW_H)))
            if cols * w > VIEW_W:
                bad.append("%d 마리는 %d 칸 x %d 픽셀이라 창 폭 %d 를 넘는다"
                           % (n, cols, w, VIEW_W))
            if G.DOT_ROW_W > w:
                bad.append("%d 마리일 때 칸이 %d 픽셀인데 점 줄이 %d 다"
                           % (n, w, G.DOT_ROW_W))
            if G.ARROW_W > w:
                bad.append("%d 마리일 때 칸이 %d 픽셀인데 화살표가 %d 다"
                           % (n, w, G.ARROW_W))
        if bad:
            sys.exit("대열이 창에 안 들어갑니다:\n  " + "\n  ".join(bad))

        lay = [G.mon_layout(n) for n in range(1, maxgrp + 1)]
        to_const()
        A("; --- 대열 (몬스터 여럿을 나란히) --------------------------------------")
        A("MON_SCALE_N  equ %d                 ; 한 번에 몇 마리까지 나오는가"
          % maxgrp)
        A("MON_SCALE_ST equ 3                 ; 한 칸 = 뱅크 1 + 주소 2")
        A("MON_MAX_COLS equ %d                 ; 가장 많이 늘어설 때의 칸 수"
          % max(l[0] for l in lay))
        A("ARROW_W      equ %d" % G.ARROW_W)
        A("ARROW_H      equ %d" % G.ARROW_H)
        A("ARROW_GAP    equ %d                 ; 화살표 끝과 머리 사이" % G.ARROW_GAP)
        A("DOT_N        equ %d                 ; HP 게이지 점 수 (하나가 20%%)" % G.DOT_N)
        A("DOT_W        equ %d" % G.DOT_W)
        A("DOT_H        equ %d" % G.DOT_H)
        A("DOT_GAP      equ %d" % G.DOT_GAP)
        A("DOT_TOP      equ %d                 ; 몬스터 아랫변과 점 사이" % G.DOT_TOP)
        A("DOT_ROW_W    equ %d                ; 점 다섯 줄의 폭" % G.DOT_ROW_W)
        to_data()
        A("; 종류마다 1..%d 마리일 때 쓸 그림. 색인은 종류*%d + (마릿수-1)."
          % (maxgrp, maxgrp))
        A("MonSprTab:")
        for i, m in enumerate(R["monsters"]):
            A("    ; %s (무리 최대 %d)" % (m["name"], m["grp"]))
            for n in range(1, maxgrp + 1):
                w = G.mon_layout(n if n <= m["grp"] else 1)[2]
                A("    db SPR_BANK_%d_W%d" % (i, w))
                A("    dw SPR_ADDR_%d_W%d" % (i, w))
        A("")
        A("; 맞은 자국. 무기 계열마다 다른 그림이고, 크기는 몬스터와 같다.")
        A("; 색인은 (계열*%d + 마릿수-1)*SLASH_N + 장, 한 칸이 뱅크 1 + 주소 2." % maxgrp)
        A("SLASH_GRP    equ %d                 ; 계열 하나가 도는 마릿수" % maxgrp)
        A("SlashTab:")
        for fam, famname in enumerate(("칼", "창", "활")):
            A("    ; --- %s 계열 ---" % famname)
            for n in range(1, maxgrp + 1):
                w = G.mon_layout(n)[2]
                A("    ; %d 마리 (%d 픽셀)" % (n, w))
                for k in range(3):
                    A("    db SLASH_BANK_F%d_W%d_F%d" % (fam, w, k))
                    A("    dw SLASH_ADDR_F%d_W%d_F%d" % (fam, w, k))
        # SlashPtr 이 AddA 로 8 비트 색인을 쓴다. 표가 256 바이트를 넘으면 조용히 감긴다.
        A("    ASSERT FAM_N * SLASH_GRP * SLASH_N * 3 <= 256")
        A("")
        A("; 마릿수별 배치. gfx/quest_geom.py 의 mon_layout 이 정한 값이다.")
        for label, k, note in (("MonSprW", 2, "한 마리의 폭(=높이)"),
                               ("MonColsTab", 0, "한 줄에 몇 칸"),
                               ("MonTopTab", 3, "첫 줄의 윗변 y"),
                               ("MonStepTab", 4, "줄 간격 (한 줄이면 0)")):
            A("%s:%s; %s" % (label, " " * max(1, 13 - len(label)), note))
            A("    db " + ", ".join(str(l[k]) for l in lay))
        A("MonLeftTab:   ; 첫 칸의 왼쪽 x. 칸이 창보다 좁으면(한 마리) 가운데로 민다")
        A("    db " + ", ".join(str(G.mon_left(n)) for n in range(1, maxgrp + 1)))
    A("")

    # ---- 이름 ----
    A("; --- 이름. 자음/모음과 무늬. 무늬 길이가 곧 이름 길이(5~7)다 -----------")
    to_const()
    A("NAME_CONS_N  equ %d" % len(NAME_CONS))
    A("NAME_VOW_N   equ %d" % len(NAME_VOWELS))
    A("NAME_PAT_N   equ %d" % len(NAME_PATTERNS))
    A("NAME_PAT_W   equ %d" % NAME_PAT_W)
    to_data()
    A("NameCons:")
    A('    db "%s"' % NAME_CONS)
    A("NameVow:")
    A('    db "%s"' % NAME_VOWELS)
    A("NamePat:")
    for pat in NAME_PATTERNS:
        A('    db "%s"%s, 0        ; %d 글자'
          % (pat, ", 0" * (NAME_PAT_W - 1 - len(pat)), len(pat)))
    to_const()
    A("")
    A("HERO_BASE_HP equ %d" % HERO_BASE_HP)
    A("HERO_BASE_AC equ %d" % HERO_BASE_AC)

    # ---- 몬스터 그림을 ROM 뱅크로 굽는다 --------------------------------
    import quest_sprite as SP
    SP.SPRITES = [(m["img"], m["name"], m["grp"]) for m in R["monsters"]]
    SP.set_mode(BPP, SPR_SIZE, PRE)
    banks, spr_const = SP.build_banks(PAL333, nearest_idx)
    to_const()
    A("")
    A("; --- 몬스터 그림이 어느 뱅크 어디에 있는가 -----------------------------")
    for line in spr_const:
        A(line)

    hdr = ("; 이 파일은 gfx/quest_rules.py 가 만든다. 직접 고치지 말 것.\n"
           "; 표는 db 라서 ORG 0x4000 뒤에서 include 해야 ROM 에 들어간다.\n\n")
    for bi, blines in enumerate(banks):
        with io.open(os.path.join(ROOT, "src", "%sspr%d.asm" % (PRE, bi)), "w",
                     encoding="utf-8", newline="\n") as f:
            f.write(SPR_HDR % bi + "\n".join(blines) + "\n")

    # **더 안 쓰는 뱅크 파일은 지운다.** 빌드 스크립트가 src/questspr*.asm 를
    # 글롭으로 집어 순서대로 이어 붙이므로, 그림이 작아져 뱅크가 줄었을 때
    # 옛 파일이 남아 있으면 그 뒤의 배경/정면벽/벽면 뱅크가 통째로 밀린다.
    # 화면이 새까맣게 뜨고, 어셈블은 멀쩡히 되기 때문에 원인을 찾기 어렵다.
    bi = len(banks)
    while True:
        stale = os.path.join(ROOT, "src", "%sspr%d.asm" % (PRE, bi))
        if not os.path.exists(stale):
            break
        os.remove(stale)
        print("  안 쓰는 뱅크 파일 지움: src/%sspr%d.asm" % (PRE, bi))
        bi += 1
    with io.open(os.path.join(ROOT, "src", PRE + "rules.asm"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    with io.open(os.path.join(ROOT, "src", PRE + "ruledata.asm"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write(hdr + "\n".join(D) + "\n")
    print("wrote src/questrules.asm (%d 줄), src/questruledata.asm (%d 줄)"
          % (len(L), len(D)))
    print("  종족 %d, 직업 %d, 몬스터 %d, 폰트 %d 바이트"
          % (len(R["races"]), len(GAME_CLASSES), len(R["monsters"]), len(fd)))


if __name__ == "__main__":
    if "--seed-monsters" in sys.argv:
        # 정본을 dnd 에서 다시 뽑아 gfx/monster.json 을 덮는다. 평소에는 안 쓴다.
        seed_monsters()
        sys.exit(0)
    if "--bpp" in sys.argv and sys.argv[sys.argv.index("--bpp") + 1] == "8":
        BPP, SPR_SIZE, PRE = 8, 96, "quest8"
    main()
