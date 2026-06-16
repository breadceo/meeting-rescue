# Meeting Rescue v0.1.21


- Live Watch에서 transcript 파일이 header 재작성이나 byte shift로 바뀐 경우 append tail로 오독하지 않고 전체 reload하도록 보강했습니다.
- Raw Transcript append 경로에서 split UTF-8 문자가 깨지거나 줄이 중복 표시될 수 있던 문제를 수정했습니다.
- 대부분이 NUL byte로 채워진 손상 transcript를 UTF-16 또는 tail-only transcript로 오인하지 않도록 디코딩 방어 로직을 강화했습니다.
- 이전 미팅 파일로 전환할 때 Raw Transcript 스크롤 위치가 이전 문서의 bottom 상태를 물려받는 문제를 수정했습니다.
- Live Watch 자동 분석 trigger와 history/search 경로의 과도한 재계산을 줄여 긴 transcript 폴더에서 CPU 사용량을 낮췄습니다.
