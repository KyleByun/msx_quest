#!/usr/bin/env bash
# verify_quest_row.ps1 의 리눅스 짝.
#
# 대열을 확인한다 - 무리를 여러 마리로 세우고 칠 상대를 고르는 것, 그리고
# 맞은 자국(SCREEN 8). 던전만 그린 화면과 대열을 얹은 화면의 차이를 오라클로
# 쓴다. 칸마다 달라진 픽셀을 세면 그 칸에 몬스터가 섰는지가 나온다.
# gfx/quest_row.py 참고.
#
# .ps1 은 uv 로 파이썬을 부르고 -romtype ASCII8 을 붙이는데, 여기서는 시스템
# 파이썬을 쓰고 romtype 은 자동 판정에 맡긴다 (tools.sh 의 설명 참고).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/tools.sh"
cd "$ROOT"

export PYTHONIOENCODING=utf-8
"$ROOT/build_quest3.sh"

WORK="$ROOT/build/row"
mkdir -p "$WORK"
# tcl 까지 지운다. 손으로 만들어 둔 것이 남아 있으면 아래 고리가 그것도
# 돌려 보고 결과 파일이 없다고 멈춘다.
rm -f "$WORK"/*.bin "$WORK"/*.txt "$WORK"/*.tcl "$WORK"/*.png

python3 gfx/quest_row.py tcl "$WORK"

for tcl in "$WORK"/*.tcl; do
    name="$(basename "$tcl" .tcl)"
    "$OPENMSX_HEADLESS" -machine "$MSX_MACHINE" -cart "$ROOT/build/quest3.rom" \
        -script "$tcl" >/dev/null 2>&1
    [ -f "$WORK/$name.txt" ] || { echo "$name : 결과가 안 나왔습니다" >&2; exit 1; }
done

python3 gfx/quest_row.py check "$WORK"
