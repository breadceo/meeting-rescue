# Meeting Rescue v0.1.16


- Google Calendar API 직접 연결을 추가해 현재 회의와 겹치는 캘린더 일정을 컨텍스트로 가져올 수 있게 했습니다.
- Test Run에서도 저장된 Calendar context snapshot을 재사용해 실제 회의 없이 캘린더 컨텍스트 반영 흐름을 검증할 수 있게 했습니다.
- 컨텍스트 탭을 다시 열고, 사용자에게 불필요한 Google Calendar MCP 메뉴는 숨긴 상태로 정리했습니다.
- 회의실/room code/title 매칭을 보강해 반복 회의와 관련 회의 연결의 정확도를 높였습니다.
- 가장 잘 맞는 캘린더 후보가 명확하면 기본으로 선택하고, room code 충돌이나 애매한 후보는 수동 선택으로 남기도록 했습니다.
