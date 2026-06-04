# D2 Google Calendar MCP Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Google Calendar MCP를 필수 입력 경로로 사용해 meeting identity, agenda/context attach, recurring memory, context broker preview를 구현한다.

**Architecture:** 앱은 EventKit을 쓰지 않고 Codex/Claude Code CLI가 연결한 Google Calendar MCP를 통해 calendar event 후보를 가져온다. Core에는 calendar event 후보, meeting identity, supplemental context source, context priority 모델을 추가하고, prompt에는 transcript보다 낮은 우선순위의 보조 context로만 주입한다. UI는 MCP 연결 상태, calendar 후보, attached context, recurring carry-over 후보를 보여주며 모든 linked-doc fetch는 D2에서 후보 표시와 사용자 확인까지만 제공한다.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Codable, JSON Schema, Codex CLI MCP, Claude Code MCP, Google Calendar MCP.

---

## Scope

이 계획은 `tasks.md`의 `D2 Context identity and input enrichment`를 구현한다.

Included:
- Calendar-linked Meeting Identity
- Agenda / Context Attach
- Recurring Meeting Memory
- Context Broker preview
- Codex와 Claude Code 양쪽의 Google Calendar MCP preflight
- 실제 Google Calendar MCP fetch smoke test script

Excluded:
- EventKit/macOS Calendar runtime path
- Google Docs/Slides/Jira/Slack linked content 자동 fetch
- Slack 공유 preview
- Team shared memory folder
- Calendar/Jira/Slack write operation

## Product Decisions

- Google Calendar MCP 연결은 필수다. MCP 연결이 없으면 D2 calendar/context 기능은 disabled/fail-fast 상태가 된다.
- Codex와 Claude Code 양쪽 모두 Google Calendar MCP preflight와 실제 fetch smoke test를 제공한다.
- 현재 로컬 확인 기준: `claude mcp list`에는 `claude.ai Google Calendar`가 connected이고, `codex mcp list`에는 `google-calendar`가 없다. D2 실행자는 Codex MCP 등록과 login을 먼저 완료해야 한다.
- Calendar event 자체는 MCP로 가져온다. Calendar description 안의 Google Docs/Slides/Jira/Slack 링크는 D2에서 source candidate로만 보여주고 자동 fetch하지 않는다.
- Context 우선순위는 `transcript > confirmed local artifacts > user-attached context > calendar metadata > linked-doc candidates`로 고정한다.
- Transcript와 calendar context가 충돌하면 transcript를 우선한다.
- `.md`, `.txt` attach는 source file bookmark/path, capped excerpt, source metadata만 저장한다. 전체 파일 내용은 analysis state에 저장하지 않는다.
- Recurring memory는 calendar recurrence ID를 series key로 우선 사용하고, 없으면 room/title/participants fingerprint fallback을 사용한다. 이전 회차의 unresolved context는 사용자가 accept한 뒤 prompt에 주입한다.

## File Structure

- Create `Sources/MeetingRescueCore/CalendarContextModels.swift`: MCP status, calendar event candidate, meeting identity, supplemental context source, recurring source models.
- Create `Sources/MeetingRescueCore/CalendarMCPContextFetcher.swift`: Codex/Claude provider command builder, prompt builder, response decoder, MCP preflight contract.
- Create `Sources/MeetingRescueCore/SupplementalContextReader.swift`: `.md`/`.txt` attach file excerpt reader with character cap and metadata.
- Modify `Sources/MeetingRescueCore/AnalysisModels.swift`: `MeetingAnalysisState`와 `AnalysisRequest`에 identity/context fields를 추가한다.
- Modify `Sources/MeetingRescueCore/LLMProvider.swift`: existing `ProcessRunner`를 Core 내부에서 재사용할 수 있도록 `private`에서 internal scope로 연다.
- Modify `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`: supplemental context payload와 conflict priority instruction을 prompt에 넣는다.
- Create `Sources/MeetingRescue/Resources/calendar-mcp-context-output.schema.json`: calendar MCP fetch output schema.
- Create `scripts/verify_calendar_mcp_context.sh`: Codex/Claude 양쪽 Google Calendar MCP real fetch smoke test.
- Create `scripts/calendar_mcp_smoke.schema.json`: script용 small JSON schema.
- Modify `Sources/MeetingRescue/AppViewModel.swift`: MCP preflight/fetch state, calendar candidate accept/dismiss, attach file, recurring carry-over accept/dismiss, request wiring.
- Modify `Sources/MeetingRescue/ContentView.swift`: `컨텍스트` intelligence tab 또는 workflow sub-section, calendar MCP status, event candidates, attached context, recurring memory UI.
- Create `Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift`: state decode/persistence, priority ordering, series key, attach cap tests.
- Create `Tests/MeetingRescueCoreTests/CalendarMCPContextFetcherTests.swift`: provider argument shape, MCP prompt, output decode, schema fixture tests.
- Modify `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`: supplemental context prompt priority and conflict instruction tests.
- Modify `Tests/MeetingRescueCoreTests/LLMProviderConfigurationTests.swift`: Codex/Claude calendar MCP mode arguments.

---

### Task 1: Google Calendar MCP Preflight And Smoke Script

**Files:**
- Create: `scripts/calendar_mcp_smoke.schema.json`
- Create: `scripts/verify_calendar_mcp_context.sh`
- Test: manual integration script after D2 implementation

- [ ] **Step 1: Register Codex Google Calendar MCP when missing**

Run:

```bash
codex mcp get google-calendar
```

Expected before registration on this machine: FAIL with `No MCP server named 'google-calendar' found.`

