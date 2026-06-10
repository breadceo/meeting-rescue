# Local Glossary Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move local glossary suggestions from a Settings-only MVP into the meeting analysis workflow, scan raw transcript history directly, and add Korean phrase suggestions with calibrated thresholds.

**Architecture:** Add a dedicated raw transcript history scanner in `MeetingRescueCore` so suggestion generation does not depend on visible `meetingHistoryItems.searchSections`. Keep the existing Latin/mixed token lane and add a separate Korean phrase lane, then merge both through `LocalGlossarySuggestionEngine`. Expose review/accept inside Meeting Intelligence `용어`, with raw transcript showing only a compact CTA/status footer and Settings reduced to management controls.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, local JSON persistence via `ApplicationStateStore`, existing `LocalGlossaryState`, `MeetingHistorySearchSection`, and `SupplementalContextSource`.

---

## Product Decisions

- Raw transcript remains the source of truth and is never rewritten.
- Suggestion generation scans raw local transcript files, not only the currently visible history search sections.
- Korean suggestions are never auto-applied. They become prompt/search hints only after the user confirms or edits the canonical term.
- The first Korean lane uses deterministic phrase extraction and similarity thresholds from `docs/local-glossary-korean-calibration.md`.
- Settings keeps glossary enable/delete management. Review, refresh, canonical editing, and evidence inspection live in Meeting Intelligence `용어`.
- Raw Transcript shows only a small `용어 후보 N개` / `용어 힌트 N개` CTA that switches to the Intelligence `용어` lane.

## File Structure

- Create `Sources/MeetingRescueCore/LocalGlossaryHistoryScanner.swift`
  - Builds `LocalGlossarySourceDocument` values directly from transcript files in the selected folder.
  - Includes raw transcript sections regardless of history search UI state.
- Create `Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift`
  - Extracts Korean tokens and short adjacent phrases.
  - Scores candidate pairs with syllable, jamo, bigram, and initial-consonant similarity.
  - Applies calibrated high-confidence and context-confirmed gates.
- Modify `Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`
  - Keep the existing Latin/mixed lane.
  - Merge Korean suggestions and dedupe by suggestion id.
- Modify `Sources/MeetingRescue/AppViewModel.swift`
  - Generate suggestions from `LocalGlossaryHistoryScanner`.
  - Expose glossary review counts for UI.
  - Accept suggestions with user-edited canonical strings.
- Modify `Sources/MeetingRescue/ContentView.swift`
  - Add Meeting Intelligence `용어` lane.
  - Add canonical editing rows for suggestions.
  - Add raw transcript footer CTA.
  - Reduce Settings glossary section to enable/delete management.
- Modify `Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`
  - Add Korean lane tests and merge tests.
- Create `Tests/MeetingRescueCoreTests/LocalGlossaryHistoryScannerTests.swift`
  - Verify scanner includes raw transcript sections independent of UI history state.
- Modify `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`
  - Verify AppViewModel uses the raw history scanner path.
- Modify `Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`
  - Verify the `용어` lane and raw transcript CTA are wired.
- Modify `tasks.md` and `execution-log.md`
  - Track D2.6 status and validation notes.

---

### Task 1: Raw Transcript History Scanner

**Files:**
- Create: `Sources/MeetingRescueCore/LocalGlossaryHistoryScanner.swift`
- Create: `Tests/MeetingRescueCoreTests/LocalGlossaryHistoryScannerTests.swift`

- [ ] **Step 1: Write failing scanner tests**

