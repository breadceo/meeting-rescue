# Raw Transcript Glossary Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users select text directly inside Raw Transcript and register it as a local glossary term or as an alias of an existing term.

**Architecture:** Keep raw transcript immutable and treat selected text as a high-confidence user label. Core state owns manual term/alias mutations, AppViewModel owns persistence and refresh side effects, and SwiftUI/AppKit captures macOS text selection inside the Raw Transcript pane before opening a lightweight registration sheet.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSTextView` bridge, Swift Testing, existing `LocalGlossaryState`, `AppViewModel`, `ApplicationStateStore`, and local JSON glossary persistence.

---

## Product Decisions

- Raw Transcript remains the source of truth. The app never rewrites transcript text.
- User-selected transcript text is an alias by default. The user must confirm the canonical term.
- New term flow defaults canonical to the selected text, but the input is editable because most real cases are `misheard alias -> correct canonical`.
- Existing term flow adds the selected text to `aliases` for the chosen term.
- Manual selections should be more trusted than automatic suggestions, but still low-priority context for analysis.
- MVP does not add team sync, shared glossary, cloud storage, or automatic canonical inference.
- MVP does not require context-menu support. Capturing drag selection and showing a visible Raw Transcript CTA is enough. Context menu can be added after the selection bridge is stable.

## File Structure

- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossaryModels.swift`
  - Add `LocalGlossaryTermSource.manualSelection`.
  - Add `LocalGlossaryManualSelection` sanitizer/validator.
  - Add `LocalGlossaryState.addManualSelectionTerm(...)`.
  - Add `LocalGlossaryState.addManualSelectionAlias(...)`.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/AppViewModel.swift`
  - Add view-model methods that call the new state mutations, persist glossary state, update status, refresh active match count, and refresh meeting history.
- Create `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/SelectableTranscriptTextView.swift`
  - AppKit-backed non-editable transcript text view that captures selected text.
  - Provides monospaced styling consistent with the current Raw Transcript pane.
  - Supports revision-driven scroll-to-bottom and focus-line requests.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/ContentView.swift`
  - Replace the line-list-only raw transcript body with `SelectableTranscriptTextView`.
  - Add a compact footer CTA when selected text is valid.
  - Add a sheet for "new term" and "existing alias" registration.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`
  - Cover manual selection sanitization, new term creation, alias creation, duplicate handling, and source persistence.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`
  - Cover view-model glossary mutations and active match count refresh behavior.
- Modify `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`
  - Add source-level wiring tests for selectable transcript view, selection CTA, registration sheet, and view-model actions.

---

### Task 1: Core Manual Selection Model

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossaryModels.swift`
- Test: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`

- [ ] **Step 1: Write failing sanitizer and mutation tests**

Add these tests to `LocalGlossaryModelsTests`:

```swift
@Test("manual glossary selection collapses whitespace and rejects oversized text")
func manualGlossarySelectionSanitizesText() {
    #expect(LocalGlossaryManualSelection.sanitizedText("  워크\n플로  ") == "워크 플로")
    #expect(LocalGlossaryManualSelection.sanitizedText("[00:12] Ethan: 아이오에스") == "아이오에스")
    #expect(LocalGlossaryManualSelection.sanitizedText("   ").isEmpty)

    let tooLong = String(repeating: "가", count: 81)
    #expect(!LocalGlossaryManualSelection.isValid(tooLong))
    #expect(LocalGlossaryManualSelection.isValid("워크 플로"))
}

@Test("manual selected text can create a new local glossary term")
func manualSelectionCanCreateNewTerm() throws {
    var state = LocalGlossaryState()

    let termID = state.addManualSelectionTerm(
        selectedText: "워크 플로",
        canonical: "워크플로우",
        category: .domainTerm
    )

    let id = try #require(termID)
    let term = try #require(state.terms.first(where: { $0.id == id }))
    #expect(term.canonical == "워크플로우")
    #expect(term.aliases == ["워크 플로"])
    #expect(term.category == .domainTerm)
    #expect(term.source == .manualSelection)
}

@Test("manual selected text identical to canonical does not duplicate alias")
func manualSelectionAvoidsDuplicateCanonicalAlias() throws {
    var state = LocalGlossaryState()

    _ = state.addManualSelectionTerm(
        selectedText: "iOS",
        canonical: "iOS",
        category: .acronym
    )

    let term = try #require(state.terms.first)
    #expect(term.canonical == "iOS")
    #expect(term.aliases.isEmpty)
}

@Test("manual selected text can be added to existing term aliases")
func manualSelectionCanAddAliasToExistingTerm() throws {
    var state = LocalGlossaryState(terms: [
        LocalGlossaryTerm(
            id: "term-workflow",
            canonical: "워크플로우",
            aliases: ["workflow"],
            category: .product
        )
    ])

    let didAdd = state.addManualSelectionAlias(
        selectedText: "워크 플로",
        toTermID: "term-workflow"
    )

    let term = try #require(state.terms.first)
    #expect(didAdd)
    #expect(term.aliases == ["workflow", "워크 플로"])
}

@Test("manual selected alias ignores invalid and duplicate values")
func manualSelectionAliasRejectsInvalidValues() throws {
    var state = LocalGlossaryState(terms: [
        LocalGlossaryTerm(
            id: "term-ios",
            canonical: "iOS",
            aliases: ["아이오에스"],
            category: .acronym
        )
    ])

    #expect(!state.addManualSelectionAlias(selectedText: "   ", toTermID: "term-ios"))
    #expect(!state.addManualSelectionAlias(selectedText: "iOS", toTermID: "term-ios"))
    #expect(!state.addManualSelectionAlias(selectedText: "아이오에스", toTermID: "term-ios"))

    let term = try #require(state.terms.first)
    #expect(term.aliases == ["아이오에스"])
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
swift test --filter 'LocalGlossaryModelsTests/manualGlossarySelectionSanitizesText|LocalGlossaryModelsTests/manualSelectionCanCreateNewTerm|LocalGlossaryModelsTests/manualSelectionAvoidsDuplicateCanonicalAlias|LocalGlossaryModelsTests/manualSelectionCanAddAliasToExistingTerm|LocalGlossaryModelsTests/manualSelectionAliasRejectsInvalidValues'
```

Expected: FAIL because `manualSelection`, `LocalGlossaryManualSelection`, `addManualSelectionTerm`, and `addManualSelectionAlias` do not exist.

- [ ] **Step 3: Implement source and sanitizer**

In `LocalGlossaryTermSource`, add the new case:

```swift
public enum LocalGlossaryTermSource: String, Codable, Sendable {
    case manual
    case manualSelection
    case suggested
}
```

Add this enum near the glossary model helpers:

```swift
public enum LocalGlossaryManualSelection {
    public static let maximumSelectedTextLength = 80

    public static func sanitizedText(_ rawText: String) -> String {
        var value = rawText
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmedGlossaryText

        if let range = value.range(
            of: #"^\[[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?\]\s*[^:]{1,40}:\s*"#,
            options: .regularExpression
        ) {
            value.removeSubrange(range)
            value = value.trimmedGlossaryText
        }

        return value
    }

    public static func isValid(_ rawText: String) -> Bool {
        let value = sanitizedText(rawText)
        return !value.isEmpty && value.count <= maximumSelectedTextLength
    }
}
```

- [ ] **Step 4: Implement state mutations**

Add these methods inside `LocalGlossaryState`:

```swift
@discardableResult
public mutating func addManualSelectionTerm(
    selectedText rawSelectedText: String,
    canonical rawCanonical: String,
    category: LocalGlossaryCategory = .domainTerm
) -> String? {
    let selectedText = LocalGlossaryManualSelection.sanitizedText(rawSelectedText)
    let canonical = LocalGlossaryManualSelection.sanitizedText(rawCanonical)
    guard LocalGlossaryManualSelection.isValid(selectedText),
          LocalGlossaryManualSelection.isValid(canonical) else {
        return nil
    }

    let now = Date()
    let newTerm = LocalGlossaryTerm(
        canonical: canonical,
        aliases: selectedText == canonical ? [] : [selectedText],
        category: category,
        note: "Raw Transcript 선택으로 추가됨",
        source: .manualSelection,
        createdAt: now,
        updatedAt: now
    )

    terms.removeAll { existing in
        MeetingHistorySearch.compactNormalize(existing.canonical) == MeetingHistorySearch.compactNormalize(newTerm.canonical)
    }
    terms.append(newTerm)
    updatedAt = now
    return newTerm.id
}

@discardableResult
public mutating func addManualSelectionAlias(
    selectedText rawSelectedText: String,
    toTermID termID: String
) -> Bool {
    let selectedText = LocalGlossaryManualSelection.sanitizedText(rawSelectedText)
    guard LocalGlossaryManualSelection.isValid(selectedText),
          let termIndex = terms.firstIndex(where: { $0.id == termID }) else {
        return false
    }

    let canonical = terms[termIndex].canonical
    guard MeetingHistorySearch.compactNormalize(selectedText) != MeetingHistorySearch.compactNormalize(canonical) else {
        return false
    }

    let nextAliases = (terms[termIndex].aliases + [selectedText])
        .normalizedGlossaryValues(excluding: [canonical])
    guard nextAliases != terms[termIndex].aliases else {
        return false
    }

    terms[termIndex].aliases = nextAliases
    terms[termIndex].source = terms[termIndex].source == .suggested ? .manualSelection : terms[termIndex].source
    terms[termIndex].updatedAt = Date()
    updatedAt = Date()
    return true
}
```

- [ ] **Step 5: Run tests to verify GREEN**

Run:

```bash
swift test --filter 'LocalGlossaryModelsTests/manualGlossarySelectionSanitizesText|LocalGlossaryModelsTests/manualSelectionCanCreateNewTerm|LocalGlossaryModelsTests/manualSelectionAvoidsDuplicateCanonicalAlias|LocalGlossaryModelsTests/manualSelectionCanAddAliasToExistingTerm|LocalGlossaryModelsTests/manualSelectionAliasRejectsInvalidValues'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add /Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescueCore/LocalGlossaryModels.swift /Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift
git commit -m "feat: add manual glossary selection model"
```

---

### Task 2: ViewModel Manual Glossary Actions

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/AppViewModel.swift`
- Test: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`

- [ ] **Step 1: Write failing view-model tests**

Add tests to `AppViewModelTestRunContextTests`:

```swift
@MainActor
@Test("view model adds selected raw transcript text as a manual glossary term")
func viewModelAddsSelectedTranscriptTextAsManualGlossaryTerm() throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("meeting-rescue-manual-glossary-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: rootURL)
    }
    let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
    let viewModel = AppViewModel(stateStore: stateStore)

    viewModel.rawTranscript = "Ethan: 워크 플로 쪽을 다시 보겠습니다."
    viewModel.addManualLocalGlossaryTerm(
        selectedText: "워크 플로",
        canonical: "워크플로우",
        category: .domainTerm
    )

    let term = try #require(viewModel.localGlossaryState.terms.first)
    #expect(term.canonical == "워크플로우")
    #expect(term.aliases.contains("워크 플로"))
    #expect(term.source == .manualSelection)
    #expect(viewModel.localGlossaryStatusMessage.contains("Raw Transcript"))
}

@MainActor
@Test("view model adds selected raw transcript text as alias to existing term")
func viewModelAddsSelectedTranscriptTextAsAlias() throws {
    let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("meeting-rescue-manual-glossary-alias-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: rootURL)
    }
    let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
    let viewModel = AppViewModel(stateStore: stateStore)

    viewModel.localGlossaryState = LocalGlossaryState(terms: [
        LocalGlossaryTerm(
            id: "term-ios",
            canonical: "iOS",
            aliases: ["아이오에스"],
            category: .acronym
        )
    ])
    viewModel.addManualLocalGlossaryAlias(selectedText: "아이유에스", toTermID: "term-ios")

    let term = try #require(viewModel.localGlossaryState.terms.first)
    #expect(term.aliases.contains("아이유에스"))
    #expect(viewModel.localGlossaryStatusMessage.contains("alias"))
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
swift test --filter 'AppViewModelTestRunContextTests/viewModelAddsSelectedTranscriptTextAsManualGlossaryTerm|AppViewModelTestRunContextTests/viewModelAddsSelectedTranscriptTextAsAlias'
```

