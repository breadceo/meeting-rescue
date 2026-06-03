# D0 Meeting Intelligence Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** D0 backlog의 Meeting Type Preset, evidence-backed wrap-up, Live Bookmark를 하나의 안정적인 Meeting Intelligence 계약으로 구현한다.

**Architecture:** Core 모델에 회의 유형, 근거 달린 전체 회의 요약, 라이브 북마크를 추가하고 기존 snapshot/patch decode는 backward-compatible하게 유지한다. Provider prompt와 JSON schema는 새 계약을 강제하고, SwiftUI는 `currentIssue`를 현재 논점으로 재라벨링하면서 요약과 북마크를 노출한다.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Codable, JSON Schema, existing `MeetingRescueCore` provider/prompt/exporter pipeline.

---

## Scope

이 계획은 `tasks.md`의 `D0 Meeting Intelligence contract`만 다룬다. D1 Decision Coach, Share Readiness, Action Ledger와 D2 Calendar/Slack/team shared context는 D0의 `meetingType`, `meetingSummary`, `bookmarks`, evidence 구조가 생긴 뒤 별도 계획으로 실행한다.

## Product Decisions

- `Meeting Type Preset`: `Auto`에서는 LLM이 `decision`, `planning`, `incident`, `oneOnOne`, `brainstorm`, `status` 중 하나를 추정해 `snapshot.meetingType`에 저장한다. 사용자가 manual preset을 고르면 그 값을 output contract에 고정한다.
- Evidence model: summary evidence에는 `timestamp`, `speaker`, `excerpt`를 저장한다. 이 앱은 local-first이고, transcript 원문을 다시 열지 않아도 summary 근거를 판단하는 것이 D0의 핵심 가치다.
- Final analysis: 회의 종료/final analysis는 이전 snapshot이 있어도 항상 `fullSnapshot` output mode를 사용해 회의 전체 wrap-up을 다시 만든다. 부분 chunk로 전체 요약이 덮이지 않도록 final 계열 reason은 catch-up chunk 제한을 적용하지 않고 전체 transcript를 입력으로 사용한다.
- Live Bookmark UX: 1차 구현은 app command의 `Cmd+B` 일반 북마크와 header quick tag `결정`, `액션`, `열린 질문`만 제공한다. 자유 입력 label은 D0 이후 UX가 필요해질 때 별도 작업으로 붙인다.
- UI terminology: `currentIssue`의 사용자-facing label은 한국어 앱 기준 `현재 논점`으로 확정한다. 내부 모델명은 기존 호환성을 위해 `currentIssue`를 유지한다.

## File Structure

- Modify `Sources/MeetingRescueCore/AnalysisModels.swift`: meeting type preset, summary evidence model, bookmark model, snapshot/patch/state/request 계약.
- Modify `Sources/MeetingRescueCore/AnalysisTranscriptWindow.swift`: final full wrap-up은 chunk 제한 없이 전체 transcript를 사용하게 한다.
- Modify `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`: meeting type preset과 bookmarks를 prompt payload에 넣고 final/full snapshot의 wrap-up 계약을 명시.
- Modify `Sources/MeetingRescueCore/LLMProvider.swift`: patch decode 후 summary evidence와 meeting type을 merge하고 candidate id 보정은 기존 경로를 유지.
- Modify `Sources/MeetingRescueCore/LocalAnalysisFallback.swift`: fallback snapshot도 meeting type과 minimal summary를 채운다.
- Modify `Sources/MeetingRescueCore/MeetingIntelligenceMarkdownExporter.swift`: `회의 요약`, `현재 논점`, summary evidence, bookmarks를 Markdown에 내보낸다.
- Modify `Sources/MeetingRescue/Resources/analysis-output.schema.json`: full snapshot schema에 `meetingType`, `meetingSummary`를 추가한다.
- Modify `Sources/MeetingRescue/Resources/analysis-patch-output.schema.json`: live patch schema에 nullable `meetingType`, nullable `meetingSummary`를 추가한다.
- Modify `Sources/MeetingRescue/AppViewModel.swift`: settings/request wiring, bookmark add/delete, final full snapshot contract propagation.
- Modify `Sources/MeetingRescue/ContentView.swift`: meeting type picker, `현재 논점` label, wrap-up card, bookmark button/list.
- Modify `Sources/MeetingRescue/MeetingRescueApp.swift`: `Cmd+B` bookmark app command.
- Modify `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`: model decode, patch merge, bookmark persistence, final output mode tests.
- Modify `Tests/MeetingRescueCoreTests/LLMProviderOutputTests.swift`: full/patch provider output tests for D0 contract.
- Modify `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`: prompt payload/instruction/final full snapshot tests.
- Modify `Tests/MeetingRescueCoreTests/MarkdownExporterTests.swift`: Markdown wrap-up and evidence tests.
- Modify `Tests/MeetingRescueCoreTests/SchemaTests.swift`: no test logic change; existing strict-required test must pass with new schema keys.

---

### Task 1: Core Contract Models

**Files:**
- Modify: `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`
- Modify: `Sources/MeetingRescueCore/AnalysisModels.swift`

- [ ] **Step 1: Write failing core contract tests**

Append these tests inside `AnalysisStateTests`.

