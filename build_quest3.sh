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

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/tools.sh"

cd "$ROOT"
mkdir -p build

# 게임에 나오는 글을 굽는다. gfx/message.json 을 고치면 여기서 롬에 반영된다.
# 한글은 달무리 8x8 을 빌드할 때 미리 조합한다(assets/dalmoori, Apache 2.0).
# 폭이 양피지 창을 넘으면 여기서 빌드가 멈춘다.
# 윈도우에서 .ps1 로 빌드한다면 이 단계를 그쪽에도 넣어야 한다.
python3 gfx/quest_msg.py

"$SJASMPLUS" --msg=war --sym="build/quest3.sym" --lst="build/quest3.lst" "src/quest3.asm"

# 글롭 순서를 PowerShell 의 Sort-Object Name 과 맞추려고 LC_ALL=C 로 고정한다.
# quest8* 만 집는다 - quest* 로 집으면 4bpp 판 뱅크까지 딸려 들어온다.
export LC_ALL=C
bankFiles=(src/quest8spr*.asm src/quest8bgbank*.asm src/quest8frontbank*.asm src/quest8runbank*.asm)
echo "뱅크 3 부터: ${bankFiles[*]}"

for f in "${bankFiles[@]}"; do
    "$SJASMPLUS" --msg=war "$f"
done

BANK=8192
TOTAL=131072
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
    [ $(((bankIndex + 1) * BANK)) -le $TOTAL ] || { echo "128KB 를 넘었습니다 (뱅크 $bankIndex)" >&2; exit 1; }
    dd if="build/$name.bin" of="$ROM" bs=$BANK seek=$bankIndex conv=notrunc status=none
    bankIndex=$((bankIndex + 1))
done

echo "built: $ROOT/$ROM ($TOTAL bytes, 뱅크 0~$((bankIndex - 1)) 사용 = $((bankIndex * BANK)) 바이트)"
