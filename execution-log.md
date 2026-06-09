# Meeting Rescue 실행 로그

이 파일은 `tasks.md`의 운영 원칙에 따른 실행 이력을 보관한다. 새 로그는 이 파일의 맨 위에 추가한다.

### 2026-06-09 Local Glossary Suggestions

- 작업 내용:
  - 개인/local glossary model과 `ApplicationStateStore` persistence를 추가했다.
  - `domainGlossary` supplemental context kind/priority를 추가하고, prompt에 glossary precedence rule을 명시했다.
  - history 기반 suggestion engine을 추가해 `jax`, `jecks`, `zacks` 같은 STT 변형 후보를 묶어 제안한다.
  - accepted glossary term을 analysis supplemental context와 meeting history search section에 반영했다.
  - search DB rebuild signature에 glossary state timestamp를 포함해 accepted term 변경 시 FTS index가 재생성되게 했다.
  - Settings > Glossary 섹션을 추가해 local glossary enable, 후보 생성, suggestion accept/dismiss, accepted term delete를 제공했다.
  - `tasks.md`에 D2.5 Local Glossary Suggestions를 Done 항목으로 추가하고 `docs/local-glossary-validation.md`를 작성했다.
- 검증:
  - `swift test --filter LocalGlossaryModelsTests`: 통과.
  - `swift test --filter CalendarContextModelsTests`: 통과.
  - `swift test --filter LocalGlossaryMatcherTests`: 통과.
  - `swift test --filter AnalysisPromptBuilderTests`: 통과.
  - `swift test --filter LocalGlossarySuggestionEngineTests`: 통과.
  - `swift test --filter AnalysisStateTests`: 통과.
  - `swift test --filter MeetingHistorySearchTests`: 통과.
  - `swift test --filter AppViewModelTestRunContextTests`: 통과.
  - `swift test --filter ContentViewContextWiringTests`: 통과.
  - `swift test`: 통과. 206 tests / 39 suites.
  - `swift build`: 통과.
  - `git diff --check`: 통과.
- 남은 관찰:
  - 실제 transcript history에서 suggestion precision을 확인해야 한다.
  - v1은 개인/local dictionary이며 team/shared Sheet workflow는 포함하지 않았다.

### 2026-06-08 Google Calendar quality validation hardening

- 작업 내용:
  - Google Calendar context가 Meeting Intelligence 품질을 높이는지 판단하기 위한 deterministic guard와 sanitized validation report를 추가했다.
  - `GoogleCalendarContextMapper`를 보강했다:
    - exact room/time match가 participant-only overlap보다 우선하도록 회귀 테스트를 추가했다.
    - useful overlap이 전혀 없는 event는 후보에서 제외해 prompt/UI noise를 줄였다.
    - accepted calendar event description의 URL을 `.linkedSourceCandidate`, `isAccepted == false` supplemental source로 분리했다.
  - `AnalysisPromptBuilder`에 calendar metadata가 transcript-derived `meetingMetadata`를 덮어쓰지 말라는 explicit instruction을 추가했다.
  - unaccepted calendar linked source candidate가 prompt에 주입되지 않는지 테스트했다.
  - Test Run replay에서 saved event candidate accepted/dismissed 상태가 유지되고, live Google Calendar API/Calendar MCP fetch 경로를 호출하지 않는지 guard를 추가했다.
  - Context panel source wiring test를 보강해 Google Calendar API controls는 유지하고 Google Calendar MCP controls/copy는 숨기도록 고정했다.
  - `docs/calendar-quality-validation.md`에 sanitized validation matrix와 local smoke result를 추가했다.
  - `tasks.md`에 D2 `11b. Google Calendar quality validation hardening` 항목을 추가하고 완료 상태로 갱신했다.
- 검증:
  - `swift test --scratch-path .build-test`: 통과. 181 tests / 35 suites.
  - `python3 -m unittest Tests/google_calendar_oauth_poc_tests.py`: 통과. 4 tests.
  - `git diff --check`: 통과.
  - `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/Users/ethan/Downloads/client_secret_...json scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` build 완료 및 bundle config resource 존재 확인.
  - `"dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue" --google-calendar-smoke --allow-empty-events`: 통과. 저장된 OAuth token으로 Calendar events 7건 fetch, persisted candidates 7건, cached replay `cachedReplay`, disconnect skipped.
  - secret/token leak check: 통과. tracked file list와 diff에서 OAuth client JSON, access token, refresh token, 실제 client secret 값 미검출.

### 2026-06-08 Google Calendar 컨텍스트 탭 재노출

- 작업 내용:
  - Meeting Intelligence의 `컨텍스트` 탭 feature gate를 열어 릴리즈 UI에서 다시 노출되도록 했다.
  - `release visible intelligence lanes include context tab` 회귀 테스트로 `overview`, `timeline`, `candidates`, `workflow`, `context` lane이 모두 보이는 상태를 고정했다.
  - AppViewModel Test Run 시작 경로 테스트를 추가해 저장된 Google Calendar context가 `cachedReplay`로 복원되고 supplemental context/meeting identity가 유지되는지 확인했다.
  - Direct Google Calendar OAuth closeout plan과 `tasks.md`의 숨김 상태 문구를 현재 상태에 맞게 갱신했다.
- 검증:
  - `swift test --filter MeetingIntelligenceFeatureGateTests`: 통과. 컨텍스트 탭 노출 테스트 PASS.
  - `swift test --filter 'CalendarContextModelsTests|AnalysisPromptBuilderTests/promptIncludesSupplementalContextPriority'`: 통과. cached replay와 supplemental context prompt 주입 확인.
  - `swift test --filter AppViewModelTestRunContextTests`: 통과. 실제 Test Run 시작 시 저장 calendar context가 `cachedReplay`로 반영됨을 확인.
  - `swift test`: 통과. 171 tests / 34 suites.
  - `git diff --check`: 통과.
  - `scripts/build_app.sh`: 통과. `/Users/ethan/Documents/git/meeting-rescue/dist/Meeting Rescue.app` 생성.

### 2026-06-08 Direct Google Calendar API OAuth closeout

- 작업 내용:
  - Direct Google Calendar API OAuth lane을 native Desktop OAuth + Calendar REST API 경로로 닫았다.
  - 브라우저 OAuth + PKCE + loopback redirect flow를 앱 target에 연결했다.
  - refresh token은 macOS Keychain에 저장하고 disconnect 시 삭제하도록 했다.
  - Calendar `events.list` 결과를 `CalendarContextState`로 매핑해 `analysisState.calendarContext`에 저장하고, Test Run에서는 저장 snapshot을 `cachedReplay`로 재사용하도록 했다.
  - Settings > Analysis에 Google Calendar 연결/가져오기/해제 card를 추가했다. 컨텍스트 탭은 릴리즈 요구에 맞춰 숨긴 상태를 유지했다.
  - release build에서 untracked OAuth config를 bundle resource로 주입할 수 있도록 `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE` 경로를 추가했다.
  - smoke 중 발견한 문제를 수정했다:
    - `NWListener`가 ready 되기 전에 port를 읽어 `localhost:0` redirect URI가 만들어지던 문제.
    - loopback callback HTTP request가 partial read 상태에서 authorization code를 파싱할 수 있던 문제.
    - Calendar API query의 RFC3339 offset `+09:00`가 raw `+`로 남아 Google `events.list` 400을 만들던 문제.
- 검증:
  - `swift test`: 통과. 170 tests / 33 suites.
  - `python3 -m unittest Tests/google_calendar_oauth_poc_tests.py`: 통과. 4 tests.
  - `git diff --check`: 통과.
  - `swift run MeetingRescue --google-calendar-smoke --config /Users/ethan/Downloads/client_secret_...json --connect --reset-before-connect --disconnect-after --time-min 2026-06-08T00:00:00+09:00 --time-max 2026-06-09T00:00:00+09:00 --room 'Meeting Rescue Smoke' --date-time '2026-06-08 00:00' --participants Ethan --auth-timeout 240`: 통과. OAuth connect, Keychain token present, Calendar events 7건 fetch, persisted candidates 7건, cached replay `cachedReplay`, disconnect verified.
  - `security find-generic-password -s MeetingRescue.GoogleCalendar -a <client-id>`: smoke disconnect 후 `keychain_token_absent` 확인.
  - `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/Users/ethan/Downloads/client_secret_...json scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` build 완료.
  - `test -f "dist/Meeting Rescue.app/Contents/Resources/MeetingRescue_MeetingRescue.bundle/GoogleCalendarOAuthConfig.json"`: 통과. bundle config resource 존재 확인.
  - secret/token leak check: 통과. OAuth client secret/access token/refresh token 값이 tracked diff와 untracked repo files에 포함되지 않음을 확인했다.

### 2026-05-28 v0.1.13 배포

- 수정 내용:
  - `VERSION`을 `0.1.13`으로 올리고 CHANGELOG에 Live Watch 현재 이슈 보강 수정 사항을 기록했다.
  - `v0.1.13` notarized DMG를 생성해 GitHub Release에 업로드했다.
  - Sparkle appcast와 앱 내 latest release note를 `0.1.13` / build `53` / notarized DMG asset 기준으로 갱신했다.
  - 실제 설치 앱이 읽는 `SUFeedURL` 기준 update feed repo(`breadceo/meeting-rescue-updates`)도 `0.1.13`으로 갱신했다.
- 검증:
  - `swift test`: 통과. 115개 test / 22개 suite.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.13.dmg` 생성.
  - `plutil -extract CFBundleShortVersionString raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `0.1.13`.
  - `plutil -extract CFBundleVersion raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `53`.
  - `plutil -extract SUFeedURL raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/appcast.xml`.
  - `./scripts/notarize_app.sh`: 통과. App notarization `Accepted` (`6ff97193-e697-4895-b1aa-6e5657cab3f3`), DMG notarization `Accepted` (`d9be3417-831d-4c90-aa7f-bad81b929c5a`).
  - `./scripts/publish_github_release.sh`: 통과. Release URL `https://github.com/breadceo/meeting-rescue/releases/tag/v0.1.13`.
  - `curl -fsSL "$(plutil -extract SUFeedURL raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist')?cachebust=..."`: `sparkle:shortVersionString`이 `0.1.13`, `sparkle:version`이 `53`, DMG URL이 `Meeting-Rescue-v0.1.13-notarized.dmg`임을 확인.
  - `curl -fsSL "https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/releases/latest.md?cachebust=..."`: `# Meeting Rescue v0.1.13` 확인.
  - `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify docs/appcast.xml`: 통과.
  - `shasum -a 256 -c dist/Meeting-Rescue-v0.1.13-notarized.dmg.sha256`: 통과.
  - `xcrun stapler validate dist/Meeting-Rescue-v0.1.13-notarized.dmg`: 통과.
  - `spctl -a -t open --context context:primary-signature -vv dist/Meeting-Rescue-v0.1.13-notarized.dmg`: `accepted`.

### 2026-05-28 빈 currentIssue live patch 보강

- 작업 내용:
  - 배포 앱의 live watch 실행 로그에서 analysis attempt는 `succeeded`였지만 provider output이 계속 `currentIssue: null`을 반환해 `latestSnapshot.currentIssue.summary`가 빈 문자열로 남는 문제를 확인했다.
  - live patch prompt에 `previousAnalysisSnapshot.currentIssue.summary`가 비어 있으면 이번 chunk의 핵심 논점으로 `currentIssue`를 반드시 채우라는 지시를 추가했다.
  - provider가 여전히 `currentIssue: null`을 반환하는 경우에도 기존 current issue가 비어 있으면 patch의 topic/decision/action/note 근거에서 현재 이슈를 보강하도록 `AnalysisSnapshot.applyingPatch`에 fallback을 추가했다.
  - 빈 baseline + null currentIssue patch 회귀 테스트와 prompt 지시문 회귀 테스트를 추가했다.
- 검증:
  - `swift test --filter 'LLMProviderOutputTests|AnalysisPromptBuilderTests'`: 통과. 16개 test / 2개 suite.
  - `swift test`: 통과. 115개 test / 22개 suite.
  - 앱 build/restart는 수행하지 않았다.

### 2026-05-27 Live analysis latency/cost hardening

- 작업 내용:
  - Analysis prompt payload를 pretty JSON에서 compact JSON으로 바꾸고 provider/model 중복 필드를 제거했다.
  - live prompt window를 줄였다: 초기 transcript 8,000자→6,000자, 새 chunk 5,000자→3,200자, recent context 800자→500자, related chunk는 700자로 cap.
  - previous snapshot compact 범위를 줄였다: timeline 4→3, decision/action 후보 6→4, notes 5→3.
  - patch schema에 `maxItems`/`maxLength`를 추가해 patch output 크기를 제한했다.
  - previous snapshot 이후 `livePatch` decode에서 full snapshot fallback을 제거하고 patch-only를 강제했다.
  - 첫 live/manual/final 분석도 repair/full-refresh가 아니면 빈 baseline snapshot 위에 patch를 적용하도록 바꿔 full snapshot 생성을 줄였다.
  - app-server diagnostics trace detail에 item text/summary length 요약을 추가했다. raw payload는 저장하지 않는다.
  - Live/Test Run/History/folder 전환 중 active analysis를 cancel하면 running attempt를 skipped로 닫고, generation guard로 늦게 도착한 provider result가 UI 상태를 되돌리지 않게 했다.
- 검증:
  - `swift test --filter 'AnalysisPromptBuilderTests|LLMProviderOutputTests|SchemaTests'`: 통과. 12개 test / 3개 suite.
  - `swift test`: 통과. 108개 test / 22개 suite.
  - 앱 build/restart는 수행하지 않았다.

### 2026-05-27 Codex app-server diagnostics option

- 작업 내용:
  - Settings에서 `Codex App Server experimental` mode일 때만 보이는 `app-server diagnostics` toggle을 추가했다.
  - diagnostics on이면 `thread/start.experimentalRawEvents`를 opt-in하도록 provider/service/runtime 경로에 설정을 전달한다.
  - run trace의 `app-server event: <method>` detail에 `item.type`/`item.phase` 요약을 함께 남긴다. raw payload는 저장하지 않는다.
  - diagnostics toggle 변경 시 app-server reuse key를 분리해 이전 non-diagnostics thread와 섞이지 않게 했다.
- 검증:
  - `swift test --filter CodexAppServerServiceTests`: 통과. 4개 test / 1개 suite.
  - `swift test`: 통과. 105개 test / 22개 suite.
  - 앱 build/restart는 수행하지 않았다.

### 2026-05-27 Codex app-server event timing diagnostics

- 작업 내용:
  - `codex app-server generate-ts --out <tmp> --experimental`로 server notification protocol을 확인했다.
  - 확인한 timing 후보: `turn/started`, `turn/completed`, `item/started`, `item/completed`, `rawResponseItem/completed`, `item/reasoning/textDelta`, `item/reasoning/summaryTextDelta`, `thread/tokenUsage/updated`, `model/rerouted`, `turn/plan/updated`.
  - app-server turn loop에서 모든 server notification `method`의 첫 등장 시점과 count를 집계한다.
  - run trace에 `app-server event: <method>` 항목으로 저장한다. raw payload는 저장하지 않는다.
  - fake runtime test에 `item/started`, `item/agentMessage/delta` event timing 보존 검증을 추가했다.
- 검증:
  - `swift test --filter CodexAppServerServiceTests`: 통과. 3개 test / 1개 suite.
  - `swift test`: 통과. 104개 test / 22개 suite.
  - 앱 build/restart는 수행하지 않았다.

### 2026-05-26 Codex app-server long-lived service

- 작업 내용:
  - `CodexAppServerService`를 추가해 `Codex App Server experimental` mode에서 앱 실행 중 app-server process를 재사용하도록 했다.
  - 같은 meeting/model/working directory 조합에서는 app-server thread를 재사용한다.
  - timeout, turn failure, protocol failure가 발생하면 service state를 reset하고 기존 `CLI exec` fallback 경로로 넘어갈 수 있게 했다.
  - run trace에 `app-server process` new/reused, `initialize app-server` new/reused, `thread/start` new/reused, `turn/start`, `first delta latency`, `final answer latency`, `total provider latency`를 기록한다.
  - Analysis 실행 상세의 Run Trace subtitle에서 process/thread reuse와 first delta latency를 바로 확인할 수 있게 했다.
  - 기존 CLI exec mode와 기본값은 변경하지 않았다.
- 검증:
  - `swift test --filter CodexAppServerServiceTests`: 통과. 3개 test / 1개 suite.
  - `swift test`: 통과. 104개 test / 22개 suite.
  - 앱 build/restart는 사용자 요청에 따라 수행하지 않았다.

### 2026-05-26 Analysis attempt provider execution mode 표기

- 작업 내용:
  - `AnalysisAttemptLog`에 Codex execution mode를 저장하도록 했다.
  - 새 attempt는 Codex CLI exec / Codex App Server experimental 중 실제 설정된 실행 경로를 함께 기록한다.
  - 기존 attempt log는 `runTrace`의 `app-server` argument/event를 보고 `Codex App Server`로 추론해 표시한다.
  - Analysis 실행 로그 row/detail에서 provider를 `Codex`, `codexExec` 대신 `Codex CLI exec` 또는 `Codex App Server`로 표시하도록 했다.
- 검증:
  - `git diff --check`: 통과.
  - 앱 build/restart와 `swift test`는 사용자 요청에 따라 수행하지 않았다.

### 2026-05-26 다음 analysis progress 표기 수정

- 작업 내용:
  - `nextAutomaticAnalysisSummary`가 실제 새 발화/문자 수가 아니라 trigger 기준까지 남은 줄/문자 수를 `새 ...`로 표시하던 문제를 수정했다.
  - 이제 다음 analysis 표기는 `새 X/Y줄 · A/B자 또는 MM:SS` 형태로 현재 누적량과 trigger 기준을 함께 보여준다.
- 검증:
  - `swift test`: 통과. 101개 test / 21개 suite.
  - 앱 build/restart는 사용자 요청에 따라 수행하지 않았다.

### 2026-05-26 Codex app-server experimental provider

- 작업 내용:
  - `codex app-server generate-json-schema --experimental`와 `generate-ts --experimental`로 protocol을 확인했다.
  - stdio JSON-RPC probe에서 `initialize`, `thread/start`, `turn/start`, `outputSchema`, `item/agentMessage/delta`가 동작함을 확인했다.
  - Codex provider 전용 `CodexExecutionMode`를 추가했다: `CLI exec`, `App Server experimental`.
  - Settings에 Codex provider 선택 시에만 `Codex execution` picker를 노출한다.
  - `CodexAppServerProvider`를 추가해 app-server stdio protocol로 schema-bound analysis를 시도하고, 실패 시 기존 `CodexExecProvider`로 fallback한다.
  - header provider summary에 app-server mode일 때 `Codex App Server · preset`으로 표시되게 했다.
- 중요한 관찰:
  - app-server protocol은 schema-bound output에 사용할 수 있다.
  - 다만 spike에서 아주 작은 `{ok:true}` 요청도 app-server 기본 context/token usage가 크게 잡히는 정황이 있었다. 이번 구현은 기본값을 바꾸지 않고 실험 옵션으로만 제공한다.
  - Q&A는 이번 scope에서 제외했다.
- 검증:
  - `swift test --filter LLMProviderConfigurationTests`: 통과. 15개 test / 1개 suite.
  - `swift test`: 통과. 101개 test / 21개 suite.
  - `./scripts/build_app.sh`: 통과. `/Users/ethan/Documents/git/meeting-rescue/dist/Meeting Rescue.app` 생성.
  - 앱 재실행: 통과. `/Users/ethan/Documents/git/meeting-rescue/dist/Meeting Rescue.app` PID `72807`.

### 2026-05-26 Live memory index overlap filter

- 작업 내용:
  - `LiveTranscriptIndex.retrieve(excludingText:)`가 새 transcript chunk와 완전히 같은 segment만 제외하던 문제를 보완했다.
  - retrieved segment 본문이 새 chunk에 포함되거나, dialogue line fingerprint가 일정 비율 이상 겹치면 retrieval 결과에서 제외한다.
  - 새 chunk와 겹치는 오래된 segment는 제외하되, 겹치지 않는 관련 segment는 유지하는 회귀 테스트를 추가했다.
- 검증:
  - `swift test --filter LiveAnalysisContextPipelineTests`: 통과. 5개 test / 1개 suite.
  - `swift test`: 통과. 99개 test / 21개 suite.

### 2026-05-26 Analysis Context Plan 상세 표시 보강

- 작업 내용:
  - Analysis 실행 상세의 `Context Plan` subtitle을 retrieval mode/topK/chunk count/latency/estimated token 중심으로 바꿨다.
  - Context Plan 본문에 retrieval mode, topK, latency, retrieved chunks, prompt token 추정치, speaker/omitted/new/recent context metric을 모두 표시한다.
  - retrieved chunk를 한 줄 truncate 대신 time range, score, 글자 수, 전체 chunk 본문 card로 렌더링한다.
  - `Raw Context Plan` JSON panel을 추가해 실제 provider prompt에 들어간 context planner payload를 그대로 확인할 수 있게 했다.
