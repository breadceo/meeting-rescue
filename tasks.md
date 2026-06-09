# Meeting Rescue 작업 목록

## 운영 원칙

- `tasks.md`를 프로젝트의 phase/backlog source of truth로 사용하고, 실행 이력은 `execution-log.md`에서 관리한다.
- 모든 구현 실행은 종료 전에 `tasks.md` 또는 `execution-log.md` 중 관련 문서를 업데이트해야 한다.
- 상태는 사실과 근거 중심으로 기록한다. 구현과 검증이 모두 끝나기 전에는 작업을 완료로 표시하지 않는다.
- 범위 경계를 지킨다. 요청된 변경이 이후 phase에 속하면 활성 phase 범위를 조용히 넓히지 말고 `Backlog`에 추가한다.
- 정확한 검증 명령과 결과를 `execution-log.md`에 기록한다.
- 작업이 막히면 상태를 `Blocked`로 표시하고, 구체적인 blocker와 다음에 필요한 조치를 함께 적는다.
- 과거 실행 로그는 삭제하지 않는다. 새 로그는 `execution-log.md`의 맨 위에 추가한다.
- README, 매뉴얼, 사용자-facing 회의 분석 prompt, 프로젝트 노트 등 모든 output 문서는 한글로 작성한다. 단, code identifier, command name, schema key, proper noun은 원문을 유지한다.
- 코드 변경 후에는 관련 검증을 실행하고, 이 파일을 업데이트한 뒤, 완료된 구현과 tracker 변경을 git commit으로 남긴다. 관련 없는 local change는 커밋하지 않는다.
- 릴리즈/업데이트 작업에서는 checked-in appcast 위치만 믿지 말고, 실제 빌드된 앱의 `Info.plist`에 들어간 `SUFeedURL`을 source of truth로 확인한다. 현재 설치 앱의 기본 Sparkle feed는 `breadceo/meeting-rescue-updates`의 `appcast.xml`이므로, GitHub Release 발행 후 해당 feed와 `releases/latest.md`가 새 버전으로 갱신됐는지 `raw.githubusercontent.com` 기준으로 검증한다. CDN cache 때문에 지연될 수 있으므로 최종 확인은 앱이 실제로 읽는 URL에서 `sparkle:shortVersionString`이 새 버전으로 보일 때까지 수행한다.

## 상태 표기

- `Not Started`: 구현 작업이 아직 시작되지 않음.
- `In Progress`: 구현은 시작됐지만 구현 또는 검증이 남아 있음.
- `Blocked`: 구체적인 누락 의존성, 결정, 환경 수정 없이는 진행할 수 없음.
- `Done`: 구현이 완료됐고 검증이 통과했거나, 남은 검증 gap이 명시적으로 수용됨.

## Phase 1: 네이티브 앱 shell + 실시간 transcript

상태: `Done`

목표:
로컬에서 실행되는 native SwiftUI macOS 앱을 만든다. 앱은 Recordings 폴더를 선택하고, 최신 `.txt` transcript 파일을 따라가며, `tailrec`처럼 raw transcript를 실시간으로 보여준다.

요구사항:

- `/Users/ethan/Documents/git/meeting-rescue`에 새 native SwiftUI macOS project를 scaffold한다.
- 이 디렉터리를 새 프로젝트로 취급한다. 일반적인 Xcode/Swift project hygiene에 필요할 때만 git을 초기화한다.
- 첫 실행 시 macOS folder picker로 transcript 폴더를 선택하게 한다.
- 선택한 폴더 권한은 security-scoped bookmark로 저장한다.
- 기본 예상 폴더는 `/Users/ethan/Documents/Recordings`이지만, 사용자 선택 없이 접근 경로를 hardcode하지 않는다.
- 선택한 폴더의 `.txt` 파일을 watch한다.
- modification time 기준으로 최신 `.txt` 파일을 자동으로 따라간다.
- 최신 파일이 바뀌면 active meeting을 전환한다.
- active transcript 파일을 tail하고 새 줄이 추가될 때 UI를 업데이트한다.
- transcript header를 parse한다:
  - room
  - date/time
  - participants
  - timestamped dialogue lines
  - parsed dialogue에서는 `[SYSTEM]` line을 무시한다. raw transcript에서는 필요하면 그대로 보여줄 수 있다.
- Application Support에 최소한의 per-meeting local session state를 저장한다:
  - source file path
  - active meeting metadata
  - raw read offset 또는 clean resume에 충분한 state
  - last opened folder bookmark
- UI:
  - main window 상단에 현재 meeting metadata를 보여준다.
  - main content에 live raw transcript를 보여준다.
  - transcript가 없을 때 명확한 empty/loading state를 제공한다.
  - 현재 active file indicator를 표시한다.
- Phase 1에서는 Codex/LLM analysis를 구현하지 않는다.
- Phase 1에서는 microphone recording, STT, markdown export, search, Slack/Jira/Calendar integration을 구현하지 않는다.

검증:

- transcript parsing과 latest-file selection에 대한 focused test를 추가한다.
- `/Users/ethan/Documents/Recordings`로 앱 실행과 검증을 수행하는 간단한 manual test path 또는 README note를 추가한다.
- 가능한 build/test를 실행하고 정확한 명령과 결과를 `실행 로그`에 기록한다.

## Phase 2: 실시간 LLM 회의 intelligence

상태: `Done`

선행 조건:
Phase 1에서 Recordings 폴더 선택, 최신 `.txt` transcript 추적, raw transcript 실시간 표시가 동작하는 SwiftUI macOS 앱이 준비되어 있어야 한다.

목표:
초기 기본 LLM provider는 로컬 Codex subscription 기반의 `codex exec`로 두고 live meeting intelligence를 추가한다. 단, 사용자별로 구독하거나 사용할 수 있는 LLM이 다를 수 있으므로, 앱은 Codex에 고정되지 않고 다른 LLM provider를 선택할 수 있는 구조와 설정을 가져야 한다. 앱은 active transcript를 주기적으로 분석하고, raw transcript가 계속 업데이트되는 동안 회의 흐름, 결정 사항, action item 후보를 갱신해야 한다.

요구사항:

- 초기 기본 provider는 로컬 `codex exec` LLM worker로 구현한다.
- 사용자는 LLM provider를 선택할 수 있어야 한다. 초기 버전에서 Codex 외 provider가 모두 완성되지 않더라도, provider 선택 설정과 provider adapter 경계는 Codex 전용으로 굳히지 않는다.
- analysis scheduler, prompt 구성, output schema validation, persistence는 provider 공통 계약을 기준으로 동작해야 한다.
- Codex provider는 OpenAI API key를 사용하지 않는다.
- Codex provider는 non-interactive 방식으로 다음 옵션을 사용해 호출한다:
  - `--skip-git-repo-check`
  - `--ephemeral`
  - `--sandbox read-only`
  - checked-in JSON schema file을 사용하는 `--output-schema`
- 이후 provider가 별도 인증 정보나 실행 경로를 요구하면 사용자 설정으로 주입하며, code에 provider-specific secret을 hardcode하지 않는다.
- single-flight analysis scheduler를 추가한다:
  - 기본 cadence: 45초.
  - 사용자 설정 가능 범위: 30초에서 60초.
  - automatic analysis는 절대 60초를 초과해서 schedule하지 않는다.
  - 같은 meeting에 대해 LLM analysis job을 겹쳐 실행하지 않는다.
- LLM prompt에는 다음을 포함한다:
  - meeting metadata
  - analysis에 필요한 transcript content
  - previous analysis snapshot
  - confirmed candidate ids
  - deleted candidate ids
- LLM output schema에는 다음을 포함한다:
  - `currentIssue`: 짧은 한글 요약과 optional open questions
  - `topicTimeline[]`: id, start/end timestamp, title, summary
  - `decisionCandidates[]`: id, text, status, evidence timestamp, speaker if known
  - `actionItemCandidates[]`: id, assignee if explicit, task, deadline if explicit, evidence timestamp, speaker if known
  - `risksOrNotes[]`
- candidate id는 normalized text와 evidence timestamp에서 파생해 refresh 이후에도 stable해야 한다.
- UI:
  - raw transcript는 analysis state와 독립적으로 계속 live update한다.
  - meeting intelligence view를 추가한다:
    - current issue summary
    - compact topic timeline
    - decision candidates
    - action item candidates
  - decision/action candidate는 기본적으로 candidate 상태로 표시한다.
  - 사용자는 candidate를 confirm 또는 delete할 수 있다.
  - v1에서는 inline text editing을 구현하지 않는다.
- Persistence:
  - latest analysis snapshot을 저장한다.
  - meeting별 confirmed/deleted candidate ids를 저장한다.
  - 이후 LLM refresh에서도 confirmed/deleted state를 유지한다.
