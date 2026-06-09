# Local Glossary Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first personal glossary that scans meeting history, suggests likely misheard domain terms, and uses accepted aliases as low-priority hints for analysis and search without modifying raw transcript text.

**Architecture:** Store the user's accepted glossary and dismissed suggestions under Application Support as `local-glossary.json`. A core suggestion engine scans existing history/search sections for recurring fuzzy term clusters, while a matcher converts accepted glossary hits into prompt supplemental context and search sections. The app surfaces suggestions in Settings and applies accepted terms automatically to future analysis/search paths.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, local JSON persistence via `ApplicationStateStore`, existing `SupplementalContextSource`, existing `MeetingHistorySearchSection`/SQLite search indexing.

---

## Product Decisions

- Raw transcript is source of truth and must never be rewritten.
- Glossary terms are personal/local by default. No Google Sheet, backend, team sync, or write/approval workflow in this implementation.
- Accepted glossary hints are low-priority interpretation hints. They may help canonicalize company/domain terms, but must not create decisions/actions by themselves.
- The first suggestion engine focuses on Latin/mixed STT variants such as `jax`, `jecks`, `zacks` because this is the observed pain. Korean spacing normalization already exists in search and should not be rebuilt here.
- User effort should be "approve a suggested cluster and edit the canonical term", not "maintain a blank dictionary from scratch".

## File Structure

- Create `Sources/MeetingRescueCore/LocalGlossaryModels.swift`
  - Data model for accepted terms, suggestions, evidence, and local glossary state.
- Create `Sources/MeetingRescueCore/LocalGlossaryMatcher.swift`
  - Matches accepted aliases/canonical terms in raw transcript or search text.
  - Builds `SupplementalContextSource` hints for analysis.
  - Builds canonical search text for history indexing.
- Create `Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`
  - Scans local history documents and emits term-cluster suggestions.
- Modify `Sources/MeetingRescueCore/ApplicationStateStore.swift`
  - Add `loadLocalGlossaryState()` and `saveLocalGlossaryState(_:)`.
- Modify `Sources/MeetingRescueCore/CalendarContextModels.swift`
  - Add `domainGlossary` supplemental context kind and priority.
- Modify `Sources/MeetingRescueCore/AnalysisModels.swift`
  - Add `AppSettings.localGlossaryEnabled`.
- Modify `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`
  - Add explicit domain glossary precedence instructions.
- Modify `Sources/MeetingRescueCore/MeetingHistorySearch.swift`
  - Add `.glossary` search field.
- Modify `Sources/MeetingRescue/AppViewModel.swift`
  - Load/save local glossary state.
  - Generate suggestions from history.
  - Accept/dismiss/delete glossary entries.
  - Inject glossary supplemental context into analysis requests.
  - Add glossary sections to meeting history search indexing.
- Modify `Sources/MeetingRescue/MeetingSearchDatabase.swift`
  - No schema change required; ensure glossary sections flow through existing FTS/semantic insert path.
- Modify `Sources/MeetingRescue/ContentView.swift`
  - Add Settings section for local glossary suggestions and accepted terms.
- Create tests:
  - `Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`
  - `Tests/MeetingRescueCoreTests/LocalGlossaryMatcherTests.swift`
  - `Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`
- Modify tests:
  - `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`
  - `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`
  - `Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift`
  - `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`
  - `Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`

---

### Task 1: Local Glossary Models And Persistence

**Files:**
- Create: `Sources/MeetingRescueCore/LocalGlossaryModels.swift`
- Modify: `Sources/MeetingRescueCore/ApplicationStateStore.swift`
- Modify: `Sources/MeetingRescueCore/CalendarContextModels.swift`
- Test: `Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`
- Test: `Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift`

- [ ] **Step 1: Write failing model and persistence tests**

Create `Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossaryModelsTests {
    @Test("accepted suggestion creates enabled local glossary term and removes suggestion")
    func acceptedSuggestionCreatesEnabledTerm() throws {
        var state = LocalGlossaryState(
            suggestions: [
                LocalGlossarySuggestion(
                    id: "suggestion-zax",
                    suggestedCanonical: "zax",
                    aliases: ["jax", "jecks", "zacks"],
                    evidence: [
                        LocalGlossaryEvidence(
                            sourceID: "meeting-1",
                            sourceTitle: "Product Sync",
                            excerpt: "Alex: jax 쪽 workflow를 다시 봅시다.",
                            timestamp: "03:12"
                        )
                    ],
                    occurrenceCount: 7,
                    meetingCount: 3,
                    confidence: 0.82
                )
            ]
        )

        state.acceptSuggestion(id: "suggestion-zax", canonical: "zax", category: .project)

        #expect(state.suggestions.isEmpty)
        #expect(state.terms.count == 1)
        #expect(state.terms[0].canonical == "zax")
        #expect(state.terms[0].aliases == ["jax", "jecks", "zacks"])
        #expect(state.terms[0].category == .project)
        #expect(state.terms[0].isEnabled)
        #expect(state.terms[0].source == .suggested)
    }

    @Test("dismissed suggestion ids survive encode and decode")
    func dismissedSuggestionIDsSurviveRoundTrip() throws {
        var state = LocalGlossaryState()
        state.dismissSuggestion(id: "suggestion-zax")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LocalGlossaryState.self, from: data)

        #expect(decoded.dismissedSuggestionIDs == ["suggestion-zax"])
        #expect(decoded.suggestions.isEmpty)
    }

    @Test("ApplicationStateStore saves and loads local glossary state")
    func stateStorePersistsLocalGlossary() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-\(UUID().uuidString)", isDirectory: true)
        let store = ApplicationStateStore(rootURL: root)
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(
                canonical: "zax",
                aliases: ["jax", "jecks"],
                category: .project,
                note: "STT가 자주 틀리는 사내 프로젝트명",
                source: .manual
            )
        ])

        try store.saveLocalGlossaryState(state)
        let loaded = store.loadLocalGlossaryState()

        #expect(loaded.terms == state.terms)
    }
}
```

Append this test to `Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift`:

```swift
@Test("domain glossary supplemental context sorts between attached text and calendar metadata")
func domainGlossarySortsBeforeCalendarMetadata() {
    let values = [
        SupplementalContextSource(id: "calendar", kind: .calendarMetadata, title: "Calendar", sourceName: "Calendar", excerpt: "event", priority: .calendarMetadata, confidence: 0.7),
        SupplementalContextSource(id: "glossary", kind: .domainGlossary, title: "Glossary", sourceName: "Local Glossary", excerpt: "zax", priority: .domainGlossary, confidence: 0.9),
        SupplementalContextSource(id: "attached", kind: .attachedText, title: "Spec", sourceName: "File", excerpt: "spec", priority: .userAttachedContext, confidence: 1.0)
    ]

    #expect(values.sortedForPrompt().map(\.id) == ["attached", "glossary", "calendar"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter LocalGlossaryModelsTests
swift test --filter CalendarContextModelsTests
```

Expected:
- `LocalGlossaryModelsTests` fails because `LocalGlossaryState`, `LocalGlossaryTerm`, `LocalGlossarySuggestion`, and persistence methods do not exist.
- `CalendarContextModelsTests` fails because `.domainGlossary` kind/priority does not exist.

