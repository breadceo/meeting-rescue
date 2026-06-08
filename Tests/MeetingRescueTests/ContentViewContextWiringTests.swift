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