```swift
@Test("D0 snapshot은 meeting type과 evidence-backed summary를 decode한다")
func decodesD0SnapshotContract() throws {
    let json = """
    {
      "meetingType": "decision",
      "meetingSummary": {
        "overview": "배포 방식과 책임자를 좁힌 회의다.",
        "keyPoints": [
          {
            "id": "summary-1",
            "text": "금요일 배포를 기준으로 준비한다.",
            "evidence": [
              {
                "timestamp": "00:10",
                "speaker": "Alex",
                "excerpt": "금요일 배포로 가죠."
              }
            ]
          }
        ],
        "openQuestions": [
          {
            "id": "question-1",
            "text": "롤백 담당자를 확정해야 한다.",
            "evidence": [
              {
                "timestamp": "00:30",
                "speaker": "Blair",
                "excerpt": "롤백 담당자는 아직 없나요?"
              }
            ]
          }
        ]
      },
      "currentIssue": {
        "summary": "롤백 담당자 확정이 남아 있다.",
        "openQuestions": ["롤백 담당자는 누구인가?"]
      },
      "topicTimeline": [],
      "decisionCandidates": [],
      "actionItemCandidates": [],
      "risksOrNotes": []
    }
    """

    let snapshot = try JSONDecoder().decode(AnalysisSnapshot.self, from: Data(json.utf8))

    #expect(snapshot.meetingType == .decision)
    #expect(snapshot.meetingSummary.overview == "배포 방식과 책임자를 좁힌 회의다.")
    #expect(snapshot.meetingSummary.keyPoints.first?.evidence.first?.timestamp == "00:10")
    #expect(snapshot.meetingSummary.openQuestions.first?.text == "롤백 담당자를 확정해야 한다.")
}

@Test("legacy snapshot은 D0 필드 없이도 기본값으로 decode한다")
func decodesLegacySnapshotWithoutD0Fields() throws {
    let json = """
    {
      "currentIssue": {
        "summary": "기존 요약",
        "openQuestions": []
      },
      "topicTimeline": [],
      "decisionCandidates": [],
      "actionItemCandidates": [],
      "risksOrNotes": []
    }
    """

    let snapshot = try JSONDecoder().decode(AnalysisSnapshot.self, from: Data(json.utf8))

    #expect(snapshot.meetingType == .automatic)
    #expect(snapshot.meetingSummary.isEmpty)
}

@Test("live patch는 meeting type과 summary를 기존 snapshot에 merge한다")
func livePatchMergesD0Fields() {
    let previous = AnalysisSnapshot(
        meetingType: .automatic,
        meetingSummary: MeetingSummary(overview: "이전 요약")
    )
    let patch = AnalysisSnapshotPatch(
        meetingType: .planning,
        meetingSummary: MeetingSummary(
            overview: "새 계획 요약",
            keyPoints: [
                MeetingSummaryItem(
                    id: "summary-plan",
                    text: "마일스톤을 다음 주로 맞춘다.",
                    evidence: [
                        EvidenceReference(
                            timestamp: "02:10",
                            speaker: "Casey",
                            excerpt: "다음 주 마일스톤으로 맞추겠습니다."
                        )
                    ]
                )
            ]
        )
    )

    let merged = previous.applyingPatch(patch, provider: .customCommand)

    #expect(merged.meetingType == .planning)
    #expect(merged.meetingSummary.overview == "새 계획 요약")
    #expect(merged.meetingSummary.keyPoints.first?.text == "마일스톤을 다음 주로 맞춘다.")
}

@Test("meeting bookmarks를 저장하고 다시 불러온다")
func persistsMeetingBookmarks() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("MeetingRescueBookmarks-\(UUID().uuidString)", isDirectory: true)
    let store = ApplicationStateStore(rootURL: rootURL)
    let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
    var state = MeetingAnalysisState()
    state.addBookmark(
        MeetingBookmark(
            id: "bookmark-1",
            timestamp: "[04:13]",
            label: "결정 기준",
            createdAt: Date(timeIntervalSince1970: 100),
            excerpt: "결정 기준은 비용과 속도입니다."
        )
    )

    try store.saveAnalysisState(state, for: transcriptURL)
    let loaded = store.loadAnalysisState(for: transcriptURL)

    #expect(loaded.bookmarks.map(\.id) == ["bookmark-1"])
    #expect(loaded.bookmarks.first?.timestamp == "[04:13]")
    #expect(loaded.bookmarks.first?.label == "결정 기준")

    try? FileManager.default.removeItem(at: rootURL)
}

@Test("final analysis는 previous snapshot이 있어도 full snapshot output을 쓴다")
func finalAnalysisUsesFullSnapshotOutput() {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[00:10] Alex: 정리합니다.",
        previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
        reason: "final",
        lastAnalyzedTranscriptCharacterCount: 8
    )

    #expect(request.outputMode == .fullSnapshot)
    #expect(AnalysisRequest.usesFullSnapshotOutput("final"))
}
```

- [ ] **Step 2: Run tests to verify the new contract fails**

Run:

```bash
swift test --filter AnalysisStateTests
```

Expected: FAIL with missing `MeetingSummary`, `MeetingSummaryItem`, `EvidenceReference`, `MeetingBookmark`, `meetingType`, `meetingSummary`, `bookmarks`, or final output mode assertions.

- [ ] **Step 3: Add meeting type, evidence, summary, and bookmark models**

In `Sources/MeetingRescueCore/AnalysisModels.swift`, insert these models after `LiveContextRetrievalMode`.

```swift
public enum MeetingTypePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case decision
    case planning
    case incident
    case oneOnOne
    case brainstorm
    case status

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic:
            return "Auto"
        case .decision:
            return "Decision"
        case .planning:
            return "Planning"
        case .incident:
            return "Incident"
        case .oneOnOne:
            return "1:1"
        case .brainstorm:
            return "Brainstorm"
        case .status:
            return "Status"
        }
    }

    public var detail: String {
        switch self {
        case .automatic:
            return "회의 초반 transcript로 유형을 추정하고 사용자가 필요하면 override합니다."
        case .decision:
            return "선택지, 판단 기준, 결정 근거, 남은 승인자를 우선 정리합니다."
        case .planning:
            return "목표, 범위, 일정, owner, dependency를 우선 정리합니다."
        case .incident:
            return "증상, 영향, 원인 가설, mitigation, follow-up을 우선 정리합니다."
        case .oneOnOne:
            return "관심사, 피드백, 약속, 다음 대화를 우선 정리합니다."
        case .brainstorm:
            return "아이디어, 가설, 근거, 수렴 지점을 우선 정리합니다."
        case .status:
            return "진행 상황, block, 다음 action, escalation을 우선 정리합니다."
        }
    }

    public static var concreteCases: [MeetingTypePreset] {
        allCases.filter { $0 != .automatic }
    }
}

public struct EvidenceReference: Codable, Equatable, Sendable, Identifiable {
    public var timestamp: String
    public var speaker: String?
    public var excerpt: String

    public var id: String {
        [timestamp, speaker ?? "", excerpt].joined(separator: "|")
    }

    public init(timestamp: String, speaker: String? = nil, excerpt: String) {
        self.timestamp = timestamp
        self.speaker = speaker
        self.excerpt = excerpt
    }
}

public struct MeetingSummaryItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var evidence: [EvidenceReference]

    public init(id: String = UUID().uuidString, text: String, evidence: [EvidenceReference] = []) {
        self.id = id
        self.text = text
        self.evidence = evidence
    }
}

public struct MeetingSummary: Codable, Equatable, Sendable {
    public var overview: String
    public var keyPoints: [MeetingSummaryItem]
    public var openQuestions: [MeetingSummaryItem]

    public init(
        overview: String = "",
        keyPoints: [MeetingSummaryItem] = [],
        openQuestions: [MeetingSummaryItem] = []
    ) {
        self.overview = overview
        self.keyPoints = keyPoints
        self.openQuestions = openQuestions
    }

    public var isEmpty: Bool {
        overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && keyPoints.isEmpty
            && openQuestions.isEmpty
    }
}

public struct MeetingBookmark: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var timestamp: String
    public var label: String?
    public var createdAt: Date
    public var excerpt: String

    public init(
        id: String = UUID().uuidString,
        timestamp: String,
        label: String? = nil,
        createdAt: Date = Date(),
        excerpt: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.excerpt = excerpt
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
```

- [ ] **Step 4: Add D0 fields to settings, snapshot, patch, state, and request**

In `AppSettings`, add `meetingTypePreset` after `modelPreset` and include it in `init`, `CodingKeys`, and `init(from:)`.

```swift
public var meetingTypePreset: MeetingTypePreset
```

```swift
meetingTypePreset: MeetingTypePreset = .automatic,
```

```swift
self.meetingTypePreset = meetingTypePreset
```

```swift
case meetingTypePreset
```

```swift
meetingTypePreset: (try? container.decode(MeetingTypePreset.self, forKey: .meetingTypePreset)) ?? .automatic,
```

In `AnalysisSnapshot`, add fields before `currentIssue`, update `init`, `CodingKeys`, `init(from:)`, and `applyingPatch`.

```swift
public var meetingType: MeetingTypePreset
public var meetingSummary: MeetingSummary
```

```swift
public init(
    meetingType: MeetingTypePreset = .automatic,
    meetingSummary: MeetingSummary = MeetingSummary(),
    currentIssue: CurrentIssue = CurrentIssue(),
    topicTimeline: [TopicTimelineItem] = [],
    decisionCandidates: [DecisionCandidate] = [],
    actionItemCandidates: [ActionItemCandidate] = [],
    risksOrNotes: [String] = [],
    generatedAt: Date = Date(),
    provider: LLMProviderKind = .codexExec
) {
    self.meetingType = meetingType
    self.meetingSummary = meetingSummary
    self.currentIssue = currentIssue
    self.topicTimeline = topicTimeline
    self.decisionCandidates = decisionCandidates
    self.actionItemCandidates = actionItemCandidates
    self.risksOrNotes = risksOrNotes
    self.generatedAt = generatedAt
    self.provider = provider
}
```

