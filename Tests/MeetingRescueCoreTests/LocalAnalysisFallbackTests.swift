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

    @Test("local fallback snapshot은 provider previous snapshot으로 재사용하지 않도록 판별한다")
    func detectsFallbackSnapshot() {
        let request = AnalysisRequest(
            meetingID: "meeting",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:01] Alex: 아직 provider 결과를 기다립니다."
        )
        let fallback = LocalAnalysisFallback.snapshot(for: request, message: "running")
        let real = AnalysisSnapshot(currentIssue: CurrentIssue(summary: "실제 provider 요약입니다."))

        #expect(LocalAnalysisFallback.isFallbackSnapshot(fallback))
        #expect(!LocalAnalysisFallback.isFallbackSnapshot(real))
        #expect(!LocalAnalysisFallback.isFallbackSnapshot(nil))
    }
}