Create `Tests/MeetingRescueCoreTests/LocalGlossaryHistoryScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossaryHistoryScannerTests {
    @Test("scanner builds raw transcript documents from folder files")
    func scannerBuildsRawTranscriptDocuments() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-scanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("20260610_103000_Zigbang_R3.txt")
        let second = root.appendingPathComponent("20260611_103000_Zigbang_R3.txt")
        try """
        Room: Zigbang_R3
        Date/Time: 2026-06-10 10:30
        Participants: Ethan
        [00:10] Ethan: jax workflow를 봅니다.
        [00:20] Ethan: 중계사 응답률 채팅을 확인합니다.
        """.write(to: first, atomically: true, encoding: .utf8)
        try """
        Room: Zigbang_R3
        Date/Time: 2026-06-11 10:30
        Participants: Ethan
        [00:10] Ethan: jecks workflow를 봅니다.
        [00:20] Ethan: 중개사 응답률 채팅을 확인합니다.
        """.write(to: second, atomically: true, encoding: .utf8)

        let documents = LocalGlossaryHistoryScanner.documents(
            in: root,
            configuration: .init(maxDocuments: 10, maxBytesPerDocument: 16_384, rawTranscriptLineLimit: 20)
        )

        #expect(documents.count == 2)
        #expect(documents.allSatisfy { document in
            document.sections.contains { $0.field == .rawTranscript }
        })
        #expect(documents.map(\.id).contains(first.path))
        #expect(documents.flatMap(\.sections).contains { section in
            section.field == .rawTranscript && section.text.contains("중개사 응답률 채팅")
        })
    }

    @Test("scanner respects max document and line limits")
    func scannerRespectsLimits() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-scanner-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<3 {
            let url = root.appendingPathComponent("meeting-\(index).txt")
            try """
            [00:01] Ethan: 첫 줄 \(index)
            [00:02] Ethan: 둘째 줄 \(index)
            """.write(to: url, atomically: true, encoding: .utf8)
        }

        let documents = LocalGlossaryHistoryScanner.documents(
            in: root,
            configuration: .init(maxDocuments: 2, maxBytesPerDocument: 16_384, rawTranscriptLineLimit: 1)
        )

        #expect(documents.count == 2)
        #expect(documents.allSatisfy { document in
            document.sections.filter { $0.field == .rawTranscript }.count == 1
        })
    }
}
```

- [ ] **Step 2: Run scanner tests to verify they fail**

Run:

```bash
swift test --filter LocalGlossaryHistoryScannerTests
```

Expected: FAIL because `LocalGlossaryHistoryScanner` does not exist.

- [ ] **Step 3: Add scanner implementation**

Create `Sources/MeetingRescueCore/LocalGlossaryHistoryScanner.swift`:

```swift
import Foundation

public struct LocalGlossaryHistoryScannerConfiguration: Equatable, Sendable {
    public var maxDocuments: Int
    public var maxBytesPerDocument: Int
    public var rawTranscriptLineLimit: Int

    public init(
        maxDocuments: Int = 120,
        maxBytesPerDocument: Int = 96_000,
        rawTranscriptLineLimit: Int = 360
    ) {
        self.maxDocuments = max(1, maxDocuments)
        self.maxBytesPerDocument = max(1_024, maxBytesPerDocument)
        self.rawTranscriptLineLimit = max(1, rawTranscriptLineLimit)
    }
}

public enum LocalGlossaryHistoryScanner {
    public static func documents(
        in folderURL: URL,
        configuration: LocalGlossaryHistoryScannerConfiguration = .init(),
        fileManager: FileManager = .default
    ) -> [LocalGlossarySourceDocument] {
        LatestTranscriptSelector.textFiles(in: folderURL, fileManager: fileManager)
            .sorted { lhs, rhs in
                if lhs.modificationDate == rhs.modificationDate {
                    return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedDescending
                }
                return lhs.modificationDate > rhs.modificationDate
            }
            .prefix(configuration.maxDocuments)
            .compactMap { candidate in
                document(from: candidate, configuration: configuration)
            }
    }

    private static func document(
        from candidate: TranscriptFileCandidate,
        configuration: LocalGlossaryHistoryScannerConfiguration
    ) -> LocalGlossarySourceDocument? {
        let text = readPrefix(from: candidate.url, byteLimit: configuration.maxBytesPerDocument)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let parsed = TranscriptParser.parse(text)
        let metadata = parsed.metadata
        let title = metadata.displayTitle.isEmpty
            ? candidate.url.deletingPathExtension().lastPathComponent
            : metadata.displayTitle
        var sections: [MeetingHistorySearchSection] = [
            .init(field: .title, text: title, weight: 92),
            .init(field: .file, text: candidate.url.deletingPathExtension().lastPathComponent, weight: 60)
        ]
        if let room = metadata.room, !room.isEmpty {
            sections.append(.init(field: .room, text: room, weight: 78))
        }
        if let dateTime = metadata.dateTime, !dateTime.isEmpty {
            sections.append(.init(field: .date, text: dateTime, weight: 52))
        }
        if !metadata.participants.isEmpty {
            sections.append(.init(field: .participant, text: metadata.participants.joined(separator: " "), weight: 84))
        }
        sections.append(contentsOf: rawTranscriptSections(from: text, lineLimit: configuration.rawTranscriptLineLimit))
        return LocalGlossarySourceDocument(
            id: candidate.url.path,
            title: title,
            sections: sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }

    private static func readPrefix(from url: URL, byteLimit: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ""
        }
        defer {
            try? handle.close()
        }
        let data = (try? handle.read(upToCount: byteLimit)) ?? Data()
        return TranscriptTextDecoder.decode(data)
    }

    private static func rawTranscriptSections(from text: String, lineLimit: Int) -> [MeetingHistorySearchSection] {
        text.components(separatedBy: .newlines)
            .prefix(lineLimit)
            .compactMap { line -> MeetingHistorySearchSection? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }
                return MeetingHistorySearchSection(
                    field: .rawTranscript,
                    text: trimmed,
                    weight: 24,
                    timestamp: TranscriptTimestampLocator.timestamp(in: trimmed)
                )
            }
    }
}
```

