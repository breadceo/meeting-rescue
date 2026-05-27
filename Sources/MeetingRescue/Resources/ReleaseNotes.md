# Meeting Rescue v0.1.11


- Live analysis가 새 transcript chunk와 compact state를 더 작게 보내도록 개선해 LLM 호출 비용과 prompt 크기를 줄였습니다.
- Codex app-server experimental provider의 실행 모드 표기, diagnostics, run trace를 보강했습니다.
- Analysis 실행 상세 화면의 긴 prompt/output 표시와 context plan 가독성을 개선했습니다.
- 자동 analysis trigger를 hybrid preset 중심으로 조정해 너무 잦은 Test Run/Live analysis 실행을 줄였습니다.
- 결정 후보와 액션 후보를 섹션 단위로 전체 복사할 수 있게 개선했습니다.
- Markdown 다운로드에서 내부 운영용 LLM 사용량 추정과 Analysis 실행 로그를 제외했습니다.
- 릴리즈 노트 작성/배포 흐름을 추가하고, 앱 안에서 현재/최신 릴리즈 노트를 확인할 수 있게 했습니다.
- 좁은 화면에서 Meetings, Raw Transcript, Meeting Intelligence 패널을 접고 펼칠 수 있게 반응형 레이아웃을 개선했습니다.