```swift
case meetingType
case meetingSummary
```

```swift
self.meetingType = (try? container.decode(MeetingTypePreset.self, forKey: .meetingType)) ?? .automatic
self.meetingSummary = (try? container.decode(MeetingSummary.self, forKey: .meetingSummary)) ?? MeetingSummary()
```

At the start of `applyingPatch`, merge D0 patch fields.

```swift
if let meetingType = patch.meetingType {
    copy.meetingType = meetingType
}
if let meetingSummary = patch.meetingSummary {
    copy.meetingSummary = meetingSummary
}
```

In `AnalysisSnapshotPatch`, add nullable D0 fields with backward-compatible decode.

```swift
public var meetingType: MeetingTypePreset?
public var meetingSummary: MeetingSummary?
```

```swift
public init(
    meetingType: MeetingTypePreset? = nil,
    meetingSummary: MeetingSummary? = nil,
    currentIssue: CurrentIssue? = nil,
    topicTimelineUpserts: [TopicTimelineItem] = [],
    closeTopicIDs: [String] = [],
    decisionCandidateUpserts: [DecisionCandidate] = [],
    actionItemCandidateUpserts: [ActionItemCandidate] = [],
    risksOrNotesAppend: [String] = []
) {
    self.meetingType = meetingType
    self.meetingSummary = meetingSummary
    self.currentIssue = currentIssue
    self.topicTimelineUpserts = topicTimelineUpserts
    self.closeTopicIDs = closeTopicIDs
    self.decisionCandidateUpserts = decisionCandidateUpserts
    self.actionItemCandidateUpserts = actionItemCandidateUpserts
    self.risksOrNotesAppend = risksOrNotesAppend
}
```

Add a custom decoder so existing patch tests and old persisted outputs remain valid.

```swift
private enum CodingKeys: String, CodingKey {
    case meetingType
    case meetingSummary
    case currentIssue
    case topicTimelineUpserts
    case closeTopicIDs
    case decisionCandidateUpserts
    case actionItemCandidateUpserts
    case risksOrNotesAppend
}

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
        meetingType: try? container.decode(MeetingTypePreset.self, forKey: .meetingType),
        meetingSummary: try? container.decode(MeetingSummary.self, forKey: .meetingSummary),
        currentIssue: try? container.decodeIfPresent(CurrentIssue.self, forKey: .currentIssue),
        topicTimelineUpserts: (try? container.decode([TopicTimelineItem].self, forKey: .topicTimelineUpserts)) ?? [],
        closeTopicIDs: (try? container.decode([String].self, forKey: .closeTopicIDs)) ?? [],
        decisionCandidateUpserts: (try? container.decode([DecisionCandidate].self, forKey: .decisionCandidateUpserts)) ?? [],
        actionItemCandidateUpserts: (try? container.decode([ActionItemCandidate].self, forKey: .actionItemCandidateUpserts)) ?? [],
        risksOrNotesAppend: (try? container.decode([String].self, forKey: .risksOrNotesAppend)) ?? []
    )
}
```

In `MeetingAnalysisState`, add bookmarks to the model and decoder.

```swift
public var bookmarks: [MeetingBookmark]
```

```swift
bookmarks: [MeetingBookmark] = [],
```

```swift
self.bookmarks = bookmarks
```

```swift
case bookmarks
```

```swift
bookmarks: (try? container.decode([MeetingBookmark].self, forKey: .bookmarks)) ?? [],
```

Add these mutating helpers near the existing candidate state helpers.

```swift
public mutating func addBookmark(_ bookmark: MeetingBookmark) {
    guard !bookmarks.contains(where: { $0.id == bookmark.id }) else {
        return
    }
    bookmarks.append(bookmark)
}

public mutating func deleteBookmark(id: String) {
    bookmarks.removeAll { $0.id == id }
}
```

In `AnalysisRequest`, add fields and final output mode behavior.

```swift
public var meetingTypePreset: MeetingTypePreset
public var bookmarks: [MeetingBookmark]
```

```swift
meetingTypePreset: MeetingTypePreset = .automatic,
bookmarks: [MeetingBookmark] = [],
```

```swift
self.meetingTypePreset = meetingTypePreset
self.bookmarks = bookmarks
```

```swift
public static func usesFullSnapshotOutput(_ reason: String) -> Bool {
    reason.hasPrefix("repair") || reason.hasPrefix("full-refresh") || reason.hasPrefix("final")
}
```

- [ ] **Step 5: Run core tests to verify pass**

Run:

```bash
swift test --filter AnalysisStateTests
```

Expected: PASS.

- [ ] **Step 6: Commit core contract**

```bash
git add Sources/MeetingRescueCore/AnalysisModels.swift Tests/MeetingRescueCoreTests/AnalysisStateTests.swift
git commit -m "feat: add D0 meeting intelligence contract models"
```

---

### Task 2: Provider Schemas and Decode

**Files:**
- Modify: `Tests/MeetingRescueCoreTests/LLMProviderOutputTests.swift`
- Modify: `Sources/MeetingRescue/Resources/analysis-output.schema.json`
- Modify: `Sources/MeetingRescue/Resources/analysis-patch-output.schema.json`
- Modify: `Sources/MeetingRescueCore/LLMProvider.swift`
- Modify: `Sources/MeetingRescueCore/LocalAnalysisFallback.swift`

- [ ] **Step 1: Write failing provider output tests**

Append these tests inside `LLMProviderOutputTests`.

```swift
@Test("full snapshot provider output은 D0 meeting summary contract를 decode한다")
func fullSnapshotDecodesD0Contract() throws {
    let output = """
    {
      "meetingType": "decision",
      "meetingSummary": {
        "overview": "배포 방식을 결정하는 회의다.",
        "keyPoints": [
          {
            "id": "summary-release",
            "text": "금요일 배포로 수렴했다.",
            "evidence": [
              {
                "timestamp": "00:10",
                "speaker": "Alex",
                "excerpt": "금요일 배포로 갑시다."
              }
            ]
          }
        ],
        "openQuestions": []
      },
      "currentIssue": {
        "summary": "배포 owner 확인이 남았다.",
        "openQuestions": ["owner는 누구인가?"]
      },
      "topicTimeline": [],
      "decisionCandidates": [],
      "actionItemCandidates": [],
      "risksOrNotes": []
    }
    """
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[00:10] Alex: 금요일 배포로 갑시다.",
        reason: "final"
    )

    let snapshot = try decodeProviderOutput(from: output, request: request, provider: .codexExec)

    #expect(snapshot.meetingType == .decision)
    #expect(snapshot.meetingSummary.keyPoints.first?.evidence.first?.speaker == "Alex")
    #expect(snapshot.provider == .codexExec)
}

@Test("live patch provider output은 nullable D0 fields를 merge한다")
func livePatchMergesNullableD0Fields() throws {
    let output = """
    {
      "meetingType": "planning",
      "meetingSummary": {
        "overview": "계획 범위가 새로 정리됐다.",
        "keyPoints": [],
        "openQuestions": [
          {
            "id": "question-owner",
            "text": "디자인 owner를 확정해야 한다.",
            "evidence": [
              {
                "timestamp": "01:40",
                "speaker": "Blair",
                "excerpt": "디자인 owner는 아직 비어 있습니다."
              }
            ]
          }
        ]
      },
      "currentIssue": null,
      "topicTimelineUpserts": [],
      "closeTopicIDs": [],
      "decisionCandidateUpserts": [],
      "actionItemCandidateUpserts": [],
      "risksOrNotesAppend": []
    }
    """
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[01:40] Blair: 디자인 owner는 아직 비어 있습니다.",
        previousSnapshot: AnalysisSnapshot(
            meetingType: .automatic,
            meetingSummary: MeetingSummary(overview: "이전 요약"),
            currentIssue: CurrentIssue(summary: "기존 요약")
        ),
        reason: "automatic-min-dialogue-lines",
        lastAnalyzedTranscriptCharacterCount: 1
    )

    let snapshot = try decodeProviderOutput(from: output, request: request, provider: .claudeCode)

    #expect(snapshot.meetingType == .planning)
    #expect(snapshot.meetingSummary.overview == "계획 범위가 새로 정리됐다.")
    #expect(snapshot.meetingSummary.openQuestions.first?.evidence.first?.timestamp == "01:40")
}
```