- [ ] **Step 4: Run scanner tests**

Run:

```bash
swift test --filter LocalGlossaryHistoryScannerTests
```

Expected: PASS.

- [ ] **Step 5: Commit scanner**

```bash
git add Sources/MeetingRescueCore/LocalGlossaryHistoryScanner.swift Tests/MeetingRescueCoreTests/LocalGlossaryHistoryScannerTests.swift
git commit -m "feat: scan raw transcripts for glossary suggestions"
```

---

### Task 2: Korean Phrase Suggestion Lane

**Files:**
- Create: `Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift`
- Modify: `Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`

- [ ] **Step 1: Add failing Korean suggestion tests**

Append to `Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`:

```swift
    @Test("Korean lane groups recurring domain phrase variants")
    func koreanLaneGroupsDomainPhraseVariants() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Product Sync 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Product Sync 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Product Sync 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중계사 응답률 채팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Product Sync 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중계사 응답률 채팅 전환을 봅니다.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossaryKoreanSuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        let suggestion = try #require(suggestions.first { $0.aliases.contains("중개사 응답률 채팅") })
        #expect(suggestion.aliases.contains("중계사 응답률 채팅"))
        #expect(suggestion.meetingCount >= 4)
        #expect(suggestion.confidence >= 0.80)
    }

    @Test("Korean lane filters generic grammar ending variants")
    func koreanLaneFiltersGrammarEndingVariants() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Daily 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같아.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Daily 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같고.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Daily 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같아.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Daily 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같고.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossaryKoreanSuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        #expect(suggestions.isEmpty)
    }

    @Test("merged suggestion engine includes Korean phrase suggestions")
    func mergedEngineIncludesKoreanPhraseSuggestions() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Marketing 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이오에스 마케팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Marketing 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이오에스 마케팅 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Marketing 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이유에스 마케팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Marketing 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이유에스 마케팅 전환을 봅니다.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossarySuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        let suggestion = try #require(suggestions.first { $0.aliases.contains("아이오에스 마케팅") })
        #expect(suggestion.aliases.contains("아이유에스 마케팅"))
    }
```

- [ ] **Step 2: Run Korean tests to verify they fail**

Run:

```bash
swift test --filter LocalGlossarySuggestionEngineTests
```

Expected: FAIL because `LocalGlossaryKoreanSuggestionEngine` does not exist and the merged engine does not include Korean suggestions.

- [ ] **Step 3: Add Korean suggestion engine**

Create `Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift` with this public surface and calibrated constants:

```swift
import Foundation

public enum LocalGlossaryKoreanSuggestionEngine {
    public static func suggestions(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int = 8
    ) -> [LocalGlossarySuggestion] {
        let acceptedValues = Set(existingState.enabledTerms.flatMap(\.allMatchValues).map(MeetingHistorySearch.compactNormalize))
        let occurrences = collectOccurrences(from: documents, acceptedValues: acceptedValues)
        let candidates = summarizeCandidates(occurrences)
        let pairs = candidatePairs(from: candidates)
        let clusters = clusters(from: pairs)
        return clusters.compactMap { cluster in
            suggestion(from: cluster, dismissedIDs: existingState.dismissedSuggestionIDs)
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
}
```

Then implement the private helpers in the same file:

- `collectOccurrences(from:acceptedValues:)`
  - Extract `[가-힣]{2,}` tokens per raw transcript line.
  - Strip timestamp and speaker prefix.
  - Strip common particles from each token.
  - Generate single tokens plus 2-3 adjacent-token phrases.
  - Keep compact values with 3...8 Korean syllables.
  - Exclude accepted values, stop words, and generic grammar suffixes.
