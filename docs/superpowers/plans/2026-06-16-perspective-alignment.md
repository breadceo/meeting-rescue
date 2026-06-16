# Perspective Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an evidence-backed "관점 정렬" card to Meeting Intelligence so users can see when participants hold different views on the current issue and what question would move the meeting forward.

**Architecture:** Extend `AnalysisSnapshot` and live patch output with `perspectiveAlignments`, keep the field evidence-first and optional, and render it in the Overview lane directly after "현재 논점" and before "회의 요약". Full snapshots replace the list; live patches keep the previous list when the provider returns `null`, replace it when the provider returns an array, and allow an empty array to clear resolved alignments.

**Tech Stack:** Swift, SwiftUI, Swift Testing, existing JSON-schema constrained provider output, existing Meeting Intelligence markdown/search indexing.

---

## Product Placement

Place the feature in the existing `요약` lane, not as a new top-level lane.

Current `overview(_:)` order in `Sources/MeetingRescue/ContentView.swift` is:

1. `currentIssue(snapshot.currentIssue)`
2. `meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)`
3. bookmarks, metrics, decisions, actions, timeline, notes, usage, diagnostics

New order:

1. `currentIssue(snapshot.currentIssue)`
2. `perspectiveAlignments(snapshot.activePerspectiveAlignments)`
3. `meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)`
4. existing remaining sections

Rationale:

- "현재 논점" answers: what are we discussing now?
- "관점 정렬" answers: why has this not converged yet?
- "회의 요약" answers: what happened overall?

Display the section only when there is at least one active alignment with two evidence-backed perspectives. The empty state should not render; a missing/weak alignment should disappear rather than show explanatory UI.

Use the user-facing label `관점 정렬`, not `갈등`, `대립`, or `A vs B`. The card should frame the issue as a decision-support aid, not interpersonal conflict.

---

## File Structure

- Modify: `Sources/MeetingRescueCore/AnalysisModels.swift`
  - Add `PerspectiveAlignment` and `PerspectivePosition` models.
  - Add `perspectiveAlignments` to `AnalysisSnapshot`.
  - Add nullable `perspectiveAlignments` to `AnalysisSnapshotPatch`.
  - Add display filtering and live patch replacement semantics.

- Modify: `Sources/MeetingRescueCore/CandidateIDGenerator.swift`
  - Add stable ID generation for provider outputs that omit perspective alignment IDs.

- Modify: `Sources/MeetingRescueCore/LLMProvider.swift`
  - Backfill missing perspective alignment IDs in full snapshot and live patch output.

- Modify: `Sources/MeetingRescue/Resources/analysis-output.schema.json`
  - Add strict `perspectiveAlignments` to full snapshot schema.

- Modify: `Sources/MeetingRescue/Resources/analysis-patch-output.schema.json`
  - Add nullable strict `perspectiveAlignments` to live patch schema.

- Modify: `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`
  - Instruct the model to emit this field only when two distinct participant perspectives have direct transcript evidence.

- Modify: `Sources/MeetingRescue/ContentView.swift`
  - Render `관점 정렬` card in Overview after `currentIssue`.

- Modify: `Sources/MeetingRescueCore/MeetingIntelligenceMarkdownExporter.swift`
  - Export `관점 정렬` after current issue.

- Modify: `Sources/MeetingRescue/AppViewModel.swift`
  - Add perspective alignment text to meeting history search sections in both duplicated section builders.

- Modify: `Sources/MeetingRescueCore/MeetingHistorySearch.swift`
  - Add `.perspectiveAlignment` search field with display name `관점 정렬`.

- Modify tests:
  - `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`
  - `Tests/MeetingRescueCoreTests/LLMProviderOutputTests.swift`
  - `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`
  - `Tests/MeetingRescueCoreTests/MarkdownExporterTests.swift`
  - `Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift`
  - `Tests/MeetingRescueTests/ContentViewContextWiringTests.swift` or create `Tests/MeetingRescueTests/ContentViewPerspectiveAlignmentTests.swift`

- Modify docs:
  - `README.md`
  - `CHANGELOG.md`

---

### Task 1: Add Core Models and Patch Semantics

**Files:**
- Modify: `Sources/MeetingRescueCore/AnalysisModels.swift`
- Test: `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`

- [ ] **Step 1: Write failing decode and merge tests**

Add these tests to `AnalysisStateTests`.

