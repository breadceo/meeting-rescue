# D1 Personal Meeting Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** D1 backlog의 Decision Coach, Share Readiness Check, Action Ledger, Open Question Carry-over를 local-first 개인 회의 워크플로우로 구현한다.

**Architecture:** `MeetingRescueCore`에 pure rule-based `PersonalWorkflowAnalyzer`를 추가하고, `AppViewModel`은 현재 회의 상태와 history 상태를 모아 analyzer 결과를 계산한다. SwiftUI는 기존 Meeting Intelligence 영역에 `워크플로우` 탭을 추가하며, export 전 readiness warning은 non-blocking preview로만 표시한다.

**Tech Stack:** Swift, SwiftUI, Swift Testing, Codable, existing `MeetingRescueCore` analysis state, Application Support session state.

---

## Scope

이 계획은 `tasks.md`의 `D1 Personal meeting workflow`만 다룬다. D2의 Calendar-linked identity, recurring meeting memory, team shared memory, Slack shared context, MCP context broker는 이 계획의 범위에 포함하지 않는다.

## Product Decisions

- Decision Coach는 LLM schema를 확장하지 않고 `AnalysisSnapshot`을 입력으로 받는 rule 기반 analyzer로 시작한다. 자동 interrupt는 만들지 않고 `워크플로우` 탭의 조용한 suggestion panel로 표시한다.
- Share Readiness Check는 Markdown 저장과 Slack preview의 전 단계에 쓸 수 있는 non-blocking checklist로 만든다. warning이 있어도 저장 버튼은 계속 사용할 수 있다.
- Action Ledger는 별도 저장소를 만들지 않고 현재 회의와 history의 `MeetingAnalysisState.latestSnapshot.actionItemCandidates` 중 confirmed action에서 계산한다.
- Open Question Carry-over는 D1에서 room, participant, topic/search text 기반 후보만 보여준다. 반복 회의 ID, calendar event, agenda context는 D2에서 붙인다.
- Carry-over dismiss/resolve 상태만 현재 회의의 `MeetingAnalysisState`에 저장한다. 과거 회의 state를 수정하지 않는다.

## File Structure

- Create `Sources/MeetingRescueCore/PersonalWorkflowModels.swift`: D1 workflow output models, action ledger source, carry-over source/status models.
- Create `Sources/MeetingRescueCore/PersonalWorkflowAnalyzer.swift`: snapshot/state/history를 받아 decision coach cards, readiness warnings, action ledger, carry-over candidates를 계산하는 pure analyzer.
- Modify `Sources/MeetingRescueCore/AnalysisModels.swift`: carry-over dismiss/resolve ID set과 상태 변경 method를 `MeetingAnalysisState`에 추가한다.
- Create `Tests/MeetingRescueCoreTests/PersonalWorkflowAnalyzerTests.swift`: analyzer rule coverage와 carry-over state persistence coverage.
- Modify `Sources/MeetingRescue/AppViewModel.swift`: workflow snapshot 계산, history state source 변환, Markdown readiness preview 상태, carry-over dismiss/resolve action을 추가한다.
- Modify `Sources/MeetingRescue/ContentView.swift`: `워크플로우` tab, Decision Coach, Share Readiness, Action Ledger, Carry-over sections, Markdown readiness preview sheet를 추가한다.

---

### Task 1: Core Workflow Models And Carry-over State

**Files:**
- Create: `Sources/MeetingRescueCore/PersonalWorkflowModels.swift`
- Modify: `Sources/MeetingRescueCore/AnalysisModels.swift`
- Test: `Tests/MeetingRescueCoreTests/PersonalWorkflowAnalyzerTests.swift`

- [ ] **Step 1: Write failing model and persistence tests**

Create `Tests/MeetingRescueCoreTests/PersonalWorkflowAnalyzerTests.swift`.

```swift
import Foundation
import Testing
@testable import MeetingRescueCore

struct PersonalWorkflowAnalyzerTests {
    @Test("carry-over 상태는 MeetingAnalysisState에 저장되고 decode된다")
    func persistsCarryOverQuestionStatus() throws {
        var state = MeetingAnalysisState()
        state.setCarryOverQuestionStatus(id: "carry-over-a", status: .dismissed)
        state.setCarryOverQuestionStatus(id: "carry-over-b", status: .resolved)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingAnalysisState.self, from: data)

        #expect(decoded.dismissedCarryOverQuestionIDs == ["carry-over-a"])
        #expect(decoded.resolvedCarryOverQuestionIDs == ["carry-over-b"])
    }

    @Test("legacy analysis state는 carry-over 상태 없이도 decode된다")
    func decodesLegacyAnalysisStateWithoutCarryOverSets() throws {
        let json = """
        {
          "latestSnapshot": null,
          "confirmedCandidateIDs": [],
          "deletedCandidateIDs": [],
          "decisionCandidateEdits": {},
          "actionItemCandidateEdits": {},
          "updatedAt": "2026-06-03T00:00:00Z",
          "isCompleted": false,
          "usageSummary": {
            "totalInputTokens": 0,
            "totalOutputTokens": 0,
            "totalEstimatedCostUSD": 0,
            "samples": []
          },
          "attemptLogs": [],
          "analyzedTranscriptCharacterCount": 0,
          "bookmarks": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingAnalysisState.self, from: Data(json.utf8))

        #expect(decoded.dismissedCarryOverQuestionIDs.isEmpty)
        #expect(decoded.resolvedCarryOverQuestionIDs.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify the new models fail**

Run:

```bash
swift test --filter PersonalWorkflowAnalyzerTests
```

Expected: FAIL with missing `setCarryOverQuestionStatus`, `dismissedCarryOverQuestionIDs`, `resolvedCarryOverQuestionIDs`, or `CarryOverQuestionStatus`.

- [ ] **Step 3: Add workflow models**

Create `Sources/MeetingRescueCore/PersonalWorkflowModels.swift`.

```swift
import Foundation

public enum WorkflowSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
}

public enum DecisionCoachCardKind: String, Codable, Equatable, Sendable {
    case unconfirmedDecision
    case missingOwner
    case missingCriteria
    case openQuestion
    case mixedScope
}