- [ ] **Step 2: Run provider tests to verify failure**

Run:

```bash
swift test --filter LLMProviderOutputTests
```

Expected: FAIL until D0 fields are accepted and patch merge is wired.

- [ ] **Step 3: Update full snapshot schema**

In `Sources/MeetingRescue/Resources/analysis-output.schema.json`, change the top-level required list.

```json
"required": ["meetingType", "meetingSummary", "currentIssue", "topicTimeline", "decisionCandidates", "actionItemCandidates", "risksOrNotes"]
```

Add these top-level properties before `currentIssue`.

```json
"meetingType": {
  "enum": ["decision", "planning", "incident", "oneOnOne", "brainstorm", "status"]
},
"meetingSummary": {
  "type": "object",
  "additionalProperties": false,
  "required": ["overview", "keyPoints", "openQuestions"],
  "properties": {
    "overview": { "type": "string" },
    "keyPoints": {
      "type": "array",
      "maxItems": 6,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "text", "evidence"],
        "properties": {
          "id": { "type": "string" },
          "text": { "type": "string" },
          "evidence": {
            "type": "array",
            "maxItems": 3,
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["timestamp", "speaker", "excerpt"],
              "properties": {
                "timestamp": { "type": "string" },
                "speaker": { "type": ["string", "null"] },
                "excerpt": { "type": "string" }
              }
            }
          }
        }
      }
    },
    "openQuestions": {
      "type": "array",
      "maxItems": 6,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "text", "evidence"],
        "properties": {
          "id": { "type": "string" },
          "text": { "type": "string" },
          "evidence": {
            "type": "array",
            "maxItems": 3,
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["timestamp", "speaker", "excerpt"],
              "properties": {
                "timestamp": { "type": "string" },
                "speaker": { "type": ["string", "null"] },
                "excerpt": { "type": "string" }
              }
            }
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Update patch schema**

In `Sources/MeetingRescue/Resources/analysis-patch-output.schema.json`, change the top-level required list.

```json
"required": ["meetingType", "meetingSummary", "currentIssue", "topicTimelineUpserts", "closeTopicIDs", "decisionCandidateUpserts", "actionItemCandidateUpserts", "risksOrNotesAppend"]
```

Add nullable D0 properties before `currentIssue`.

```json
"meetingType": {
  "anyOf": [
    { "enum": ["decision", "planning", "incident", "oneOnOne", "brainstorm", "status"] },
    { "type": "null" }
  ]
},
"meetingSummary": {
  "anyOf": [
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["overview", "keyPoints", "openQuestions"],
      "properties": {
        "overview": { "type": "string", "maxLength": 500 },
        "keyPoints": {
          "type": "array",
          "maxItems": 4,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "text", "evidence"],
            "properties": {
              "id": { "type": "string" },
              "text": { "type": "string", "maxLength": 260 },
              "evidence": {
                "type": "array",
                "maxItems": 3,
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["timestamp", "speaker", "excerpt"],
                  "properties": {
                    "timestamp": { "type": "string" },
                    "speaker": { "type": ["string", "null"] },
                    "excerpt": { "type": "string", "maxLength": 220 }
                  }
                }
              }
            }
          }
        },
        "openQuestions": {
          "type": "array",
          "maxItems": 4,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "text", "evidence"],
            "properties": {
              "id": { "type": "string" },
              "text": { "type": "string", "maxLength": 220 },
              "evidence": {
                "type": "array",
                "maxItems": 3,
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["timestamp", "speaker", "excerpt"],
                  "properties": {
                    "timestamp": { "type": "string" },
                    "speaker": { "type": ["string", "null"] },
                    "excerpt": { "type": "string", "maxLength": 220 }
                  }
                }
              }
            }
          }
        }
      }
    },
    { "type": "null" }
  ]
}
```

- [ ] **Step 5: Keep provider decode focused on existing normalization**

`LLMProvider.swift` should not synthesize summary evidence. After Task 1, `decodeSnapshot` and `decodePatch` can decode D0 fields. Keep only existing candidate id and topic end timestamp normalization.

Confirm this code path remains unchanged except any compiler adjustments from new initializers:

```swift
func decodeProviderOutput(
    from output: String,
    request: AnalysisRequest,
    provider: LLMProviderKind
) throws -> AnalysisSnapshot {
    switch request.outputMode {
    case .fullSnapshot:
        return try decodeSnapshot(from: output, provider: provider)
    case .livePatch:
        guard let previousSnapshot = request.previousSnapshot else {
            throw LLMProviderError.invalidOutput
        }
        let patch = try decodePatch(from: output, request: request)
        return previousSnapshot.applyingPatch(patch, provider: provider)
    }
}
```

- [ ] **Step 6: Fill D0 fields in local fallback**

In `LocalAnalysisFallback.snapshot(for:message:)`, pass request meeting type and a minimal evidence summary.

```swift
let fallbackEvidence = dialogue.last.map {
    EvidenceReference(timestamp: $0.timestamp, speaker: $0.speaker, excerpt: $0.text)
}
let meetingSummary = MeetingSummary(
    overview: summary,
    keyPoints: fallbackEvidence.map {
        [
            MeetingSummaryItem(
                id: "local-summary-latest",
                text: "최근 발화를 기준으로 provider 결과를 기다리는 중입니다.",
                evidence: [$0]
            )
        ]
    } ?? [],
    openQuestions: [
        MeetingSummaryItem(
            id: "local-question-provider",
            text: "LLM provider 연결 또는 schema 오류를 확인해야 합니다.",
            evidence: fallbackEvidence.map { [$0] } ?? []
        )
    ]
)

