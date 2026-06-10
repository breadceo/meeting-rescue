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

    @Test("compact Meeting Intelligence labels can wrap to two lines")
    func compactMeetingIntelligenceLabelsCanWrapToTwoLines() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains(#"return "Meeting\nIntelligence""#))
        #expect(source.contains("pane.compactTitle"))
        #expect(source.contains(".lineLimit(2)"))
        #expect(source.contains(".multilineTextAlignment(.center)"))
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
