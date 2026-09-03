#!/usr/bin/env bash
# build_quest3.ps1 의 리눅스 짝.
# src/quest3.asm 를 build/quest3.rom (128KB ASCII8) 으로 만든다. **지금 쓰는 판.**
#
# quest.rom 의 SCREEN 8 (GRAPHIC 7, 256색) 판이다. quest3.asm 이 SCREEN8 을
# define 하므로 하위 파일들이 IFDEF 로 8bpp 자료(quest8*)를 고르고, 본체는
# build/quest8main.bin 으로 떨어진다 (4bpp 판은 questmain.bin).
#
#   뱅크 0~2   본체 코드와 자료      (0x4000-0x9FFF 고정)
#   그 뒤로     몬스터 그림 -> 배경 -> 정면 벽 -> 벽면 런
#
# 뱅크 번호는 자료 크기에 따라 달라지므로 어셈블러가 계산한다
# (quest8const.asm 의 BG_BANK / FRONT_BANK / RUN_BANK0). 그러니 아래 순서를
# 바꾸면 롬 안의 자리와 코드가 보는 뱅크 번호가 어긋난다.
set -euo pipefail

# --title 을 주면 타이틀 화면이 들어간다. 안 주면 부팅하자마자 게임이다
# (테스트할 때 매번 넘기지 않으려고). 그림이 13 뱅크라 롬이 256KB 가 된다.
TITLE=0
for a in "$@"; do [ "$a" = "--title" ] && TITLE=1; done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/tools.sh"

cd "$ROOT"
mkdir -p build

# 손으로 고치는 자료를 롬 표로 굽는다. 셋 다 1 초 안에 끝난다.
#
#   gfx/message.json  게임에 나오는 글 (한글은 달무리 8x8 을 여기서 조합한다)
#   gfx/items.json    무기/방어구/소모품 한 표
#   gfx/monster.json  몬스터 수치
#
# 값이 어긋나면 (양피지 폭을 넘거나, 한 바이트에 안 들어가거나, 없는 열쇠를
# 가리키거나) **여기서 빌드가 멈춘다.** SCREEN 8 에는 픽셀 오라클이 없어서,
# 안 막으면 화면을 눈으로 보다가 한참 뒤에 발견하게 된다.
#
# 벽면 픽셀(quest_convert.py)은 몇 분 걸리므로 여기 없다. 기하나 텍스처를
# 고쳤을 때만 손으로 돌린다.
python3 gfx/quest_msg.py
python3 gfx/quest_gear.py
python3 gfx/quest_rules.py --bpp 8
[ "$TITLE" = 1 ] && python3 gfx/quest_title.py
[ "$TITLE" = 1 ] && python3 gfx/psg_music.py title

DEFS=()
[ "$TITLE" = 1 ] && DEFS+=(-DTITLE)
"$SJASMPLUS" --msg=war "${DEFS[@]+"${DEFS[@]}"}" --sym="build/quest3.sym" --lst="build/quest3.lst" "src/quest3.asm"

# 글롭 순서를 PowerShell 의 Sort-Object Name 과 맞추려고 LC_ALL=C 로 고정한다.
# quest8* 만 집는다 - quest* 로 집으면 4bpp 판 뱅크까지 딸려 들어온다.
export LC_ALL=C
bankFiles=(src/quest8spr*.asm src/quest8bgbank*.asm src/quest8frontbank*.asm src/quest8runbank*.asm)
# 타이틀 그림은 게임 뱅크 뒤에 붙는다 (TITLE_BANK0 = RUN_BANK0 + RUN_BANKS).
[ "$TITLE" = 1 ] && bankFiles+=(src/quest8titlebank*.asm src/quest8musicbank*.asm)
echo "뱅크 3 부터: ${bankFiles[*]}"

for f in "${bankFiles[@]}"; do
    "$SJASMPLUS" --msg=war "$f"
done

BANK=8192
# 128KB 로는 게임 14 뱅크 + 타이틀 13 뱅크가 안 들어간다. ASCII8 은 뱅크 번호가
# 8 비트라 2MB 까지 되고, 256KB 는 openMSX 에서 확인했다.
if [ "$TITLE" = 1 ]; then TOTAL=262144; else TOTAL=131072; fi
ROM=build/quest3.rom

mainSize=$(stat -c%s build/quest8main.bin)
[ "$mainSize" -eq $((3 * BANK)) ] || { echo "quest8main.bin 이 $mainSize 바이트다 (24576 이어야 함)" >&2; exit 1; }

dd if=/dev/zero of="$ROM" bs=$BANK count=$((TOTAL / BANK)) status=none
dd if=build/quest8main.bin of="$ROM" bs=$BANK seek=0 conv=notrunc status=none

bankIndex=3
for f in "${bankFiles[@]}"; do
    name=$(basename "$f" .asm)
    size=$(stat -c%s "build/$name.bin")
    [ "$size" -eq $BANK ] || { echo "$name.bin 이 $size 바이트다 (8192 이어야 함)" >&2; exit 1; }
    [ $(((bankIndex + 1) * BANK)) -le $TOTAL ] || { echo "롬 크기($TOTAL)를 넘었습니다 (뱅크 $bankIndex)" >&2; exit 1; }
    dd if="build/$name.bin" of="$ROM" bs=$BANK seek=$bankIndex conv=notrunc status=none
    bankIndex=$((bankIndex + 1))
done

if [ "$TITLE" = 1 ]; then WHAT="타이틀 있음"; else WHAT="타이틀 없음 - 바로 게임"; fi
echo "built: $ROOT/$ROM ($TOTAL bytes, 뱅크 0~$((bankIndex - 1)) 사용, $WHAT)"