return AnalysisSnapshot(
    meetingType: request.meetingTypePreset,
    meetingSummary: meetingSummary,
    currentIssue: CurrentIssue(
        summary: summary,
        openQuestions: ["LLM provider 연결 또는 schema 오류를 확인해야 합니다."]
    ),
    topicTimeline: timeline,
    decisionCandidates: [],
    actionItemCandidates: [],
    risksOrNotes: [
        "Fallback reason: \(message)",
        speakerNote.isEmpty ? "최근 speaker 정보를 아직 만들 수 없습니다." : "최근 주요 speaker: \(speakerNote)"
    ],
    provider: request.providerKind
)
```

- [ ] **Step 7: Run provider and schema tests**

Run:

```bash
swift test --filter LLMProviderOutputTests
swift test --filter SchemaTests
```

Expected: PASS.

- [ ] **Step 8: Commit provider contract**

```bash
git add Sources/MeetingRescue/Resources/analysis-output.schema.json Sources/MeetingRescue/Resources/analysis-patch-output.schema.json Sources/MeetingRescueCore/LLMProvider.swift Sources/MeetingRescueCore/LocalAnalysisFallback.swift Tests/MeetingRescueCoreTests/LLMProviderOutputTests.swift
git commit -m "feat: enforce D0 analysis output schema"
```

---

### Task 3: Prompt Contract

**Files:**
- Modify: `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`
- Modify: `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`

- [ ] **Step 1: Replace final analysis prompt test**

In `AnalysisPromptBuilderTests`, replace `finalAnalysisUsesPatchPromptWhenSnapshotExists` with this test.

```swift
@Test("final analysis with previous snapshot asks for full wrap-up output")
func finalAnalysisUsesFullWrapUpPromptWhenSnapshotExists() throws {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[10:00] Alex: 기존 내용\n[20:00] Alex: 후반부 결정 후보",
        previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
        reason: "final",
        lastAnalyzedTranscriptCharacterCount: 18
    )

    let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

    #expect(request.outputMode == .fullSnapshot)
    #expect(prompt.contains("meetingSummary"))
    #expect(prompt.contains("회의 전체 wrap-up"))
    #expect(prompt.contains("후반부 결정 후보"))
    #expect(!prompt.contains("전체 AnalysisSnapshot을 쓰지 마세요"))
}
```

- [ ] **Step 2: Add prompt payload tests for meeting type and bookmarks**

Append these tests inside `AnalysisPromptBuilderTests`.

```swift
@Test("prompt payload includes meeting type preset and bookmarks")
func promptIncludesMeetingTypePresetAndBookmarks() throws {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[00:10] Alex: 금요일 배포 기준으로 보겠습니다.",
        meetingTypePreset: .decision,
        bookmarks: [
            MeetingBookmark(
                id: "bookmark-1",
                timestamp: "[00:10]",
                label: "결정 기준",
                createdAt: Date(timeIntervalSince1970: 10),
                excerpt: "금요일 배포 기준으로 보겠습니다."
            )
        ]
    )

    let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

    #expect(prompt.contains(#""meetingTypePreset":"decision""#))
    #expect(prompt.contains(#""bookmarks""#))
    #expect(prompt.contains("결정 기준"))
    #expect(prompt.contains("bookmark 주변 발화를 summary evidence로 우선 고려하세요"))
}

