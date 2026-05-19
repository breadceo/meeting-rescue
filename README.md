# Meeting Rescue

Meeting Rescue는 로컬 transcript 폴더를 감시하면서 회의 원문, 검색, LLM 기반 Meeting Intelligence를 함께 보여주는 native SwiftUI macOS 앱입니다.

이 앱은 마이크 녹음기나 STT 엔진이 아닙니다. Soma 같은 별도 도구가 생성한 `.txt` 회의록을 읽고, 사용자가 선택한 로컬 LLM CLI provider를 통해 요약, 흐름, 결정 후보, 액션 후보를 갱신하는 transcript consumer입니다.

## 주요 기능

- 선택한 폴더의 `.txt` 회의록 감시
- 최신 transcript 자동 추적
- raw transcript 실시간 tail
- 과거 회의록 목록과 검색
- SQLite FTS5 기반 로컬 검색 index
- live 회의 중 검색 DB rebuild 지연
- Test Run replay
- timestamp 기반 replay와 배속 조절
- LLM 기반 Meeting Intelligence
- current issue, topic timeline, decision/action 후보 표시
- decision/action 후보 confirm, delete, inline edit, 원문 복원
- Meeting Intelligence markdown export
- LLM usage/token/cost estimate
- analysis attempt diagnostics
- Soma recordings folder onboarding
- Codex, Claude Code, Custom Command provider 선택

## 요구사항

- macOS 14 이상
- Swift 6 toolchain
- Xcode 또는 Command Line Tools
- transcript `.txt` 파일이 저장되는 로컬 폴더
- 선택 사항:
  - Codex CLI
  - Claude Code CLI

SwiftPM package는 macOS native executable target으로 구성되어 있습니다.

```sh
swift --version
swift test
```

## 빠른 시작

```sh
git clone https://github.com/breadceo/meeting-rescue.git
cd meeting-rescue
./scripts/build_app.sh
open "dist/Meeting Rescue.app"
```

첫 실행 시 onboarding에서 다음을 확인합니다.

1. transcript 폴더
2. LLM provider
3. 기본 UI 구조

선택한 transcript 폴더 권한은 macOS security-scoped bookmark로 저장됩니다.

## 실행 방법

개발 중 SwiftPM으로 바로 실행할 수 있습니다.

```sh
swift run MeetingRescue
```

앱 번들을 만들려면 다음 스크립트를 사용합니다.

```sh
./scripts/build_app.sh
open "dist/Meeting Rescue.app"
```

`build_app.sh`는 release build를 만든 뒤 `dist/Meeting Rescue.app`을 생성하고, SwiftPM resource bundle과 앱 아이콘을 함께 복사합니다. `config/release.local.env`에 signing identity가 있으면 Developer ID signing을 사용하고, 없으면 로컬 개발용 ad-hoc signing을 사용합니다.

## 배포 빌드

release 설정은 git에 올리지 않는 `config/release.local.env`에 둡니다. 시작점으로 예제 파일을 복사하세요.

```sh
cp config/release.env.example config/release.local.env
```

로컬 release archive를 만들려면:

```sh
./scripts/package_release.sh
```

생성물:

- `dist/Meeting-Rescue-vX.Y.Z.zip`
- `dist/Meeting-Rescue-vX.Y.Z.zip.sha256`
- `dist/release-notes-vX.Y.Z.md`

Developer ID notarization까지 수행하려면 `config/release.local.env`에 `SIGN_IDENTITY`와 `NOTARY_KEYCHAIN_PROFILE`을 설정한 뒤:

```sh
./scripts/notarize_app.sh
```

notarization이 성공하면 최종 배포용 archive가 생성됩니다.

- `dist/Meeting-Rescue-vX.Y.Z-notarized.zip`
- `dist/Meeting-Rescue-vX.Y.Z-notarized.zip.sha256`

## Transcript 폴더

Meeting Rescue는 사용자가 선택한 폴더의 `.txt` 파일을 읽습니다. 파일명은 자유롭지만, 현재 앱은 아래 형태의 transcript를 가장 잘 지원합니다.

```txt
회의실 이름
2026-05-19 09:45:34
참석자 A, 참석자 B
############################################################

[00:00][SYSTEM] 대화 기록 시작됨
[00:05] Speaker A: 오늘 회의 시작하겠습니다.
[00:12] Jane Doe: 네, 먼저 지표부터 보겠습니다.
```

지원하는 주요 parse 항목은 다음과 같습니다.

- room
- date/time
- participants
- timestamped dialogue lines
- meeting end marker

