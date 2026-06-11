# Meeting Rescue v0.1.17


- 기존 raw transcript history에서 로컬 용어 후보를 찾고 검토할 수 있는 용어집 워크플로우를 추가했습니다.
- Meeting Intelligence에 `용어` 탭을 추가해 후보를 새 용어로 등록하거나 기존 용어의 alias로 연결할 수 있게 했습니다.
- Raw Transcript에서 텍스트를 직접 선택해 로컬 용어집에 등록할 수 있게 했습니다.
- Transcript 표시를 `원문`과 `용어 적용` 보기로 전환할 수 있게 해 전사 오류가 보정된 문맥을 바로 비교할 수 있게 했습니다.
- 로컬 용어집을 분석 prompt와 검색 인덱스에 낮은 우선순위 힌트로 반영해 요약/검색 품질 개선을 검증할 수 있게 했습니다.
- 용어 후보 스캔의 진행 상태와 진단 로그, offline scoring runner, glossary 적용 전/후 A/B runner를 추가해 품질 검증을 반복할 수 있게 했습니다.
- 좁은 화면과 중간 폭 화면에서 Raw Transcript와 Meeting Intelligence 헤더가 깨지지 않도록 레이아웃을 정리했습니다.
