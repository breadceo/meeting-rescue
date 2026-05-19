import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("AnalysisScheduler")
struct AnalysisSchedulerTests {
    @Test("같은 meeting의 analysis job은 single-flight로 실행한다")
    func enforcesSingleFlight() async {
        let scheduler = AnalysisScheduler()
        let provider = DelayedProvider(delayNanoseconds: 200_000_000)
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "A"),
            rawTranscript: "[00:01] A: hello"
        )
        await scheduler.setActiveMeetingID("meeting-1")

        async let first = scheduler.runIfIdle(request: request, provider: provider)
        try? await Task.sleep(nanoseconds: 40_000_000)
        let second = await scheduler.runIfIdle(request: request, provider: provider)

        #expect(second == .skippedAlreadyRunning)
        guard case .success(_, _, let rawOutput, _) = await first else {
            Issue.record("첫 analysis는 성공해야 한다.")
            return
        }
        #expect(rawOutput == #"{"ok":true}"#)
    }

    @Test("active file switch 이후 stale result를 무시한다")
    func ignoresStaleResultAfterActiveMeetingSwitch() async {
        let scheduler = AnalysisScheduler()
        let provider = DelayedProvider(delayNanoseconds: 120_000_000)
        let request = AnalysisRequest(
            meetingID: "old-meeting",
            metadata: MeetingMetadata(room: "Old"),
            rawTranscript: "[00:01] A: old"
        )
        await scheduler.setActiveMeetingID("old-meeting")

        async let result = scheduler.runIfIdle(request: request, provider: provider)
        try? await Task.sleep(nanoseconds: 40_000_000)
        await scheduler.setActiveMeetingID("new-meeting")

        #expect(await result == .staleIgnored(previousSnapshot: nil))
    }

    @Test("provider failure가 이전 snapshot을 보존한다")
    func preservesPreviousSnapshotOnFailure() async {
        let scheduler = AnalysisScheduler()
        let previous = AnalysisSnapshot(currentIssue: CurrentIssue(summary: "이전 분석"))
        await scheduler.setActiveMeetingID("meeting-1")
        await scheduler.seedSnapshot(previous, for: "meeting-1")

        let result = await scheduler.runIfIdle(
            request: AnalysisRequest(
                meetingID: "meeting-1",
                metadata: MeetingMetadata(room: "A"),
                rawTranscript: "[00:01] A: hello"
            ),
            provider: FailingProvider()
        )

        #expect(result == .failurePreserved(previousSnapshot: previous, message: "boom", runTrace: nil))
    }
}

private struct DelayedProvider: LLMProvider {
    let kind: LLMProviderKind = .codexExec
    let delayNanoseconds: UInt64

    func analyze(_ request: AnalysisRequest) async throws -> AnalysisProviderResult {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let snapshot = AnalysisSnapshot(
            currentIssue: CurrentIssue(summary: request.metadata.displayTitle),
            provider: kind
        )
        let usage = LLMUsageSample(
            provider: kind,
            modelPreset: request.modelPreset,
            modelName: "test-model",
            inputTokens: 10,
            outputTokens: 5,
            inputPricePerMillionUSD: 1,
            outputPricePerMillionUSD: 2,
            estimatedCostUSD: 0.00002
        )
        return AnalysisProviderResult(snapshot: snapshot, usage: usage, rawOutput: #"{"ok":true}"#)
    }
}

private struct FailingProvider: LLMProvider {
    let kind: LLMProviderKind = .codexExec

    func analyze(_ request: AnalysisRequest) async throws -> AnalysisProviderResult {
        throw TestError()
    }

    private struct TestError: LocalizedError {
        var errorDescription: String? { "boom" }
    }
}