지원하는 종료 marker:

```txt
[SYSTEM] 대화 기록 종료
[SYSTEM] Chat Logs has been ended
```

## Soma 폴더 자동 감지

onboarding은 Soma 설정에서 recordings folder를 자동 제안할 수 있습니다.

현재 자동 감지는 다음 한 곳만 읽습니다.

```txt
~/Library/Preferences/com.somadevelopmentco.soma.plist
```

사용하는 key:

```txt
CustomChatLogDirectory
```

`CustomChatLogDirectory` 값이 없거나 유효한 디렉터리가 아니면 자동 감지는 실패한 것으로 봅니다. 다른 bundle id, dev plist, container plist, hardcoded fallback은 사용하지 않습니다.

감지된 폴더도 앱이 바로 사용하지 않습니다. 사용자가 folder picker에서 확인해야 security-scoped bookmark가 저장됩니다.

## 화면 구성

앱은 세 개의 주요 영역으로 구성됩니다.

- `Meetings`: live meeting, Test Run, meeting history, search/filter
- `Raw Transcript`: 선택한 transcript 원문과 timestamp anchor
- `Meeting Intelligence`: 요약, 흐름, 후보, usage, attempt diagnostics

상단 버튼:

- `분석`: 현재 transcript를 수동 분석
- `Markdown`: Meeting Intelligence markdown export
- `일시정지/재개`: Test Run replay 제어
- `Live`: 최신 live transcript로 복귀
- `설정`: provider, preset, timeout, 자동 분석 설정
- `폴더`: transcript source folder 변경

## LLM Providers

Meeting Rescue는 provider를 앱 설정에서 선택합니다.

지원 provider:

- `Codex`
- `Claude Code`
- `Custom Command`

기본 provider는 Codex입니다. Codex provider는 OpenAI API key를 직접 사용하지 않고, 로컬에 로그인된 Codex CLI를 실행합니다.

Codex provider의 기본 실행 형태:

```sh
codex exec \
  --model <preset-model> \
  --skip-git-repo-check \
  --ephemeral \
  --sandbox read-only \
  --output-schema <schema-file> \
  -
```

`CLI default` preset은 `--model`을 생략합니다.

## Model Preset

model preset은 provider 공통 의미를 갖습니다.

| Preset | 의미 | Codex model |
| --- | --- | --- |
| CLI default | provider 기본 model 사용 | `--model` 생략 |
| Economy | 반복적인 회의 요약과 후보 추출용 | `gpt-5.4-mini` |
| Balanced | 흐름/결정 후보 품질과 비용 균형 | `gpt-5.4` |
| Frontier | 최종 정리나 난도 높은 회의용 | `gpt-5.5` |

Claude Code provider는 preset을 Claude Code CLI의 model/effort 설정으로 변환합니다. Custom Command provider에는 preset 정보를 환경변수로 전달합니다.

```txt
MEETING_RESCUE_LLM_MODEL_PRESET
MEETING_RESCUE_LLM_MODEL
```

provider별 secret이나 token은 앱 code에 hardcode하지 않습니다.

## Meeting Intelligence 동작 방식

Meeting Rescue는 live transcript를 계속 읽으면서 별도 scheduler로 LLM analysis를 실행합니다.

요약 흐름:

1. transcript tail 또는 Test Run replay가 raw transcript를 갱신합니다.
2. 자동 trigger 조건을 만족하거나 사용자가 `분석`을 누르면 `AnalysisRequest`를 만듭니다.
3. request에는 meeting metadata, transcript chunk, previous compact snapshot, confirmed/deleted candidate ids가 포함됩니다.
4. scheduler는 meeting별 single-flight로 provider를 실행합니다.
5. 성공하면 latest analysis snapshot을 저장하고 UI를 갱신합니다.
6. 실패하면 이전 successful snapshot을 유지하고 attempt log에 기록합니다.
7. transcript end marker가 감지되면 final analysis를 시도하고 meeting을 complete 상태로 표시합니다.

자동 분석은 고정 45초 polling이 아니라 hybrid trigger를 사용합니다.

- 새 발화 수
- 새 transcript 글자 수
- 최소 대기 시간
- 최대 대기 시간
- 초기 1분 gate

trigger preset:

- `Responsive`
- `Balanced`
- `Economy`

## Search

Meeting history search는 SQLite FTS5 index를 사용합니다.

검색 대상:

- title
- file name
- room
- date/time
- participants
- current issue
- topic timeline
- decision/action candidates
- risks/notes
- raw transcript segments

