import Testing
@testable import MeetingRescueCore

@Suite("Analysis transcript window")
struct AnalysisTranscriptWindowTests {
    @Test("automatic analysis limits restart catch-up to the next chunk")
    func automaticLimitsCatchUpChunk() {
        let rawTranscript = (0..<20)
            .map { "[00:\($0)] Speaker: line \($0)" }
            .joined(separator: "\n")
        let previousLineEnd = rawTranscript.firstIndex(of: "\n")!
        let lastAnalyzedCount = rawTranscript.distance(
            from: rawTranscript.startIndex,
            to: rawTranscript.index(after: previousLineEnd)
        )

        let window = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: lastAnalyzedCount,
            reason: "automatic",
            maxAutomaticCatchUpCharacters: 90
        )

        #expect(window.isChunked)
        #expect(window.rawTranscript.count == window.targetTranscriptCharacterCount)
        #expect(window.targetTranscriptCharacterCount < rawTranscript.count)
        #expect(window.lastAnalyzedTranscriptCharacterCount == lastAnalyzedCount)
        #expect(window.rawTranscript.hasSuffix("\n"))
        #expect(window.messageSuffix?.contains("catch-up \(lastAnalyzedCount)-") == true)
    }

    @Test("hybrid automatic reason도 catch-up chunk를 제한한다")
    func hybridAutomaticReasonLimitsCatchUpChunk() {
        let rawTranscript = String(repeating: "[00:01] Speaker: long line\n", count: 50)

        let window = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: 10,
            reason: "automatic-min-dialogue-lines",
            maxAutomaticCatchUpCharacters: 100
        )

        #expect(window.isChunked)
        #expect(window.targetTranscriptCharacterCount < rawTranscript.count)
    }

    @Test("manual analysis also limits long transcript to the next chunk")
    func manualLimitsCatchUpChunk() {
        let rawTranscript = String(repeating: "[00:01] Speaker: long line\n", count: 50)

        let window = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: 10,
            reason: "manual",
            maxAutomaticCatchUpCharacters: 100
        )

        #expect(window.isChunked)
        #expect(window.targetTranscriptCharacterCount < rawTranscript.count)
        #expect(window.lastAnalyzedTranscriptCharacterCount == 10)
        #expect(window.messageSuffix?.contains("catch-up 10-") == true)
    }

    @Test("final analysis uses the full transcript for whole-meeting wrap-up")
    func finalAnalysisUsesFullTranscript() {
        let rawTranscript = String(repeating: "[00:01] Speaker: long line\n", count: 50)

        let window = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: 100,
            reason: "final-continue",
            maxAutomaticCatchUpCharacters: 100
        )

        #expect(!window.isChunked)
        #expect(window.targetTranscriptCharacterCount == rawTranscript.count)
        #expect(window.rawTranscript == rawTranscript)
        #expect(window.lastAnalyzedTranscriptCharacterCount == 100)
    }
}