- Failure behavior:
  - 선택된 LLM provider가 느리거나 timeout/failure가 발생하면 이전 successful analysis를 계속 표시한다.
  - raw transcript update는 계속한다.
  - 작은 stale/error indicator를 표시한다.
  - active meeting file이 바뀌면 stale LLM output을 cancel하거나 무시한다.
- Meeting end behavior:
  - transcript end marker를 감지한다:
    - `[SYSTEM] 대화 기록 종료`
    - `[SYSTEM] Chat Logs has been ended`
  - final LLM snapshot을 한 번 trigger한다.
  - session을 complete로 표시한다.

검증:

- 다음 test를 추가한다:
  - scheduler single-flight behavior
  - active file switch 이후 stale result ignored
  - candidate confirm/delete persistence
  - stable candidate id behavior
  - LLM provider failure preserving previous snapshot
- 가능한 build/test를 실행하고 정확한 명령과 결과를 `실행 로그`에 기록한다.
- `/Users/ethan/Documents/Recordings`의 live file로 테스트하는 짧은 manual verification note를 포함한다.

## Phase 3: polish + local 운영

상태: `Done`

목표:
v1 product scope를 넓히지 않으면서 사용성, 안정성, local developer ergonomics를 개선한다.

요구사항:

- 긴 transcript를 가진 실제 회의에서도 읽기 좋은 layout density와 readability를 개선한다.
- settings를 추가한다:
  - selected Recordings folder
  - LLM provider
  - analysis cadence between 30 and 60 seconds
  - LLM provider timeout
- 명확한 status indicator를 추가한다:
  - watching folder
  - active file
  - transcript updated time
  - analysis running/stale/failed
  - meeting completed
- non-destructive reset control을 추가한다:
  - forget selected folder
  - clear current meeting analysis state
- README 문서를 추가한다:
  - setup
  - default Codex provider login
  - LLM provider selection
  - how to run
  - how to test with `/Users/ethan/Documents/Recordings`
  - known limitations
- export, search archive, microphone recording, STT, team sync, external integration은 추가하지 않는다.

검증:

- 가능한 build/test를 실행한다.
- app startup, folder selection, live transcript update, analysis refresh, failure indicator를 수동 검증한다.

## Backlog

Backlog는 `Not Started` 항목을 위에 두고, 완료된 항목은 아래 `Done archive`에 짧게 보관한다. 구현 세부와 검증 이력은 `execution-log.md`를 우선 확인한다.

### Next

