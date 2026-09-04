#!/usr/bin/env bash
# verify_quest_cover.ps1 의 리눅스 짝.
#
# 던전 한 프레임이 창을 빠짐없이 덮는가 (SCREEN 8). 창을 표식으로 가득 채우고
# 다시 그린 뒤, 표식이 남은 픽셀을 센다. 남으면 그 자리를 아무도 안 그린
# 것이고, 거기에는 앞 프레임 조각이 남는다. 손으로 만든 통로(막힘 1~5)와
# 진짜 지도를 걸어 다니는 두 가지로 본다. gfx/quest_cover.py 참고.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/tools.sh"
cd "$ROOT"

export PYTHONIOENCODING=utf-8
"$ROOT/build_quest3.sh"

WORK="$ROOT/build/cover"
mkdir -p "$WORK"
rm -f "$WORK"/*.bin "$WORK"/*.txt "$WORK"/*.tcl "$WORK"/*.png

python3 gfx/quest_cover.py tcl "$WORK"
python3 gfx/quest_cover.py livetcl "$WORK"

for tcl in "$WORK"/*.tcl; do
    "$OPENMSX_HEADLESS" -machine "$MSX_MACHINE" -cart "$ROOT/build/quest3.rom" \
        -script "$tcl" >/dev/null 2>&1
done

python3 gfx/quest_cover.py check "$WORK"
python3 gfx/quest_cover.py livecheck "$WORK"