@Test("full prompt explains current issue as live focus and summary as whole-meeting wrap-up")
func fullPromptSeparatesLiveFocusAndWrapUp() throws {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[00:10] Alex: 사고 원인을 봅니다.",
        meetingTypePreset: .incident
    )

    let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

    #expect(prompt.contains("currentIssue는 현재 논점 또는 Live Focus입니다"))
    #expect(prompt.contains("meetingSummary는 회의 전체 wrap-up입니다"))
    #expect(prompt.contains("meetingType이 incident이면 증상, 영향, 원인 가설, mitigation"))
}
```

- [ ] **Step 3: Run prompt tests to verify failure**

Run:

```bash
swift test --filter AnalysisPromptBuilderTests
```

Expected: FAIL until prompt payload and instructions are updated.

- [ ] **Step 4: Add D0 fields to prompt payload**

In `AnalysisPromptBuilder.buildPrompt(for:)`, pass `request.meetingTypePreset` and `request.bookmarks`.

```swift
let payload = PromptPayload(
    meetingMetadata: promptMetadata(from: request.metadata, transcriptContext: transcriptContext),
    meetingTypePreset: request.meetingTypePreset,
    bookmarks: compactBookmarks(request.bookmarks),
    transcriptContext: transcriptContext,
    contextPlan: request.contextPlan,
    previousAnalysisSnapshot: compactSnapshot(from: request.previousSnapshot),
    confirmedCandidateIDs: Array(request.confirmedCandidateIDs).sorted(),
    deletedCandidateIDs: Array(request.deletedCandidateIDs).sorted()
)
```

Update `PromptPayload`.

```swift
private struct PromptPayload: Encodable {
    var meetingMetadata: MeetingMetadata
    var meetingTypePreset: MeetingTypePreset
    var bookmarks: [MeetingBookmark]
    var transcriptContext: TranscriptContext
    var contextPlan: AnalysisContextPlan?
    var previousAnalysisSnapshot: AnalysisSnapshot?
    var confirmedCandidateIDs: [String]
    var deletedCandidateIDs: [String]
}
```

Add a helper near `compactSnapshot`.

```swift
private static func compactBookmarks(_ bookmarks: [MeetingBookmark]) -> [MeetingBookmark] {
    Array(bookmarks.suffix(12))
}
```

Update `compactSnapshot(from:)` to keep summary compact.

```swift
snapshot.meetingSummary.keyPoints = Array(snapshot.meetingSummary.keyPoints.prefix(4))
snapshot.meetingSummary.openQuestions = Array(snapshot.meetingSummary.openQuestions.prefix(4))
for index in snapshot.meetingSummary.keyPoints.indices {
    snapshot.meetingSummary.keyPoints[index].evidence = Array(snapshot.meetingSummary.keyPoints[index].evidence.prefix(2))
}
for index in snapshot.meetingSummary.openQuestions.indices {
    snapshot.meetingSummary.openQuestions[index].evidence = Array(snapshot.meetingSummary.openQuestions[index].evidence.prefix(2))
}
```

- [ ] **Step 5: Update full snapshot prompt text**

In `fullSnapshotPrompt(payloadJSON:)`, replace the guidance body with this D0 contract language while preserving existing timestamp and size rules.

```swift
"""
당신은 실시간 회의 분석 assistant입니다. 모든 사용자-facing 응답은 한글로 작성하세요.

아래 payload만 근거로 지정된 JSON schema의 JSON 객체 하나만 반환하세요.
fullTranscript가 있으면 첫 분석입니다. 제공된 범위로 작고 읽기 쉬운 snapshot을 만드세요.
newTranscriptChunk가 있으면 primary source로 쓰고 recentTranscriptContext/relatedTranscriptChunks는 연결 맥락으로만 쓰세요.
final/full-refresh에서는 회의 전체 wrap-up을 다시 구성하세요.
과거 맥락을 새 결정처럼 반복하지 말고, 불확실하면 candidate/note/openQuestions로 남기세요.

meetingTypePreset이 automatic이면 transcript를 보고 meetingType을 decision/planning/incident/oneOnOne/brainstorm/status 중 하나로 추정하세요.
meetingTypePreset이 automatic이 아니면 그 값을 meetingType으로 사용하세요.
meetingType이 decision이면 선택지, 판단 기준, 결정 근거, 남은 승인자를 우선 정리하세요.
meetingType이 planning이면 목표, 범위, 일정, owner, dependency를 우선 정리하세요.
meetingType이 incident이면 증상, 영향, 원인 가설, mitigation, follow-up을 우선 정리하세요.
meetingType이 oneOnOne이면 관심사, 피드백, 약속, 다음 대화를 우선 정리하세요.
meetingType이 brainstorm이면 아이디어, 가설, 근거, 수렴 지점을 우선 정리하세요.
meetingType이 status이면 진행 상황, block, 다음 action, escalation을 우선 정리하세요.

meetingSummary는 회의 전체 wrap-up입니다. overview는 2-4문장으로 작성하고, keyPoints/openQuestions는 각 항목마다 evidence를 1개 이상 붙이세요.
evidence.timestamp는 원문 회의 경과 시간만 사용하세요. 예: "04:13" 또는 "[04:13]". ISO 날짜를 만들지 마세요.
evidence.excerpt는 payload 원문에서 근거가 되는 짧은 발화 일부를 그대로 옮기세요.
bookmarks가 있으면 bookmark 주변 발화를 summary evidence로 우선 고려하세요.
currentIssue는 현재 논점 또는 Live Focus입니다. meetingSummary와 중복되는 전체 요약을 쓰지 마세요.
topicTimeline은 시간순이며 agenda/논점/대상/실행 방향이 바뀌면 나누세요. 전체 6개 이하를 권장합니다.
currentIssue.summary는 2-4문장, decision/action 후보는 각각 6개 이하로 간결하게 유지하세요.
optional 값은 null 또는 빈 배열로 채우세요.

Payload:
\(payloadJSON)
"""
```

- [ ] **Step 6: Update live patch prompt text**

In `livePatchPrompt(payloadJSON:)`, add D0 patch rules.

```swift
"""
당신은 실시간 회의 분석 assistant입니다. 모든 사용자-facing 응답은 한글로 작성하세요.

아래 payload만 근거로 지정된 JSON schema의 JSON patch 객체 하나만 반환하세요.
전체 AnalysisSnapshot을 쓰지 마세요. 이번 newTranscriptChunk 때문에 추가/수정할 항목만 patch로 반환하세요.
meetingType은 automatic 추정이 새로 확실해졌거나 수동 preset과 맞춰야 할 때만 채우고, 변화가 없으면 null로 두세요.
meetingSummary는 이번 chunk 또는 bookmark 때문에 회의 전체 결론, 핵심 포인트, 열린 질문이 바뀌었을 때만 채우고, 변화가 없으면 null로 두세요.
meetingSummary를 채울 때는 evidence.timestamp/speaker/excerpt를 함께 채우세요.
currentIssue는 현재 논점 또는 Live Focus입니다. 실제 변화가 있을 때만 채우고, 변화가 작으면 null로 두세요.
단, previousAnalysisSnapshot.currentIssue.summary가 비어 있으면 이번 chunk의 핵심 논점으로 currentIssue를 반드시 채우세요.
topicTimelineUpserts/decisionCandidateUpserts/actionItemCandidateUpserts/risksOrNotesAppend는 보통 0-2개, 최대 3개로 제한하세요.
기존 후보/노트/토픽을 반복하지 말고, confirmed/deleted 상태를 되돌리지 마세요.
relatedTranscriptChunks는 생략된 현재 회의 맥락 연결용입니다. 관련성이 낮으면 무시하세요.
timestamp는 원문 회의 경과 시간만 사용하세요. 예: "04:13" 또는 "[04:13]". ISO 날짜를 만들지 마세요.
topicTimelineUpserts의 startTimestamp와 endTimestamp는 둘 다 채우세요. 한 발화짜리 topic이면 같은 timestamp를 넣으세요.
optional 값은 null 또는 빈 배열로 채우세요.

Payload:
\(payloadJSON)
"""
```

- [ ] **Step 7: Run prompt tests**

Run:

```bash
swift test --filter AnalysisPromptBuilderTests
```

Expected: PASS.

- [ ] **Step 8: Commit prompt contract**

```bash
git add Sources/MeetingRescueCore/AnalysisPromptBuilder.swift Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift
git commit -m "feat: prompt for D0 meeting wrap-up contract"
```

---

### Task 4: App Settings, Requests, and Bookmarks

**Files:**
- Modify: `Sources/MeetingRescue/AppViewModel.swift`
- Modify: `Sources/MeetingRescue/ContentView.swift`
- Modify: `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`

- [ ] **Step 1: Add a settings decode test**

Append this test inside `AnalysisStateTests`.

```swift
@Test("AppSettings stores meeting type preset with automatic legacy default")
func appSettingsStoresMeetingTypePreset() throws {
    let legacyJSON = #"{"selectedProvider":"codexExec"}"#
    let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))
    #expect(legacy.meetingTypePreset == .automatic)

    let settings = AppSettings(meetingTypePreset: .incident)
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    #expect(decoded.meetingTypePreset == .incident)
}
```

- [ ] **Step 2: Run settings test to verify failure**

Run:

```bash
swift test --filter AnalysisStateTests.appSettingsStoresMeetingTypePreset
```

Expected: FAIL until `AppSettings` initializer and Codable wiring include `meetingTypePreset`.

- [ ] **Step 3: Wire settings save and update**

In `AppViewModel.saveSettings()`, include `meetingTypePreset`.

```swift
settings = AppSettings(
    selectedProvider: settings.selectedProvider,
    codexExecutionMode: settings.codexExecutionMode,
    codexAppServerDiagnosticsEnabled: settings.codexAppServerDiagnosticsEnabled,
    modelPreset: settings.modelPreset,
    meetingTypePreset: settings.meetingTypePreset,
    automaticAnalysisEnabled: settings.automaticAnalysisEnabled,
    hasCompletedOnboarding: settings.hasCompletedOnboarding,
    analysisTriggerPreset: settings.analysisTriggerPreset,
    analysisCadenceSeconds: settings.analysisCadenceSeconds,
    providerTimeoutSeconds: settings.providerTimeoutSeconds,
    liveContextRetrievalMode: settings.liveContextRetrievalMode,
    customProviderCommand: settings.customProviderCommand
)
```

Add an update method near `updateModelPreset`.

```swift
func updateMeetingTypePreset(_ preset: MeetingTypePreset) {
    settings.meetingTypePreset = preset
    saveSettings()
}
```

- [ ] **Step 4: Pass meeting type and bookmarks into every analysis request**

In `refreshTestRunFallbackIfNeeded(message:)`, add these parameters to `AnalysisRequest`.

```swift
meetingTypePreset: settings.meetingTypePreset,
bookmarks: analysisState.bookmarks,
```

In `triggerAnalysis(reason:)`, add the same parameters to `AnalysisRequest`.

```swift
meetingTypePreset: settings.meetingTypePreset,
bookmarks: analysisState.bookmarks,
```

- [ ] **Step 5: Add live bookmark methods to the view model**

In `AppViewModel`, add these public methods near `triggerManualAnalysis()`.

```swift
var canAddLiveBookmark: Bool {
    activeTranscriptURL != nil && !rawTranscriptPreviewLines.isEmpty
}

func addLiveBookmark(label: String? = nil) {
    guard let activeTranscriptURL, canAddLiveBookmark else {
        statusMessage = "북마크할 transcript가 없습니다."
        return
    }

    let seconds = latestTranscriptElapsedSeconds()
    let bookmark = MeetingBookmark(
        timestamp: elapsedTimestamp(seconds),
        label: label,
        excerpt: latestTranscriptExcerpt()
    )
    analysisState.addBookmark(bookmark)
    analysisState.updatedAt = Date()
    try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
    statusMessage = "북마크 저장: \(bookmark.timestamp)"
}

func deleteLiveBookmark(id: String) {
    guard let activeTranscriptURL else {
        return
    }
    analysisState.deleteBookmark(id: id)
    analysisState.updatedAt = Date()
    try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
    statusMessage = "북마크를 삭제했습니다."
}
```

Add private helpers near `latestTranscriptElapsedSeconds()`.

```swift
private func elapsedTimestamp(_ seconds: Int) -> String {
    let total = max(0, seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "[%02d:%02d:%02d]", hours, minutes, seconds)
    }
    return String(format: "[%02d:%02d]", minutes, seconds)
}