public struct DecisionCoachCard: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: DecisionCoachCardKind
    public var severity: WorkflowSeverity
    public var title: String
    public var stuckPoint: String
    public var minimumDecision: String
    public var options: [String]
    public var missingInfo: [String]
    public var nextQuestion: String
    public var evidence: [EvidenceReference]

    public init(
        id: String,
        kind: DecisionCoachCardKind,
        severity: WorkflowSeverity,
        title: String,
        stuckPoint: String,
        minimumDecision: String,
        options: [String] = [],
        missingInfo: [String] = [],
        nextQuestion: String,
        evidence: [EvidenceReference] = []
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.stuckPoint = stuckPoint
        self.minimumDecision = minimumDecision
        self.options = options
        self.missingInfo = missingInfo
        self.nextQuestion = nextQuestion
        self.evidence = evidence
    }
}

public enum ShareReadinessWarningKind: String, Codable, Equatable, Sendable {
    case emptySummary
    case unconfirmedDecision
    case unconfirmedAction
    case missingActionOwner
    case missingActionDeadline
    case weakDecisionEvidence
    case openQuestion
    case unresolvedDecisionCoachCard
}

public struct ShareReadinessWarning: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: ShareReadinessWarningKind
    public var severity: WorkflowSeverity
    public var title: String
    public var detail: String
    public var relatedID: String?

    public init(
        id: String,
        kind: ShareReadinessWarningKind,
        severity: WorkflowSeverity,
        title: String,
        detail: String,
        relatedID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.relatedID = relatedID
    }
}

public struct ActionLedgerMeetingSource: Codable, Equatable, Sendable {
    public var meetingID: String
    public var sourceFileName: String
    public var metadata: MeetingMetadata
    public var snapshot: AnalysisSnapshot

    public init(meetingID: String, sourceFileName: String, metadata: MeetingMetadata, snapshot: AnalysisSnapshot) {
        self.meetingID = meetingID
        self.sourceFileName = sourceFileName
        self.metadata = metadata
        self.snapshot = snapshot
    }
}

public struct ActionLedgerItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var task: String
    public var assignee: String?
    public var deadline: String?
    public var meetingID: String
    public var meetingTitle: String
    public var sourceFileName: String
    public var evidenceTimestamp: String
    public var speaker: String?

    public init(
        id: String,
        task: String,
        assignee: String?,
        deadline: String?,
        meetingID: String,
        meetingTitle: String,
        sourceFileName: String,
        evidenceTimestamp: String,
        speaker: String?
    ) {
        self.id = id
        self.task = task
        self.assignee = assignee
        self.deadline = deadline
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.sourceFileName = sourceFileName
        self.evidenceTimestamp = evidenceTimestamp
        self.speaker = speaker
    }
}

public enum CarryOverQuestionStatus: String, Codable, Equatable, Sendable {
    case active
    case dismissed
    case resolved
}

public struct CarryOverMeetingSource: Codable, Equatable, Sendable {
    public var meetingID: String
    public var sourceFileName: String
    public var metadata: MeetingMetadata
    public var snapshot: AnalysisSnapshot

    public init(meetingID: String, sourceFileName: String, metadata: MeetingMetadata, snapshot: AnalysisSnapshot) {
        self.meetingID = meetingID
        self.sourceFileName = sourceFileName
        self.metadata = metadata
        self.snapshot = snapshot
    }
}

public struct OpenQuestionCarryOverCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var question: String
    public var sourceMeetingID: String
    public var sourceTitle: String
    public var sourceFileName: String
    public var reason: String
    public var status: CarryOverQuestionStatus
    public var evidence: [EvidenceReference]

    public init(
        id: String,
        question: String,
        sourceMeetingID: String,
        sourceTitle: String,
        sourceFileName: String,
        reason: String,
        status: CarryOverQuestionStatus = .active,
        evidence: [EvidenceReference] = []
    ) {
        self.id = id
        self.question = question
        self.sourceMeetingID = sourceMeetingID
        self.sourceTitle = sourceTitle
        self.sourceFileName = sourceFileName
        self.reason = reason
        self.status = status
        self.evidence = evidence
    }
}

public struct PersonalWorkflowSnapshot: Codable, Equatable, Sendable {
    public var coachCards: [DecisionCoachCard]
    public var readinessWarnings: [ShareReadinessWarning]
    public var actionLedgerItems: [ActionLedgerItem]
    public var carryOverCandidates: [OpenQuestionCarryOverCandidate]