- 검증:
  - `swift test`: 통과. 98개 test / 21개 suite가 통과했다.
  - `./scripts/build_app.sh`: 통과. `/Users/ethan/Documents/git/meeting-rescue/dist/Meeting Rescue.app` 생성.
  - Computer Use Test Run: `20260526_170014_Zigbang(2F)_Meeting Room L1.txt`로 Test Run 완료. 최신 attempt `2026-05-26 17:25:03 KST`는 `automatic-min-dialogue-lines · succeeded`, `input 3792`, `output 432`, `duration 58112ms`, `new 90 lines / 3803 chars`.
  - 기존 UI 대비: 이전에는 Context Plan이 한 줄 summary 중심이었으나, 최신 dist 앱에서 `Memory live index · top 1 · 1 chunks · 3ms · est 3791 tokens`, metric grid, retrieved chunk `[08:57]-[09:49]` 전체 본문, raw JSON이 표시됨을 확인했다.
  - 이전 run 비교: `2026-05-26 17:22:57 KST` 첫 실제 analysis는 `topK 0 / retrievedChunks 0 / input 1491`였고, 이후 `17:25:03 KST` incremental run은 live memory index에서 관련 chunk 1개를 회수해 prompt에 연결했다.

### 2026-05-26 Analysis 실행 상세 accordion UI

- 작업 내용:
  - Analysis 실행 상세 화면에서 header/닫기 버튼을 스크롤 밖 고정 영역으로 분리했다.
  - Summary, Batch, Context Plan, Message, Run Trace, Prompt, Provider Output을 각각 접었다 펼칠 수 있는 `DisclosureGroup` 섹션으로 바꿨다.
  - Run Trace는 기본 collapsed로 시작해 상세 화면의 초기 세로 공간 사용량을 줄였다.
- 검증:
  - `swift test`: 통과. 98개 test / 21개 suite가 통과했다.

### 2026-05-26 Test Run 첫 provider 호출 previous snapshot 오염 수정

- 작업 내용:
  - Test Run replay 중 UI preview를 위해 저장하는 `LocalAnalysisFallback` snapshot이 첫 실제 LLM provider 호출의 `previousAnalysisSnapshot`으로 전달되는 문제를 수정했다.
  - `LocalAnalysisFallback.isFallbackSnapshot`을 추가해 저장된 fallback snapshot도 real provider snapshot과 구분한다.
  - provider request와 scheduler seed에는 fallback snapshot을 제외하고, UI 표시용 fallback은 계속 유지한다.
- 검증:
  - `swift test`: 통과. 98개 test / 21개 suite가 통과했다.

### 2026-05-26 Live Analysis Context Pipeline v2 구현

- 작업 내용:
  - `LiveTranscriptIndex`를 추가해 live/test run 중 active meeting 전용 memory segment index를 유지한다.
  - `AnalysisContextPlanner`를 추가해 retrieval mode/topK/latency, retrieved chunk time range/score, speaking/omitted participants, new chunk stats, estimated prompt tokens를 `contextPlan`으로 남긴다.
  - `AnalysisPromptBuilder` payload에 `contextPlan`과 `relatedTranscriptChunks`를 포함해 provider가 새 transcript chunk를 primary source로 쓰면서 관련 과거 chunk를 보조 맥락으로 볼 수 있게 했다.
  - Settings에 `Live context retrieval` 옵션을 추가했다: `Off`, `Memory live index`.
  - Test Run도 live memory index/context planner 경로를 사용하게 했다. History mode는 retrieval off로 유지한다.
  - previous snapshot이 있으면 automatic/final/manual 모두 patch output을 사용하게 했다. full snapshot은 첫 분석 또는 명시적인 repair/full-refresh reason에만 허용한다.
  - Analysis 실행 상세에 `Context Plan` 섹션을 추가하고, 상단 status chip에 다음 automatic analysis 조건을 표시했다.
  - `docs/adr/0001-live-analysis-context-pipeline-v2.md`에 Test Run 적용 방식을 보강했다.
  - `tasks.md`에서 `Live Analysis Context Pipeline v2`를 `Done Archive`로 이동했다.
- 검증:
  - `swift test`: 통과. 97개 test / 21개 suite가 통과했다.
  - 요청에 따라 `./scripts/build_app.sh`, packaging, 앱 실행은 수행하지 않았다. 단, `swift test`의 SwiftPM 컴파일 과정에서 test target과 executable target link는 수행됐다.

### 2026-05-26 Live Analysis Context Pipeline v2 ADR 정리

- 작업 내용:
  - `docs/adr/0001-live-analysis-context-pipeline-v2.md`를 추가해 live analysis context/state ownership과 provider 경계를 기록했다.
  - production path는 stateless `codex exec` patch worker로 유지하고, persistent TTY/app-server는 experimental spike로 분리하기로 했다.
  - previous snapshot 이후 patch-only를 기본 계약으로 삼고, full refresh는 수동 repair/전체 재분석 escape hatch로 분리하기로 했다.
  - live retrieval은 active meeting 전용 memory `LiveTranscriptIndex`로 구현하고, 기존 History FTS5 live retrieval은 이번 scope에서 제외해 후속 backlog로만 남겼다.
  - `tasks.md` Backlog 상단에 `Live Analysis Context Pipeline v2` 실행 계획과 `History FTS5 live retrieval` 후속 항목을 추가했다.
- 검증:
  - 문서/계획 변경만 수행했다. build/test는 실행하지 않았다.

### 2026-05-26 v0.1.10 bridge feed migration

- 작업 내용:
  - `breadceo/meeting-rescue-updates` public repo를 생성하고 `appcast.xml` bridge feed를 초기화했다.
  - bridge raw feed URL을 `https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/appcast.xml`로 정했다.
  - `VERSION`을 `0.1.10`으로 올리고, app bundle의 기본 `SPARKLE_FEED_URL`을 bridge raw feed로 변경했다.
  - 기존 `breadceo/meeting-rescue` release/appcast에서 v0.1.10을 배포해 기존 설치본이 migration release를 받을 수 있게 했다.
  - bridge feed repo의 `appcast.xml`도 v0.1.10으로 갱신했다.
- 검증:
  - `gh repo create breadceo/meeting-rescue-updates --public --description "Sparkle appcast bridge feed for Meeting Rescue" --clone=false`: 통과. Repo 생성 완료.
  - `curl -fsSL https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/appcast.xml | rg '0\\.1\\.9|sparkle:version|Meeting-Rescue-v0\\.1\\.9'`: 통과. 초기 bridge feed가 v0.1.9를 반환했다.
  - `git diff --check`: 통과.
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `plutil -extract SUFeedURL raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/appcast.xml`.
  - `plutil -extract CFBundleShortVersionString raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `0.1.10`.
  - `plutil -extract CFBundleVersion raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `32`.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.10.dmg` 생성.
  - `./scripts/notarize_app.sh`: 통과. App notarization `Accepted` (`fa9d5736-6efb-4b04-9416-69109a82d808`), DMG notarization `Accepted` (`f3335743-63de-44cd-be99-3651cbaea4b8`).
  - `./scripts/publish_github_release.sh`: 통과. Release URL `https://github.com/breadceo/meeting-rescue/releases/tag/v0.1.10`.
  - `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify docs/appcast.xml`: 통과.
  - `gh release view v0.1.10 --repo breadceo/meeting-rescue --json tagName,isDraft,isPrerelease,url,assets`: 통과. DMG와 checksum asset이 uploaded 상태임을 확인했다.
  - `shasum -a 256 -c dist/Meeting-Rescue-v0.1.10-notarized.dmg.sha256`: 통과.
  - `curl -fsSL "https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/appcast.xml?cachebust=..." | rg '0\\.1\\.10|sparkle:version|Meeting-Rescue-v0\\.1\\.10|application/x-apple-diskimage'`: 통과. Bridge raw feed가 v0.1.10을 반환했다.
  - `curl -fsSL "https://breadceo.github.io/meeting-rescue/appcast.xml?cachebust=..." | rg '0\\.1\\.10|sparkle:version|Meeting-Rescue-v0\\.1\\.10|application/x-apple-diskimage'`: 통과. 기존 old feed도 v0.1.10을 반환했다.

### 2026-05-21 v0.1.9 배포

- 수정 내용:
  - `VERSION`을 `0.1.9`로 올리고 `main`에 push했다.
  - responsive compact layout 개선을 포함한 notarized DMG를 생성해 GitHub Release `v0.1.9`에 업로드했다.
  - Sparkle appcast를 `0.1.9` / build `30` / notarized DMG asset 기준으로 갱신했다.
- 검증:
  - `git diff --check`: 통과.
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.9.dmg` 생성.
  - `./scripts/notarize_app.sh`: 통과. App notarization `Accepted` (`ea3e7d6b-f0e4-4da7-9bd4-972976599314`), DMG notarization `Accepted` (`727fde4a-d7d2-482f-9918-1dcb9eda6935`).
  - `./scripts/publish_github_release.sh`: 통과. Release URL `https://github.com/breadceo/meeting-rescue/releases/tag/v0.1.9`.
  - `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify docs/appcast.xml`: 통과.
  - `gh release view v0.1.9 --repo breadceo/meeting-rescue --json tagName,isDraft,isPrerelease,url,assets`: 통과. DMG와 checksum asset이 uploaded 상태임을 확인했다.
  - `plutil -extract CFBundleShortVersionString raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `0.1.9`.
  - `plutil -extract CFBundleVersion raw -o - 'dist/Meeting Rescue.app/Contents/Info.plist'`: `30`.
  - `shasum -a 256 -c dist/Meeting-Rescue-v0.1.9-notarized.dmg.sha256`: 통과.
  - `curl -fsSL "https://breadceo.github.io/meeting-rescue/appcast.xml?cachebust=..." | rg '0\\.1\\.9|sparkle:version|Meeting-Rescue-v0\\.1\\.9|application/x-apple-diskimage'`: 통과. GitHub Pages appcast가 `0.1.9`, `sparkle:version 30`, notarized DMG URL을 반환함을 확인했다.

### 2026-05-21 Compact raw-primary layout

- 작업 내용:
  - responsive layout mode를 `wide`, `split`, `rawPrimary`, `compactOverlay`로 나누었다.
  - `rawPrimary`/`compactOverlay`에서는 Raw Transcript를 바닥에 두고, Meetings와 Meeting Intelligence를 상단 토글 drawer로 여는 구조로 바꿨다.
  - Meeting Intelligence가 더 이른 폭에서 접히도록 breakpoint를 조정했다.
  - 상단 action buttons는 `ViewThatFits`로 full/compact/icon 상태를 선택하고, 좁은 폭에서는 이슈/Markdown/설정/폴더 등을 더보기 menu에 넣었다.
  - status chips는 full/medium/compact density로 바꿔 좁은 폭에서 낮은 우선순위 chip을 숨긴다.
- 검증:
  - `swift build`: 통과. debug build 완료.
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `kill 85153 2>/dev/null || true; sleep 1; open "dist/Meeting Rescue.app"; sleep 3; pgrep -fl "MeetingRescue|Meeting Rescue"`: 통과. PID `95738`으로 새 app bundle 실행을 확인했다.
  - Computer Use `/Users/ethan/Documents/git/meeting-rescue/dist/Meeting Rescue.app`: 통과. 작은 폭에서 상단 action이 `분석` + `더보기`로 축약되고, status chip이 `mode/status/provider`만 남으며, Intelligence drawer 토글 open/close가 동작함을 확인했다.

### 2026-05-21 Adaptive collapsible panes

- 작업 내용:
  - main layout을 폭 기반 adaptive pane 구성으로 바꿔 Meetings와 Meeting Intelligence pane이 좁은 창에서 rail로 접히게 했다.
  - Meetings/Meeting Intelligence header에 수동 접기 버튼을 추가했고, 접힌 rail을 누르면 해당 pane을 다시 펼치게 했다.
  - 창 최소 폭을 `1180`에서 `760`으로 낮췄고, status chip row는 horizontal scroll로 처리해 상단 UI가 가로로 밀리지 않게 했다.
- 검증:
  - `swift build`: 통과. debug build 완료.
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `osascript -e 'tell application "Meeting Rescue" to quit' >/dev/null 2>&1 || true; sleep 1; open "dist/Meeting Rescue.app"; sleep 3; pgrep -fl "MeetingRescue|Meeting Rescue"`: 통과. PID `85153`으로 새 app bundle 실행을 확인했다.
  - Computer Use `/Users/ethan/Documents/git/meeting-rescue/dist/Meeting Rescue.app`: 통과. Meetings/Intelligence 접기 버튼이 보이고, Meetings pane 접기/펼치기가 동작함을 확인했다.

### 2026-05-20 v0.1.8 배포

- 수정 내용:
  - `VERSION`을 `0.1.8`로 올리고 `main`에 push했다.
  - GitHub issue browser prefill 기능을 포함한 notarized DMG를 생성해 GitHub Release `v0.1.8`에 업로드했다.
  - Sparkle appcast를 `0.1.8` / build `26` / notarized DMG asset 기준으로 갱신하고 `main`에 push했다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.8.dmg` 생성.
  - `./scripts/notarize_app.sh`: 통과. App notarization `Accepted` (`04bcaf68-8bda-4529-a8cd-35ec646a4db4`), DMG notarization `Accepted` (`742bf36d-ecd0-4ceb-a1b1-4ef0229fe2aa`).
  - `spctl` Gatekeeper 검증: app과 DMG 모두 `accepted`, `source=Notarized Developer ID`.
  - `./scripts/publish_github_release.sh`: 통과. Release URL `https://github.com/breadceo/meeting-rescue/releases/tag/v0.1.8`.
  - `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify docs/appcast.xml`: 통과.
  - GitHub Pages appcast cache-busted 확인: `0.1.8`, `sparkle:version 26`, notarized DMG URL, `application/x-apple-diskimage`, `sparkle:edSignature` 확인.

### 2026-05-20 GitHub issue browser prefill 추가

- 수정 내용:
  - 상단 `분석` 버튼 옆에 `이슈` menu를 추가했다.
  - `버그 신고`는 GitHub `bug` label, `기능 제안`은 `enhancement` label이 prefill된 issue 작성 화면을 기본 브라우저로 연다.
  - issue body에는 앱 버전/build, mode, source file name, analysis/provider/search DB 상태, usage, 최근 analysis attempt 요약을 포함한다.
  - 회의 원문, 참석자 전체 목록, 로컬 full path는 기본 body에서 제외했다.
- 검증:
  - `gh label list --repo breadceo/meeting-rescue --limit 100`: `bug`, `enhancement` label 존재 확인.
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.

### 2026-05-20 v0.1.7 배포

- 수정 내용:
  - `VERSION`을 `0.1.7`로 올리고 `main`에 push했다.
  - notarized DMG를 생성해 GitHub Release `v0.1.7`에 업로드했다.
  - Sparkle appcast를 `0.1.7` / build `23` / notarized DMG asset 기준으로 갱신하고 `main`에 push했다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.7.dmg` 생성.
  - `./scripts/notarize_app.sh`: 통과. App notarization `Accepted` (`9aee7b0b-542d-4345-b7fd-493dd4bae604`), DMG notarization `Accepted` (`dc210363-e5dd-404a-b18c-06c0c06d99a9`).
  - `spctl` Gatekeeper 검증: app과 DMG 모두 `accepted`, `source=Notarized Developer ID`.
  - `./scripts/publish_github_release.sh`: 통과. Release URL `https://github.com/breadceo/meeting-rescue/releases/tag/v0.1.7`.
  - `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify docs/appcast.xml`: 통과.
  - GitHub Pages appcast cache-busted 확인: `0.1.7`, `sparkle:version 23`, notarized DMG URL, `application/x-apple-diskimage`, `sparkle:edSignature` 확인.

### 2026-05-20 발화자/참석자 popover UI

- 수정 내용:
  - 상단 참석자 metadata를 dropdown menu에서 popover로 변경했다.
  - raw transcript preview 갱신 시 실제 발화자 목록을 캐시하고, 상단에는 `첫 발화자 외 n명 발화 · 참석자 m명` 형태로 요약한다.
  - popover 안에서 `발화자`와 `참석자`를 별도 섹션으로 구분해 확인할 수 있게 했다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.

### 2026-05-20 Meeting Intelligence metadata/diagnostics UI 조정

- 수정 내용:
  - Overview 탭의 `LLM 사용량 추정`과 `Analysis 실행 로그`를 `Risks / Notes` 아래로 이동했다.
  - 상단 참석자 metadata를 전체 comma string 대신 `첫 참석자 외 n명` 요약으로 표시하고, dropdown에서 전체 참석자 목록을 확인할 수 있게 했다.
  - raw transcript 참석자 highlight multi-select는 구현하지 않고 후속 계획으로만 정리했다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.

### 2026-05-20 Search latency fast path 적용

- 수정 내용:
  - UI search에서 `segments_semantic` full scan을 기본 비활성화하고 SQLite FTS keyword search만 즉시 실행하게 했다.
  - 검색어 입력 시 raw transcript 포함 history cache rebuild를 시작하지 않게 해 전체 파일 재읽기로 인한 수초 단위 지연을 제거했다.
  - `lastSearchDiagnostics`에 `semanticEnabled`를 기록해 fast path 여부를 확인할 수 있게 했다.
  - 검색 DB/semantic index는 계속 생성되지만, 즉시 검색 경로는 UI 반응성을 우선한다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.

### 2026-05-20 Search raw fallback 복구

- 수정 내용:
  - Search quality v2 최적화 후 검색어 입력 시 raw transcript 포함 history cache rebuild 트리거가 빠져 DB 준비 전 원문 검색이 동작하지 않는 문제를 수정했다.
  - 검색어 debounce 완료 시 raw transcript search cache가 아직 없으면 background `refreshMeetingHistory(force: true, includeRawTranscriptSearch: true)`를 시작하고, 동시에 현재 cache 기준 검색 결과를 먼저 갱신한다.
  - DB 색인이 늦거나 진행 중이어도 local/raw fallback 검색이 살아나도록 했다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.

### 2026-05-20 Search DB 색인 main thread blocking 해소

- 수정 내용:
  - 검색 DB `storedSignature()` 확인, raw transcript 포함 history rebuild, SQLite FTS/semantic index rebuild를 모두 background detached task로 이동했다.
  - `MeetingSearchDatabase.rebuild`와 section insert loop에 cancellation check를 추가해 refresh/cancel 시 오래 도는 색인을 중단할 수 있게 했다.
  - 검색 DB 색인 중에는 검색 품질이 일시적으로 낮아질 수 있지만 앱 스크롤/입력/회의 화면을 우선하도록 조정했다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.

### 2026-05-20 Search quality v2 hybrid ranking

- 수정 내용:
  - `MeetingHistorySearch`에 `local-semantic-v2` deterministic semantic vector를 추가했다.
  - SQLite search DB schema를 v2로 올리고 `segments_semantic` table에 raw transcript/structured intelligence chunk vector를 저장하게 했다.
  - 기존 `segments_fts` keyword score와 semantic vector score를 path별 best match로 merge해 hybrid ranking을 만든다.
  - schema version metadata를 확인해 기존 DB는 자동 재색인되게 했다.
  - search diagnostics metadata에 query, provider, estimated cost 0, elapsed milliseconds를 저장한다.
  - non-empty search result 계산은 DB query, local fallback, facet filter, sort까지 detached task에서 수행하고 generation guard로 stale result를 버린다.
  - search task priority를 utility로 낮추고 SQLite row scan 중 cancellation check를 넣어 새 검색어 입력/스크롤과 경쟁하지 않게 했다.
  - main actor는 최종 result array 반영만 수행해 검색 결과 업데이트 시 UI thread blocking 가능성을 줄였다.
  - README의 Search 설명과 `tasks.md` Done archive를 갱신했다.
- 검증:
  - `swift test`: 통과. 93개 test / 20개 suite가 통과했다.
  - `swift build -c release`: 통과.
  - `git diff --check`: 통과.

### 2026-05-19 Release asset을 ZIP에서 DMG로 전환

- 수정 내용:
  - `scripts/package_release.sh`가 release archive로 zip 대신 DMG를 생성하게 변경했다.
  - `scripts/notarize_app.sh`가 app bundle notarization/staple 후 최종 배포 DMG를 만들고, DMG 자체도 codesign/notarize/staple/spctl 검증을 수행하게 했다.
  - `scripts/publish_github_release.sh`의 기본 asset을 `Meeting-Rescue-vX.Y.Z-notarized.dmg`로 바꾸고, Sparkle appcast enclosure type을 `application/x-apple-diskimage`로 변경했다.
  - README의 release 산출물 설명을 DMG 기준으로 갱신했다.
  - `VERSION`을 `0.1.2`로 올렸다.
  - `tasks.md`의 release packaging/publish 항목을 DMG 기준으로 정리했다.
