import Testing
@testable import MeetingRescueCore

@Suite("Meeting timestamp formatter")
struct MeetingTimestampFormatterTests {
    @Test("ISO timestamp를 회의 경과 시간으로 표시한다")
    func formatsISOAsElapsedTime() {
        let value = MeetingTimestampFormatter.display(
            "2025-12-29T17:05:28Z",
            meetingDateTime: "2025-12-29 17:01:15"
        )

        #expect(value == "[04:13]")
    }

    @Test("이미 경과 시간인 timestamp는 bracket 형식으로 정규화한다")
    func normalizesElapsedTimestamp() {
        #expect(MeetingTimestampFormatter.display("04:13", meetingDateTime: nil) == "[04:13]")
        #expect(MeetingTimestampFormatter.display("[04:13]", meetingDateTime: nil) == "[04:13]")
    }

    @Test("자정 기준 ISO처럼 들어온 elapsed timestamp는 transcript 시간으로 표시한다")
    func formatsMidnightISOAsTranscriptElapsedTime() {
        let meetingDateTime = "2026-05-19 09:45:34"

        #expect(MeetingTimestampFormatter.display("2026-05-19T00:05:00Z", meetingDateTime: meetingDateTime) == "[00:05]")
        #expect(MeetingTimestampFormatter.display("2026-05-19T01:25:00Z", meetingDateTime: meetingDateTime) == "[01:25]")
        #expect(MeetingTimestampFormatter.display("2026-05-19T00:06:53Z", meetingDateTime: meetingDateTime) == "[06:53]")
        #expect(MeetingTimestampFormatter.displayRange(
            "2026-05-19T03:57:00Z",
            endTimestamp: "2026-05-19T00:06:53Z",
            meetingDateTime: meetingDateTime
        ) == "[03:57]-[06:53]")
    }
}
