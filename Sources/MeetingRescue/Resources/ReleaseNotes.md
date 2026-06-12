# Meeting Rescue v0.1.19


- Raw Transcript에서 사용자가 직접 스크롤을 올렸을 때 새 줄 append 자동 스크롤을 일시 중지하고, `맨 아래` 버튼이나 최하단 복귀 시 다시 따라가도록 개선했습니다.
- 새 줄 append와 미팅 전환 시 `NSTextView`의 스크롤 영역 계산이 이전 미팅 상태를 물려받아 상단이 비거나 잘못된 위치로 이동하던 문제를 수정했습니다.
- Live Watch에서 최신 transcript 탐색과 history refresh 빈도를 줄이고, 오래된 미팅의 metadata preview를 필요할 때만 읽도록 해 긴 history 폴더에서 append 처리 부하를 낮췄습니다.
- Raw Transcript 하단의 용어 힌트 표기를 실제 의미에 맞게 정리했습니다.