Expected: FAIL because `addManualLocalGlossaryTerm` and `addManualLocalGlossaryAlias` do not exist.

- [ ] **Step 3: Implement view-model methods**

Add these methods near the existing local glossary action methods in `AppViewModel`:

```swift
func addManualLocalGlossaryTerm(
    selectedText: String,
    canonical: String,
    category: LocalGlossaryCategory = .domainTerm
) {
    guard localGlossaryState.addManualSelectionTerm(
        selectedText: selectedText,
        canonical: canonical,
        category: category
    ) != nil else {
        localGlossaryStatusMessage = "선택한 텍스트를 용어로 추가할 수 없습니다."
        return
    }
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "Raw Transcript 선택을 용어 사전에 추가했습니다."
    refreshActiveLocalGlossaryMatchCountIfNeeded()
    refreshMeetingHistory(force: true)
}

func addManualLocalGlossaryAlias(
    selectedText: String,
    toTermID termID: String
) {
    guard localGlossaryState.addManualSelectionAlias(selectedText: selectedText, toTermID: termID) else {
        localGlossaryStatusMessage = "선택한 텍스트를 alias로 추가할 수 없습니다."
        return
    }
    try? stateStore.saveLocalGlossaryState(localGlossaryState)
    localGlossaryStatusMessage = "Raw Transcript 선택을 기존 용어 alias로 추가했습니다."
    refreshActiveLocalGlossaryMatchCountIfNeeded()
    refreshMeetingHistory(force: true)
}
```

- [ ] **Step 4: Run tests to verify GREEN**

Run:

```bash
swift test --filter 'AppViewModelTestRunContextTests/viewModelAddsSelectedTranscriptTextAsManualGlossaryTerm|AppViewModelTestRunContextTests/viewModelAddsSelectedTranscriptTextAsAlias'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add /Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/AppViewModel.swift /Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift
git commit -m "feat: wire manual glossary actions"
```

---

### Task 3: Selectable Raw Transcript View

**Files:**
- Create: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/SelectableTranscriptTextView.swift`
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`

- [ ] **Step 1: Write failing source-level wiring test**

Add this test to `ContentViewContextWiringTests`:

```swift
@Test("raw transcript uses selectable text view for glossary registration")
func rawTranscriptUsesSelectableTextViewForGlossaryRegistration() throws {
    let contentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
    let selectableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MeetingRescue/SelectableTranscriptTextView.swift")

    let content = try String(contentsOf: contentURL, encoding: .utf8)
    let selectable = try String(contentsOf: selectableURL, encoding: .utf8)

    #expect(content.contains("SelectableTranscriptTextView("))
    #expect(selectable.contains("NSViewRepresentable"))
    #expect(selectable.contains("NSTextView"))
    #expect(selectable.contains("textViewDidChangeSelection"))
    #expect(selectable.contains("onSelectionChange"))
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'ContentViewContextWiringTests/rawTranscriptUsesSelectableTextViewForGlossaryRegistration'
```

Expected: FAIL because `SelectableTranscriptTextView.swift` does not exist and `ContentView` does not use it.

- [ ] **Step 3: Create selectable transcript bridge**

Create `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/SelectableTranscriptTextView.swift`:

```swift
import AppKit
import SwiftUI

struct SelectableTranscriptTextView: NSViewRepresentable {
    var text: String
    var revision: Int
    var focusLineID: Int?
    var onSelectionChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(Color.smoothSurface)
        textView.textColor = NSColor(Color.smoothInk)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isRichText = false
        textView.usesFindPanel = true
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastRevision = revision
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.onSelectionChange = onSelectionChange

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            if selectedRange.location <= (text as NSString).length {
                textView.setSelectedRange(selectedRange)
            }
        }

        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            textView.scrollToEndOfDocument(nil)
        }

        if let focusLineID {
            context.coordinator.scrollToLine(focusLineID)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var onSelectionChange: (String) -> Void
        var lastRevision: Int = 0
        private var lastFocusedLineID: Int?

        init(onSelectionChange: @escaping (String) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                onSelectionChange("")
                return
            }
            let range = textView.selectedRange()
            guard range.length > 0,
                  let swiftRange = Range(range, in: textView.string) else {
                onSelectionChange("")
                return
            }
            onSelectionChange(String(textView.string[swiftRange]))
        }

        func scrollToLine(_ lineID: Int) {
            guard lastFocusedLineID != lineID,
                  let textView else {
                return
            }
            lastFocusedLineID = lineID
            let lines = textView.string.components(separatedBy: .newlines)
            let target = max(0, min(lineID, lines.count - 1))
            let location = lines.prefix(target).reduce(0) { $0 + ($1 as NSString).length + 1 }
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }
    }
}
```

- [ ] **Step 4: Run build to catch AppKit bridge errors**

Run:

```bash
swift build
```

Expected: PASS. If AppKit delegate signatures drift, fix compiler errors before moving on.

- [ ] **Step 5: Commit**

```bash
git add /Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/SelectableTranscriptTextView.swift /Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/ContentViewContextWiringTests.swift
git commit -m "feat: add selectable transcript view"
```

---

### Task 4: Raw Transcript Registration UI

**Files:**
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/ContentView.swift`
- Modify: `/Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/ContentViewContextWiringTests.swift`

- [ ] **Step 1: Write failing ContentView wiring test**

Add this test to `ContentViewContextWiringTests`:

```swift
@Test("raw transcript exposes selected text glossary registration sheet")
func rawTranscriptExposesSelectedTextGlossaryRegistrationSheet() throws {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("@State private var selectedRawTranscriptGlossaryText"))
    #expect(source.contains("@State private var glossarySelectionSheet"))
    #expect(source.contains("선택한 텍스트"))
    #expect(source.contains("새 용어로 등록"))
    #expect(source.contains("기존 용어 alias로 추가"))
    #expect(source.contains("LocalGlossarySelectionSheet"))
    #expect(source.contains("viewModel.addManualLocalGlossaryTerm"))
    #expect(source.contains("viewModel.addManualLocalGlossaryAlias"))
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'ContentViewContextWiringTests/rawTranscriptExposesSelectedTextGlossaryRegistrationSheet'
```

Expected: FAIL because the selection CTA and sheet do not exist.

- [ ] **Step 3: Add ContentView state**

Near other `@State` properties in `ContentView`, add:

```swift
@State private var selectedRawTranscriptGlossaryText = ""
@State private var glossarySelectionSheet: LocalGlossarySelectionSheetModel?
```

Add this UI-local model near other private view models in `ContentView.swift`:

```swift
private struct LocalGlossarySelectionSheetModel: Identifiable, Equatable {
    var id = UUID()
    var selectedText: String
}
```

- [ ] **Step 4: Replace raw transcript body with selectable view**

Replace `rawTranscriptScroll` with:

```swift
private var rawTranscriptScroll: some View {
    VStack(spacing: 0) {
        SelectableTranscriptTextView(
            text: viewModel.rawTranscript,
            revision: viewModel.rawTranscriptRevision,
            focusLineID: viewModel.highlightedTranscriptLineID,
            onSelectionChange: { selectedText in
                selectedRawTranscriptGlossaryText = LocalGlossaryManualSelection.sanitizedText(selectedText)
            }
        )
        rawTranscriptGlossaryFooter
    }
    .background(Color.smoothSurface)
}
```

Keep `rawTranscriptLineList` in the file only if other code still references it. If it becomes unused and the compiler warns, remove `rawTranscriptLineList` and `TranscriptLineRow` only when no tests or layout paths depend on them.

- [ ] **Step 5: Add selection CTA to footer**

Update `rawTranscriptGlossaryFooter` to include this button before the existing "검토" button:

```swift
if LocalGlossaryManualSelection.isValid(selectedRawTranscriptGlossaryText) {
    Button {
        glossarySelectionSheet = LocalGlossarySelectionSheetModel(
            selectedText: selectedRawTranscriptGlossaryText
        )
    } label: {
        Label("선택한 텍스트", systemImage: "text.badge.plus")
    }
    .buttonStyle(.borderless)
    .help("Raw Transcript에서 선택한 텍스트를 용어 사전에 등록")
}
```

- [ ] **Step 6: Attach registration sheet**

Attach this sheet to the top-level `body` view where other sheets are attached:

```swift
.sheet(item: $glossarySelectionSheet) { model in
    LocalGlossarySelectionSheet(
        selectedText: model.selectedText,
        terms: viewModel.localGlossaryState.terms,
        onAddNew: { canonical, category in
            viewModel.addManualLocalGlossaryTerm(
                selectedText: model.selectedText,
                canonical: canonical,
                category: category
            )
            glossarySelectionSheet = nil
            selectedRawTranscriptGlossaryText = ""
        },
        onAddAlias: { termID in
            viewModel.addManualLocalGlossaryAlias(
                selectedText: model.selectedText,
                toTermID: termID
            )
            glossarySelectionSheet = nil
            selectedRawTranscriptGlossaryText = ""
        },
        onCancel: {
            glossarySelectionSheet = nil
        }
    )
}
```

- [ ] **Step 7: Add sheet view**

Add this view near existing local glossary row views:

```swift
private struct LocalGlossarySelectionSheet: View {
    let selectedText: String
    let terms: [LocalGlossaryTerm]
    let onAddNew: (String, LocalGlossaryCategory) -> Void
    let onAddAlias: (String) -> Void
    let onCancel: () -> Void

