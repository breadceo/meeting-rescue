import Testing
@testable import MeetingRescueCore

@Suite("LocalAnalysisFallback")
struct LocalAnalysisFallbackTests {
    @Test("provider 실패 시 표시 가능한 snapshot을 만든다")
    func createsDisplayableSnapshot() {
        let request = AnalysisRequest(
            meetingID: "meeting",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: """
            Room
            2026-05-15 10:00
            Alex, Sam

            [00:01] Alex: 오늘은 analysis 표시 문제를 봅니다.
            [00:10] Sam: schema 오류를 확인해야 합니다.
            """
        )

        let snapshot = LocalAnalysisFallback.snapshot(for: request, message: "schema failed")

        #expect(!snapshot.currentIssue.summary.isEmpty)
        #expect(!snapshot.topicTimeline.isEmpty)
        #expect(snapshot.risksOrNotes.contains { $0.contains("schema failed") })
    }
}