Register and authenticate:

```bash
codex mcp add google-calendar --url https://calendarmcp.googleapis.com/mcp/v1
codex mcp login google-calendar
codex mcp get google-calendar
```

Expected after registration: `google-calendar` exists and is enabled/authenticated.

- [ ] **Step 2: Verify Claude Google Calendar MCP**

Run:

```bash
claude mcp list
```

Expected: output contains `Google Calendar` and `Connected`.

- [ ] **Step 3: Add smoke schema**

Create `scripts/calendar_mcp_smoke.schema.json`.

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["provider", "mcpServer", "events", "fetchedAt"],
  "properties": {
    "provider": {
      "type": "string",
      "enum": ["codex", "claude"]
    },
    "mcpServer": {
      "type": "string",
      "minLength": 1
    },
    "fetchedAt": {
      "type": "string",
      "minLength": 1
    },
    "events": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["title", "start", "end"],
        "properties": {
          "title": { "type": "string" },
          "start": { "type": "string" },
          "end": { "type": "string" },
          "organizer": { "type": ["string", "null"] },
          "attendeeCount": { "type": "integer", "minimum": 0 }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Add real MCP fetch smoke script**

Create `scripts/verify_calendar_mcp_context.sh`.

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_PATH="$ROOT_DIR/scripts/calendar_mcp_smoke.schema.json"
OUTPUT_DIR="$ROOT_DIR/.tmp/calendar-mcp-smoke"
mkdir -p "$OUTPUT_DIR"

if ! codex mcp get google-calendar >/dev/null 2>&1; then
  echo "BLOCK: Codex google-calendar MCP is not configured." >&2
  echo "Run: codex mcp add google-calendar --url https://calendarmcp.googleapis.com/mcp/v1" >&2
  echo "Then: codex mcp login google-calendar" >&2
  exit 10
fi

if ! claude mcp list 2>/dev/null | grep -E "Google Calendar.*Connected|Google Calendar.*✓ Connected" >/dev/null; then
  echo "BLOCK: Claude Code Google Calendar MCP is not connected." >&2
  exit 11
fi

PROMPT='Use the connected Google Calendar MCP server to fetch calendar events overlapping now through the next 2 hours. Return only JSON matching the provided schema. Include at most 5 events. If there are no events, return an empty events array after actually checking Google Calendar.'

codex exec \
  --model gpt-5.4-mini \
  --skip-git-repo-check \
  --sandbox read-only \
  --output-schema "$SCHEMA_PATH" \
  - <<EOF > "$OUTPUT_DIR/codex-calendar.json"
$PROMPT
Set provider to "codex" and mcpServer to "google-calendar".
EOF

SCHEMA_JSON="$(cat "$SCHEMA_PATH")"
claude -p \
  --output-format json \
  --input-format text \
  --no-session-persistence \
  --json-schema "$SCHEMA_JSON" \
  "$PROMPT Set provider to \"claude\" and mcpServer to \"Google Calendar\"." \
  > "$OUTPUT_DIR/claude-calendar.json"

python3 - "$OUTPUT_DIR/codex-calendar.json" "$OUTPUT_DIR/claude-calendar.json" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    raw = open(path, encoding="utf-8").read()
    data = json.loads(raw)
    if "structured_output" in data:
        data = data["structured_output"]
    if isinstance(data, str):
        data = json.loads(data)
    assert data["provider"] in {"codex", "claude"}, data
    assert data["mcpServer"], data
    assert isinstance(data["events"], list), data
    print(f"PASS {data['provider']}: {len(data['events'])} calendar events fetched")
PY
```

- [ ] **Step 5: Make script executable**

Run:

```bash
chmod +x scripts/verify_calendar_mcp_context.sh
```

Expected: script is executable.

- [ ] **Step 6: Commit preflight script**

Run:

```bash
git add scripts/calendar_mcp_smoke.schema.json scripts/verify_calendar_mcp_context.sh
git commit -m "chore: add calendar mcp smoke test"
```

Expected: commit succeeds.

---

### Task 2: Core Calendar Context Models

**Files:**
- Create: `Sources/MeetingRescueCore/CalendarContextModels.swift`
- Modify: `Sources/MeetingRescueCore/AnalysisModels.swift`
- Test: `Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift`.

```swift
import Foundation
import Testing
@testable import MeetingRescueCore

struct CalendarContextModelsTests {
    @Test("supplemental context는 prompt priority 순서로 정렬된다")
    func sortsSupplementalContextByPriority() {
        let values = [
            SupplementalContextSource(id: "calendar", kind: .calendarMetadata, title: "Calendar", sourceName: "Calendar", excerpt: "event", priority: .calendarMetadata, confidence: 0.7),
            SupplementalContextSource(id: "attached", kind: .attachedText, title: "Agenda", sourceName: "agenda.md", excerpt: "agenda", priority: .userAttachedContext, confidence: 1.0),
            SupplementalContextSource(id: "confirmed", kind: .confirmedLocalArtifact, title: "Previous", sourceName: "Meeting Rescue", excerpt: "decision", priority: .confirmedLocalArtifact, confidence: 1.0)
        ]

        #expect(values.sortedForPrompt().map(\.id) == ["confirmed", "attached", "calendar"])
    }

    @Test("calendar identity는 recurrence id를 series key로 우선 사용한다")
    func calendarIdentityUsesRecurrenceIDForSeriesKey() {
        let identity = MeetingIdentity(
            calendarEventID: "event-1",
            recurrenceID: "series-1",
            fallbackFingerprint: "fallback",
            confidence: 0.91,
            isConfirmed: true
        )

        #expect(identity.seriesKey == "calendar:series-1")
    }

    @Test("analysis state는 calendar context를 저장하고 legacy JSON은 기본값으로 decode된다")
    func persistsCalendarContextStateAndDecodesLegacy() throws {
        var state = MeetingAnalysisState()
        state.calendarContext = CalendarContextState(
            mcpStatus: .connected,
            eventCandidates: [
                CalendarEventCandidate(
                    id: "event-1",
                    title: "Launch Review",
                    startDateText: "2026-06-03T10:00:00+09:00",
                    endDateText: "2026-06-03T11:00:00+09:00",
                    organizer: "alex@example.com",
                    attendees: ["alex@example.com", "blair@example.com"],
                    descriptionExcerpt: "Agenda",
                    recurrenceID: "series-1",
                    confidence: 0.88,
                    status: .accepted
                )
            ],
            supplementalSources: [
                SupplementalContextSource(id: "ctx-1", kind: .calendarMetadata, title: "Launch Review", sourceName: "Google Calendar", excerpt: "Agenda", priority: .calendarMetadata, confidence: 0.88)
            ],
            meetingIdentity: MeetingIdentity(calendarEventID: "event-1", recurrenceID: "series-1", fallbackFingerprint: "fallback", confidence: 0.88, isConfirmed: true)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(MeetingAnalysisState.self, from: data)

        #expect(decoded.calendarContext.mcpStatus == .connected)
        #expect(decoded.calendarContext.eventCandidates.first?.status == .accepted)
        #expect(decoded.calendarContext.meetingIdentity?.seriesKey == "calendar:series-1")

        let legacy = #"{"confirmedCandidateIDs":[],"deletedCandidateIDs":[],"decisionCandidateEdits":{},"actionItemCandidateEdits":{},"updatedAt":"2026-06-03T00:00:00Z","isCompleted":false,"usageSummary":{"totalInputTokens":0,"totalOutputTokens":0,"totalEstimatedCostUSD":0,"samples":[]},"attemptLogs":[],"analyzedTranscriptCharacterCount":0,"bookmarks":[]}"#
        let legacyDecoded = try JSONDecoder().decode(MeetingAnalysisState.self, from: Data(legacy.utf8))
        #expect(legacyDecoded.calendarContext == CalendarContextState())
    }
}
```

- [ ] **Step 2: Run tests to verify missing models fail**

Run:

```bash
swift test --filter CalendarContextModelsTests
```

Expected: FAIL with missing calendar context model symbols.

- [ ] **Step 3: Add calendar context models**

Create `Sources/MeetingRescueCore/CalendarContextModels.swift`.

```swift
import Foundation

public enum CalendarMCPStatus: String, Codable, Equatable, Sendable {
    case unknown
    case missing
    case connected
    case failed
}

public enum CalendarContextCandidateStatus: String, Codable, Equatable, Sendable {
    case candidate
    case accepted
    case dismissed
}

public struct CalendarEventCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startDateText: String
    public var endDateText: String
    public var organizer: String?
    public var attendees: [String]
    public var descriptionExcerpt: String
    public var recurrenceID: String?
    public var confidence: Double
    public var status: CalendarContextCandidateStatus

    public init(
        id: String,
        title: String,
        startDateText: String,
        endDateText: String,
        organizer: String? = nil,
        attendees: [String] = [],
        descriptionExcerpt: String = "",
        recurrenceID: String? = nil,
        confidence: Double = 0,
        status: CalendarContextCandidateStatus = .candidate
    ) {
        self.id = id
        self.title = title
        self.startDateText = startDateText
        self.endDateText = endDateText
        self.organizer = organizer
        self.attendees = attendees
        self.descriptionExcerpt = descriptionExcerpt
        self.recurrenceID = recurrenceID
        self.confidence = min(1, max(0, confidence))
        self.status = status
    }
}

public enum SupplementalContextKind: String, Codable, Equatable, Sendable {
    case confirmedLocalArtifact
    case attachedText
    case calendarMetadata
    case linkedSourceCandidate
    case recurringMemory
}

public enum SupplementalContextPriority: Int, Codable, Equatable, Comparable, Sendable {
    case confirmedLocalArtifact = 10
    case userAttachedContext = 20
    case calendarMetadata = 30
    case linkedSourceCandidate = 40

    public static func < (lhs: SupplementalContextPriority, rhs: SupplementalContextPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SupplementalContextSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: SupplementalContextKind
    public var title: String
    public var sourceName: String
    public var excerpt: String
    public var priority: SupplementalContextPriority
    public var confidence: Double
    public var isAccepted: Bool

    public init(
        id: String,
        kind: SupplementalContextKind,
        title: String,
        sourceName: String,
        excerpt: String,
        priority: SupplementalContextPriority,
        confidence: Double,
        isAccepted: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceName = sourceName
        self.excerpt = excerpt
        self.priority = priority
        self.confidence = min(1, max(0, confidence))
        self.isAccepted = isAccepted
    }
}

public struct MeetingIdentity: Codable, Equatable, Sendable {
    public var calendarEventID: String?
    public var recurrenceID: String?
    public var fallbackFingerprint: String
    public var confidence: Double
    public var isConfirmed: Bool

    public init(
        calendarEventID: String? = nil,
        recurrenceID: String? = nil,
        fallbackFingerprint: String,
        confidence: Double,
        isConfirmed: Bool = false
    ) {
        self.calendarEventID = calendarEventID
        self.recurrenceID = recurrenceID
        self.fallbackFingerprint = fallbackFingerprint
        self.confidence = min(1, max(0, confidence))
        self.isConfirmed = isConfirmed
    }

    public var seriesKey: String {
        if let recurrenceID, !recurrenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "calendar:\(recurrenceID)"
        }
        return "fingerprint:\(fallbackFingerprint)"
    }
}

public struct CalendarContextState: Codable, Equatable, Sendable {
    public var mcpStatus: CalendarMCPStatus
    public var eventCandidates: [CalendarEventCandidate]
    public var supplementalSources: [SupplementalContextSource]
    public var meetingIdentity: MeetingIdentity?
    public var lastFetchedAt: Date?
    public var lastError: String?

    public init(
        mcpStatus: CalendarMCPStatus = .unknown,
        eventCandidates: [CalendarEventCandidate] = [],
        supplementalSources: [SupplementalContextSource] = [],
        meetingIdentity: MeetingIdentity? = nil,
        lastFetchedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.mcpStatus = mcpStatus
        self.eventCandidates = eventCandidates
        self.supplementalSources = supplementalSources
        self.meetingIdentity = meetingIdentity
        self.lastFetchedAt = lastFetchedAt
        self.lastError = lastError
    }
}

public extension Array where Element == SupplementalContextSource {
    func sortedForPrompt() -> [SupplementalContextSource] {
        filter { $0.isAccepted && !$0.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.confidence > $1.confidence
                }
                return $0.priority < $1.priority
            }
    }
}
```

- [ ] **Step 4: Add state/request fields**

In `Sources/MeetingRescueCore/AnalysisModels.swift`, add:

```swift
public var calendarContext: CalendarContextState
```

Update `MeetingAnalysisState.init`, `CodingKeys`, and `init(from:)` with default `CalendarContextState()`.

Add to `AnalysisRequest`:

```swift
public var supplementalContextSources: [SupplementalContextSource]
```

Update `AnalysisRequest.init` with:

```swift
supplementalContextSources: [SupplementalContextSource] = []
```

and assign:

```swift
self.supplementalContextSources = supplementalContextSources
```

- [ ] **Step 5: Run model tests**

Run:

```bash
swift test --filter CalendarContextModelsTests
```

Expected: PASS.

- [ ] **Step 6: Commit models**

Run:

```bash
git add Sources/MeetingRescueCore/CalendarContextModels.swift Sources/MeetingRescueCore/AnalysisModels.swift Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift
git commit -m "feat: add calendar context models"
```

Expected: commit succeeds.

---

### Task 3: Calendar MCP Fetcher

**Files:**
- Create: `Sources/MeetingRescueCore/CalendarMCPContextFetcher.swift`
- Create: `Sources/MeetingRescue/Resources/calendar-mcp-context-output.schema.json`
- Modify: `Sources/MeetingRescueCore/LLMProvider.swift`
- Test: `Tests/MeetingRescueCoreTests/CalendarMCPContextFetcherTests.swift`
- Modify: `Tests/MeetingRescueCoreTests/LLMProviderConfigurationTests.swift`

- [ ] **Step 1: Write failing fetcher tests**

Create `Tests/MeetingRescueCoreTests/CalendarMCPContextFetcherTests.swift`.

```swift
import Foundation
import Testing
@testable import MeetingRescueCore

struct CalendarMCPContextFetcherTests {
    @Test("Codex calendar MCP arguments keep user config and enable google-calendar access")
    func codexCalendarArgumentsKeepMCPConfig() {
        let schemaURL = URL(fileURLWithPath: "/tmp/calendar-schema.json")
        let arguments = CalendarMCPCommandBuilder.codexArguments(schemaURL: schemaURL, modelPreset: .economy)

        #expect(arguments.starts(with: ["codex", "exec"]))
        #expect(!arguments.contains("--ignore-user-config"))
        #expect(arguments.contains("--output-schema"))
        #expect(arguments.contains(schemaURL.path))
        #expect(arguments.contains("--sandbox"))
        #expect(arguments.contains("read-only"))
    }

    @Test("Claude calendar MCP arguments use print mode and preserve MCP config")
    func claudeCalendarArgumentsUsePrintMode() throws {
        let schemaURL = URL(fileURLWithPath: "/tmp/calendar-schema.json")
        let arguments = try CalendarMCPCommandBuilder.claudeArguments(schemaURL: schemaURL, modelPreset: .economy)

        #expect(arguments.starts(with: ["claude", "-p"]))
        #expect(arguments.contains("--json-schema"))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(!arguments.contains("--tools"))
        #expect(!arguments.contains("--strict-mcp-config"))
    }

    @Test("calendar MCP output decodes event candidates and linked source candidates")
    func decodesCalendarMCPOutput() throws {
        let output = """
        {
          "events": [
            {
              "id": "event-1",
              "title": "Launch Review",
              "startDateText": "2026-06-03T10:00:00+09:00",
              "endDateText": "2026-06-03T11:00:00+09:00",
              "organizer": "alex@example.com",
              "attendees": ["alex@example.com", "blair@example.com"],
              "descriptionExcerpt": "Agenda: decide launch owner. https://docs.google.com/document/d/abc",
              "recurrenceID": "series-1",
              "confidence": 0.9
            }
          ],
          "linkedSourceCandidates": [
            {
              "id": "link-1",
              "title": "Launch PRD",
              "url": "https://docs.google.com/document/d/abc",
              "sourceName": "Google Docs",
              "confidence": 0.7
            }
          ]
        }
        """

        let result = try CalendarMCPContextFetcher.decode(output)

        #expect(result.events.first?.title == "Launch Review")
        #expect(result.events.first?.recurrenceID == "series-1")
        #expect(result.linkedSourceCandidates.first?.sourceName == "Google Docs")
    }
}
```

- [ ] **Step 2: Run tests to verify fetcher fails**

Run:

```bash
swift test --filter CalendarMCPContextFetcherTests
```

Expected: FAIL with missing `CalendarMCPCommandBuilder` and `CalendarMCPContextFetcher`.

- [ ] **Step 3: Add resource schema**

Create `Sources/MeetingRescue/Resources/calendar-mcp-context-output.schema.json`.

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["events", "linkedSourceCandidates"],
  "properties": {
    "events": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "title", "startDateText", "endDateText", "attendees", "descriptionExcerpt", "confidence"],
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "startDateText": { "type": "string" },
          "endDateText": { "type": "string" },
          "organizer": { "type": ["string", "null"] },
          "attendees": { "type": "array", "items": { "type": "string" } },
          "descriptionExcerpt": { "type": "string" },
          "recurrenceID": { "type": ["string", "null"] },
          "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
        }
      }
    },
    "linkedSourceCandidates": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "title", "url", "sourceName", "confidence"],
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string" },
          "url": { "type": "string" },
          "sourceName": { "type": "string" },
          "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Implement command builder and decoder**

Create `Sources/MeetingRescueCore/CalendarMCPContextFetcher.swift`.

```swift
import Foundation

public struct CalendarLinkedSourceCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var sourceName: String
    public var confidence: Double
}

