#!/usr/bin/env bash
# build.ps1 의 리눅스 짝. src/main.asm 을 build/game.rom (16KB 카트리지) 으로 만든다.
#
# 16KB 롬은 한 번에 끝난다 - main.asm 끝의 SAVEBIN 이 0x4000 부터 16KB 를
# 잘라 파일로 쓴다. 어셈블러가 롬 파일을 자동으로 만들어 주지 않는다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$ROOT/tools.sh"

# SAVEBIN 의 "build/..." 는 소스 위치가 아니라 sjasmplus 의 현재 폴더 기준이다.
cd "$ROOT"
mkdir -p build

"$SJASMPLUS" --msg=war --sym="build/game.sym" --lst="build/game.lst" "src/main.asm"

size=$(stat -c%s build/game.rom)
[ "$size" -eq 16384 ] || { echo "game.rom 이 $size 바이트다 (16384 이어야 함)" >&2; exit 1; }
echo "built: $ROOT/build/game.rom ($size bytes)"