- 검증:
  - `bash -n scripts/build_app.sh scripts/package_release.sh scripts/notarize_app.sh scripts/publish_github_release.sh`: 통과.
  - `swift test`: 통과. 91개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.2.dmg`와 `.sha256` 생성.
  - `shasum -a 256 -c dist/Meeting-Rescue-v0.1.2.dmg.sha256`: 통과.
  - `./scripts/notarize_app.sh`: 통과. App notarization status `Accepted`, submission id `189ebb1a-14af-4330-bba2-7fe20830cdd5`.
  - DMG notarization status `Accepted`, submission id `313234a9-ec4f-4545-a368-1fac884eb29f`.
  - `xcrun stapler validate dist/Meeting-Rescue-v0.1.2-notarized.dmg`: 통과.
  - `spctl -a -t open --context context:primary-signature -vv dist/Meeting-Rescue-v0.1.2-notarized.dmg`: `accepted`, `source=Notarized Developer ID`.
  - `./scripts/publish_github_release.sh`: 통과. `v0.1.2` public release에 notarized DMG와 checksum asset 업로드.
  - `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify docs/appcast.xml`: 통과.
  - `curl -L https://breadceo.github.io/meeting-rescue/appcast.xml`: `0.1.2`, DMG asset URL, `application/x-apple-diskimage`, `sparkle:edSignature` 확인.
  - 실제 업데이트 검증: `/tmp/MeetingRescue-DMGOld.app`의 `0.1.1` build `4`에서 Settings의 `업데이트 확인`을 눌러 Sparkle이 `0.1.2` DMG를 다운로드/설치하게 했고, 설치 후 app bundle이 `0.1.2` build `6`으로 변경되고 재실행됨을 확인했다.
- 커밋/릴리즈:
  - DMG 전환 commit: `004de61 Switch release artifacts to DMG`.
  - Appcast 갱신 commit: `4151002 Update Sparkle appcast for v0.1.2`.
  - Release tag: `v0.1.2` -> `004de61`.
  - Release URL: `https://github.com/breadceo/meeting-rescue/releases/tag/v0.1.2`.

### 2026-05-19 Sparkle 자동 업데이트 / GitHub Release 발행 완료

- 수정 내용:
  - Sparkle 2.9.2를 SwiftPM dependency로 추가하고 `SPUStandardUpdaterController`를 앱에 연결했다.
  - Settings와 app menu에 `업데이트 확인`을 추가했다. GitHub Release 페이지를 여는 방식이 아니라 Sparkle update check를 호출한다.
  - `scripts/build_app.sh`가 Sparkle framework를 app bundle에 포함하고 `SUFeedURL`, `SUPublicEDKey`, signed feed, automatic update 설정을 `Info.plist`에 주입하게 했다.
  - Sparkle public key는 repo에 포함하고, private key backup은 gitignored `private/`에 두었다.
  - `scripts/publish_github_release.sh`를 추가해 notarized zip/checksum을 GitHub Release에 올리고, release asset signature를 포함한 `docs/appcast.xml`을 생성/서명하게 했다.
  - GitHub Pages를 `main` branch의 `/docs` source로 활성화했다.
  - `VERSION`을 `0.1.1`로 올렸다.
  - `tasks.md`에서 `GitHub Release publish command`, `Sparkle auto-update`를 `Done`으로 변경하고, manual release-page updater는 Sparkle로 대체됨을 기록했다.
- 검증:
  - `swift build`: 통과.
  - `swift test`: 통과. 91개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. Sparkle framework 포함, rpath `@executable_path/../Frameworks`, `Info.plist` update key 확인.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.1.zip`, `.sha256`, `release-notes-v0.1.1.md` 생성.
  - `./scripts/notarize_app.sh`: 통과. Notarization status `Accepted`, submission id `25ffd7e5-b18a-4fe6-9823-44c5cb70cf9c`.
  - `xcrun stapler validate "dist/Meeting Rescue.app"`: 통과.
  - `spctl -a -t exec -vv "dist/Meeting Rescue.app"`: `accepted`, `source=Notarized Developer ID`.
  - `codesign --verify --deep --strict --verbose=2 "dist/Meeting Rescue.app"`: 통과.
  - `./scripts/publish_github_release.sh`: 통과. `v0.1.1` tag, public GitHub Release, notarized zip/checksum asset, signed appcast 생성.
  - `.build/artifacts/sparkle/Sparkle/bin/sign_update --verify docs/appcast.xml`: 통과.
  - `curl -L https://breadceo.github.io/meeting-rescue/appcast.xml`: `0.1.1`, `sparkle:version 4`, release asset URL, `sparkle:edSignature` 확인.
  - 실제 업데이트 검증: `/tmp/MeetingRescue-SparkleOld.app`의 `0.1.0` build `3`에서 Settings의 `업데이트 확인`을 눌러 Sparkle update dialog를 띄우고 `설치 & 재실행`을 수행했다. 설치 후 해당 app bundle이 `0.1.1` build `4`로 변경되고 재실행됨을 확인했다.
- 커밋/릴리즈:
  - Sparkle 통합 commit: `c6978e6 Add Sparkle automatic updates`.
  - Appcast 갱신 commit: `6684ec5 Update Sparkle appcast for v0.1.1`.
  - Release tag: `v0.1.1` -> `c6978e6`.
  - Release URL: `https://github.com/breadceo/meeting-rescue/releases/tag/v0.1.1`.

### 2026-05-19 Notary credential 저장 및 notarization 완료

- 수정 내용:
  - Apple notary credential을 `meeting-rescue-notary` Keychain profile로 저장했다. credential 값은 repo/local config에 저장하지 않았다.
  - `scripts/notarize_app.sh`로 `Meeting Rescue.app`을 Apple notary service에 제출했고 notarization을 완료했다.
  - notarization 성공 후 app bundle에 ticket을 staple하고 최종 notarized zip과 checksum을 생성했다.
  - `tasks.md`의 `Developer ID signing + notarization` 상태를 `Done`으로 변경했다.
- 검증:
  - `xcrun notarytool store-credentials "meeting-rescue-notary" ...`: 통과. credential validation과 Keychain 저장이 성공했다.
  - `./scripts/notarize_app.sh`: 통과.
  - Notarization status: `Accepted`.
  - Submission ID: `6db1b9b7-0ea1-437d-b517-6af378df54e0`.
  - `xcrun stapler staple "dist/Meeting Rescue.app"`: 통과.
  - `xcrun stapler validate "dist/Meeting Rescue.app"`: 통과.
  - `spctl -a -t exec -vv "dist/Meeting Rescue.app"`: `accepted`, `source=Notarized Developer ID`.
  - `codesign --verify --deep --strict --verbose=2 "dist/Meeting Rescue.app"`: 통과.
  - 최종 산출물: `dist/Meeting-Rescue-v0.1.0-notarized.zip`.
  - 최종 checksum: `dist/Meeting-Rescue-v0.1.0-notarized.zip.sha256`.
  - `shasum -a 256 -c dist/Meeting-Rescue-v0.1.0-notarized.zip.sha256`: 통과.
  - `git diff --check`: 통과.

### 2026-05-19 Release packaging / notarization scripts 추가

- 수정 내용:
  - `VERSION`을 추가해 release version의 source of truth를 만들었다.
  - `scripts/build_app.sh`가 `VERSION`을 기본 version으로 읽고, `CFBundleVersion`은 별도 override가 없으면 git commit count를 사용하게 했다.
  - `scripts/package_release.sh`를 추가했다. app build, `codesign --verify`, `ditto --keepParent` zip 생성, SHA-256 checksum, release note 초안을 생성한다.
  - release note 초안은 기본적으로 최신 version/build 값으로 다시 생성하고, 필요한 경우 `OVERWRITE_RELEASE_NOTES=0`으로 보존할 수 있게 했다.
  - `scripts/notarize_app.sh`를 추가했다. Developer ID signed app을 notary 제출용 zip으로 만들고, `xcrun notarytool submit --wait`, `stapler staple`, `stapler validate`, `spctl`, 최종 notarized zip/checksum 생성을 수행한다.
  - `tasks.md`에서 `Release versioning`과 `Release packaging command`를 `Done`으로 표시하고, 실제 Apple notary 제출이 남은 `Developer ID signing + notarization`은 `In Progress`로 표시했다.
- 검증:
  - `swift test`: 통과. 91개 test / 20개 suite가 통과했다.
  - `bash -n scripts/build_app.sh scripts/package_release.sh scripts/notarize_app.sh`: 통과.
  - `git diff --check`: 통과.
  - `./scripts/package_release.sh`: 통과. `dist/Meeting-Rescue-v0.1.0.zip`, `.sha256`, `release-notes-v0.1.0.md`를 생성했다.
  - `sed -n '1,12p' dist/release-notes-v0.1.0.md`: release note 초안의 Build 값이 `70`으로 갱신됨을 확인했다.
  - `plutil -extract CFBundleShortVersionString raw -o - "dist/Meeting Rescue.app/Contents/Info.plist"`: `0.1.0` 확인.
  - `plutil -extract CFBundleVersion raw -o - "dist/Meeting Rescue.app/Contents/Info.plist"`: `70` 확인. git commit count와 일치했다.
  - `codesign -dv "dist/Meeting Rescue.app"`: `Identifier=com.zigbang.meeting-rescue`, `TeamIdentifier=7AX2JZT3L8`, hardened runtime flag, timestamp 확인.
  - `shasum -a 256 -c dist/Meeting-Rescue-v0.1.0.zip.sha256`: 통과.
  - `RELEASE_CONFIG_FILE=/tmp/meeting-rescue-no-such-env scripts/notarize_app.sh`: 기대한 실패. `NOTARY_KEYCHAIN_PROFILE`이 없으면 제출하지 않고 중단함을 확인했다.
  - 실제 `xcrun notarytool submit`은 `meeting-rescue-notary` Keychain profile 준비 이후 실행해야 하므로 이번 검증에서는 제출하지 않았다.

### 2026-05-19 Release local config 분리

- 수정 내용:
  - `config/release.local.env`와 `config/*.secret.env`를 `.gitignore`에 추가했다.
  - `config/release.env.example`을 추가해 bundle id, version/build, Team ID, Developer ID signing identity, notary Keychain profile 이름을 문서화했다.
  - `scripts/build_app.sh`가 `config/release.local.env`를 자동 source하고, `BUNDLE_ID`, `APP_VERSION`, `BUILD_NUMBER`, `APP_COPYRIGHT`, `SIGN_IDENTITY`, `CODESIGN_ENTITLEMENTS` override를 받을 수 있게 했다.
  - `SIGN_IDENTITY`가 있으면 `codesign --options runtime --timestamp`로 Developer ID signing을 수행하고, 없으면 기존처럼 ad-hoc signing을 유지한다.
  - `tasks.md`의 `Release versioning` backlog에 release local config는 gitignored 파일로 관리한다는 요구사항을 추가했다.
- 검증:
  - `swift test`: 통과. 91개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `config/release.local.env` 적용 전 ad-hoc signing 경로가 성공했다.
  - `./scripts/build_app.sh`: 통과. `config/release.local.env` 적용 후 `com.zigbang.meeting-rescue` bundle id와 Developer ID signing 경로가 성공했다.
  - `plutil -extract CFBundleIdentifier raw -o - "dist/Meeting Rescue.app/Contents/Info.plist"`: `com.zigbang.meeting-rescue` 확인.
  - `codesign -dv "dist/Meeting Rescue.app"`: `TeamIdentifier=7AX2JZT3L8`, `flags=0x10000(runtime)`, timestamp 포함 signing 확인.
  - `codesign --verify --deep --strict --verbose=2 "dist/Meeting Rescue.app"`: 통과.
  - `git check-ignore -v config/release.local.env`: `.gitignore`의 `config/release.local.env` rule로 ignore됨을 확인.

### 2026-05-19 Release 운영 레이어 backlog 정리

- 수정 내용:
  - `tasks.md`의 `Team distribution, signing, notarization, update flow` 단일 backlog를 실행 가능한 순서로 분리했다.
  - 새 항목은 `Release versioning`, `Release packaging command`, `Developer ID signing + notarization`, `GitHub Release publish command`, `Manual update check`, `Sparkle auto-update` 순서로 정리했다.
  - GitHub Release publish는 notarized zip만 업로드하도록 명시했고, 자동 업데이트는 manual update check 안정화 이후 별도 phase로 두었다.
- 검증:
  - `git diff --check`: 통과.

### 2026-05-19 GitHub용 한국어 README 정리

- 수정 내용:
  - `README.md`를 GitHub 공개용 한국어 문서로 재작성했다.
  - Overview, 주요 기능, 요구사항, 빠른 시작, 실행 방법, transcript 폴더, Soma 자동 감지, LLM provider, analysis 동작 방식, search, Test Run, Markdown export, 저장 위치, 개인정보/보안, macOS 권한 팝업, 개발 명령, 프로젝트 구조, 제한 사항, roadmap을 정리했다.
  - 개인 로컬 경로 중심의 수동 검증 절차를 줄이고, 사용자가 직접 선택하는 transcript folder와 Application Support 저장 구조 중심으로 설명했다.
- 검증:
  - `git diff --check`: 통과.
  - README-only 변경이라 `swift test`와 app rebuild는 실행하지 않았다.

### 2026-05-19 Settings 온보딩 버튼 노출 보강

- 원인:
  - Settings 하단 액션 영역에 `onboarding 다시 보기` 버튼을 추가했지만, 실제 실행 화면에서 보이지 않는 케이스가 확인됐다.
- 수정 내용:
  - Settings header 우측에 `온보딩` 버튼을 추가해 하단 액션 영역과 별개로 항상 바로 접근할 수 있게 했다.
  - 기존 하단 `onboarding 다시 보기` 버튼은 유지했다.
- 검증:
  - `swift test`: 통과.
  - `git diff --check`: 통과.
  - `swift build`: 통과.
  - `./scripts/build_app.sh`: 통과.
  - app relaunch 수행.

### 2026-05-19 Live 중 검색 DB build defer

- 원인:
  - `scanFolder()`가 최신 live transcript를 갱신하기 전에 `refreshMeetingHistory()`를 먼저 호출했다.
  - 이 순서에서는 현재 쓰이는 live file이 search index exclusion 대상에서 빠지는 순간이 생길 수 있고, live file modification이 계속 바뀌면서 검색 DB signature 확인이 반복되어 UI에 `검색 DB 확인 중`이 자주 표시됐다.
- 수정 내용:
  - `scanFolder()`에서 최신 transcript candidate와 live 상태를 먼저 반영한 뒤 meeting history/search refresh를 실행하게 순서를 바꿨다.
  - 최신 live transcript가 아직 end marker를 포함하지 않았고 analysis state도 completed가 아니면 SQLite FTS5 rebuild/check를 defer한다.
  - defer 중에는 진행 UI를 `checking/indexing`으로 바꾸지 않아 live meeting 중 `검색 DB 확인 중` 표시가 반복되지 않게 했다.
  - live transcript end marker를 감지해 completed로 저장하면 `refreshMeetingHistory(force: true)`를 호출해 회의 종료 시 검색 DB 갱신을 재개한다.
  - history mode에서도 최신 live transcript가 열려 있으면 해당 live file 기준으로 search index rebuild를 미룬다.
- 검증:
  - `swift test`: 통과. 91개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다.

### 2026-05-19 최근 흐름 timestamp `[00:00]` 표시 수정

- 원인:
  - 최신 L17 meeting analysis state에서 LLM이 topic timestamp를 `2026-05-19T00:05:00Z`, `2026-05-19T01:25:00Z`처럼 날짜가 붙은 ISO 형태로 반환했다.
  - UI는 `MeetingTimestampFormatter`에서 ISO timestamp를 실제 절대시각으로 해석했고, meeting start(`2026-05-19 09:45:34`)보다 이전 시각이라 음수 elapsed를 `0`으로 clamp해 `[00:00]~[00:00]`처럼 표시했다.
- 수정 내용:
  - ISO timestamp가 meeting start보다 이전이고 같은 날짜의 자정 기준 transcript elapsed처럼 보이면 clock portion을 transcript elapsed로 fallback 표시한다.
    - 예: `2026-05-19T00:05:00Z` → `[00:05]`
    - 예: `2026-05-19T01:25:00Z` → `[01:25]`
    - 예: `2026-05-19T00:06:53Z` → `[06:53]`
  - timeline merge 정렬도 같은 ISO-like elapsed timestamp를 이해하도록 보강했다.
  - LLM prompt에 topic/candidate timestamp는 transcript 원문의 회의 경과 시간(`04:13` 또는 `[04:13]`)만 사용하고 ISO timestamp를 새로 만들지 말라고 명시했다.
- 검증:
  - `swift test`: 통과. 91개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다.

### 2026-05-19 Onboarding layer 구현 및 Q&A backlog 정리

- 수정 내용:
  - `tasks.md`의 Q&A backlog를 `Single Meeting Q&A`, `Multi-Meeting Source Q&A`, `NotebookLM-style Q&A Threads` 순서로 정리했다.
  - Q&A v1은 사용자가 선택한 LLM provider/model preset을 재사용하고, streaming 없이 Codex `codex exec` 기반 non-streaming provider로도 시작할 수 있게 방향을 기록했다.
  - `AppSettings.hasCompletedOnboarding`을 추가해 onboarding 완료 여부를 저장한다.
  - `SomaRecordingsFolderDetector`를 추가했다. `/Users/ethan/Library/Preferences/com.somadevelopmentco.soma.plist`의 `CustomChatLogDirectory`만 읽고, 값이 없거나 유효한 디렉터리가 아니면 fallback 없이 `nil`을 반환한다.
  - onboarding sheet를 추가해 recordings folder, LLM provider, Meetings/Raw Transcript/Meeting Intelligence 레이아웃과 상단 버튼을 안내한다.
  - 감지된 Soma folder는 바로 hardcode 사용하지 않고 macOS folder picker에서 사용자가 확인한 뒤 security-scoped bookmark로 저장하게 했다.
  - `LLMProviderAvailabilityDetector`를 추가해 Codex/Claude Code 실행 파일을 PATH에서 확인하고, 첫 실행에서 둘 다 없으면 automatic Meeting Intelligence를 disabled로 시작하게 했다. 기존 저장 provider 선택은 덮어쓰지 않는다.
  - `chooseFolder`의 `/Users/ethan/Documents/Recordings` hardcoded initial directory를 제거하고, 선택된 폴더 또는 감지된 Soma folder만 초기 위치로 사용하게 했다.
  - Settings에서 onboarding을 다시 열 수 있는 버튼을 추가했다.
- 검증:
  - `swift test`: 통과. 89개 test / 20개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다.

### 2026-05-18 Final analysis patch/continuation 우선 적용

- 원인:
  - final analysis가 이전 snapshot이 있어도 full snapshot schema를 우선 사용해, 긴 회의 후반 catch-up에서 prompt/output이 커지고 timeout 가능성이 높았다.
  - final chunk 하나가 성공해도 이어지는 continuation이 남아 있으면 상태 표시와 retry 이름이 헷갈릴 수 있었다.
  - `final-continue` 실패가 meeting-level retry counter를 공유해 `final-retry-2`처럼 보이는 로그를 만들었다.
- 수정 내용:
  - `final`, `final-retry-*`, `final-continue`, `final-continue-retry-*`도 previous snapshot이 있으면 patch output schema를 사용하게 했다.
  - final catch-up prompt를 compact patch 중심으로 정리하고, 남은 transcript chunk의 추가 흐름/결정/action/note만 반영하도록 명시했다.
  - final chunk 성공분은 즉시 기존 snapshot에 merge/save하고 UI에 반영하되, 남은 chunk가 있으면 analysis status를 `running`으로 유지한다.
  - final retry counter를 meeting 단위에서 failed chunk range 단위로 바꾸고, continuation 실패는 `final-continue-retry-N`으로 기록하게 했다.
  - topic이 5분 이상 계속 열린 채로 남지 않도록 agenda/논점/speaker focus/실행 방향 전환 시 topic split을 요구하는 prompt를 보강했다.
- 검증:
  - `swift test`: 통과. 84개 test / 19개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다. 실행 중인 앱/회의를 끊지 않기 위해 새 bundle만 빌드했다.

### 2026-05-18 Test Run trigger preset 정렬

- 원인:
  - Test Run은 `Balanced` preset 도입 후에도 별도 compressed trigger(`8초 min wait`, `18~24초 max wait`, `8줄`, `900자`)를 계속 사용했다.
  - 마지막 L1 회의 Test Run에서 12개 attempt가 남았고, 대부분 `automatic-max-wait-flush`로 3~7줄/85~342자 같은 작은 batch를 분석했다.
  - 11번째 attempt는 3줄/212자 batch에서 `LLM provider 실행 시간이 초과되었습니다.`로 실패했고 retry가 예약됐다.
- 수정 내용:
  - Test Run도 live와 같은 `analysisTriggerPreset` threshold를 사용하게 했다.
  - Test Run의 wait 계산은 wall-clock `Date()` 대신 transcript 경과 시간 기반 synthetic date를 사용한다.
  - 배속 재생에서는 실제 wall-clock만 빨라지고, trigger cadence는 회의 경과 시간 기준 `Balanced 180/300` 등 preset 의도를 따른다.
  - Settings 설명에서 compressed trigger 문구를 제거했다.
- 검증:
  - `swift test`: 통과. 83개 test / 19개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.

### 2026-05-18 Analysis trigger preset 및 Balanced 기본값 적용

- 사전 검토:
  - `Zigbang(2F)_L17` 회의를 제외한 최근 transcript 30개를 timestamp/dialogue 기준으로 시뮬레이션했다.
  - 기존 `45s/150s/8줄/900자` 정책은 30개 샘플에서 총 810회, 회의당 평균 27.0회 호출로 추정됐다.
  - `120s/300s/20줄/1500자` 정책은 총 338회, 회의당 평균 11.3회 호출로 추정됐다.
  - `180s/300s/24줄/1800자` 정책은 총 256회, 회의당 평균 8.5회 호출로 추정됐다.
  - `300s/300s/30줄/2200자` 정책은 총 175회, 회의당 평균 5.8회 호출로 추정됐다.