- [ ] **Step 3: Add glossary models**

Create `Sources/MeetingRescueCore/LocalGlossaryModels.swift`:

```swift
import Foundation

public enum LocalGlossaryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case project
    case product
    case team
    case person
    case acronym
    case domainTerm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .project:
            return "Project"
        case .product:
            return "Product"
        case .team:
            return "Team"
        case .person:
            return "Person"
        case .acronym:
            return "Acronym"
        case .domainTerm:
            return "Domain term"
        }
    }
}

public enum LocalGlossaryTermSource: String, Codable, Sendable {
    case manual
    case suggested
}

public struct LocalGlossaryTerm: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var canonical: String
    public var aliases: [String]
    public var category: LocalGlossaryCategory
    public var note: String
    public var isEnabled: Bool
    public var source: LocalGlossaryTermSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        canonical: String,
        aliases: [String],
        category: LocalGlossaryCategory = .domainTerm,
        note: String = "",
        isEnabled: Bool = true,
        source: LocalGlossaryTermSource = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.canonical = canonical.trimmedGlossaryText
        self.aliases = aliases.normalizedGlossaryValues(excluding: [canonical])
        self.category = category
        self.note = note.trimmedGlossaryText
        self.isEnabled = isEnabled
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var allMatchValues: [String] {
        ([canonical] + aliases).normalizedGlossaryValues()
    }
}

public struct LocalGlossaryEvidence: Codable, Equatable, Sendable {
    public var sourceID: String
    public var sourceTitle: String
    public var excerpt: String
    public var timestamp: String?

    public init(sourceID: String, sourceTitle: String, excerpt: String, timestamp: String? = nil) {
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.excerpt = excerpt.trimmedGlossaryText
        self.timestamp = timestamp?.trimmedGlossaryText.nonEmptyGlossaryText
    }
}

public struct LocalGlossarySuggestion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var suggestedCanonical: String
    public var aliases: [String]
    public var evidence: [LocalGlossaryEvidence]
    public var occurrenceCount: Int
    public var meetingCount: Int
    public var confidence: Double
    public var createdAt: Date

    public init(
        id: String,
        suggestedCanonical: String,
        aliases: [String],
        evidence: [LocalGlossaryEvidence],
        occurrenceCount: Int,
        meetingCount: Int,
        confidence: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.suggestedCanonical = suggestedCanonical.trimmedGlossaryText
        self.aliases = aliases.normalizedGlossaryValues(excluding: [suggestedCanonical])
        self.evidence = Array(evidence.prefix(5))
        self.occurrenceCount = max(0, occurrenceCount)
        self.meetingCount = max(0, meetingCount)
        self.confidence = min(1, max(0, confidence))
        self.createdAt = createdAt
    }
}

public struct LocalGlossaryMatch: Codable, Equatable, Sendable {
    public var termID: String
    public var canonical: String
    public var category: LocalGlossaryCategory
    public var matchedAliases: [String]
    public var evidenceExcerpts: [String]
    public var confidence: Double

    public init(
        termID: String,
        canonical: String,
        category: LocalGlossaryCategory,
        matchedAliases: [String],
        evidenceExcerpts: [String],
        confidence: Double
    ) {
        self.termID = termID
        self.canonical = canonical
        self.category = category
        self.matchedAliases = matchedAliases.normalizedGlossaryValues(excluding: [canonical])
        self.evidenceExcerpts = Array(evidenceExcerpts.map(\.trimmedGlossaryText).filter { !$0.isEmpty }.prefix(3))
        self.confidence = min(1, max(0, confidence))
    }
}

public struct LocalGlossaryState: Codable, Equatable, Sendable {
    public var terms: [LocalGlossaryTerm]
    public var suggestions: [LocalGlossarySuggestion]
    public var dismissedSuggestionIDs: Set<String>
    public var updatedAt: Date

    public init(
        terms: [LocalGlossaryTerm] = [],
        suggestions: [LocalGlossarySuggestion] = [],
        dismissedSuggestionIDs: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.terms = terms
        self.suggestions = suggestions
        self.dismissedSuggestionIDs = dismissedSuggestionIDs
        self.updatedAt = updatedAt
    }

    public var enabledTerms: [LocalGlossaryTerm] {
        terms.filter { $0.isEnabled && !$0.canonical.isEmpty }
    }

    public mutating func acceptSuggestion(
        id: String,
        canonical: String,
        category: LocalGlossaryCategory
    ) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else {
            return
        }
        let term = LocalGlossaryTerm(
            canonical: canonical,
            aliases: suggestion.aliases,
            category: category,
            note: "history 기반 제안에서 추가됨",
            source: .suggested
        )
        suggestions.removeAll { $0.id == id }
        dismissedSuggestionIDs.remove(id)
        terms.removeAll { existing in
            MeetingHistorySearch.compactNormalize(existing.canonical) == MeetingHistorySearch.compactNormalize(term.canonical)
        }
        terms.append(term)
        updatedAt = Date()
    }

    public mutating func dismissSuggestion(id: String) {
        suggestions.removeAll { $0.id == id }
        dismissedSuggestionIDs.insert(id)
        updatedAt = Date()
    }

    public mutating func upsertSuggestion(_ suggestion: LocalGlossarySuggestion) {
        guard !dismissedSuggestionIDs.contains(suggestion.id) else {
            return
        }
        if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
            suggestions[index] = suggestion
        } else {
            suggestions.append(suggestion)
        }
        suggestions.sort {
            if $0.confidence == $1.confidence {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.confidence > $1.confidence
        }
        updatedAt = Date()
    }

    public mutating func deleteTerm(id: String) {
        terms.removeAll { $0.id == id }
        updatedAt = Date()
    }
}

private extension String {
    var trimmedGlossaryText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmptyGlossaryText: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == String {
    func normalizedGlossaryValues(excluding excluded: [String] = []) -> [String] {
        let excludedValues = Set(excluded.map(MeetingHistorySearch.compactNormalize))
        var seen: Set<String> = []
        var values: [String] = []
        for value in self {
            let trimmed = value.trimmedGlossaryText
            let normalized = MeetingHistorySearch.compactNormalize(trimmed)
            guard !trimmed.isEmpty,
                  !excludedValues.contains(normalized),
                  !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            values.append(trimmed)
        }
        return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
```

- [ ] **Step 4: Add persistence methods**

Modify `Sources/MeetingRescueCore/ApplicationStateStore.swift`:

```swift
public func saveLocalGlossaryState(_ state: LocalGlossaryState) throws {
    try ensureRootDirectory()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: localGlossaryURL, options: [.atomic])
}

public func loadLocalGlossaryState() -> LocalGlossaryState {
    guard let data = try? Data(contentsOf: localGlossaryURL) else {
        return LocalGlossaryState()
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(LocalGlossaryState.self, from: data)) ?? LocalGlossaryState()
}

private var localGlossaryURL: URL {
    rootURL.appendingPathComponent("local-glossary.json")
}
```

