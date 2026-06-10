# Local Glossary Review Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Google Photos-style glossary review queue where lower-confidence term variants can be mapped to a new dictionary term, added as aliases to an existing term, rejected as "not the same", or dismissed.

**Architecture:** Keep the current strict suggestion lane conservative and add a separate exploratory review lane. The engine should return strict suggestions plus lower-confidence review candidates; state should persist review candidates and negative alias mappings so repeated refreshes learn from user feedback. SwiftUI should present strict candidates first and review candidates as a lightweight labeling queue with actions for new term, existing-term alias, not-same, and dismiss.

**Tech Stack:** Swift Package, Swift Testing, SwiftUI, local JSON state via `ApplicationStateStore`, existing `LocalGlossarySuggestionEngine`, `LocalGlossaryState`, and `ContentView`.

---

## File Structure

- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossaryModels.swift`
  - Add `LocalGlossaryCandidateLane`.
  - Add `lane` and `reviewReason` to `LocalGlossarySuggestion`.
  - Add `reviewCandidates` and `rejectedSuggestionIDs` to `LocalGlossaryState`.
  - Add state methods to accept as a new term, add as aliases to an existing term, mark not same, dismiss review candidate, and replace strict/review candidates separately.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift`
  - Keep strict candidate logic as-is.
  - Add exploratory pair generation for lower-confidence but supported variants.
  - Exclude accepted aliases, dismissed suggestions, and negative/rejected suggestion IDs.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`
  - Return both strict suggestions and review candidates.
  - Preserve existing `suggestionsWithDiagnostics` API for strict-only callers.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/AppViewModel.swift`
  - Refresh both lanes.
  - Add view model methods for review candidate actions.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/ContentView.swift`
  - Split "용어 후보" and "검토 필요 후보".
  - Add a review row with existing-term picker, new canonical input, not-same, and dismiss actions.
- Modify tests:
  - `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`
  - `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`
  - `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`
  - `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`

## Task 1: Persist Review Candidates And Negative Mappings

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossaryModels.swift`
- Test: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`

- [ ] **Step 1: Write failing model tests**

Add these tests to `LocalGlossaryModelsTests`:

```swift
@Test("local glossary state stores strict suggestions separately from review candidates")
func localGlossaryStateStoresReviewCandidatesSeparately() {
    var state = LocalGlossaryState()
    let strict = LocalGlossarySuggestion(
        id: "suggestion:strict",
        suggestedCanonical: "유저 안드로이드",
        aliases: ["유자 안드로이드", "유저 안드로이드"],
        evidence: [],
        occurrenceCount: 8,
        meetingCount: 4,
        confidence: 0.88,
        lane: .strict
    )
    let review = LocalGlossarySuggestion(
        id: "suggestion:review",
        suggestedCanonical: "신규 활성 유저",
        aliases: ["신규활성제", "신규 활성 유저"],
        evidence: [],
        occurrenceCount: 5,
        meetingCount: 3,
        confidence: 0.58,
        lane: .review,
        reviewReason: "반복 등장하지만 strict threshold 미만"
    )

    state.replaceSuggestions(strict: [strict], review: [review])

    #expect(state.suggestions.map(\.id) == ["suggestion:strict"])
    #expect(state.reviewCandidates.map(\.id) == ["suggestion:review"])
    #expect(state.reviewCandidates.first?.lane == .review)
}

@Test("review candidate can be added as alias to an existing term")
func reviewCandidateCanBeAddedAsAliasToExistingTerm() throws {
    var state = LocalGlossaryState(
        terms: [
            LocalGlossaryTerm(
                id: "term-new-active-user",
                canonical: "신규 활성 유저",
                aliases: ["신규활성 유저"],
                category: .domainTerm
            )
        ],
        reviewCandidates: [
            LocalGlossarySuggestion(
                id: "suggestion:review:new-active",
                suggestedCanonical: "신규 활성 유저",
                aliases: ["신규활성제", "신규 활성 유전"],
                evidence: [],
                occurrenceCount: 5,
                meetingCount: 3,
                confidence: 0.58,
                lane: .review
            )
        ]
    )

    state.addReviewCandidate(id: "suggestion:review:new-active", asAliasesToTermID: "term-new-active-user")

    let term = try #require(state.terms.first)
    #expect(term.aliases.contains("신규활성제"))
    #expect(term.aliases.contains("신규 활성 유전"))
    #expect(state.reviewCandidates.isEmpty)
}

