# Live Watch CPU Hotspots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the remaining live-watch CPU spikes seen in the running Meeting Rescue app without changing transcript, glossary, or history behavior.

**Architecture:** Fix only the sampled hot paths. Disable AppKit text checking on the read-only transcript view, then make history search-section construction use the existing `.fast` tokenization path so refreshes do not repeatedly invoke `NLTokenizer`.

**Tech Stack:** Swift 6, SwiftUI/AppKit, NaturalLanguage, Swift Testing, macOS `sample`/`top`.

---

## Profiling Evidence

- Running app: `/Applications/Meeting Rescue.app/Contents/MacOS/MeetingRescue`, PID 699, version `0.1.22 (122)`.
- Raw sample: `/tmp/meetingrescue-pid699.sample.txt`.
- Hot spots to target:
  - `NSTextCheckingOperationQueue`, `DataDetectorsCore`, `CoreNLP`, `MeCab` from transcript text checking.
  - `MeetingHistoryBuilder.makeHistorySearchSections` -> `MeetingHistorySearchSection.init` -> `MeetingHistorySearch.tokenize` -> `NLTokenizer`.
  - `SelectableTranscriptTextView.updateNSView(_:context:)` around append/selection/scroll; the text-checking fix is the smallest direct hit there.
- Red-team change: do not remove `stateStore.hasAnalysisState` / `stateStore.hasSession` in this patch. The sample shows both `lstat` and `read`; replacing existence probes with failed reads is not proven cheaper.
- Out of scope: release packaging, Sparkle feed changes, UI redesign, broad SwiftUI view decomposition, custom caches.

## Files

- Modify: `Sources/MeetingRescue/SelectableTranscriptTextView.swift`
  - Add one small helper that disables automatic text checking and call it from `makeNSView`.
- Modify: `Sources/MeetingRescueCore/MeetingHistorySearch.swift`
  - Let `MeetingHistorySearchSection.perspectiveAlignment` accept an explicit tokenization mode.
- Modify: `Sources/MeetingRescue/AppViewModel.swift`
  - Use `.fast` tokenization for history-builder search sections.
- Modify: `Tests/MeetingRescueTests/SelectableTranscriptTextViewTests.swift`
  - Add a property-level regression check for disabled text checking flags.
- Modify: `Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift`
  - Add a regression check that perspective alignment sections can use `.fast`.
- Modify: `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`
  - Update source-level history-builder checks to require `.fast` tokenization for built sections and to keep the existing `has*` probes.

---

### Task 1: Disable AppKit Text Checking In Transcript View

**Files:**
- Modify: `Tests/MeetingRescueTests/SelectableTranscriptTextViewTests.swift`
- Modify: `Sources/MeetingRescue/SelectableTranscriptTextView.swift`

- [x] **Step 1: Write the failing test**

Add this test to `SelectableTranscriptTextViewTests`:

```swift
@Test("transcript text view disables AppKit text checking work")
@MainActor
func transcriptTextViewDisablesAppKitTextCheckingWork() {
    let textView = NSTextView()

    SelectableTranscriptTextView.configureTextChecking(textView)

    #expect(textView.enabledTextCheckingTypes == 0)
    #expect(textView.isContinuousSpellCheckingEnabled == false)
    #expect(textView.isGrammarCheckingEnabled == false)
    #expect(textView.isAutomaticSpellingCorrectionEnabled == false)
    #expect(textView.isAutomaticDataDetectionEnabled == false)
    #expect(textView.isAutomaticLinkDetectionEnabled == false)
    #expect(textView.isAutomaticTextReplacementEnabled == false)
    #expect(textView.isAutomaticQuoteSubstitutionEnabled == false)
    #expect(textView.isAutomaticDashSubstitutionEnabled == false)
}
```

