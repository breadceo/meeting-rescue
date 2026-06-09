import Foundation
import Testing

struct CalendarQualityABRunnerTests {
    @Test("Calendar quality A/B runner is wired as an opt-in CLI path")
    func runnerIsCommandLineOnly() throws {
        let appSource = try sourceFile("Sources/MeetingRescue/MeetingRescueApp.swift")
        let runnerSource = try sourceFile("Sources/MeetingRescue/CalendarQualityABRunner.swift")

        #expect(appSource.contains("CalendarQualityABRunner.runFromCommandLineIfRequested()"))
        #expect(runnerSource.contains("guard arguments.contains(\"--calendar-quality-ab\") else"))
        #expect(!runnerSource.contains("Button("))
    }

    @Test("Calendar quality A/B runner uses one-shot Codex exec for batch runs")
    func runnerUsesOneShotCodexExec() throws {
        let runnerSource = try sourceFile("Sources/MeetingRescue/CalendarQualityABRunner.swift")
        let providerFactory = try #require(
            runnerSource.slice(from: "private static func makeProvider", to: "private static func makeGoogleCalendarServiceIfAvailable")
        )

        #expect(providerFactory.contains("CodexExecProvider("))
        #expect(providerFactory.contains("return fallback"))
        #expect(!providerFactory.contains("CodexAppServerProvider("))
        #expect(runnerSource.contains("? CodexExecutionMode.cliExec.rawValue"))
    }

    @Test("Calendar quality A/B report keeps raw output opt-in")
    func runnerKeepsRawOutputOptIn() throws {
        let runnerSource = try sourceFile("Sources/MeetingRescue/CalendarQualityABRunner.swift")

        #expect(runnerSource.contains("includeRawOutput = false"))
        #expect(runnerSource.contains("case \"--include-raw-output\""))
        #expect(runnerSource.contains("includeRawOutput ? result.rawOutput : nil"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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