public struct CalendarMCPFetchResult: Codable, Equatable, Sendable {
    public var events: [CalendarEventCandidate]
    public var linkedSourceCandidates: [CalendarLinkedSourceCandidate]
}

public struct CalendarMCPFetchRequest: Equatable, Sendable {
    public var metadata: MeetingMetadata
    public var rawTranscriptPrefix: String
    public var now: Date

    public init(metadata: MeetingMetadata, rawTranscriptPrefix: String, now: Date = Date()) {
        self.metadata = metadata
        self.rawTranscriptPrefix = rawTranscriptPrefix
        self.now = now
    }
}

public enum CalendarMCPCommandBuilder {
    public static func codexArguments(schemaURL: URL, modelPreset: LLMModelPreset) -> [String] {
        var arguments = ["codex", "exec"]
        if let modelName = modelPreset.codexModelName {
            arguments.append(contentsOf: ["--model", modelName])
        }
        arguments.append(contentsOf: [
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox",
            "read-only",
            "--output-schema",
            schemaURL.path,
            "-"
        ])
        return arguments
    }

    public static func claudeArguments(schemaURL: URL, modelPreset: LLMModelPreset) throws -> [String] {
        let schema = try String(contentsOf: schemaURL, encoding: .utf8)
        var arguments = [
            "claude",
            "-p",
            "--output-format",
            "json",
            "--input-format",
            "text",
            "--no-session-persistence",
            "--json-schema",
            schema
        ]
        if let modelName = modelPreset.claudeCodeModelName {
            arguments.append(contentsOf: ["--model", modelName])
        }
        if let effort = modelPreset.claudeCodeEffort {
            arguments.append(contentsOf: ["--effort", effort])
        }
        return arguments
    }
}

