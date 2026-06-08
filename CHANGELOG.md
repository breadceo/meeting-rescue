# Changelog

Meeting Rescue의 사용자-facing 변경사항을 기록합니다.

## [Unreleased]

## [0.1.15] - 2026-06-08

- Meeting Intelligence의 `컨텍스트` 탭을 릴리스 UI에서 숨겨 Calendar context lane 정리 전 사용자 노출을 막았습니다.
- Live/Test Run 중 `Raw Transcript`에서 현재 시점을 `중요 시점`으로 표시할 수 있게 위치와 이름을 정리했습니다.
- 이어받은 미해결 질문을 반복 회의와 최근 참석자/주제 일치 회의로 나누고, 같은 회의실의 주간 반복 회의 판정을 보강했습니다.
- Decision Coach와 Share Readiness가 사용자의 수동 체크 없이 AI 결정 후보를 바로 기준으로 삼도록 조정했습니다.
- 업데이트 feed가 설정되지 않은 개발 빌드에서 불필요한 업데이트 확인 팝업이 뜨지 않도록 했습니다.

## [0.1.14] - 2026-06-02

- 릴리즈 노트 화면이 packaged app에서 resource bundle을 찾지 못하면 앱이 종료될 수 있던 문제를 수정했습니다.

## [0.1.13] - 2026-05-28

- Live Watch 분석이 성공했는데도 현재 이슈가 `-`로 남을 수 있던 문제를 수정했습니다.
- 첫 live patch 분석에서 이전 현재 이슈가 비어 있으면 새 transcript chunk의 핵심 논점을 반드시 현재 이슈로 채우도록 보강했습니다.
- LLM provider가 여전히 `currentIssue`를 비워 반환해도 topic, 결정 후보, 액션 후보, note 근거로 현재 이슈를 보강하도록 했습니다.

## [0.1.12] - 2026-05-27

- 설정창을 `LLM`, `Analysis`, `App`, `Danger` 탭으로 나눠 기능별로 정리했습니다.
- 설정 항목을 카드형 row로 재배치해 설명과 control이 한눈에 보이도록 개선했습니다.
- LLM 가격 reference를 기본 접힘 상태로 바꿔 설정창의 기본 밀도를 낮췄습니다.

## [0.1.11] - 2026-05-27

- Live analysis가 새 transcript chunk와 compact state를 더 작게 보내도록 개선해 LLM 호출 비용과 prompt 크기를 줄였습니다.
- Codex app-server experimental provider의 실행 모드 표기, diagnostics, run trace를 보강했습니다.
- Analysis 실행 상세 화면의 긴 prompt/output 표시와 context plan 가독성을 개선했습니다.
- 자동 analysis trigger를 hybrid preset 중심으로 조정해 너무 잦은 Test Run/Live analysis 실행을 줄였습니다.
- 결정 후보와 액션 후보를 섹션 단위로 전체 복사할 수 있게 개선했습니다.
- Markdown 다운로드에서 내부 운영용 LLM 사용량 추정과 Analysis 실행 로그를 제외했습니다.
- 릴리즈 노트 작성/배포 흐름을 추가하고, 앱 안에서 현재/최신 릴리즈 노트를 확인할 수 있게 했습니다.
- 좁은 화면에서 Meetings, Raw Transcript, Meeting Intelligence 패널을 접고 펼칠 수 있게 반응형 레이아웃을 개선했습니다.

## [0.1.10] - 2026-05-26

- Live Analysis Context Pipeline v2를 추가해 새 transcript chunk와 compact state 중심으로 live analysis context를 줄였습니다.
- Codex app-server experimental provider가 앱 실행 중 process와 meeting thread를 재사용하도록 개선했습니다.
- Analysis 실행 상세에서 context plan, run trace, provider latency를 확인할 수 있게 했습니다.
- 후보 편집, 확정, 되돌리기, markdown export 흐름을 보강했습니다.
- Sparkle 기반 macOS 자동 업데이트와 notarized DMG 배포 흐름을 추가했습니다.