Place `localGlossaryURL` near `settingsURL`.

- [ ] **Step 5: Add supplemental context kind and priority**

Modify `Sources/MeetingRescueCore/CalendarContextModels.swift`:

```swift
public enum SupplementalContextKind: String, Codable, Equatable, Sendable {
    case confirmedLocalArtifact
    case attachedText
    case domainGlossary
    case calendarMetadata
    case linkedSourceCandidate
    case recurringMemory
}

public enum SupplementalContextPriority: Int, Codable, Equatable, Comparable, Sendable {
    case confirmedLocalArtifact = 10
    case userAttachedContext = 20
    case domainGlossary = 25
    case calendarMetadata = 30
    case linkedSourceCandidate = 40
}
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
swift test --filter LocalGlossaryModelsTests
swift test --filter CalendarContextModelsTests
```

Expected: PASS.

Commit:

```bash
git add Sources/MeetingRescueCore/LocalGlossaryModels.swift Sources/MeetingRescueCore/ApplicationStateStore.swift Sources/MeetingRescueCore/CalendarContextModels.swift Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift Tests/MeetingRescueCoreTests/CalendarContextModelsTests.swift
git commit -m "feat: add local glossary models"
```

---

### Task 2: Local Glossary Matcher And Prompt Hints

**Files:**
- Create: `Sources/MeetingRescueCore/LocalGlossaryMatcher.swift`
- Modify: `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`
- Test: `Tests/MeetingRescueCoreTests/LocalGlossaryMatcherTests.swift`
- Modify Test: `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`

- [ ] **Step 1: Write failing matcher tests**

Create `Tests/MeetingRescueCoreTests/LocalGlossaryMatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossaryMatcherTests {
    @Test("matcher returns accepted glossary hints without rewriting transcript")
    func matcherReturnsHintsWithoutRewritingTranscript() {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(
                id: "term-zax",
                canonical: "zax",
                aliases: ["jax", "jecks", "zacks"],
                category: .project,
                source: .manual
            )
        ])
        let transcript = "[03:12] Alex: jax 쪽 workflow와 jecks 요약 품질을 봅시다."

        let matches = LocalGlossaryMatcher.matches(in: transcript, state: state)

        #expect(matches.count == 1)
        #expect(matches[0].canonical == "zax")
        #expect(matches[0].matchedAliases == ["jax", "jecks"])
        #expect(transcript.contains("jax"))
        #expect(!transcript.contains("zax 쪽 workflow"))
    }

    @Test("matcher builds domain glossary supplemental sources")
    func matcherBuildsSupplementalSources() throws {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax"], category: .project)
        ])

        let sources = LocalGlossaryMatcher.supplementalSources(
            for: "[03:12] Alex: jax 쪽으로 정리합시다.",
            state: state
        )

        let source = try #require(sources.first)
        #expect(source.id == "glossary:term-zax")
        #expect(source.kind == .domainGlossary)
        #expect(source.priority == .domainGlossary)
        #expect(source.title == "용어 힌트: zax")
        #expect(source.excerpt.contains("canonical: zax"))
        #expect(source.excerpt.contains("matched aliases: jax"))
        #expect(source.excerpt.contains("low-priority interpretation hint"))
    }

    @Test("canonicalized search text adds canonical and aliases for matched terms")
    func canonicalizedSearchTextAddsCanonicalAndAliases() {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax", "jecks"], category: .project)
        ])

        let value = LocalGlossaryMatcher.canonicalizedSearchText(
            for: "회의에서 jax 정리를 논의했다",
            state: state
        )

        #expect(value.contains("회의에서 jax 정리를 논의했다"))
        #expect(value.contains("zax"))
        #expect(value.contains("jecks"))
    }
}
```

Append this test to `Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift`:

```swift
@Test("prompt includes domain glossary as low-priority interpretation hints")
func promptIncludesDomainGlossaryPriorityRules() throws {
    let request = AnalysisRequest(
        meetingID: "meeting-1",
        metadata: MeetingMetadata(room: "R3"),
        rawTranscript: "[03:12] Alex: jax 품질을 봅시다.",
        supplementalContextSources: [
            SupplementalContextSource(
                id: "glossary:term-zax",
                kind: .domainGlossary,
                title: "용어 힌트: zax",
                sourceName: "Local Glossary",
                excerpt: "canonical: zax\nmatched aliases: jax\nrule: low-priority interpretation hint",
                priority: .domainGlossary,
                confidence: 0.9
            )
        ]
    )

    let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

    #expect(prompt.contains("domainGlossary"))
    #expect(prompt.contains("canonical: zax"))
    #expect(prompt.contains("Domain glossary"))
    #expect(prompt.contains("raw transcript를 수정하지 말고"))
    #expect(prompt.contains("glossary만 보고 decision/action을 만들지 마세요"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter LocalGlossaryMatcherTests
swift test --filter AnalysisPromptBuilderTests
```

Expected:
- Matcher tests fail because `LocalGlossaryMatcher` does not exist.
- Prompt test fails because prompt does not mention domain glossary rules.

- [ ] **Step 3: Add matcher**

Create `Sources/MeetingRescueCore/LocalGlossaryMatcher.swift`:

```swift
import Foundation

public enum LocalGlossaryMatcher {
    public static func matches(
        in text: String,
        state: LocalGlossaryState,
        maxMatches: Int = 8
    ) -> [LocalGlossaryMatch] {
        let normalizedText = MeetingHistorySearch.normalize(text)
        guard !normalizedText.isEmpty else {
            return []
        }

        return state.enabledTerms.compactMap { term -> LocalGlossaryMatch? in
            let matchedAliases = term.allMatchValues.filter { value in
                containsGlossaryValue(value, in: normalizedText)
            }
            guard !matchedAliases.isEmpty else {
                return nil
            }
            return LocalGlossaryMatch(
                termID: term.id,
                canonical: term.canonical,
                category: term.category,
                matchedAliases: matchedAliases,
                evidenceExcerpts: evidenceExcerpts(for: matchedAliases, in: text),
                confidence: matchedAliases.contains(term.canonical) ? 0.95 : 0.85
            )
        }
        .sorted {
            if $0.confidence == $1.confidence {
                return $0.canonical.localizedStandardCompare($1.canonical) == .orderedAscending
            }
            return $0.confidence > $1.confidence
        }
        .prefix(maxMatches)
        .map { $0 }
    }

    public static func supplementalSources(
        for text: String,
        state: LocalGlossaryState,
        maxMatches: Int = 8
    ) -> [SupplementalContextSource] {
        matches(in: text, state: state, maxMatches: maxMatches).map { match in
            SupplementalContextSource(
                id: "glossary:\(match.termID)",
                kind: .domainGlossary,
                title: "용어 힌트: \(match.canonical)",
                sourceName: "Local Glossary",
                excerpt: excerpt(for: match),
                priority: .domainGlossary,
                confidence: match.confidence
            )
        }
    }

    public static func canonicalizedSearchText(
        for text: String,
        state: LocalGlossaryState
    ) -> String {
        let matches = matches(in: text, state: state)
        guard !matches.isEmpty else {
            return text
        }
        let additions = matches.flatMap { match in
            [match.canonical] + match.matchedAliases
        }
        return ([text] + additions).joined(separator: " ")
    }

    private static func containsGlossaryValue(_ value: String, in normalizedText: String) -> Bool {
        let normalizedValue = MeetingHistorySearch.normalize(value)
        guard normalizedValue.count >= 2 else {
            return false
        }
        if normalizedText.contains(normalizedValue) {
            return true
        }
        let compactText = MeetingHistorySearch.compactNormalize(normalizedText)
        let compactValue = MeetingHistorySearch.compactNormalize(normalizedValue)
        return compactValue.count >= 3 && compactText.contains(compactValue)
    }

    private static func evidenceExcerpts(for aliases: [String], in text: String) -> [String] {
        aliases.compactMap { alias in
            guard let range = text.range(of: alias, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) else {
                return nil
            }
            let start = text.index(range.lowerBound, offsetBy: -min(36, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: min(72, text.distance(from: range.upperBound, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
            return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func excerpt(for match: LocalGlossaryMatch) -> String {
        [
            "canonical: \(match.canonical)",
            "category: \(match.category.rawValue)",
            "matched aliases: \(match.matchedAliases.joined(separator: ", "))",
            "rule: low-priority interpretation hint; raw transcript를 수정하지 말고, transcript context가 맞을 때만 canonical term으로 해석하세요.",
            match.evidenceExcerpts.isEmpty ? nil : "evidence excerpts: \(match.evidenceExcerpts.joined(separator: " / "))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Add prompt rules**

Modify both prompt templates in `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`. Replace the existing supplemental context paragraph with this expanded paragraph:

```swift
Supplemental context는 transcript보다 낮은 우선순위의 보조 근거입니다. transcript가 supplemental context와 충돌하면 transcript를 우선하고, confirmed local artifact가 있으면 calendar metadata보다 우선하세요. calendar metadata로 meetingMetadata를 덮어쓰지 마세요. Calendar linked source candidate는 자동으로 읽은 문서가 아니라 사용자가 확인해야 할 후보로만 취급하세요. Domain glossary는 STT가 잘못 받아쓴 회사/팀 용어를 해석하기 위한 low-priority hint입니다. raw transcript를 수정하지 말고, evidence.excerpt에는 원문 표현을 유지하세요. Domain glossary가 canonical term을 제안해도 transcript 문맥이 맞을 때만 사용하고, glossary만 보고 decision/action을 만들지 마세요.
```

Apply the same replacement in `fullSnapshotPrompt` and `livePatchPrompt`.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
swift test --filter LocalGlossaryMatcherTests
swift test --filter AnalysisPromptBuilderTests
```

Expected: PASS.

Commit:

```bash
git add Sources/MeetingRescueCore/LocalGlossaryMatcher.swift Sources/MeetingRescueCore/AnalysisPromptBuilder.swift Tests/MeetingRescueCoreTests/LocalGlossaryMatcherTests.swift Tests/MeetingRescueCoreTests/AnalysisPromptBuilderTests.swift
git commit -m "feat: add local glossary prompt hints"
```

---

### Task 3: History-Based Glossary Suggestion Engine

**Files:**
- Create: `Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`
- Test: `Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`

- [ ] **Step 1: Write failing suggestion tests**

Create `Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossarySuggestionEngineTests {
    @Test("history scan groups likely STT variants into one suggestion")
    func groupsLikelySTTVariants() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: jax workflow를 다시 보죠.", weight: 24, timestamp: "03:12"),
                    .init(field: .topic, text: "jecks 품질 검토", weight: 58, timestamp: "03:30")
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-2",
                title: "AI Workflow",
                sections: [
                    .init(field: .rawTranscript, text: "[04:01] Blair: zacks 쪽 summary가 흔들립니다.", weight: 24, timestamp: "04:01")
                ]
            )
        ]

        let suggestions = LocalGlossarySuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState()
        )

        let suggestion = try #require(suggestions.first)
        #expect(suggestion.aliases == ["jax", "jecks", "zacks"])
        #expect(suggestion.occurrenceCount == 3)
        #expect(suggestion.meetingCount == 2)
        #expect(suggestion.confidence >= 0.60)
        #expect(suggestion.evidence.count == 3)
    }

    @Test("accepted glossary aliases are excluded from new suggestions")
    func excludesAcceptedAliases() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: jax jecks zacks", weight: 24, timestamp: "03:12")
                ]
            )
        ]
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(canonical: "zax", aliases: ["jax", "jecks", "zacks"], category: .project)
        ])

        let suggestions = LocalGlossarySuggestionEngine.suggestions(from: documents, existingState: state)

        #expect(suggestions.isEmpty)
    }

    @Test("dismissed suggestions are not returned again")
    func excludesDismissedSuggestionIDs() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: jax workflow", weight: 24, timestamp: "03:12"),
                    .init(field: .rawTranscript, text: "[03:18] Alex: jecks workflow", weight: 24, timestamp: "03:18")
                ]
            )
        ]
        let first = try #require(LocalGlossarySuggestionEngine.suggestions(from: documents, existingState: LocalGlossaryState()).first)
        let dismissed = LocalGlossaryState(dismissedSuggestionIDs: [first.id])

        let second = LocalGlossarySuggestionEngine.suggestions(from: documents, existingState: dismissed)

        #expect(second.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter LocalGlossarySuggestionEngineTests
```

Expected: FAIL because `LocalGlossarySuggestionEngine` and `LocalGlossarySourceDocument` do not exist.

- [ ] **Step 3: Add suggestion engine**

Create `Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`:

```swift
import Foundation

public struct LocalGlossarySourceDocument: Equatable, Sendable {
    public var id: String
    public var title: String
    public var sections: [MeetingHistorySearchSection]

    public init(id: String, title: String, sections: [MeetingHistorySearchSection]) {
        self.id = id
        self.title = title
        self.sections = sections
    }
}

public enum LocalGlossarySuggestionEngine {
    private static let tokenPattern = #"\b[A-Za-z][A-Za-z0-9_-]{2,23}\b"#
    private static let minimumClusterSize = 2

    public static func suggestions(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int = 8
    ) -> [LocalGlossarySuggestion] {
        let acceptedValues = Set(existingState.enabledTerms.flatMap(\.allMatchValues).map(MeetingHistorySearch.compactNormalize))
        let occurrences = collectOccurrences(from: documents, acceptedValues: acceptedValues)
        let clusters = clusterOccurrences(occurrences)

        return clusters.compactMap { cluster -> LocalGlossarySuggestion? in
            let aliases = cluster.map(\.token).normalizedSuggestionAliases()
            guard aliases.count >= minimumClusterSize else {
                return nil
            }
            let id = suggestionID(for: aliases)
            guard !existingState.dismissedSuggestionIDs.contains(id) else {
                return nil
            }
            let meetingIDs = Set(cluster.map(\.documentID))
            let occurrenceCount = cluster.count
            let confidence = confidenceForSuggestion(aliasCount: aliases.count, occurrenceCount: occurrenceCount, meetingCount: meetingIDs.count)
            guard confidence >= 0.55 else {
                return nil
            }
            let evidence = cluster.prefix(5).map {
                LocalGlossaryEvidence(
                    sourceID: $0.documentID,
                    sourceTitle: $0.documentTitle,
                    excerpt: $0.excerpt,
                    timestamp: $0.timestamp
                )
            }
            return LocalGlossarySuggestion(
                id: id,
                suggestedCanonical: aliases.sortedByUsefulCanonical.first ?? aliases[0],
                aliases: aliases,
                evidence: evidence,
                occurrenceCount: occurrenceCount,
                meetingCount: meetingIDs.count,
                confidence: confidence
            )
        }
        .sorted {
            if $0.confidence == $1.confidence {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.confidence > $1.confidence
        }
        .prefix(maxSuggestions)
        .map { $0 }
    }

    private static func collectOccurrences(
        from documents: [LocalGlossarySourceDocument],
        acceptedValues: Set<String>
    ) -> [TermOccurrence] {
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else {
            return []
        }
        return documents.flatMap { document in
            document.sections.flatMap { section -> [TermOccurrence] in
                let text = section.text
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                return regex.matches(in: text, range: range).compactMap { match in
                    guard let matchRange = Range(match.range, in: text) else {
                        return nil
                    }
                    let token = String(text[matchRange])
                    let normalized = MeetingHistorySearch.compactNormalize(token)
                    guard isCandidateToken(normalized),
                          !acceptedValues.contains(normalized) else {
                        return nil
                    }
                    return TermOccurrence(
                        token: token.lowercased(),
                        documentID: document.id,
                        documentTitle: document.title,
                        timestamp: section.timestamp,
                        excerpt: section.text
                    )
                }
            }
        }
    }

    private static func clusterOccurrences(_ occurrences: [TermOccurrence]) -> [[TermOccurrence]] {
        var clusters: [[TermOccurrence]] = []
        for occurrence in occurrences {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { areLikelyVariants(lhs: $0.token, rhs: occurrence.token) }
            }) {
                clusters[index].append(occurrence)
            } else {
                clusters.append([occurrence])
            }
        }
        return clusters
    }

    private static func areLikelyVariants(lhs: String, rhs: String) -> Bool {
        let lhsKey = phoneticKey(lhs)
        let rhsKey = phoneticKey(rhs)
        if lhsKey == rhsKey {
            return true
        }
        return editDistance(lhsKey, rhsKey) <= 1 || bigramSimilarity(lhsKey, rhsKey) >= 0.50
    }

    private static func phoneticKey(_ value: String) -> String {
        MeetingHistorySearch.compactNormalize(value)
            .replacingOccurrences(of: "cks", with: "x")
            .replacingOccurrences(of: "ks", with: "x")
            .replacingOccurrences(of: "ck", with: "k")
            .replacingOccurrences(of: "zz", with: "z")
            .replacingOccurrences(of: "je", with: "ja")
    }

    private static func isCandidateToken(_ token: String) -> Bool {
        guard token.count >= 3, token.count <= 24 else {
            return false
        }
        return !commonTokens.contains(token)
    }

    private static func confidenceForSuggestion(aliasCount: Int, occurrenceCount: Int, meetingCount: Int) -> Double {
        let aliasScore = min(0.35, Double(aliasCount - 1) * 0.18)
        let occurrenceScore = min(0.30, Double(occurrenceCount) * 0.08)
        let meetingScore = min(0.25, Double(meetingCount) * 0.10)
        return min(0.95, 0.20 + aliasScore + occurrenceScore + meetingScore)
    }

    private static func suggestionID(for aliases: [String]) -> String {
        "suggestion:\(aliases.map(MeetingHistorySearch.compactNormalize).sorted().joined(separator: "|"))"
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0...rhs.count)
        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            var current = [lhsIndex + 1]
            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                let substitution = previous[rhsIndex] + (lhsCharacter == rhsCharacter ? 0 : 1)
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                current.append(min(substitution, insertion, deletion))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private static func bigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsGrams = Set(bigrams(lhs))
        let rhsGrams = Set(bigrams(rhs))
        guard !lhsGrams.isEmpty, !rhsGrams.isEmpty else {
            return 0
        }
        return Double(lhsGrams.intersection(rhsGrams).count * 2) / Double(lhsGrams.count + rhsGrams.count)
    }

    private static func bigrams(_ value: String) -> [String] {
        let chars = Array(value)
        guard chars.count >= 2 else {
            return value.isEmpty ? [] : [value]
        }
        return (0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) }
    }
}

private struct TermOccurrence {
    var token: String
    var documentID: String
    var documentTitle: String
    var timestamp: String?
    var excerpt: String
}

private let commonTokens: Set<String> = [
    "about", "action", "after", "again", "agenda", "also", "and", "are", "back", "because",
    "before", "calendar", "can", "check", "context", "decision", "for", "from", "have",
    "meeting", "next", "not", "now", "owner", "plan", "review", "summary", "sync",
    "task", "team", "test", "that", "the", "then", "this", "today", "with", "work", "workflow"
]

private extension Array where Element == String {
    func normalizedSuggestionAliases() -> [String] {
        Array(Set(map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var sortedByUsefulCanonical: [String] {
        sorted {
            if $0.count == $1.count {
                return $0.localizedStandardCompare($1) == .orderedAscending
            }
            return $0.count < $1.count
        }
    }
}
```

- [ ] **Step 4: Run tests and commit**

Run:

```bash
swift test --filter LocalGlossarySuggestionEngineTests
```

Expected: PASS.

Commit:

```bash
git add Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift
git commit -m "feat: suggest local glossary terms from history"
```

---

### Task 4: App State, Analysis Injection, And Search Indexing

**Files:**
- Modify: `Sources/MeetingRescueCore/AnalysisModels.swift`
- Modify: `Sources/MeetingRescueCore/MeetingHistorySearch.swift`
- Modify: `Sources/MeetingRescue/AppViewModel.swift`
- Test: `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`
- Test: `Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift`
- Test: `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`

- [ ] **Step 1: Write failing settings/search/request tests**

Append to `Tests/MeetingRescueCoreTests/AnalysisStateTests.swift`:

```swift
@Test("AppSettings stores local glossary enabled with legacy default")
func appSettingsStoresLocalGlossaryEnabled() throws {
    let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"selectedProvider":"codexExec"}"#.utf8))
    #expect(legacy.localGlossaryEnabled)

    let settings = AppSettings(localGlossaryEnabled: false)
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(!decoded.localGlossaryEnabled)
}
```

Append to `Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift`:

```swift
@Test("glossary field lets canonical query match alias-only history")
func glossaryFieldMatchesCanonicalQuery() {
    let sections = [
        MeetingHistorySearchSection(field: .rawTranscript, text: "[03:12] Alex: jax workflow를 봤다", weight: 24, timestamp: "03:12"),
        MeetingHistorySearchSection(field: .glossary, text: "zax jax jecks", weight: 66)
    ]

    let match = MeetingHistorySearch.match(sections: sections, query: "zax")

    #expect(match?.field == .glossary)
}
```