- Product / Team Context Roadmap:
  - 상태: `Not Started`
  - 우선순위: 기존 Backlog `Next` 항목보다 높게 둔다. 단, 실제 배포 중 crash/hotfix가 발생하면 Release notes crash hardening 같은 안정화 작업은 예외적으로 먼저 처리할 수 있다.
  - 정렬 기준:
    - 먼저 Meeting Intelligence output contract와 evidence model을 안정화한다.
    - 그 다음 개인 사용자의 회의 품질, 후속 정리, local workflow를 만든다.
    - 그 다음 calendar/docs/team shared artifact 같은 외부 context를 붙인다.
    - Slack/Jira/Calendar write integration은 distribution이므로 artifact 신뢰도와 공유 안전성이 검증된 뒤 붙인다.
  - D0 Meeting Intelligence contract:
    - 1. Meeting Type Preset:
      - 의존성: evidence-backed wrap-up, readiness check, decision coach의 output shape를 결정하므로 먼저 정의한다.
      - 구현 방향: `Decision`, `Planning`, `Incident`, `1:1`, `Brainstorm`, `Status` preset을 두고, 초기에는 자동 추정 + 수동 override를 검토한다.
      - 검증 질문: preset 선택이 부담을 늘리지 않으면서 같은 transcript의 output relevance를 높이는가?
    - 2. Evidence-backed Wrap-up:
      - 의존성: share readiness, action ledger, open question carry-over, team memory, Slack preview의 기반이다.
      - 구현 방향:
        - `currentIssue` UI label은 `현재 이슈`보다 `현재 논점` 또는 `Live Focus`에 가깝게 재정의한다.
        - `AnalysisSnapshot`에 회의 전체를 설명하는 `meetingSummary` 또는 `wrapUpSummary` 필드를 추가할지 검토한다.
        - `회의 요약`, `결정`, `액션`, `열린 질문`에 근거 timestamp/source line을 붙인다.
        - meeting end/final analysis에서는 전체 회의 wrap-up summary를 생성하는 별도 pass 또는 final contract를 검토한다.
      - 검증 질문: transcript 원문을 열지 않아도 각 summary/follow-up의 근거를 판단할 수 있는가?
    - 3. Live Bookmark:
      - 의존성: evidence timestamp model이 있어야 final wrap-up과 decision coach에 안정적으로 반영할 수 있다.
      - 구현 방향: 현재 transcript timestamp를 bookmark로 저장하는 버튼/단축키를 추가하고 optional label 또는 quick tag를 붙인다.
      - 검증 질문: 사용자가 회의 중 부담 없이 bookmark를 찍고, bookmark 주변 발화가 summary 품질을 개선하는가?
  - D1 Personal meeting workflow:
    - 4. Decision Coach / Unstick:
      - 의존성: meeting type, current focus/topic shift, evidence model이 필요하다.
      - 구현 방향:
        - 자동 interrupt가 아니라 opt-in 또는 조용한 suggestion panel로 시작한다.
        - 반복 발화, 결정 후보 부재, owner 부재, 판단 기준 부재, 문제/해결책 혼재, scope 섞임을 감지한다.
        - 출력은 일반 요약이 아니라 `막힌 지점`, `결정해야 할 최소 단위`, `선택지`, `부족한 정보`, `다음 질문` 형태의 decision card로 만든다.
        - 회의 종료 후에는 readiness check와 연결해 `결정되지 않은 최소 단위`를 열린 질문으로 남긴다.
      - 검증 질문: coach가 회의 흐름을 방해하지 않고 실제로 논의를 좁히는가?
    - 5. Share Readiness Check:
      - 의존성: evidence-backed wrap-up, candidate/confirmed state, decision coach의 unresolved decision card를 사용한다.
      - 구현 방향:
        - 담당자 없는 action, 기한 없는 follow-up, 근거 약한 decision, candidate/confirmed 혼동, 비어 있는 summary를 warning으로 표시한다.
        - warning은 전송을 막기보다 수정/confirm을 유도하는 non-blocking checklist로 시작한다.
      - 검증 질문: readiness warning이 실제로 사람이 공유 전에 수정할 만한 문제를 잡아내는가?
    - 6. Action Ledger:
      - 의존성: confirmed action items와 evidence timestamp가 필요하다.
      - 구현 방향: confirmed actions를 Application Support 상태에서 모아 담당자, 기한, source meeting, evidence timestamp, status 기준으로 보여준다.
      - 검증 질문: 사용자가 회의별 화면을 열지 않고도 본인/팀 action을 훑을 수 있는가?
    - 7. Open Question Carry-over:
      - 의존성: wrap-up의 열린 질문과 unresolved decision card가 필요하다.
      - 구현 방향: 새 회의가 같은 room/participant/topic/search match와 연결되면 carry-over 후보를 보여주고 dismiss/resolve할 수 있게 한다.
      - 검증 질문: 관련 없는 질문을 다시 띄워 noise를 만들지 않으면서 다음 회의 준비를 돕는가?
  - D2 Context identity and input enrichment:
    - 8. Calendar-linked Meeting Identity:
      - 의존성: recurring meeting memory와 context broker의 entry point다. local-only path와 병립해야 한다.
      - 구현 방향:
        - 현재 시간, transcript header time, invited attendees, organizer, event title을 이용해 calendar event 후보를 매칭한다.
        - event title, organizer, attendees, start/end time, recurrence ID, description의 agenda를 낮은 우선순위 context hint로 주입한다.
        - transcript와 calendar context가 충돌하면 transcript를 우선한다.
      - 검증 질문: calendar event 매칭이 meeting title/participants/current purpose 품질을 실제로 개선하는가?
    - 9. Agenda / Context Attach:
      - 의존성: Context Broker가 여러 source를 주입하려면 먼저 회의별 supplemental context payload와 우선순위 규칙이 필요하다.
      - 구현 방향:
        - `.md`, `.txt` 등 텍스트 문서를 회의별 supplemental context로 붙인다.
        - 각 context에는 source file name, excerpt, token/character cap, 사용 목적을 포함한다.
        - prompt는 supplemental context를 transcript보다 낮은 우선순위의 보조 근거로만 사용하게 한다.
      - 검증 질문: supplemental context가 결정/action 품질을 높이면서 prompt 비용과 latency를 통제하는가?
    - 10. Recurring Meeting Memory:
      - 의존성: Calendar-linked Meeting Identity와 Open Question Carry-over가 필요하다.
      - 구현 방향:
        - recurrence ID 또는 calendar event relation으로 meeting series를 식별한다.
        - 이전 회차의 공유/로컬 wrap-up artifact에서 열린 질문, 결정, unresolved actions를 current meeting pre-context로 제안한다.
        - 사용자가 이번 회의에 가져올 항목을 accept/dismiss할 수 있게 한다.
      - 검증 질문: 반복 회의에서 같은 미결 논점이 사라지지 않고 이어지는가?
    - 11. Context Broker:
      - 의존성: Calendar-linked Meeting Identity와 Agenda / Context Attach payload가 필요하다.
      - 구현 방향:
        - Calendar event description의 Google Docs/Slides/Jira/Slack 링크를 context 후보로 보여준다.
        - 자동 fetch는 capability/permission이 확인된 connector에만 제한하고, 기본은 user confirmation을 둔다.
        - prompt에는 source name, excerpt, freshness, confidence를 함께 넣는다.
        - context source가 transcript와 충돌하면 transcript와 confirmed artifact를 우선한다.
      - 검증 질문: Calendar 자체보다 linked docs/previous wrap-up이 Meeting Intelligence 품질을 더 높이는가?
    - 11a. Direct Google Calendar API OAuth:
      - 상태: `Done`
      - 목표: 회사 소유 Google OAuth app과 사용자별 동의를 통해 Google Calendar event를 직접 읽고, 현재 회의와 겹치는 calendar context를 `CalendarContextState`에 저장한다. Workspace admin allow는 현재 release blocker가 아니라 restrictive Workspace 정책에서 필요한 운영 fallback으로 둔다.
      - 제품 원칙:
        - 사용자가 각자 Google Cloud Console을 열어 Calendar API를 enable하지 않게 한다.
        - 회사/앱 배포자가 Google Cloud project, OAuth consent, Desktop OAuth client를 관리한다.
        - 현재 Workspace에서는 사용자 동의만으로 POC가 성공했으므로 v1 기본 경로는 user consent OAuth다.
        - Workspace 정책이 강화되어 `admin_policy_enforced` 또는 equivalent 403이 발생할 때만 Workspace app access approval을 운영 절차로 요구한다.
        - v1은 full calendar sync가 아니라 현재 회의 시간대 on-demand fetch다.
        - raw transcript는 Google로 보내지 않는다. Google API에는 calendar id와 time window만 보낸다.
        - Calendar context는 transcript보다 낮은 우선순위의 보조 근거로만 prompt에 들어간다.
        - Test Run은 live Google API를 다시 호출하지 않고 저장된 calendar context snapshot을 재사용한다.
      - 아키텍처:
        - Google Calendar 연동은 Apps Script/GAS 없이 native OAuth + Calendar REST API로 구현한다.
        - OAuth는 외부 브라우저 + PKCE + loopback redirect flow를 사용한다.
        - refresh token은 macOS Keychain에 저장하고 access token은 memory 또는 짧은 만료 cache에만 둔다.
        - provider abstraction은 `CalendarContextProvider` 형태로 두어, 기존 Calendar MCP fetcher와 future EventKit fallback을 같은 output model에 맞출 수 있게 한다.
        - UI는 `Google Calendar 연결`, `연결 해제`, `Calendar context 가져오기`, `다시 로그인` 상태를 분리한다.
      - 관리자/운영 준비:
        - Google Cloud project는 회사 소유로 만든다.
        - Google Calendar API를 enable한다.
        - OAuth consent screen은 회사 내부 앱이면 `Internal`로 둔다.
        - OAuth client type은 `Desktop app`으로 만든다.
        - 기본 배포는 Workspace Admin allow 없이 사용자 동의 OAuth로 진행한다.
        - 배포 smoke에서 `admin_policy_enforced`, `access_denied`, Calendar scope block, 403 app access block이 확인되면 Workspace Admin API controls에서 Meeting Rescue OAuth client를 trusted/allowed로 승인한다.
        - v1 scope는 최소 권한인 `https://www.googleapis.com/auth/calendar.events.readonly`로 시작한다.
        - calendar list metadata가 실제로 필요해질 때만 `calendar.readonly` 또는 calendar list 관련 scope 확장을 별도 product/security decision으로 다룬다.
      - OAuth client 배포 결정 후보:
        - Desktop/installed app은 client secret을 비밀로 유지할 수 없으므로 `client_secret_*.json` 파일 자체를 repo나 release artifact의 보안 경계로 취급하지 않는다.
        - `2026-06-08` 검증 결과 현재 Desktop OAuth client는 refresh token grant에서 `client_secret is missing`을 반환하므로, v1 app flow는 optional `clientSecret` 설정을 지원해야 한다.
        - 앱 번들에는 v1에서 필요한 `clientID`, optional `clientSecret`, redirect host/prefix, scope allowlist를 포함하는 `GoogleCalendarOAuthConfig.json` 형태를 둔다.
        - 실제 `clientSecret` 값은 git tracked source에 넣지 않고 `private/` 또는 release-only local config에서 bundle resource로 주입한다.
        - `clientSecret`은 token 보호 수단으로 보지 않고, 실제 보호는 사용자 동의, PKCE state 검증, refresh token Keychain 저장, 필요 시 Workspace admin allowed app으로 한다.
        - 사내 배포에서는 release artifact 안에 config를 포함해 사용자가 별도 JSON 파일을 고르지 않게 한다. 이 artifact 안의 client secret은 public-client identifier 수준으로 취급하고, 노출 시 client rotation으로 대응한다.
        - 개발/POC에서는 `--credentials` 또는 local override path를 허용하되, 다운로드된 client secret JSON은 `.gitignore`/문서로 repo 반입 금지한다.
        - client id rotation이 필요해질 경우 앱 업데이트로 config를 교체하고, 기존 refresh token은 invalid_grant/admin block 상태에서 재로그인을 요구한다.
      - 구현 계획:
        - GC0 OAuth/API spike:
          - 상태: `Done`
          - Create: `docs/superpowers/plans/YYYY-MM-DD-google-calendar-api-oauth.md`
          - Create: `scripts/google_calendar_oauth_poc.py`
          - 목적: 회사 OAuth client로 브라우저 OAuth를 열고 `primary` calendar의 `events.list`를 호출할 수 있는지 확인한다.
          - POC request:
            ```http
            GET https://www.googleapis.com/calendar/v3/calendars/primary/events?singleEvents=true&orderBy=startTime&maxResults=10&timeMin=2026-06-08T10:45:00%2B09:00&timeMax=2026-06-08T12:30:00%2B09:00
            Authorization: Bearer ACCESS_TOKEN
            ```
          - 성공 기준: event가 0개여도 Google Calendar API가 실제로 호출되고 schema-valid JSON이 내려오면 PASS.
          - 결과: `2026-06-08` 실제 브라우저 OAuth 동의 후 `primary` calendar `events.list` 호출 PASS. Workspace admin allow 없이 사용자 동의만으로 `google-calendar-api` context JSON event 1개 수신.
        - GC1 OAuth models and PKCE:
          - 상태: `Done`
          - Create: `Sources/MeetingRescueCore/GoogleCalendarOAuthModels.swift`
          - Create: `Tests/MeetingRescueCoreTests/GoogleCalendarOAuthModelsTests.swift`
          - 구현 대상:
            - `GoogleCalendarOAuthConfiguration(clientID:redirectURI:scopes:)`
            - `PKCEChallenge(verifier:challenge:)`
            - authorization URL builder
            - token response decoder
          - 테스트:
            - authorization URL에 `response_type=code`, `client_id`, `redirect_uri`, `scope`, `code_challenge`, `code_challenge_method=S256`, `access_type=offline`이 들어간다.
            - token response에서 `access_token`, `refresh_token`, `expires_in`을 decode한다.
          - 결과: Swift Core model/PKCE/authorization URL/token response 테스트 PASS.
        - GC2 Keychain token store:
          - 상태: `Done`
          - Create: `Sources/MeetingRescue/GoogleCalendarIntegration.swift`
          - Create: `Tests/MeetingRescueCoreTests/GoogleCalendarTokenStateTests.swift`
          - 구현 대상:
            - refresh token 저장/로드/삭제.
            - access token expiry 계산.
            - token revoked 또는 missing 상태 분리.
          - 보안 원칙:
            - refresh token은 Keychain에만 저장한다.
            - logs, attempt logs, settings JSON에 token을 남기지 않는다.
          - 결과:
            - Core token state/expiry model 추가 완료.
            - refresh token 없는 access-token refresh response는 기존 refresh token을 유지하도록 테스트 완료.
            - app target `GoogleCalendarKeychainTokenStore`로 refresh token 저장/로드/삭제 구현 완료.
        - GC3 OAuth service:
          - 상태: `Done`
          - Create: `Sources/MeetingRescue/GoogleCalendarIntegration.swift`
          - Modify: `Sources/MeetingRescue/AppViewModel.swift`
          - 구현 대상:
            - loopback redirect local listener.
            - default browser authorization open.
            - authorization code exchange.
            - refresh token grant.
            - 사용자 취소, admin block, network failure, token revoked 상태를 명시적으로 반환.
          - UI copy:
            - `Google Calendar 연결됨`
            - `Google Calendar 다시 로그인 필요`
            - `관리자 승인 또는 앱 접근 권한이 필요합니다`
            - `Google Calendar 연결 해제`
          - 결과:
            - app target `GoogleCalendarService`로 loopback redirect, browser open, authorization code exchange, refresh grant 구현 완료.
            - failure state는 user denied/admin policy/missing client secret/invalid grant/network/state mismatch로 분리.
            - `2026-06-08` smoke 중 확인된 `localhost:0` redirect 문제를 수정했다. `NWListener`가 ready 상태에서 nonzero ephemeral port를 배정받은 뒤 redirect URI를 만들도록 회귀 테스트를 추가했다.
            - loopback callback은 HTTP request header가 완성된 뒤 authorization code를 파싱한다. `NWConnection.receive(minimumIncompleteLength: 1)`의 partial read로 code가 잘릴 수 있는 경로를 회귀 테스트로 막았다.
        - GC4 Calendar API client:
          - 상태: `Done`
          - Create: `Sources/MeetingRescueCore/GoogleCalendarAPIModels.swift`
          - Create: `Sources/MeetingRescue/GoogleCalendarIntegration.swift`
          - Create: `Tests/MeetingRescueCoreTests/GoogleCalendarAPIModelsTests.swift`
          - 구현 대상:
            - `events.list` request builder.
            - `GoogleCalendarEvent` fixture decode.
            - all-day event, timed event, recurring event, organizer/attendees/location/description fields 처리.
            - HTTP 401은 refresh 후 1회 retry, HTTP 403은 permission/admin issue로 분리.
          - v1 request defaults:
            - `calendarId=primary`
            - `singleEvents=true`
            - `orderBy=startTime`
            - `maxResults=10`
            - `timeMin=currentMeetingStart - 15m`
            - `timeMax=currentMeetingEnd + 30m` 또는 live unknown이면 `now + 3h`
          - 결과:
            - Core `events.list` request URL builder 추가 완료.
            - RFC3339 offset의 `+09:00`가 raw query에서 `+`로 남아 Google API 400을 만들 수 있어, query를 strict percent-encoding(`%2B`)하도록 회귀 테스트와 수정을 추가했다.
            - Google Calendar timed/all-day/recurring event decode model 추가 완료.
            - app target HTTP client, 401 refresh retry, 403 permission/admin issue 분리 구현 완료.
        - GC5 Calendar context mapping:
          - 상태: `Done`
          - Create: `Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift`
          - Create: `Tests/MeetingRescueCoreTests/GoogleCalendarContextMapperTests.swift`
          - Modify: `Sources/MeetingRescueCore/CalendarContextModels.swift`
          - 구현 대상:
            - Google event를 `CalendarEventCandidate`로 변환.
            - description은 1200 chars cap.
            - attendees는 email 또는 display name을 저장하되 empty/null tolerant.
            - `recurringEventId` 또는 event recurring relation을 `recurrenceID`로 보존.
            - overlap, room/location exact match, participant overlap, title/topic token overlap으로 confidence 계산.
          - mapping example:
            ```json
            {
              "id": "google:event-id",
              "title": "Weekly Product Sync",
              "startDateText": "2026-06-08T11:00:00+09:00",
              "endDateText": "2026-06-08T12:00:00+09:00",
              "organizer": "owner@example.com",
              "attendees": ["owner@example.com", "teammate@example.com"],
              "descriptionExcerpt": "Agenda excerpt capped to 1200 chars",
              "recurrenceID": "series-id",
              "confidence": 0.86
            }
            ```
          - 결과:
            - Google event를 `CalendarEventCandidate`, `SupplementalContextSource`, `MeetingIdentity`로 변환 완료.
            - high-confidence event는 자동 accepted 처리해 유저 tick 없이 workflow/prompt context에 반영한다.
        - GC6 App wiring and UI:
          - 상태: `Done`
          - Modify: `Sources/MeetingRescue/AppViewModel.swift`
          - Modify: `Sources/MeetingRescue/ContentView.swift`
          - Modify: `Sources/MeetingRescueCore/AnalysisModels.swift`
          - 구현 대상:
            - Settings에 `Google Calendar` connection card 추가.
            - Meeting Intelligence context lane에 `Google Calendar 가져오기` 버튼 추가.
            - Calendar MCP 실패 상태와 Google Calendar API 연결 상태를 별도 row로 보여준다.
            - accepted event는 기존 meeting identity/supplemental source flow를 재사용한다.
            - 연결이 없거나 fetch가 실패해도 analysis는 optional context 없음으로 계속 진행한다.
          - 결과:
            - Settings > Analysis에 Google Calendar 연결/가져오기/해제 card 추가.
            - Calendar MCP fetch path와 Google Calendar API status message를 분리.
            - Google Calendar API UX/data path 검증 후 Context tab을 다시 노출.
        - GC7 Persistence and Test Run replay:
          - 상태: `Done`
          - Modify: `Sources/MeetingRescue/AppViewModel.swift`
          - Modify: `Sources/MeetingRescueCore/CalendarContextModels.swift`
          - Test: `Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift`
          - 구현 대상:
            - API로 가져온 calendar context를 기존 `analysisState.calendarContext`에 저장한다.
            - Test Run 시작 시 `cachedForTestRunReplay()`로 저장 snapshot을 재사용한다.
            - cached replay 상태 메시지는 `저장된 Google Calendar context를 Test Run에 적용했습니다.`로 구분한다.
          - 결과:
            - API fetch 결과를 `analysisState.calendarContext`에 저장하고 기존 `ApplicationStateStore` 저장 경로를 재사용.
            - Test Run replay 문구를 Google Calendar context 기준으로 갱신.
            - `2026-06-08` app-target smoke에서 Google Calendar event 7건 fetch, persisted candidates 7건, cached replay `cachedReplay`, disconnect 후 Keychain token 제거를 확인.
        - GC8 Context tab re-enable gate:
          - 상태: `Done`
          - Modify: `Sources/MeetingRescueCore/MeetingIntelligenceFeatureGate.swift`
          - Test: `Tests/MeetingRescueCoreTests/MeetingIntelligenceFeatureGateTests.swift`
          - 구현 대상:
            - 현재 숨겨둔 `컨텍스트` 탭은 Google Calendar API fetch가 실제로 연결/검증된 뒤 다시 노출한다.
            - 노출 전에는 Settings 연결 UX와 hidden context data path만 먼저 구현한다.
          - 결과:
            - `release visible intelligence lanes include context tab` 테스트로 현재 릴리즈에서 컨텍스트 탭이 노출되는 상태를 확인.
            - `AppViewModelTestRunContextTests`로 저장된 Google Calendar context가 Test Run 시작 시 `cachedReplay`로 복원되고 supplemental context가 유지되는 것을 확인.
        - GC9 Later incremental sync:
          - 상태: 후속 scope.
          - full sync나 background sync는 v1에서 하지 않는다.
          - 필요해지면 Google Calendar incremental sync token을 사용한다.
          - push notification은 HTTPS webhook receiver가 필요하므로 local-first v1 범위에서 제외한다.
      - 검증 계획:
        - Unit:
          - OAuth URL/PKCE/token response decode.
          - Keychain token state without real secret values.
          - `events.list` request shape.
          - Google event fixture decode.
          - event-to-context mapping and confidence scoring.
          - Test Run snapshot replay.
        - Integration:
          - 회사 Google 계정으로 OAuth connect.
          - 현재 시간 ±2h `primary` calendar fetch.
          - event 0개도 API success면 PASS.
          - fixture event가 있는 시간대를 지정해 title/start/end/location/attendees/description excerpt가 내려오는지 확인.
          - refresh token으로 앱 재시작 후 재조회.
          - Google 계정에서 app access revoke 후 `다시 로그인 필요` 상태 확인.
          - Workspace admin blocked 상태에서 `관리자 승인 필요` 상태 확인.
        - App flow:
          - fresh install에서 Google Calendar 연결.
          - Live/Test Run에서 `Google Calendar 가져오기`.
          - accepted calendar event가 meeting identity와 prompt supplemental context에 반영.
          - Test Run 재실행 시 live API 없이 저장 snapshot 사용.
      - 리스크:
        - Desktop app OAuth client id는 앱에 포함되므로 secret처럼 취급할 수 없다. PKCE와 redirect validation이 필수다.
        - refresh token을 저장하므로 Keychain 처리와 disconnect UX가 중요하다.
        - scope 확장은 관리자의 재승인/사용자 재동의가 필요할 수 있다.
        - Calendar description에는 민감 정보가 있을 수 있으므로 excerpt cap과 dismiss/preview가 필요하다.
        - Google Calendar push notification은 webhook backend가 필요해 local-first와 충돌한다.
      - 공식 참고:
        - Google Calendar API auth/scopes: https://developers.google.com/workspace/calendar/api/auth
        - OAuth for installed/desktop apps: https://developers.google.com/identity/protocols/oauth2/native-app
        - Calendar `events.list`: https://developers.google.com/calendar/api/v3/reference/events/list
        - Calendar incremental sync: https://developers.google.com/workspace/calendar/api/guides/sync
        - Calendar push notifications: https://developers.google.com/workspace/calendar/api/guides/push
        - Workspace app access control: https://support.google.com/a/answer/7281227
      - 완료 기준:
        - 사용자는 Google Cloud Console을 직접 열지 않고 Meeting Rescue에서 Google Calendar를 연결한다.
        - refresh token은 Keychain에 저장되고 disconnect 시 제거된다.
        - 현재 회의와 겹치는 calendar event 후보를 가져와 `CalendarContextState`에 저장한다.
        - Google Calendar MCP가 없어도 Test Run은 저장된 Google Calendar context snapshot으로 재현된다.
        - 컨텍스트 탭을 다시 노출할 때 Calendar MCP 실패 상태와 Google Calendar API 성공 상태가 명확히 구분된다.
      - `2026-06-08` 최종 검증:
        - `swift test`: 통과. 170 tests / 33 suites.
        - `python3 -m unittest Tests/google_calendar_oauth_poc_tests.py`: 통과. 4 tests.
        - `swift run MeetingRescue --google-calendar-smoke ... --connect --reset-before-connect --disconnect-after`: 통과. OAuth connect, Calendar fetch 7 events, persisted candidates 7, cached replay `cachedReplay`, disconnect verified.
        - `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/Users/ethan/Downloads/client_secret_...json scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` build 완료 및 bundle config resource 존재 확인.
        - secret/token leak check: 통과. tracked diff와 untracked repo files에서 OAuth client secret/access token/refresh token 값 미검출.
    - 11b. Google Calendar quality validation hardening:
      - 상태: `Done`
      - 목표: D3/team feature로 넘어가기 전에 Google Calendar context가 실제 Meeting Intelligence 품질을 올리는지 판단 가능한 deterministic guard와 sanitized validation report를 만든다.
      - 제품 원칙:
        - Calendar context는 transcript보다 낮은 우선순위의 보조 근거다.
        - exact room/time match와 recurrence ID는 meeting identity 품질을 높이는 신호로 사용한다.
        - 관련 없는 calendar event는 candidate/prompt를 오염시키지 않는다.
        - Calendar description link는 자동 주입 근거가 아니라 사용자가 확인할 supplemental candidate로만 둔다.
        - Test Run은 live Google API나 Calendar MCP를 호출하지 않고 저장 snapshot만 replay한다.
      - 구현/검증 항목:
        - Mapper 품질 guard:
          - exact room/time match가 participant-only overlap보다 우선한다.
          - `Zigbang(2F)`와 `Zigbang(2F)_Meeting Room L3`는 다른 room으로 처리한다.
          - useful overlap이 없는 event는 후보에서 제외한다.
          - description link는 `.linkedSourceCandidate`, `isAccepted == false`로 변환한다.
        - Prompt 품질 guard:
          - supplemental context는 transcript보다 낮은 우선순위임을 유지한다.
          - calendar metadata가 transcript-derived `meetingMetadata`를 덮어쓰지 않도록 prompt에 명시한다.
          - unaccepted calendar linked source candidate는 prompt에 주입하지 않는다.
        - Test Run replay guard:
          - saved Google Calendar context는 `cachedReplay`로 복원된다.
          - accepted/dismissed event candidate state와 supplemental sources가 replay에서 유지된다.
          - Test Run 시작 경로는 live Google Calendar API/Calendar MCP fetch를 호출하지 않는다.
        - UI guard:
          - Context panel은 Google Calendar API controls를 노출한다.
          - Context panel은 Google Calendar MCP controls/copy를 노출하지 않는다.
        - 문서:
          - `docs/calendar-quality-validation.md`에 sanitized validation matrix와 product readout을 남긴다.
      - 완료 전 검증:
        - `swift test --scratch-path .build-test`: 통과. 181 tests / 35 suites.
        - `python3 -m unittest Tests/google_calendar_oauth_poc_tests.py`: 통과. 4 tests.
        - `git diff --check`: 통과.
        - `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/Users/ethan/Downloads/client_secret_...json scripts/build_app.sh`: 통과. `dist/Meeting Rescue.app` build 완료 및 bundle config resource 존재 확인.
        - `"dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue" --google-calendar-smoke --allow-empty-events`: 통과. 저장된 OAuth token으로 Calendar events 7건 fetch, persisted candidates 7건, cached replay `cachedReplay`.
        - secret/token leak check: 통과. tracked file list와 diff에서 OAuth client JSON, access token, refresh token, 실제 client secret 값 미검출.
      - `2026-06-09` Calendar quality A/B readout:
        - 상태: `Done`
        - 실행:
          - `swift run MeetingRescue --calendar-quality-ab --samples 3 --timeout 300 --output /tmp/meeting-rescue-calendar-ab-report.json`: usable saved Calendar context 2 samples.
          - `MEETING_RESCUE_GOOGLE_CALENDAR_OAUTH_CONFIG=private/GoogleCalendarOAuthConfig.json swift run MeetingRescue --calendar-quality-ab --samples 1 --timeout 600 --exclude-sample-ids ... --output /tmp/meeting-rescue-calendar-ab-report-extra.json`: fetched Calendar context 1 additional sample.
        - 결과:
          - 총 3 samples에서 with-calendar 평균 delta는 key point `+0.33`, evidence ref `+1.67`, topic `0`, decision `-1.0`, confirmed decision `-0.67`, action `-0.67`.
          - Calendar metadata는 회의 제목/성격 프레이밍에는 일부 도움을 줬지만, summary/decision/action 추출 품질을 일관되게 높인다는 근거는 부족했다.
          - Calendar context는 평균 input token을 약 `+293` 늘렸다.
        - 제품 결정:
          - 유지: Calendar context는 meeting identity, recurring carry-over, 관련 회의 연결, 회의 프레이밍 보조에 사용한다.
          - 축소: Calendar context를 summary/decision/action 품질 향상의 핵심 근거로 포지셔닝하지 않는다.
          - 가드: Calendar metadata는 계속 낮은 우선순위 supplemental context로만 주입하고, transcript와 충돌하면 transcript를 우선한다. 결정/action 후보는 calendar만 보고 만들지 않는다.
        - 구현 결정:
          - `--calendar-quality-ab` CLI runner를 dev-only 검증 경로로 유지한다.
          - A/B runner는 batch 검증 안정성을 위해 Codex app-server가 아니라 one-shot Codex CLI exec를 사용한다.
          - A/B runner report는 기본적으로 sanitized metrics/usage만 저장하고, full snapshot/raw output은 `--include-raw-output`를 명시한 경우에만 포함한다.
  - D2.5 Local Glossary Suggestions:
    - 상태: `Done`
    - 목표: 로컬 meeting history에서 STT가 자주 틀리는 회사/팀 용어 후보를 묶어 제안하고, 사용자가 승인한 개인 glossary를 분석/search/carry-over용 low-priority hint로 사용한다.
    - 제품 원칙:
      - raw transcript는 source of truth이며 수정하지 않는다.
      - glossary는 v1에서 개인/local state다. Google Sheet, backend, team sync, 제안/승인 workflow는 포함하지 않는다.
      - accepted term만 prompt supplemental context와 search index에 반영한다.
      - glossary hint는 transcript보다 낮은 우선순위이며, glossary만 보고 결정/action 후보를 만들지 않는다.
      - 사용자는 빈 사전을 직접 채우기보다 history 기반 후보를 보고 승인한다.
    - 구현 요약:
      - `LocalGlossaryState`를 Application Support의 `local-glossary.json`에 저장한다.
      - history scan은 `jax`, `jecks`, `zacks` 같은 Latin/mixed token 변형을 묶어 suggestion으로 만든다.
      - accepted glossary term은 `domainGlossary` supplemental context로 prompt에 들어가며 calendar metadata보다 높은 priority, user-attached context보다 낮은 priority를 갖는다.
      - accepted glossary term은 meeting history search section과 SQLite search index signature에 반영한다.
      - dismissed suggestion은 다시 노출하지 않는다.
      - Settings > Glossary에서 local glossary 사용 여부, 후보 생성, suggestion accept/dismiss, accepted term delete를 제공한다.
    - 검증:
      - `swift test --filter LocalGlossaryModelsTests`: 통과.
      - `swift test --filter LocalGlossaryMatcherTests`: 통과.
      - `swift test --filter LocalGlossarySuggestionEngineTests`: 통과.
      - `swift test --filter AnalysisPromptBuilderTests`: 통과.
      - `swift test --filter MeetingHistorySearchTests`: 통과.
      - `swift test --filter AppViewModelTestRunContextTests`: 통과.
      - `swift test --filter ContentViewContextWiringTests`: 통과.
    - 남은 관찰:
      - 실제 transcript history에서 suggestion precision을 확인해야 한다.
      - canonical term을 suggestion row에서 직접 수정하는 UI는 v1 이후 사용성 개선으로 남긴다.
  - D3 Team shared memory:
    - 12. Team Memory Folder:
      - 의존성: evidence-backed wrap-up과 share readiness가 필요하다. calendar identity가 있으면 metadata 품질이 좋아지지만 필수는 아니다.
      - 구현 방향:
        - raw transcript를 공유하지 않고, 명시적으로 공유한 `회의 요약`, confirmed decisions, confirmed actions, 열린 질문, source meeting metadata만 JSON/Markdown sidecar로 저장한다.
        - 공유 위치는 회사 Google Drive/shared folder 같은 user-controlled location으로 시작하고, 별도 서버는 두지 않는다.
        - 다른 사용자의 앱은 공유 artifact만 읽어 local/team search index에 반영한다.
        - 민감 회의, 1:1, private transcript는 기본 비공유로 둔다.
      - 검증 질문: raw transcript 없이도 팀이 유용한 decision/action/open-question memory를 얻는가?
    - 13. Team Insight:
      - 의존성: Team Memory Folder, Action Ledger, Open Question Carry-over가 필요하다.
      - 구현 방향:
        - 특정 사람의 생산성 지표가 아니라, 주제/결정/action 중심의 operational insight만 제공한다.
        - `Repeated unresolved topics`, `Conflicting decisions`, `Stale actions`, `Frequent context sources` 같은 team-level view를 검토한다.
        - 모든 insight는 source meeting과 evidence를 붙인다.
      - 검증 질문: team insight가 개인 감시로 해석되지 않으면서 의사결정 품질을 높이는가?
  - D4 Distribution:
    - 14. Slack 공유 preview:
      - 의존성: evidence-backed wrap-up, share readiness, optional team memory sidecar format이 필요하다.
      - 구현 방향:
        - generic Markdown exporter를 그대로 쓰지 않고 Slack 전용 `mrkdwn` formatter를 둔다.
        - `Markdown` 근처에 `Slack` 또는 `공유` 액션을 추가하고, 전송 전 preview modal/sheet를 보여준다.
        - MVP는 preview + clipboard copy를 우선 검토하고, Incoming Webhook 전송은 설정/credential 저장 방식이 정리된 뒤 붙인다.
        - webhook URL 같은 secret은 plain config가 아니라 macOS Keychain 저장을 우선 검토한다.
        - OAuth/channel picker/thread reply는 후속 scope로 둔다.
      - 검증 질문: Slack을 붙이기 전 preview/copy만으로도 사용자가 팀 공유 가치를 느끼는가?
  - 명시적으로 뒤로 미룬 항목:
    - Jira/Calendar 직접 쓰기.
    - Slack OAuth 기반 workspace/channel browser.
    - Multi-meeting Q&A 또는 NotebookLM-style thread.
    - microphone recording/STT.