    public init(
        coachCards: [DecisionCoachCard] = [],
        readinessWarnings: [ShareReadinessWarning] = [],
        actionLedgerItems: [ActionLedgerItem] = [],
        carryOverCandidates: [OpenQuestionCarryOverCandidate] = []
    ) {
        self.coachCards = coachCards
        self.readinessWarnings = readinessWarnings
        self.actionLedgerItems = actionLedgerItems
        self.carryOverCandidates = carryOverCandidates
    }
}
```

- [ ] **Step 4: Add carry-over state to `MeetingAnalysisState`**

In `Sources/MeetingRescueCore/AnalysisModels.swift`, add two stored properties to `MeetingAnalysisState`.

```swift
public var dismissedCarryOverQuestionIDs: Set<String>
public var resolvedCarryOverQuestionIDs: Set<String>
```

Update the initializer signature and body.

```swift
public init(
    latestSnapshot: AnalysisSnapshot? = nil,
    confirmedCandidateIDs: Set<String> = [],
    deletedCandidateIDs: Set<String> = [],
    decisionCandidateEdits: [String: DecisionCandidateEdit] = [:],
    actionItemCandidateEdits: [String: ActionItemCandidateEdit] = [:],
    lastError: String? = nil,
    updatedAt: Date = Date(),
    isCompleted: Bool = false,
    usageSummary: LLMUsageSummary = LLMUsageSummary(),
    attemptLogs: [AnalysisAttemptLog] = [],
    analyzedTranscriptCharacterCount: Int = 0,
    bookmarks: [MeetingBookmark] = [],
    dismissedCarryOverQuestionIDs: Set<String> = [],
    resolvedCarryOverQuestionIDs: Set<String> = []
) {
    self.latestSnapshot = latestSnapshot
    self.confirmedCandidateIDs = confirmedCandidateIDs
    self.deletedCandidateIDs = deletedCandidateIDs
    self.decisionCandidateEdits = decisionCandidateEdits
    self.actionItemCandidateEdits = actionItemCandidateEdits
    self.lastError = lastError
    self.updatedAt = updatedAt
    self.isCompleted = isCompleted
    self.usageSummary = usageSummary
    self.attemptLogs = attemptLogs
    self.analyzedTranscriptCharacterCount = analyzedTranscriptCharacterCount
    self.bookmarks = bookmarks
    self.dismissedCarryOverQuestionIDs = dismissedCarryOverQuestionIDs
    self.resolvedCarryOverQuestionIDs = resolvedCarryOverQuestionIDs
}
```

Add the coding keys.

```swift
case dismissedCarryOverQuestionIDs
case resolvedCarryOverQuestionIDs
```

Add the decode defaults in `init(from:)`.

```swift
dismissedCarryOverQuestionIDs: (try? container.decode(Set<String>.self, forKey: .dismissedCarryOverQuestionIDs)) ?? [],
resolvedCarryOverQuestionIDs: (try? container.decode(Set<String>.self, forKey: .resolvedCarryOverQuestionIDs)) ?? []
```

Add this public mutating method near `deleteBookmark(id:)`.

```swift
public mutating func setCarryOverQuestionStatus(id: String, status: CarryOverQuestionStatus) {
    switch status {
    case .active:
        dismissedCarryOverQuestionIDs.remove(id)
        resolvedCarryOverQuestionIDs.remove(id)
    case .dismissed:
        resolvedCarryOverQuestionIDs.remove(id)
        dismissedCarryOverQuestionIDs.insert(id)
    case .resolved:
        dismissedCarryOverQuestionIDs.remove(id)
        resolvedCarryOverQuestionIDs.insert(id)
    }
}
```

- [ ] **Step 5: Run model tests**

Run:

```bash
swift test --filter PersonalWorkflowAnalyzerTests/persistsCarryOverQuestionStatus
swift test --filter PersonalWorkflowAnalyzerTests/decodesLegacyAnalysisStateWithoutCarryOverSets
```

Expected: PASS.

- [ ] **Step 6: Commit core models**

Run:

```bash
git add Sources/MeetingRescueCore/PersonalWorkflowModels.swift Sources/MeetingRescueCore/AnalysisModels.swift Tests/MeetingRescueCoreTests/PersonalWorkflowAnalyzerTests.swift
git commit -m "feat: add personal workflow models"
```

Expected: commit succeeds.

---

### Task 2: Rule-based Personal Workflow Analyzer

**Files:**
- Create: `Sources/MeetingRescueCore/PersonalWorkflowAnalyzer.swift`
- Modify: `Tests/MeetingRescueCoreTests/PersonalWorkflowAnalyzerTests.swift`

- [ ] **Step 1: Add failing analyzer tests**

Append these tests inside `PersonalWorkflowAnalyzerTests`.

```swift
@Test("decision coach는 미확정 결정과 부족한 기준을 decision card로 만든다")
func createsDecisionCoachCards() {
    let snapshot = AnalysisSnapshot(
        meetingType: .decision,
        meetingSummary: MeetingSummary(
            overview: "배포 방식을 논의했다.",
            openQuestions: [
                MeetingSummaryItem(
                    id: "q1",
                    text: "최종 배포 방식은 무엇인가?",
                    evidence: [EvidenceReference(timestamp: "00:12", speaker: "Alex", excerpt: "아직 최종 방식은 없네요.")]
                )
            ]
        ),
        currentIssue: CurrentIssue(summary: "금요일 배포 방식 결정을 논의 중이다."),
        topicTimeline: [
            TopicTimelineItem(id: "t1", startTimestamp: "00:01", title: "배포", summary: "배포 방식 논의")
        ],
        decisionCandidates: [
            DecisionCandidate(id: "d1", text: "금요일에 배포한다.", status: .candidate, evidenceTimestamp: "00:20", speaker: "Blair")
        ],
        actionItemCandidates: []
    )

    let cards = PersonalWorkflowAnalyzer.decisionCoachCards(for: snapshot)

    #expect(cards.map(\.kind).contains(.unconfirmedDecision))
    #expect(cards.map(\.kind).contains(.missingCriteria))
    #expect(cards.map(\.kind).contains(.openQuestion))
    #expect(cards.first { $0.kind == .unconfirmedDecision }?.minimumDecision.contains("금요일에 배포한다.") == true)
}

@Test("share readiness는 공유 전 수정할 warning을 계산한다")
func createsShareReadinessWarnings() {
    let snapshot = AnalysisSnapshot(
        meetingType: .planning,
        meetingSummary: MeetingSummary(),
        decisionCandidates: [
            DecisionCandidate(id: "d1", text: "일정을 다음 주로 미룬다.", status: .candidate, evidenceTimestamp: "00:20")
        ],
        actionItemCandidates: [
            ActionItemCandidate(id: "a1", assignee: nil, task: "릴리즈 체크리스트 정리", deadline: nil, status: .confirmed, evidenceTimestamp: "00:30")
        ]
    )
    let cards = [
        DecisionCoachCard(
            id: "coach-1",
            kind: .unconfirmedDecision,
            severity: .warning,
            title: "결정 확인 필요",
            stuckPoint: "결정 후보가 확정되지 않았습니다.",
            minimumDecision: "일정을 다음 주로 미룰지 결정",
            nextQuestion: "이 결정을 확정할까요?"
        )
    ]

    let warnings = PersonalWorkflowAnalyzer.shareReadinessWarnings(for: snapshot, coachCards: cards)

    #expect(warnings.map(\.kind).contains(.emptySummary))
    #expect(warnings.map(\.kind).contains(.unconfirmedDecision))
    #expect(warnings.map(\.kind).contains(.missingActionOwner))
    #expect(warnings.map(\.kind).contains(.missingActionDeadline))
    #expect(warnings.map(\.kind).contains(.unresolvedDecisionCoachCard))
}

@Test("action ledger는 confirmed action만 회의 source와 함께 모은다")
func createsActionLedgerItems() {
    let source = ActionLedgerMeetingSource(
        meetingID: "meeting-a",
        sourceFileName: "meeting-a.txt",
        metadata: MeetingMetadata(room: "Launch", participants: ["Alex"], dateTime: "2026-06-03 10:00"),
        snapshot: AnalysisSnapshot(
            actionItemCandidates: [
                ActionItemCandidate(id: "a1", assignee: "Alex", task: "공유 초안 작성", deadline: "금요일", status: .confirmed, evidenceTimestamp: "00:30", speaker: "Blair"),
                ActionItemCandidate(id: "a2", assignee: "Casey", task: "후보 정리", status: .candidate, evidenceTimestamp: "00:40")
            ]
        )
    )

    let items = PersonalWorkflowAnalyzer.actionLedgerItems(from: [source])

    #expect(items.map(\.id) == ["meeting-a:a1"])
    #expect(items.first?.task == "공유 초안 작성")
    #expect(items.first?.meetingTitle == "Launch")
}