@Test("review candidate rejected as not same is not returned on replacement")
func reviewCandidateRejectedAsNotSameIsFilteredFromReplacement() {
    var state = LocalGlossaryState()
    let candidate = LocalGlossarySuggestion(
        id: "suggestion:review:not-same",
        suggestedCanonical: "대비 포인트",
        aliases: ["대비 포인트", "대비로 포인트"],
        evidence: [],
        occurrenceCount: 10,
        meetingCount: 6,
        confidence: 0.57,
        lane: .review
    )

    state.markReviewCandidateAsNotSame(id: candidate.id)
    state.replaceSuggestions(strict: [], review: [candidate])

    #expect(state.reviewCandidates.isEmpty)
    #expect(state.rejectedSuggestionIDs.contains(candidate.id))
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'LocalGlossaryModelsTests/localGlossaryStateStoresReviewCandidatesSeparately|LocalGlossaryModelsTests/reviewCandidateCanBeAddedAsAliasToExistingTerm|LocalGlossaryModelsTests/reviewCandidateRejectedAsNotSameIsFilteredFromReplacement'
```

Expected: FAIL because `LocalGlossaryCandidateLane`, `reviewCandidates`, `rejectedSuggestionIDs`, and review action methods do not exist.

- [ ] **Step 3: Implement the model changes**

Add near `LocalGlossaryTermSource`:

```swift
public enum LocalGlossaryCandidateLane: String, Codable, Sendable {
    case strict
    case review
}
```

Add to `LocalGlossarySuggestion`:

```swift
public var lane: LocalGlossaryCandidateLane
public var reviewReason: String
```

Update its initializer with defaults:

```swift
lane: LocalGlossaryCandidateLane = .strict,
reviewReason: String = ""
```

Set:

```swift
self.lane = lane
self.reviewReason = reviewReason.trimmedGlossaryText
```

Add both fields to `CodingKeys`, and decode with legacy defaults:

```swift
lane = try container.decodeIfPresent(LocalGlossaryCandidateLane.self, forKey: .lane) ?? .strict
reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason) ?? ""
```

Add to `LocalGlossaryState`:

```swift
public var reviewCandidates: [LocalGlossarySuggestion]
public var rejectedSuggestionIDs: Set<String>
```

Update `init`:

```swift
reviewCandidates: [LocalGlossarySuggestion] = [],
rejectedSuggestionIDs: Set<String> = [],
```

Set:

```swift
self.reviewCandidates = reviewCandidates
self.rejectedSuggestionIDs = rejectedSuggestionIDs
```

Add methods:

```swift
public mutating func replaceSuggestions(
    strict strictSuggestions: [LocalGlossarySuggestion],
    review reviewSuggestions: [LocalGlossarySuggestion]
) {
    suggestions = strictSuggestions
        .filter { !dismissedSuggestionIDs.contains($0.id) && !rejectedSuggestionIDs.contains($0.id) }
        .map { suggestion in
            var value = suggestion
            value.lane = .strict
            return value
        }
        .sortedByGlossaryConfidence

    reviewCandidates = reviewSuggestions
        .filter { !dismissedSuggestionIDs.contains($0.id) && !rejectedSuggestionIDs.contains($0.id) }
        .map { suggestion in
            var value = suggestion
            value.lane = .review
            return value
        }
        .sortedByGlossaryConfidence

    updatedAt = Date()
}

public mutating func addReviewCandidate(
    id: String,
    asAliasesToTermID termID: String
) {
    guard let candidate = reviewCandidates.first(where: { $0.id == id }),
          let termIndex = terms.firstIndex(where: { $0.id == termID }) else {
        return
    }
    let aliases = (terms[termIndex].aliases + candidate.aliases).normalizedGlossaryValues(excluding: [terms[termIndex].canonical])
    terms[termIndex].aliases = aliases
    terms[termIndex].updatedAt = Date()
    reviewCandidates.removeAll { $0.id == id }
    dismissedSuggestionIDs.remove(id)
    rejectedSuggestionIDs.remove(id)
    updatedAt = Date()
}

