import Foundation
import Testing
@testable import MeetingRescueCore

struct CalendarContextModelsTests {
    @Test("supplemental context는 prompt priority 순서로 정렬된다")
    func sortsSupplementalContextByPriority() {
        let values = [
            SupplementalContextSource(id: "calendar", kind: .calendarMetadata, title: "Calendar", sourceName: "Calendar", excerpt: "event", priority: .calendarMetadata, confidence: 0.7),
            SupplementalContextSource(id: "attached", kind: .attachedText, title: "Agenda", sourceName: "agenda.md", excerpt: "agenda", priority: .userAttachedContext, confidence: 1.0),
            SupplementalContextSource(id: "confirmed", kind: .confirmedLocalArtifact, title: "Previous", sourceName: "Meeting Rescue", excerpt: "decision", priority: .confirmedLocalArtifact, confidence: 1.0)
        ]

        #expect(values.sortedForPrompt().map(\.id) == ["confirmed", "attached", "calendar"])
    }

    @Test("calendar identity는 recurrence id를 series key로 우선 사용한다")
    func calendarIdentityUsesRecurrenceIDForSeriesKey() {
        let identity = MeetingIdentity(
            calendarEventID: "event-1",
            recurrenceID: "series-1",
            fallbackFingerprint: "fallback",
            confidence: 0.91,
            isConfirmed: true
        )

        #expect(identity.seriesKey == "calendar:series-1")
    }

    @Test("analysis state는 calendar context를 저장하고 legacy JSON은 기본값으로 decode된다")
    func persistsCalendarContextStateAndDecodesLegacy() throws {
        var state = MeetingAnalysisState()
        state.calendarContext = CalendarContextState(
            mcpStatus: .connected,
            eventCandidates: [
                CalendarEventCandidate(
                    id: "event-1",
                    title: "Launch Review",
                    startDateText: "2026-06-03T10:00:00+09:00",
                    endDateText: "2026-06-03T11:00:00+09:00",
                    organizer: "alex@example.com",
                    attendees: ["alex@example.com", "blair@example.com"],
                    descriptionExcerpt: "Agenda",
                    recurrenceID: "series-1",
                    confidence: 0.88,
                    status: .accepted
                )
            ],
            supplementalSources: [
                SupplementalContextSource(id: "ctx-1", kind: .calendarMetadata, title: "Launch Review", sourceName: "Google Calendar", excerpt: "Agenda", priority: .calendarMetadata, confidence: 0.88)
            ],
            meetingIdentity: MeetingIdentity(calendarEventID: "event-1", recurrenceID: "series-1", fallbackFingerprint: "fallback", confidence: 0.88, isConfirmed: true)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(MeetingAnalysisState.self, from: data)

        #expect(decoded.calendarContext.mcpStatus == .connected)
        #expect(decoded.calendarContext.eventCandidates.first?.status == .accepted)
        #expect(decoded.calendarContext.meetingIdentity?.seriesKey == "calendar:series-1")

        let legacy = #"{"confirmedCandidateIDs":[],"deletedCandidateIDs":[],"decisionCandidateEdits":{},"actionItemCandidateEdits":{},"updatedAt":"2026-06-03T00:00:00Z","isCompleted":false,"usageSummary":{"totalInputTokens":0,"totalOutputTokens":0,"totalEstimatedCostUSD":0,"samples":[]},"attemptLogs":[],"analyzedTranscriptCharacterCount":0,"bookmarks":[]}"#
        let legacyDecoded = try JSONDecoder().decode(MeetingAnalysisState.self, from: Data(legacy.utf8))
        #expect(legacyDecoded.calendarContext == CalendarContextState())
    }

    @Test("test run replay는 저장된 calendar context만 재사용하고 MCP 상태를 cached로 표시한다")
    func cachedCalendarContextForTestRunReplay() {
        let context = CalendarContextState(
            mcpStatus: .connected,
            eventCandidates: [
                CalendarEventCandidate(
                    id: "event-1",
                    title: "Launch Review",
                    startDateText: "2026-06-03T10:00:00+09:00",
                    endDateText: "2026-06-03T11:00:00+09:00",
                    organizer: "alex@example.com",
                    attendees: ["alex@example.com", "blair@example.com"],
                    descriptionExcerpt: "Agenda",
                    recurrenceID: "series-1",
                    confidence: 0.88,
                    status: .accepted
                )
            ],
            supplementalSources: [
                SupplementalContextSource(id: "ctx-1", kind: .calendarMetadata, title: "Launch Review", sourceName: "Google Calendar", excerpt: "Agenda", priority: .calendarMetadata, confidence: 0.88)
            ],
            meetingIdentity: MeetingIdentity(calendarEventID: "event-1", recurrenceID: "series-1", fallbackFingerprint: "fallback", confidence: 0.88, isConfirmed: true),
            lastFetchedAt: Date(timeIntervalSince1970: 100),
            lastError: "previous transient failure"
        )

        let replayContext = context.cachedForTestRunReplay()

        #expect(replayContext.mcpStatus == .cachedReplay)
        #expect(replayContext.eventCandidates.first?.id == "event-1")
        #expect(replayContext.supplementalSources.first?.id == "ctx-1")
        #expect(replayContext.meetingIdentity?.seriesKey == "calendar:series-1")
        #expect(replayContext.lastFetchedAt == context.lastFetchedAt)
        #expect(replayContext.lastError == nil)
    }

    @Test("text attachment reader stores capped excerpt and source metadata")
    func readsCappedAttachmentExcerpt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-rescue-context-\(UUID().uuidString).md")
        try String(repeating: "agenda ", count: 1_000).write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = try SupplementalContextReader.source(from: url, characterLimit: 120)

        #expect(source.kind == .attachedText)
        #expect(source.sourceName == url.lastPathComponent)
        #expect(source.excerpt.count <= 120)
        #expect(source.priority == .userAttachedContext)
    }
}
