import Foundation
import MeetingRescueCore
import Testing
@testable import MeetingRescue

struct AppViewModelTestRunContextTests {
    @Test("Test Run loads saved Google Calendar context as cached replay")
    @MainActor
    func testRunLoadsSavedCalendarContextAsCachedReplay() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRescueTestRun-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let transcriptURL = rootURL.appendingPathComponent("calendar-context-test.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        Zigbang(2F)_Meeting Room L3
        2026-06-08 11:30
        Ethan, Alex

        [00:00] Ethan: Calendar context smoke.
        """.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
        let savedContext = CalendarContextState(
            mcpStatus: .connected,
            eventCandidates: [
                CalendarEventCandidate(
                    id: "google:event-1",
                    title: "원오빌 통합광고 싱크업",
                    startDateText: "2026-06-08T11:30:00+09:00",
                    endDateText: "2026-06-08T12:00:00+09:00",
                    recurrenceID: "series-1",
                    confidence: 0.92,
                    status: .accepted
                ),
                CalendarEventCandidate(
                    id: "google:event-ignored",
                    title: "다른 회의",
                    startDateText: "2026-06-08T11:30:00+09:00",
                    endDateText: "2026-06-08T12:00:00+09:00",
                    confidence: 0.45,
                    status: .dismissed
                )
            ],
            supplementalSources: [
                SupplementalContextSource(
                    id: "calendar:sync",
                    kind: .calendarMetadata,
                    title: "원오빌 통합광고 싱크업",
                    sourceName: "Google Calendar",
                    excerpt: "Calendar context that should replay during Test Run.",
                    priority: .calendarMetadata,
                    confidence: 0.92
                )
            ],
            meetingIdentity: MeetingIdentity(
                calendarEventID: "google:event-1",
                recurrenceID: "series-1",
                fallbackFingerprint: "fallback",
                confidence: 0.92,
                isConfirmed: true
            ),
            lastFetchedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        try stateStore.saveAnalysisState(MeetingAnalysisState(calendarContext: savedContext), for: transcriptURL)

        let viewModel = AppViewModel(stateStore: stateStore)
        let item = MeetingHistoryItem(
            id: transcriptURL.path,
            url: transcriptURL,
            modificationDate: Date(),
            fileSize: 1,
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3"),
            summary: nil,
            topicCount: 0,
            decisionCount: 0,
            actionCount: 0,
            hasAnalysis: true,
            isCompleted: false,
            searchIndex: "",
            searchSections: [],
            summaryPreview: nil
        )

        viewModel.startTestRunFromHistory(item)

        #expect(viewModel.transcriptRunMode == .testRun)
        #expect(viewModel.analysisState.calendarContext.mcpStatus == .cachedReplay)
        #expect(viewModel.analysisState.calendarContext.eventCandidates == savedContext.eventCandidates)
        #expect(viewModel.analysisState.calendarContext.supplementalSources == savedContext.supplementalSources)
        #expect(viewModel.analysisState.calendarContext.meetingIdentity?.seriesKey == "calendar:series-1")
        #expect(viewModel.calendarContextStatusMessage == "저장된 Google Calendar context를 Test Run에 적용했습니다.")
    }

    @Test("Test Run start path does not fetch live Google Calendar or Calendar MCP context")
    func testRunStartPathDoesNotFetchLiveCalendarContext() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let startTestRun = try #require(source.slice(from: "private func startTestRun(fileURL: URL)", to: "private func appendReplayPreambleIfNeeded()"))

        #expect(startTestRun.contains("cachedForTestRunReplay()"))
        #expect(!startTestRun.contains("fetchGoogleCalendarAPIContext()"))
        #expect(!startTestRun.contains("fetchGoogleCalendarContext()"))
        #expect(!startTestRun.contains("makeGoogleCalendarService()"))
        #expect(!startTestRun.contains("CalendarMCPContextFetcher"))
    }

    @Test("analysis request includes local glossary supplemental context")
    @MainActor
    func analysisRequestIncludesLocalGlossaryContext() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-request-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
        try stateStore.saveLocalGlossaryState(LocalGlossaryState(terms: [
            LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax"], category: .project)
        ]))
        let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "[03:12] Alex: jax workflow를 봅시다.".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let viewModel = AppViewModel(stateStore: stateStore)
        viewModel.loadTranscriptForTesting(url: transcriptURL, rawTranscript: "[03:12] Alex: jax workflow를 봅시다.")

        let request = try #require(viewModel.analysisRequestForTesting(reason: "manual-test"))

        #expect(request.supplementalContextSources.contains { $0.kind == .domainGlossary && $0.excerpt.contains("canonical: zax") })
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