- 수정 내용:
  - `AnalysisTriggerPreset`을 추가했다.
  - 기본 preset을 `Balanced`로 설정했다.
  - preset 구성:
    - `Responsive`: `minBatchWaitSeconds 120`, `maxBatchWaitSeconds 240`, `minNewDialogueLines 20`, `minNewTranscriptCharacters 1500`
    - `Balanced`: `minBatchWaitSeconds 180`, `maxBatchWaitSeconds 300`, `minNewDialogueLines 24`, `minNewTranscriptCharacters 1800`
    - `Economy`: `minBatchWaitSeconds 300`, `maxBatchWaitSeconds 300`, `minNewDialogueLines 30`, `minNewTranscriptCharacters 2200`
  - Settings 화면에서 `analysis trigger` preset을 선택하고 현재 threshold 설명을 볼 수 있게 했다.
  - 기존 settings JSON은 `analysisTriggerPreset`이 없어도 `Balanced`로 decode되게 했다.
  - Test Run은 빠른 동적 검증을 위해 기존 compressed trigger timing을 유지한다.
- 검증:
  - `swift test`: 통과. 82개 test / 19개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다. 실행 중인 앱/회의를 끊지 않기 위해 새 bundle만 빌드했다.

### 2026-05-18 Hybrid automatic analysis trigger 적용

- 수정 내용:
  - `AnalysisTriggerPolicy`를 추가해 automatic analysis 실행 조건을 pure core policy로 분리했다.
  - live automatic trigger를 45초 고정 cadence에서 hybrid trigger로 변경했다.
  - 실행 조건은 새 의미 발화 8줄, 새 transcript 900자, 또는 마지막 automatic attempt 이후 최대 150초 flush다.
  - 회의 시작 후 60초 gate와 single-flight guard는 유지했다.
  - system-only 또는 짧은 인사/응답만 있는 low-value batch는 LLM 호출 없이 `skipped` attempt로 기록한다.
  - 실패 retry는 기존 cursor를 전진하지 않고, 다음 eligible tick에서 이전 미분석 chunk를 다시 포함한다.
  - automatic reason을 `automatic-min-dialogue-lines`, `automatic-min-transcript-characters`, `automatic-max-wait-flush`처럼 세분화해 attempt log에서 trigger reason을 볼 수 있게 했다.
  - automatic 첫 live patch에서도 `fullTranscript` 대신 `newTranscriptChunk`를 사용하게 해 compact patch prompt 원칙을 강화했다.
  - previous snapshot compact limit을 topic 4개, decision/action 후보 6개, recent transcript context 800자로 줄였다.
  - Settings의 `analysis cadence` 문구를 `min batch wait`로 바꾸고 hybrid trigger 조건을 설명했다.
- 검증:
  - `swift test`: 통과. 80개 test / 19개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다. 실행 중인 앱/회의를 끊지 않기 위해 새 bundle만 빌드했다.

### 2026-05-18 Automatic Meeting Intelligence toggle 추가

- 수정 내용:
  - `AppSettings.automaticAnalysisEnabled`를 추가하고 기존 settings JSON은 기본값 `true`로 decode되게 했다.
  - Settings 화면에 `automatic meeting intelligence` toggle을 추가했다.
  - toggle을 끄면 live/test-run cadence analysis, 회의 종료 marker 기반 final analysis, final retry를 실행하지 않는다.
  - 수동 `분석` 버튼은 toggle off 상태에서도 계속 사용할 수 있다.
  - `saveSettings()`가 새 설정값을 보존하도록 수정했다.
  - toggle off 시 이미 실행 중인 automatic/final analysis task는 cancel하고 stale 상태 메시지를 남긴다.
- 현재 실행 상태:
  - `~/Library/Application Support/MeetingRescue/settings.json`에 `"automaticAnalysisEnabled": false`를 저장했다.
  - `dist/Meeting Rescue.app`을 재빌드 후 재시작했다.
  - 재시작 후 Meeting Rescue app PID `20485`가 실행 중이고, Meeting Rescue schema 기반 `codex exec` process가 새로 뜨지 않는 것을 확인했다.
- 검증:
  - `swift test`: 통과. 74개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - 중간 검증에서 `.stale` enum payload 누락으로 compile error가 발생했고, stale message를 포함하도록 수정한 뒤 위 검증을 재실행해 통과했다.

### 2026-05-18 Analysis run trace 추가

- 수정 내용:
  - analysis attempt log에 `runTrace`를 추가해 provider CLI 실행 단계를 저장한다.
  - trace에는 executable, sanitized arguments, working directory, input/output/stderr bytes, exit code, timeout 여부, 단계별 event를 저장한다.
  - event는 `spawn process`, `write stdin`, `wait for process`, `read stdout`, `read stderr`, `extract structured output`, `decode provider output` 같은 단계와 시작 offset/duration/detail을 포함한다.
  - timeout 또는 non-zero exit 실패에서도 가능한 경우 trace를 attempt log에 남기도록 `LLMProviderError`에 trace를 연결했다.
  - Analysis 실행 상세 화면에 `Run Trace` 섹션을 추가해 CLI startup/auth/provider wait 구간을 구분해 볼 수 있게 했다.
- 한계:
  - provider가 숨긴 internal reasoning 또는 chain-of-thought는 노출/저장하지 않는다.
  - `wait for process`에는 CLI 인증, model request, provider processing, schema validation 등 CLI 내부 시간이 합쳐질 수 있다. stream-json/app-server provider를 쓰면 이후 더 세분화할 수 있다.
- 검증:
  - `swift test`: 통과. 73개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다. 실행 중인 앱을 끊지 않기 위해 새 bundle만 빌드했다.

### 2026-05-18 Live transcript append 중 검색 DB 재확인 반복 수정

- 원인:
  - `scanFolder()`가 주기적으로 `refreshMeetingHistory()`를 호출하고, live transcript append로 active file의 modification date가 계속 바뀌었다.
  - `MeetingHistoryBuilder.fileSignature`가 모든 transcript file의 modification date를 포함했고, `startSearchIndexBuildIfNeeded`가 이 signature 변경을 검색 DB stale 상태로 판단했다.
  - 그 결과 live session에서 문구가 추가될 때마다 `검색 DB 확인 중`이 표시되고, raw transcript indexing/rebuild 경로가 반복될 수 있었다.
- 수정 내용:
  - live watch 중 아직 완료되지 않은 active transcript file은 search index freshness signature에서 제외한다.
  - 검색 DB rebuild 시에도 해당 active transcript file을 indexing 대상에서 제외해, 회의 중 append만으로 DB가 계속 stale해지지 않게 했다.
  - 같은 search index signature가 이미 ready 상태이면 `검색 DB 확인 중` 상태로 다시 전환하지 않도록 `lastReadySearchIndexSignature` guard를 추가했다.
  - history list signature는 유지해 새 파일/회의 전환 감지는 계속 가능하게 했다.
- 검증:
  - `swift test`: 통과. 72개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다. 실행 중인 회의를 끊지 않기 위해 새 bundle만 빌드했다.

### 2026-05-18 Backlog 정리

- 수정 내용:
  - `tasks.md` Backlog를 `Next`, `Provider / Infrastructure`, `Integrations / Distribution`, `Done Archive`로 재구성했다.
  - `Not Started` 항목을 상단으로 올리고, 완료된 항목은 한 줄 요약 중심의 archive로 압축했다.
  - NotebookLM-style Q&A, hybrid analysis trigger, Search quality v2를 다음 후보로 명확히 분리했다.
  - 구현 세부와 검증 이력은 `execution-log.md`를 우선 보도록 Backlog 설명을 정리했다.
- 검증:
  - `git diff --check`: 통과.

### 2026-05-18 Claude Code subscription provider 추가

- 조사:
  - Claude Code official docs 기준 `claude -p`는 non-interactive print mode이고, `--output-format json`은 `result/session_id/metadata` wrapper를 반환한다.
  - `--json-schema`를 함께 쓰면 schema-conforming 결과가 `structured_output` 필드에 들어간다.
  - `--bare`는 startup 최적화에는 유리하지만 OAuth/keychain을 읽지 않고 `ANTHROPIC_API_KEY` 또는 `apiKeyHelper` 인증을 요구하므로 subscription login provider 기본값으로 쓰지 않는다.
  - local CLI 확인: `command -v claude`가 `/Users/ethan/.local/bin/claude`를 반환했고, `claude --version`은 `2.1.142 (Claude Code)`였다.
- 수정 내용:
  - `LLMProviderKind.claudeCode`와 `ClaudeCodeProvider`를 추가했다.
  - Claude Code provider는 `claude -p --output-format json --input-format text --no-session-persistence --json-schema <schema>`를 사용한다.
  - Claude Code `structured_output` wrapper를 해제해 기존 full snapshot/live patch decode 경로에 연결했다.
  - provider 설정 UI와 header summary에서 Claude Code를 선택할 수 있게 했다.
  - Claude Code preset은 `automatic` CLI default, `economy/balanced` sonnet, `frontier` opus로 매핑하고 effort는 low/medium/high로 적용한다.
  - Anthropic token price 참고값 기반 usage estimate를 Claude Code provider에도 표시한다. 실제 subscription billing/credit과 다를 수 있다.
  - `tasks.md`에 NotebookLM-style full meeting Q&A streaming 화면 구성을 후속 backlog로 추가했다.
- 검증:
  - `swift test`: 통과. 72개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - 실제 Claude LLM 호출은 subscription credit 사용을 피하기 위해 수행하지 않았다. CLI 존재/버전, provider arguments, schema wrapper parsing은 검증했다.

### 2026-05-18 Analysis 실행 로그 accordion UI 적용

- 수정 내용:
  - Analysis 실행 로그 section을 accordion 형태로 바꿨다.
  - 접힌 상태에서는 최신 attempt의 reason/status/time/요약만 보이고, 펼친 상태에서는 현재 보관 중인 최대 40개 attempt가 최신순으로 보인다.
  - 접힌 최신 attempt 요약도 클릭하면 기존처럼 Analysis 실행 상세 sheet를 연다.
- 검증:
  - `swift test`: 통과. 68개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다. 실행 중인 회의를 끊지 않기 위해 새 bundle만 빌드했다.

### 2026-05-18 Analysis attempt diagnostics 보강

- 수정 내용:
  - `AnalysisAttemptLog`에 optional `batchStats`를 추가해 기존 저장 JSON과 호환되도록 했다.
  - 실행되는 analysis attempt마다 trigger reason, 새 transcript 글자 수, 포함된 transcript 글자 수, 새 dialogue line 수, 포함된 dialogue line 수, cursor 범위를 저장한다.
  - Analysis 실행 로그 UI의 최근 4개 제한을 제거하고, 현재 보관 중인 최대 40개 attempt를 최신순으로 모두 보여주게 했다.
  - Analysis 실행 상세 metric과 markdown export에 batch stats를 표시한다.
- 검증:
  - `swift test`: 통과. 68개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch는 하지 않았다. 실행 중인 회의를 끊지 않기 위해 새 bundle만 빌드했다.

### 2026-05-18 Subscription provider 및 analysis trigger 전략 backlog 추가

- 수정 내용:
  - `tasks.md` Backlog에 `Subscription-based LLM provider 확장` 항목을 추가했다.
  - Codex CLI를 기본 strict schema provider로 유지하면서 Gemini CLI, GitHub Copilot CLI, Claude CLI, custom command provider를 구독 기반 후보로 검토하도록 기록했다.
  - `tasks.md` Backlog에 `Analysis trigger strategy를 transcript-progress 기반으로 전환` 항목을 추가했다.
  - 현재 45초 고정 cadence만 쓰는 방식보다 `새 transcript chunk가 일정량 이상 쌓였을 때 실행 + 최대 대기 시간이 지나면 flush`하는 hybrid trigger 전략을 추천 방향으로 기록했다.
- 판단:
  - live analysis는 초 단위 cadence만으로 실행하면 새 내용이 적을 때 불필요한 LLM 호출이 생기고, 발화가 몰릴 때는 반응이 늦을 수 있다.
  - `minNewDialogueLines`, `minNewTranscriptCharacters`, `maxBatchWaitSeconds`, `minBatchWaitSeconds`를 두고 attempt log에 trigger reason과 batch size를 남기는 방식이 품질/비용/반응성 균형이 더 좋다.
- 검증:
  - `git diff --check`: 통과.

### 2026-05-18 SQLite FTS5 meeting search index 적용

- 수정 내용:
  - `meeting-search.sqlite`를 Application Support에 만들고, `segments_fts` FTS5 virtual table에 meeting search segment를 저장하도록 했다.
  - 앱 시작 후 선택 폴더의 transcript file signature를 확인하고, DB가 없거나 오래됐으면 background에서 raw transcript line/title/metadata/summary/topic/decision/action segment를 재색인한다.
  - Search Meetings 영역에 `검색 DB 확인 중`, `검색 DB 생성 중 N/M`, 실패 상태를 보여주는 progress bar를 추가했다.
  - 검색어가 입력되면 SQLite FTS5 결과를 우선 사용하고, DB가 준비되지 않았거나 structured memory match가 있는 경우 기존 in-memory search를 fallback으로 사용한다.
  - 한국어 복합어/띄어쓰기 검색을 위해 FTS indexed text에 normalized/compact text와 2-4글자 n-gram token을 같이 넣었다.
  - 앱 시작 리스트 build는 raw transcript preview tokenization을 하지 않고 structured index만 만든다. raw transcript 검색은 DB 색인으로 분리했다.
- 검증:
  - `swift test`: 통과. 66개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - app relaunch/manual DB validation: 통과. `meeting-search.sqlite`가 생성됐고 `segments_fts` row count가 `52975`로 확인됐다.
  - `sqlite3 "$HOME/Library/Application Support/MeetingRescue/meeting-search.sqlite" "select path, field, timestamp, substr(text,1,80) from segments_fts where segments_fts match '\"마케팅\"' limit 5;"`: 통과. raw transcript timestamp가 있는 `마케팅` 결과가 반환됐다.

### 2026-05-18 Initial live analysis gating 및 history initial load 개선

- 확인:
  - 최신 Test Run session(`148549a12988915b-analysis.json`)의 최근 automatic success들은 prompt가 `JSON patch`를 포함하고 provider output key가 `currentIssue, topicTimelineUpserts, closeTopicIDs, decisionCandidateUpserts, actionItemCandidateUpserts, risksOrNotesAppend`인 patch JSON이었다.
  - 다만 snapshot이 없는 첫 automatic run은 `previousSnapshot == nil`이라 full `analysis-output.schema.json`을 사용했고, 이 경우 provider output이 `currentIssue, topicTimeline, decisionCandidates, actionItemCandidates, risksOrNotes`인 full snapshot으로 남았다.
- 수정 내용:
  - `AnalysisRequest.outputMode`를 `automatic` exact match가 아니라 `automatic*` reason 계열에 대응하도록 바꿨다.
  - snapshot이 없는 첫 automatic analysis도 local placeholder snapshot을 만든 뒤 live patch output으로 요청하도록 했다.
  - live patch prompt가 `newTranscriptChunk`뿐 아니라 첫 live patch의 `fullTranscript`도 source로 쓸 수 있음을 명시했다.
  - raw transcript 최신 elapsed timestamp가 60초 이상일 때만 automatic analysis를 시작하도록 했다. 초기 1분은 LLM judge를 하지 않는다.
  - 앱 시작 또는 active transcript reload 중 이미 종료 마커가 있는 파일을 읽어도 즉시 final analysis를 자동 실행하지 않도록 했다.
  - 앱 시작 직후 meeting history build에서는 raw transcript preview search index를 만들지 않고, 검색어가 입력된 뒤에만 raw transcript index를 포함해 다시 build하도록 했다.
- 원인 분석:
  - 첫 리스트 갱신 지연은 `/Users/ethan/Documents/Recordings`의 `.txt` 274개를 대상으로 analysis/session JSON, metadata preview, raw transcript preview 32KB, raw line별 `NaturalLanguage` token을 모두 미리 만들던 비용이 주 원인이었다.
  - 폴더 크기는 약 7.6MB로 크지 않지만, raw line section 수와 tokenizer 호출 수가 파일 수에 비례해 초기 list 표시를 늦췄다.
- 검증:
  - `jq`로 최근 attempt log 확인: 최신 automatic success는 patch output key를 사용했고, 과거 첫 automatic run만 full snapshot output이었다.
  - `find /Users/ethan/Documents/Recordings -maxdepth 1 -type f -name '*.txt' | wc -l`: 274개.
  - `swift test`: 통과. 66개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - `git diff --check`: 통과.

### 2026-05-18 Codex CLI PATH resolution

- 원인:
  - 앱에서 Codex provider 실행 시 `env: codex: No such file or directory` 오류가 발생했다.
  - 셸에서는 `codex`가 `/Users/ethan/.local/share/mise/installs/node/20.19.4/bin/codex`, `/opt/homebrew/bin/codex`, `/Applications/Codex.app/Contents/Resources/codex` 등에 존재하지만, GUI 앱 환경의 `PATH`에는 이 경로들이 빠질 수 있다.
- 수정 내용:
  - `CodexExecProvider.environment`가 기존 `PATH`를 유지하면서 `~/.local/bin`, `~/.local/share/mise/shims`, `/opt/homebrew/bin`, `/usr/local/bin`, `/Applications/Codex.app/Contents/Resources`, system bin 경로를 fallback으로 추가하도록 했다.
  - GUI app 환경에서도 `/usr/bin/env codex ...`가 CLI 후보 경로를 찾을 수 있게 했다.
- 검증:
  - `command -v codex; which -a codex`: 통과. shell 기준 여러 `codex` 후보 경로를 확인했다.
  - `env -i PATH='/opt/homebrew/bin:/usr/local/bin:/Applications/Codex.app/Contents/Resources:/usr/bin:/bin:/usr/sbin:/sbin' /usr/bin/env codex --version`: 통과. `codex-cli 0.124.0`.
  - `swift test`: 통과. 64개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - `git diff --check`: 통과.

### 2026-05-18 Live analysis patch output 및 Search quality 후속

- 수정 내용:
  - live 자동 분석에서 이전 snapshot이 있는 경우 full `AnalysisSnapshot` 대신 patch output schema(`analysis-patch-output.schema.json`)를 사용하도록 했다.
  - patch provider output을 기존 snapshot에 merge하는 `AnalysisSnapshotPatch`와 `AnalysisSnapshot.applyingPatch`를 추가했다.
  - `CodexExecProvider`와 `CustomCommandProvider`가 request output mode에 따라 patch/full snapshot decode를 선택하게 했고, patch decode 실패 시 full snapshot decode를 fallback으로 시도한다.
  - manual/final analysis는 기존 full snapshot/chunk continuation 경로를 유지했다.
  - 검색 index에 `NaturalLanguage.NLTokenizer` 기반 token, whitespace/punctuation 제거 compact normalization, local fuzzy edit distance, character n-gram phrase score를 추가했다.
  - `검색 품질`/`검색품질`, `마케팅 팀`/`마케팅팀`, 작은 영문 typo가 매칭되도록 search ranking test를 보강했다.
- 품질/성능 판단:
  - live tick의 schema-valid output 대상이 전체 snapshot에서 작은 patch로 줄어, 긴 회의에서 output generation 병목과 timeout 가능성을 낮추는 방향이다.
  - embedding 기반 hybrid search는 별도 저장소와 provider 비용/latency 설계가 필요해 후속 후보로 유지했다.
- 검증:
  - `swift test`: 통과. 63개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 및 ad-hoc signing 완료.
  - `git diff --check`: 통과.
  - manual validation: 실행 중인 app process `pid 80483`가 있어 회의 중단을 피하기 위해 relaunch는 하지 않았다. 새 bundle은 다음 실행부터 반영된다.

### 2026-05-18 Analysis 실행 상세 가로 스크롤 제거

- 원인:
  - `NSTextView` 기반 상세 panel이 원문 폭을 유지하도록 설정되어 긴 prompt/provider output line에서 가로 스크롤이 생겼다.
  - Provider Output JSON은 공백이 적은 긴 line이 많아 word wrapping만으로는 읽기 좋은 폭에 맞춰지지 않는다.
- 수정 내용:
  - Analysis 실행 상세의 prompt/provider output text view에서 horizontal scroller를 비활성화했다.
  - text container가 view width를 따라가도록 바꾸고, 긴 line은 character wrapping으로 panel 폭 안에서 줄바꿈되게 했다.
- 검증:
  - `swift test`: 통과. 58개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - app relaunch: 통과. 새 process `pid 80483`를 확인했다.
  - Computer Use validation: 통과. Analysis 실행 상세에서 prompt/provider output panel 하단의 가로 스크롤이 사라지고 긴 JSON line이 panel 폭 안에서 wrap됨을 확인했다.

### 2026-05-18 Analysis 실행 상세 blocking 완화 및 duration 표시

- 원인:
  - Analysis 실행 상세가 큰 prompt/provider output을 SwiftUI `Text`와 `textSelection`으로 렌더링해 layout과 선택 가능 text 계산이 main thread를 점유할 수 있었다.
  - 이전 preview 방식은 main thread 부담을 일부 줄였지만, 사용자가 실제 prompt/output 전체를 확인하려는 목적에는 맞지 않았다.
