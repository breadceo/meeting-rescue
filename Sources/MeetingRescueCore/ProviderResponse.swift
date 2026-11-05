import Foundation

public struct LLMReportedUsage: Codable, Equatable, Sendable {
    public var modelName: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var cachedInputTokens: Int?
    public var cacheWriteInputTokens: Int?
    public var reasoningOutputTokens: Int?
    public var responseID: String?

    public init(modelName: String? = nil, inputTokens: Int, outputTokens: Int,
                totalTokens: Int? = nil, cachedInputTokens: Int? = nil,
                cacheWriteInputTokens: Int? = nil, reasoningOutputTokens: Int? = nil, responseID: String? = nil) {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        let sum = inputTokens.addingReportingOverflow(outputTokens)
        self.totalTokens = totalTokens ?? (sum.overflow ? -1 : sum.partialValue)
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.responseID = responseID
    }

    var isValid: Bool {
        inputTokens >= 0 && outputTokens >= 0 && totalTokens >= inputTokens
            && totalTokens - inputTokens == outputTokens
            && (cachedInputTokens.map { (0...inputTokens).contains($0) } ?? true)
            && (cacheWriteInputTokens.map { (0...inputTokens).contains($0) } ?? true)
            && (reasoningOutputTokens.map { (0...outputTokens).contains($0) } ?? true)
            && (modelName.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true)
    }
}

struct ParsedProviderResponse {
    var output: String
    var reportedUsage: LLMReportedUsage?

    private struct Envelope: Decodable {
        var meetingRescueResultVersion: Int
        var output: String
        var usage: LLMReportedUsage
    }

    static func customCommand(_ output: String) throws -> Self {
        let data = Data(output.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["meetingRescueResultVersion"] != nil else {
            return Self(output: output)
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.meetingRescueResultVersion == 1, envelope.usage.isValid,
              envelope.usage.modelName != nil else {
            throw LLMProviderError.invalidOutput
        }
        return Self(output: envelope.output, reportedUsage: envelope.usage)
    }

    static func codexEvents(_ output: String) throws -> Self {
        var message: String?
        var usage: LLMReportedUsage?
        for line in output.split(separator: "\n") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }
            if event["type"] as? String == "item.completed",
               let item = event["item"] as? [String: Any],
               item["type"] as? String == "agent_message" {
                message = item["text"] as? String
            }
            if event["type"] as? String == "turn.completed", let tokens = event["usage"] as? [String: Any],
               let input = tokens["input_tokens"] as? Int, let output = tokens["output_tokens"] as? Int {
                let reported = LLMReportedUsage(
                    modelName: event["model"] as? String, inputTokens: input, outputTokens: output,
                    cachedInputTokens: tokens["cached_input_tokens"] as? Int,
                    cacheWriteInputTokens: tokens["cache_write_input_tokens"] as? Int,
                    reasoningOutputTokens: tokens["reasoning_output_tokens"] as? Int
                )
                guard reported.isValid else { throw LLMProviderError.invalidOutput }
                usage = reported
            }
        }
        // Accept plain JSON from older CLI wrappers; these runs remain explicitly estimated.
        return Self(output: message ?? output, reportedUsage: usage)
    }
}
