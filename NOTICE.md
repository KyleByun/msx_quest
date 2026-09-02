# 가져다 쓴 것

## 달무리 글꼴 (`assets/dalmoori/`)

한글 8x8 글리프 원본입니다. **Apache License 2.0** — 전문은
[`assets/dalmoori/LICENSE`](assets/dalmoori/LICENSE), 원저작자의 설명은
[`assets/dalmoori/README.upstream.md`](assets/dalmoori/README.upstream.md) 에 있습니다.

`gfx/dalmoori.py` 는 달무리의 타입스크립트 조합기(`generator/src/core` 의
`ascii-font.ts`, `hangul-phoneme.ts`, `combine.ts`)를 파이썬으로 옮긴 것으로,
`../hangul` 저장소에서 가져왔습니다. 같은 Apache 2.0 을 따릅니다.

> **원본 그대로는 아닙니다.** 달무리의 조합기는 파일 목록을 정렬하지 않고 읽어서,
> 조건을 통과하는 후보가 여럿일 때 파일시스템 순서가 결과를 가릅니다. 여기서는
> 빌드가 재현되도록 이름 정렬 순서로 고정했습니다. 달무리의 규칙 안에 있는
> 결과지만 공식 배포판과 글자별로 다를 수 있습니다.

빌드할 때 `gfx/quest_msg.py` 가 `gfx/message.json` 에 실제로 쓰인 글자만 조합해
8바이트 비트맵으로 굽습니다. 롬에는 그 비트맵만 들어갑니다.

## 그 밖

배경과 화면 배치는 Bard's Tale 화면을 참고했고, 몬스터 그림과 슈팅 게임
그래픽은 개인 습작 프로젝트에서 가져왔습니다. **원저작자가 따로 있는 소재가
섞여 있으므로 학습·시연 목적으로만 봐 주세요** (`README.md` 의 "참고 자료 출처").
