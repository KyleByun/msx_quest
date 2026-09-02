#!/usr/bin/env bash
# run_quest3.ps1 의 리눅스 짝.
# build/quest3.rom (SCREEN 8, 256색 - 지금 쓰는 판) 을 만들고 창으로 띄운다.
#
# --no-build 를 주면 이미 만들어 둔 롬을 그대로 띄운다.
#
# 여기 openMSX 는 19.1 이라 -romtype 없이 자동 판정에 맡긴다. .ps1 은
# ASCII8 을 붙이는데 이 판에서는 붙이든 말든 같고, doc/random_map.md 에는
# 21.0 에서 붙이면 부팅이 실패한다고 적혀 있다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/tools.sh"

cd "$ROOT"

if [ "${1:-}" != "--no-build" ]; then
    "$ROOT/build_quest3.sh"
fi

# 창을 닫으면 돌아온다.
exec "$OPENMSX" -machine "$MSX_MACHINE" -cart "$ROOT/build/quest3.rom"