```swift
@Test("snapshot decodes evidence-backed perspective alignments")
func decodesPerspectiveAlignments() throws {
    let json = """
    {
      "meetingType": "decision",
      "meetingSummary": {
        "overview": "릴리즈 범위를 논의했다.",
        "keyPoints": [],
        "openQuestions": []
      },
      "currentIssue": {
        "summary": "이번 릴리즈에 실험 기능을 포함할지 논의 중이다.",
        "openQuestions": []
      },
      "perspectiveAlignments": [
        {
          "id": "alignment-release-scope",
          "topic": "실험 기능 릴리즈 범위",
          "axis": "속도와 안정성의 균형",
          "sharedGround": "이번 주 안에 릴리즈 범위를 정해야 한다.",
          "nextQuestion": "오늘 결정할 최소 릴리즈 범위는 어디까지인가?",
          "perspectives": [
            {
              "speaker": "Alex",
              "summary": "이번 릴리즈에 포함해야 한다.",
              "reasoning": "사용자 피드백을 빨리 받아야 한다.",
              "evidence": [
                {
                  "timestamp": "02:10",
                  "speaker": "Alex",
                  "excerpt": "이번에 넣어야 피드백을 받을 수 있어요."
                }
              ]
            },
            {
              "speaker": "Blair",
              "summary": "다음 릴리즈로 미뤄야 한다.",
              "reasoning": "QA 시간이 부족하다.",
              "evidence": [
                {
                  "timestamp": "02:40",
                  "speaker": "Blair",
                  "excerpt": "QA 시간이 부족해서 다음으로 미루는 게 안전해요."
                }
              ]
            }
          ]
        }
      ],
      "topicTimeline": [],
      "decisionCandidates": [],
      "actionItemCandidates": [],
      "risksOrNotes": []
    }
    """

    let snapshot = try JSONDecoder().decode(AnalysisSnapshot.self, from: Data(json.utf8))

    #expect(snapshot.perspectiveAlignments.first?.topic == "실험 기능 릴리즈 범위")
    #expect(snapshot.activePerspectiveAlignments.count == 1)
    #expect(snapshot.activePerspectiveAlignments.first?.perspectives.map(\.speaker) == ["Alex", "Blair"])
}

@Test("live patch keeps, replaces, and clears perspective alignments")
func livePatchMergesPerspectiveAlignments() {
    let alignment = PerspectiveAlignment(
        id: "alignment-release-scope",
        topic: "실험 기능 릴리즈 범위",
        axis: "속도와 안정성의 균형",
        sharedGround: "이번 주 안에 범위를 정해야 한다.",
        nextQuestion: "최소 릴리즈 범위는 어디까지인가?",
        perspectives: [
            PerspectivePosition(
                speaker: "Alex",
                summary: "이번 릴리즈에 포함해야 한다.",
                reasoning: "피드백을 빨리 받아야 한다.",
                evidence: [EvidenceReference(timestamp: "02:10", speaker: "Alex", excerpt: "이번에 넣어야 피드백을 받을 수 있어요.")]
            ),
            PerspectivePosition(
                speaker: "Blair",
                summary: "다음 릴리즈로 미뤄야 한다.",
                reasoning: "QA 시간이 부족하다.",
                evidence: [EvidenceReference(timestamp: "02:40", speaker: "Blair", excerpt: "QA 시간이 부족해요.")]
            )
        ]
    )
    let previous = AnalysisSnapshot(perspectiveAlignments: [alignment])

    let kept = previous.applyingPatch(AnalysisSnapshotPatch(perspectiveAlignments: nil), provider: .codexExec)
    #expect(kept.perspectiveAlignments.map(\.id) == ["alignment-release-scope"])

    let cleared = previous.applyingPatch(AnalysisSnapshotPatch(perspectiveAlignments: []), provider: .codexExec)
    #expect(cleared.perspectiveAlignments.isEmpty)
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
swift test --filter AnalysisStateTests/decodesPerspectiveAlignments
swift test --filter AnalysisStateTests/livePatchMergesPerspectiveAlignments
```

Expected: FAIL because `PerspectiveAlignment`, `PerspectivePosition`, `perspectiveAlignments`, and `activePerspectiveAlignments` do not exist.

- [ ] **Step 3: Add models and snapshot field**

In `AnalysisModels.swift`, add these models near `CurrentIssue` and before `TopicTimelineItem`.