public mutating func acceptReviewCandidateAsNewTerm(
    id: String,
    canonical: String,
    category: LocalGlossaryCategory
) {
    guard let candidate = reviewCandidates.first(where: { $0.id == id }) else {
        return
    }
    let now = Date()
    terms.removeAll {
        MeetingHistorySearch.compactNormalize($0.canonical) == MeetingHistorySearch.compactNormalize(canonical)
    }
    terms.append(LocalGlossaryTerm(
        canonical: canonical,
        aliases: candidate.aliases,
        category: category,
        note: "review queue에서 추가됨",
        source: .suggested,
        createdAt: now,
        updatedAt: now
    ))
    reviewCandidates.removeAll { $0.id == id }
    dismissedSuggestionIDs.remove(id)
    rejectedSuggestionIDs.remove(id)
    updatedAt = now
}

public mutating func dismissReviewCandidate(id: String) {
    reviewCandidates.removeAll { $0.id == id }
    dismissedSuggestionIDs.insert(id)
    updatedAt = Date()
}

public mutating func markReviewCandidateAsNotSame(id: String) {
    reviewCandidates.removeAll { $0.id == id }
    rejectedSuggestionIDs.insert(id)
    updatedAt = Date()
}
```

Add a private sorting helper near the model extensions:

```swift
private extension Array where Element == LocalGlossarySuggestion {
    var sortedByGlossaryConfidence: [LocalGlossarySuggestion] {
        sorted {
            if $0.confidence == $1.confidence {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.confidence > $1.confidence
        }
    }
}
```

- [ ] **Step 4: Run test to verify GREEN**

Run the same command from Step 2.

Expected: PASS.

## Task 2: Engine Returns Strict And Review Candidates

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift`
- Test: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`

- [ ] **Step 1: Write failing engine tests**

Add tests:

```swift
@Test("suggestion engine exposes exploratory review candidates separately from strict suggestions")
func suggestionEngineExposesReviewCandidates() throws {
    let documents = [
        LocalGlossarySourceDocument(
            id: "m1",
            title: "Growth 1",
            sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 지표를 봅니다.", weight: 24)]
        ),
        LocalGlossarySourceDocument(
            id: "m2",
            title: "Growth 2",
            sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성 유전 지표를 봅니다.", weight: 24)]
        ),
        LocalGlossarySourceDocument(
            id: "m3",
            title: "Growth 3",
            sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성제 전환을 봅니다.", weight: 24)]
        ),
        LocalGlossarySourceDocument(
            id: "m4",
            title: "Growth 4",
            sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 전환을 봅니다.", weight: 24)]
        )
    ]

    let result = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
        from: documents,
        existingState: LocalGlossaryState(),
        maxSuggestions: 8,
        maxReviewCandidates: 20
    )

    #expect(result.reviewCandidates.contains { candidate in
        candidate.lane == .review
            && candidate.aliases.contains("신규활성제")
            && candidate.aliases.contains("신규 활성 유저")
    })
}

