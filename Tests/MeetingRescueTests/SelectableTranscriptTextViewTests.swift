import AppKit
import Testing
@testable import MeetingRescue

struct SelectableTranscriptTextViewTests {
    @Test("raw append update appends text storage without disturbing selection")
    @MainActor
    func rawAppendUpdateAppendsTextStorageWithoutDisturbingSelection() throws {
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.string = "첫 줄🙂\n"
        let selectedRange = (textView.string as NSString).range(of: "줄🙂")
        textView.setSelectedRange(selectedRange)
        let originalTextStorage = try #require(textView.textStorage)

        let mutation = SelectableTranscriptTextStorageUpdater.apply(
            text: "첫 줄🙂\n둘째 줄\n",
            textUpdate: .append(sequence: 1, text: "둘째 줄\n"),
            documentDidChange: false,
            previousTextIdentity: "raw:0",
            newTextIdentity: "raw:1",
            textView: textView
        )

        #expect(mutation == .appended)
        #expect(textView.textStorage === originalTextStorage)
        #expect(textView.string == "첫 줄🙂\n둘째 줄\n")
        #expect(textView.selectedRange() == selectedRange)
    }

    @Test("append update falls back to full replace when text does not match the appended suffix")
    @MainActor
    func appendUpdateFallsBackToFullReplaceWhenTextDoesNotMatchSuffix() throws {
        let textView = NSTextView()
        textView.string = "원본\n"

        let mutation = SelectableTranscriptTextStorageUpdater.apply(
            text: "재작성된 원본\n",
            textUpdate: .append(sequence: 2, text: "append-only 아님\n"),
            documentDidChange: false,
            previousTextIdentity: "raw:1",
            newTextIdentity: "raw:2",
            textView: textView
        )

        #expect(mutation == .replaced)
        #expect(textView.string == "재작성된 원본\n")
    }

    @Test("full replace update does not use append fast path even when the text has the old prefix")
    @MainActor
    func fullReplaceUpdateDoesNotUseAppendFastPathEvenWithOldPrefix() throws {
        let textView = NSTextView()
        textView.string = "원문 alias\n"

        let mutation = SelectableTranscriptTextStorageUpdater.apply(
            text: "원문 alias\ncanonical 적용\n",
            textUpdate: .fullReplace(sequence: 3),
            documentDidChange: false,
            previousTextIdentity: "glossary:2",
            newTextIdentity: "glossary:3",
            textView: textView
        )

        #expect(mutation == .replaced)
        #expect(textView.string == "원문 alias\ncanonical 적용\n")
    }

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
}