```swift
public struct PerspectivePosition: Codable, Equatable, Sendable, Identifiable {
    public var speaker: String
    public var summary: String
    public var reasoning: String
    public var evidence: [EvidenceReference]

    public var id: String {
        [speaker, summary].joined(separator: "|")
    }

    public init(
        speaker: String,
        summary: String,
        reasoning: String = "",
        evidence: [EvidenceReference] = []
    ) {
        self.speaker = speaker
        self.summary = summary
        self.reasoning = reasoning
        self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey {
        case speaker
        case summary
        case reasoning
        case evidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            speaker: (try? container.decode(String.self, forKey: .speaker)) ?? "",
            summary: (try? container.decode(String.self, forKey: .summary)) ?? "",
            reasoning: (try? container.decode(String.self, forKey: .reasoning)) ?? "",
            evidence: (try? container.decode([EvidenceReference].self, forKey: .evidence)) ?? []
        )
    }
}

public struct PerspectiveAlignment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var topic: String
    public var axis: String
    public var sharedGround: String
    public var nextQuestion: String
    public var perspectives: [PerspectivePosition]

    public init(
        id: String,
        topic: String,
        axis: String,
        sharedGround: String = "",
        nextQuestion: String,
        perspectives: [PerspectivePosition] = []
    ) {
        self.id = id
        self.topic = topic
        self.axis = axis
        self.sharedGround = sharedGround
        self.nextQuestion = nextQuestion
        self.perspectives = perspectives
    }

    public var isDisplayable: Bool {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuestion = nextQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidenceBacked = perspectives.filter { perspective in
            !perspective.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !perspective.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !perspective.evidence.isEmpty
        }
        return !trimmedTopic.isEmpty && !trimmedQuestion.isEmpty && evidenceBacked.count >= 2
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case topic
        case axis
        case sharedGround
        case nextQuestion
        case perspectives
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decode(String.self, forKey: .id)) ?? "",
            topic: (try? container.decode(String.self, forKey: .topic)) ?? "",
            axis: (try? container.decode(String.self, forKey: .axis)) ?? "",
            sharedGround: (try? container.decode(String.self, forKey: .sharedGround)) ?? "",
            nextQuestion: (try? container.decode(String.self, forKey: .nextQuestion)) ?? "",
            perspectives: (try? container.decode([PerspectivePosition].self, forKey: .perspectives)) ?? []
        )
    }
}
```

Update `AnalysisSnapshot`:

```swift
public var perspectiveAlignments: [PerspectiveAlignment]
```

Add it to the initializer after `currentIssue`:

```swift
perspectiveAlignments: [PerspectiveAlignment] = [],
```

Assign it:

```swift
self.perspectiveAlignments = perspectiveAlignments
```

Add it to `CodingKeys`:

```swift
case perspectiveAlignments
```

Decode with a legacy-safe default:

```swift
self.perspectiveAlignments = (try? container.decode([PerspectiveAlignment].self, forKey: .perspectiveAlignments)) ?? []
```

Add this computed property to `AnalysisSnapshot`:

```swift
public var activePerspectiveAlignments: [PerspectiveAlignment] {
    Array(perspectiveAlignments.filter(\.isDisplayable).prefix(2))
}
```

- [ ] **Step 4: Add patch field and replacement semantics**

Update `AnalysisSnapshotPatch` with:

```swift
public var perspectiveAlignments: [PerspectiveAlignment]?
```

Add to initializer:

```swift
perspectiveAlignments: [PerspectiveAlignment]? = nil,
```

Assign:

```swift
self.perspectiveAlignments = perspectiveAlignments
```

Add to `CodingKeys`:

```swift
case perspectiveAlignments
```

Decode:

```swift
perspectiveAlignments: try container.decodeIfPresent([PerspectiveAlignment].self, forKey: .perspectiveAlignments),
```

In `AnalysisSnapshot.applyingPatch(_:provider:)`, after current issue handling and before timeline upserts, add:

```swift
if let perspectiveAlignments = patch.perspectiveAlignments {
    copy.perspectiveAlignments = Array(perspectiveAlignments.filter(\.isDisplayable).prefix(2))
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter AnalysisStateTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeetingRescueCore/AnalysisModels.swift Tests/MeetingRescueCoreTests/AnalysisStateTests.swift
git commit -m "feat: add perspective alignment models"
```

---

### Task 2: Update Provider Schemas and Decode ID Backfill

**Files:**
- Modify: `Sources/MeetingRescue/Resources/analysis-output.schema.json`
- Modify: `Sources/MeetingRescue/Resources/analysis-patch-output.schema.json`
- Modify: `Sources/MeetingRescueCore/CandidateIDGenerator.swift`
- Modify: `Sources/MeetingRescueCore/LLMProvider.swift`
- Test: `Tests/MeetingRescueCoreTests/LLMProviderOutputTests.swift`
- Test: `Tests/MeetingRescueCoreTests/SchemaTests.swift`

- [ ] **Step 1: Add failing provider output tests**

Add to `LLMProviderOutputTests`.