- Release notes crash hardening:
  - 상태: `Not Started`
  - 아이디어: 유저가 "릴리즈 노트"를 누르면 앱이 종료된다는 리포트가 있었으므로, 릴리즈 노트 sheet의 bundled/current/latest 로드 경로를 crash-safe하게 만든다.
  - 검토 포인트:
    - SwiftPM `Bundle.module` resource accessor는 packaged app에서 resource bundle 위치를 못 찾으면 `fatalError`를 낼 수 있으므로, 앱 번들 내부 실제 `Contents/Resources/MeetingRescue_MeetingRescue.bundle/Resources/ReleaseNotes.md` 경로를 우선 확인한다.
    - `SUFeedURL` 기반 latest URL이 raw GitHub feed인지 GitHub Pages feed인지에 따라 `releases/latest.md` 위치가 달라질 수 있으므로, 실패 시 현재 버전 릴리즈 노트 fallback이 안전하게 렌더링되는지 확인한다.
    - Settings sheet 안에서 다시 ReleaseNotes sheet를 띄우는 nested sheet 경로가 macOS/SwiftUI 버전에 따라 불안정하지 않은지 확인한다.
  - 검증 아이디어:
    - packaged `.app`에서 Release notes 버튼을 눌러 current/latest/fallback 상태를 수동 확인한다.
    - resource bundle을 일부러 누락한 빌드 또는 fixture로 앱이 crash 대신 fallback 문구를 보여주는지 확인한다.