- 수정 내용:
  - prompt/provider output panel을 AppKit `NSTextView` 기반 `NSViewRepresentable`로 교체해 전체 원문을 표시하면서 scroll/selection 렌더링 비용을 낮췄다.
  - `전체 N자 중 일부 표시` 문구와 head/tail preview truncation을 제거하고, panel header에는 전체 글자수만 표시한다.
  - `AnalysisAttemptLog`에 `durationMilliseconds`를 추가했다.
  - analysis attempt 완료 시 `startedAt`에서 `completedAt`까지의 ms를 저장하고, 저장값이 없는 기존 attempt도 `startedAt`/`completedAt`으로 duration을 계산해 실행 로그 목록/상세 metric/markdown export에 표시한다.
- 검증:
  - `swift test`: 통과. 58개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - app relaunch: 통과. 새 process `pid 74970`를 확인했다.
  - Computer Use validation: 통과. Analysis 실행 상세를 열어 prompt/provider output 전체 panel과 duration metric이 표시되고, 상세 화면 내 스크롤이 동작함을 확인했다.

### 2026-05-18 Codex minimal exec profile 적용 및 app-server loading 최소화 조사

- 수정 내용:
  - `CodexExecProvider`의 `codex exec` 호출에 `--ignore-user-config`, `--ignore-rules`를 추가했다.
  - Codex provider one-shot 호출에서 `hooks`, `plugins`, `memories`, `apps`, `browser_use`, `computer_use`, `multi_agent`, `tool_search`를 `--disable`로 끄도록 했다.
  - 기존 `--skip-git-repo-check`, `--ephemeral`, `--sandbox read-only`, `--output-schema` 경로는 유지했다.
  - `LLMProviderConfigurationTests`에 minimal profile 인자 검증을 추가했다.
- 조사:
  - `codex exec --ignore-user-config --ignore-rules --disable hooks --disable plugins --disable memories --disable apps --disable browser_use --disable computer_use --disable multi_agent --disable tool_search --skip-git-repo-check --sandbox read-only --model gpt-5.4-mini --output-schema Sources/MeetingRescue/Resources/analysis-output.schema.json ...`: 통과. schema-valid JSON을 반환했고 `real 4.37s`, `tokens used 7,037`이었다.
  - `codex app-server --help`: `--ignore-user-config` 옵션이 없고, `-c/--config`, `--enable`, `--disable`만 확인됐다.
  - `codex app-server --listen stdio:// --disable hooks ...`는 hook notification은 줄였지만, 기존 user config의 MCP server startup notification은 남았다.
  - `-c 'mcp_servers={}'`는 기존 `[mcp_servers.*]` 설정을 clear하지 못하고 merge되어 MCP startup을 막지 못했다.
  - 임시 전용 `CODEX_HOME`에 `auth.json`만 공유하고 minimal config로 hooks/plugins/memories/apps/browser_use/computer_use/multi_agent/tool_search를 끄자 app-server startup에서 MCP notification이 사라졌다.
  - 전용 minimal `CODEX_HOME` app-server의 tiny schema turn은 `inputTokens=6,196`, `totalTokens=6,214`, `durationMs=1296`이었다.
  - 조사 중 인증 파일 내용은 출력하지 않았고, 경로와 설정 key만 확인했다.
- 판단:
  - 단기 기본 경로는 minimal `codex exec` profile 적용이 안전하다.
  - app-server provider를 구현하려면 `--disable`만으로는 부족하고, 앱 전용 minimal Codex home을 만들어 config/MCP/hook loading을 격리하는 방식이 필요하다.
  - app-server prototype은 인증 공유/로그인 UX, crash recovery, turn cancellation, meeting별 context isolation까지 함께 설계해야 한다.
- 검증:
  - `swift test`: 통과. 56개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - app relaunch: 통과. 기존 process `pid 94665`를 종료하고 새 process `pid 39061`를 확인했다.

### 2026-05-18 Codex app-server protocol 및 persistent API provider 조사

- 조사:
  - `codex app-server generate-json-schema --experimental --out /tmp/codex-app-server-schema`: 통과. app-server JSON-RPC schema bundle을 생성했다.
  - generated schema 기준 app-server는 `initialize`, `thread/start`, `turn/start`, `turn/interrupt` method를 제공한다.
  - `TurnStartParams`에는 `outputSchema` 필드가 있어 turn 단위 structured output을 요청할 수 있다.
  - `codex app-server --listen stdio:// ...`를 stdio session으로 띄우고 `initialize` request를 전송해 `InitializeResponse`를 받았다.
  - 이어 `thread/start`로 ephemeral thread를 만들고, `turn/start`에 간단한 JSON schema를 넣어 `{"summary":"hello","items":[]}` 형태의 schema-valid `agentMessage`를 받았다.
  - notification stream에서 `item/agentMessage/delta`, `item/completed`, `thread/tokenUsage/updated`, `turn/completed`를 확인했다.
  - `turn/start`에 잘못된 sandbox enum(`read-only`)을 넣으면 JSON-RPC `Invalid request`가 반환됐고, protocol enum은 `readOnly`를 요구했다.
- 판단:
  - `app-server`는 long-lived process + turn-level output schema + streaming output + token usage를 지원하므로 기술적으로 Meeting Rescue provider prototype 후보가 될 수 있다.
  - 다만 `experimental` CLI surface이고, Codex 앱 전체 프로토콜이어서 hook/MCP/config startup이 개입한다. tiny schema turn도 `inputTokens=27,866`으로 커서 minimal config isolation 없이는 live analysis latency 개선 효과가 제한적일 수 있다.
  - `exec-server`는 standalone executor surface지만 현재 help만으로는 analysis turn/output schema protocol을 바로 확인하기 어려웠고, `app-server` 쪽이 우선 spike 대상으로 더 구체적이다.
  - 장기 안정 경로는 CLI protocol 의존보다 OpenAI Responses API 같은 persistent HTTP/API provider를 `LLMProvider` adapter로 붙이는 방향이다.
- 문서 업데이트:
  - `tasks.md`에서 `Codex server protocol spike`를 조사 완료로 갱신했다.
  - `Codex app-server provider prototype`, `Persistent HTTP/API provider` backlog를 추가했다.

### 2026-05-18 Codex session/process reuse 조사

- 조사:
  - `Sources/MeetingRescueCore/LLMProvider.swift` 기준 현재 `CodexExecProvider`는 매 analysis마다 `ProcessRunner.run`으로 `/usr/bin/env codex exec ... -`를 새로 실행한다.
  - `codex exec resume --help`: `resume`은 저장된 session id를 재개할 수 있지만 `--output-schema` 옵션이 없음을 확인했다.
  - `codex exec-server --help`, `codex app-server --help`, `codex remote-control --help`: server 계열은 현재 CLI에서 `experimental`로 표시됨을 확인했다.
  - tiny prompt 실험에서 일반 `codex exec --json`은 session id를 만들고 context를 저장했지만 `real 12.51s`, `input_tokens=23,946`이었다.
  - 같은 session을 `codex exec resume <session_id>`로 재개하면 marker는 기억했지만 새 process 초기화가 반복됐고, 이전 대화가 붙어 `real 16.98s`, `input_tokens=48,070`으로 증가했다.
  - `--ignore-user-config --ignore-rules`만 적용하면 tiny prompt가 `real 5.95s`, `input_tokens=13,314`로 줄었다.
  - `--ignore-user-config --ignore-rules`와 불필요한 feature disable을 함께 적용하면 tiny prompt가 `real 3.71s`, `input_tokens=9,086`으로 줄었다.
  - 같은 minimal profile에 `--output-schema Sources/MeetingRescue/Resources/analysis-output.schema.json`을 붙인 schema-valid 분석 JSON 실험도 `real 4.43s`, `tokens used 7,123`으로 성공했다.
- 판단:
  - `codex exec resume`은 context 유지 기능이지 process reuse가 아니며, Meeting Rescue의 schema-bound live analysis에는 latency/비용 개선책으로 부적합하다.
  - 단기 개선은 session reuse보다 Codex 호출을 minimal exec profile로 격리하는 쪽이 더 현실적이다.
  - 장기적으로는 `exec-server`/`app-server` protocol spike 또는 HTTP/persistent client provider가 필요하다.
- 문서 업데이트:
  - `tasks.md`의 `LLM provider process/session reuse 검토`를 조사 완료로 갱신했다.
  - `Codex minimal exec profile 적용`, `Codex server protocol spike` backlog를 추가했다.

### 2026-05-18 L3 analysis timeout 조사 및 상세 화면 blocking 완화

- 조사:
  - 대상 회의는 `/Users/ethan/Documents/Recordings/20260515_173438_Zigbang(2F)_Meeting Room L3.txt`이고, 저장 상태는 `Sessions/c6b8c1851d4b8cc2-analysis.json`이다.
  - 최근 자동 분석은 16회 성공 후 `01:45:18-01:47:18`, `01:47:26-01:49:27` 두 번 120초 timeout으로 실패했다.
  - 실패 직전 성공 run은 `inputTokens=3272`, `outputTokens=1561`, `promptLen=10470`, 실행 시간 약 104초였다.
  - 실패 run은 각각 `inputTokens=3713/promptLen=11880`, `inputTokens=4212/promptLen=13476`으로, 거대 input보다는 누적 snapshot과 schema-valid JSON 전체 출력을 `codex exec` one-shot process로 생성하는 시간이 병목에 가까웠다.
  - ChatGPT 앱은 persistent/streaming 대화 UI이고, Meeting Rescue는 매 tick마다 `codex exec --ephemeral --sandbox read-only --output-schema ...`를 새 process로 실행한 뒤 완성 JSON을 기다리므로 동일 prompt라도 latency 특성이 다르다.
- 수정 내용:
  - live analysis prompt의 transcript cap을 `initial 8000자`, `new chunk 6000자`, `recent context 1200자`로 줄였다.
  - previous snapshot compact 범위를 topic 5개, decision/action 후보 각 8개, note 5개로 줄였다.
  - prompt 지침에 `currentIssue.summary` 3-5문장, timeline/후보 8개 이하, 오래된 항목 반복 설명 축소를 명시했다.
  - `Analysis 실행 상세` sheet가 prompt/provider output 전체를 한 번에 `Text` layout 하지 않고, 8000자 앞/뒤 preview와 생략 안내를 렌더링하도록 바꿨다.
- 검증:
  - `swift test`: 통과. 56개 test / 18개 suite가 통과했다.
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - app relaunch: 통과. 기존 app process를 종료하고 새 process `pid 94665`를 확인했다.
  - Computer Use validation: 통과. L3 meeting의 failed attempt 상세를 열었을 때 prompt가 `전체 13,476자 중 8,055자 표시` preview로 렌더링되고, 중간 생략 안내와 닫기 버튼이 표시됨을 확인했다.

### 2026-05-18 Prompt participants/context token 최적화 및 닫기 버튼 보강

- 원인:
  - 다수 참석 회의에서 transcript header의 전체 참석자 목록과 입장 system line이 `meetingMetadata.participants`, `transcriptContext.recentTranscriptContext`에 그대로 들어가 token을 많이 사용했다.
  - 실제 발화하지 않은 참석자와 `그룹에 입장했습니다` line은 meeting intelligence 품질에는 거의 기여하지 않는다.
  - 이전 커밋의 상세 sheet 닫기 버튼은 실행 중인 앱이 아직 이전 build라 보이지 않았고, 위치도 상단에만 있어 눈에 덜 띌 수 있었다.
- 수정 내용:
  - LLM prompt에 넣는 transcript context는 timestamped speaker 발화 line만 남기고 header, separator, `[SYSTEM]` speaker line을 제거한다.
  - prompt용 `meetingMetadata.participants`는 prompt context 안의 실제 발화자와 매칭되는 참석자만 유지한다.
  - matching된 참석자가 없으면 speaker name 목록을 participants로 사용해 전체 참석자 fallback을 피한다.
  - `Analysis 실행 상세` sheet 하단 우측에도 bordered prominent `닫기` 버튼을 추가했다.
  - README의 analysis 실행 흐름에 prompt metadata/context 최적화 정책을 기록했다.
- 검증:
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `swift test`: 통과. prompt가 실제 발화자만 participants로 남기고 system 입장 line/header를 제거하는 test를 포함해 56개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - app relaunch: 통과. 기존 app process를 종료하고 새 process `pid 74712`를 확인했다.
  - Computer Use validation: 통과. Analysis 실행 로그 row를 열었을 때 상세 sheet 상단 우측과 하단 우측에 `닫기` 버튼이 표시됨을 확인했다.

### 2026-05-18 Analysis attempt 상세 닫기 버튼 추가

- 수정 내용:
  - `Analysis 실행 상세` sheet 우측 상단에 `닫기` 버튼을 추가했다.
  - 버튼은 `xmark` icon과 label을 함께 표시하고, `Esc`/cancel shortcut으로도 닫을 수 있게 했다.
- 검증:
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `swift test`: 통과. 55개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - 실행 중인 앱은 재시작하지 않았다. 변경 사항은 다음 앱 재실행 또는 새 앱 번들 실행 시 반영된다.

### 2026-05-18 Main thread blocking 완화 및 analysis attempt 상세 화면

- 원인:
  - `AppViewModel`이 `@MainActor`인 상태에서 1초 folder scan 경로가 meeting history index를 재구성했고, 각 history item 생성 중 analysis/session JSON과 transcript preview 파일 읽기가 메인 액터에서 실행될 수 있었다.
  - live transcript append와 Test Run replay도 새 내용이 조금 들어올 때마다 전체 raw transcript를 다시 line split/join하고, metadata/end marker 확인을 위해 전체 transcript parse를 반복했다.
  - Analysis 실행 로그는 reason/status/token/message만 보여줘 실제 provider prompt와 raw output을 UI에서 확인할 수 없었다.
- 수정 내용:
  - `MeetingHistoryBuilder`를 추가해 meeting history index 생성, analysis/session load, transcript preview read를 utility priority detached task에서 수행하도록 분리했다.
  - folder scan이 이미 history refresh 중이면 중복 refresh를 시작하지 않고, non-force refresh는 10초 throttle을 먼저 적용해 불필요한 전체 index 재구성을 줄였다.
  - raw transcript view 갱신은 전체 split/join 대신 append된 text만 line buffer에 반영하고 `rawTranscriptRevision`으로 scroll update를 트리거한다.
  - append/replay 중 metadata parse는 필요한 초기 구간에만 수행하고, end marker 확인은 최근 tail 구간을 사용하도록 줄였다.
  - `AnalysisAttemptLog`에 `prompt`와 `providerOutput`을 추가하고, provider 성공 output을 scheduler result를 통해 attempt log에 저장한다.
  - Analysis 실행 로그 row를 클릭하면 prompt와 provider raw JSON output을 나란히 볼 수 있는 상세 sheet를 추가했다.
  - README의 diagnostics 설명에 attempt 상세 화면을 추가했다.
- 검증:
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `swift test`: 통과. raw provider output 전파 확인을 포함해 55개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - 현재 사용자가 실행 중인 앱에서 미팅 중이므로 app relaunch와 `dist/Meeting Rescue.app` 교체 검증은 수행하지 않았다. 변경 사항은 다음 앱 실행 또는 새 앱 번들 실행 시 반영된다.

### 2026-05-15 Manual/final analysis chunk continuation

- 원인:
  - 최근 실패 대상은 `/Users/ethan/Documents/Recordings/20260515_173438_Zigbang(2F)_Meeting Room L3.txt`였다.
  - 저장된 attempt log에서 `manual` run이 `09:26:58-09:29:58`, `09:31:48-09:34:48`에 각각 180초 timeout으로 실패했다.
  - 두 run 모두 input token estimate가 `6,666`으로 동일했고 `analyzedTranscriptCharacterCount`가 `0`이라, 매번 전체 prompt를 처음부터 one-shot으로 다시 보냈다.
  - 기존 bounded chunk 정책은 `automatic` reason에만 적용되어 `manual`/`final` 분석에는 효과가 없었다.
- 판단:
  - timeout을 300초로 늘리면 일부 케이스는 통과할 수 있지만, schema 출력 생성 시간이 길어지는 회의에서는 같은 문제가 반복된다.
  - 실패 단위를 줄이고 성공한 구간의 cursor를 저장하려면 완료 회의 전체 분석도 chunk continuation으로 처리하는 편이 더 안정적이다.
- 수정 내용:
  - `AnalysisTranscriptWindow`의 bounded chunk 적용 대상을 `automatic`뿐 아니라 `manual*`/`final*` reason으로 확장했다.
  - `manual`/`final` chunk가 성공했지만 전체 transcript가 아직 남아 있으면 `manual-continue` 또는 `final-continue` attempt를 예약해 다음 chunk를 자동으로 이어서 분석한다.
  - 성공한 chunk의 `targetTranscriptCharacterCount`를 `analyzedTranscriptCharacterCount`로 저장해 timeout/재시작 시 처음부터 다시 보내지 않게 했다.
  - `manual-continue`/`final-continue`도 one-shot 계열로 보고 최소 180초 timeout을 적용한다.
  - README의 analysis 실행 흐름과 `tasks.md` Backlog 상태를 갱신했다.
- 검증:
  - `swift test`: 통과. 55개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. 기존 app process를 종료하고 새 process `pid 95717`를 확인했다.
  - Computer Use validation: 통과. 새 앱이 `Zigbang(2F)_Meeting Room L3` meeting과 기존 diagnostics를 정상 로드함을 확인했다.

### 2026-05-15 Catch-up newline cursor 및 Test Run UX 정리

- 원인:
  - catch-up window를 newline 직전에서 자르면 다음 chunk가 같은 newline으로 시작해 prompt 앞쪽에 불필요한 개행이 남을 수 있었다.
  - `Test Run`은 이제 좌측 회의록 list에서 파일을 고를 수 있는 흐름이 생겼으므로 상단 header의 주요 action으로 두기보다 `Meetings` 영역에 붙이는 편이 자연스럽다.
- 수정 내용:
  - catch-up window가 newline boundary를 찾으면 newline 문자까지 포함해 cursor를 전진하도록 변경했다.
  - `AnalysisTranscriptWindowTests`에서 chunk가 newline으로 끝나는지 검증한다.
  - 상단 header의 `Test Run` 버튼을 제거하고 좌측 `Meetings` 영역의 `Live Now` 아래에 보조 `Test Run` control을 추가했다.
  - 각 history row에 play 버튼을 추가해 해당 회의록 파일을 바로 Test Run으로 실행할 수 있게 했다.
  - README의 Test Run 설명과 검증 경로를 좌측 진입점 기준으로 갱신했다.
  - `tasks.md` Backlog에 Test Run UX 정리 항목과 완료 상태를 기록했다.
- 검증:
  - `swift test`: 통과. 54개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. 기존 app process와 Codex provider process를 정리한 뒤 새 process `pid 79698`를 확인했다.
  - Computer Use validation: 통과. 상단 header에는 `Test Run`이 없고, 좌측 `Meetings` 영역의 `Live Now` 아래에 `Test Run` control이 표시되며, history row별 play 버튼이 별도 control로 노출됨을 확인했다.

### 2026-05-15 Restart catch-up chunking 구현

- 원인:
  - 앱 재시작 또는 timeout 반복 이후 `analyzedTranscriptCharacterCount` 이후 미분석 transcript backlog가 커지면 automatic analysis가 한 번에 큰 chunk를 보내며 timeout이 반복됐다.
  - 실패 시 cursor가 전진하지 않기 때문에 다음 retry는 같은 시작점에서 더 커진 현재 transcript까지 다시 포함했고, input token이 4,762 -> 6,877처럼 계속 증가했다.
- 수정 내용:
  - `AnalysisTranscriptWindow`를 추가해 automatic analysis 요청의 raw transcript를 bounded catch-up window로 제한한다.
  - automatic analysis는 `analyzedTranscriptCharacterCount` 이후 최대 5,000자 단위로 다음 chunk만 포함한다.
  - window 끝은 가능하면 newline 경계에 맞춰 잘라 transcript line 중간 절단을 줄인다.
  - 성공 시 기존 로직처럼 request raw transcript 길이만큼 cursor가 전진하므로, 이제 전체 raw 끝이 아니라 이번 catch-up window 끝까지만 `analyzedTranscriptCharacterCount`가 이동한다.
  - manual/final analysis는 전체 transcript를 대상으로 유지한다.
  - analysis attempt message에 `catch-up start-end/total자` 범위를 표시해 실행 로그에서 실제 window를 확인할 수 있게 했다.
  - `tasks.md` Backlog에 restart catch-up chunking 항목과 완료 상태를 기록했다.
- 검증:
  - `swift test`: 통과. 54개 test / 18개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. 기존 app process와 Codex provider process를 정리한 뒤 새 process `pid 34356`를 확인했다.
  - saved-state validation: 통과. 재시작 전 남아 있던 `automatic running` attempt가 `skipped`로 닫히고 `앱 재시작 또는 meeting reload로 이전 running attempt를 중단 처리했습니다.` message가 기록됨을 확인했다.
  - live automatic validation: 현재 transcript에 `[SYSTEM] 대화 기록 종료`가 있어 `isCompleted=true`로 복원되므로 새 automatic catch-up run은 실행되지 않는 것이 정상임을 확인했다. catch-up window 동작은 `AnalysisTranscriptWindowTests`에서 검증했다.

### 2026-05-15 Live topic breakdown 개선

