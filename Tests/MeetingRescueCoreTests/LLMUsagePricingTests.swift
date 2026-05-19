import Testing
@testable import MeetingRescueCore

@Suite("LLM usage pricing")
struct LLMUsagePricingTests {
    @Test("Codex usage sample은 선택 preset 가격으로 비용을 추정한다")
    func estimatesCodexUsageCost() {
        let sample = LLMUsageSample(
            provider: .codexExec,
            modelPreset: .economy,
            modelName: "gpt-5.4-mini",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            inputPricePerMillionUSD: 0.375,
            outputPricePerMillionUSD: 2.25,
            estimatedCostUSD: LLMUsagePricing.estimatedCost(
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                inputPricePerMillionUSD: 0.375,
                outputPricePerMillionUSD: 2.25
            )
        )

        #expect(sample.estimatedCostUSD == 2.625)
    }

    @Test("Claude Code usage sample은 Anthropic 참고 가격으로 비용을 추정한다")
    func estimatesClaudeCodeUsageCost() {
        let sample = LLMUsagePricing.usageSample(
            provider: .claudeCode,
            modelPreset: .balanced,
            reason: "automatic",
            inputText: String(repeating: "a", count: 3_200),
            outputText: String(repeating: "b", count: 3_200)
        )

        #expect(sample.modelName == "sonnet")
        #expect(sample.inputPricePerMillionUSD == 3.00)
        #expect(sample.outputPricePerMillionUSD == 15.00)
        #expect(sample.estimatedCostUSD != nil)
    }

    @Test("analysis state는 usage를 누적한다")
    func accumulatesUsage() {
        var state = MeetingAnalysisState()
        state.appendUsage(
            LLMUsageSample(
                provider: .codexExec,
                modelPreset: .economy,
                modelName: "gpt-5.4-mini",
                inputTokens: 100,
                outputTokens: 50,
                inputPricePerMillionUSD: 0.375,
                outputPricePerMillionUSD: 2.25,
                estimatedCostUSD: 0.0003
            )
        )

        #expect(state.usageSummary.totalInputTokens == 100)
        #expect(state.usageSummary.totalOutputTokens == 50)
        #expect(state.usageSummary.totalEstimatedCostUSD == 0.0003)
    }
}