@Test("rejected review candidates are excluded from future review results")
func rejectedReviewCandidatesAreExcluded() throws {
    let documents = [
        LocalGlossarySourceDocument(
            id: "m1",
            title: "Metrics 1",
            sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 대비 포인트를 봅니다.", weight: 24)]
        ),
        LocalGlossarySourceDocument(
            id: "m2",
            title: "Metrics 2",
            sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 대비로 포인트를 봅니다.", weight: 24)]
        ),
        LocalGlossarySourceDocument(
            id: "m3",
            title: "Metrics 3",
            sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 대비 포인트를 다시 봅니다.", weight: 24)]
        )
    ]
    let first = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
        from: documents,
        existingState: LocalGlossaryState(),
        maxSuggestions: 8,
        maxReviewCandidates: 20
    )
    let rejectedID = try #require(first.reviewCandidates.first?.id)
    let state = LocalGlossaryState(rejectedSuggestionIDs: [rejectedID])

    let second = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
        from: documents,
        existingState: state,
        maxSuggestions: 8,
        maxReviewCandidates: 20
    )

    #expect(!second.reviewCandidates.contains { $0.id == rejectedID })
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'LocalGlossarySuggestionEngineTests/suggestionEngineExposesReviewCandidates|LocalGlossarySuggestionEngineTests/rejectedReviewCandidatesAreExcluded'
```

Expected: FAIL because `suggestionsAndReviewCandidatesWithDiagnostics` does not exist.

- [ ] **Step 3: Add result type and preserve existing API**

In `LocalGlossarySuggestionEngine.swift`, add:

```swift
public struct LocalGlossarySuggestionEngineResult: Sendable {
    public var suggestions: [LocalGlossarySuggestion]
    public var reviewCandidates: [LocalGlossarySuggestion]
    public var diagnostics: LocalGlossarySuggestionEngineDiagnostics

    public init(
        suggestions: [LocalGlossarySuggestion],
        reviewCandidates: [LocalGlossarySuggestion],
        diagnostics: LocalGlossarySuggestionEngineDiagnostics
    ) {
        self.suggestions = suggestions
        self.reviewCandidates = reviewCandidates
        self.diagnostics = diagnostics
    }
}
```

Add the new public entrypoint:

```swift
public static func suggestionsAndReviewCandidatesWithDiagnostics(
    from documents: [LocalGlossarySourceDocument],
    existingState: LocalGlossaryState,
    maxSuggestions: Int = 8,
    maxReviewCandidates: Int = 50,
    includeLatin: Bool = false
) -> LocalGlossarySuggestionEngineResult
```

Keep `suggestionsWithDiagnostics` by calling the new method and returning `(result.suggestions, result.diagnostics)`.

- [ ] **Step 4: Add Korean review candidate generation**

In `LocalGlossaryKoreanSuggestionEngine.swift`, add a result type:

```swift
public struct LocalGlossaryKoreanSuggestionResult: Sendable {
    public var suggestions: [LocalGlossarySuggestion]
    public var reviewCandidates: [LocalGlossarySuggestion]
    public var diagnostics: LocalGlossaryKoreanSuggestionDiagnostics
}
```

Add `suggestionsAndReviewCandidatesWithDiagnostics(...)`.

Keep the strict pipeline unchanged, then build review candidates from pairs that satisfy:

```swift
private static func acceptsReviewPair(
    lhs: KoreanPhraseCandidate,
    rhs: KoreanPhraseCandidate,
    score: Double,
    contextOverlap: Double
) -> Bool {
    let combinedDocumentSupport = lhs.documentCount + rhs.documentCount
    let recurringSupport = lhs.documentCount >= 2 || rhs.documentCount >= 2
        || lhs.occurrenceCount >= 3 || rhs.occurrenceCount >= 3
    return score >= 0.72
        && contextOverlap >= 0.05
        && combinedDocumentSupport >= 3
        && recurringSupport
}
```

Build review suggestions with:

```swift
var suggestion = LocalGlossarySuggestion(
    id: "suggestion:review:ko:\(cluster.map(\.compact).sorted().joined(separator: "|"))",
    suggestedCanonical: suggestedCanonical,
    aliases: aliases,
    evidence: evidence,
    occurrenceCount: occurrences.count,
    meetingCount: meetingIDs.count,
    confidence: min(score.finalScore, 0.74),
    score: score,
    lane: .review,
    reviewReason: "반복/맥락 근거는 있으나 strict threshold 미만"
)
```

Exclude any review candidate whose aliases overlap an accepted enabled term:

```swift
let acceptedValues = Set(existingState.enabledTerms.flatMap(\.allMatchValues).map(MeetingHistorySearch.compactNormalize))
guard suggestion.aliases.map(MeetingHistorySearch.compactNormalize).allSatisfy({ !acceptedValues.contains($0) }) else {
    return nil
}
```

Exclude IDs in `existingState.dismissedSuggestionIDs` and `existingState.rejectedSuggestionIDs`.

- [ ] **Step 5: Run engine tests**

Run:

```bash
swift test --filter 'LocalGlossarySuggestionEngineTests'
```

Expected: PASS.

## Task 3: Refresh Stores Both Lanes

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/AppViewModel.swift`
- Test: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`

- [ ] **Step 1: Write failing AppViewModel source wiring test**

Update `localGlossaryRefreshScansSelectedRawTranscriptFolder` to assert:

```swift
#expect(refresh.contains("suggestionsAndReviewCandidatesWithDiagnostics"))
#expect(refresh.contains("replaceSuggestions(strict: suggestions, review: reviewCandidates)"))
#expect(refresh.contains("reviewCandidates=\\(reviewCandidates.count)"))
```

Add a separate test:

```swift
@Test("AppViewModel exposes review candidate actions")
func appViewModelExposesReviewCandidateActions() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("func acceptLocalGlossaryReviewCandidateAsNewTerm"))
    #expect(source.contains("func addLocalGlossaryReviewCandidate"))
    #expect(source.contains("func markLocalGlossaryReviewCandidateAsNotSame"))
    #expect(source.contains("func dismissLocalGlossaryReviewCandidate"))
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'AppViewModelTestRunContextTests/localGlossaryRefreshScansSelectedRawTranscriptFolder|AppViewModelTestRunContextTests/appViewModelExposesReviewCandidateActions'
```

Expected: FAIL because refresh still stores only strict suggestions.

- [ ] **Step 3: Update refresh**

Change:

```swift
let suggestionResult = await Task.detached(priority: .utility) {
    LocalGlossarySuggestionEngine.suggestionsWithDiagnostics(
        from: documents,
        existingState: currentState,
        maxSuggestions: 12
    )
}.value
let suggestions = suggestionResult.suggestions
```

to:

```swift
let suggestionResult = await Task.detached(priority: .utility) {
    LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
        from: documents,
        existingState: currentState,
        maxSuggestions: 12,
        maxReviewCandidates: 50
    )
}.value
let suggestions = suggestionResult.suggestions
let reviewCandidates = suggestionResult.reviewCandidates
```

Change state replacement:

```swift
self.localGlossaryState.replaceSuggestions(strict: suggestions, review: reviewCandidates)
```

Update diagnostic detail:

```swift
detail: "documents=\(documents.count) suggestions=\(suggestions.count) reviewCandidates=\(reviewCandidates.count) ..."
```

Update status message:

```swift
self.localGlossaryStatusMessage = suggestions.isEmpty && reviewCandidates.isEmpty
    ? "회의 \(documents.count)개에서 새 용어 후보 없음 · \(totalMilliseconds)ms"
    : "회의 \(documents.count)개에서 용어 후보 \(suggestions.count)개 · 검토 \(reviewCandidates.count)개 · \(totalMilliseconds)ms"