@Test("carry-over는 관련 history의 열린 질문을 후보로 만들고 dismissed 항목을 숨긴다")
func createsCarryOverCandidates() {
    let current = CarryOverMeetingSource(
        meetingID: "current",
        sourceFileName: "current.txt",
        metadata: MeetingMetadata(room: "Launch", participants: ["Alex", "Blair"]),
        snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "Launch 준비"))
    )
    let previous = CarryOverMeetingSource(
        meetingID: "previous",
        sourceFileName: "previous.txt",
        metadata: MeetingMetadata(room: "Launch", participants: ["Alex"]),
        snapshot: AnalysisSnapshot(
            meetingSummary: MeetingSummary(
                overview: "Launch 준비",
                openQuestions: [
                    MeetingSummaryItem(id: "q1", text: "Slack 공유 대상은 누구인가?", evidence: [EvidenceReference(timestamp: "00:44", speaker: "Alex", excerpt: "공유 대상은 아직 없네요.")])
                ]
            )
        )
    )

    let all = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
        current: current,
        previous: [previous],
        dismissedIDs: [],
        resolvedIDs: []
    )
    let hidden = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
        current: current,
        previous: [previous],
        dismissedIDs: [all[0].id],
        resolvedIDs: []
    )

    #expect(all.count == 1)
    #expect(all[0].question == "Slack 공유 대상은 누구인가?")
    #expect(all[0].reason.contains("room") == true)
    #expect(hidden.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify analyzer fails**

Run:

```bash
swift test --filter PersonalWorkflowAnalyzerTests
```

Expected: FAIL with missing `PersonalWorkflowAnalyzer`.

- [ ] **Step 3: Implement analyzer**

Create `Sources/MeetingRescueCore/PersonalWorkflowAnalyzer.swift`.

