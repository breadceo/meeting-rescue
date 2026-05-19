import Testing
@testable import MeetingRescueCore

@Suite("Transcript replay")
struct TranscriptReplayTests {
    @Test("line 순서대로 transcript frame을 만든다")
    func advancesInOrder() throws {
        var cursor = TranscriptReplayCursor(rawTranscript: "Room\nTime\nA, B\n\n[00:01] A: hi\n[00:02] B: ok")

        let firstFrame = cursor.advance(maxLines: 4)
        let first = try #require(firstFrame)
        #expect(first.text == "Room\nTime\nA, B\n\n")
        #expect(first.currentLine == 4)
        #expect(first.totalLines == 6)
        #expect(first.isCompleted == false)

        let secondFrame = cursor.advance(maxLines: 1)
        let second = try #require(secondFrame)
        #expect(second.text == "[00:01] A: hi\n")
        #expect(second.currentLine == 5)
        #expect(second.isCompleted == false)

        let thirdFrame = cursor.advance(maxLines: 10)
        let third = try #require(thirdFrame)
        #expect(third.text == "[00:02] B: ok")
        #expect(third.currentLine == 6)
        #expect(third.isCompleted)
        #expect(cursor.advance(maxLines: 1) == nil)
    }

    @Test("timestamp 차이를 다음 frame delay로 사용한다")
    func usesTimestampDeltaForNextFrameDelay() throws {
        var cursor = TranscriptReplayCursor(rawTranscript: "Room\nTime\nA, B\n\n[12:10] A: 먼저\n[12:13] B: 3초 뒤\n[12:13] A: 같은 시각")

        let preambleFrame = cursor.advancePreambleFrame()
        let preamble = try #require(preambleFrame)
        #expect(preamble.text == "Room\nTime\nA, B\n\n")
        #expect(preamble.currentLine == 4)

        let firstFrame = cursor.advanceTimestampPacedFrame()
        let first = try #require(firstFrame)
        #expect(first.text == "[12:10] A: 먼저\n")
        #expect(first.delayAfterSeconds == 3)

        let secondFrame = cursor.advanceTimestampPacedFrame()
        let second = try #require(secondFrame)
        #expect(second.text == "[12:13] B: 3초 뒤\n")
        #expect(second.delayAfterSeconds == 0.05)

        let thirdFrame = cursor.advanceTimestampPacedFrame()
        let third = try #require(thirdFrame)
        #expect(third.text == "[12:13] A: 같은 시각")
        #expect(third.delayAfterSeconds == 0)
        #expect(third.isCompleted)
    }

    @Test("timestamp parser는 mm:ss와 hh:mm:ss를 지원한다")
    func parsesTimestamp() {
        #expect(TranscriptReplayCursor.timestampSeconds(in: "[12:10] A: hi") == 730)
        #expect(TranscriptReplayCursor.timestampSeconds(in: "[01:02:03] A: hi") == 3_723)
        #expect(TranscriptReplayCursor.timestampSeconds(in: "no timestamp") == nil)
    }

    @Test("배속에 맞춰 timestamp delay를 줄이고 최소 delay를 보장한다")
    func adjustsDelayForReplaySpeed() {
        #expect(TranscriptReplayCursor.adjustedDelay(3, speedMultiplier: 1, minimumDelaySeconds: 0.05) == 3)
        #expect(TranscriptReplayCursor.adjustedDelay(3, speedMultiplier: 2, minimumDelaySeconds: 0.05) == 1.5)
        #expect(TranscriptReplayCursor.adjustedDelay(3, speedMultiplier: 4, minimumDelaySeconds: 0.05) == 0.75)
        #expect(TranscriptReplayCursor.adjustedDelay(0.1, speedMultiplier: 8, minimumDelaySeconds: 0.05) == 0.05)
        #expect(TranscriptReplayCursor.adjustedDelay(3, speedMultiplier: 0, minimumDelaySeconds: 0.05) == 3)
    }
}