- `koreanScore(_:_:)`
  - syllable edit similarity weight: 0.35
  - jamo edit similarity weight: 0.35
  - syllable bigram Dice similarity weight: 0.20
  - initial consonant similarity weight: 0.10
- `candidatePairs(from:)`
  - Only compare same/similar initial-consonant buckets and length difference <= 2.
  - High-confidence lane: score >= 0.85 and both candidates appear in at least 2 documents.
  - Context-confirmed lane: score >= 0.80, context overlap >= 0.12, combined document support >= 5, and either candidate appears in 3+ documents or 4+ occurrences.
- `suggestion(from:dismissedIDs:)`
  - Suggestion id format: `suggestion:ko:<sorted compact aliases joined by "|">`.
  - `suggestedCanonical` is the display alias with the highest document support, then highest occurrence count, then shortest compact length.
  - Evidence is capped to 5 items.

Use the Korean stop/suffix values from `docs/local-glossary-korean-calibration.md`:

```swift
private let koreanStopWords: Set<String> = [
    "그리고", "그래서", "그러면", "그런데", "근데", "이제", "지금", "그냥", "약간",
    "저희", "제가", "저는", "우리", "우리가", "이거", "그거", "저거", "여기", "거기",
    "오늘", "내일", "다음", "이번", "지난", "계속", "조금", "진짜", "일단", "혹시",
    "경우", "부분", "관련", "대한", "대해서", "때문에", "회의", "회의록", "회의실",
    "말씀", "생각", "사람", "분들", "내용", "얘기", "이야기", "질문", "답변",
    "확인", "진행", "정리", "공유", "준비", "업데이트", "문제", "이슈", "느낌",
    "정도", "방식", "방향", "상황", "기능", "작업", "일정", "시간"
]

private let koreanGenericSuffixes: [String] = [
    "같아", "같고", "같은", "같긴", "같기", "같아서", "싶어", "싶기", "싶긴", "싶어서",
    "합니다", "했습니다", "있습니다", "나왔습니다", "나왔고", "필요하다", "필요하다고",
    "필요할", "필요한", "되는데", "되는지", "좋겠다", "좋겠다고", "좋을", "주시면",
    "주세요", "만들어", "만들어서", "하는지", "있어서", "있어"
]
```

- [ ] **Step 4: Merge Korean lane into `LocalGlossarySuggestionEngine`**

Modify `Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`:

```swift
public static func suggestions(
    from documents: [LocalGlossarySourceDocument],
    existingState: LocalGlossaryState,
    maxSuggestions: Int = 8
) -> [LocalGlossarySuggestion] {
    let latinSuggestions = latinSuggestions(
        from: documents,
        existingState: existingState,
        maxSuggestions: maxSuggestions
    )
    let koreanSuggestions = LocalGlossaryKoreanSuggestionEngine.suggestions(
        from: documents,
        existingState: existingState,
        maxSuggestions: maxSuggestions
    )
    return mergedSuggestions(latinSuggestions + koreanSuggestions, maxSuggestions: maxSuggestions)
}
```

Move the current implementation body into:

```swift
private static func latinSuggestions(
    from documents: [LocalGlossarySourceDocument],
    existingState: LocalGlossaryState,
    maxSuggestions: Int
) -> [LocalGlossarySuggestion]
```

Add:

```swift
private static func mergedSuggestions(
    _ suggestions: [LocalGlossarySuggestion],
    maxSuggestions: Int
) -> [LocalGlossarySuggestion] {
    var byID: [String: LocalGlossarySuggestion] = [:]
    for suggestion in suggestions {
        if let existing = byID[suggestion.id] {
            if suggestion.confidence > existing.confidence ||
                (suggestion.confidence == existing.confidence && suggestion.occurrenceCount > existing.occurrenceCount) {
                byID[suggestion.id] = suggestion
            }
        } else {
            byID[suggestion.id] = suggestion
        }
    }
    return byID.values.sorted {
        if $0.confidence == $1.confidence {
            return $0.occurrenceCount > $1.occurrenceCount
        }
        return $0.confidence > $1.confidence
    }
    .prefix(maxSuggestions)
    .map { $0 }
}
```

- [ ] **Step 5: Run Korean lane tests**

Run:

```bash
swift test --filter LocalGlossarySuggestionEngineTests
```

Expected: PASS.

- [ ] **Step 6: Commit Korean lane**