- Meeting Intelligence supplemental context:
  - 상태: `Not Started`
  - 아이디어: transcript만으로 부족한 회의 맥락을 보강하기 위해 사용자가 Markdown/text 문서와 이미지 기반 맥락을 Meeting Intelligence 입력에 추가할 수 있는지 검토한다.
  - v1 Markdown/text:
    - `.md`, `.txt` 등 텍스트 문서를 읽어 `AnalysisRequest`의 supplemental context로 구조화해 prompt payload에 넣는다.
    - 각 context에는 source file name, excerpt, token/character cap, 사용 목적을 포함하고, transcript보다 낮은 우선순위의 보조 근거로만 쓰게 prompt 규칙을 둔다.
    - live analysis latency를 키우지 않도록 수동 첨부 또는 회의별 opt-in으로 시작한다.
  - v1 Image-as-text:
    - 이미지 원본 멀티모달 입력이 아니라 OCR 또는 사용자가 입력한 caption/description을 텍스트 supplemental context로 붙이는 방식을 먼저 검토한다.
    - 스크린샷/화이트보드/슬라이드 이미지는 결정, 액션, 용어 정의 보강에는 유용하지만, OCR 품질과 token cap 때문에 요약 근거 우선순위를 낮춘다.
  - 후속 멀티모달:
    - provider가 image input을 안정적으로 지원하는지 확인한 뒤, Codex app-server 또는 별도 OpenAI API provider에서 원본 이미지 첨부를 실험한다.
    - 현재 provider 경로는 대부분 stdin text prompt이므로, provider별 capability flag와 fallback text extraction 경로가 필요하다.
  - 검증 아이디어:
    - 같은 transcript에 supplemental Markdown을 붙였을 때 결정/action 후보 품질이 개선되는지 golden transcript fixture로 비교한다.
    - 큰 문서/이미지가 들어와도 prompt token cap, timeout, attempt log 표시가 과도하게 커지지 않는지 확인한다.