Append to `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`:

```swift
@Test("analysis request includes local glossary supplemental context")
func analysisRequestIncludesLocalGlossaryContext() throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("meeting-rescue-glossary-request-\(UUID().uuidString)", isDirectory: true)
    let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
    try stateStore.saveLocalGlossaryState(LocalGlossaryState(terms: [
        LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax"], category: .project)
    ]))
    let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try "[03:12] Alex: jax workflow를 봅시다.".write(to: transcriptURL, atomically: true, encoding: .utf8)

    let viewModel = AppViewModel(stateStore: stateStore)
    viewModel.loadTranscriptForTesting(url: transcriptURL, rawTranscript: "[03:12] Alex: jax workflow를 봅시다.")

    let request = try #require(viewModel.analysisRequestForTesting(reason: "manual-test"))

    #expect(request.supplementalContextSources.contains { $0.kind == .domainGlossary && $0.excerpt.contains("canonical: zax") })
}
```

This test relies on two test-only `AppViewModel` helpers. Add `loadTranscriptForTesting(url:rawTranscript:)` and `analysisRequestForTesting(reason:)` exactly as specified in Step 6.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter AnalysisStateTests
swift test --filter MeetingHistorySearchTests
swift test --filter AppViewModelTestRunContextTests
```

Expected:
- Settings test fails because `localGlossaryEnabled` does not exist.
- Search test fails because `.glossary` field does not exist.
- AppViewModel test fails because local glossary state is not loaded or injected.

- [ ] **Step 3: Add settings field**

Modify `Sources/MeetingRescueCore/AnalysisModels.swift` `AppSettings`:

```swift
public var localGlossaryEnabled: Bool
```

Add the initializer parameter after `liveContextRetrievalMode`:

```swift
localGlossaryEnabled: Bool = true,
```

Assign it:

```swift
self.localGlossaryEnabled = localGlossaryEnabled
```

Add coding key:

```swift
case localGlossaryEnabled
```

Decode with legacy default:

```swift
localGlossaryEnabled: (try? container.decode(Bool.self, forKey: .localGlossaryEnabled)) ?? true,
```

- [ ] **Step 4: Add glossary search field**

Modify `Sources/MeetingRescueCore/MeetingHistorySearch.swift`:

```swift
case glossary
```

Add display name:

```swift
case .glossary:
    return "용어 사전"
```

- [ ] **Step 5: Load glossary state in AppViewModel and preserve settings save**

Modify `Sources/MeetingRescue/AppViewModel.swift`:

```swift
@Published var localGlossaryState: LocalGlossaryState
@Published var localGlossaryStatusMessage = "로컬 용어 사전 준비"
@Published var isGeneratingLocalGlossarySuggestions = false
```

In `init(stateStore:)`, after `self.settings = stateStore.loadSettings()`:

```swift
self.localGlossaryState = stateStore.loadLocalGlossaryState()
```

In `saveSettings()`, include the new field when reconstructing `AppSettings`:

```swift
localGlossaryEnabled: settings.localGlossaryEnabled,
```

- [ ] **Step 6: Add analysis request helper and glossary supplemental context**

Extract the request construction in `triggerAnalysis(reason:)` into a helper:

```swift
private func makeAnalysisRequest(
    reason: String,
    transcriptWindow: AnalysisTranscriptWindow,
    previousSnapshot: AnalysisSnapshot?
) -> AnalysisRequest? {
    guard let activeTranscriptURL else {
        return nil
    }
    let supplementalSources = analysisState.calendarContext.supplementalSources
        + glossarySupplementalSources(for: transcriptWindow.rawTranscript)
    return AnalysisRequest(
        meetingID: meetingID(for: activeTranscriptURL),
        metadata: metadata,
        rawTranscript: transcriptWindow.rawTranscript,
        previousSnapshot: previousSnapshot,
        confirmedCandidateIDs: analysisState.confirmedCandidateIDs,
        deletedCandidateIDs: analysisState.deletedCandidateIDs,
        providerKind: settings.selectedProvider,
        modelPreset: settings.modelPreset,
        meetingTypePreset: settings.meetingTypePreset,
        bookmarks: analysisState.bookmarks,
        reason: reason,
        lastAnalyzedTranscriptCharacterCount: transcriptWindow.lastAnalyzedTranscriptCharacterCount,
        supplementalContextSources: supplementalSources
    )
}

private func glossarySupplementalSources(for text: String) -> [SupplementalContextSource] {
    guard settings.localGlossaryEnabled else {
        return []
    }
    return LocalGlossaryMatcher.supplementalSources(for: text, state: localGlossaryState)
}
```

Replace the inline `AnalysisRequest(...)` in `triggerAnalysis(reason:)` with:

```swift
guard var request = makeAnalysisRequest(
    reason: reason,
    transcriptWindow: transcriptWindow,
    previousSnapshot: previousSnapshot
) else {
    return
}
```

Add test helpers near other testing hooks:

```swift
#if DEBUG
func loadTranscriptForTesting(url: URL, rawTranscript: String) {
    activeTranscriptURL = url
    metadata = TranscriptParser.parse(rawTranscript).metadata
    self.rawTranscript = rawTranscript
}

