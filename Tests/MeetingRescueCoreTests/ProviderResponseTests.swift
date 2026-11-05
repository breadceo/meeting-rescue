import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Provider response metadata")
struct ProviderResponseTests {
    let envelope = #"{"meetingRescueResultVersion":1,"output":"{\"meetingType\":\"planning\"}","usage":{"modelName":"gpt-6-luna-2026-09-22","inputTokens":1234,"outputTokens":87,"totalTokens":1321,"cachedInputTokens":100,"reasoningOutputTokens":12,"responseID":"resp-test"}}"#

    @Test("custom command retains API model and exact usage instead of preset estimates")
    func customCommandUsesReportedMetadata() throws {
        let parsed = try ParsedProviderResponse.customCommand(envelope)
        let reported = try #require(parsed.reportedUsage)
        let sample = LLMUsagePricing.usageSample(
            provider: .customCommand, modelPreset: .balanced, reason: "manual",
            inputText: "short", outputText: parsed.output, reportedUsage: reported
        )
        #expect(sample.modelName == "gpt-6-luna-2026-09-22")
        #expect(sample.inputTokens == 1234)
        #expect(sample.outputTokens == 87)
        #expect(sample.reportedUsage?.totalTokens == 1321)
        #expect(sample.reportedUsage?.cachedInputTokens == 100)
        #expect(sample.reportedUsage?.reasoningOutputTokens == 12)
        #expect(sample.reportedUsage?.responseID == "resp-test")
        #expect(sample.tokenUsageLabel == "실측")
        #expect(parsed.output == #"{"meetingType":"planning"}"#)
        var attempt = AnalysisAttemptLog(reason: "manual", status: .running,
                                         provider: .customCommand, modelPreset: .balanced, modelName: "old")
        attempt.recordUsage(sample)
        let restored = try JSONDecoder().decode(AnalysisAttemptLog.self, from: JSONEncoder().encode(attempt))
        #expect(restored.modelName == sample.modelName)
        #expect(restored.inputTokens == 1234)
        #expect(restored.outputTokens == 87)
        #expect(restored.usage?.reportedUsage?.responseID == "resp-test")
    }

    @Test("legacy custom commands remain compatible and never inherit a Codex model name")
    func legacyCommandsAreEstimated() throws {
        let output = #"{"meetingType":"status"}"#
        let parsed = try ParsedProviderResponse.customCommand(output)
        #expect(parsed.output == output)
        #expect(parsed.reportedUsage == nil)
        let sample = LLMUsagePricing.usageSample(provider: .customCommand, modelPreset: .balanced,
                                                reason: "manual", inputText: "prompt", outputText: output)
        #expect(sample.modelName == "custom provider default")
        #expect(sample.tokenUsageLabel == "추정")
    }

    @Test("malformed usage is rejected instead of silently recording estimates as actual")
    func rejectsInvalidEnvelope() {
        for output in [envelope.replacingOccurrences(of: "1234", with: "-1"),
                       envelope.replacingOccurrences(of: "ResultVersion\":1", with: "ResultVersion\":2")] {
            #expect(throws: (any Error).self) { try ParsedProviderResponse.customCommand(output) }
        }
    }

    @Test("Codex JSONL retains completed turn usage and only the final assistant message")
    func codexEventUsage() throws {
        let jsonl = """
        {"type":"thread.started","thread_id":"thread-test"}
        {"type":"item.completed","item":{"type":"reasoning","text":"internal"}}
        {"type":"item.completed","item":{"type":"agent_message","text":"{\\"meetingType\\":\\"planning\\"}"}}
        {"type":"turn.completed","usage":{"input_tokens":4321,"cached_input_tokens":4000,"cache_write_input_tokens":0,"output_tokens":123,"reasoning_output_tokens":20}}
        """
        let parsed = try ParsedProviderResponse.codexEvents(jsonl)
        #expect(parsed.output == #"{"meetingType":"planning"}"#)
        #expect(parsed.reportedUsage?.inputTokens == 4321)
        #expect(parsed.reportedUsage?.outputTokens == 123)
        #expect(parsed.reportedUsage?.cachedInputTokens == 4000)
        #expect(parsed.reportedUsage?.cacheWriteInputTokens == 0)
        #expect(parsed.reportedUsage?.reasoningOutputTokens == 20)
        #expect(parsed.reportedUsage?.modelName == nil)
    }

    @Test("old persisted usage samples remain estimated")
    func legacyUsageDecodes() throws {
        let sample = LLMUsagePricing.usageSample(provider: .codexExec, modelPreset: .economy,
                                                reason: "manual", inputText: "a", outputText: "b")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        json.removeValue(forKey: "reportedUsage")
        let restored = try JSONDecoder().decode(LLMUsageSample.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.reportedUsage == nil)
        #expect(restored.tokenUsageLabel == "추정")
    }

    @Test("custom command process negotiates metadata and returns a decoded snapshot with real usage")
    func customCommandProcessUsesEnvelope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = AnalysisSnapshot(meetingType: .planning, currentIssue: CurrentIssue(summary: "테스트 계획"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let snapshotText = try #require(String(data: encoder.encode(snapshot), encoding: .utf8))
        let metadata = try #require(JSONSerialization.jsonObject(with: Data(envelope.utf8)) as? [String: Any])
        var response = metadata
        response["output"] = snapshotText
        let outputURL = directory.appendingPathComponent("response.json")
        try JSONSerialization.data(withJSONObject: response).write(to: outputURL)
        let provider = CustomCommandProvider(
            command: "test \"$MEETING_RESCUE_RESULT_FORMAT\" = json-v1 && /bin/cat '\(outputURL.path)'",
            timeoutSeconds: 10, workingDirectoryURL: directory, modelPreset: .balanced
        )
        let result = try await provider.analyze(AnalysisRequest(
            meetingID: "integration", metadata: MeetingMetadata(room: "Test"),
            rawTranscript: "[00:01] Alex: 테스트 계획입니다.", reason: "final"
        ))
        #expect(result.snapshot.currentIssue.summary == "테스트 계획")
        #expect(result.usage.modelName == "gpt-6-luna-2026-09-22")
        #expect(result.usage.inputTokens == 1234)
        #expect(result.usage.reportedUsage?.responseID == "resp-test")
        #expect(result.rawOutput == snapshotText)
    }
}