```swift
import Foundation

public enum PersonalWorkflowAnalyzer {
    public static func snapshot(
        currentMeetingID: String,
        metadata: MeetingMetadata,
        state: MeetingAnalysisState,
        historySources: [ActionLedgerMeetingSource]
    ) -> PersonalWorkflowSnapshot {
        guard let latestSnapshot = state.latestSnapshot else {
            return PersonalWorkflowSnapshot()
        }

        let coachCards = decisionCoachCards(for: latestSnapshot)
        let readinessWarnings = shareReadinessWarnings(for: latestSnapshot, coachCards: coachCards)
        let currentSource = ActionLedgerMeetingSource(
            meetingID: currentMeetingID,
            sourceFileName: currentMeetingID,
            metadata: metadata,
            snapshot: latestSnapshot
        )
        let ledgerSources = ([currentSource] + historySources).deduplicatedByMeetingID()
        let carryOverCurrent = CarryOverMeetingSource(
            meetingID: currentMeetingID,
            sourceFileName: currentMeetingID,
            metadata: metadata,
            snapshot: latestSnapshot
        )
        let carryOverPrevious = historySources.map {
            CarryOverMeetingSource(
                meetingID: $0.meetingID,
                sourceFileName: $0.sourceFileName,
                metadata: $0.metadata,
                snapshot: $0.snapshot
            )
        }

        return PersonalWorkflowSnapshot(
            coachCards: coachCards,
            readinessWarnings: readinessWarnings,
            actionLedgerItems: actionLedgerItems(from: ledgerSources),
            carryOverCandidates: openQuestionCarryOverCandidates(
                current: carryOverCurrent,
                previous: carryOverPrevious,
                dismissedIDs: state.dismissedCarryOverQuestionIDs,
                resolvedIDs: state.resolvedCarryOverQuestionIDs
            )
        )
    }

    public static func decisionCoachCards(for snapshot: AnalysisSnapshot) -> [DecisionCoachCard] {
        var cards: [DecisionCoachCard] = []
        let visibleDecisions = snapshot.decisionCandidates.filter { $0.status != .deleted }
        let candidateDecisions = visibleDecisions.filter { $0.status == .candidate }
        let confirmedDecisions = visibleDecisions.filter { $0.status == .confirmed }
        let visibleActions = snapshot.actionItemCandidates.filter { $0.status != .deleted }

        if !candidateDecisions.isEmpty && confirmedDecisions.isEmpty {
            let first = candidateDecisions[0]
            cards.append(
                DecisionCoachCard(
                    id: "coach:unconfirmed-decision:\(first.id)",
                    kind: .unconfirmedDecision,
                    severity: .warning,
                    title: "결정 후보 확인 필요",
                    stuckPoint: "결정 후보는 있지만 확정된 결정이 없습니다.",
                    minimumDecision: first.text,
                    options: candidateDecisions.prefix(3).map(\.text),
                    missingInfo: ["이 후보를 확정할 사람", "확정 여부"],
                    nextQuestion: "지금 확정할 결정은 무엇인가요?",
                    evidence: evidence(from: first)
                )
            )
        }

        if let action = visibleActions.first(where: { normalized($0.assignee).isEmpty }) {
            cards.append(
                DecisionCoachCard(
                    id: "coach:missing-owner:\(action.id)",
                    kind: .missingOwner,
                    severity: .warning,
                    title: "Owner가 없는 action",
                    stuckPoint: "액션은 잡혔지만 실행 담당자가 없습니다.",
                    minimumDecision: "\(action.task)의 owner 지정",
                    missingInfo: ["담당자"],
                    nextQuestion: "이 액션의 owner는 누구인가요?",
                    evidence: evidence(from: action)
                )
            )
        }

        if snapshot.meetingType == .decision && !hasDecisionCriteria(snapshot) {
            cards.append(
                DecisionCoachCard(
                    id: "coach:missing-criteria",
                    kind: .missingCriteria,
                    severity: .info,
                    title: "판단 기준 보강",
                    stuckPoint: "결정 논의지만 비용, 영향, 리스크, 우선순위 같은 판단 기준이 명확하지 않습니다.",
                    minimumDecision: "선택지를 평가할 기준 확정",
                    missingInfo: ["판단 기준", "선택지별 trade-off"],
                    nextQuestion: "이 결정에서 가장 중요한 기준은 무엇인가요?"
                )
            )
        }

        let openQuestions = openQuestionItems(from: snapshot)
        if let question = openQuestions.first {
            cards.append(
                DecisionCoachCard(
                    id: "coach:open-question:\(stableKey(question.text))",
                    kind: .openQuestion,
                    severity: .info,
                    title: "열린 질문 정리",
                    stuckPoint: "회의 공유 전에 답이 필요한 질문이 남아 있습니다.",
                    minimumDecision: question.text,
                    missingInfo: ["답변 또는 다음 확인 owner"],
                    nextQuestion: "이 질문은 지금 답할 수 있나요, 아니면 follow-up owner를 정할까요?",
                    evidence: question.evidence
                )
            )
        }

        let recentTopicTitles = Set(snapshot.topicTimeline.suffix(4).map { stableKey($0.title) }.filter { !$0.isEmpty })
        if recentTopicTitles.count >= 3 && confirmedDecisions.isEmpty {
            cards.append(
                DecisionCoachCard(
                    id: "coach:mixed-scope",
                    kind: .mixedScope,
                    severity: .info,
                    title: "Scope가 섞이는 중",
                    stuckPoint: "최근 흐름이 여러 주제로 이동했지만 확정된 결정은 없습니다.",
                    minimumDecision: "이번 회의에서 끝낼 논점 1개 선택",
                    missingInfo: ["이번 회의의 종료 조건"],
                    nextQuestion: "지금 결정할 최소 논점 하나만 고르면 무엇인가요?"
                )
            )
        }

        return cards
    }

    public static func shareReadinessWarnings(
        for snapshot: AnalysisSnapshot,
        coachCards: [DecisionCoachCard]
    ) -> [ShareReadinessWarning] {
        var warnings: [ShareReadinessWarning] = []

        if snapshot.meetingSummary.isEmpty {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:empty-summary",
                    kind: .emptySummary,
                    severity: .warning,
                    title: "회의 요약이 비어 있음",
                    detail: "공유 전에 전체 회의 요약을 한 번 더 생성하거나 수동으로 정리하세요."
                )
            )
        }

        for decision in snapshot.decisionCandidates where decision.status == .candidate {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:unconfirmed-decision:\(decision.id)",
                    kind: .unconfirmedDecision,
                    severity: .warning,
                    title: "확정되지 않은 결정 후보",
                    detail: decision.text,
                    relatedID: decision.id
                )
            )
        }

        for decision in snapshot.decisionCandidates where decision.status == .confirmed && normalized(decision.evidenceTimestamp).isEmpty {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:weak-decision-evidence:\(decision.id)",
                    kind: .weakDecisionEvidence,
                    severity: .warning,
                    title: "결정 근거 timestamp 없음",
                    detail: decision.text,
                    relatedID: decision.id
                )
            )
        }

        for action in snapshot.actionItemCandidates where action.status == .candidate {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:unconfirmed-action:\(action.id)",
                    kind: .unconfirmedAction,
                    severity: .info,
                    title: "확정되지 않은 action 후보",
                    detail: action.task,
                    relatedID: action.id
                )
            )
        }

        for action in snapshot.actionItemCandidates where action.status == .confirmed {
            if normalized(action.assignee).isEmpty {
                warnings.append(
                    ShareReadinessWarning(
                        id: "readiness:missing-action-owner:\(action.id)",
                        kind: .missingActionOwner,
                        severity: .warning,
                        title: "담당자 없는 action",
                        detail: action.task,
                        relatedID: action.id
                    )
                )
            }
            if normalized(action.deadline).isEmpty {
                warnings.append(
                    ShareReadinessWarning(
                        id: "readiness:missing-action-deadline:\(action.id)",
                        kind: .missingActionDeadline,
                        severity: .info,
                        title: "기한 없는 action",
                        detail: action.task,
                        relatedID: action.id
                    )
                )
            }
        }

        if !openQuestionItems(from: snapshot).isEmpty {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:open-question",
                    kind: .openQuestion,
                    severity: .info,
                    title: "열린 질문 남음",
                    detail: "공유문에 열린 질문 또는 follow-up owner를 포함하세요."
                )
            )
        }

        for card in coachCards where card.severity == .warning {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:coach:\(card.id)",
                    kind: .unresolvedDecisionCoachCard,
                    severity: .warning,
                    title: card.title,
                    detail: card.minimumDecision,
                    relatedID: card.id
                )
            )
        }

        return warnings.deduplicatedByID()
    }

    public static func actionLedgerItems(from sources: [ActionLedgerMeetingSource]) -> [ActionLedgerItem] {
        sources.flatMap { source in
            source.snapshot.actionItemCandidates
                .filter { $0.status == .confirmed }
                .map { action in
                    ActionLedgerItem(
                        id: "\(source.meetingID):\(action.id)",
                        task: action.task,
                        assignee: action.assignee,
                        deadline: action.deadline,
                        meetingID: source.meetingID,
                        meetingTitle: source.metadata.displayTitle,
                        sourceFileName: source.sourceFileName,
                        evidenceTimestamp: action.evidenceTimestamp,
                        speaker: action.speaker
                    )
                }
        }
        .sorted { lhs, rhs in
            if normalized(lhs.deadline) == normalized(rhs.deadline) {
                return lhs.meetingTitle.localizedStandardCompare(rhs.meetingTitle) == .orderedAscending
            }
            if normalized(lhs.deadline).isEmpty {
                return false
            }
            if normalized(rhs.deadline).isEmpty {
                return true
            }
            return normalized(lhs.deadline) < normalized(rhs.deadline)
        }
    }

    public static func openQuestionCarryOverCandidates(
        current: CarryOverMeetingSource,
        previous: [CarryOverMeetingSource],
        dismissedIDs: Set<String>,
        resolvedIDs: Set<String>
    ) -> [OpenQuestionCarryOverCandidate] {
        previous
            .filter { $0.meetingID != current.meetingID }
            .compactMap { source -> (CarryOverMeetingSource, String)? in
                guard let reason = matchReason(current: current, previous: source) else {
                    return nil
                }
                return (source, reason)
            }
            .flatMap { source, reason in
                openQuestionItems(from: source.snapshot).map { item in
                    OpenQuestionCarryOverCandidate(
                        id: "carry-over:\(source.meetingID):\(stableKey(item.text))",
                        question: item.text,
                        sourceMeetingID: source.meetingID,
                        sourceTitle: source.metadata.displayTitle,
                        sourceFileName: source.sourceFileName,
                        reason: reason,
                        evidence: item.evidence
                    )
                }
            }
            .filter { !dismissedIDs.contains($0.id) && !resolvedIDs.contains($0.id) }
            .deduplicatedByID()
    }

    private static func evidence(from decision: DecisionCandidate) -> [EvidenceReference] {
        guard !normalized(decision.evidenceTimestamp).isEmpty else {
            return []
        }
        return [EvidenceReference(timestamp: decision.evidenceTimestamp, speaker: decision.speaker, excerpt: decision.text)]
    }

    private static func evidence(from action: ActionItemCandidate) -> [EvidenceReference] {
        guard !normalized(action.evidenceTimestamp).isEmpty else {
            return []
        }
        return [EvidenceReference(timestamp: action.evidenceTimestamp, speaker: action.speaker, excerpt: action.task)]
    }

    private static func openQuestionItems(from snapshot: AnalysisSnapshot) -> [MeetingSummaryItem] {
        let summaryQuestions = snapshot.meetingSummary.openQuestions
        let currentQuestions = snapshot.currentIssue.openQuestions.map {
            MeetingSummaryItem(id: "current:\(stableKey($0))", text: $0)
        }
        return (summaryQuestions + currentQuestions).filter { !normalized($0.text).isEmpty }
    }

    private static func hasDecisionCriteria(_ snapshot: AnalysisSnapshot) -> Bool {
        let text = [
            snapshot.meetingSummary.overview,
            snapshot.currentIssue.summary,
            snapshot.risksOrNotes.joined(separator: " "),
            snapshot.decisionCandidates.map(\.text).joined(separator: " ")
        ].joined(separator: " ").lowercased()
        let criteriaTokens = ["기준", "근거", "비용", "영향", "리스크", "우선순위", "criteria", "impact", "risk", "cost"]
        return criteriaTokens.contains { text.contains($0) }
    }

    private static func matchReason(current: CarryOverMeetingSource, previous: CarryOverMeetingSource) -> String? {
        let currentRoom = normalized(current.metadata.room)
        let previousRoom = normalized(previous.metadata.room)
        if !currentRoom.isEmpty && currentRoom == previousRoom {
            return "same room"
        }

        let sharedParticipants = Set(current.metadata.participants.map(normalized))
            .intersection(Set(previous.metadata.participants.map(normalized)))
            .filter { !$0.isEmpty }
        if !sharedParticipants.isEmpty {
            return "shared participant"
        }

        let currentTokens = topicTokens(from: current)
        let previousTokens = topicTokens(from: previous)
        if !currentTokens.intersection(previousTokens).isEmpty {
            return "topic match"
        }

        return nil
    }

    private static func topicTokens(from source: CarryOverMeetingSource) -> Set<String> {
        let text = [
            source.metadata.displayTitle,
            source.snapshot.meetingSummary.overview,
            source.snapshot.currentIssue.summary,
            source.snapshot.topicTimeline.map(\.title).joined(separator: " ")
        ].joined(separator: " ")
        return Set(text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalized)
            .filter { $0.count >= 3 })
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func stableKey(_ value: String) -> String {
        normalized(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private extension Array where Element == ShareReadinessWarning {
    func deduplicatedByID() -> [ShareReadinessWarning] {
        var seen: Set<String> = []
        var values: [ShareReadinessWarning] = []
        for item in self where seen.insert(item.id).inserted {
            values.append(item)
        }
        return values
    }
}

private extension Array where Element == OpenQuestionCarryOverCandidate {
    func deduplicatedByID() -> [OpenQuestionCarryOverCandidate] {
        var seen: Set<String> = []
        var values: [OpenQuestionCarryOverCandidate] = []
        for item in self where seen.insert(item.id).inserted {
            values.append(item)
        }
        return values
    }
}

private extension Array where Element == ActionLedgerMeetingSource {
    func deduplicatedByMeetingID() -> [ActionLedgerMeetingSource] {
        var seen: Set<String> = []
        var values: [ActionLedgerMeetingSource] = []
        for item in self where seen.insert(item.meetingID).inserted {
            values.append(item)
        }
        return values
    }
}
```