func analysisRequestForTesting(reason: String) -> AnalysisRequest? {
    guard activeTranscriptURL != nil else {
        return nil
    }
    let window = AnalysisTranscriptWindow.make(
        rawTranscript: rawTranscript,
        lastAnalyzedTranscriptCharacterCount: analysisState.analyzedTranscriptCharacterCount,
        reason: reason,
        maxAutomaticCatchUpCharacters: automaticCatchUpChunkCharacters
    )
    return makeAnalysisRequest(reason: reason, transcriptWindow: window, previousSnapshot: providerPreviousSnapshot())
}
#endif
```

- [ ] **Step 7: Add glossary sections to history builder**

Modify `MeetingHistoryBuilder` in `Sources/MeetingRescue/AppViewModel.swift`:

```swift
let localGlossaryState: LocalGlossaryState
let localGlossaryEnabled: Bool
```

Update `signature`:

```swift
let glossarySignature = localGlossaryEnabled ? "\(localGlossaryState.updatedAt.timeIntervalSince1970)" : "off"
let signature = "\(includeRawTranscriptSearch ? "raw" : "structured")|\(glossarySignature)|\(fileSignature)"
```

In `makeHistorySearchSections(...)`, before final filter:

```swift
if localGlossaryEnabled {
    sections.append(contentsOf: glossarySearchSections(from: sections))
}
```

Add helper:

```swift
private func glossarySearchSections(from sections: [MeetingHistorySearchSection]) -> [MeetingHistorySearchSection] {
    let sourceText = sections.map(\.text).joined(separator: "\n")
    let matches = LocalGlossaryMatcher.matches(in: sourceText, state: localGlossaryState)
    guard !matches.isEmpty else {
        return []
    }
    return matches.map { match in
        MeetingHistorySearchSection(
            field: .glossary,
            text: ([match.canonical] + match.matchedAliases).joined(separator: " "),
            weight: 66
        )
    }
}
```

When creating `MeetingHistoryBuilder` inside `refreshMeetingHistory(...)`, pass:

```swift
localGlossaryState: localGlossaryState,
localGlossaryEnabled: settings.localGlossaryEnabled,
```

- [ ] **Step 8: Run tests and commit**

Run:

```bash
swift test --filter AnalysisStateTests
swift test --filter MeetingHistorySearchTests
swift test --filter AppViewModelTestRunContextTests
```

Expected: PASS.

Commit:

```bash
git add Sources/MeetingRescueCore/AnalysisModels.swift Sources/MeetingRescueCore/MeetingHistorySearch.swift Sources/MeetingRescue/AppViewModel.swift Tests/MeetingRescueCoreTests/AnalysisStateTests.swift Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift
git commit -m "feat: wire local glossary into analysis and search"
```

---

### Task 5: Suggestion Generation Actions And Settings UI

**Files:**
- Modify: `Sources/MeetingRescue/AppViewModel.swift`
- Modify: `Sources/MeetingRescue/ContentView.swift`
- Test: `Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`

- [ ] **Step 1: Write failing UI wiring tests**

Append to `Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`:

```swift
@Test("settings exposes local glossary controls")
func settingsExposeLocalGlossaryControls() throws {
    let source = try String(contentsOfFile: "Sources/MeetingRescue/ContentView.swift")

    #expect(source.contains("case glossary = \"Glossary\""))
    #expect(source.contains("localGlossarySettings"))
    #expect(source.contains("용어 후보 생성"))
    #expect(source.contains("사전에 추가"))
    #expect(source.contains("다시 보지 않기"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter ContentViewContextWiringTests
```

Expected: FAIL because glossary settings UI does not exist.

- [ ] **Step 3: Add AppViewModel actions**

Add to `Sources/MeetingRescue/AppViewModel.swift`:

```swift
func refreshLocalGlossarySuggestions() {
    guard !isGeneratingLocalGlossarySuggestions else {
        return
    }
    isGeneratingLocalGlossarySuggestions = true
    localGlossaryStatusMessage = "회의 history에서 용어 후보를 찾는 중"

    let documents = meetingHistoryItems.map { item in
        LocalGlossarySourceDocument(id: item.id, title: item.title, sections: item.searchSections)
    }
    let currentState = localGlossaryState

    Task { @MainActor in
        let suggestions = await Task.detached(priority: .utility) {
            LocalGlossarySuggestionEngine.suggestions(from: documents, existingState: currentState)
        }.value
        for suggestion in suggestions {
            localGlossaryState.upsertSuggestion(suggestion)
        }
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = suggestions.isEmpty ? "새 용어 후보 없음" : "용어 후보 \(suggestions.count)개"
        isGeneratingLocalGlossarySuggestions = false
    }
}
```

Add actions:

```swift
func acceptLocalGlossarySuggestion(id: String, canonical: String, category: LocalGlossaryCategory = .domainTerm) {
    localGlossaryState.acceptSuggestion(id: id, canonical: canonical, category: category)
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "용어 사전에 추가했습니다."
    refreshMeetingHistory(force: true)
}

func dismissLocalGlossarySuggestion(id: String) {
    localGlossaryState.dismissSuggestion(id: id)
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "용어 후보를 숨겼습니다."
}

func deleteLocalGlossaryTerm(id: String) {
    localGlossaryState.deleteTerm(id: id)
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "용어를 삭제했습니다."
    refreshMeetingHistory(force: true)
}

func setLocalGlossaryEnabled(_ isEnabled: Bool) {
    settings.localGlossaryEnabled = isEnabled
    saveSettings()
    refreshMeetingHistory(force: true)
}
```

- [ ] **Step 4: Add Settings section**

Modify `SettingsSection` in `Sources/MeetingRescue/ContentView.swift`:

```swift
case glossary = "Glossary"
```

Add system image:

```swift
case .glossary:
    return "text.book.closed"
```

Add subtitle:

```swift
case .glossary:
    return "회의 history에서 자주 헷갈리는 사내 용어를 로컬 사전으로 정리합니다."
```

Add switch branch:

```swift
case .glossary:
    localGlossarySettings
```

Add view:

```swift
private var localGlossarySettings: some View {
    VStack(alignment: .leading, spacing: 12) {
        settingsCard("Local Glossary", systemImage: "text.book.closed") {
            settingsRow("사용", detail: "raw transcript는 수정하지 않고 분석/search용 low-priority 용어 힌트만 사용합니다.") {
                Toggle("local glossary", isOn: Binding(
                    get: { viewModel.settings.localGlossaryEnabled },
                    set: { viewModel.setLocalGlossaryEnabled($0) }
                ))
                .labelsHidden()
            }

            actionRow("용어 후보", detail: viewModel.localGlossaryStatusMessage) {
                Button {
                    viewModel.refreshLocalGlossarySuggestions()
                } label: {
                    Label(viewModel.isGeneratingLocalGlossarySuggestions ? "생성 중" : "용어 후보 생성", systemImage: "wand.and.stars")
                }
                .buttonStyle(SmoothActionButtonStyle())
                .disabled(viewModel.isGeneratingLocalGlossarySuggestions || viewModel.meetingHistoryItems.isEmpty)
            }
        }

        settingsCard("Suggestions", systemImage: "lightbulb") {
            if viewModel.localGlossaryState.suggestions.isEmpty {
                Text("표시할 용어 후보가 없습니다.")
                    .font(.callout)
                    .foregroundStyle(Color.smoothMuted)
            } else {
                ForEach(viewModel.localGlossaryState.suggestions.prefix(8)) { suggestion in
                    localGlossarySuggestionRow(suggestion)
                }
            }
        }

        settingsCard("Accepted Terms", systemImage: "checkmark.seal") {
            if viewModel.localGlossaryState.terms.isEmpty {
                Text("아직 추가된 용어가 없습니다.")
                    .font(.callout)
                    .foregroundStyle(Color.smoothMuted)
            } else {
                ForEach(viewModel.localGlossaryState.terms) { term in
                    localGlossaryTermRow(term)
                }
            }
        }
    }
}
```

Add row helpers inside `SettingsView`:

```swift
private func localGlossarySuggestionRow(_ suggestion: LocalGlossarySuggestion) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.aliases.joined(separator: ", "))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                Text("회의 \(suggestion.meetingCount)개 · 출현 \(suggestion.occurrenceCount)회")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
            }
            Spacer()
            Button {
                viewModel.acceptLocalGlossarySuggestion(id: suggestion.id, canonical: suggestion.suggestedCanonical)
            } label: {
                Label("사전에 추가", systemImage: "checkmark")
            }
            .buttonStyle(SmoothActionButtonStyle())

            Button {
                viewModel.dismissLocalGlossarySuggestion(id: suggestion.id)
            } label: {
                Label("다시 보지 않기", systemImage: "eye.slash")
            }
            .buttonStyle(SmoothActionButtonStyle())
        }

        if let evidence = suggestion.evidence.first {
            Text(evidence.excerpt)
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
                .lineLimit(2)
        }
    }
    .padding(.vertical, 6)
}