private func latestTranscriptExcerpt() -> String {
    rawTranscriptPreviewLines
        .reversed()
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? ""
}
```

- [ ] **Step 6: Run targeted tests and build**

Run:

```bash
swift test --filter AnalysisStateTests
swift build
```

Expected: PASS. `swift build` may fail until the UI bindings in Task 6 are added; if it fails only on `ContentView` missing `meetingTypePresetBinding`, continue to Task 6 before re-running.

- [ ] **Step 7: Commit request wiring**

```bash
git add Sources/MeetingRescue/AppViewModel.swift Tests/MeetingRescueCoreTests/AnalysisStateTests.swift
git commit -m "feat: wire meeting type and live bookmarks"
```

---

### Task 5: Markdown Exporter

**Files:**
- Modify: `Tests/MeetingRescueCoreTests/MarkdownExporterTests.swift`
- Modify: `Sources/MeetingRescueCore/MeetingIntelligenceMarkdownExporter.swift`

- [ ] **Step 1: Update Markdown test for wrap-up evidence**

In `MarkdownExporterTests.exportsMarkdown`, update the snapshot setup to include a D0 summary.

```swift
latestSnapshot: AnalysisSnapshot(
    meetingType: .decision,
    meetingSummary: MeetingSummary(
        overview: "배포 방식과 follow-up을 정리한 회의다.",
        keyPoints: [
            MeetingSummaryItem(
                id: "summary-release",
                text: "금요일 배포로 수렴했다.",
                evidence: [
                    EvidenceReference(
                        timestamp: "00:10",
                        speaker: "A",
                        excerpt: "금요일 배포로 진행합니다."
                    )
                ]
            )
        ],
        openQuestions: [
            MeetingSummaryItem(
                id: "question-owner",
                text: "롤백 owner를 확정해야 한다.",
                evidence: [
                    EvidenceReference(
                        timestamp: "00:20",
                        speaker: "B",
                        excerpt: "롤백 owner는 아직 없습니다."
                    )
                ]
            )
        ]
    ),
    currentIssue: CurrentIssue(summary: "요약"),
    topicTimeline: [
        TopicTimelineItem(
            id: "topic-1",
            startTimestamp: "2025-12-29T17:05:28Z",
            title: "논의",
            summary: "내용"
        )
    ],
    decisionCandidates: [
        DecisionCandidate(id: "decision-1", text: "원문 결정", status: .confirmed, evidenceTimestamp: "00:10")
    ],
    actionItemCandidates: [
        ActionItemCandidate(id: "action-1", assignee: "A", task: "원문 액션", deadline: "금요일", status: .confirmed, evidenceTimestamp: "00:20")
    ]
)
```

Replace and add expectations.

```swift
#expect(markdown.contains("## 회의 요약"))
#expect(markdown.contains("- 유형: Decision"))
#expect(markdown.contains("배포 방식과 follow-up을 정리한 회의다."))
#expect(markdown.contains("- 금요일 배포로 수렴했다. ([00:10] · A · 금요일 배포로 진행합니다.)"))
#expect(markdown.contains("### 열린 질문"))
#expect(markdown.contains("- 롤백 owner를 확정해야 한다. ([00:20] · B · 롤백 owner는 아직 없습니다.)"))
#expect(markdown.contains("## 현재 논점"))
#expect(!markdown.contains("## 현재 이슈"))
```

- [ ] **Step 2: Run Markdown test to verify failure**

Run:

```bash
swift test --filter MarkdownExporterTests
```

Expected: FAIL until exporter adds the new sections and label.

- [ ] **Step 3: Implement wrap-up Markdown section**

In `MeetingIntelligenceMarkdownExporter.markdown(...)`, replace the `## 현재 이슈` block with this order: meeting summary, current focus, flow.

```swift
appendMeetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType, to: &lines, metadata: metadata)
lines.append("")

lines.append("## 현재 논점")
lines.append("")
lines.append(snapshot.currentIssue.summary.isEmpty ? "-" : snapshot.currentIssue.summary)
if !snapshot.currentIssue.openQuestions.isEmpty {
    lines.append("")
    lines.append("### 열린 질문")
    for question in snapshot.currentIssue.openQuestions {
        lines.append("- \(question)")
    }
}
lines.append("")
```

Add helpers below `markdown(...)`.

```swift
private static func appendMeetingSummary(
    _ summary: MeetingSummary,
    meetingType: MeetingTypePreset,
    to lines: inout [String],
    metadata: MeetingMetadata
) {
    lines.append("## 회의 요약")
    lines.append("")
    lines.append("- 유형: \(meetingType.displayName)")
    lines.append("")
    lines.append(summary.overview.isEmpty ? "-" : summary.overview)

    if !summary.keyPoints.isEmpty {
        lines.append("")
        lines.append("### 핵심 포인트")
        for item in summary.keyPoints {
            lines.append("- \(item.text) \(summaryEvidenceText(item.evidence, metadata: metadata))")
        }
    }

    if !summary.openQuestions.isEmpty {
        lines.append("")
        lines.append("### 열린 질문")
        for item in summary.openQuestions {
            lines.append("- \(item.text) \(summaryEvidenceText(item.evidence, metadata: metadata))")
        }
    }
}

private static func summaryEvidenceText(_ evidence: [EvidenceReference], metadata: MeetingMetadata) -> String {
    guard let first = evidence.first else {
        return ""
    }
    let timestamp = MeetingTimestampFormatter.display(first.timestamp, meetingDateTime: metadata.dateTime)
    let speaker = first.speaker.map { " · \($0)" } ?? ""
    let excerpt = first.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
    let excerptText = excerpt.isEmpty ? "" : " · \(excerpt)"
    return "(\(timestamp)\(speaker)\(excerptText))"
}
```

- [ ] **Step 4: Run Markdown test**

Run:

```bash
swift test --filter MarkdownExporterTests
```

Expected: PASS.

- [ ] **Step 5: Commit Markdown export**

```bash
git add Sources/MeetingRescueCore/MeetingIntelligenceMarkdownExporter.swift Tests/MeetingRescueCoreTests/MarkdownExporterTests.swift
git commit -m "feat: export evidence-backed meeting wrap-up"
```

---

### Task 6: SwiftUI Meeting Intelligence UI

**Files:**
- Modify: `Sources/MeetingRescue/ContentView.swift`
- Modify: `Sources/MeetingRescue/AppViewModel.swift`

- [ ] **Step 1: Add meeting type picker binding**

In `ContentView`, add this binding near `modelPresetBinding`.

```swift
private var meetingTypePresetBinding: Binding<MeetingTypePreset> {
    Binding {
        viewModel.settings.meetingTypePreset
    } set: { value in
        viewModel.updateMeetingTypePreset(value)
    }
}
```

- [ ] **Step 2: Add meeting type setting row**

In `analysisSettings`, insert this row after `Analysis trigger`.

```swift
settingsRow("Meeting type", detail: viewModel.settings.meetingTypePreset.detail) {
    Picker("meeting type", selection: meetingTypePresetBinding) {
        ForEach(MeetingTypePreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
        }
    }
    .labelsHidden()
    .frame(width: 180)
}
```

- [ ] **Step 3: Add bookmark header button**

In `fullHeaderActions`, insert `bookmarkHeaderButton` after `analysisHeaderButton`.

```swift
analysisHeaderButton
bookmarkHeaderButton
issueDraftMenu
```

Add this view near `analysisHeaderButton`.