- [ ] **Step 4: Run analyzer tests**

Run:

```bash
swift test --filter PersonalWorkflowAnalyzerTests
```

Expected: PASS.

- [ ] **Step 5: Commit analyzer**

Run:

```bash
git add Sources/MeetingRescueCore/PersonalWorkflowAnalyzer.swift Tests/MeetingRescueCoreTests/PersonalWorkflowAnalyzerTests.swift
git commit -m "feat: add personal workflow analyzer"
```

Expected: commit succeeds.

---

### Task 3: AppViewModel Workflow Integration

**Files:**
- Modify: `Sources/MeetingRescue/AppViewModel.swift`

- [ ] **Step 1: Add published readiness preview state**

In `AppViewModel`, add this property near the other `@Published` UI state.

```swift
@Published var pendingMarkdownReadinessWarnings: [ShareReadinessWarning] = []
```

- [ ] **Step 2: Add computed workflow snapshot**

In `AppViewModel`, add this computed property near `filteredMeetingHistoryItems`.

```swift
var personalWorkflowSnapshot: PersonalWorkflowSnapshot {
    guard activeTranscriptURL != nil || analysisState.latestSnapshot != nil else {
        return PersonalWorkflowSnapshot()
    }

    return PersonalWorkflowAnalyzer.snapshot(
        currentMeetingID: currentWorkflowMeetingID,
        metadata: metadata,
        state: analysisState,
        historySources: workflowHistorySources(excluding: activeTranscriptURL)
    )
}

var currentShareReadinessWarnings: [ShareReadinessWarning] {
    personalWorkflowSnapshot.readinessWarnings
}
```

Add these private helpers near `makeHistoryItem(from:)`.

```swift
private var currentWorkflowMeetingID: String {
    activeTranscriptURL?.path ?? metadata.displayTitle
}

private func workflowHistorySources(excluding activeURL: URL?) -> [ActionLedgerMeetingSource] {
    meetingHistoryItems.compactMap { item in
        guard item.url != activeURL else {
            return nil
        }
        let state = stateStore.loadAnalysisState(for: item.url)
        guard let snapshot = state.latestSnapshot else {
            return nil
        }
        return ActionLedgerMeetingSource(
            meetingID: item.id,
            sourceFileName: item.url.lastPathComponent,
            metadata: item.metadata,
            snapshot: snapshot
        )
    }
}
```