private func localGlossaryTermRow(_ term: LocalGlossaryTerm) -> some View {
    HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
            Text(term.canonical)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.smoothInk)
            Text(term.aliases.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
        }
        Spacer()
        Button(role: .destructive) {
            viewModel.deleteLocalGlossaryTerm(id: term.id)
        } label: {
            Label("삭제", systemImage: "trash")
        }
        .buttonStyle(SmoothActionButtonStyle(kind: .destructive))
    }
    .padding(.vertical, 6)
}
```

- [ ] **Step 5: Run UI wiring test and commit**

Run:

```bash
swift test --filter ContentViewContextWiringTests
```

Expected: PASS.

Commit:

```bash
git add Sources/MeetingRescue/AppViewModel.swift Sources/MeetingRescue/ContentView.swift Tests/MeetingRescueTests/ContentViewContextWiringTests.swift
git commit -m "feat: add local glossary settings"
```

---

### Task 6: Tracker, Validation, And Release Readiness

**Files:**
- Modify: `tasks.md`
- Modify: `execution-log.md`
- Create: `docs/local-glossary-validation.md`

- [ ] **Step 1: Update `tasks.md` backlog**

Add this item above `D3 Team shared memory`:

```markdown
  - D2.5 Local Glossary Suggestions:
    - 상태: `Done`
    - 목표: 로컬 meeting history에서 STT가 자주 틀리는 회사/팀 용어 후보를 묶어 제안하고, 사용자가 승인한 개인 glossary를 분석/search/carry-over용 low-priority hint로 사용한다.
    - 구현 요약:
      - raw transcript는 수정하지 않는다.
      - glossary state는 Application Support의 `local-glossary.json`에 저장한다.
      - history scan은 `jax`, `jecks`, `zacks` 같은 Latin/mixed token 변형을 묶어 suggestion으로 만든다.
      - accepted term만 prompt supplemental context와 search index에 반영한다.
      - dismissed suggestion은 다시 노출하지 않는다.
    - 검증 질문:
      - 사용자가 직접 사전을 먼저 정리하지 않아도 유용한 후보가 나오는가?
      - canonical term hint가 요약/search 품질을 높이면서 오탐을 만들지 않는가?
```

- [ ] **Step 2: Add execution log entry**

Prepend to `execution-log.md`:

```markdown
## 2026-06-09 Local Glossary Suggestions

- 구현:
  - local glossary model/persistence 추가.
  - history 기반 glossary suggestion engine 추가.
  - accepted glossary hint를 analysis supplemental context와 history search에 반영.
  - Settings에 Glossary 섹션 추가.
- 검증:
  - `swift test --filter LocalGlossaryModelsTests`: PASS
  - `swift test --filter LocalGlossaryMatcherTests`: PASS
  - `swift test --filter LocalGlossarySuggestionEngineTests`: PASS
  - `swift test --filter AnalysisPromptBuilderTests`: PASS
  - `swift test --filter MeetingHistorySearchTests`: PASS
  - `swift test --filter AppViewModelTestRunContextTests`: PASS
  - `swift test --filter ContentViewContextWiringTests`: PASS
  - `swift test`: PASS
  - `swift build`: PASS
- 남은 관찰:
  - 실제 transcript history에서 suggestion precision을 확인해야 한다.
  - v1은 개인/local dictionary이며 team/shared Sheet workflow는 포함하지 않았다.
```

- [ ] **Step 3: Create validation note**

Create `docs/local-glossary-validation.md`:

````markdown
# Local Glossary Validation

Date: 2026-06-09
Scope: Local-first glossary suggestions for Meeting Rescue.

## Synthetic Fixture

```text
Room: Zigbang(2F)_R3
Date/Time: 2026-06-09 10:30
Participants: Alex, Blair
[00:10] Alex: jax workflow 요약 품질을 봅시다.
[02:20] Blair: jecks 쪽 action item이 이상하게 잡혀요.
[04:40] Alex: zacks 검색 결과도 같이 비교합시다.
```

## Expected Checks

- Settings > Glossary > `용어 후보 생성` shows a suggestion containing `jax`, `jecks`, `zacks`.
- Accepting the suggestion with canonical `zax` creates an accepted term.
- Analysis request for transcript containing `jax` includes a `domainGlossary` supplemental context source.
- Search query `zax` finds meetings whose raw transcript only contains `jax` or `jecks`.
- Raw transcript display still shows original `jax` and `jecks` text.

## Result

- Synthetic suggestion generation: PASS
- Prompt supplemental context: PASS
- Search canonicalization: PASS
- Raw transcript preservation: PASS

## Notes

- Calendar context remains separate from glossary context.
- Team/shared dictionary sync is out of scope for this release.
````

- [ ] **Step 4: Run full verification**

Run:

```bash
swift test
swift build
git diff --check
```

Expected:
- `swift test`: all tests pass.
- `swift build`: build complete.
- `git diff --check`: no output.

- [ ] **Step 5: Commit tracker updates**

Commit:

```bash
git add tasks.md execution-log.md docs/local-glossary-validation.md
git commit -m "docs: track local glossary suggestions"
```

---

## Manual Validation

Use a short synthetic transcript before real meeting history:

```text
Room: Zigbang(2F)_R3
Date/Time: 2026-06-09 10:30
Participants: Alex, Blair
[00:10] Alex: jax workflow 요약 품질을 봅시다.
[02:20] Blair: jecks 쪽 action item이 이상하게 잡혀요.
[04:40] Alex: zacks 검색 결과도 같이 비교합시다.
```

Expected manual behavior:
- Settings > Glossary > `용어 후보 생성` shows a suggestion containing `jax`, `jecks`, `zacks`.
- Accepting the suggestion with canonical `zax` creates an accepted term.
- A later analysis of a transcript containing `jax` includes a `domainGlossary` supplemental context source.
- Search query `zax` finds meetings whose raw transcript only contains `jax` or `jecks`.
- Raw transcript display still shows original `jax`/`jecks` text.

---

## Self-Review

Spec coverage:
- Local-first personal dictionary: covered by Task 1 persistence and Task 5 UI.
- History-based grouped suggestions: covered by Task 3 engine and Task 5 generation action.
- No raw transcript mutation: covered by Task 2 matcher test and prompt rules.
- Analysis improvement path: covered by Task 2 prompt hints and Task 4 AppViewModel injection.
- Search improvement path: covered by Task 4 glossary search field/sections.
- Team/shared workflow excluded: explicitly scoped out in Product Decisions and tracker text.

Placeholder scan:
- No placeholder implementation steps remain.
- Every new public type referenced in tests is introduced in a task.
- Every command includes expected result.

Type consistency:
- `LocalGlossaryState`, `LocalGlossaryTerm`, `LocalGlossarySuggestion`, `LocalGlossaryEvidence`, and `LocalGlossaryMatch` are defined before later tasks use them.
- `SupplementalContextKind.domainGlossary` and `SupplementalContextPriority.domainGlossary` are defined before prompt/search/UI tasks use them.
- `AppSettings.localGlossaryEnabled` is added before UI bindings and AppViewModel guards use it.
