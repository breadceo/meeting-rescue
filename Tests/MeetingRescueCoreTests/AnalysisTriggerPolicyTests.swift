import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Analysis trigger policy")
struct AnalysisTriggerPolicyTests {
    private let baseDate = Date(timeIntervalSince1970: 1_000)

    @Test("초기 1분 전에는 automatic analysis를 기다린다")
    func waitsDuringInitialGate() {
        let policy = AnalysisTriggerPolicy()
        let decision = policy.evaluate(
            rawTranscript: "[00:30] Alex: 이 내용은 아직 초반입니다.",
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 30,
            now: baseDate,
            lastAutomaticAnalysisAt: nil
        )

        #expect(decision == .wait(reason: "initial-meeting-gate"))
    }

    @Test("새 발화가 충분히 쌓이면 실행한다")
    func runsWhenDialogueThresholdIsReached() {
        let policy = AnalysisTriggerPolicy()
        let transcript = (1...8)
            .map { "[01:\(String(format: "%02d", $0))] Speaker: 마케팅 운영 계획과 담당 액션을 확인합니다 \($0)" }
            .joined(separator: "\n")

        let decision = policy.evaluate(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 90,
            now: baseDate,
            lastAutomaticAnalysisAt: baseDate.addingTimeInterval(-60)
        )

        #expect(decision == .run(reason: "min-dialogue-lines"))
    }

    @Test("짧은 인사만 있으면 skip한다")
    func skipsLowValueDialogue() {
        let policy = AnalysisTriggerPolicy()
        let transcript = """
        [01:10] Alex: 네
        [01:11] Morgan: 좋아요
        """

        let decision = policy.evaluate(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 90,
            now: baseDate,
            lastAutomaticAnalysisAt: baseDate.addingTimeInterval(-60)
        )

        #expect(decision == .skip(reason: "low-value-dialogue"))
    }

    @Test("precomputed transcript stats can drive the same decision without reparsing")
    func precomputedTranscriptStatsDriveDecision() {
        let policy = AnalysisTriggerPolicy()
        let transcript = (1...8)
            .map { "[01:\(String(format: "%02d", $0))] Speaker: 마케팅 운영 계획과 담당 액션을 확인합니다 \($0)" }
            .joined(separator: "\n")
        let stats = policy.transcriptStats(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0
        )

        let decision = policy.evaluate(
            stats: stats,
            latestTranscriptElapsedSeconds: 90,
            now: baseDate,
            lastAutomaticAnalysisAt: baseDate.addingTimeInterval(-60)
        )

        #expect(stats.newCharacterCount == transcript.count)
        #expect(stats.dialogueLineCount == 8)
        #expect(stats.meaningfulDialogueLineCount == 8)
        #expect(decision == .run(reason: "min-dialogue-lines"))
    }

    @Test("max wait가 지나면 작은 의미 chunk도 flush한다")
    func flushesAfterMaxWait() {
        let policy = AnalysisTriggerPolicy()
        let transcript = """
        [01:10] Alex: 운영 자료 확인이 필요합니다.
        [01:20] Morgan: 담당 일정을 다시 보겠습니다.
        """

        let decision = policy.evaluate(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 90,
            now: baseDate,
            lastAutomaticAnalysisAt: baseDate.addingTimeInterval(-180)
        )

        #expect(decision == .run(reason: "max-wait-flush"))
    }

    @Test("min batch wait 전에는 threshold가 쌓여도 기다린다")
    func waitsUntilMinimumBatchWait() {
        let policy = AnalysisTriggerPolicy()
        let transcript = (1...8)
            .map { "[01:\(String(format: "%02d", $0))] Speaker: 마케팅 운영 계획과 담당 액션을 확인합니다 \($0)" }
            .joined(separator: "\n")

        let decision = policy.evaluate(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 90,
            now: baseDate,
            lastAutomaticAnalysisAt: baseDate.addingTimeInterval(-20)
        )

        #expect(decision == .wait(reason: "min-batch-wait"))
    }

    @Test("min batch wait 전에도 큰 batch는 조기 실행한다")
    func bypassesMinimumBatchWaitForLargeBatch() {
        let policy = AnalysisTriggerPolicy()
        let transcript = (1...12)
            .map { "[01:\(String(format: "%02d", $0))] Speaker: 마케팅 운영 계획과 담당 액션을 확인합니다 \($0)" }
            .joined(separator: "\n")

        let decision = policy.evaluate(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 90,
            now: baseDate,
            lastAutomaticAnalysisAt: baseDate.addingTimeInterval(-20)
        )

        #expect(decision == .run(reason: "min-dialogue-lines"))
    }

    @Test("Balanced preset은 최소 대기 전에는 기다리고 이후 충분한 batch를 실행한다")
    func balancedPresetWaitsForLargerBatch() {
        let policy = AnalysisTriggerPolicy(
            configuration: AnalysisTriggerPreset.balanced.configuration.withMinimumMeetingElapsedSeconds(60)
        )
        let transcript = (1...24)
            .map { "[\(String(format: "%02d", 1 + ($0 / 10))):\(String(format: "%02d", $0 % 60))] Speaker: 운영 계획과 담당 액션을 확인합니다 \($0)" }
            .joined(separator: "\n")

        let earlyDecision = policy.evaluate(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 170,
            now: Date(timeIntervalSince1970: 170),
            lastAutomaticAnalysisAt: Date(timeIntervalSince1970: 60)
        )
        let readyDecision = policy.evaluate(
            rawTranscript: transcript,
            lastAnalyzedTranscriptCharacterCount: 0,
            latestTranscriptElapsedSeconds: 240,
            now: Date(timeIntervalSince1970: 240),
            lastAutomaticAnalysisAt: Date(timeIntervalSince1970: 60)
        )

        #expect(earlyDecision == .wait(reason: "min-batch-wait"))
        #expect(readyDecision == .run(reason: "min-dialogue-lines"))
    }
}