- Meeting Q&A:
  - 상태: `Not Started`
  - 목표: live meeting intelligence와 별도로 선택한 회의록에 대해 사용자가 질문하고 LLM 응답을 받는 화면을 만든다.
  - v1 Single Meeting Q&A:
    - source는 현재 선택한 meeting 1개로 제한한다.
    - 사용자가 선택한 LLM provider와 model preset을 재사용한다.
    - streaming은 optional이다. Codex도 `codex exec` 기반 non-streaming Q&A provider로 먼저 지원할 수 있다.
    - context는 전체 transcript를 매번 무조건 보내지 않고 SQLite FTS5 segment + topic/decision/action snapshot으로 relevant chunk를 고른다.
    - 응답에는 `[mm:ss]` citation chip을 붙여 raw transcript anchor로 이동할 수 있게 한다.
    - 질문/답변 history, prompt/context/output/duration/token estimate는 live analysis attempt log와 분리된 `qaAttemptLogs`에 저장한다.
  - v2 Multi-Meeting Source Q&A:
    - 여러 meeting을 source로 선택할 수 있게 한다.
    - 답변 citation은 meeting title/file + `[mm:ss]`를 함께 표시한다.
    - source coverage를 UI에 표시해 어떤 회의들이 답변 근거로 쓰였는지 확인할 수 있게 한다.
  - v3 NotebookLM-style Q&A Threads:
    - `New Thread`를 만들 수 있게 하고 thread별 source meeting set, provider, model preset, messages를 저장한다.
    - thread 이름 자동 생성, thread 목록/삭제/검색을 제공한다.
    - Codex app-server streaming/persistent meeting thread는 optional prototype 이후 검토한다.

### Provider / Infrastructure

- Live analysis latency/cost hardening:
  - 상태: `Done`
  - 목표: Codex App Server/CLI 공통 live analysis의 prompt/output 크기와 stale running 상태 꼬임을 줄인다.
  - 구현 범위:
    - prompt payload를 compact JSON으로 줄이고, previous snapshot/recent context/retrieval chunk 한도를 낮춘다.
    - previous snapshot 이후 `livePatch` 요청은 full snapshot fallback 없이 patch-only decode를 강제한다.
    - diagnostics는 기본 off를 유지하고, opt-in 시에도 raw payload 대신 event type/phase/text length 요약만 남긴다.
    - Test Run/History/Live 전환 중 active analysis cancel 시 running attempt를 skipped로 닫고, 늦게 도착한 provider result가 UI 상태를 되돌리지 않게 한다.
  - 검증:
    - prompt compacting과 patch-only decode focused test를 추가한다.
    - `swift test`를 통과시킨다.

