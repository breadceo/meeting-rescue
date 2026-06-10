# 한글 용어 후보 캘리브레이션 스파이크

날짜: 2026-06-10

## 범위

로컬 Meeting Rescue transcript를 사용해 한글 fuzzy matching 기반 용어 후보의 초기 threshold를 잡았다.

입력 corpus:

- 폴더: `/Users/ethan/Documents/Recordings`
- 전체 파일: `.txt` transcript 327개
- 스파이크 샘플: 최신 transcript 120개

스파이크 결과에는 raw transcript excerpt를 저장하지 않았다. 후보 문자열, 출현 회의 수, 출현 횟수, 주변 context overlap, similarity score만 기록했다.

## 후보 추출 관찰

유용한 한글 후보는 단일 단어보다 짧은 도메인 phrase에서 많이 나왔다.

- `문의 방식별 전환율` / `문의 방식별 전환률`
- `호갱노노 워너비` / `호갱노노 워너빌`
- `중개사 응답률 채팅` / `중계사 응답률 채팅`
- `아이오에스 마케팅` / `아이유에스 마케팅`
- `데일리 스크럼` / `데일리스크람`
- `워너빌 통합 광고` / `워너비 통합 광고`
- `프로젝트 트래킹` / `프로젝트 트레킹`
- `컴비네이션` / `콤비네이션`
- `피처 플래그` / `퓨처 플래그`
- `클로드 코드` / `크로드 코드`

따라서 한글 glossary suggestion은 token 단위만 보면 부족하고, 짧은 phrase 추출을 포함해야 한다.

## Scoring Signal

스파이크에서 사용한 weighted score:

- 음절 edit similarity: 35%
- 한글 자모 edit similarity: 35%
- 음절 bigram Dice similarity: 20%
- 초성 similarity: 10%

주변 context overlap은 주 점수가 아니라 guard로 사용했다.

## Noise 유형

강한 guard 없이 similarity만 보면 높은 점수의 false positive가 많이 나온다.

- 어미 변형: `같아` / `같고`, `싶어` / `싶기`, `필요하다` / `필요하다고`
- 조사/확장 변형: `쪽에` / `쪽에서`, `신청` / `신청자`
- 일반 회의 발화: `확인해` / `확인해서`, `정리해` / `정리해서`
- 용어 alias가 아닌 의미 인접 표현: `현금영수증 발급` / `현금영수증 발행`

한글 후보는 similarity ranking 전에 candidate-quality gate가 필요하다.

## 초기 Threshold 제안

두 lane으로 시작한다.

1. High-confidence lane:
   - score >= 0.85
   - 양쪽 후보 모두 2개 이상 회의에서 출현
   - 문법 어미/조사 suffix로만 달라지는 후보 제외
   - context overlap이 낮아도 노출 가능

2. Context-confirmed lane:
   - score >= 0.80
   - context overlap >= 0.12
   - 두 후보 합산 회의 support >= 5
   - 한쪽 후보가 3개 이상 회의 또는 4회 이상 출현

0.80 아래에도 유용한 예시는 있지만 noise가 빠르게 늘어서 첫 제품 버전에서는 기본 노출하지 않는 것이 낫다.

## 제품 반영

한글 후보는 자동 적용하지 않고, 사용자가 canonical을 확인/수정한 뒤 accepted glossary term으로 승격해야 한다.

권장 UI 형태:

```text
후보: 중개사 응답률 채팅 / 중계사 응답률 채팅
정답 용어: [중개사 응답률 채팅]
근거: 회의 4개 / 출현 7회
```

한글 suggestion 자체는 분석 prompt에 바로 넣지 않는다. accepted glossary term만 `domainGlossary` supplemental context가 된다.

## 구현 메모

- 기존 Latin/mixed token lane 옆에 Korean phrase suggestion lane을 추가한다.
- 2-8음절 한글 token과 2-3개 인접 token phrase를 추출한다.
- 띄어쓰기 compact normalization을 적용한다.
- 조사와 일반 어미를 stripping 또는 후보 제외 guard로 처리한다.
- 한글 stoplist와 generic phrase suffix list를 둔다.
- similarity score, context overlap, meeting support, occurrence count로 rank한다.
- 한쪽이 다른 쪽의 문법적 확장일 뿐인 pair는 dedupe 또는 제외한다.
- dismissed Korean suggestion은 기존 local glossary suggestion과 같은 방식으로 저장한다.