- 원인:
  - live meeting에서 transcript와 analysis는 계속 갱신됐지만, LLM이 `topicTimeline`을 `[00:00]` 단일 항목으로 유지하면서 summary만 길게 확장하는 케이스가 있었다.
  - prompt가 기존 compact state의 timeline 유지를 강하게 유도했지만, 새 agenda나 하위 논점 전환 시 topic을 append하라는 기준은 명확하지 않았다.
  - 요약 탭의 `최근 흐름`은 `topicTimeline.prefix(4)`를 보여줘, timeline이 정상적으로 여러 항목이 되어도 최신 항목이 아니라 앞쪽 항목을 보여줄 수 있었다.
- 수정 내용:
  - LLM prompt에 topic breakdown 기준을 추가했다.
  - 3-6분 이상 이어지는 장문 발제라도 하위 agenda, 논점, 대상, 실행 방향이 바뀌면 별도 topic item으로 나누도록 명시했다.
  - incremental refresh에서 기존 마지막 topic을 무한 확장하지 말고, 새 논점이나 다음 agenda가 시작되면 이전 topic의 `endTimestamp`를 닫고 새 topic을 append하도록 명시했다.
  - `topicTimeline`은 시간순으로 정렬하고, 각 item의 `startTimestamp`/`endTimestamp`를 근거 발화 timestamp로 채우도록 prompt에 기록했다.
  - 요약 탭의 `최근 흐름`은 `topicTimeline.suffix(4)`를 사용해 최신 흐름 중심으로 표시한다.
  - prompt에 breakdown 기준이 포함되는 regression test를 추가했다.
  - `tasks.md` Backlog에 live topic breakdown 개선 항목과 완료 상태를 기록했다.
- 검증:
  - `swift build`: 통과. `MeetingRescue` debug build가 성공했다.
  - `swift test`: 통과. 51개 test / 17개 suite가 통과했다.
  - `git diff --check`: 통과.
  - 현재 live meeting 중인 실행 앱을 방해하지 않기 위해 앱 종료, 재실행, app bundle rebuild, Computer Use manual relaunch validation은 수행하지 않았다.

### 2026-05-15 Search Meetings 정렬 옵션 추가

- 원인:
  - 검색 결과가 관련도 점수 우선으로만 정렬되어 `마케팅`처럼 오래된 회의의 current issue match가 최신 회의보다 위에 노출될 수 있었다.
  - 실제 사용 흐름은 최근 회의에서 해당 키워드를 다시 찾는 경우가 많으므로 기본 정렬은 최신순이 더 자연스럽다.
- 수정 내용:
  - `MeetingHistorySortOrder`를 추가하고 기본값을 `최신순`으로 설정했다.
  - Search Meetings header에 `최신순` / `관련도순` 정렬 메뉴를 추가했다.
  - `최신순`은 meeting modification date 역순을 우선하고, 같은 시각이면 match score와 title로 tie-break한다.
  - `관련도순`은 기존처럼 match score를 우선하고, 동점이면 최신 회의를 우선한다.
  - README의 검색 정렬 설명을 기본 최신순과 옵션 관련도순 기준으로 갱신했다.
- 검증:
  - `swift build`: 통과. `MeetingRescue` executable debug build가 성공했다.
  - `swift test`: 통과. 50개 test / 17개 suite가 통과했다.
  - `git diff --check`: 통과.
  - manual app relaunch validation은 현재 사용자가 미팅 중인 실행 앱을 종료하지 않기 위해 수행하지 않았다. 변경 사항은 다음 앱 실행 또는 새 빌드 앱 실행 시 UI에 반영된다.

### 2026-05-15 Current issue 검색 결과 anchor fallback 수정

- 원인:
  - `마케팅`처럼 current issue 요약이 가장 높은 점수로 매칭되면 display match가 `현재 이슈`로 잡혔지만, current issue section에는 timestamp가 없어 클릭 이동에 사용할 anchor가 없었다.
  - 같은 회의 안의 raw transcript에는 timestamp match가 있어도 display match만 click anchor로 쓰던 탓에 scroll/highlight가 누락됐다.
- 수정 내용:
  - display용 best match와 navigation용 timestamp match를 분리했다.
  - `MeetingHistorySearch.timestampedMatch`를 추가해 같은 query에 대해 timestamp가 있는 section 중 best match를 찾는다.
  - `MeetingHistorySearchResult`가 `anchorTimestamp`를 별도로 들고, display match에 timestamp가 없어도 fallback anchor가 있으면 클릭 시 raw transcript로 이동한다.
  - search result hint도 `anchorTimestamp` 기준으로 표시한다.
  - current issue가 best match이고 raw transcript가 anchor인 regression test를 추가했다.
- 검증:
  - `swift test`: 통과. 50개 test / 17개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. 기존 app process를 정리한 뒤 `open -n dist/Meeting Rescue.app`로 새 process `pid 59274`를 확인했다.
  - Computer Use validation: 통과. `마케팅` 검색 첫 결과 `현재 이슈: 주간 회의에서...`에 `클릭하면 원문 위치로 이동` hint가 표시되고, 클릭 시 `Zigbang(2F)_Meeting Room L5` history transcript가 열리며 raw transcript가 `[23:12]` 브랜드 마케팅 발화 근처로 이동/highlight됨을 확인했다.

### 2026-05-15 Transcript anchor 재클릭 이동 누락 수정

- 원인:
  - 검색 결과를 클릭해 같은 raw transcript line으로 다시 이동하는 경우 `focusedTranscriptLineID` 값이 이전과 동일해 SwiftUI `onChange`가 다시 실행되지 않을 수 있었다.
  - 특히 사용자가 anchor 이동 후 raw transcript를 다른 위치로 스크롤한 뒤 같은 검색 결과를 다시 누르면, line id가 변하지 않아 재이동/highlight 요청이 무시되는 케이스가 생겼다.
- 수정 내용:
  - `focusedTranscriptLineID` 단일 값 대신 `TranscriptFocusRequest(lineID, token)`을 발행하도록 변경했다.
  - 같은 line으로 이동하더라도 클릭마다 token이 증가하므로 SwiftUI `onChange`가 매번 새 focus request로 인식한다.
  - transcript reset 지점들은 새 focus request를 `nil`로 초기화하도록 정리했다.
- 검증:
  - `swift test`: 통과. 49개 test / 17개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. 기존 app process를 정리한 뒤 `open -n dist/Meeting Rescue.app`로 새 process `pid 43974`를 확인했다.
  - Computer Use repeat anchor validation: 통과. `마케팅팀` 검색 결과 클릭으로 `[09:04]` 근처로 이동한 뒤 raw transcript를 위로 스크롤하고 같은 검색 결과를 다시 클릭했을 때 `[09:04]` 근처로 재이동하고 highlight가 다시 표시됨을 확인했다.

### 2026-05-15 Search 입력 debounce 및 transcript anchor scroll 최적화

- 범위:
  - 검색 입력마다 meeting history 전체 검색이 즉시 반복되는 문제와, anchor 이동 후 raw transcript panel scroll이 버벅이는 문제를 완화했다.
- 수정 내용:
  - `historySearchText` 입력값과 실제 검색 query를 분리하고, 300ms debounce 이후에만 history search 결과를 갱신하도록 했다.
  - 검색 결과를 computed property 대신 `filteredMeetingHistorySearchResults` cache로 보관해 count/list/row 렌더 중 같은 검색을 반복하지 않게 했다.
  - history row는 cache에 저장된 `MeetingHistorySearchMatch`를 재사용해 row 렌더마다 match를 다시 계산하지 않는다.
  - raw transcript line을 `TranscriptLineRow` `Equatable` view로 분리하고, line-level background는 highlight line에만 적용하도록 줄였다.
  - anchor jump의 `withAnimation`을 제거하고, highlight는 2초 뒤 자동 해제해 이후 수동 스크롤 중 compositing 부담을 줄였다.
  - README에 검색 입력 debounce 동작을 기록했다.
- 검증:
  - `swift test`: 통과. 49개 test / 17개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. 기존 app process를 정리한 뒤 `open -n dist/Meeting Rescue.app`로 새 process `pid 14971`를 확인했다.
  - Computer Use search validation: 통과. `마케팅팀` 입력 후 debounce된 검색 결과가 `Search Meetings 2/271`로 표시되고, `[09:04] 원문` snippet이 유지됨을 확인했다.
  - Computer Use anchor/scroll validation: 통과. 검색 결과 클릭 시 raw transcript가 09분대 anchor로 이동하고, 이후 raw transcript panel을 수동 scroll해도 정상적으로 viewport가 이동함을 확인했다.
  - Computer Use reset validation: 통과. 검색어 clear 후 `Search Meetings 271/271`로 복구되고 `Live` 버튼으로 Live Watch에 복귀됨을 확인했다.

### 2026-05-15 Search result timestamp jump 구현

- 범위:
  - Backlog `Search quality 후속`의 `검색 결과 snippet 클릭 시 해당 transcript timestamp 또는 topic 구간으로 이동한다` 항목을 구현했다.
- 수정 내용:
  - raw transcript search index를 전체 preview 1개가 아니라 timestamp를 가진 line 단위 section으로 나눠 검색 match가 원문 timestamp를 보존하도록 했다.
  - `TranscriptTimestampLocator`를 core에 추가해 `[MM:SS]`, `[HH:MM:SS]`, ISO timestamp를 raw transcript line index로 연결하게 했다.
  - sidebar 검색 결과 row가 timestamp match를 표시하고, 클릭 시 history transcript를 연 뒤 raw transcript pane의 해당 line으로 스크롤/강조하도록 연결했다.
  - README 수동 검증 경로와 알려진 제한, `tasks.md` Backlog를 갱신했다.
- 검증:
  - `swift test`: 통과. Transcript timestamp locator test를 포함해 49개 test / 17개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. 기존 app process를 정리한 뒤 `open -n dist/Meeting Rescue.app`로 새 process `pid 94640`를 확인했다.
  - Computer Use search validation: 통과. `마케팅팀` 검색 시 `Search Meetings 2/271`로 필터링되고, 첫 결과에 `[09:04] 원문: ... 마케팅팀...` snippet과 `클릭하면 원문 위치로 이동` hint가 표시됨을 확인했다.
  - Computer Use timestamp jump validation: 통과. 해당 결과 클릭 후 `History` mode로 전환되고 raw transcript pane이 `showing 62-121 of 122 items` 상태로 이동해 `[09:04] Justin Choi: ... 마케팅팀...` line이 강조됨을 확인했다.
  - Computer Use reset validation: 통과. 검색어를 clear하면 `Search Meetings 271/271`로 복구되고 `Live` 버튼으로 Live Watch에 복귀됨을 확인했다.

### 2026-05-15 Search Meetings facet filter 구현

- 범위:
  - Backlog `Search quality 후속`의 날짜 범위, 참석자, room, 완료 여부, decision/action 존재 여부 facet filter를 구현했다.
- 수정 내용:
  - `MeetingHistoryFacetSelection`과 관련 facet enum/document를 core에 추가해 history filtering 조건을 testable하게 분리했다.
  - Search Meetings panel에 기간, 상태, 후보, 참석자, room menu filter를 추가했다.
  - facet filter와 keyword search가 함께 적용되도록 `filteredMeetingHistorySearchResults` 흐름을 변경했다.
  - 활성 filter가 있을 때 reset 버튼을 표시해 전체 목록으로 빠르게 되돌릴 수 있게 했다.
  - README 수동 검증 경로와 알려진 제한, `tasks.md` Backlog를 갱신했다.
- 검증:
  - `swift test`: 통과. Meeting history filters test를 포함해 46개 test / 16개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. `open -n dist/Meeting Rescue.app`로 새 process `pid 46995`를 확인했다.
  - Computer Use `get_app_state`: 통과. Search Meetings panel에 `기간`, `상태`, `후보`, `참석자`, `room` menu filter가 표시됨을 확인했다.
  - Computer Use candidate facet validation: 통과. `후보 > 결정 있음` 선택 시 count가 `272/272`에서 `7/272`로 줄고 reset 버튼이 표시됨을 확인했다.
  - Computer Use reset validation: 통과. reset 버튼 클릭 후 count가 `272/272`로 복구됨을 확인했다.

### 2026-05-15 Search quality 1차 개선 및 hipocampus Backlog 제거

- 원인:
  - `hipocampus digest watcher` 대체/통합은 Meeting Rescue 내부 검색 품질과 별도 의사결정이 필요한 작업이므로 현재 Backlog에서 제거했다.
  - 기존 meeting history 검색은 모든 검색 대상이 같은 문자열로 합쳐져 있어 제목/참석자/확정 decision/action 같은 중요한 field가 raw transcript와 같은 우선순위로 처리됐고, 결과 행에서 왜 매칭됐는지 알기 어려웠다.
- 수정 내용:
  - `MeetingHistorySearch` ranker를 core에 추가해 field별 local index, normalized text cache, AND token matching, substring fallback, score 기반 정렬을 제공한다.
  - history item index를 제목, 파일명, room, 일시, 참석자, current issue, topic, confirmed/candidate decision/action, note, raw transcript preview field로 분리했다.
  - 제목/참석자/room/current issue/confirmed decision/action에는 높은 weight를 주고, raw transcript preview는 낮은 weight로 검색 보조에 사용한다.
  - 검색 결과 row에 match된 field와 snippet을 표시하도록 했다.
  - 검색 입력 반응성을 위해 index 생성 시 normalized text를 캐시하고 raw transcript preview는 bounded read로 제한했다.
  - README와 `tasks.md` Backlog를 갱신해 완료된 search quality 1차 항목은 제거하고, facet filter/timestamp jump/semantic ranking만 후속으로 남겼다.
- 검증:
  - `swift test`: 통과. Meeting history search test를 포함해 43개 test / 15개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. `open -n dist/Meeting Rescue.app`로 새 process `pid 30304`를 확인했다.
  - Computer Use `get_app_state`: 통과. `Search Meetings 272/272`와 새 placeholder `제목, 참석자, 결정, 액션, 원문 검색`을 확인했다.
  - Computer Use search validation: 통과. `Pinpoint` 입력 시 `Search Meetings 1/272`로 필터링되고 row에 `현재 이슈: ... Pinpoint ...` match snippet이 표시됨을 확인했다.
  - Computer Use reset validation: 통과. clear 버튼으로 검색어를 지우면 `Search Meetings 272/272`로 돌아감을 확인했다.

### 2026-05-15 candidate 상태 inline editing 허용

- 원인:
  - 후보 문구를 수정하려면 먼저 `take`해야 했고, 사용자는 `take`가 Markdown/export/LLM refresh에 어떤 의미를 갖는지 신경 써야 했다.
  - 사람이 후보 문구를 직접 다듬는 행위는 사실상 채택 의사에 가깝기 때문에, 편집 진입 자체는 candidate 상태에서도 허용하고 저장 시 자동 confirmed 처리하는 편이 자연스럽다.
- 수정 내용:
  - 후보 탭의 decision/action candidate row에서 candidate 상태에도 `편집` 버튼을 표시하도록 변경했다.
  - 기존 `editDecision`/`editActionItem` 저장 흐름은 그대로 사용해, 편집 저장 시 자동으로 confirmed 처리된다.
  - README의 기능 설명과 수동 검증 경로를 candidate edit 후 자동 confirmed 흐름에 맞게 갱신했다.
- 검증:
  - `swift test`: 통과. 40개 test / 14개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. `dist/Meeting Rescue.app`를 다시 실행했고 새 process `pid 13784`를 확인했다.
  - Computer Use `get_app_state`: 통과. 후보 탭에서 아직 confirmed가 아닌 decision/action candidate에도 `편집` 버튼이 표시됨을 확인했다.

### 2026-05-15 confirmed decision/action inline editing 구현

- 범위:
  - Backlog의 `confirmed decision/action item inline editing`을 쓸만한 버전까지 구현했다.
- 수정 내용:
  - `MeetingAnalysisState`에 decision/action candidate별 사용자 수정본을 저장하는 구조를 추가했다.
  - decision edit은 최종 문장을 저장하고, action edit은 담당자/할 일/기한을 분리 저장한다.
  - 수정본은 candidate id 기준으로 저장되며 LLM refresh snapshot에 다시 적용된다.
  - 원문 복원 기능을 추가해 사용자가 LLM 원본 후보로 되돌릴 수 있게 했다.
  - 후보 탭에서 confirmed item에 편집 버튼, 원문 복원 버튼, `수정됨` 표시를 제공한다.
  - Markdown export와 meeting history search index는 수정된 snapshot 값을 사용한다.
  - README의 기능 설명과 수동 검증 경로를 갱신했다.
  - 완료된 Backlog 항목을 `tasks.md`에서 제거했다.
- 검증:
  - `swift test`: 통과. inline edit persistence/refresh/restore, confirm 취소 시 원문 복원, Markdown export 반영 test를 포함해 40개 test / 14개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. `dist/Meeting Rescue.app`를 다시 실행했고 새 process `pid 4703`를 확인했다.
  - Computer Use `get_app_state`: 통과. 후보 탭에서 candidate confirm 후 confirmed row에 `편집` 버튼과 `confirm 취소` 버튼이 표시됨을 확인했다.
  - Computer Use edit form: 통과. `편집` 버튼 클릭 시 `결정 문장 편집` form, text entry, `저장`, `취소` 버튼이 표시됨을 확인했다.

### 2026-05-15 실행 로그 분리 및 검색 개선 Backlog 정리

- 원인:
  - `tasks.md`가 phase 정의, backlog, 과거 실행 로그를 모두 담으면서 길어지고 있어 source of truth로서 읽기 어려워졌다.
  - meeting history 검색은 현재 단순 text matching 중심이라, 회의가 많아질수록 원하는 회의/결정/액션을 빠르게 찾기 어렵다.
- 수정 내용:
  - 기존 `tasks.md`의 `## 실행 로그` 이하 모든 기록을 `execution-log.md`로 분리했다.
  - `tasks.md`의 운영 원칙을 `tasks.md`는 phase/backlog source of truth, `execution-log.md`는 실행 이력 source로 쓰는 구조에 맞게 갱신했다.
  - `tasks.md`의 `## 실행 로그` 섹션은 `execution-log.md` 링크만 남기도록 축약했다.
  - Backlog에 search quality 개선 후보를 추가했다.
- 검증:
  - `python3` split script: 통과. 기존 실행 로그를 `execution-log.md`로 이동하고 `tasks.md`에는 링크 섹션만 남김을 확인했다.
  - manual inspection `sed -n '1,230p' tasks.md`, `sed -n '1,35p' execution-log.md`: 통과. 문서 구조와 최신 로그 위치를 확인했다.
  - `git diff --check -- tasks.md execution-log.md`: 통과.
  - `rg -n "^## 실행 로그|execution-log.md|Search quality" tasks.md execution-log.md`: 통과. `tasks.md` 링크 섹션과 Backlog의 search quality 항목을 확인했다.

### 2026-05-15 Sidebar Live Now/Search Meetings 시각 분리

- 원인:
  - `Meetings` sidebar 상단에서 `Live Now` 복귀 버튼과 `Search meetings` 입력창이 같은 작은 컨트롤 묶음처럼 보여, 현재 live 상태 확인과 과거 회의 검색의 역할이 시각적으로 잘 분리되지 않았다.
  - history mode 사용 빈도상 `Search Meetings`가 더 중요한 진입점인데 기존 rounded text field만으로는 충분히 부각되지 않았다.
- 수정 내용:
  - `Live Now`를 별도 control block으로 분리하고 live 상태일 때 mint 배경과 accent border를 유지하도록 했다.
  - `Search Meetings`를 별도 search panel로 분리해 accent label, 검색 아이콘, 결과 카운트, clear 버튼을 제공했다.
  - search panel에는 별도 배경/테두리를 적용해 live control과 meeting list 사이에서 더 명확한 기능 영역으로 보이게 했다.
