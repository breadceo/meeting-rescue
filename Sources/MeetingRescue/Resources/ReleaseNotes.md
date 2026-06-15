# Meeting Rescue v0.1.20


- Live Watch 중 history search 인덱스 재생성을 실제 검색이 필요할 때까지 미뤄 긴 history 폴더에서 idle CPU 사용량을 낮췄습니다.
- Raw Transcript 검색 인덱싱에서 무거운 자연어 토큰화를 생략하는 빠른 경로를 사용해 append 처리와 용어 후보 스캔 부하를 줄였습니다.
- Live metadata refresh가 전체 transcript 파싱 대신 header metadata preview만 읽도록 바꿔 긴 transcript에서 앱이 멈출 가능성을 낮췄습니다.
- Raw Transcript 선택 callback을 SwiftUI 업데이트 사이클 밖에서 전달해 선택 중 상태 갱신 충돌을 방지했습니다.
