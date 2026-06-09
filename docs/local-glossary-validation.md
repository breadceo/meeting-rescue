# Local Glossary 검증 노트

날짜: 2026-06-09

범위: Meeting Rescue의 local-first glossary suggestion 기능.

## 합성 Fixture

```text
Room: Zigbang(2F)_R3
Date/Time: 2026-06-09 10:30
Participants: Alex, Blair
[00:10] Alex: jax workflow 요약 품질을 봅시다.
[02:20] Blair: jecks 쪽 action item이 이상하게 잡혀요.
[04:40] Alex: zacks 검색 결과도 같이 비교합시다.
```

## 기대 동작

- Settings > Glossary > `용어 후보 생성`은 `jax`, `jecks`, `zacks`를 포함하는 후보를 만든다.
- 후보를 승인하면 accepted local glossary term이 생성된다.
- `jax`가 포함된 transcript 분석 request에는 `domainGlossary` supplemental context가 포함된다.
- `zax` 검색은 raw transcript에 `jax` 또는 `jecks`만 있는 회의도 찾을 수 있다.
- raw transcript 표시와 evidence excerpt는 원문 표현을 유지한다.

## 자동 검증 결과

- synthetic suggestion grouping: PASS
- accepted glossary persistence: PASS
- prompt supplemental context: PASS
- search canonicalization: PASS
- raw transcript preservation: PASS
- settings source wiring: PASS

## 제품 판단

- glossary는 calendar context와 별도 lane으로 유지한다.
- v1은 개인/local dictionary다.
- team/shared dictionary, Google Sheet sync, 제안/승인 workflow는 실제 개인 history suggestion의 precision을 본 뒤 다시 판단한다.