public enum CalendarMCPContextFetcher {
    public static func prompt(for request: CalendarMCPFetchRequest) -> String {
        """
        Use the connected Google Calendar MCP server. Fetch calendar events that overlap this meeting or are likely to refer to it.

        Matching signals:
        - current time: \(ISO8601DateFormatter().string(from: request.now))
        - transcript room/title: \(request.metadata.displayTitle)
        - transcript date/time: \(request.metadata.dateTime ?? "-")
        - transcript participants: \(request.metadata.participants.joined(separator: ", "))
        - transcript prefix:
        \(request.rawTranscriptPrefix)

        Return only JSON matching the schema. Include at most 5 event candidates. Include linkedSourceCandidates only for links found in calendar descriptions. Do not fetch linked documents.
        """
    }

    public static func decode(_ output: String) throws -> CalendarMCPFetchResult {
        let data = try structuredOutputData(from: output)
        let decoder = JSONDecoder()
        return try decoder.decode(CalendarMCPFetchResult.self, from: data)
    }

    private static func structuredOutputData(from output: String) throws -> Data {
        guard let data = output.data(using: .utf8) else {
            throw LLMProviderError.invalidOutput
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let structured = object["structured_output"] {
            if let string = structured as? String, let structuredData = string.data(using: .utf8) {
                return structuredData
            }
            if JSONSerialization.isValidJSONObject(structured) {
                return try JSONSerialization.data(withJSONObject: structured)
            }
        }
        return data
    }
}
```

- [ ] **Step 5: Open ProcessRunner for Core reuse**

In `Sources/MeetingRescueCore/LLMProvider.swift`, change:

```swift
private enum ProcessRunner {
```

to:

```swift
enum ProcessRunner {
```

This keeps the runner internal to `MeetingRescueCore` while allowing `CalendarMCPContextFetcher.swift` to reuse the existing traced process execution path.

- [ ] **Step 6: Add fetch execution API**

Append to `CalendarMCPContextFetcher`.

```swift
public static func fetch(
    request: CalendarMCPFetchRequest,
    providerKind: LLMProviderKind,
    modelPreset: LLMModelPreset,
    schemaURL: URL,
    timeoutSeconds: Int,
    workingDirectoryURL: URL
) async throws -> CalendarMCPFetchResult {
    let prompt = prompt(for: request)
    let arguments: [String]
    switch providerKind {
    case .codexExec:
        arguments = CalendarMCPCommandBuilder.codexArguments(schemaURL: schemaURL, modelPreset: modelPreset)
    case .claudeCode:
        arguments = try CalendarMCPCommandBuilder.claudeArguments(schemaURL: schemaURL, modelPreset: modelPreset)
    case .customCommand:
        throw LLMProviderError.missingCustomCommand
    }
    let output = try await ProcessRunner.runWithTrace(
        executableURL: URL(fileURLWithPath: "/usr/bin/env"),
        arguments: arguments,
        environment: CodexExecProvider.environment(for: modelPreset),
        standardInput: prompt,
        timeoutSeconds: timeoutSeconds,
        workingDirectoryURL: workingDirectoryURL
    )
    return try decode(output.output)
}
```

- [ ] **Step 7: Run fetcher tests**

Run:

```bash
swift test --filter CalendarMCPContextFetcherTests
```

Expected: PASS.

- [ ] **Step 8: Commit fetcher**

Run:

```bash
git add Sources/MeetingRescueCore/CalendarMCPContextFetcher.swift Sources/MeetingRescueCore/LLMProvider.swift Sources/MeetingRescue/Resources/calendar-mcp-context-output.schema.json Tests/MeetingRescueCoreTests/CalendarMCPContextFetcherTests.swift Tests/MeetingRescueCoreTests/LLMProviderConfigurationTests.swift
git commit -m "feat: add calendar mcp context fetcher"
```

Expected: commit succeeds.

---

### Task 4: Supplemental Context Prompt Contract

**Files:**
- Modify: `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`
- Modify: `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`

- [ ] **Step 1: Write failing prompt tests**

Append to `AnalysisPromptBuilderTests`.

```swift
@Test("prompt includes supplemental context with transcript priority warning")
func promptIncludesSupplementalContextPriority() throws {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-03 10:00", participants: ["Alex"]),
        rawTranscript: "[00:01] Alex: transcript가 source of truth입니다.",
        reason: "manual",
        supplementalContextSources: [
            SupplementalContextSource(
                id: "calendar-1",
                kind: .calendarMetadata,
                title: "Launch Review",
                sourceName: "Google Calendar",
                excerpt: "Calendar says launch review with Blair.",
                priority: .calendarMetadata,
                confidence: 0.86
            )
        ]
    )

