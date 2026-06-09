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

        #expect(source.contains("case glossary = \"Glossary\""))
        #expect(source.contains("localGlossarySettings"))
        #expect(source.contains("용어 후보 생성"))
        #expect(source.contains("사전에 추가"))
        #expect(source.contains("다시 보지 않기"))
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
