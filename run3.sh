#!/usr/bin/env bash
# run_quest3.ps1 의 리눅스 짝.
# build/quest3.rom (SCREEN 8, 256색 - 지금 쓰는 판) 을 만들고 창으로 띄운다.
#
#   ./run3.sh              빌드하고 띄운다 (타이틀 없음 - 바로 게임)
#   ./run3.sh --title      타이틀까지 넣어 빌드하고 띄운다
#   ./run3.sh --no-build   이미 만들어 둔 롬을 그대로 띄운다
#
# 여기 openMSX 는 19.1 이라 -romtype 없이 자동 판정에 맡긴다. .ps1 은
# ASCII8 을 붙이는데 이 판에서는 붙이든 말든 같고, doc/random_map.md 에는
# 21.0 에서 붙이면 부팅이 실패한다고 적혀 있다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/tools.sh"

cd "$ROOT"

NOBUILD=0
TITLE=""
for a in "$@"; do
    case "$a" in
        --no-build) NOBUILD=1 ;;
        --title)    TITLE="--title" ;;
        *) echo "모르는 인자: $a  (쓸 수 있는 것은 --no-build / --title)" >&2; exit 1 ;;
    esac
done

if [ "$NOBUILD" = 1 ]; then
    # --title 은 빌드에만 쓰는 것이라 --no-build 와 같이 주면 뜻이 없다.
    [ -n "$TITLE" ] && echo "--no-build 라서 --title 은 무시합니다"
    [ -f "$ROOT/build/quest3.rom" ] || {
        echo "build/quest3.rom 이 없습니다. --no-build 를 빼고 한 번 빌드하세요." >&2
        exit 1
    }
    echo "빌드 없이 띄웁니다: build/quest3.rom"
else
    "$ROOT/build_quest3.sh" ${TITLE:+$TITLE}
fi

# 창을 닫으면 돌아온다.
exec "$OPENMSX" -machine "$MSX_MACHINE" -cart "$ROOT/build/quest3.rom"