```

- [ ] **Step 4: Add AppViewModel actions**

Add:

```swift
func acceptLocalGlossaryReviewCandidateAsNewTerm(
    id: String,
    canonical: String,
    category: LocalGlossaryCategory = .domainTerm
) {
    localGlossaryState.acceptReviewCandidateAsNewTerm(id: id, canonical: canonical, category: category)
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "검토 후보를 새 용어로 추가했습니다."
    refreshMeetingHistory(force: true)
}

func addLocalGlossaryReviewCandidate(id: String, toTermID termID: String) {
    localGlossaryState.addReviewCandidate(id: id, asAliasesToTermID: termID)
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "기존 용어 alias로 추가했습니다."
    refreshMeetingHistory(force: true)
}

func markLocalGlossaryReviewCandidateAsNotSame(id: String) {
    localGlossaryState.markReviewCandidateAsNotSame(id: id)
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "서로 다른 단어로 표시했습니다."
}

func dismissLocalGlossaryReviewCandidate(id: String) {
    localGlossaryState.dismissReviewCandidate(id: id)
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "검토 후보를 숨겼습니다."
}
```

- [ ] **Step 5: Run test to verify GREEN**

Run the same command from Step 2.

Expected: PASS.

## Task 4: Add Review Queue UI

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/ContentView.swift`
- Test: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`

- [ ] **Step 1: Write failing UI wiring test**

Add:

```swift
@Test("glossary tab exposes a review queue for low-confidence candidates")
func glossaryTabExposesReviewQueue() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("검토 필요 후보"))
    #expect(source.contains("LocalGlossaryReviewCandidateRow"))
    #expect(source.contains("기존 용어에 추가"))
    #expect(source.contains("새 용어로 추가"))
    #expect(source.contains("서로 다른 단어"))
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'ContentViewContextWiringTests/glossaryTabExposesReviewQueue'
```

Expected: FAIL because the review queue UI does not exist.

- [ ] **Step 3: Split the glossary panel**

In `localGlossaryPanel`, keep strict suggestions first and add:

```swift
if !viewModel.localGlossaryState.reviewCandidates.isEmpty {
    localGlossaryReviewQueue()
}
```

Add:

```swift
private func localGlossaryReviewQueue() -> some View {
    VStack(alignment: .leading, spacing: 10) {
        sectionHeader("검토 필요 후보", systemImage: "rectangle.stack.badge.person.crop")
        ForEach(viewModel.localGlossaryState.reviewCandidates.prefix(50)) { candidate in
            LocalGlossaryReviewCandidateRow(
                candidate: candidate,
                terms: viewModel.localGlossaryState.terms,
                onAddToExisting: { termID in
                    viewModel.addLocalGlossaryReviewCandidate(id: candidate.id, toTermID: termID)
                },
                onAcceptNew: { canonical in
                    viewModel.acceptLocalGlossaryReviewCandidateAsNewTerm(id: candidate.id, canonical: canonical)
                },
                onNotSame: {
                    viewModel.markLocalGlossaryReviewCandidateAsNotSame(id: candidate.id)
                },
                onDismiss: {
                    viewModel.dismissLocalGlossaryReviewCandidate(id: candidate.id)
                }
            )
        }
    }
}
```

- [ ] **Step 4: Add `LocalGlossaryReviewCandidateRow`**

Place near `LocalGlossarySuggestionReviewRow`:

```swift
private struct LocalGlossaryReviewCandidateRow: View {
    let candidate: LocalGlossarySuggestion
    let terms: [LocalGlossaryTerm]
    let onAddToExisting: (String) -> Void
    let onAcceptNew: (String) -> Void
    let onNotSame: () -> Void
    let onDismiss: () -> Void