- [ ] **Step 3: Add carry-over actions**

Add these methods near `deleteLiveBookmark(id:)`.

```swift
func dismissCarryOverQuestion(id: String) {
    setCarryOverQuestionStatus(id: id, status: .dismissed)
    statusMessage = "Carry-over 질문을 숨겼습니다."
}

func resolveCarryOverQuestion(id: String) {
    setCarryOverQuestionStatus(id: id, status: .resolved)
    statusMessage = "Carry-over 질문을 해결됨으로 표시했습니다."
}

private func setCarryOverQuestionStatus(id: String, status: CarryOverQuestionStatus) {
    analysisState.setCarryOverQuestionStatus(id: id, status: status)
    analysisState.updatedAt = Date()
    if let activeTranscriptURL {
        try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
        patchMeetingHistoryItem(for: activeTranscriptURL)
    }
}
```

- [ ] **Step 4: Route Markdown export through readiness preview**

Rename the existing export method body to `exportCurrentIntelligenceMarkdownIgnoringReadiness()`.

```swift
func requestCurrentIntelligenceMarkdownExport() {
    let warnings = currentShareReadinessWarnings
    guard !warnings.isEmpty else {
        exportCurrentIntelligenceMarkdownIgnoringReadiness()
        return
    }
    pendingMarkdownReadinessWarnings = warnings
}

func exportCurrentIntelligenceMarkdownIgnoringReadiness() {
    guard let activeTranscriptURL, analysisState.latestSnapshot != nil else {
        statusMessage = "저장할 Meeting Intelligence가 아직 없습니다."
        return
    }

    let panel = NSSavePanel()
    panel.title = "Meeting Intelligence Markdown 저장"
    panel.prompt = "저장"
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    panel.canCreateDirectories = true
    panel.directoryURL = activeTranscriptURL.deletingLastPathComponent()
    let baseName = activeTranscriptURL.deletingPathExtension().lastPathComponent
    panel.nameFieldStringValue = "\(baseName)-meeting-intelligence.md"

    guard panel.runModal() == .OK, let url = panel.url else {
        return
    }

    let markdown = MeetingIntelligenceMarkdownExporter.markdown(
        metadata: metadata,
        sourceFileName: activeTranscriptURL.lastPathComponent,
        state: analysisState
    )
    do {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        pendingMarkdownReadinessWarnings = []
        statusMessage = "Markdown 저장 완료: \(url.lastPathComponent)"
    } catch {
        statusMessage = "Markdown 저장 실패: \(error.localizedDescription)"
    }
}

func cancelMarkdownReadinessPreview() {
    pendingMarkdownReadinessWarnings = []
}
```

Update every `viewModel.exportCurrentIntelligenceMarkdown()` call in `ContentView.swift` in Task 4 to use `viewModel.requestCurrentIntelligenceMarkdownExport()`.

- [ ] **Step 5: Build app target**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit view model integration**

Run:

```bash
git add Sources/MeetingRescue/AppViewModel.swift
git commit -m "feat: wire personal workflow state"
```

Expected: commit succeeds.

---

### Task 4: Workflow Tab UI

**Files:**
- Modify: `Sources/MeetingRescue/ContentView.swift`

- [ ] **Step 1: Add workflow mode**

Update `IntelligenceMode`.

```swift
private enum IntelligenceMode: String, CaseIterable, Identifiable {
    case overview = "요약"
    case timeline = "흐름"
    case candidates = "후보"
    case workflow = "워크플로우"

    var id: String { rawValue }
}
```

Widen the segmented control.

```swift
.frame(width: 300)
```

- [ ] **Step 2: Route workflow mode**

Update the `switch intelligenceMode` block in `intelligenceContent`.

```swift
switch intelligenceMode {
case .overview:
    overview(snapshot)
case .timeline:
    timeline(snapshot.topicTimeline, full: true)
case .candidates:
    VStack(alignment: .leading, spacing: 12) {
        decisions(snapshot.decisionCandidates, compact: false)
        actionItems(snapshot.actionItemCandidates, compact: false)
        notes(snapshot.risksOrNotes)
    }
case .workflow:
    workflow(viewModel.personalWorkflowSnapshot)
}
```

- [ ] **Step 3: Add workflow sections**

Insert these view helpers near `overview(_:)`.