- Codex app-server diagnostics option:
  - 상태: `Done`
  - 목표: app-server experimental mode에서 first delta latency 지연 원인을 더 잘 구분할 수 있도록 opt-in diagnostics를 제공한다.
  - 구현 범위:
    - Settings에서 Codex App Server experimental일 때만 diagnostics toggle을 노출한다.
    - diagnostics on이면 `thread/start.experimentalRawEvents`를 opt-in한다.
    - run trace에는 server notification method timing과 item type/phase 요약만 기록하고 raw payload는 저장하지 않는다.
  - 검증:
    - diagnostics option이 thread/start raw events opt-in으로 전달되는지 focused test로 검증한다.
    - `swift test`를 통과시킨다.

- Codex app-server long-lived service:
  - 상태: `Done`
  - 목표: Codex app-server experimental mode가 analysis마다 process/thread를 새로 만들지 않고, 앱 실행 중 long-lived app-server process와 meeting별 reusable thread를 사용하게 한다.
  - 요구사항:
    - `Codex App Server experimental` mode에서 provider singleton/service가 app-server process를 유지한다.
    - 동일 meeting session에서는 가능한 한 같은 thread를 재사용한다.
    - process exit, timeout, protocol error, turn failure가 발생하면 service state를 reset하고 CLI exec fallback 또는 기존 failure path로 안전하게 복구한다.
    - run trace에 process spawn/reuse, initialize/reuse, thread create/reuse, turn/start latency, first delta latency, final answer latency, total provider latency, fallback 여부/이유를 구분해 기록한다.
    - Analysis 실행 상세 UI에서 app-server process/thread reuse와 first delta latency를 확인할 수 있게 한다.
    - 기존 CLI exec mode는 그대로 유지하고 기본값도 바꾸지 않는다.
    - app-server mode는 계속 experimental 옵션으로 둔다.
  - 검증:
    - service가 두 번의 analysis에서 process/thread를 재사용하는지 focused test로 검증한다.
    - timeout/protocol failure 시 service reset 또는 fallback이 동작하는지 검증한다.
    - `swift test`를 통과시킨다.

- Codex app-server provider prototype:
  - 상태: `Done`
  - 목표: optional provider로 `codex app-server` stdio child process를 유지하고 JSON-RPC로 schema-bound analysis를 실행할 수 있는지 구현 검증한다.
  - 후보 flow: spawn → `initialize` → meeting별 short-lived ephemeral thread → `turn/start(input, outputSchema)` → streaming/completed JSON 수집 → timeout 시 `turn/interrupt`.
  - 전제: 앱 전용 minimal `CODEX_HOME`과 auth 공유/로그인 안내를 분리한다.
  - 리스크: experimental protocol, context 오염, token 증가, process recovery.
  - 이번 구현 범위:
    - Q&A는 제외한다.
    - Codex provider 전용 `execution mode` 설정(`CLI exec`, `App Server experimental`)을 추가한다.
    - app-server protocol spike에서 `thread/start`, `turn/start`, `outputSchema`, `item/agentMessage/delta`가 동작함을 확인했다.
    - app-server mode가 실패하거나 지원되지 않으면 `CLI exec`로 fallback하고 attempt trace에 남긴다.
    - 주의: app-server mode는 아직 process persistence 최적화가 아니며, spike에서 작은 요청도 기본 context/token 사용량이 크게 잡히는 정황이 있었다. 기본값은 계속 `CLI exec`이다.

- Persistent HTTP/API provider:
  - 상태: `Not Started`
  - 목표: CLI process 대신 provider API를 직접 호출하는 adapter를 추가한다.
  - OpenAI 후보: Responses API structured output + streaming. 앱이 compact state를 소유하고 API에는 `newTranscriptChunk + compactState` 또는 patch schema만 보낸다.
  - 공통 계약: `AnalysisRequest -> AnalysisProviderResult`, Keychain/env 기반 secret 관리, prompt/output/usage logging, timeout/cancel 유지.

- History FTS5 live retrieval:
  - 상태: `Not Started`
  - 목표: live analysis에서 active meeting 전용 memory index를 넘어, 사용자가 명시한 과거 회의 또는 관련 history chunk를 prompt context로 넣을지 검토한다.
  - 이번 scope 제외 사유:
    - live 중 history search DB 의존이 UI blocking과 indexing 상태 혼선을 다시 만들 수 있다.
    - 현재 회의 분석에 과거 회의 chunk가 섞이면 LLM이 현재 회의에서 말하지 않은 내용을 현재 이슈처럼 오염시킬 수 있다.
    - NotebookLM-style multi-meeting Q&A와 책임 경계가 겹치므로 별도 product decision이 필요하다.
  - 후속 검토 조건:
    - Live Analysis Context Pipeline v2의 memory live index가 안정화된다.
    - Q&A source selection UX가 정리된다.
    - attempt log에서 history retrieval source/citation을 명확히 구분할 수 있다.

### Integrations / Distribution

- Slack/Jira/Calendar integration:
  - 상태: `Not Started`
  - 목표: confirmed decision/action item을 외부 업무 시스템으로 내보내거나 연결한다.
  - 범위는 provider 안정화와 local history/Q&A가 충분히 쓸만해진 뒤 다시 쪼갠다.

- Release versioning:
  - 상태: `Done`
  - 목표: 배포 산출물의 버전/빌드 번호를 source of truth로 관리한다.
  - 요구사항:
    - `VERSION` 또는 동등한 단일 source에서 `CFBundleShortVersionString`을 주입한다.
    - `CFBundleVersion`은 release build에서 명시적으로 주입하거나 git commit count/tag 기반으로 계산한다.
    - bundle id는 배포용 stable id로 고정하되, local/debug override가 가능해야 한다.
    - signing/notary 관련 local 설정은 gitignored `config/release.local.env`에 두고, repo에는 `config/release.env.example`만 둔다.
    - app bundle, dmg, release note 파일명은 같은 version/build 값을 사용한다.

- Release packaging command:
  - 상태: `Done`
  - 목표: CI 없이 로컬에서 GitHub Release에 올릴 수 있는 app archive를 만든다.
  - 요구사항:
    - `scripts/build_app.sh`가 version/build/bundle id/sign identity override를 받을 수 있게 한다.
    - `scripts/package_release.sh` 또는 동등한 command로 `dist/Meeting-Rescue-vX.Y.Z.dmg`을 생성한다.
    - DMG에는 app bundle과 `/Applications` symlink를 포함한다.
    - 산출물 checksum과 release note 초안을 함께 생성한다.

- Developer ID signing + notarization:
  - 상태: `Done`
  - 목표: 로컬 ad-hoc signed app이 아니라 Gatekeeper 경고 없이 배포 가능한 Developer ID signed/notarized app을 만든다.
  - 요구사항:
    - Developer ID Application certificate로 app bundle을 signing한다.
    - Hardened Runtime(`codesign --options runtime`)과 secure timestamp를 사용한다.
    - notarization 제출 전/후 `codesign --verify --deep --strict`와 `spctl` 검증을 실행한다.
    - `xcrun notarytool submit --wait`로 notarization을 제출하고, 성공 후 `xcrun stapler staple`로 ticket을 app에 staple한다.
    - 실패 시 `xcrun notarytool log`로 developer log를 받아 원인 확인 command를 문서화한다.
    - Apple ID/app-specific password 또는 App Store Connect API key 기반 notary credential은 Keychain profile로 저장하고 repo에 secret을 남기지 않는다.

- GitHub Release publish command:
  - 상태: `Done`
  - 목표: notarized DMG를 수동 command로 GitHub Release에 업로드하고 Sparkle appcast를 갱신한다.
  - 요구사항:
    - `gh release create` 기반 publish script를 추가한다.
    - 자동 업데이트 feed에서 접근 가능해야 하므로 기본은 published release로 생성한다. 필요하면 `RELEASE_DRAFT=1`로 override한다.
    - tag, title, release note, notarized DMG, checksum을 같은 version 값으로 묶는다.
    - 업로드 대상은 notarization/stapling 검증이 끝난 최종 DMG로 제한한다.
    - release asset 서명을 Sparkle appcast에 반영한다.

- Manual update check:
  - 상태: `Superseded`
  - 목표: Sparkle auto-update로 대체한다. GitHub Release 페이지 안내만 하는 manual updater는 구현하지 않는다.
  - 요구사항:
    - Settings/Menu의 `업데이트 확인`은 Sparkle update check를 호출한다.
    - GitHub latest release metadata 직접 조회는 별도 요구가 생기기 전까지 보류한다.