- 검증:
  - `swift test`: 통과. 37개 test / 14개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Format=app bundle with Mach-O thin (arm64)`, ad-hoc signature를 확인했다.
  - app relaunch: 통과. `dist/Meeting Rescue.app`를 다시 실행했고 새 process `pid 33209`를 확인했다.
  - Computer Use `get_app_state`: 통과. sidebar에서 `Live Now`와 `Search Meetings`가 별도 영역으로 표시되고, `Search Meetings 272/272` count 및 강조된 검색 field가 표시됨을 확인했다.

### 2026-05-15 Candidate confirm 취소 및 history row patch 개선

- 원인:
  - 결정/액션 후보를 confirm하면 `confirmedCandidateIDs`에 저장되지만, UI에서 다시 candidate 상태로 되돌리는 경로가 없었다.
  - 후보 상태 변경 후 현재 meeting 하나의 count/search/summary만 바뀌는데도 `refreshMeetingHistory(force: true)`가 전체 Recordings folder의 `.txt` 272개를 다시 읽고 모든 history row를 재구성했다.
  - 이 전체 rebuild가 SwiftUI sidebar와 accessibility tree까지 다시 만들면서 tick 반응이 느려졌다.
- 수정 내용:
  - `MeetingAnalysisState.setCandidateStatus(id:status:)`를 추가해 confirm/delete/candidate 복귀 규칙을 core state로 분리했다.
  - 결정/액션 후보 row에서 이미 confirmed 상태인 항목은 check 버튼 대신 `arrow.uturn.backward` 버튼을 보여주고, 누르면 `.candidate` 상태로 되돌리도록 했다.
  - 후보 상태 저장 후 전체 history refresh 대신 `patchMeetingHistoryItem(for:)`로 현재 `activeTranscriptURL`에 해당하는 history item 하나만 재계산해 교체하도록 변경했다.
  - README에 decision/action candidate를 confirm 취소할 수 있음을 반영했다.
- 검증:
  - `swift test`: 통과. candidate status revert test를 포함해 37개 test / 14개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.
  - app relaunch: 통과. `dist/Meeting Rescue.app`를 다시 실행했고 새 process `pid 24302`를 확인했다.
  - Computer Use confirm/undo: 통과. 결정 후보 첫 항목을 confirm하면 `confirm 취소` 버튼으로 바뀌고, 다시 누르면 candidate 상태로 돌아감을 확인했다.

### 2026-05-15 Analysis reason별 timeout 정책 수정

- 원인:
  - 수동 `분석` 버튼으로 과거/완료 회의를 one-shot 분석할 때도 live automatic analysis와 같은 provider timeout 설정을 사용했다.
  - 긴 회의 한방 분석은 prompt가 크고 처리 시간이 길어질 수 있는데, live transcription과 같은 짧은 timeout 정책을 적용하면 사용자가 명시적으로 요청한 분석이 불필요하게 timeout될 수 있었다.
- 수정 내용:
  - `AnalysisTimeoutPolicy`를 추가해 실행 reason별 effective timeout을 분리했다.
  - `manual` 및 `final*` analysis는 최소 180초 timeout을 사용한다. 사용자가 설정한 timeout이 180초보다 크면 설정값을 유지한다.
  - `automatic` live analysis와 retry/test run 계열은 설정값을 사용하되 최소 10초 timeout을 보장한다.
  - settings의 provider timeout 상한을 180초에서 300초로 늘렸다.
  - analysis attempt log의 running entry에 적용 timeout을 `timeout N초`로 기록한다.
  - README와 settings UI 설명에 reason별 timeout 정책을 반영했다.
- 검증:
  - `swift test`: 통과. timeout clamp 및 reason별 timeout policy test를 포함해 36개 test / 14개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.

### 2026-05-15 History Live Now badge 및 raw transcript 전체 표시 수정

- 원인:
  - History mode 진입 시 `liveActiveTranscriptURL`이 선택한 과거 회의와 다르면 즉시 `liveMeetingUpdated`를 켜고 있어, 이미 종료된 최신 회의록을 가리키는 `Live Now`에도 종 badge가 표시됐다.
  - Raw Transcript pane은 긴 transcript에서 마지막 220줄만 preview로 보여주고 `[이전 n줄 생략됨]` marker를 붙였기 때문에, 과거 회의록을 위로 스크롤해도 전체 원문 앞부분을 볼 수 없었다.
- 수정 내용:
  - History mode 진입 시점의 latest transcript 후보를 baseline으로 저장하고, 이후 latest 파일이 바뀌거나 같은 latest 파일의 modification time이 baseline 이후로 갱신될 때만 `Live Now` 종 badge를 표시하도록 변경했다.
  - `LiveTranscriptUpdateDetector`를 추가해 history live badge 조건을 core logic으로 분리했다.
  - Raw Transcript pane은 더 이상 220줄 suffix preview로 자르지 않고 전체 transcript line을 `LazyVStack`에 표시하도록 변경했다.
- 검증:
  - `swift test`: 통과. history live badge detector test를 포함해 34개 test / 14개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.
  - app relaunch: 통과. `dist/Meeting Rescue.app`를 다시 실행했고 새 process `pid 80391`을 확인했다.
  - Computer Use `get_app_state`: 통과. Live Watch 화면에서 앱이 정상 로드됨을 확인했다.
  - Computer Use history 선택: 통과. 과거 회의 선택 시 `Live Now`는 기존 latest transcript를 가리키지만 종 badge가 뜨지 않음을 확인했다.
  - Computer Use raw transcript scroll: 통과. 634줄 history transcript를 맨 위로 스크롤했을 때 `[이전 n줄 생략됨]` 없이 회의 header와 `[00:00]` 시작 줄이 표시됨을 확인했다.

### 2026-05-15 History sidebar decode/stutter 수정

- 원인:
  - 이전 `Live Now` 복귀 최적화에서 history metadata preview를 파일 앞 16KB만 읽도록 줄였는데, UTF-8 multi-byte character 중간에서 잘린 data에 대해 `.utf8` decode가 실패하면 `.unicode` fallback이 UTF-8 bytes를 UTF-16처럼 해석했다.
  - 그 결과 일부 meeting row에 `婩杢...` 형태의 긴 mojibake 문자열이 표시되고, SwiftUI layout/accessibility tree가 무거워져 history list와 `Live Now` 복귀가 다시 버벅일 수 있었다.
  - history row가 화면에는 line limit로 보이더라도 accessibility label에는 긴 summary가 포함되어 row tree가 불필요하게 커질 수 있었다.
- 수정 내용:
  - `TranscriptTextDecoder`를 추가해 UTF-16 BOM/likely UTF-16은 보존하되, 일반 transcript와 잘린 UTF-8 snippet은 UTF-8 replacement decode로 처리하도록 했다.
  - full read, appended read, metadata preview가 공통 decoder를 사용하도록 변경했다.
  - meeting history row의 summary display는 180자 preview로 제한하고, 검색용 index에는 기존 full summary/topic/decision/action/note text를 유지했다.
- 검증:
  - `swift test`: 통과. `TranscriptTextDecoder` test를 포함해 33개 test / 14개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.
  - app relaunch: 통과. `dist/Meeting Rescue.app`를 다시 실행했고 새 process `pid 73533`을 확인했다.
  - Computer Use `get_app_state`: 통과. 새 앱에서 history sidebar의 mojibake row가 사라졌고 `Live Watch` 화면이 정상 표시됨을 확인했다.
  - Computer Use history -> live 복귀: 통과. 과거 meeting row 선택 후 `Live Now`를 눌러 `Live Watch` mode와 최신 transcript로 정상 복귀함을 확인했다.

### 2026-05-15 Live Now 복귀 끊김 수정

- 원인:
  - `Live Now`/`Live` 복귀가 단순 모드 전환이 아니라 `startWatching()`을 다시 호출해 timer, security scope, history rebuild를 모두 재초기화했다.
  - history list metadata preview가 저장된 session이 없는 파일에 대해 transcript 전체를 읽고 parse해, meeting 파일이 많은 폴더에서 메인 스레드가 순간적으로 끊길 수 있었다.
- 수정 내용:
  - `returnToLiveWatch()`는 이미 선택된 folder가 있으면 watcher를 재시작하지 않고 `scanFolder()`와 `ensureFolderScanTimer()`만 호출하도록 변경했다.
  - security-scoped folder 접근을 Live 복귀 때 불필요하게 stop/start하지 않게 했다.
  - history metadata preview는 transcript 전체가 아니라 파일 앞 16KB만 읽어 header metadata를 추출하도록 줄였다.
- 검증:
  - `swift test`: 통과. 31개 test / 13개 suite가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.

### 2026-05-15 History mode 및 meeting search 구현

- Backlog의 source folder meeting list/history browser와 검색 가능한 meeting history를 구현했다.
- 수정 내용:
  - `TranscriptRunMode.history`를 추가해 `Live Watch`, `History`, `Test Run` 모드를 구분한다.
  - `liveActiveTranscriptURL`과 화면 열람 대상인 `activeTranscriptURL`을 분리했다.
  - 왼쪽 `Meetings` sidebar를 추가해 선택한 source folder의 `.txt` 회의록을 modification time 기준으로 표시한다.
  - `Live Now` row와 `Live` 버튼을 추가해 과거 회의 열람 중에도 최신 transcript 추적으로 돌아갈 수 있게 했다.
  - 과거 회의를 클릭하면 `History` 모드로 전환하고, 선택 파일의 raw transcript와 저장된 Meeting Intelligence를 로드한다.
  - `History` 모드에서는 automatic analysis와 end-marker final analysis를 실행하지 않는다. 사용자가 `분석`을 누른 경우에만 provider를 실행한다.
  - 폴더 scan timer는 `History` 모드에서도 계속 유지해 meeting list와 live update indicator를 갱신한다.
  - sidebar 검색은 파일명, room, 일시, 참석자, current issue summary, topic/decision/action/note 텍스트를 대상으로 한다.
  - meeting list는 analysis state 변경 후 강제 refresh되어 topic/decision/action count와 summary가 최신 상태로 보인다.
  - README에 history/search 사용법과 수동 검증 경로를 추가했다.
- 검증:
  - `swift test`: 통과. `LatestTranscriptSelector.textFiles` test를 포함해 31개 test / 13개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.
  - Computer Use `get_app_state`: 통과. 왼쪽 `Meetings` sidebar, `Live Now`, meeting rows, `History` mode, 저장된 Meeting Intelligence 로드가 정상 표시됨을 확인했다.
  - Computer Use search: 통과. 검색어 `Pinpoint` 입력 시 matching meeting 1개로 필터링되고, `Live` 버튼으로 `Live Watch` 모드 복귀가 동작함을 확인했다.

### 2026-05-15 incremental transcript chunk + compact state prompt 설계 구현

- 최근 timeout의 원인이 긴 transcript suffix를 매번 다시 보내는 구조에 있다고 보고, 새로 추가된 transcript chunk와 compact state 중심으로 analysis prompt를 재설계했다.
- 수정 내용:
  - `MeetingAnalysisState`에 `analyzedTranscriptCharacterCount`를 추가해 마지막 successful analysis가 처리한 raw transcript 문자 위치를 저장한다.
  - `AnalysisRequest`에 `lastAnalyzedTranscriptCharacterCount`를 추가했다.
  - 첫 성공 전에는 제한된 transcript tail을 `fullTranscript`로 보내고, 이후에는 마지막 성공 위치 이후의 `newTranscriptChunk`와 짧은 `recentTranscriptContext`만 prompt에 넣는다.
  - 실패/timeout 시에는 `analyzedTranscriptCharacterCount`를 갱신하지 않는다. 따라서 다음 retry는 마지막 성공 이후 누락된 chunk를 다시 포함한다.
  - successful analysis가 끝나면 현재 raw transcript 길이로 `analyzedTranscriptCharacterCount`를 갱신한다.
  - `previousAnalysisSnapshot`은 최근 topic, decision/action candidates, notes 중심으로 compact해서 보낸다.
  - prompt instruction에 compact state와 new transcript chunk의 역할을 명시했다.
  - README의 analysis 실행 흐름을 incremental chunk 방식으로 갱신했다.
- 기대 효과:
  - 긴 회의에서 매 refresh마다 동일한 transcript suffix를 반복 전송하는 비용과 latency를 줄인다.
  - timeout 이후 retry가 실패 구간을 건너뛰지 않고 마지막 successful analysis 이후 chunk를 다시 처리한다.
- 검증:
  - `swift test`: 통과. incremental prompt builder, compact previous snapshot, persisted analyzed transcript count test를 포함해 30개 test / 13개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.

### 2026-05-15 Meeting history/list 검색 방향 추가 및 timeout 로그 점검

- 사용자와 논의한 방향을 Backlog에 구체화했다.
- 추가한 방향:
  - source folder의 meeting list/history browser를 추가한다.
  - `Live`와 `History` 모드를 분리해 자동 최신 파일 추적과 과거 회의 열람이 서로 화면을 빼앗지 않게 한다.
  - `liveActiveTranscript`와 `viewingTranscript`를 분리해 자동 추적 대상과 사용자가 보는 대상을 다르게 모델링한다.
  - 과거 meeting에서는 automatic analysis를 돌리지 않고, 명시적 `Analyze`/`Rebuild Intelligence`에서만 실행한다.
  - 검색은 raw transcript보다 Meeting Intelligence 구조화 데이터 중심으로 시작하고, raw full-text와 semantic search는 후순위 확장으로 둔다.
- 최근 failure attempt log 점검:
  - Application Support 경로: `/Users/ethan/Library/Application Support/MeetingRescue`.
  - 현재 settings의 `providerTimeoutSeconds`: `60`.
  - 최근 timeout 대상: `/Users/ethan/Documents/Recordings/20260514_173245_Zigbang(2F)_Meeting Room L4.txt`.
  - 최근 실패들은 `automatic`, `gpt-5.4-mini`, `LLM provider 실행 시간이 초과되었습니다.`로 기록되어 있었다.
  - 실패 attempt는 `03:49:13-03:50:13`, `03:50:21-03:51:21`, `03:52:22-03:53:22`, `03:53:31-03:54:31`처럼 모두 60초에서 종료됐다.
  - 입력 token 추정치는 실패 시점에 `4088`, `5943`, `9233`, `9238`로 증가했다. 중간에 `7735` tokens run은 51초 만에 성공했지만, 이후 9k tokens대 run은 60초 timeout에 걸렸다.
- 검증:
  - `jq ~/Library/Application\\ Support/MeetingRescue/settings.json`: `providerTimeoutSeconds`가 `60`임을 확인했다.
  - `jq`로 `Sessions/*-analysis.json`의 `attemptLogs`를 조회해 최근 failed/retryScheduled attempt를 확인했다.
  - 문서/tracker 변경과 local state 조회만 수행했으므로 build/test는 실행하지 않았다.

### 2026-05-15 Backlog 정리

- 사용자 요청에 따라 `microphone capture와 STT`를 Backlog에서 제거했다.
- 이유:
  - Meeting Rescue의 현재 방향은 외부 transcript 파일을 source로 meeting intelligence를 구축하는 local companion에 가깝다.
  - microphone/STT를 직접 포함하면 권한, 개인정보, audio pipeline, diarization, 품질 검증까지 scope가 크게 넓어져 현재 v1 운영 polish와 분리하는 편이 맞다.
- 검증:
  - 문서 전용 변경이라 build/test는 실행하지 않았다.

### 2026-05-15 Meeting Intelligence 표시/usage/export/timeout diagnostics 개선

- 사용자 요청에 따라 Phase 3 이후 v1 운영 polish 범위에서 Meeting Intelligence 표시와 analysis failure 관측성을 개선했다. 새로운 phase를 열지 않고 현재 앱 범위 안에서 처리했다.
- 수정 내용:
  - `YYYY-MM-DDTHH:mm:ssZ` 형태의 topic/candidate timestamp를 summary/timeline/markdown에서 회의 경과 시간 `[04:13]` 형식으로 표시하도록 `MeetingTimestampFormatter`를 추가했다.
  - analysis state에 `usageSummary`와 `attemptLogs`를 추가해 input token 추정치, output token 추정치, 선택 model 기준 누적 추정 비용, 실행 reason/status/error/retry 기록을 저장한다.
  - Codex provider 결과에 prompt/stdout 기반 usage estimate를 붙이고, UI header와 summary diagnostics card에 누적 usage와 최근 attempt를 표시한다.
  - `Markdown` 저장 버튼과 `MeetingIntelligenceMarkdownExporter`를 추가해 현재 Meeting Intelligence를 `.md`로 저장할 수 있게 했다.
  - timeout/failure 발생 시 이전 successful snapshot 또는 local fallback을 유지하고 failure attempt를 기록한다.
  - final end marker가 아닌 일반 실패는 다음 automatic tick에서 previous snapshot과 최신 transcript를 포함해 재시도하도록 scheduling한다.
  - final analysis 실패는 종료 snapshot 누락을 줄이기 위해 최대 2회 짧은 delay 후 재시도한다.
  - README에 LLM 사용량/비용 추정의 한계, analysis 실행 흐름, 실패/재시도 동작, markdown export 수동 검증 경로를 추가했다.
- 가격 조사:
  - OpenAI official pricing 확인: standard short context 기준 `gpt-5.4-mini` $0.375/$2.25, `gpt-5.4` $1.25/$7.50, `gpt-5.5` $2.50/$15.00 per 1M input/output tokens.
  - Anthropic official pricing 확인: `Claude Haiku 4.5` $1/$5, `Claude Sonnet 4.6` $3/$15, `Claude Opus 4.7` $5/$25 per 1M input/output tokens.
  - Gemini Developer API pricing 확인: `gemini-3.1-flash-lite-preview` $0.25/$1.50, `gemini-3-flash-preview` $0.50/$3.00, `gemini-3.1-pro` $2/$12 per 1M input/output tokens.
  - 현재 앱의 token/cost 값은 provider billing API 값이 아니라 prompt/stdout 길이 기반 local estimate임을 README에 명시했다.
- Analysis 실행 흐름:
  - transcript tail 또는 Test Run replay가 raw transcript를 갱신한다.
  - automatic cadence 또는 수동 `분석`으로 `AnalysisRequest`를 만들고 metadata, transcript suffix, previous snapshot, confirmed/deleted ids, provider, model preset, reason을 포함한다.
  - scheduler가 meeting별 single-flight로 provider를 실행한다.
  - 성공하면 snapshot, usage estimate, attempt success log를 저장한다.
  - 실패하면 기존 snapshot을 보존하고 error/failure attempt를 저장한다. 일반 실패는 다음 automatic tick에서 재시도하고, final 실패는 explicit retry를 예약한다.
- 검증:
  - `swift test`: 통과. 28개 test / 12개 suite가 통과했다.
  - `git diff --check`: 통과.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.
  - Computer Use `get_app_state`: 통과. 재실행된 `Meeting Rescue.app`에서 `Markdown` 버튼, `usage` chip, `provider Codex · Economy`, empty/loading state가 정상 렌더링됨을 확인했다.
  - `pgrep -fl 'codex exec --skip-git-repo-check --ephemeral --sandbox read-only --output-schema.*/MeetingRescue_MeetingRescue.bundle' || true`: 통과. leftover provider process가 없음을 확인했다.

### 2026-05-15 model preset mapping 최신화

- OpenAI official model docs를 다시 확인해 Codex provider의 preset-to-model mapping을 최신 frontier/general model 계열로 조정했다.
- 수정 내용:
  - `Frontier`는 사용자 의도대로 `gpt-5.5`로 변경했다.
  - official docs가 복잡한 reasoning/coding 시작점으로 `gpt-5.5`를, 더 저렴한 최신 계열로 `gpt-5.4-mini`/`gpt-5.4-nano`를 권장하는 것을 확인했다.
  - meeting intelligence는 structured summary/candidate extraction이라 `Economy`는 `gpt-5.4-mini`, `Balanced`는 더 넓은 품질 여지를 위해 `gpt-5.4`로 변경했다.
  - README와 provider configuration tests의 model id 기대값을 함께 갱신했다.
