import Foundation
import Testing

struct ContentViewContextWiringTests {
    @Test("context intelligence lane renders the context panel")
    func contextLaneRendersContextPanel() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("case .context:\n                            contextPanel()"))
        #expect(!source.contains("case .context:\n                            EmptyView()"))
    }

    @Test("context panel hides Google Calendar MCP controls")
    func contextPanelHidesGoogleCalendarMCPControls() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let contextPanel = try #require(source.slice(from: "private func contextPanel()", to: "private func googleCalendarAPIStatusCard()"))
        let eventCandidates = try #require(source.slice(from: "private func calendarEventCandidates", to: "private func supplementalContextSources"))

        #expect(!contextPanel.contains("calendarMCPStatusCard()"))
        #expect(!eventCandidates.contains("Google Calendar MCP"))
    }

    @Test("context panel exposes Google Calendar API controls")
    func contextPanelExposesGoogleCalendarAPIControls() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let contextPanel = try #require(source.slice(from: "private func contextPanel()", to: "private func googleCalendarAPIStatusCard()"))
        let apiCard = try #require(source.slice(from: "private func googleCalendarAPIStatusCard()", to: "private var googleCalendarContextActions"))
        let apiActions = try #require(source.slice(from: "private var googleCalendarContextActions", to: "private func calendarMCPStatusCard()"))

        #expect(contextPanel.contains("googleCalendarAPIStatusCard()"))
        #expect(apiCard.contains(#"sectionHeader("Google Calendar API""#))
        #expect(apiCard.contains("googleCalendarContextActions"))
        #expect(apiActions.contains("connectGoogleCalendar()"))
        #expect(apiActions.contains("fetchGoogleCalendarAPIContext()"))
        #expect(apiActions.contains("disconnectGoogleCalendar()"))
    }

    @Test("settings exposes local glossary controls")
    func settingsExposeLocalGlossaryControls() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("case glossary = \"용어\""))
        #expect(source.contains("localGlossarySettings"))
        #expect(source.contains("용어 후보 검토와 정답 용어 편집은 Meeting Intelligence의 용어 탭에서 진행합니다."))
        #expect(source.contains("Accepted Terms"))
    }

    @Test("meeting intelligence exposes local glossary lane")
    func meetingIntelligenceExposesLocalGlossaryLane() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("case glossary = \"용어\""))
        #expect(source.contains("case .glossary:"))
        #expect(source.contains("localGlossaryPanel()"))
        #expect(source.contains("LocalGlossarySuggestionReviewRow"))
        #expect(source.contains("localGlossaryProgressView"))
        #expect(source.contains("viewModel.localGlossaryRefreshProgress"))
    }

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

    @Test("selectable transcript bridge captures raw text selection")
    func selectableTranscriptBridgeCapturesRawTextSelection() throws {
        let selectableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/SelectableTranscriptTextView.swift")
        let selectable = try String(contentsOf: selectableURL, encoding: .utf8)

        #expect(selectable.contains("NSViewRepresentable"))
        #expect(selectable.contains("NSTextView"))
        #expect(selectable.contains("textViewDidChangeSelection"))
        #expect(selectable.contains("onSelectionChange"))
        #expect(selectable.contains("scrollToLine"))
        #expect(selectable.contains("textIdentity"))
        #expect(selectable.contains("lastTextIdentity"))
        #expect(!selectable.contains("textView.string != text"))
    }

    @Test("selectable transcript bridge pauses live follow on manual scroll")
    func selectableTranscriptBridgePausesLiveFollowOnManualScroll() throws {
        let selectableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/SelectableTranscriptTextView.swift")
        let selectable = try String(contentsOf: selectableURL, encoding: .utf8)

        #expect(selectable.contains("scrollToBottomToken"))
        #expect(selectable.contains("onAutoFollowChange"))
        #expect(selectable.contains("boundsDidChangeNotification"))
        #expect(selectable.contains("clipViewBoundsDidChange"))
        #expect(selectable.contains("isAutoFollowEnabled"))
        #expect(selectable.contains("isProgrammaticScroll"))
        #expect(selectable.contains("isNearBottom"))
        #expect(selectable.contains("scrollToBottom(enableAutoFollow: true)"))
    }

    @Test("selectable transcript defers SwiftUI state callbacks outside updateNSView")
    func selectableTranscriptDefersSwiftUIStateCallbacksOutsideUpdateNSView() throws {
        let selectableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/SelectableTranscriptTextView.swift")
        let selectable = try String(contentsOf: selectableURL, encoding: .utf8)
        let updateNSView = try #require(selectable.slice(from: "func updateNSView", to: "final class Coordinator"))
        let autoFollowSetter = try #require(selectable.slice(from: "private func setAutoFollowEnabled", to: "func emitSelectionChange"))

        #expect(selectable.contains("func emitSelectionChange"))
        #expect(selectable.contains("private func emitAutoFollowChange"))
        #expect(selectable.contains("Task { @MainActor in"))
        #expect(!updateNSView.contains("context.coordinator.onSelectionChange("))
        #expect(!autoFollowSetter.contains("onAutoFollowChange(isEnabled)"))
    }

    @Test("selectable transcript keeps text layout top aligned while following append")
    func selectableTranscriptKeepsTextLayoutTopAlignedWhileFollowingAppend() throws {
        let selectableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/SelectableTranscriptTextView.swift")
        let selectable = try String(contentsOf: selectableURL, encoding: .utf8)

        #expect(selectable.contains("configureTextViewLayout"))
        #expect(selectable.contains("CGFloat.greatestFiniteMagnitude"))
        #expect(selectable.contains("textView.layoutManager?.ensureLayout"))
        #expect(selectable.contains("scrollToVisibleBottom"))
        #expect(!selectable.contains("textView.scrollToEndOfDocument(nil)"))
    }

    @Test("selectable transcript resets scroll layout when selected document changes")
    func selectableTranscriptResetsScrollLayoutWhenSelectedDocumentChanges() throws {
        let selectableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/SelectableTranscriptTextView.swift")
        let selectable = try String(contentsOf: selectableURL, encoding: .utf8)
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(selectable.contains("documentIdentity"))
        #expect(selectable.contains("lastDocumentIdentity"))
        #expect(selectable.contains("resetLayoutForNewDocument"))
        #expect(selectable.contains("lastFocusedLineID = nil"))
        #expect(selectable.contains("scrollView.contentView.scroll(to: .zero)"))
        #expect(selectable.contains("textView.setFrameSize(NSSize(width: width, height: height))"))
        #expect(source.contains("displayedTranscriptDocumentIdentity"))
        #expect(source.contains("documentIdentity: displayedTranscriptDocumentIdentity"))
        #expect(source.contains(".id(displayedTranscriptDocumentIdentity)"))
    }

    @Test("raw transcript exposes resume live follow button")
    func rawTranscriptExposesResumeLiveFollowButton() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rawScroll = try #require(source.slice(from: "private var rawTranscriptScroll", to: "private var displayedTranscript"))
        let footer = try #require(source.slice(from: "private var rawTranscriptGlossaryFooter", to: "private var header"))

        #expect(source.contains("@State private var rawTranscriptScrollToBottomToken"))
        #expect(source.contains("@State private var isRawTranscriptAutoFollowPaused"))
        #expect(rawScroll.contains("scrollToBottomToken: rawTranscriptScrollToBottomToken"))
        #expect(rawScroll.contains("onAutoFollowChange"))
        #expect(footer.contains("isRawTranscriptAutoFollowPaused"))
        #expect(footer.contains("rawTranscriptScrollToBottomToken += 1"))
        #expect(footer.contains("맨 아래"))
        #expect(footer.contains("arrow.down.to.line"))
    }

    @Test("raw transcript exposes selected text glossary registration sheet")
    func rawTranscriptExposesSelectedTextGlossaryRegistrationSheet() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("@State private var selectedRawTranscriptGlossaryText"))
        #expect(source.contains("@State private var glossarySelectionSheet"))
        #expect(source.contains("SelectableTranscriptTextView("))
        #expect(source.contains("LocalGlossaryManualSelection.sanitizedText"))
        #expect(source.contains("선택한 텍스트"))
        #expect(source.contains("새 용어로 등록"))
        #expect(source.contains("기존 용어 alias로 추가"))
        #expect(source.contains("LocalGlossarySelectionSheet"))
        #expect(source.contains("viewModel.addManualLocalGlossaryTerm"))
        #expect(source.contains("viewModel.addManualLocalGlossaryAlias"))
    }

    @Test("raw transcript exposes glossary applied display toggle")
    func rawTranscriptExposesGlossaryAppliedDisplayToggle() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rawScroll = try #require(source.slice(from: "private var rawTranscriptScroll", to: "private var displayedTranscript"))
        let header = try #require(source.slice(from: "private var rawTranscriptHeader", to: "private var momentMarkerTranscriptMenu"))

        #expect(source.contains("private enum TranscriptDisplayMode"))
        #expect(source.contains("@State private var transcriptDisplayMode"))
        #expect(source.contains("@State private var cachedDisplayedTranscript"))
        #expect(source.contains("@State private var cachedDisplayedTranscriptSignature"))
        #expect(header.contains("VStack(alignment: .leading"))
        #expect(header.contains("HStack(spacing: 10)"))
        #expect(header.contains("HStack(spacing: 8)"))
        #expect(header.contains("Picker(\"Transcript view\""))
        #expect(header.contains("원문"))
        #expect(source.contains("용어 적용"))
        #expect(source.contains("용어 힌트"))
        #expect(!source.contains("힌트 \\(viewModel.activeLocalGlossaryMatchCount)개 적용 중"))
        #expect(header.contains("mode.displayName"))
        #expect(header.contains(".labelsHidden()"))
        #expect(rawScroll.contains("cachedDisplayedTranscript"))
        #expect(!rawScroll.contains("LocalGlossaryTranscriptRenderer.render"))
        #expect(rawScroll.contains("renderedTranscript.text"))
        #expect(source.contains("replacementCount"))
        #expect(source.contains("refreshDisplayedTranscriptCacheIfNeeded"))
        #expect(source.contains("displayedTranscriptSignature"))
    }

    @Test("wide intelligence header stacks tabs without wrapping title")
    func wideIntelligenceHeaderStacksTabsWithoutWrappingTitle() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let intelligenceContent = try #require(source.slice(from: "private func intelligenceContent", to: "private var visibleIntelligenceMode"))
        let regularHeader = try #require(source.slice(from: "private func regularIntelligenceHeader()", to: "private var visibleIntelligenceMode"))
        let paneTitle = try #require(source.slice(from: "private func paneTitle", to: "private var overlayPaneToggleBar"))

        #expect(intelligenceContent.contains("regularIntelligenceHeader()"))
        #expect(regularHeader.contains("ViewThatFits(in: .horizontal)"))
        #expect(regularHeader.contains("paneTitle(\"Meeting Intelligence\""))
        #expect(regularHeader.contains("VStack(alignment: .leading, spacing: 10)"))
        #expect(regularHeader.contains("intelligenceModeMenu()"))
        #expect(!source.contains("Meeting\\nIntelligence"))
        #expect(paneTitle.contains("Label {"))
        #expect(paneTitle.contains(".lineLimit(2)"))
        #expect(paneTitle.contains(".fixedSize(horizontal: true, vertical: true)"))
        #expect(!source.contains("compactTitle"))
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
}

private extension String {
    func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker),
              let end = range(of: endMarker, range: start.upperBound..<endIndex) else {
            return nil
        }
        return String(self[start.lowerBound..<end.lowerBound])
    }
}
