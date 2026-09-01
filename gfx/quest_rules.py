"""D&D 규칙 자료를 D:/my/python/dnd 에서 가져와 asm 표로 굽는다.

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

# hero.py apply_class_stats - 기본 10 에 더하는 값
CLASS_BONUS = {
    "Fighter": {"str": 6, "con": 4, "dex": 2, "dmg": (1, 10)},
    "Rogue":   {"dex": 8, "str": 2, "dmg": (2, 6)},
    "Wizard":  {"int": 8, "dmg": (2, 6)},
    "Ranger":  {"dex": 6, "wis": 4, "dmg": (1, 10)},
    "Cleric":  {"wis": 6, "con": 4, "str": 4},
}

HERO_BASE_HP = 30       # constants.py
HERO_BASE_AC = 12       # constants.py

ABIL = ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]

# 이름 만들기. 원본에는 이름 생성기가 없다 - 참고 화면의 MORILDRANE 같은 이름은
# 원래 Bard's Tale 것이다. 그 분위기에 맞춰 음절을 짜 넣었다.
NAME_HEAD = ["MOR", "KRO", "BLOOD", "PHAN", "FAS", "THAL", "GRIM", "VOR",
             "ELD", "SHAR", "DUR", "GAL", "MAR", "ZOR", "BEL", "HAR"]
NAME_MID = ["IL", "AN", "OR", "UL", "AR", "EN", "YR", ""]
NAME_TAIL = ["DRANE", "LM", "WULF", "TYR", "HOR", "DUR", "GAR", "NIS",
             "MOR", "RIK", "THAS", "VEN", "DAR", "LOK", "RETH", "SON"]

CLASS_ABBREV = {
    "Barbarian": "BA", "Bard": "BD", "Cleric": "CL", "Druid": "DR",
    "Fighter": "FI", "Monk": "MO", "Paladin": "PA", "Ranger": "RA",
    "Rogue": "RO", "Sorcerer": "SO", "Wizard": "WI",
}


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
                "monsters": [],
            }
            for shown, src, img in MONSTER_POOL:
                st = monster_stats.MONSTER_STATS[src]
                cnt, sides = MON_DAMAGE.get(src, MON_DEFAULT_DAMAGE)
                hp = st["hp"]
                # 무리 크기. Bard`s Tale 처럼 약한 것은 떼로, 센 것은 하나만
                # 나오게 한다. 트롤(84) 이 셋 나오면 스무 라운드가 걸린다.
                grp = max(1, min(4, 60 // max(1, hp)))
                data["monsters"].append({"name": shown, "src": src, "img": img,
                                         "ac": st["ac"], "hp": hp,
                                         "str": st["strength"], "dcnt": cnt,
                                         "dside": sides, "grp": grp})
            with io.open(SNAPSHOT, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=1)
            print("규칙을 %s 에서 가져왔다" % DND)
            return data
        finally:
            sys.path.pop(0)
    print("원본이 없어 %s 를 쓴다" % SNAPSHOT)
    return json.load(io.open(SNAPSHOT, encoding="utf-8"))


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


def main():
    R = load_rules()
    import quest_font as F

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
              "P_DCNT", "P_DSIDE", "P_DMOD", "P_SPL", "P_MAXSPL"]
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
    A("; --- 직업 (race_job.py CLASS_DATA + hero.py apply_class_stats) ----------")
    A("; 히트다이스, BAB 진행(0 good/1 average/2 poor), 능력치 보정 6,")
    A("; 피해 주사위 개수/면, 약자 2, 이름 10")
    to_const()
    A("CLASS_N      equ %d" % len(R["classes"]))
    A("CLASS_STRIDE equ 22")
    A("C_HITDIE     equ 0")
    A("C_BAB        equ 1")
    A("C_MODS       equ 2")
    A("C_DCNT       equ 8")
    A("C_DSIDE      equ 9")
    A("C_ABBREV     equ 10")
    A("C_NAME       equ 12")
    to_data()
    A("ClassTable:")
    babmap = {"good": 0, "average": 1, "poor": 2}
    for c in R["classes"]:
        bon = CLASS_BONUS.get(c["name"], {})
        mods = [bon.get(k, 0) for k in ("str", "dex", "con", "int", "wis", "cha")]
        dcnt, dside = bon.get("dmg", (1, max(4, c["hit_die"])))
        A("    ; %s" % c["name"])
        A("    db %d, %d" % (c["hit_die"], babmap[c["bab"]]))
        A(db_sbytes(mods))
        A("    db %d, %d" % (dcnt, dside))
        A(db_str(CLASS_ABBREV[c["name"]]))
        A(db_str(pad(c["name"], 10)))
    A("")

    # ---- 몬스터표 ----
    A("; --- 몬스터 (battlefield.py monster_pool + monster_stats.py) ------------")
    A("; AC, HP, 힘, 피해 개수/면, 이름 12")
    to_const()
    A("MONSTER_N    equ %d" % len(R["monsters"]))
    A("MON_TSTRIDE  equ 20")
    A("T_AC         equ 0")
    A("T_HP         equ 1")
    A("T_STR        equ 2")
    A("T_DCNT       equ 3")
    A("T_DSIDE      equ 4")
    A("T_MAXGRP     equ 5                 ; 한 번에 몇 마리까지 나오는가")
    A("T_SPRBANK    equ 6                 ; 그림이 든 ROM 뱅크")
    A("T_SPRADDR    equ 7                 ; 그 뱅크 안의 주소")
    A("T_NAME       equ 9")
    to_data()
    A("MonsterTable:")
    for i, m in enumerate(R["monsters"]):
        A("    ; %-6s  <- monster_stats.py %s" % (m["name"], m.get("src", m["name"])))
        A("    db %d, %d, %d, %d, %d, %d" % (m["ac"], min(255, m["hp"]), m["str"],
                                             m["dcnt"], m["dside"], m["grp"]))
        A("    db SPR_BANK_%d" % i)
        A("    dw SPR_ADDR_%d" % i)
        A(db_str(pad(m["name"], 11)))
    A("")

    # ---- 이름 음절 ----
    A("; --- 이름 음절. 원본에는 이름 생성기가 없어 새로 넣었다 ------------------")
    for tag, arr, w in (("Head", NAME_HEAD, 5), ("Mid", NAME_MID, 2), ("Tail", NAME_TAIL, 5)):
        to_const()
        A("SYL_%s_N     equ %d" % (tag.upper(), len(arr)))
        A("SYL_%s_W     equ %d" % (tag.upper(), w))
        to_data()
        A("Syl%s:" % tag)
        for syl in arr:
            A(db_str(pad(syl, w)) + "   ; %s" % (syl or "-"))
    to_const()
    A("")
    A("HERO_BASE_HP equ %d" % HERO_BASE_HP)
    A("HERO_BASE_AC equ %d" % HERO_BASE_AC)

    # ---- 몬스터 그림을 ROM 뱅크로 굽는다 --------------------------------
    import quest_sprite as SP
    SP.SPRITES = [(m["img"], m["name"]) for m in R["monsters"]]
    banks, spr_const = SP.build_banks(PAL333, nearest_idx)
    to_const()
    A("")
    A("; --- 몬스터 그림이 어느 뱅크 어디에 있는가 -----------------------------")
    for line in spr_const:
        A(line)

    hdr = ("; 이 파일은 gfx/quest_rules.py 가 만든다. 직접 고치지 말 것.\n"
           "; 표는 db 라서 ORG 0x4000 뒤에서 include 해야 ROM 에 들어간다.\n\n")
    for bi, blines in enumerate(banks):
        with io.open(os.path.join(ROOT, "src", "questspr%d.asm" % bi), "w",
                     encoding="utf-8", newline="\n") as f:
            f.write(SPR_HDR % bi + "\n".join(blines) + "\n")
    with io.open(os.path.join(ROOT, "src", "questrules.asm"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    with io.open(os.path.join(ROOT, "src", "questruledata.asm"), "w",
                 encoding="utf-8", newline="\n") as f:
        f.write(hdr + "\n".join(D) + "\n")
    print("wrote src/questrules.asm (%d 줄), src/questruledata.asm (%d 줄)"
          % (len(L), len(D)))
    print("  종족 %d, 직업 %d, 몬스터 %d, 폰트 %d 바이트"
          % (len(R["races"]), len(R["classes"]), len(R["monsters"]), len(fd)))


if __name__ == "__main__":
    main()