```swift
@Test("full snapshot provider output decodes perspective alignments")
func fullSnapshotDecodesPerspectiveAlignments() throws {
    let output = """
    {
      "meetingType": "decision",
      "meetingSummary": {
        "overview": "릴리즈 범위를 논의했다.",
        "keyPoints": [],
        "openQuestions": []
      },
      "currentIssue": {
        "summary": "이번 릴리즈에 실험 기능을 포함할지 논의 중이다.",
        "openQuestions": []
      },
      "perspectiveAlignments": [
        {
          "id": "",
          "topic": "실험 기능 릴리즈 범위",
          "axis": "속도와 안정성의 균형",
          "sharedGround": "이번 주 안에 범위를 정해야 한다.",
          "nextQuestion": "오늘 결정할 최소 릴리즈 범위는 어디까지인가?",
          "perspectives": [
            {
              "speaker": "Alex",
              "summary": "이번 릴리즈에 포함해야 한다.",
              "reasoning": "사용자 피드백을 빨리 받아야 한다.",
              "evidence": [
                {
                  "timestamp": "02:10",
                  "speaker": "Alex",
                  "excerpt": "이번에 넣어야 피드백을 받을 수 있어요."
                }
              ]
            },
            {
              "speaker": "Blair",
              "summary": "다음 릴리즈로 미뤄야 한다.",
              "reasoning": "QA 시간이 부족하다.",
              "evidence": [
                {
                  "timestamp": "02:40",
                  "speaker": "Blair",
                  "excerpt": "QA 시간이 부족해요."
                }
              ]
            }
          ]
        }
      ],
      "topicTimeline": [],
      "decisionCandidates": [],
      "actionItemCandidates": [],
      "risksOrNotes": []
    }
    """
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[02:10] Alex: 이번에 넣어야 피드백을 받을 수 있어요.\n[02:40] Blair: QA 시간이 부족해요.",
        reason: "final"
    )

    let snapshot = try decodeProviderOutput(from: output, request: request, provider: .codexExec)

    #expect(snapshot.activePerspectiveAlignments.count == 1)
    #expect(snapshot.activePerspectiveAlignments.first?.id.hasPrefix("alignment-") == true)
}

@Test("live patch provider output replaces perspective alignments when array is present")
func livePatchReplacesPerspectiveAlignments() throws {
    let patchOutput = """
    {
      "meetingType": null,
      "meetingSummary": null,
      "currentIssue": null,
      "perspectiveAlignments": [],
      "topicTimelineUpserts": [],
      "closeTopicIDs": [],
      "decisionCandidateUpserts": [],
      "actionItemCandidateUpserts": [],
      "risksOrNotesAppend": []
    }
    """
    let previous = PerspectiveAlignment(
        id: "alignment-existing",
        topic: "기존 관점",
        axis: "범위",
        nextQuestion: "무엇을 정할까?",
        perspectives: [
            PerspectivePosition(speaker: "A", summary: "포함", evidence: [EvidenceReference(timestamp: "00:10", speaker: "A", excerpt: "넣죠.")]),
            PerspectivePosition(speaker: "B", summary: "제외", evidence: [EvidenceReference(timestamp: "00:20", speaker: "B", excerpt: "빼죠.")])
        ]
    )
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[00:30] Alex: 정리됐습니다.",
        previousSnapshot: AnalysisSnapshot(perspectiveAlignments: [previous]),
        reason: "automatic-min-dialogue-lines",
        lastAnalyzedTranscriptCharacterCount: 0
    )

    let snapshot = try decodeProviderOutput(from: patchOutput, request: request, provider: .codexExec)

    #expect(snapshot.perspectiveAlignments.isEmpty)
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
swift test --filter LLMProviderOutputTests/fullSnapshotDecodesPerspectiveAlignments
swift test --filter LLMProviderOutputTests/livePatchReplacesPerspectiveAlignments
```

Expected: FAIL because schemas and decode logic do not yet support the field.

- [ ] **Step 3: Add ID generator**

In `CandidateIDGenerator.swift`, add:

```swift
public static func perspectiveAlignmentID(topic: String, axis: String, evidenceTimestamp: String) -> String {
    stableID(prefix: "alignment", text: "\(topic)|\(axis)", evidenceTimestamp: evidenceTimestamp)
}
```

- [ ] **Step 4: Backfill IDs in provider decode**

In `LLMProvider.swift`, add helper functions near `decodeSnapshot`.

```swift
private func normalizedPerspectiveAlignments(_ alignments: [PerspectiveAlignment]) -> [PerspectiveAlignment] {
    alignments.map { alignment in
        var alignment = alignment
        if alignment.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let timestamp = alignment.perspectives
                .flatMap(\.evidence)
                .first?
                .timestamp ?? ""
            alignment.id = CandidateIDGenerator.perspectiveAlignmentID(
                topic: alignment.topic,
                axis: alignment.axis,
                evidenceTimestamp: timestamp
            )
        }
        return alignment
    }
}
```

In `decodeSnapshot`, before `return snapshot`, add:

```swift
snapshot.perspectiveAlignments = normalizedPerspectiveAlignments(snapshot.perspectiveAlignments)
```

In `decodePatch`, before `return patch`, add:

```swift
if let alignments = patch.perspectiveAlignments {
    patch.perspectiveAlignments = normalizedPerspectiveAlignments(alignments)
}
```

- [ ] **Step 5: Update full output schema**

In `analysis-output.schema.json`:

1. Add `"perspectiveAlignments"` to the top-level `required` array after `"currentIssue"`.
2. Add a top-level property after `currentIssue`:

```json
"perspectiveAlignments": {
  "type": "array",
  "maxItems": 2,
  "items": {
    "type": "object",
    "additionalProperties": false,
    "required": ["id", "topic", "axis", "sharedGround", "nextQuestion", "perspectives"],
    "properties": {
      "id": { "type": "string" },
      "topic": { "type": "string" },
      "axis": { "type": "string" },
      "sharedGround": { "type": "string" },
      "nextQuestion": { "type": "string" },
      "perspectives": {
        "type": "array",
        "minItems": 2,
        "maxItems": 2,
        "items": {
          "type": "object",
          "additionalProperties": false,
          "required": ["speaker", "summary", "reasoning", "evidence"],
          "properties": {
            "speaker": { "type": "string" },
            "summary": { "type": "string" },
            "reasoning": { "type": "string" },
            "evidence": {
              "type": "array",
              "minItems": 1,
              "maxItems": 2,
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
}
```

- [ ] **Step 6: Update live patch schema**

In `analysis-patch-output.schema.json`:

1. Add `"perspectiveAlignments"` to the top-level `required` array after `"currentIssue"`.
2. Add a top-level nullable property after `currentIssue`:

```json
"perspectiveAlignments": {
  "anyOf": [
    {
      "type": "array",
      "maxItems": 2,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "topic", "axis", "sharedGround", "nextQuestion", "perspectives"],
        "properties": {
          "id": { "type": "string" },
          "topic": { "type": "string", "maxLength": 120 },
          "axis": { "type": "string", "maxLength": 120 },
          "sharedGround": { "type": "string", "maxLength": 180 },
          "nextQuestion": { "type": "string", "maxLength": 180 },
          "perspectives": {
            "type": "array",
            "minItems": 2,
            "maxItems": 2,
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["speaker", "summary", "reasoning", "evidence"],
              "properties": {
                "speaker": { "type": "string", "maxLength": 80 },
                "summary": { "type": "string", "maxLength": 180 },
                "reasoning": { "type": "string", "maxLength": 180 },
                "evidence": {
                  "type": "array",
                  "minItems": 1,
                  "maxItems": 2,
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
      }
    },
    { "type": "null" }
  ]
}
```

- [ ] **Step 7: Run schema and provider tests**

Run:

```bash
swift test --filter SchemaTests
swift test --filter LLMProviderOutputTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/MeetingRescue/Resources/analysis-output.schema.json Sources/MeetingRescue/Resources/analysis-patch-output.schema.json Sources/MeetingRescueCore/CandidateIDGenerator.swift Sources/MeetingRescueCore/LLMProvider.swift Tests/MeetingRescueCoreTests/LLMProviderOutputTests.swift
git commit -m "feat: support perspective alignment provider output"
```

---

### Task 3: Prompt the Model Conservatively

**Files:**
- Modify: `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`
- Test: `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`

- [ ] **Step 1: Add failing prompt tests**

Add to `AnalysisPromptBuilderTests`.

```swift
@Test("full snapshot prompt asks for evidence-backed perspective alignments")
func fullSnapshotPromptIncludesPerspectiveAlignmentRules() {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[00:10] Alex: 이번에 넣죠.\n[00:20] Blair: QA가 부족해요.",
        reason: "final"
    )

    let prompt = AnalysisPromptBuilder.prompt(for: request)

    #expect(prompt.contains("perspectiveAlignments"))
    #expect(prompt.contains("관점 정렬"))
    #expect(prompt.contains("서로 다른 speaker"))
    #expect(prompt.contains("직접 evidence"))
    #expect(prompt.contains("갈등이나 대립으로 과장하지 마세요"))
}

@Test("live patch prompt explains null versus empty perspective alignment semantics")
func livePatchPromptIncludesPerspectiveAlignmentPatchRules() {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "Room"),
        rawTranscript: "[00:10] Alex: 새 내용",
        previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
        reason: "automatic-min-dialogue-lines",
        lastAnalyzedTranscriptCharacterCount: 0
    )

    let prompt = AnalysisPromptBuilder.prompt(for: request)

    #expect(prompt.contains("perspectiveAlignments는 변화가 없으면 null"))
    #expect(prompt.contains("해소되었으면 빈 배열"))
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
swift test --filter AnalysisPromptBuilderTests/fullSnapshotPromptIncludesPerspectiveAlignmentRules
swift test --filter AnalysisPromptBuilderTests/livePatchPromptIncludesPerspectiveAlignmentPatchRules
```

Expected: FAIL because prompt rules do not mention the new field.

- [ ] **Step 3: Update full snapshot prompt**

In `fullSnapshotPrompt(payloadJSON:)`, after the `currentIssue` instructions, add:

```swift
        perspectiveAlignments는 관점 정렬 카드입니다. 하나의 사안에서 서로 다른 speaker가 다른 판단 기준, 선호, 우려, 제약을 말했고 그 차이가 현재 논점이나 결정 후보의 수렴을 막을 때만 채우세요.
        갈등이나 대립으로 과장하지 마세요. 사람을 평가하지 말고 "속도와 안정성", "범위와 일정", "사용자 영향 판단"처럼 정렬해야 할 기준을 axis로 쓰세요.
        각 perspective는 서로 다른 speaker의 직접 evidence를 1개 이상 가져야 합니다. 직접 evidence가 부족하거나 단순 보충 의견이면 perspectiveAlignments는 빈 배열로 두세요.
        nextQuestion은 회의 진행자가 바로 물을 수 있는 한 문장 질문이어야 합니다.
```

- [ ] **Step 4: Update live patch prompt**

In `livePatchPrompt(payloadJSON:)`, after the `currentIssue` instructions, add:

```swift
        perspectiveAlignments는 변화가 없으면 null로 두세요. 새 관점 차이가 생겼거나 기존 관점 차이가 해소되어 목록을 바꿔야 할 때만 배열로 채우세요. 해소되었으면 빈 배열로 명시하세요.
        관점 차이는 서로 다른 speaker의 직접 evidence가 각각 1개 이상 있을 때만 포함하세요. 약한 뉘앙스를 갈등이나 대립으로 과장하지 마세요.
```

- [ ] **Step 5: Run prompt tests**

Run:

```bash
swift test --filter AnalysisPromptBuilderTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeetingRescueCore/AnalysisPromptBuilder.swift Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift
git commit -m "feat: prompt perspective alignment conservatively"
```

---

### Task 4: Render in the Overview Lane

**Files:**
- Modify: `Sources/MeetingRescue/ContentView.swift`
- Test: `Tests/MeetingRescueTests/ContentViewPerspectiveAlignmentTests.swift`

- [ ] **Step 1: Add static UI wiring tests**

Create `Tests/MeetingRescueTests/ContentViewPerspectiveAlignmentTests.swift`.

```swift
import Foundation
import Testing

@Suite("ContentView perspective alignment wiring")
struct ContentViewPerspectiveAlignmentTests {
    @Test("overview renders perspective alignment between current issue and meeting summary")
    func overviewRendersPerspectiveAlignmentAfterCurrentIssue() throws {
        let source = try String(contentsOfFile: "Sources/MeetingRescue/ContentView.swift", encoding: .utf8)
        let overview = try #require(source.slice(from: "private func overview(_ snapshot: AnalysisSnapshot)", to: "private func workflow("))

        #expect(overview.contains("currentIssue(snapshot.currentIssue)"))
        #expect(overview.contains("perspectiveAlignments(snapshot.activePerspectiveAlignments)"))
        #expect(overview.contains("meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)"))
        #expect(overview.range(of: "currentIssue(snapshot.currentIssue)")?.lowerBound ?? overview.startIndex < overview.range(of: "perspectiveAlignments(snapshot.activePerspectiveAlignments)")?.lowerBound ?? overview.endIndex)
        #expect(overview.range(of: "perspectiveAlignments(snapshot.activePerspectiveAlignments)")?.lowerBound ?? overview.startIndex < overview.range(of: "meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)")?.lowerBound ?? overview.endIndex)
    }

    @Test("perspective alignment section uses product-safe language")
    func perspectiveAlignmentUsesSafeLanguage() throws {
        let source = try String(contentsOfFile: "Sources/MeetingRescue/ContentView.swift", encoding: .utf8)
        let section = try #require(source.slice(from: "private func perspectiveAlignments", to: "private func currentIssue"))

        #expect(section.contains("관점 정렬"))
        #expect(section.contains("정렬 질문"))
        #expect(!section.contains("갈등"))
        #expect(!section.contains("대립"))
    }
}

private extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex) else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
swift test --filter ContentViewPerspectiveAlignmentTests
```

Expected: FAIL because the UI helper is not implemented.

- [ ] **Step 3: Wire the section into Overview**

In `overview(_:)`, insert the new section directly after `currentIssue(snapshot.currentIssue)`.

```swift
currentIssue(snapshot.currentIssue)
perspectiveAlignments(snapshot.activePerspectiveAlignments)
meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)
```

- [ ] **Step 4: Add the SwiftUI helper**

Add this helper before `currentIssue(_:)`.