    @State private var canonical: String
    @State private var selectedTermID: String

    init(
        candidate: LocalGlossarySuggestion,
        terms: [LocalGlossaryTerm],
        onAddToExisting: @escaping (String) -> Void,
        onAcceptNew: @escaping (String) -> Void,
        onNotSame: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.terms = terms
        self.onAddToExisting = onAddToExisting
        self.onAcceptNew = onAcceptNew
        self.onNotSame = onNotSame
        self.onDismiss = onDismiss
        _canonical = State(initialValue: candidate.suggestedCanonical)
        _selectedTermID = State(initialValue: terms.first?.id ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("같은 용어일 수 있음", systemImage: "person.2.crop.square.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.smoothAccent)
                Spacer()
                Text("\(Int(candidate.confidence * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.smoothMuted)
            }
            Text(candidate.aliases.joined(separator: " / "))
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.smoothInk)
            Text(candidate.reviewReason.isEmpty ? candidate.score.summaryText : candidate.reviewReason)
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
            if let excerpt = candidate.evidence.first?.excerpt {
                Text(excerpt)
                    .font(.caption2)
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                TextField("새 정답 용어", text: $canonical)
                    .textFieldStyle(.roundedBorder)
                Button("새 용어로 추가") {
                    onAcceptNew(canonical)
                }
                .disabled(canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !terms.isEmpty {
                HStack(spacing: 8) {
                    Picker("기존 용어", selection: $selectedTermID) {
                        ForEach(terms) { term in
                            Text(term.canonical).tag(term.id)
                        }
                    }
                    .labelsHidden()
                    Button("기존 용어에 추가") {
                        onAddToExisting(selectedTermID)
                    }
                    .disabled(selectedTermID.isEmpty)
                }
            }
            HStack {
                Button("서로 다른 단어", role: .destructive) {
                    onNotSame()
                }
                Button("숨김") {
                    onDismiss()
                }
                Spacer()
            }
        }
        .smoothCard(tint: Color.smoothSky)
    }
}
```

- [ ] **Step 5: Run UI wiring test**

Run the same command from Step 2.

Expected: PASS.

## Task 5: Offline Runner Visibility

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/LocalGlossaryScoringRunner.swift`
- Test: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/LocalGlossaryScoringRunnerTests.swift`

- [ ] **Step 1: Write failing runner source test**

Add assertions to `runnerSupportsQualityScoringOptions`:

```swift
#expect(runnerSource.contains("reviewCandidateCount"))
#expect(runnerSource.contains("reviewCandidates"))
#expect(runnerSource.contains("maxReviewCandidates"))
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'LocalGlossaryScoringRunnerTests/runnerSupportsQualityScoringOptions'
```

Expected: FAIL because the runner report has no review lane fields.

- [ ] **Step 3: Update runner output**

Change runner call to:

```swift
let result = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
    from: documents,
    existingState: state,
    maxSuggestions: 12,
    maxReviewCandidates: 50,
    includeLatin: options.includeLatin
)
```

Add to `LocalGlossaryScoringReport`:

```swift
var reviewCandidateCount: Int
var reviewCandidates: [LocalGlossaryCandidateScoreReport]
```

Populate:

```swift
let candidates = result.suggestions.map(LocalGlossaryCandidateScoreReport.init(suggestion:))
let reviewCandidates = result.reviewCandidates.map(LocalGlossaryCandidateScoreReport.init(suggestion:))
```

Use strict candidates for existing quality gate noise count, and include review count in JSON output.

- [ ] **Step 4: Run runner test**

Run the same command from Step 2.

Expected: PASS.

## Task 6: Verification

**Files:**
- All changed files above.

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift test --filter 'LocalGlossaryModelsTests|LocalGlossarySuggestionEngineTests|AppViewModelTestRunContextTests|ContentViewContextWiringTests|LocalGlossaryScoringRunnerTests'
```

Expected: PASS.

- [ ] **Step 2: Run default full-folder scoring**

Run:

```bash
swift run MeetingRescue --local-glossary-score --folder /Users/ethan/Documents/Recordings --limit 200 --output .build/local-glossary-review-queue-report.json
```

Expected:
- exit may be `1` if strict suggestion timing exceeds the old 15s gate; JSON must still be written.
- JSON must contain `reviewCandidateCount`.
- `reviewCandidateCount` should be greater than strict `candidateCount` on the current corpus.

- [ ] **Step 3: Inspect candidate counts**

Run:

```bash
jq '{candidateCount, reviewCandidateCount, reviewCandidates: [.reviewCandidates[] | {canonical: .suggestedCanonical, aliases, confidence, impactLabel}]}' .build/local-glossary-review-queue-report.json
```

Expected: review candidates are visible for manual inspection.

- [ ] **Step 4: Run build checks**

Run:

```bash
swift build
scripts/build_app.sh
git diff --check
```

Expected: all pass.

## Self-Review

- Spec coverage: This plan covers the Google Photos-style labeling loop, new-term creation, existing-term alias mapping, not-same negative mapping, dismissed candidates, UI review queue, runner visibility, and repeat-run behavior.
- Placeholder scan: The plan contains concrete file paths, commands, test bodies, and code snippets. It does not rely on undefined task names.
- Type consistency: `LocalGlossaryCandidateLane`, `reviewCandidates`, `rejectedSuggestionIDs`, `replaceSuggestions(strict:review:)`, `addReviewCandidate`, `acceptReviewCandidateAsNewTerm`, `markReviewCandidateAsNotSame`, and `dismissReviewCandidate` are used consistently across model, engine, view model, UI, and runner tasks.