    let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

    #expect(prompt.contains("\"supplementalContext\""))
    #expect(prompt.contains("Google Calendar"))
    #expect(prompt.contains("transcript가 supplemental context와 충돌하면 transcript를 우선"))
}
```

- [ ] **Step 2: Run test to verify prompt contract fails**

Run:

```bash
swift test --filter AnalysisPromptBuilderTests/promptIncludesSupplementalContextPriority
```

Expected: FAIL because prompt does not include supplemental context.

- [ ] **Step 3: Add supplemental context payload**

In `AnalysisPromptBuilder.Payload`, add:

```swift
var supplementalContext: [SupplementalContextPayload]
```

Add:

```swift
private struct SupplementalContextPayload: Encodable {
    var id: String
    var kind: String
    var title: String
    var sourceName: String
    var excerpt: String
    var priority: String
    var confidence: Double
}
```

When building `Payload`, add:

```swift
supplementalContext: request.supplementalContextSources.sortedForPrompt().map {
    SupplementalContextPayload(
        id: $0.id,
        kind: $0.kind.rawValue,
        title: $0.title,
        sourceName: $0.sourceName,
        excerpt: cappedSuffix($0.excerpt, limit: 1_200),
        priority: String($0.priority.rawValue),
        confidence: $0.confidence
    )
}
```

Add this instruction near the existing source-priority instructions:

```swift
Supplemental context는 transcript보다 낮은 우선순위의 보조 근거입니다. transcript가 supplemental context와 충돌하면 transcript를 우선하고, confirmed local artifact가 있으면 calendar metadata보다 우선하세요. Calendar linked source candidate는 자동으로 읽은 문서가 아니라 사용자가 확인해야 할 후보로만 취급하세요.
```

- [ ] **Step 4: Run prompt tests**

Run:

```bash
swift test --filter AnalysisPromptBuilderTests/promptIncludesSupplementalContextPriority
swift test --filter AnalysisPromptBuilderTests
```

Expected: PASS.

- [ ] **Step 5: Commit prompt contract**

Run:

```bash
git add Sources/MeetingRescueCore/AnalysisPromptBuilder.swift Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift
git commit -m "feat: include supplemental context in prompts"
```

Expected: commit succeeds.

---

### Task 5: Context Attach Reader

**Files:**
- Create: `Sources/MeetingRescueCore/SupplementalContextReader.swift`
- Test: `Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift`

- [ ] **Step 1: Add failing attach reader test**

Append to `CalendarContextModelsTests`.

```swift
@Test("text attachment reader stores capped excerpt and source metadata")
func readsCappedAttachmentExcerpt() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("meeting-rescue-context-\(UUID().uuidString).md")
    try String(repeating: "agenda ", count: 1_000).write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    let source = try SupplementalContextReader.source(from: url, characterLimit: 120)