```bash
git add Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift
git commit -m "feat: suggest korean glossary phrases"
```

---

### Task 3: AppViewModel Scanner Wiring

**Files:**
- Modify: `Sources/MeetingRescue/AppViewModel.swift`
- Modify: `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`

- [ ] **Step 1: Add failing source-wiring test**

Append to `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`:

```swift
    @Test("local glossary refresh scans selected raw transcript folder")
    func localGlossaryRefreshScansSelectedRawTranscriptFolder() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let refresh = try #require(source.slice(from: "func refreshLocalGlossarySuggestions()", to: "func acceptLocalGlossarySuggestion"))

        #expect(refresh.contains("selectedFolderURL"))
        #expect(refresh.contains("LocalGlossaryHistoryScanner.documents"))
        #expect(!refresh.contains("meetingHistoryItems.map"))
    }
```

- [ ] **Step 2: Run wiring test to verify it fails**

Run:

```bash
swift test --filter AppViewModelTestRunContextTests/localGlossaryRefreshScansSelectedRawTranscriptFolder
```

Expected: FAIL because `refreshLocalGlossarySuggestions()` still reads `meetingHistoryItems.map`.

- [ ] **Step 3: Rewire refresh to the raw scanner**

Replace `refreshLocalGlossarySuggestions()` in `Sources/MeetingRescue/AppViewModel.swift` with:

```swift
func refreshLocalGlossarySuggestions() {
    guard !isGeneratingLocalGlossarySuggestions else {
        return
    }
    guard let selectedFolderURL else {
        localGlossaryStatusMessage = "transcript 폴더를 먼저 선택하세요."
        return
    }
    isGeneratingLocalGlossarySuggestions = true
    localGlossaryStatusMessage = "raw transcript history에서 용어 후보를 찾는 중"

    let currentState = localGlossaryState
    Task { @MainActor [weak self, selectedFolderURL, currentState] in
        let documents = await Task.detached(priority: .utility) {
            LocalGlossaryHistoryScanner.documents(
                in: selectedFolderURL,
                configuration: .init(maxDocuments: 120, maxBytesPerDocument: 96_000, rawTranscriptLineLimit: 360)
            )
        }.value
        let suggestions = await Task.detached(priority: .utility) {
            LocalGlossarySuggestionEngine.suggestions(
                from: documents,
                existingState: currentState,
                maxSuggestions: 12
            )
        }.value
        guard let self else {
            return
        }
        for suggestion in suggestions {
            self.localGlossaryState.upsertSuggestion(suggestion)
        }
        try? self.stateStore.saveLocalGlossaryState(self.localGlossaryState)
        self.localGlossaryStatusMessage = suggestions.isEmpty
            ? "회의 \(documents.count)개에서 새 용어 후보 없음"
            : "회의 \(documents.count)개에서 용어 후보 \(suggestions.count)개"
        self.isGeneratingLocalGlossarySuggestions = false
    }
}
```

Add AppViewModel computed helpers near the other derived properties:

```swift
var activeLocalGlossaryMatchCount: Int {
    guard settings.localGlossaryEnabled else {
        return 0
    }
    return LocalGlossaryMatcher.matches(in: rawTranscript, state: localGlossaryState).count
}

var localGlossarySuggestionCount: Int {
    localGlossaryState.suggestions.count
}
```

- [ ] **Step 4: Run AppViewModel tests**

Run:

```bash
swift test --filter AppViewModelTestRunContextTests
```

Expected: PASS.

- [ ] **Step 5: Commit AppViewModel wiring**

```bash
git add Sources/MeetingRescue/AppViewModel.swift Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift
git commit -m "feat: refresh glossary suggestions from raw history"
```

---

### Task 4: Meeting Intelligence Glossary Lane And Raw Transcript CTA

**Files:**
- Modify: `Sources/MeetingRescue/ContentView.swift`
- Modify: `Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`

- [ ] **Step 1: Add failing UI wiring tests**

Append to `Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`:

```swift
    @Test("meeting intelligence exposes local glossary lane")
    func meetingIntelligenceExposesLocalGlossaryLane() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("case glossary = \"용어\""))
        #expect(source.contains("case .glossary:"))
        #expect(source.contains("localGlossaryPanel()"))
        #expect(source.contains("LocalGlossarySuggestionReviewRow"))
    }

    @Test("raw transcript shows compact glossary CTA")
    func rawTranscriptShowsGlossaryCTA() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rawScroll = try #require(source.slice(from: "private var rawTranscriptScroll", to: "private var rawTranscriptLineList"))

        #expect(rawScroll.contains("rawTranscriptGlossaryFooter"))
        #expect(source.contains("용어 후보"))
        #expect(source.contains("intelligenceMode = .glossary"))
    }

    @Test("settings glossary section no longer hosts suggestion review")
    func settingsGlossarySectionNoLongerHostsSuggestionReview() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let settings = try #require(source.slice(from: "private var localGlossarySettings", to: "private func localGlossaryTermRow"))

        #expect(!settings.contains("localGlossarySuggestionRow"))
        #expect(!settings.contains("용어 후보 생성"))
    }
```

- [ ] **Step 2: Run UI wiring tests to verify they fail**

Run:

```bash
swift test --filter ContentViewContextWiringTests
```

Expected: FAIL because `용어` lane and raw transcript CTA are not wired yet.

- [ ] **Step 3: Add `용어` intelligence mode**

Modify `IntelligenceMode` in `Sources/MeetingRescue/ContentView.swift`:

```swift
private enum IntelligenceMode: String, CaseIterable, Identifiable {
    case overview = "요약"
    case timeline = "흐름"
    case candidates = "후보"
    case workflow = "워크플로우"
    case glossary = "용어"
    case context = "컨텍스트"

    var id: String { rawValue }

    var laneID: String {
        switch self {
        case .overview:
            return "overview"
        case .timeline:
            return "timeline"
        case .candidates:
            return "candidates"
        case .workflow:
            return "workflow"
        case .glossary:
            return "glossary"
        case .context:
            return "context"
        }
    }
}
```

Add to the intelligence content switch:

```swift
case .glossary:
    localGlossaryPanel()
```

- [ ] **Step 4: Add raw transcript CTA**

Modify `rawTranscriptScroll`:

```swift
private var rawTranscriptScroll: some View {
    ScrollViewReader { proxy in
        ScrollView {
            rawTranscriptLineList
            rawTranscriptGlossaryFooter
            Color.clear
                .frame(height: 1)
                .id("bottom")
        }
        .background(Color.smoothSurface)
        .onChange(of: viewModel.rawTranscriptRevision) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        .onChange(of: viewModel.transcriptFocusRequest) { _, request in
            guard let request else {
                return
            }
            proxy.scrollTo(request.lineID, anchor: .center)
        }
    }
}
```

Add:

```swift
private var rawTranscriptGlossaryFooter: some View {
    HStack(spacing: 8) {
        Label("용어 후보 \(viewModel.localGlossarySuggestionCount)개", systemImage: "text.book.closed")
        if viewModel.activeLocalGlossaryMatchCount > 0 {
            Text("힌트 \(viewModel.activeLocalGlossaryMatchCount)개 적용 중")
                .foregroundStyle(Color.smoothMuted)
        }
        Spacer(minLength: 0)
        Button {
            intelligenceMode = .glossary
            withAnimation(.easeInOut(duration: 0.16)) {
                activeOverlayPane = .intelligence
            }
        } label: {
            Label("검토", systemImage: "arrow.right.circle")
        }
        .buttonStyle(.borderless)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(Color.smoothInk)
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .background(Color.smoothSurface)
}
```

- [ ] **Step 5: Add glossary review panel**

Add inside `ContentView` near `contextPanel()`:

```swift
private func localGlossaryPanel() -> some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            sectionHeader("용어", systemImage: "text.book.closed")
            Spacer(minLength: 0)
            Button {
                viewModel.refreshLocalGlossarySuggestions()
            } label: {
                Label(viewModel.isGeneratingLocalGlossarySuggestions ? "찾는 중" : "후보 새로 찾기", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isGeneratingLocalGlossarySuggestions || viewModel.selectedFolderURL == nil)
        }

        Text(viewModel.localGlossaryStatusMessage)
            .font(.caption)
            .foregroundStyle(Color.smoothMuted)

        settingsToggleRow

        if viewModel.localGlossaryState.suggestions.isEmpty {
            emptyState("표시할 용어 후보 없음", systemImage: "text.magnifyingglass", description: "raw transcript history에서 반복되는 STT 변형을 찾으면 여기에 표시합니다.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.localGlossaryState.suggestions.prefix(12)) { suggestion in
                    LocalGlossarySuggestionReviewRow(
                        suggestion: suggestion,
                        onAccept: { canonical in
                            viewModel.acceptLocalGlossarySuggestion(id: suggestion.id, canonical: canonical)
                        },
                        onDismiss: {
                            viewModel.dismissLocalGlossarySuggestion(id: suggestion.id)
                        }
                    )
                }
            }
        }

        settingsCard("저장된 용어", systemImage: "checkmark.seal") {
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

private var settingsToggleRow: some View {
    HStack {
        Text("분석/search 힌트 사용")
            .font(.callout.weight(.semibold))
        Spacer()
        Toggle("local glossary", isOn: Binding(
            get: { viewModel.settings.localGlossaryEnabled },
            set: { viewModel.setLocalGlossaryEnabled($0) }
        ))
        .labelsHidden()
    }
    .smoothCard(tint: Color.smoothAccent)
}
```