```swift
private var bookmarkHeaderButton: some View {
    Menu {
        Button {
            viewModel.addLiveBookmark()
        } label: {
            Label("일반", systemImage: "bookmark")
        }

        Button {
            viewModel.addLiveBookmark(label: "결정")
        } label: {
            Label("결정", systemImage: "checkmark.seal")
        }

        Button {
            viewModel.addLiveBookmark(label: "액션")
        } label: {
            Label("액션", systemImage: "person.crop.circle.badge.checkmark")
        }

        Button {
            viewModel.addLiveBookmark(label: "열린 질문")
        } label: {
            Label("열린 질문", systemImage: "questionmark.circle")
        }
    } label: {
        Label("Bookmark", systemImage: "bookmark")
            .font(.callout.weight(.semibold))
            .lineLimit(1)
    }
    .buttonStyle(SmoothActionButtonStyle())
    .menuStyle(.button)
    .controlSize(.regular)
    .disabled(!viewModel.canAddLiveBookmark)
    .keyboardShortcut("b", modifiers: [.command])
}
```

In `compactActionsMenu`, add the same four bookmark actions before the Markdown action.

```swift
Button {
    viewModel.addLiveBookmark()
} label: {
    Label("Bookmark", systemImage: "bookmark")
}
.disabled(!viewModel.canAddLiveBookmark)

Menu("Quick bookmark") {
    Button("결정") { viewModel.addLiveBookmark(label: "결정") }
    Button("액션") { viewModel.addLiveBookmark(label: "액션") }
    Button("열린 질문") { viewModel.addLiveBookmark(label: "열린 질문") }
}
.disabled(!viewModel.canAddLiveBookmark)
```

- [ ] **Step 4: Rename current issue UI label**

In `currentIssue(_:)`, change the label text.

```swift
Label("현재 논점", systemImage: "dot.radiowaves.left.and.right")
```

- [ ] **Step 5: Add meeting summary card to overview**

In `overview(_:)`, render the summary before metrics and after current focus.

```swift
currentIssue(snapshot.currentIssue)
meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)
if !viewModel.analysisState.bookmarks.isEmpty {
    bookmarks(viewModel.analysisState.bookmarks)
}
metricsRow(snapshot)
```

Add these views near `currentIssue(_:)`.

```swift
@ViewBuilder
private func meetingSummary(_ summary: MeetingSummary, meetingType: MeetingTypePreset) -> some View {
    if !summary.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("회의 요약", systemImage: "text.badge.checkmark")
                    .font(.headline)
                Spacer()
                Text(meetingType.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.smoothAccent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.smoothAccent)
            }

            if !summary.overview.isEmpty {
                Text(summary.overview)
                    .font(.callout)
                    .foregroundStyle(Color.smoothInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !summary.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.keyPoints.prefix(4)) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                if let evidence = item.evidence.first {
                                    Text(summaryEvidenceText(evidence))
                                        .font(.caption)
                                        .foregroundStyle(Color.smoothMuted)
                                }
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                        .font(.callout)
                    }
                }
            }

            if !summary.openQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.openQuestions.prefix(3)) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                if let evidence = item.evidence.first {
                                    Text(summaryEvidenceText(evidence))
                                        .font(.caption)
                                        .foregroundStyle(Color.smoothMuted)
                                }
                            }
                        } icon: {
                            Image(systemName: "questionmark.circle")
                        }
                        .font(.callout)
                        .foregroundStyle(Color.smoothMuted)
                    }
                }
            }
        }
        .smoothCard(tint: Color.smoothAccent)
    }
}

private func summaryEvidenceText(_ evidence: EvidenceReference) -> String {
    let timestamp = MeetingTimestampFormatter.display(evidence.timestamp, meetingDateTime: viewModel.metadata.dateTime)
    let speaker = evidence.speaker.map { " · \($0)" } ?? ""
    let excerpt = evidence.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
    let excerptText = excerpt.isEmpty ? "" : " · \(excerpt)"
    return "\(timestamp)\(speaker)\(excerptText)"
}
```

- [ ] **Step 6: Add bookmark list to overview**

Add this view near the summary views.

```swift
private func bookmarks(_ bookmarks: [MeetingBookmark]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Label("Bookmarks", systemImage: "bookmark")
                .font(.headline)
            Spacer()
            Text("\(bookmarks.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)
        }

        ForEach(bookmarks.suffix(6)) { bookmark in
            HStack(alignment: .top, spacing: 8) {
                Text(MeetingTimestampFormatter.display(bookmark.timestamp, meetingDateTime: viewModel.metadata.dateTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.smoothAccent)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.label ?? "Bookmark")
                        .font(.callout.weight(.semibold))
                    if !bookmark.excerpt.isEmpty {
                        Text(bookmark.excerpt)
                            .font(.caption)
                            .foregroundStyle(Color.smoothMuted)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    viewModel.deleteLiveBookmark(id: bookmark.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("북마크 삭제")
            }
        }
    }
    .smoothCard(tint: Color.smoothAccent)
}
```

- [ ] **Step 7: Run UI build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 8: Commit UI**

```bash
git add Sources/MeetingRescue/ContentView.swift Sources/MeetingRescue/AppViewModel.swift
git commit -m "feat: show D0 wrap-up and live bookmarks"
```

---

### Task 7: End-to-End Verification and Backlog State

**Files:**
- Modify: `tasks.md` (local ignored backlog file)
- Read: `execution-log.md`

- [ ] **Step 1: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Run app build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Manual smoke with Test Run**

Run the app from Xcode or the local build, then verify these behaviors with an existing `.txt` transcript:

```text
1. Settings > Meeting Intelligence > Meeting type에서 Auto와 Incident/Decision 등 manual preset이 선택된다.
2. Manual analysis 또는 Test Run analysis prompt에 meetingTypePreset과 bookmarks가 포함된다.
3. Meeting Intelligence overview에서 "현재 논점"과 "회의 요약"이 동시에 보인다.
4. Bookmark 버튼 또는 Cmd+B로 현재 transcript timestamp가 저장된다.
5. 저장된 bookmark가 overview에 표시되고 다음 analysis request의 payload에 포함된다.
6. Markdown export에 "## 회의 요약", "## 현재 논점", summary evidence가 포함된다.
```

- [ ] **Step 4: Update backlog status**

In `tasks.md`, keep D0 under `Next` until the implementation ships. After tests and smoke pass, update only the D0 subsection status text by adding this line under `D0 Meeting Intelligence contract`.

```markdown
  - D0 Meeting Intelligence contract:
    - 상태: `Done`
```

If D1 planning starts before shipping D0, leave D0 as `In Progress` and add the exact blocking note under D0.

```markdown
    - 상태: `In Progress`
    - 남은 검증: Test Run smoke에서 bookmark evidence가 final summary에 반영되는지 확인한다.
```

- [ ] **Step 5: Record verification result**

Do not commit `tasks.md` unless the repository changes its ignore policy or the user explicitly asks to track the backlog file. Leave the local backlog update visible in `git status --ignored=matching -- tasks.md` as an ignored local planning artifact.

---

## Self-Review

- Spec coverage: Meeting Type Preset is covered by `MeetingTypePreset`, settings picker, prompt payload, schema output, and request wiring. Evidence-backed Wrap-up is covered by `MeetingSummary`, `EvidenceReference`, full/final output mode, prompt/schema, UI, and Markdown export. Live Bookmark is covered by `MeetingBookmark`, persisted state, header/menu UI, request payload, and overview list.
- Dependency order: core models first, provider schema second, prompt third, app wiring fourth, export/UI after contract. This lets D1/D2 features consume stable fields without reworking the contract.
- Type consistency: the plan uses `meetingTypePreset` for settings/request input, `meetingType` for snapshot/provider output, `meetingSummary` for wrap-up, and `bookmarks` for per-meeting user evidence anchors.
- Backward compatibility: old snapshots, old patches, and old settings decode with defaults. New provider schema still requires all declared properties so `SchemaTests` remains meaningful.
