#!/usr/bin/env bash
# build_quest.ps1 의 리눅스 짝.
# src/quest.asm 를 build/quest.rom (128KB ASCII8 카트리지 이미지) 으로 만든다.
#
# SCREEN 5 (4bpp) 보관용 판이다. 지금 쓰는 것은 build_quest3.sh 쪽이지만,
# verify_quest_sides.ps1 의 픽셀 단위 오라클이 4bpp 에서만 돌기 때문에 공유
# 하위 파일을 고쳤을 때 회귀를 잡으려면 이쪽도 빌드해야 한다.
#
# ROM 안에서 8KB 뱅크가 이렇게 놓인다.
#   뱅크 0~2  본체 코드와 자료   (실행 중 0x4000-0x9FFF 에 고정)
#   그 뒤로    몬스터 그림 -> 배경 RLE -> 정면 벽 -> 벽면 런
#
# 뱅크 3 부터는 모두 실행 중에 0xA000 에 놓이므로 한 번에 어셈블할 수 없다.
# 파일마다 따로 어셈블해서 여기서 이어 붙인다.
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

"$SJASMPLUS" --msg=war --sym="build/quest.sym" --lst="build/quest.lst" "src/quest.asm"

# 0xA000 창에 걸리는 뱅크들. 이 순서가 곧 뱅크 번호(3 부터)이고,
# src/quest.asm 의 BG_BANK / FRONT_BANK / RUN_BANK0 계산과 같아야 한다.
# 글롭 순서를 PowerShell 의 Sort-Object Name 과 맞추려고 LC_ALL=C 로 고정한다.
export LC_ALL=C
bankFiles=(src/questspr*.asm src/questbgbank*.asm src/questfrontbank*.asm src/questrunbank*.asm)
echo "뱅크 3 부터: ${bankFiles[*]}"

for f in "${bankFiles[@]}"; do
    "$SJASMPLUS" --msg=war "$f"
done

BANK=8192
TOTAL=131072
ROM=build/quest.rom

# 본체가 24KB 를 넘으면 조용히 뱅크 3 을 밀어내서 그림이 깨진다.
mainSize=$(stat -c%s build/questmain.bin)
[ "$mainSize" -eq $((3 * BANK)) ] || { echo "questmain.bin 이 $mainSize 바이트다 (24576 이어야 함)" >&2; exit 1; }

dd if=/dev/zero of="$ROM" bs=$BANK count=$((TOTAL / BANK)) status=none
dd if=build/questmain.bin of="$ROM" bs=$BANK seek=0 conv=notrunc status=none

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
