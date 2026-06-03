import Foundation
import Testing
@testable import MeetingRescueCore

struct CalendarMCPContextFetcherTests {
    @Test("Codex calendar MCP arguments keep user config and enable google-calendar access")
    func codexCalendarArgumentsKeepMCPConfig() {
        let schemaURL = URL(fileURLWithPath: "/tmp/calendar-schema.json")
        let arguments = CalendarMCPCommandBuilder.codexArguments(schemaURL: schemaURL, modelPreset: .economy)

        #expect(arguments.starts(with: ["codex", "exec"]))
        #expect(!arguments.contains("--ignore-user-config"))
        #expect(arguments.contains("--output-schema"))
        #expect(arguments.contains(schemaURL.path))
        #expect(arguments.contains("--sandbox"))
        #expect(arguments.contains("read-only"))
        #expect(disabledFeatures(in: arguments).isSuperset(of: ["apps", "tool_search"]))
    }

    @Test("Claude calendar MCP arguments use print mode and preserve MCP config")
    func claudeCalendarArgumentsUsePrintMode() throws {
        let schemaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-rescue-calendar-schema-\(UUID().uuidString).json")
        try #"{"type":"object","properties":{"events":{"type":"array"}},"required":["events"]}"#
            .write(to: schemaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: schemaURL) }

        let arguments = try CalendarMCPCommandBuilder.claudeArguments(schemaURL: schemaURL, modelPreset: .economy)

        #expect(arguments.starts(with: ["claude", "-p"]))
        #expect(arguments.contains("--json-schema"))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(!arguments.contains("--tools"))
        #expect(!arguments.contains("--strict-mcp-config"))
    }

    @Test("calendar MCP output decodes event candidates and linked source candidates")
    func decodesCalendarMCPOutput() throws {
        let output = """
        {
          "events": [
            {
              "id": "event-1",
              "title": "Launch Review",
              "startDateText": "2026-06-03T10:00:00+09:00",
              "endDateText": "2026-06-03T11:00:00+09:00",
              "organizer": "alex@example.com",
              "attendees": ["alex@example.com", "blair@example.com"],
              "descriptionExcerpt": "Agenda: decide launch owner. https://docs.google.com/document/d/abc",
              "recurrenceID": "series-1",
              "confidence": 0.9
            }
          ],
          "linkedSourceCandidates": [
            {
              "id": "link-1",
              "title": "Launch PRD",
              "url": "https://docs.google.com/document/d/abc",
              "sourceName": "Google Docs",
              "confidence": 0.7
            }
          ]
        }
        """

        let result = try CalendarMCPContextFetcher.decode(output)

        #expect(result.events.first?.title == "Launch Review")
        #expect(result.events.first?.recurrenceID == "series-1")
        #expect(result.events.first?.status == .candidate)
        #expect(result.linkedSourceCandidates.first?.sourceName == "Google Docs")
    }

    private func disabledFeatures(in arguments: [String]) -> Set<String> {
        var features = Set<String>()
        for index in arguments.indices where arguments[index] == "--disable" {
            let nextIndex = arguments.index(after: index)
            guard arguments.indices.contains(nextIndex) else {
                continue
            }
            features.insert(arguments[nextIndex])
        }
        return features
    }
}