Add a reusable row outside `ContentView`:

```swift
private struct LocalGlossarySuggestionReviewRow: View {
    let suggestion: LocalGlossarySuggestion
    let onAccept: (String) -> Void
    let onDismiss: () -> Void
    @State private var canonical: String

    init(
        suggestion: LocalGlossarySuggestion,
        onAccept: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.suggestion = suggestion
        self.onAccept = onAccept
        self.onDismiss = onDismiss
        _canonical = State(initialValue: suggestion.suggestedCanonical)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(suggestion.aliases.joined(separator: " / "))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.smoothInk)
                    Text("회의 \(suggestion.meetingCount)개 · 출현 \(suggestion.occurrenceCount)회 · 신뢰도 \(Int(suggestion.confidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                }
                Spacer(minLength: 0)
                Button {
                    onDismiss()
                } label: {
                    Label("다시 보지 않기", systemImage: "eye.slash")
                }
                .buttonStyle(.borderless)
            }

            TextField("정답 용어", text: $canonical)
                .textFieldStyle(.roundedBorder)

            if !suggestion.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(suggestion.evidence.prefix(3).enumerated()), id: \.offset) { _, evidence in
                        Text("\(evidence.sourceTitle): \(evidence.excerpt)")
                            .font(.caption)
                            .foregroundStyle(Color.smoothMuted)
                            .lineLimit(2)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    onAccept(canonical.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Label("사전에 추가", systemImage: "checkmark")
                }
                .buttonStyle(SmoothActionButtonStyle())
                .disabled(canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .smoothCard(tint: Color.smoothAccent)
    }
}
```

- [ ] **Step 6: Reduce Settings glossary section**

Replace `localGlossarySettings` in `SettingsView` with a management-only view:

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
            Text("용어 후보 검토와 정답 용어 편집은 Meeting Intelligence의 용어 탭에서 진행합니다.")
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
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

Keep `localGlossaryTermRow(_:)`. Remove `localGlossarySuggestionRow(_:)`.

- [ ] **Step 7: Run UI wiring tests**

Run:

```bash
swift test --filter ContentViewContextWiringTests
```

Expected: PASS.

- [ ] **Step 8: Commit UI lane**

```bash
git add Sources/MeetingRescue/ContentView.swift Tests/MeetingRescueTests/ContentViewContextWiringTests.swift
git commit -m "feat: move glossary review into intelligence"
```

---

### Task 5: Validation And Tracker Updates

**Files:**
- Modify: `tasks.md`
- Modify: `execution-log.md`
- Create: `docs/local-glossary-hardening-validation.md`

- [ ] **Step 1: Add validation document**

Create `docs/local-glossary-hardening-validation.md`:

````markdown
# Local Glossary Hardening Validation

Date: 2026-06-10

## Scope

D2.6 Local Glossary Hardening validates:

- raw transcript folder scanning
- Korean phrase suggestions
- Meeting Intelligence `용어` review flow
- canonical editing before accept
- raw transcript CTA

## Synthetic Fixtures

Latin fixture:

```text
[00:10] Ethan: jax workflow를 봅니다.
[00:20] Ethan: jecks workflow를 봅니다.
[00:30] Ethan: zacks workflow를 봅니다.
```

Korean fixture:

```text
[00:10] Ethan: 중개사 응답률 채팅 지표를 봅니다.
[00:20] Ethan: 중계사 응답률 채팅 전환을 봅니다.
[00:30] Ethan: 아이오에스 마케팅 지표를 봅니다.
[00:40] Ethan: 아이유에스 마케팅 전환을 봅니다.
```

## Expected Behavior