```swift
private func workflow(_ snapshot: PersonalWorkflowSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        decisionCoach(snapshot.coachCards)
        shareReadiness(snapshot.readinessWarnings)
        actionLedger(snapshot.actionLedgerItems)
        carryOverQuestions(snapshot.carryOverCandidates)
    }
}

private func decisionCoach(_ cards: [DecisionCoachCard]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        sectionHeader("Decision Coach", systemImage: "lightbulb.max")
        if cards.isEmpty {
            placeholderLine("현재 막힌 논점으로 보이는 항목이 없습니다.")
        }
        ForEach(cards) { card in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: card.severity == .warning ? "exclamationmark.triangle" : "sparkle.magnifyingglass")
                        .foregroundStyle(card.severity == .warning ? Color.orange : Color.smoothAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.smoothInk)
                        Text(card.stuckPoint)
                            .font(.callout)
                            .foregroundStyle(Color.smoothMuted)
                        Text("최소 결정: \(card.minimumDecision)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.smoothInk)
                        if !card.missingInfo.isEmpty {
                            Text("부족한 정보: \(card.missingInfo.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(Color.smoothMuted)
                        }
                        Text(card.nextQuestion)
                            .font(.caption)
                            .foregroundStyle(Color.smoothAccent)
                    }
                }
            }
            .padding(10)
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
        }
    }
    .smoothCard(tint: Color.smoothMint)
}

private func shareReadiness(_ warnings: [ShareReadinessWarning]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            sectionHeader("Share Readiness", systemImage: "checklist")
            Spacer()
            Text(warnings.isEmpty ? "Ready" : "\(warnings.count) warnings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(warnings.isEmpty ? Color.smoothMint : Color.orange)
        }
        if warnings.isEmpty {
            placeholderLine("공유 전 확인할 warning이 없습니다.")
        }
        ForEach(warnings) { warning in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.title)
                        .font(.callout.weight(.semibold))
                    Text(warning.detail)
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                }
            } icon: {
                Image(systemName: warning.severity == .warning ? "exclamationmark.circle" : "info.circle")
                    .foregroundStyle(warning.severity == .warning ? Color.orange : Color.smoothAccent)
            }
        }
    }
    .smoothCard(tint: Color.smoothWarm)
}

private func actionLedger(_ items: [ActionLedgerItem]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        sectionHeader("Action Ledger", systemImage: "tray.full")
        if items.isEmpty {
            placeholderLine("확정된 action이 아직 없습니다.")
        }
        ForEach(items.prefix(12)) { item in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(Color.smoothAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.task)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.smoothInk)
                        Text(actionLedgerMetadata(item))
                            .font(.caption)
                            .foregroundStyle(Color.smoothMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 4)
            if item.id != items.prefix(12).last?.id {
                Divider().overlay(Color.smoothLine)
            }
        }
    }
    .smoothCard(tint: Color.smoothSky)
}

private func carryOverQuestions(_ candidates: [OpenQuestionCarryOverCandidate]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        sectionHeader("Open Question Carry-over", systemImage: "arrowshape.turn.up.right")
        if candidates.isEmpty {
            placeholderLine("관련 history에서 이어받을 열린 질문이 없습니다.")
        }
        ForEach(candidates.prefix(8)) { candidate in
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.question)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                Text("\(candidate.sourceTitle) · \(candidate.reason)")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                HStack(spacing: 8) {
                    Button {
                        viewModel.resolveCarryOverQuestion(id: candidate.id)
                    } label: {
                        Label("해결됨", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        viewModel.dismissCarryOverQuestion(id: candidate.id)
                    } label: {
                        Label("숨기기", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption.weight(.semibold))
            }
            .padding(10)
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
        }
    }
    .smoothCard()
}

private func actionLedgerMetadata(_ item: ActionLedgerItem) -> String {
    [
        item.assignee.map { "@\($0)" },
        item.deadline.map { "기한 \($0)" },
        item.meetingTitle,
        MeetingTimestampFormatter.display(item.evidenceTimestamp, meetingDateTime: nil)
    ]
    .compactMap { $0 }
    .filter { !$0.isEmpty }
    .joined(separator: " · ")
}
```

- [ ] **Step 4: Build UI**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 5: Commit workflow tab**

Run:

```bash
git add Sources/MeetingRescue/ContentView.swift
git commit -m "feat: add personal workflow tab"
```

Expected: commit succeeds.

---

### Task 5: Markdown Readiness Preview UI

**Files:**
- Modify: `Sources/MeetingRescue/ContentView.swift`

- [ ] **Step 1: Update Markdown actions**

Replace the full header Markdown action.

```swift
private var markdownHeaderButton: some View {
    headerButton("Markdown", systemImage: "square.and.arrow.down") {
        viewModel.requestCurrentIntelligenceMarkdownExport()
    }
    .disabled(viewModel.analysisState.latestSnapshot == nil)
}
```

Replace the compact menu Markdown action.

```swift
Button {
    viewModel.requestCurrentIntelligenceMarkdownExport()
} label: {
    Label("Markdown", systemImage: "square.and.arrow.down")
}
.disabled(viewModel.analysisState.latestSnapshot == nil)
```

- [ ] **Step 2: Add readiness preview sheet binding**

Add this modifier to the main `ContentView.body` chain with the other sheets.

```swift
.sheet(
    isPresented: Binding(
        get: { !viewModel.pendingMarkdownReadinessWarnings.isEmpty },
        set: { isPresented in
            if !isPresented {
                viewModel.cancelMarkdownReadinessPreview()
            }
        }
    )
) {
    MarkdownReadinessPreviewSheet(warnings: viewModel.pendingMarkdownReadinessWarnings) {
        viewModel.exportCurrentIntelligenceMarkdownIgnoringReadiness()
    } onCancel: {
        viewModel.cancelMarkdownReadinessPreview()
    }
}
```

- [ ] **Step 3: Add readiness preview sheet view**

Add this view near the other private SwiftUI helper views in `ContentView.swift`.

```swift
private struct MarkdownReadinessPreviewSheet: View {
    let warnings: [ShareReadinessWarning]
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Readiness")
                        .font(.headline)
                    Text("공유 전에 확인할 항목이 있습니다.")
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                }
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(warnings) { warning in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.title)
                                    .font(.callout.weight(.semibold))
                                Text(warning.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.smoothMuted)
                            }
                        } icon: {
                            Image(systemName: warning.severity == .warning ? "exclamationmark.circle" : "info.circle")
                                .foregroundStyle(warning.severity == .warning ? Color.orange : Color.smoothAccent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 320)

            HStack {
                Spacer()
                Button("취소") {
                    onCancel()
                }
                Button("계속 저장") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Color.smoothCanvas)
    }
}
```

- [ ] **Step 4: Build preview flow**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 5: Commit readiness preview**

Run:

```bash
git add Sources/MeetingRescue/ContentView.swift
git commit -m "feat: preview share readiness before export"
```

Expected: commit succeeds.

---

### Task 6: Verification

**Files:**
- Verify: full repository

- [ ] **Step 1: Run focused analyzer tests**

Run:

```bash
swift test --filter PersonalWorkflowAnalyzerTests
```

Expected: PASS.

- [ ] **Step 2: Run affected existing tests**

Run:

```bash
swift test --filter AnalysisStateTests
swift test --filter MarkdownExporterTests
swift test --filter MeetingHistorySearchTests
```

Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Run build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 5: Check diff cleanliness**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 6: Inspect final status**

Run:

```bash
git status --short --branch
```

Expected: only D1 commits are ahead of main branch baseline, plus any pre-existing user changes that were present before execution.

---

## Self-review Checklist

- Spec coverage: Decision Coach, Share Readiness, Action Ledger, and Open Question Carry-over each has a model, analyzer rule, AppViewModel path, and UI section.
- Product constraints: no LLM schema change, no automatic interrupt, no separate action store, no calendar/recurring/team dependency in D1.
- Type consistency: `PersonalWorkflowSnapshot`, `DecisionCoachCard`, `ShareReadinessWarning`, `ActionLedgerItem`, `OpenQuestionCarryOverCandidate`, and `CarryOverQuestionStatus` are defined before AppViewModel and UI tasks use them.
- Verification: focused analyzer tests, affected tests, full `swift test`, `swift build`, and `git diff --check` are included.