    @State private var canonical: String
    @State private var category: LocalGlossaryCategory = .domainTerm
    @State private var selectedTermID: String

    init(
        selectedText: String,
        terms: [LocalGlossaryTerm],
        onAddNew: @escaping (String, LocalGlossaryCategory) -> Void,
        onAddAlias: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.terms = terms
        self.onAddNew = onAddNew
        self.onAddAlias = onAddAlias
        self.onCancel = onCancel
        _canonical = State(initialValue: selectedText)
        _selectedTermID = State(initialValue: Self.recommendedTermID(for: selectedText, terms: terms))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("선택한 텍스트", systemImage: "text.badge.plus")
                    .font(.headline)
                Spacer()
                Button("닫기") {
                    onCancel()
                }
                .buttonStyle(.borderless)
            }

            Text(selectedText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.smoothInk)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("새 용어로 등록")
                    .font(.subheadline.weight(.semibold))
                TextField("대표 용어", text: $canonical)
                    .textFieldStyle(.roundedBorder)
                Picker("유형", selection: $category) {
                    ForEach(LocalGlossaryCategory.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        onAddNew(canonical.trimmingCharacters(in: .whitespacesAndNewlines), category)
                    } label: {
                        Label("새 용어로 등록", systemImage: "plus.circle")
                    }
                    .buttonStyle(SmoothActionButtonStyle())
                    .disabled(!LocalGlossaryManualSelection.isValid(canonical))
                }
            }

            if !terms.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("기존 용어 alias로 추가")
                        .font(.subheadline.weight(.semibold))
                    Picker("기존 용어", selection: $selectedTermID) {
                        ForEach(Self.sortedTerms(for: selectedText, terms: terms)) { term in
                            Text(term.canonical).tag(term.id)
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            onAddAlias(selectedTermID)
                        } label: {
                            Label("기존 용어 alias로 추가", systemImage: "link.badge.plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(selectedTermID.isEmpty)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color.smoothCanvas)
    }

    private static func recommendedTermID(for selectedText: String, terms: [LocalGlossaryTerm]) -> String {
        sortedTerms(for: selectedText, terms: terms).first?.id ?? ""
    }

    private static func sortedTerms(for selectedText: String, terms: [LocalGlossaryTerm]) -> [LocalGlossaryTerm] {
        let selected = MeetingHistorySearch.compactNormalize(selectedText)
        return terms.sorted { lhs, rhs in
            let lhsValues = lhs.allMatchValues.map(MeetingHistorySearch.compactNormalize)
            let rhsValues = rhs.allMatchValues.map(MeetingHistorySearch.compactNormalize)
            let lhsScore = lhsValues.contains(where: { $0.contains(selected) || selected.contains($0) }) ? 1 : 0
            let rhsScore = rhsValues.contains(where: { $0.contains(selected) || selected.contains($0) }) ? 1 : 0
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.canonical.localizedStandardCompare(rhs.canonical) == .orderedAscending
        }
    }
}
```

- [ ] **Step 8: Run ContentView wiring tests**

Run:

```bash
swift test --filter 'ContentViewContextWiringTests/rawTranscriptUsesSelectableTextViewForGlossaryRegistration|ContentViewContextWiringTests/rawTranscriptExposesSelectedTextGlossaryRegistrationSheet|ContentViewContextWiringTests/rawTranscriptShowsGlossaryCTA'
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add /Users/ethan/Documents/git/meeting-rescue/Sources/MeetingRescue/ContentView.swift /Users/ethan/Documents/git/meeting-rescue/Tests/MeetingRescueTests/ContentViewContextWiringTests.swift
git commit -m "feat: add raw transcript glossary registration UI"
```

---

### Task 5: Verification And Local App Check

**Files:**
- Verify all files touched by Tasks 1-4.

- [ ] **Step 1: Run focused glossary tests**

Run:

```bash
swift test --filter 'LocalGlossaryModelsTests|LocalGlossaryMatcherTests|LocalGlossaryHistoryScannerTests|LocalGlossarySuggestionEngineTests|AppViewModelTestRunContextTests|ContentViewContextWiringTests'
```

Expected: PASS.

- [ ] **Step 2: Run full build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Build app bundle**

Run:

```bash
scripts/build_app.sh
```

Expected: PASS and `dist/Meeting Rescue.app` is produced.

- [ ] **Step 4: Manual UI smoke**

Run:

```bash
open "/Users/ethan/Documents/git/meeting-rescue/dist/Meeting Rescue.app"
```

Expected manual checks:

- Raw Transcript text is visible and selectable.
- Selecting `워크 플로` or any phrase reveals the `선택한 텍스트` CTA in the Raw Transcript footer.
- New term flow can save `워크 플로 -> 워크플로우`.
- Existing alias flow can add `아이유에스` to an existing `iOS` term.
- After save, Meeting Intelligence > 용어 shows the accepted term.
- Raw Transcript footer match count updates without the app slowing down.
- Test Run and Live Watch still render transcript content.

- [ ] **Step 5: Commit verification fixes if needed**

If verification required code fixes:

```bash
git add /Users/ethan/Documents/git/meeting-rescue/Sources /Users/ethan/Documents/git/meeting-rescue/Tests
git commit -m "fix: harden raw transcript glossary selection"
```

If no fixes were needed, do not create an empty commit.

---

## Risks And Guardrails

- `NSTextView` bridge can regress scroll/focus behavior. Keep revision-based scroll-to-bottom and focus-line scrolling in the bridge.
- Replacing the current `LazyVStack` removes per-line SwiftUI highlight styling unless recreated in AppKit. MVP accepts this only if focus scrolling remains usable. If highlight loss feels bad in manual smoke, keep the old line list for normal mode and add a small "선택 모드" toggle that swaps to `SelectableTranscriptTextView`.
- Long accidental selections should not become terms. `LocalGlossaryManualSelection.maximumSelectedTextLength = 80` blocks paragraph-sized selections.
- Transcript timestamps/speaker prefixes should not become aliases. The sanitizer strips simple `[00:12] Speaker:` prefixes.
- Manual selections should not force auto suggestion behavior. They only mutate accepted glossary terms.

## Completion Criteria

- User can select text in Raw Transcript and add it as a new glossary term.
- User can select text in Raw Transcript and add it as an alias to an existing glossary term.
- Selected text is sanitized, validated, persisted, and reflected in active glossary matching.
- Focused tests pass.
- `swift build` passes.
- `scripts/build_app.sh` passes.
- Manual smoke confirms the app remains responsive after adding terms.