- Meeting Intelligence shows a `용어` lane.
- Raw Transcript footer shows local glossary candidate/match counts.
- `후보 새로 찾기` scans raw transcript files from the selected folder.
- Korean variants are shown only as suggestions.
- User can edit canonical text before accepting a suggestion.
- Accepted terms are the only glossary values injected as `domainGlossary` supplemental context.
- Settings no longer hosts the suggestion review list.

## Verification Commands

```bash
swift test --filter LocalGlossaryHistoryScannerTests
swift test --filter LocalGlossarySuggestionEngineTests
swift test --filter AppViewModelTestRunContextTests
swift test --filter ContentViewContextWiringTests
swift test
swift build
git diff --check
```
````

- [ ] **Step 2: Update `tasks.md`**

Add under the existing D2.5 local glossary entry:

```markdown
  - D2.6 Local Glossary Hardening:
    - 상태: `Done`
    - 목표: local glossary suggestion을 raw transcript history 기반으로 안정화하고, 한글 phrase 후보와 Meeting Intelligence 내 검토 UX를 추가한다.
    - 구현 요약:
      - `LocalGlossaryHistoryScanner`가 선택 폴더의 raw transcript를 직접 스캔한다.
      - 기존 Latin/mixed lane에 Korean phrase lane을 병합한다.
      - 한글 후보는 calibrated threshold(score >= 0.85 또는 score >= 0.80 + context guard)를 사용한다.
      - Meeting Intelligence에 `용어` 탭을 추가하고 canonical 편집 후 승인하게 한다.
      - Settings는 glossary 사용/삭제 관리로 축소한다.
    - 검증:
      - `swift test`
      - `swift build`
      - `git diff --check`
```

- [ ] **Step 3: Update `execution-log.md`**

Prepend:

```markdown
## 2026-06-10 Local Glossary Hardening

- 구현:
  - raw transcript folder scanner를 추가해 suggestion 생성이 visible history search state에 의존하지 않도록 했다.
  - 한글 phrase suggestion lane을 추가하고 calibration threshold를 적용했다.
  - Meeting Intelligence에 `용어` 탭을 추가해 후보 refresh, evidence 확인, canonical 편집, accept/dismiss를 처리한다.
  - raw transcript 하단에 glossary CTA를 추가하고 Settings glossary는 관리용으로 축소했다.
- 검증:
  - `swift test --filter LocalGlossaryHistoryScannerTests`: PASS
  - `swift test --filter LocalGlossarySuggestionEngineTests`: PASS
  - `swift test --filter AppViewModelTestRunContextTests`: PASS
  - `swift test --filter ContentViewContextWiringTests`: PASS
  - `swift test`: PASS
  - `swift build`: PASS
  - `git diff --check`: PASS
```

- [ ] **Step 4: Run full verification**

Run:

```bash
swift test
swift build
git diff --check
```

Expected:

- `swift test`: PASS
- `swift build`: PASS
- `git diff --check`: no output

- [ ] **Step 5: Commit tracker and validation**

```bash
git add tasks.md execution-log.md docs/local-glossary-hardening-validation.md
git commit -m "docs: track local glossary hardening"
```

---

## Self-Review

Spec coverage:

- Raw transcript scanner: Task 1 and Task 3.
- Korean threshold from prior transcript calibration: Task 2 uses `docs/local-glossary-korean-calibration.md`.
- Meeting Intelligence `용어` lane: Task 4.
- Raw transcript CTA instead of full review UI: Task 4.
- Canonical edit before accept: Task 4.
- Settings reduced to management: Task 4.
- Accepted terms only used for prompt/search hints: existing matcher remains unchanged; Task 4 keeps suggestions out of prompt context until accepted.

Placeholder scan:

- No placeholder markers or open implementation placeholders are intentionally left.
- Each new type referenced by later tasks is introduced by an earlier task.

Type consistency:

- `LocalGlossaryHistoryScanner.documents(...)` returns `[LocalGlossarySourceDocument]`, matching existing `LocalGlossarySuggestionEngine.suggestions(...)`.
- `LocalGlossaryKoreanSuggestionEngine.suggestions(...)` returns `[LocalGlossarySuggestion]`, matching the Latin lane.
- `AppViewModel.activeLocalGlossaryMatchCount` and `localGlossarySuggestionCount` are read-only computed properties used by `ContentView`.
- `IntelligenceMode.glossary` uses lane id `glossary`, which is accepted by the current `MeetingIntelligenceFeatureGate.isVisibleLane(_:)`.
