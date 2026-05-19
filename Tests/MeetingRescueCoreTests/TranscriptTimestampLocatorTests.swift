import Testing
@testable import MeetingRescueCore

@Suite("Transcript timestamp locator")
struct TranscriptTimestampLocatorTests {
    @Test("raw transcript line에서 elapsed timestamp를 추출한다")
    func extractsElapsedTimestamp() {
        #expect(TranscriptTimestampLocator.timestamp(in: "[04:13] Alex: 결정합니다") == "04:13")
        #expect(TranscriptTimestampLocator.timestamp(in: "[01:04:13] Alex: 길어진 회의") == "01:04:13")
        #expect(TranscriptTimestampLocator.timestamp(in: "[SYSTEM] 회의 시작") == nil)
    }

    @Test("raw transcript line의 elapsed seconds를 추출한다")
    func extractsElapsedSeconds() {
        #expect(TranscriptTimestampLocator.elapsedSeconds(in: "[00:59] Alex: 아직 초반") == 59)
        #expect(TranscriptTimestampLocator.elapsedSeconds(in: "[01:00] Alex: 이제 분석 가능") == 60)
        #expect(TranscriptTimestampLocator.elapsedSeconds(in: "[01:02:03] Alex: 긴 회의") == 3723)
    }

    @Test("검색 match timestamp를 raw transcript line index로 연결한다")
    func findsLineIndexForTimestamp() {
        let lines = [
            "[00:30] Mina: 안건을 열었습니다",
            "[04:13] Alex: 가격 정책은 6월 파일럿 이후 고정합니다",
            "[04:20] Mina: 다음 액션을 정리합니다"
        ]

        #expect(TranscriptTimestampLocator.lineIndex(in: lines, matching: "04:13", meetingDateTime: nil) == 1)
        #expect(TranscriptTimestampLocator.lineIndex(in: lines, matching: "[04:20]", meetingDateTime: nil) == 2)
    }

    @Test("ISO timestamp도 회의 경과 시간 line으로 연결한다")
    func findsLineIndexForISOAsElapsedTimestamp() {
        let lines = [
            "[00:30] Mina: 안건을 열었습니다",
            "[04:13] Alex: 가격 정책은 6월 파일럿 이후 고정합니다"
        ]

        let index = TranscriptTimestampLocator.lineIndex(
            in: lines,
            matching: "2025-12-29T17:05:28Z",
            meetingDateTime: "2025-12-29 17:01:15"
        )

        #expect(index == 1)
    }
}