```swift
@ViewBuilder
private func perspectiveAlignments(_ alignments: [PerspectiveAlignment]) -> some View {
    if !alignments.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("관점 정렬", systemImage: "arrow.left.and.right.text.vertical")
                    .font(.headline)
                Spacer()
                Text("\(alignments.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.smoothMint.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.smoothMint)
            }

            ForEach(alignments) { alignment in
                VStack(alignment: .leading, spacing: 8) {
                    Text(alignment.topic)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.smoothInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if !alignment.axis.isEmpty {
                        Text(alignment.axis)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.smoothMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(alignment.perspectives.prefix(2)) { perspective in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(perspective.speaker): \(perspective.summary)")
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !perspective.reasoning.isEmpty {
                                        Text(perspective.reasoning)
                                            .font(.caption)
                                            .foregroundStyle(Color.smoothMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if let evidence = perspective.evidence.first {
                                        Text(summaryEvidenceText(evidence))
                                            .font(.caption)
                                            .foregroundStyle(Color.smoothMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            } icon: {
                                Image(systemName: "person.crop.circle")
                            }
                            .font(.callout)
                        }
                    }

                    if !alignment.sharedGround.isEmpty {
                        Label(alignment.sharedGround, systemImage: "equal.circle")
                            .font(.caption)
                            .foregroundStyle(Color.smoothMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Label(alignment.nextQuestion, systemImage: "questionmark.bubble")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.smoothInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .smoothCard(tint: Color.smoothMint)
    }
}
```

If `arrow.left.and.right.text.vertical` is unavailable for the repo's macOS target, use `arrow.left.and.right` instead.

- [ ] **Step 5: Run UI wiring tests**

Run:

```bash
swift test --filter ContentViewPerspectiveAlignmentTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MeetingRescue/ContentView.swift Tests/MeetingRescueTests/ContentViewPerspectiveAlignmentTests.swift
git commit -m "feat: show perspective alignment in overview"
```

---

### Task 5: Export and Search Perspective Alignments

**Files:**
- Modify: `Sources/MeetingRescueCore/MeetingIntelligenceMarkdownExporter.swift`
- Modify: `Sources/MeetingRescueCore/MeetingHistorySearch.swift`
- Modify: `Sources/MeetingRescue/AppViewModel.swift`
- Test: `Tests/MeetingRescueCoreTests/MarkdownExporterTests.swift`
- Test: `Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift`

- [ ] **Step 1: Add failing markdown export expectations**

In `MarkdownExporterTests.exportsMarkdown`, add a `perspectiveAlignments` value to the test snapshot.

```swift
perspectiveAlignments: [
    PerspectiveAlignment(
        id: "alignment-release-scope",
        topic: "실험 기능 릴리즈 범위",
        axis: "속도와 안정성의 균형",
        sharedGround: "이번 주 안에 범위를 정해야 한다.",
        nextQuestion: "오늘 결정할 최소 릴리즈 범위는 어디까지인가?",
        perspectives: [
            PerspectivePosition(
                speaker: "A",
                summary: "이번 릴리즈에 포함해야 한다.",
                reasoning: "피드백을 빨리 받아야 한다.",
                evidence: [EvidenceReference(timestamp: "00:30", speaker: "A", excerpt: "이번에 넣죠.")]
            ),
            PerspectivePosition(
                speaker: "B",
                summary: "다음 릴리즈로 미뤄야 한다.",
                reasoning: "QA 시간이 부족하다.",
                evidence: [EvidenceReference(timestamp: "00:40", speaker: "B", excerpt: "QA가 부족해요.")]
            )
        ]
    )
],
```

Add expectations:

```swift
#expect(markdown.contains("## 관점 정렬"))
#expect(markdown.contains("### 실험 기능 릴리즈 범위"))
#expect(markdown.contains("- 축: 속도와 안정성의 균형"))
#expect(markdown.contains("- A: 이번 릴리즈에 포함해야 한다."))
#expect(markdown.contains("- 정렬 질문: 오늘 결정할 최소 릴리즈 범위는 어디까지인가?"))
```

- [ ] **Step 2: Add failing search field tests**

In `MeetingHistorySearchTests`, add or extend a section weighting test so it covers a new field.

```swift
@Test("perspective alignment field has display name")
func perspectiveAlignmentFieldDisplayName() {
    #expect(MeetingHistorySearchField.perspectiveAlignment.displayName == "관점 정렬")
}
```

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
swift test --filter MarkdownExporterTests
swift test --filter MeetingHistorySearchTests/perspectiveAlignmentFieldDisplayName
```

Expected: FAIL because export/search support is missing.

- [ ] **Step 4: Export markdown section**

In `MeetingIntelligenceMarkdownExporter.markdown(...)`, after the current issue block and before `## 흐름`, add:

```swift
appendPerspectiveAlignments(snapshot.activePerspectiveAlignments, to: &lines, metadata: metadata)
lines.append("")
```

Add helper:

```swift
private static func appendPerspectiveAlignments(
    _ alignments: [PerspectiveAlignment],
    to lines: inout [String],
    metadata: MeetingMetadata
) {
    guard !alignments.isEmpty else {
        return
    }

    lines.append("## 관점 정렬")
    for alignment in alignments {
        lines.append("")
        lines.append("### \(alignment.topic)")
        if !alignment.axis.isEmpty {
            lines.append("- 축: \(alignment.axis)")
        }
        if !alignment.sharedGround.isEmpty {
            lines.append("- 공통 전제: \(alignment.sharedGround)")
        }
        for perspective in alignment.perspectives.prefix(2) {
            let evidence = summaryEvidenceText(perspective.evidence, metadata: metadata)
            let reasoning = perspective.reasoning.isEmpty ? "" : " / 근거: \(perspective.reasoning)"
            lines.append("- \(perspective.speaker): \(perspective.summary)\(reasoning) \(evidence)")
        }
        lines.append("- 정렬 질문: \(alignment.nextQuestion)")
    }
}
```

- [ ] **Step 5: Add search field**

In `MeetingHistorySearchField`, add:

```swift
case perspectiveAlignment
```

Add display name:

```swift
case .perspectiveAlignment:
    return "관점 정렬"
```

- [ ] **Step 6: Index perspective alignment sections**

In both duplicated `AppViewModel` search-section builders, after current issue indexing and before topic indexing, add:

```swift
for alignment in snapshot.activePerspectiveAlignments {
    let perspectiveText = alignment.perspectives
        .map { "\($0.speaker) \($0.summary) \($0.reasoning)" }
        .joined(separator: " ")
    sections.append(
        .init(
            field: .perspectiveAlignment,
            text: "\(alignment.topic) \(alignment.axis) \(alignment.sharedGround) \(alignment.nextQuestion) \(perspectiveText)",
            weight: 76,
            timestamp: alignment.perspectives.flatMap(\.evidence).first?.timestamp
        )
    )
}
```

- [ ] **Step 7: Run export/search tests**

Run:

```bash
swift test --filter MarkdownExporterTests
swift test --filter MeetingHistorySearchTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/MeetingRescueCore/MeetingIntelligenceMarkdownExporter.swift Sources/MeetingRescueCore/MeetingHistorySearch.swift Sources/MeetingRescue/AppViewModel.swift Tests/MeetingRescueCoreTests/MarkdownExporterTests.swift Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift
git commit -m "feat: export and search perspective alignments"
```

---

### Task 6: Docs and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README feature list**

In `README.md`, update the Meeting Intelligence bullet list near the top from:

```markdown
- current issue, topic timeline, decision/action 후보 표시
```

to:

```markdown
- current issue, 관점 정렬, topic timeline, decision/action 후보 표시
```

In the Markdown export included-content list, add:

```markdown
- perspective alignment / 관점 정렬
```

- [ ] **Step 2: Update changelog**

At the top of `CHANGELOG.md` under the unreleased/current section, add:

```markdown
- Meeting Intelligence 요약 탭에 `관점 정렬` 카드를 추가해 현재 논점에서 참석자 관점 차이와 다음 정렬 질문을 evidence와 함께 볼 수 있게 했습니다.
```

- [ ] **Step 3: Run targeted tests**

Run:

```bash
swift test --filter AnalysisStateTests
swift test --filter LLMProviderOutputTests
swift test --filter AnalysisPromptBuilderTests
swift test --filter MarkdownExporterTests
swift test --filter MeetingHistorySearchTests
swift test --filter ContentViewPerspectiveAlignmentTests
swift test --filter SchemaTests
```

Expected: all PASS.

- [ ] **Step 4: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Run the app for visual smoke**

Run:

```bash
swift run MeetingRescue
```

Expected:

- App launches.
- Overview lane still shows `현재 논점`.
- A meeting with no perspective alignment does not show an empty `관점 정렬` card.
- A test fixture/provider output with two evidence-backed perspectives shows `관점 정렬` between `현재 논점` and `회의 요약`.
- The card text wraps without overlapping in narrow and wide layouts.

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: document perspective alignment"
```

---

## Acceptance Criteria

- `관점 정렬` appears only in the Overview lane after `현재 논점`.
- The feature never renders an empty placeholder.
- Each displayed alignment has:
  - topic
  - axis
  - two speaker-labeled perspectives
  - at least one transcript evidence item per perspective
  - shared ground when available
  - one next alignment question
- Prompt language avoids conflict framing and requires direct evidence.
- Live patch semantics are stable:
  - `null` keeps previous alignments.
  - `[]` clears alignments.
  - non-empty array replaces alignments.
- Markdown export includes active alignments.
- Meeting history search indexes alignment topic, axis, shared ground, next question, and perspective text.
- Legacy snapshots decode with `perspectiveAlignments == []`.
- All targeted and full tests pass.

## Self-Review

- Spec coverage: product placement, data contract, provider schema, prompt behavior, UI rendering, export, search, docs, and verification are covered.
- Placeholder scan: no `TBD`, `TODO`, or "similar to" instructions remain.
- Type consistency: plan consistently uses `PerspectiveAlignment`, `PerspectivePosition`, `perspectiveAlignments`, and `activePerspectiveAlignments`.
