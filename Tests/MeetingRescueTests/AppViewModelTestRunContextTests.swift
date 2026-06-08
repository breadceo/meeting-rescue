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
        #expect(viewModel.analysisState.calendarContext.supplementalSources == savedContext.supplementalSources)
        #expect(viewModel.analysisState.calendarContext.meetingIdentity?.seriesKey == "calendar:series-1")
        #expect(viewModel.calendarContextStatusMessage == "저장된 Google Calendar context를 Test Run에 적용했습니다.")
    }
}