- Sparkle auto-update:
  - 상태: `Done`
  - 목표: Sparkle 기반 자동 업데이트를 GitHub Release asset + GitHub Pages appcast로 검증한다.
  - 요구사항:
    - Sparkle framework를 app bundle에 포함하고 `SUFeedURL`, `SUPublicEDKey`, signed feed 설정을 주입한다.
    - Sparkle private key는 Keychain에 저장하고, export backup은 gitignored `private/`에 둔다.
    - GitHub Pages `/docs/appcast.xml`을 update feed로 사용한다.
    - notarized archive를 GitHub Release asset으로 올리고 appcast enclosure에 EdDSA signature/length를 기록한다.
    - 이전 Sparkle-enabled build에서 새 release로 실제 update install/relaunch가 되는지 검증한다.

### Done Archive

- App-server event timing diagnostics: `Done`
  - Codex app-server protocol의 server notification method를 확인했고, `turn/started`, `item/started`, `item/reasoning/*`, `rawResponseItem/completed`, `thread/tokenUsage/updated` 같은 event timing 후보가 있음을 확인했다.
  - app-server turn trace에 method별 첫 등장 시점과 count를 `app-server event: ...` 형태로 기록하게 했다.
  - raw payload는 저장하지 않고 method name/count/timing만 저장해 로그 비대화와 민감 정보 노출을 줄였다.
- Live Analysis Context Pipeline v2: `Done`
  - `docs/adr/0001-live-analysis-context-pipeline-v2.md`의 결정에 따라 Codex CLI production path는 stateless patch worker로 유지하고, app-owned context/state 구조를 명시했다.
  - `LiveTranscriptIndex`와 `AnalysisContextPlanner`를 추가해 live/test run 중 active meeting 전용 memory retrieval top 0~3개를 prompt context에 넣을 수 있게 했다.
  - 기존 방식과 병립하도록 Settings에 `Live context retrieval` 옵션(`Off`, `Memory live index`)을 추가했다.
  - attempt log에 `contextPlan`을 저장하고 상세 화면에서 participants pruning, retrieval mode/topK/latency/score/time range, estimated prompt tokens를 확인할 수 있게 했다.
  - previous snapshot이 있으면 manual/final/automatic 모두 patch output을 기본으로 사용하게 했다. full snapshot은 첫 분석 또는 명시적인 repair/full-refresh reason에만 허용한다.
  - 상단 status chip에 다음 automatic analysis 조건을 표시한다.
  - Test Run도 같은 context planner/live memory index 경로를 사용하며, trigger wait 계산은 transcript 경과 시간 기준을 유지한다.
- Adaptive collapsible panes: `Done`
  - 창 가로 폭이 줄어들 때 Meetings와 Meeting Intelligence pane을 자동으로 접고, rail 버튼으로 다시 펼칠 수 있게 했다.
  - 사용자가 직접 Meetings/Intelligence pane을 접을 수 있는 pane header 버튼을 추가했다.
  - 좁은 폭에서 status chip row가 레이아웃을 밀지 않도록 horizontal scroll 처리를 추가했다.
- Compact raw-primary layout: `Done`
  - 작은 창에서는 Raw Transcript를 기본 화면으로 두고 Meetings/Meeting Intelligence를 상단 토글 drawer로 열 수 있게 했다.
  - 창 폭이 더 줄어들 때 Meeting Intelligence도 접히도록 breakpoint를 조정했다.
  - 상단 action button은 `ViewThatFits` 기반으로 full/compact/icon 상태를 전환하고, overflow 작업은 더보기 menu로 이동했다.
  - status chip row는 full/medium/compact 밀도로 전환해 좁은 화면에서 usage/update/lines 같은 낮은 우선순위 chip을 숨긴다.
- Onboarding layer: `Done`
  - 첫 실행 또는 설정 미완료 상태에서 recordings folder, LLM provider, 기본 UI 구조를 안내하는 onboarding sheet를 추가했다.
  - Soma recordings folder 자동 감지는 `/Users/ethan/Library/Preferences/com.somadevelopmentco.soma.plist`의 `CustomChatLogDirectory`만 읽고, 값이 없거나 유효하지 않으면 fallback 없이 없는 것으로 판단한다.
  - 감지된 경로는 onboarding에서 제안하고, 사용자가 macOS folder picker로 확인해야 security-scoped bookmark를 저장한다.
  - Codex/Claude Code 실행 경로를 확인해 둘 다 없으면 automatic Meeting Intelligence를 disabled로 시작한다. 기존 저장 provider 선택은 덮어쓰지 않는다.
  - Settings에서 onboarding을 다시 열 수 있게 했다.
- Automatic Meeting Intelligence toggle: `Done`
  - Settings에서 자동 live/test-run analysis와 회의 종료 final analysis를 on/off할 수 있게 했다.
- Analysis trigger strategy를 transcript-progress 기반으로 전환: `Done`
  - 45초 고정 cadence를 새 발화/새 글자 수/max wait 기반 hybrid trigger로 바꾸고, low-value batch는 skipped attempt로 기록하게 했다.
- Analysis trigger preset 추가: `Done`
  - non-L17 30개 회의 샘플 검토 결과를 반영해 기본값을 `Balanced(180/300/24줄/1800자)`로 올리고, Settings에 `Responsive`, `Balanced`, `Economy` preset을 추가했다.
- Test Run trigger preset 정렬: `Done`
  - Test Run의 compressed 8초 trigger가 preset 의도와 다르게 작은 batch를 과도하게 호출하는 문제를 수정한다.
  - Test Run도 선택한 preset threshold를 사용하되, wait 계산은 wall-clock이 아니라 transcript 경과 시간 기준으로 수행한다.
- Final analysis patch/continuation 우선 적용: `Done`
  - final analysis도 previous snapshot이 있으면 full snapshot 대신 patch/continuation을 우선 사용하게 했다.
  - final chunk 성공분은 즉시 UI/state에 반영하고, 남은 chunk가 있으면 running 상태를 유지한다.
  - final retry를 chunk range 단위로 분리해 continuation 실패 로그가 `final-continue-retry-N`으로 드러나게 했다.
- Live topic breakdown 개선: `Done`
  - topic split prompt와 최근 흐름 표시를 개선했다.
- Restart catch-up chunking: `Done`
  - automatic analysis가 큰 미분석 backlog를 bounded chunk로 처리하게 했다.
- Test Run UX 정리: `Done`
  - Test Run 진입점을 Meetings 영역과 row action으로 정리했다.
- Manual/final analysis chunk continuation: `Done`
  - manual/final 분석도 bounded chunk continuation으로 timeout 위험을 낮췄다.
- Search quality 후속: `Done`
  - `NaturalLanguage`, compact normalization, fuzzy/ngram scoring, anchor 분리를 적용했다.
- SQLite FTS5 meeting search index: `Done`
  - Application Support SQLite FTS5 index와 progress UI를 추가했다.
- Meeting history initial load performance: `Done`
  - 초기 list build와 raw transcript search indexing을 분리했다.
- Live analysis latency/quality 개선: `Done`
  - live automatic을 patch schema 기반으로 전환했다.
- Initial live analysis gating: `Done`
  - 초기 1분 gate, automatic patch mode, reload 시 final auto-run 방지를 적용했다.
- Analysis attempt diagnostics 보강: `Done`
  - attempt batch stats, duration, 상세 raw prompt/output, provider run trace, accordion log UI를 추가했다.
- Analysis 실행 상세 main thread blocking 해소: `Done`
  - 큰 prompt/output 렌더링을 AppKit `NSTextView` 기반으로 바꿨다.
- Codex CLI PATH resolution: `Done`
  - GUI app 환경의 `codex` PATH fallback을 추가했다.
- LLM provider process/session reuse 검토: `Done`
  - `codex exec resume`은 schema-bound live latency 개선책으로 부적합하다고 판단했다.
- Codex minimal exec profile 적용: `Done`
  - one-shot `codex exec`에 minimal flags를 적용했다.
- Codex server protocol spike: `Done`
  - `codex app-server` JSON-RPC/schema/streaming 가능성과 리스크를 확인했다.
- Subscription-based LLM provider 확장: `Done`
  - Claude Code provider를 추가했고 `structured_output` wrapper를 기존 provider 계약에 연결했다.
- Live search index rebuild 억제: `Done`
  - live transcript append 중 active file 변경만으로 검색 DB 확인/재색인이 반복되지 않게 했다.
- Search quality v2: `Done`
  - SQLite FTS5 keyword score와 local semantic vector score를 hybrid ranking으로 섞는다.
  - semantic vector는 Application Support 검색 DB에 chunk 단위로 캐시하고, schema v2 metadata로 기존 DB를 재색인한다.
  - 검색 결과 계산은 utility priority detached task에서 수행하고 cancellation check/generation guard로 stale result를 폐기해 UI thread blocking을 줄였다.
  - provider는 `local-semantic-v2`라 네트워크/API 비용은 0이며, search diagnostics metadata에 provider/cost/latency를 기록한다.

## 실행 로그

실행 로그는 [`execution-log.md`](execution-log.md)에서 관리한다. 새 로그는 해당 파일의 맨 위에 추가한다.