live meeting 중에는 현재 쓰이는 live transcript가 계속 수정되므로 검색 DB rebuild를 미룹니다. meeting end marker가 감지되거나 live가 아닌 과거 회의를 탐색할 때 검색 DB 갱신이 재개됩니다.

검색 결과에 timestamp가 있으면 raw transcript의 해당 line으로 이동하고 강조합니다.

## Test Run

Test Run은 과거 transcript 파일을 선택해 시간순으로 replay하는 기능입니다.

- raw transcript가 한 번에 뜨지 않고 timestamp 순서대로 누적됩니다.
- `[12:10]` 다음 줄이 `[12:13]`이면 `1x`에서 약 3초 뒤 표시됩니다.
- `2x`, `4x`, `8x` 배속을 지원합니다.
- Test Run 중에도 Meeting Intelligence를 확인할 수 있습니다.

## Markdown Export

현재 Meeting Intelligence를 markdown 파일로 저장할 수 있습니다.

포함 내용:

- meeting metadata
- current issue
- topic timeline
- confirmed/candidate decisions
- confirmed/candidate action items
- risks/notes
- usage estimate
- analysis attempt summary

## 저장 위치

앱 상태는 사용자 로컬 Application Support 아래에 저장됩니다.

```txt
~/Library/Application Support/MeetingRescue
```

저장되는 데이터:

- selected folder bookmark
- settings
- meeting session metadata
- per-meeting analysis state
- confirmed/deleted candidate ids
- inline edits
- analysis attempt logs
- SQLite search index

transcript 원본 파일은 사용자가 선택한 source folder에 그대로 남습니다.

## 개인정보와 보안

Meeting Rescue는 transcript와 analysis state를 로컬에 저장합니다.

다만 LLM provider를 실행하면 prompt에 포함된 transcript chunk가 선택한 provider CLI로 전달됩니다. Codex/Claude Code CLI가 실제로 어떤 원격 서비스를 호출하는지는 해당 CLI의 로그인 상태와 provider 정책을 따릅니다.

GitHub에 올릴 때 포함하지 말아야 할 것:

- 실제 회의록 `.txt`
- `~/Library/Application Support/MeetingRescue` 아래 session/search DB
- provider token
- 개인 설정 파일

repo에는 앱 source, schema, tests, build script만 포함하는 것을 권장합니다.

## macOS 권한 팝업

notarized 배포 앱은 Gatekeeper의 “미확인 개발자” 경고 없이 열 수 있습니다.

다만 transcript 폴더가 `Documents`, `Desktop`, `Downloads` 같은 macOS 보호 영역 아래에 있으면 파일 접근 권한 확인이 한 번 뜰 수 있습니다. 이 권한은 앱이 사용자가 선택한 transcript 폴더를 읽기 위한 macOS privacy 동작입니다.

권장 사용법:

- folder picker로 다시 선택해 bookmark 저장
- 같은 앱 번들을 계속 사용
- transcript 폴더를 보호 영역 밖으로 둘지 검토

## 개발 명령

테스트:

```sh
swift test
```

debug build:

```sh
swift build
```

앱 번들 생성:

```sh
./scripts/build_app.sh
```

diff whitespace 검사:

```sh
git diff --check
```

## 프로젝트 구조

```txt
Sources/
  MeetingRescue/
    AppViewModel.swift
    ContentView.swift
    MeetingRescueApp.swift
    MeetingSearchDatabase.swift
    Resources/
      analysis-output.schema.json
      analysis-patch-output.schema.json
  MeetingRescueCore/
    AnalysisModels.swift
    AnalysisPromptBuilder.swift
    AnalysisScheduler.swift
    LLMProvider.swift
    TranscriptParser.swift
    MeetingHistorySearch.swift
    MeetingTimestampFormatter.swift
Tests/
  MeetingRescueCoreTests/
scripts/
  build_app.sh
  package_release.sh
  notarize_app.sh
```

## 알려진 제한

- macOS native 앱만 지원합니다.
- 현재 transcript `.txt` format에 맞춰져 있습니다.
- microphone recording과 STT는 포함하지 않습니다.
- Slack/Jira/Calendar 연동은 아직 없습니다.
- semantic embedding 기반 검색은 아직 없습니다.
- Codex app-server provider는 prototype backlog입니다.
- NotebookLM-style Q&A는 아직 구현되지 않았습니다.

## Roadmap

가까운 backlog:

- Single Meeting Q&A
- Multi-Meeting Source Q&A
- NotebookLM-style Q&A Threads
- Search quality v2
- Codex app-server provider prototype
- GitHub Release publish command
- manual update check
