# tools.ps1 의 리눅스 짝. build*.sh 가 source 한다.
#
# 윈도우 쪽은 D:\my\8bit\msx\tools 를 보고, 리눅스 쪽은 이 저장소 바깥의
# ../tools 를 본다. 둘 다 다른 MSX 프로젝트와 도구를 같이 쓰려는 것이다.
#
# openMSX 는 압축을 푼 .deb 라 실행 파일을 직접 부르지 않고 환경 변수를
# 잡아 주는 래퍼(run-openmsx*)를 쓴다.

TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools" && pwd)"

SJASMPLUS="$TOOLS_ROOT/sjasmplus/sjasmplus"
OPENMSX="$TOOLS_ROOT/run-openmsx-gui"
OPENMSX_HEADLESS="$TOOLS_ROOT/run-openmsx-headless"
MSX_MACHINE="C-BIOS_MSX2"

for t in "$SJASMPLUS" "$OPENMSX" "$OPENMSX_HEADLESS"; do
    [ -x "$t" ] || { echo "tool not found: $t" >&2; return 1 2>/dev/null || exit 1; }
done

# 여기 openMSX 는 19.1 이라 문서(21.0)와 두 군데 다르다.
#   - screenshot 에 -size 옵션이 없다. `screenshot -raw <파일>` 로 쓴다.
#   - 128KB 롬에 -romtype ASCII8 을 붙여도 정상 부팅한다(21.0 에서는 실패한다고
#     doc/random_map.md 에 적혀 있다). 자동 판정으로 두면 양쪽 다 문제없다.