    #expect(source.kind == .attachedText)
    #expect(source.sourceName == url.lastPathComponent)
    #expect(source.excerpt.count <= 120)
    #expect(source.priority == .userAttachedContext)
}
```

- [ ] **Step 2: Run test to verify reader fails**

Run:

```bash
swift test --filter CalendarContextModelsTests/readsCappedAttachmentExcerpt
```

Expected: FAIL with missing `SupplementalContextReader`.

- [ ] **Step 3: Implement reader**

Create `Sources/MeetingRescueCore/SupplementalContextReader.swift`.

```swift
import Foundation

public enum SupplementalContextReader {
    public static func source(from url: URL, characterLimit: Int = 4_000) throws -> SupplementalContextSource {
        let extensionValue = url.pathExtension.lowercased()
        guard ["md", "txt"].contains(extensionValue) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(text.prefix(max(1, characterLimit)))
        return SupplementalContextSource(
            id: "attached:\(url.path)",
            kind: .attachedText,
            title: url.deletingPathExtension().lastPathComponent,
            sourceName: url.lastPathComponent,
            excerpt: capped,
            priority: .userAttachedContext,
            confidence: 1.0
        )
    }
}
```

- [ ] **Step 4: Run attach tests**

Run:

```bash
swift test --filter CalendarContextModelsTests
```

Expected: PASS.

- [ ] **Step 5: Commit attach reader**

Run:

```bash
git add Sources/MeetingRescueCore/SupplementalContextReader.swift Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift
git commit -m "feat: add supplemental context attach reader"
```

Expected: commit succeeds.

---

### Task 6: AppViewModel Calendar Context Wiring

**Files:**
- Modify: `Sources/MeetingRescue/AppViewModel.swift`

- [ ] **Step 1: Add published runtime state**

Add near existing analysis state:

```swift
@Published var calendarContextStatusMessage = "Google Calendar MCP 확인 전"
@Published var isFetchingCalendarContext = false
```

- [ ] **Step 2: Add calendar fetch action**

Add:

```swift
func fetchGoogleCalendarContext() {
    guard !isFetchingCalendarContext else {
        return
    }
    isFetchingCalendarContext = true
    calendarContextStatusMessage = "Google Calendar MCP에서 회의 후보를 가져오는 중"

    let request = CalendarMCPFetchRequest(
        metadata: metadata,
        rawTranscriptPrefix: String(rawTranscript.prefix(3_000))
    )

    Task { [weak self] in
        guard let self else {
            return
        }
        do {
            let schemaURL = Bundle.module.url(forResource: "calendar-mcp-context-output", withExtension: "schema.json")
                ?? Bundle.module.url(forResource: "calendar-mcp-context-output", withExtension: "json")
            guard let schemaURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            let result = try await CalendarMCPContextFetcher.fetch(
                request: request,
                providerKind: self.settings.selectedProvider,
                modelPreset: self.settings.modelPreset,
                schemaURL: schemaURL,
                timeoutSeconds: self.effectiveAnalysisTimeoutSeconds(for: "calendar-mcp"),
                workingDirectoryURL: self.selectedFolderURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
            await MainActor.run {
                self.analysisState.calendarContext.mcpStatus = .connected
                self.analysisState.calendarContext.eventCandidates = result.events
                self.analysisState.calendarContext.lastFetchedAt = Date()
                self.analysisState.calendarContext.lastError = nil
                self.calendarContextStatusMessage = "Calendar 후보 \(result.events.count)개"
                self.isFetchingCalendarContext = false
                self.persistCandidateStateChange()
            }
        } catch {
            await MainActor.run {
                self.analysisState.calendarContext.mcpStatus = .failed
                self.analysisState.calendarContext.lastError = error.localizedDescription
                self.calendarContextStatusMessage = "Calendar MCP 실패: \(error.localizedDescription)"
                self.isFetchingCalendarContext = false
            }
        }
    }
}
```

- [ ] **Step 3: Add accept/dismiss context actions**

Add:

```swift
func acceptCalendarEventCandidate(id: String) {
    guard let index = analysisState.calendarContext.eventCandidates.firstIndex(where: { $0.id == id }) else {
        return
    }
    var candidate = analysisState.calendarContext.eventCandidates[index]
    candidate.status = .accepted
    analysisState.calendarContext.eventCandidates[index] = candidate
    analysisState.calendarContext.meetingIdentity = MeetingIdentity(
        calendarEventID: candidate.id,
        recurrenceID: candidate.recurrenceID,
        fallbackFingerprint: meetingIdentityFallbackFingerprint(),
        confidence: candidate.confidence,
        isConfirmed: true
    )
    analysisState.calendarContext.supplementalSources.removeAll { $0.id == "calendar:\(candidate.id)" }
    analysisState.calendarContext.supplementalSources.append(
        SupplementalContextSource(
            id: "calendar:\(candidate.id)",
            kind: .calendarMetadata,
            title: candidate.title,
            sourceName: "Google Calendar",
            excerpt: calendarExcerpt(candidate),
            priority: .calendarMetadata,
            confidence: candidate.confidence
        )
    )
    persistCandidateStateChange()
}

func dismissCalendarEventCandidate(id: String) {
    guard let index = analysisState.calendarContext.eventCandidates.firstIndex(where: { $0.id == id }) else {
        return
    }
    analysisState.calendarContext.eventCandidates[index].status = .dismissed
    persistCandidateStateChange()
}

private func calendarExcerpt(_ candidate: CalendarEventCandidate) -> String {
    [
        "title: \(candidate.title)",
        "time: \(candidate.startDateText)-\(candidate.endDateText)",
        candidate.organizer.map { "organizer: \($0)" },
        candidate.attendees.isEmpty ? nil : "attendees: \(candidate.attendees.joined(separator: ", "))",
        candidate.descriptionExcerpt.isEmpty ? nil : "description: \(candidate.descriptionExcerpt)"
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
}

private func meetingIdentityFallbackFingerprint() -> String {
    [
        metadata.room ?? "",
        metadata.displayTitle,
        metadata.participants.sorted().joined(separator: ",")
    ]
    .joined(separator: "|")
    .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    .lowercased()
}
```

- [ ] **Step 4: Wire supplemental context into analysis request**

When creating `AnalysisRequest`, pass:

```swift
supplementalContextSources: analysisState.calendarContext.supplementalSources
```

- [ ] **Step 5: Build AppViewModel**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit wiring**

Run:

```bash
git add Sources/MeetingRescue/AppViewModel.swift
git commit -m "feat: wire google calendar context"
```

Expected: commit succeeds.

---

### Task 7: Context UI

**Files:**
- Modify: `Sources/MeetingRescue/ContentView.swift`

- [ ] **Step 1: Add context tab**

Extend `IntelligenceMode`:

```swift
case context = "컨텍스트"
```

Update switch:

```swift
case .context:
    contextPanel()
```

- [ ] **Step 2: Add context panel UI**

Add:

```swift
private func contextPanel() -> some View {
    VStack(alignment: .leading, spacing: 12) {
        calendarMCPStatusCard()
        calendarEventCandidates(viewModel.analysisState.calendarContext.eventCandidates)
        supplementalContextSources(viewModel.analysisState.calendarContext.supplementalSources)
    }
}

private func calendarMCPStatusCard() -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            sectionHeader("Google Calendar MCP", systemImage: "calendar.badge.clock")
            Spacer()
            Button {
                viewModel.fetchGoogleCalendarContext()
            } label: {
                Label(viewModel.isFetchingCalendarContext ? "가져오는 중" : "가져오기", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isFetchingCalendarContext)
        }
        Text(viewModel.calendarContextStatusMessage)
            .font(.caption)
            .foregroundStyle(Color.smoothMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
    .smoothCard(tint: Color.smoothAccent)
}

private func calendarEventCandidates(_ candidates: [CalendarEventCandidate]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        sectionHeader("Calendar Event Candidates", systemImage: "calendar")
        if candidates.filter({ $0.status != .dismissed }).isEmpty {
            placeholderLine("Google Calendar MCP에서 가져온 후보가 없습니다.")
        }
        ForEach(candidates.filter { $0.status != .dismissed }) { candidate in
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.title)
                    .font(.callout.weight(.semibold))
                Text("\(candidate.startDateText)-\(candidate.endDateText)")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                if !candidate.descriptionExcerpt.isEmpty {
                    Text(candidate.descriptionExcerpt)
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                        .lineLimit(3)
                }
                HStack {
                    Button("사용") {
                        viewModel.acceptCalendarEventCandidate(id: candidate.id)
                    }
                    Button("숨기기") {
                        viewModel.dismissCalendarEventCandidate(id: candidate.id)
                    }
                }
                .font(.caption.weight(.semibold))
            }
            .padding(10)
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    .smoothCard(tint: Color.smoothSky)
}

private func supplementalContextSources(_ sources: [SupplementalContextSource]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        sectionHeader("Supplemental Context", systemImage: "doc.text.magnifyingglass")
        if sources.sortedForPrompt().isEmpty {
            placeholderLine("Prompt에 주입할 accepted context가 없습니다.")
        }
        ForEach(sources.sortedForPrompt()) { source in
            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.callout.weight(.semibold))
                Text("\(source.sourceName) · priority \(source.priority.rawValue) · confidence \(String(format: "%.2f", source.confidence))")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                Text(source.excerpt)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(4)
            }
            .padding(10)
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    .smoothCard()
}
```

- [ ] **Step 3: Build UI**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 4: Commit UI**

Run:

```bash
git add Sources/MeetingRescue/ContentView.swift
git commit -m "feat: add calendar context ui"
```

Expected: commit succeeds.

---

### Task 8: D2 Verification Gate

**Files:**
- Verify: full repository

- [ ] **Step 1: Run focused model/fetcher tests**

Run:

```bash
swift test --filter CalendarContextModelsTests
swift test --filter CalendarMCPContextFetcherTests
swift test --filter AnalysisPromptBuilderTests
```

Expected: PASS.

- [ ] **Step 2: Run full tests and build**

Run:

```bash
swift test
swift build
git diff --check
```

Expected: all pass and `git diff --check` has no output.

- [ ] **Step 3: Run real Google Calendar MCP fetch smoke**

Run:

```bash
./scripts/verify_calendar_mcp_context.sh
```

Expected:

```txt
PASS codex: <N> calendar events fetched
PASS claude: <N> calendar events fetched
```

`N` may be `0` when the calendar has no event in the next 2 hours. The pass condition is that both providers actually connect to Google Calendar MCP and return schema-valid JSON.

- [ ] **Step 4: Inspect final branch state**

Run:

```bash
git status --short --branch
git log --oneline --decorate -6
```

Expected: only intentional D2 commits are present. Pre-existing unrelated files remain untouched.

---

## Self-review Checklist

- Google Calendar MCP is mandatory for D2 and has Codex plus Claude Code preflight.
- Codex provider calendar fetch path does not use `--ignore-user-config`, because that would hide MCP configuration.
- Claude Code calendar fetch path does not set `--tools ""`, because that would block MCP tool use.
- Calendar linked docs are surfaced as candidates only; D2 does not auto-fetch Google Docs/Slides/Jira/Slack content.
- Prompt priority rule is explicit: transcript wins over supplemental context on conflict.
- Real MCP fetch smoke is a required D2 verification gate.