- [x] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
swift test --filter SelectableTranscriptTextViewTests
```

Expected: FAIL because `SelectableTranscriptTextView.configureTextChecking` does not exist.

- [x] **Step 3: Write the minimal implementation**

Inside `SelectableTranscriptTextView`, before `makeCoordinator()`, add:

```swift
@MainActor
static func configureTextChecking(_ textView: NSTextView) {
    textView.enabledTextCheckingTypes = 0
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
}
```

In `makeNSView(context:)`, immediately after `textView.usesFindPanel = true`, add:

```swift
Self.configureTextChecking(textView)
```

- [x] **Step 4: Run the targeted test to verify it passes**

Run:

```bash
swift test --filter SelectableTranscriptTextViewTests
```

Expected: PASS.

---

### Task 2: Use Fast Tokenization For History-Built Search Sections

**Files:**
- Modify: `Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift`
- Modify: `Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift`
- Modify: `Sources/MeetingRescueCore/MeetingHistorySearch.swift`
- Modify: `Sources/MeetingRescue/AppViewModel.swift`

- [x] **Step 1: Write the failing perspective-alignment test**

Add this test to `MeetingHistorySearchTests`:

```swift
@Test("perspective alignment search section can use fast tokenization")
func perspectiveAlignmentSearchSectionCanUseFastTokenization() {
    let alignment = PerspectiveAlignment(
        id: "alignment-marketing",
        topic: "마케팅팀이랑 계정 확인",
        axis: "속도와 정확도",
        sharedGround: "계정 소유자를 확인해야 한다.",
        nextQuestion: "누가 오늘 확인할 것인가?",
        perspectives: [
            PerspectivePosition(
                speaker: "Alex",
                summary: "오늘 확인해야 한다.",
                reasoning: "릴리즈가 막혀 있다."
            )
        ]
    )

    let section = MeetingHistorySearchSection.perspectiveAlignment(alignment, tokenization: .fast)

    #expect(section.tokenization == .fast)
    #expect(section.searchTokens.contains("마케팅팀이랑"))
    #expect(section.searchTokens.contains("마케"))
}
```

- [x] **Step 2: Update the history-builder source test**

In `historyAndSearchIndexGlossaryWorkUsesTermSignatureAndPreparedMatcher`, add:

```swift
#expect(builder.contains("private let historySearchTokenization: MeetingHistorySearchTokenization = .fast"))
#expect(builder.contains("tokenization: historySearchTokenization"))
#expect(builder.contains("MeetingHistorySearchSection.perspectiveAlignment(alignment, tokenization: historySearchTokenization)"))
```

In `historyBuilderBoundsEagerMetadataPreviewDuringIdleRefresh`, keep these existing expectations:

```swift
#expect(builder.contains("stateStore.hasAnalysisState(for: candidate.url)"))
#expect(builder.contains("stateStore.hasSession(for: candidate.url)"))
```

- [x] **Step 3: Run the targeted tests to verify they fail**

Run:

```bash
swift test --filter MeetingHistorySearchTests
swift test --filter AppViewModelTestRunContextTests
```

Expected:
- `MeetingHistorySearchTests` FAIL because `perspectiveAlignment(_:tokenization:)` does not exist.
- `AppViewModelTestRunContextTests` FAIL because the builder does not yet force `.fast`.

- [x] **Step 4: Add tokenization to perspective alignment sections**

In `MeetingHistorySearchSection.perspectiveAlignment`, change the signature from:

```swift
public static func perspectiveAlignment(
    _ alignment: PerspectiveAlignment,
    weight: Int = 76
) -> MeetingHistorySearchSection {
```

to:

```swift
public static func perspectiveAlignment(
    _ alignment: PerspectiveAlignment,
    weight: Int = 76,
    tokenization: MeetingHistorySearchTokenization = .full
) -> MeetingHistorySearchSection {
```

Then pass the tokenization into the returned section:

```swift
return MeetingHistorySearchSection(
    field: .perspectiveAlignment,
    text: text,
    weight: weight,
    timestamp: alignment.perspectives.flatMap(\.evidence).first?.timestamp,
    tokenization: tokenization
)
```

- [x] **Step 5: Make the history builder use fast tokenization**

In `MeetingHistoryBuilder`, after `private let eagerMetadataPreviewLimit = 120`, add:

```swift
private let historySearchTokenization: MeetingHistorySearchTokenization = .fast
```

In `MeetingHistoryBuilder.makeHistorySearchSections`, pass `tokenization: historySearchTokenization` to every structured `MeetingHistorySearchSection` created there:

```swift
.init(field: .title, text: metadata.displayTitle, weight: 92, tokenization: historySearchTokenization)
.init(field: .file, text: url.deletingPathExtension().lastPathComponent, weight: 60, tokenization: historySearchTokenization)
```

Apply the same argument to `.room`, `.date`, `.participant`, `.currentIssue`, `.topic`, `.decision`, `.confirmedDecision`, `.action`, `.confirmedAction`, and `.note` sections in the same function.

Change the perspective alignment append to:

```swift
sections.append(MeetingHistorySearchSection.perspectiveAlignment(alignment, tokenization: historySearchTokenization))
```

In `localGlossarySearchSections`, change the glossary return section to:

```swift
return MeetingHistorySearchSection(
    field: .glossary,
    text: values.joined(separator: " "),
    weight: 66,
    tokenization: .fast
)
```

- [x] **Step 6: Run the targeted tests to verify they pass**

Run:

```bash
swift test --filter MeetingHistorySearchTests
swift test --filter AppViewModelTestRunContextTests
```

Expected: PASS.

---

### Task 3: Verify Build And CPU Direction

**Files:**
- No source changes.

- [x] **Step 1: Run the focused tests**

Run:

```bash
swift test --filter SelectableTranscriptTextViewTests
swift test --filter MeetingHistorySearchTests
swift test --filter AppViewModelTestRunContextTests
```

Expected: all PASS.

- [x] **Step 2: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [x] **Step 3: Build the app bundle**

Run:

```bash
./scripts/build_app.sh release
```

Expected: `dist/Meeting Rescue.app` exists.

- [x] **Step 4: Profile the built app**

Run the built app as a separate instance, reproduce live watch, verify the PID, then sample:

```bash
open -n "dist/Meeting Rescue.app"
PID=""
for _ in {1..20}; do
  PID="$(pgrep -f 'dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue' | head -1)"
  [ -n "$PID" ] && break
  sleep 0.5
done
test -n "$PID"
ps -p "$PID" -o pid=,command=
sample "$PID" 15 -file /tmp/meetingrescue-after-cpu-fix.sample.txt
top -pid "$PID" -l 4 -s 2 -stats pid,command,cpu,threads,time,mem,state
```

Expected:
- `NSTextCheckingOperationQueue` is absent or much smaller in `/tmp/meetingrescue-after-cpu-fix.sample.txt`.
- `MeetingHistorySearch.naturalLanguageTokens` / `NLTokenizer` is absent or much smaller during history refresh.
- CPU direction improves versus the earlier `50-90%` samples. Do not promise a final CPU number from this patch alone because SwiftUI layout work can still remain.

Result note: completed with a fresh `dist/Meeting Rescue.app` smoke profile. This was not a full user-session live-watch reproduction, but the after-sample no longer contains the original AppKit text-checking or `NLTokenizer` symbols.

---

## Commit

After verification:

```bash
git add Sources/MeetingRescue/SelectableTranscriptTextView.swift Sources/MeetingRescueCore/MeetingHistorySearch.swift Sources/MeetingRescue/AppViewModel.swift Tests/MeetingRescueTests/SelectableTranscriptTextViewTests.swift Tests/MeetingRescueCoreTests/MeetingHistorySearchTests.swift Tests/MeetingRescueTests/AppViewModelTestRunContextTests.swift docs/superpowers/plans/2026-06-18-live-watch-cpu-hotspots.md
git commit -m "fix: reduce live watch CPU hotspots"
```

Skipped: custom caches, state-store rewrites, release packaging, and SwiftUI view splitting. Add them only if the after-sample still shows the same hot path.