- 검증:
  - OpenAI official docs 확인: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini` model id와 용도/가격 설명을 확인했다.
  - `swift test`: 통과. provider configuration tests를 포함해 23개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.

### 2026-05-15 provider 공통 model preset 추가

- Codex 전용 `--model` 선택이 아니라 이후 다른 LLM provider에도 재사용 가능한 `model preset` 설정을 추가했다.
- 수정 내용:
  - `LLMModelPreset`을 추가했다: `CLI default`, `Economy`, `Balanced`, `Frontier`.
  - 새 기본값은 반복적인 live meeting intelligence 비용을 낮추기 위해 `Economy`로 설정했다.
  - Codex provider는 preset에 따라 `--model`을 주입한다:
    - `CLI default`: `--model` 생략
    - `Economy`: `gpt-5.1-codex-mini`
    - `Balanced`: `gpt-5.1-codex`
    - `Frontier`: `gpt-5.2-codex`
  - Custom Command provider에는 `MEETING_RESCUE_LLM_MODEL_PRESET`, `MEETING_RESCUE_LLM_MODEL` 환경변수를 전달해 이후 다른 LLM adapter도 같은 preset 의미를 해석할 수 있게 했다.
  - prompt payload에도 `providerKind`, `modelPreset`을 포함해 분석 요청의 실행 맥락을 남겼다.
  - settings UI에 `model preset` picker와 preset 설명을 추가하고 header provider chip에 현재 preset을 표시했다.
  - 기존 settings JSON에 `modelPreset`이 없어도 기존 provider/cadence/timeout/custom command를 유지하며 `Economy`로 decode되도록 했다.
  - README에 provider 공통 model preset과 Codex model mapping, Custom Command 환경변수 계약을 기록했다.
- 검증:
  - `codex exec --help`: 통과. `-m, --model <MODEL>` 옵션이 현재 CLI에 존재함을 확인했다.
  - OpenAI official docs 확인: `gpt-5.2-codex`, `gpt-5.1-codex`, `gpt-5.1-codex-mini` model 문서와 비용/용도 설명을 확인했다.
  - `swift test`: 통과. legacy settings decode, Codex `--model` argument 생성, automatic preset의 `--model` 생략, Custom provider 환경변수 포함 test를 포함해 23개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - Computer Use `get_app_state`: 통과. header에 `provider Codex · Economy`가 표시됨을 확인했다.
  - Computer Use settings: 통과. `model preset` picker에 `CLI default`, `Economy`, `Balanced`, `Frontier`가 표시되고 선택 설명이 갱신됨을 확인했다. 검증 후 preset은 `Economy`로 되돌렸다.

### 2026-05-15 Test Run 배속 및 app bundle signing 수정

- Test Run replay에 `1x`/`2x`/`4x`/`8x` 배속 control을 추가했다.
- 수정 내용:
  - Test Run header에 speed menu를 추가하고 현재 배속을 status chip으로 표시했다.
  - timestamp 간격 기반 replay delay를 선택 배속으로 나누어 적용했다. 예: `[12:10]` 이후 `[12:13]` line은 `1x`에서 약 3초, `4x`에서 약 0.75초 뒤 표시된다.
  - 배속 delay 계산을 `TranscriptReplayCursor.adjustedDelay`로 분리하고 focused test를 추가했다.
  - `Live` 복귀 시 실행 중인 analysis task도 cancel해 Test Run에서 시작된 provider process가 남지 않도록 했다.
  - 앱 번들 signing 실패 원인이던 resource bundle root copy를 제거하고 `Contents/Resources`에서 schema를 찾도록 변경했다.
  - generated `Info.plist`에 `NSDocumentsFolderUsageDescription`을 추가했다.
  - README에 Test Run 배속 검증 경로와 macOS Documents 접근 팝업 설명을 추가했다.
- 팝업 원인 판단:
  - `/Users/ethan/Documents/Recordings`가 macOS privacy 보호 대상인 `Documents` 아래에 있어 앱 단위 접근 허용이 필요하다.
  - 기존 `scripts/build_app.sh`는 app bundle root의 unsealed resource 때문에 `codesign`이 실패했지만 실패를 숨기고 있었고, 실제 signature identifier가 `com.local.meeting-rescue`로 묶이지 않았다.
  - 이 상태와 ad-hoc 재빌드는 macOS TCC가 앱 identity를 안정적으로 기억하지 못해 같은 권한 팝업을 반복 표시하는 원인이 될 수 있다.
- 검증:
  - `swift test`: 통과. 19개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `codesign -dv --verbose=4 'dist/Meeting Rescue.app'`: 통과. `Identifier=com.local.meeting-rescue`, `Info.plist entries=12`, `Sealed Resources version=2`를 확인했다.
  - Computer Use `get_app_state`: 통과. 새 앱이 실행되고 `Live Watch` empty state가 정상 렌더링됨을 확인했다.
  - Computer Use `Test Run`: 통과. `/Users/ethan/Documents/Recordings/20251229_170115_Zigbang(2F)_Meeting Room L5.txt`를 선택해 Test Run이 시작되고 speed menu가 `1x`에서 `4x`로 변경되며 `speed 4x` chip이 표시됨을 확인했다.
  - `pgrep -fl 'codex exec --skip-git-repo-check --ephemeral --sandbox read-only --output-schema.*/MeetingRescue_MeetingRescue.bundle'`: 통과. cleanup 후 leftover provider process가 없음을 확인했다.

### 2026-05-15 Test Run timestamp-paced replay 수정

- Test Run replay가 고정 tick으로 여러 줄을 빠르게 주입하던 동작을 transcript timestamp 간격 기반으로 변경했다.
- 수정 내용:
  - `TranscriptReplayCursor`가 preamble/header는 즉시 frame으로 만들고, timestamp line은 한 줄씩 frame으로 만든다.
  - 각 timestamp frame은 현재 줄과 다음 timestamp 줄의 시간 차이를 `delayAfterSeconds`로 계산한다.
  - 예: `[12:10]` frame 이후 다음 timestamp가 `[12:13]`이면 다음 line을 약 3초 뒤 표시한다.
  - 동일 timestamp 또는 역전 timestamp는 최소 display delay를 사용하고, timestamp가 없는 줄은 fallback delay를 사용한다.
  - Test Run timer를 repeating timer에서 frame별 one-shot timer로 바꿔 timestamp 간격을 반영했다.
  - README Test Run 검증 경로에 timestamp-paced 동작을 명시했다.
- 검증:
  - `swift test`: 통과. 18개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - Computer Use `get_app_state`: 통과. 재생성된 앱에서 `Test Run` control이 표시되고 live transcript 화면이 정상 렌더링됨을 확인했다.

### 2026-05-15 Test Run replay 기능 추가

- 사용자가 선택한 `.txt` 파일로 `Meeting Intelligence`를 빠르게 검증할 수 있도록 `Test Run` replay 기능을 추가했다.
- 수정 내용:
  - `TranscriptReplayCursor`를 추가해 transcript 파일을 line 순서대로 replay frame으로 나눌 수 있게 했다.
  - 앱 상단에 `Test Run`, `일시정지/재개`, `Live` control을 추가했다.
  - `Test Run` 중에는 live folder scan과 최신 파일 자동 전환을 멈추고, 선택 파일을 active transcript로 고정한다.
  - replay는 header를 먼저 주입한 뒤 dialogue line을 시간순으로 누적하고, progress chip에 `현재 line / 전체 line`을 표시한다.
  - replay 진행 중 local fallback `Meeting Intelligence`를 계속 갱신해 topic count와 최근 흐름이 동적으로 변하는 것을 확인할 수 있게 했다.
  - `Live` 복귀 또는 active meeting 전환 시 실행 중인 provider process가 timeout까지 남지 않도록 `ProcessRunner` cancellation을 자식 process termination까지 전파했다.
  - README에 `Test Run` 검증 경로를 추가했다.
- 검증:
  - `swift test`: 통과. 16개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - Computer Use `Test Run`: 통과. `/Users/ethan/Documents/Recordings/20251229_170115_Zigbang(2F)_Meeting Room L5.txt`를 선택해 `mode Test Run`, `4 / 251 lines`, `88 / 251 lines`, `133 / 251 lines`로 progress가 증가하고 raw transcript가 누적되는 것을 확인했다.
  - Computer Use `Test Run` intelligence: 통과. replay가 진행되면서 fallback summary의 최근 발화, topic count, 최근 흐름이 갱신되는 것을 확인했다.
  - Computer Use `일시정지`, `Live`: 통과. pause 상태로 전환되고, `Live` 복귀 시 최신 active transcript 자동 선택 모드로 돌아오는 것을 확인했다.
  - `pgrep -fl 'codex exec --skip-git-repo-check --ephemeral --sandbox read-only --output-schema.*/MeetingRescue_MeetingRescue.bundle'`: cleanup 후 실행 중인 leftover provider process가 없음을 확인했다.

### 2026-05-15 Smooth 참고 디자인 및 summary UX 개선

- `https://www.trysmooth.ai/ko`의 밝은 product UI, pill/segmented control, card 중심 정보 구조를 참고해 native macOS app 디자인을 조정했다.
- Computer Use로 현재 실행 중인 `Meeting Rescue.app`을 확인했고, 기존 `Meeting Intelligence`가 긴 문서처럼 이어져 회의 중 one-pager로 보고 반응하기 어렵다는 점을 확인했다.
- 수정 내용:
  - 전체 배경을 warm off-white canvas로 바꾸고 white panel/card, green accent, compact chip을 적용했다.
  - header를 status/provider/update/line count chip 중심으로 정리했다.
  - `Meeting Intelligence`를 `요약`, `흐름`, `후보` segmented view로 분리했다.
  - 기본 `요약` view는 current issue, topic/decision/action count, 결정 후보, 액션 후보, 최근 흐름, notes를 카드로 묶어 한 화면에서 판단/반응하기 쉽게 했다.
  - 전체 topic timeline은 `흐름`, 후보 confirm/delete 중심 작업은 `후보` view에서 볼 수 있게 했다.
  - Codex provider는 `--model`을 지정하지 않고 Codex CLI default model을 사용한다는 설명을 settings에 추가했다.
- 검증:
  - `swift test`: 통과. 15개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - Computer Use `get_app_state`: 통과. 새 카드형 `요약` view, `흐름` segmented view, green accent tint, panel layout이 표시됨을 확인했다.

### 2026-05-15 analysis 미표시 원인 수정

- Computer Use로 실행 중인 `Meeting Rescue.app`을 관찰했고, `Meeting Intelligence` pane이 비어 있거나 provider 실패 후 의미 있는 snapshot 없이 남을 수 있음을 확인했다.
- 원인:
  - `analysis-output.schema.json`이 OpenAI/Codex strict JSON schema 규칙을 만족하지 않았다. nullable optional property가 `properties`에는 선언되어 있지만 `required`에 빠져 있어 `invalid_json_schema` 오류가 발생했다.
  - 첫 분석이 실패하거나 timeout될 때 이전 successful snapshot이 없는 경우 표시할 fallback snapshot이 없어 사용자가 `analysis`가 한 번도 뜨지 않는 것처럼 보였다.
- 수정 내용:
  - checked-in output schema에서 모든 declared property를 `required`에 포함하고 optional 값은 nullable로 유지했다.
  - app runtime에서 채우는 `generatedAt`, `provider`는 schema output 요구사항에서 제거했다.
  - LLM prompt에 optional 값은 key를 생략하지 말고 `null` 또는 빈 배열로 채우도록 명시했다.
  - provider 결과가 아직 없거나 실패한 경우에도 transcript 기반 `LocalAnalysisFallback` snapshot을 만들어 `Meeting Intelligence` pane에 즉시 표시하도록 했다.
  - strict schema required 규칙과 fallback snapshot 생성을 검증하는 focused test를 추가했다.
- 검증:
  - `swift test`: 통과. 15개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `printf '%s\n' 'Return a concise valid JSON object for a tiny meeting. Include null optional values and empty arrays where needed.' | codex exec --skip-git-repo-check --ephemeral --sandbox read-only --output-schema Sources/MeetingRescue/Resources/analysis-output.schema.json -`: 통과. `invalid_json_schema` 없이 schema-valid JSON을 반환했다.
  - Computer Use `get_app_state`: 통과. `Meeting Intelligence` pane에 fallback current issue와 topic timeline이 표시됨을 확인했다.

### 2026-05-15 Computer Use UI/performance 점검 및 수정

- Computer Use로 실행 중인 `Meeting Rescue.app`을 관찰했다.
- 발견한 문제:
  - root view가 `minHeight` 중심으로 잡혀 큰 창에서 상단에 큰 빈 공간이 생겼다.
  - 긴 raw transcript를 단일 `Text`로 렌더링해 live update 중 SwiftUI/CoreText layout 비용이 커졌다.
  - 앱 시작 직후 automatic analysis가 즉시 실행되어 live transcript 확인 중 UI가 `analysis 실행 중`으로 묶였다.
  - Codex failure stderr가 header 상태 영역에 길게 들어와 레이아웃을 밀었다.
  - 완료 marker가 있는 meeting을 다시 열 때 final analysis를 반복 trigger할 수 있었다.
- 수정 내용:
  - root view와 split view가 window 전체를 채우도록 `maxWidth/maxHeight` frame을 추가했다.
  - header metadata layout을 좌우 column으로 재구성하고 긴 참석자/파일/status text는 한 줄 truncate 처리했다.
  - raw transcript UI를 전체 단일 `Text`에서 최근 220줄의 line 기반 `LazyVStack` preview로 변경했다.
  - LLM prompt transcript는 24,000자 budget으로 제한해 긴 회의가 provider 호출을 과도하게 키우지 않도록 했다.
  - app launch 직후 automatic analysis를 즉시 시작하지 않고 cadence 이후부터 시작하도록 했다.
  - 이미 complete로 저장된 meeting은 재실행 시 final analysis를 반복하지 않도록 했다.
  - stale/failure message는 header에서 짧게 compact하고, snapshot이 없을 때는 intelligence pane에 failure state를 표시하도록 했다.
- 검증:
  - `sample <MeetingRescue pid> 2 -mayDie`: 수정 전에는 `StyledTextLayoutEngine`/CoreText가 긴 transcript 단일 `Text` 측정에 시간을 쓰는 것을 확인했다.
  - `swift test`: 통과. 13개 test가 통과했다.
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 재생성 완료.
  - `open "dist/Meeting Rescue.app"` 후 `ps -o pid,pcpu,pmem,etime,command`: 초기 렌더 후 CPU가 약 `1.0%` 수준으로 안정화되는 것을 확인했다.
  - Computer Use `get_app_state`: 통과. 상단 빈 공간이 사라지고 `analysis 대기` 상태로 표시됨을 확인했다.
  - Computer Use `drag`: 통과. split divider를 드래그해 raw transcript pane과 intelligence pane 폭이 조정되는 것을 확인했다.

### 2026-05-14 실행 가능한 app bundle 추가

- `swift run MeetingRescue`뿐 아니라 더블클릭 가능한 local `.app` bundle을 만들 수 있도록 `scripts/build_app.sh`를 추가했다.
- script는 `swift build -c release --product MeetingRescue` 후 `dist/Meeting Rescue.app`을 만들고, executable과 `MeetingRescue_MeetingRescue.bundle` resource bundle을 함께 복사한다.
- SwiftPM `Bundle.module`이 app bundle root의 `MeetingRescue_MeetingRescue.bundle`을 먼저 찾는 구조라, schema resource가 double-click 실행에서도 동작하도록 app root와 `Contents/Resources` 양쪽에 resource bundle을 배치했다.
- `dist/`는 generated artifact라 `.gitignore`에 추가했고, README에 app bundle 생성과 실행 방법을 추가했다.
- 검증:
  - `./scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` 생성 완료.
  - `test -x "dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue"`: 통과. app executable 존재와 실행 권한을 확인했다.
  - `test -f "dist/Meeting Rescue.app/Contents/Info.plist"`: 통과.
  - `test -f "dist/Meeting Rescue.app/MeetingRescue_MeetingRescue.bundle/Resources/analysis-output.schema.json"`: 통과.
  - `open "dist/Meeting Rescue.app"; sleep 4; osascript -e 'tell application "Meeting Rescue" to quit'`: 통과. app bundle을 launch하고 종료했다.
  - `swift test`: 통과. 13개 test가 통과했다.
  - `git diff --check`: 통과.

### 2026-05-14 Phase 2-3 구현

- Phase 2와 Phase 3를 구현했다. 이전에 수정했던 Phase 2의 LLM provider 선택 요구사항도 함께 반영했다.
- Phase 2 구현 내용:
  - 기본 LLM provider로 `codex exec` adapter를 추가했다.
  - `codex exec --skip-git-repo-check --ephemeral --sandbox read-only --output-schema <schema> -` 호출 경로를 구현했다.
  - Codex에 고정되지 않도록 provider 공통 계약(`LLMProvider`)과 `Custom Command` provider adapter를 추가했다.
  - checked-in output schema file(`Sources/MeetingRescue/Resources/analysis-output.schema.json`)을 추가했다.
  - `AnalysisScheduler` actor를 추가해 같은 meeting의 analysis job이 겹쳐 실행되지 않도록 했다.
  - active meeting switch 이후 stale result를 무시하도록 했다.
  - provider timeout/failure 시 이전 successful snapshot을 유지하고 error 상태를 표시하도록 했다.
  - prompt payload에 meeting metadata, transcript, previous snapshot, confirmed candidate ids, deleted candidate ids를 포함하도록 했다.
  - `currentIssue`, `topicTimeline`, `decisionCandidates`, `actionItemCandidates`, `risksOrNotes` snapshot model을 추가했다.
  - normalized text와 evidence timestamp 기반 stable candidate id generator를 추가했다.
  - decision/action candidate confirm/delete state를 meeting별로 저장하고 refresh snapshot에 재적용하도록 했다.
  - transcript end marker(`[SYSTEM] 대화 기록 종료`, `[SYSTEM] Chat Logs has been ended`) 감지와 final analysis trigger 상태를 추가했다.
- Phase 3 구현 내용:
  - raw transcript와 meeting intelligence를 나란히 보는 split view UI로 개선했다.
  - 긴 transcript readability를 위해 monospaced callout, line spacing, scroll-to-bottom behavior를 조정했다.
  - settings UI를 추가했다:
    - selected Recordings folder 변경
    - LLM provider 선택
    - analysis cadence 30-60초
    - provider timeout
    - custom provider command
  - status indicator를 추가했다:
    - watching folder/status message
    - active file
    - transcript updated time
    - analysis running/stale/failed/completed
    - selected provider
  - non-destructive reset control을 추가했다:
    - 선택 폴더 잊기
    - 현재 meeting analysis state 지우기
  - README를 setup, default Codex provider login, LLM provider selection, run/test/manual validation, known limitations 중심으로 갱신했다.
- 범위 밖으로 유지한 항목:
  - inline text editing, markdown export, search archive, microphone recording, STT, Slack/Jira/Calendar integration은 구현하지 않았다.
- 검증:
  - `codex exec --help`: 통과. Phase 2에서 요구한 `--skip-git-repo-check`, `--ephemeral`, `--sandbox read-only`, `--output-schema` 옵션이 현재 CLI에 존재함을 확인했다.
  - `swift test`: 최초 1회는 Swift 6 strict concurrency가 `Process.terminationHandler`의 non-Sendable capture를 막아 실패했다. `ProcessRunner`를 detached blocking runner로 수정했다.
  - `swift test`: 통과. scheduler single-flight, stale result ignored, candidate confirm/delete persistence, stable candidate id, provider failure preserving previous snapshot, output decode, parser/latest-file tests 포함 총 13개 test가 통과했다.
  - `swift build`: 통과. debug build 완료.
  - `latest=$(find /Users/ethan/Documents/Recordings -maxdepth 1 -type f -iname '*.txt' -print0 | xargs -0 ls -t 2>/dev/null | head -1); printf 'Recordings latest: %s\n' "$latest"; if [ -n "$latest" ]; then tail -5 "$latest"; fi`: 통과. 최신 transcript `/Users/ethan/Documents/Recordings/20260514_173245_Zigbang(2F)_Meeting Room L4.txt`에서 `[SYSTEM] 대화 기록 종료` end marker를 확인했다.
  - `(swift run MeetingRescue > /tmp/meeting-rescue-smoke.log 2>&1 & pid=$!; sleep 4; if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; printf 'swift run MeetingRescue launched and was terminated after smoke window\n'; else wait "$pid"; printf 'swift run MeetingRescue exited during smoke\n'; fi; printf '%s\n' '--- smoke log ---'; cat /tmp/meeting-rescue-smoke.log)`: 통과. 앱 product build 후 실행 프로세스가 올라오는 것을 확인하고 smoke window 뒤 종료했다.
  - 실제 GUI에서 folder picker 클릭, live append, provider failure indicator 버튼 조작은 자동화된 현재 실행에서 장시간 수동 조작하지 않았다. 대신 README에 `/Users/ethan/Documents/Recordings` 기준 수동 검증 경로를 갱신했고, 해당 동작의 core behavior는 focused tests로 검증했다.

### 2026-05-14 Phase 1 구현

- Phase 1만 구현했다. Swift Package 기반 native SwiftUI macOS 앱을 scaffold했고, core target(`MeetingRescueCore`)과 app target(`MeetingRescue`)을 분리했다.
- 구현 내용:
  - 첫 실행/재선택용 macOS folder picker를 추가했다.
  - 선택 폴더 security-scoped bookmark 저장/복원을 추가했다.
  - 선택 폴더의 `.txt` 파일 중 modification time 기준 최신 파일을 active transcript로 선택하도록 했다.
  - 1초 polling으로 active file 변경과 append를 감지해 raw transcript UI를 갱신하도록 했다.
  - transcript header parser를 추가했다. label 기반 header(`Room:`, `Date/Time:`, `Participants:`)와 `/Users/ethan/Documents/Recordings` 실제 파일의 unlabeled 3-line header 형식을 지원한다.
  - parsed dialogue에서 `[SYSTEM]` speaker line을 제외하도록 했다.
  - Application Support 아래에 마지막 폴더 bookmark와 meeting별 `sourceFilePath`, `metadata`, `rawReadOffset`, `updatedAt` session state를 저장하도록 했다.
  - README에 `/Users/ethan/Documents/Recordings` 수동 검증 경로를 추가했다.
- 범위 밖으로 유지한 항목:
  - Codex/LLM analysis, microphone recording, STT, markdown export, search, Slack/Jira/Calendar integration은 구현하지 않았다.
- 검증:
  - `swift test`: 최초 1회는 Swift 6 actor isolation 오류로 실패했다. `AppViewModel.deinit`의 MainActor-isolated state 접근을 제거한 뒤 재실행했다.
  - `swift test`: 통과. `LatestTranscriptSelector` 2개, `TranscriptParser` 3개, 총 5개 test가 통과했다.
  - `swift build`: 통과. debug build 완료.
  - `if [ -d /Users/ethan/Documents/Recordings ]; then printf 'Recordings directory exists\n'; find /Users/ethan/Documents/Recordings -maxdepth 1 -type f -iname '*.txt' -print | head -5; else printf 'Recordings directory missing\n'; fi`: 통과. `Recordings directory exists` 및 `.txt` 파일 예시가 확인됐다.
  - `latest=$(find /Users/ethan/Documents/Recordings -maxdepth 1 -type f -iname '*.txt' -print0 | xargs -0 ls -t 2>/dev/null | head -1); printf 'Latest transcript: %s\n' "$latest"; if [ -n "$latest" ]; then sed -n '1,40p' "$latest"; fi`: 통과. 최신 파일 `/Users/ethan/Documents/Recordings/20260514_173245_Zigbang(2F)_Meeting Room L4.txt`의 실제 unlabeled header와 timestamped dialogue 형식을 확인했고 parser test에 반영했다.

### 2026-05-14

- `tasks.md` 전체를 한글 문서로 변환했다. code identifier, command, schema key, path, proper noun은 원문을 유지했다.
- 모든 output 문서를 한글로 작성하고, 검증된 코드 변경 후 git commit을 남기도록 운영 원칙을 업데이트했다.
- phase goal, scope boundary, validation expectation, 운영 원칙을 포함한 초기 `tasks.md`를 생성했다.
- tracker 생성 시점의 project directory는 비어 있었고 git repository가 아니었다.
