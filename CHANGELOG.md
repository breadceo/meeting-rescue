# Changelog

Meeting Rescue의 사용자-facing 변경사항을 기록합니다.

## [Unreleased]

## [0.1.22] - 2026-06-16

- Meeting Intelligence 요약 탭에 `관점 정렬` 카드를 추가해 현재 논점에서 참석자 관점 차이와 다음 정렬 질문을 evidence와 함께 볼 수 있게 했습니다.

## [0.1.21] - 2026-06-16

- Live Watch에서 transcript 파일이 header 재작성이나 byte shift로 바뀐 경우 append tail로 오독하지 않고 전체 reload하도록 보강했습니다.
- Raw Transcript append 경로에서 split UTF-8 문자가 깨지거나 줄이 중복 표시될 수 있던 문제를 수정했습니다.
- 대부분이 NUL byte로 채워진 손상 transcript를 UTF-16 또는 tail-only transcript로 오인하지 않도록 디코딩 방어 로직을 강화했습니다.
- 이전 미팅 파일로 전환할 때 Raw Transcript 스크롤 위치가 이전 문서의 bottom 상태를 물려받는 문제를 수정했습니다.
- Live Watch 자동 분석 trigger와 history/search 경로의 과도한 재계산을 줄여 긴 transcript 폴더에서 CPU 사용량을 낮췄습니다.

## [0.1.20] - 2026-06-15

- Live Watch 중 history search 인덱스 재생성을 실제 검색이 필요할 때까지 미뤄 긴 history 폴더에서 idle CPU 사용량을 낮췄습니다.
- Raw Transcript 검색 인덱싱에서 무거운 자연어 토큰화를 생략하는 빠른 경로를 사용해 append 처리와 용어 후보 스캔 부하를 줄였습니다.
- Live metadata refresh가 전체 transcript 파싱 대신 header metadata preview만 읽도록 바꿔 긴 transcript에서 앱이 멈출 가능성을 낮췄습니다.
- Raw Transcript 선택 callback을 SwiftUI 업데이트 사이클 밖에서 전달해 선택 중 상태 갱신 충돌을 방지했습니다.

## [0.1.19] - 2026-06-12

- Raw Transcript에서 사용자가 직접 스크롤을 올렸을 때 새 줄 append 자동 스크롤을 일시 중지하고, `맨 아래` 버튼이나 최하단 복귀 시 다시 따라가도록 개선했습니다.
- 새 줄 append와 미팅 전환 시 `NSTextView`의 스크롤 영역 계산이 이전 미팅 상태를 물려받아 상단이 비거나 잘못된 위치로 이동하던 문제를 수정했습니다.
- Live Watch에서 최신 transcript 탐색과 history refresh 빈도를 줄이고, 오래된 미팅의 metadata preview를 필요할 때만 읽도록 해 긴 history 폴더에서 append 처리 부하를 낮췄습니다.
- Raw Transcript 하단의 용어 힌트 표기를 실제 의미에 맞게 정리했습니다.

## [0.1.18] - 2026-06-11

- 긴 transcript에서 `용어 적용` 보기로 전환했을 때 CPU 사용량이 크게 오를 수 있던 문제를 수정했습니다.
- 용어 적용 transcript 렌더링을 캐시하고, 텍스트 뷰 갱신 시 긴 문자열 전체 비교를 반복하지 않도록 개선했습니다.

## [0.1.17] - 2026-06-11

- 기존 raw transcript history에서 로컬 용어 후보를 찾고 검토할 수 있는 용어집 워크플로우를 추가했습니다.
- Meeting Intelligence에 `용어` 탭을 추가해 후보를 새 용어로 등록하거나 기존 용어의 alias로 연결할 수 있게 했습니다.
- Raw Transcript에서 텍스트를 직접 선택해 로컬 용어집에 등록할 수 있게 했습니다.
- Transcript 표시를 `원문`과 `용어 적용` 보기로 전환할 수 있게 해 전사 오류가 보정된 문맥을 바로 비교할 수 있게 했습니다.
- 로컬 용어집을 분석 prompt와 검색 인덱스에 낮은 우선순위 힌트로 반영해 요약/검색 품질 개선을 검증할 수 있게 했습니다.
- 용어 후보 스캔의 진행 상태와 진단 로그, offline scoring runner, glossary 적용 전/후 A/B runner를 추가해 품질 검증을 반복할 수 있게 했습니다.
- 좁은 화면과 중간 폭 화면에서 Raw Transcript와 Meeting Intelligence 헤더가 깨지지 않도록 레이아웃을 정리했습니다.

## [0.1.16] - 2026-06-09

- Google Calendar API 직접 연결을 추가해 현재 회의와 겹치는 캘린더 일정을 컨텍스트로 가져올 수 있게 했습니다.
- Test Run에서도 저장된 Calendar context snapshot을 재사용해 실제 회의 없이 캘린더 컨텍스트 반영 흐름을 검증할 수 있게 했습니다.
- 컨텍스트 탭을 다시 열고, 사용자에게 불필요한 Google Calendar MCP 메뉴는 숨긴 상태로 정리했습니다.
- 회의실/room code/title 매칭을 보강해 반복 회의와 관련 회의 연결의 정확도를 높였습니다.
- 가장 잘 맞는 캘린더 후보가 명확하면 기본으로 선택하고, room code 충돌이나 애매한 후보는 수동 선택으로 남기도록 했습니다.

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
