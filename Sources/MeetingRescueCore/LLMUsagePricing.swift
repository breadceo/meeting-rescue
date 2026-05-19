import Foundation

public struct LLMModelPrice: Equatable, Sendable {
    public var providerLabel: String
    public var modelName: String
    public var inputPerMillionUSD: Double
    public var outputPerMillionUSD: Double
    public var sourceLabel: String

    public init(
        providerLabel: String,
        modelName: String,
        inputPerMillionUSD: Double,
        outputPerMillionUSD: Double,
        sourceLabel: String
    ) {
        self.providerLabel = providerLabel
        self.modelName = modelName
        self.inputPerMillionUSD = inputPerMillionUSD
        self.outputPerMillionUSD = outputPerMillionUSD
        self.sourceLabel = sourceLabel
    }
}

public enum LLMUsagePricing {
    public static func codexPrice(for modelPreset: LLMModelPreset) -> LLMModelPrice? {
        switch modelPreset {
        case .automatic:
            return nil
        case .economy:
            return LLMModelPrice(
                providerLabel: "Codex / OpenAI",
                modelName: "gpt-5.4-mini",
                inputPerMillionUSD: 0.375,
                outputPerMillionUSD: 2.25,
                sourceLabel: "OpenAI Pricing, standard short context"
            )
        case .balanced:
            return LLMModelPrice(
                providerLabel: "Codex / OpenAI",
                modelName: "gpt-5.4",
                inputPerMillionUSD: 1.25,
                outputPerMillionUSD: 7.50,
                sourceLabel: "OpenAI Pricing, standard short context"
            )
        case .frontier:
            return LLMModelPrice(
                providerLabel: "Codex / OpenAI",
                modelName: "gpt-5.5",
                inputPerMillionUSD: 2.50,
                outputPerMillionUSD: 15.00,
                sourceLabel: "OpenAI Pricing, standard short context"
            )
        }
    }

    public static func claudeCodePrice(for modelPreset: LLMModelPreset) -> LLMModelPrice? {
        switch modelPreset {
        case .automatic:
            return nil
        case .economy, .balanced:
            return LLMModelPrice(
                providerLabel: "Claude Code / Anthropic",
                modelName: "sonnet",
                inputPerMillionUSD: 3.00,
                outputPerMillionUSD: 15.00,
                sourceLabel: "Anthropic Pricing reference; subscription usage may use plan credits"
            )
        case .frontier:
            return LLMModelPrice(
                providerLabel: "Claude Code / Anthropic",
                modelName: "opus",
                inputPerMillionUSD: 5.00,
                outputPerMillionUSD: 25.00,
                sourceLabel: "Anthropic Pricing reference; subscription usage may use plan credits"
            )
        }
    }

    public static var referencePrices: [LLMModelPrice] {
        [
            LLMModelPrice(providerLabel: "Codex / OpenAI", modelName: "gpt-5.4-mini", inputPerMillionUSD: 0.375, outputPerMillionUSD: 2.25, sourceLabel: "OpenAI Pricing, standard short context"),
            LLMModelPrice(providerLabel: "Codex / OpenAI", modelName: "gpt-5.4", inputPerMillionUSD: 1.25, outputPerMillionUSD: 7.50, sourceLabel: "OpenAI Pricing, standard short context"),
            LLMModelPrice(providerLabel: "Codex / OpenAI", modelName: "gpt-5.5", inputPerMillionUSD: 2.50, outputPerMillionUSD: 15.00, sourceLabel: "OpenAI Pricing, standard short context"),
            LLMModelPrice(providerLabel: "Claude Code / Anthropic", modelName: "Claude Haiku 4.5", inputPerMillionUSD: 1.00, outputPerMillionUSD: 5.00, sourceLabel: "Anthropic Pricing"),
            LLMModelPrice(providerLabel: "Claude Code / Anthropic", modelName: "Claude Sonnet 4.6", inputPerMillionUSD: 3.00, outputPerMillionUSD: 15.00, sourceLabel: "Anthropic Pricing"),
            LLMModelPrice(providerLabel: "Claude Code / Anthropic", modelName: "Claude Opus 4.7", inputPerMillionUSD: 5.00, outputPerMillionUSD: 25.00, sourceLabel: "Anthropic Pricing"),
            LLMModelPrice(providerLabel: "Gemini / Google", modelName: "gemini-3.1-flash-lite", inputPerMillionUSD: 0.25, outputPerMillionUSD: 1.50, sourceLabel: "Gemini Developer API Pricing"),
            LLMModelPrice(providerLabel: "Gemini / Google", modelName: "gemini-3-flash-preview", inputPerMillionUSD: 0.50, outputPerMillionUSD: 3.00, sourceLabel: "Gemini Developer API Pricing"),
            LLMModelPrice(providerLabel: "Gemini / Google", modelName: "gemini-3.1-pro", inputPerMillionUSD: 2.00, outputPerMillionUSD: 12.00, sourceLabel: "Gemini Developer API Pricing")
        ]
    }

    public static func usageSample(
        provider: LLMProviderKind,
        modelPreset: LLMModelPreset,
        reason: String,
        inputText: String,
        outputText: String
    ) -> LLMUsageSample {
        let inputTokens = TokenEstimator.estimateTokens(in: inputText)
        let outputTokens = TokenEstimator.estimateTokens(in: outputText)
        let price: LLMModelPrice? = switch provider {
        case .codexExec:
            codexPrice(for: modelPreset)
        case .claudeCode:
            claudeCodePrice(for: modelPreset)
        case .customCommand:
            nil
        }
        let inputPrice = price?.inputPerMillionUSD
        let outputPrice = price?.outputPerMillionUSD
        let cost = estimatedCost(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            inputPricePerMillionUSD: inputPrice,
            outputPricePerMillionUSD: outputPrice
        )

        return LLMUsageSample(
            provider: provider,
            modelPreset: modelPreset,
            modelName: price?.modelName ?? modelPreset.codexModelName ?? "provider default",
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            inputPricePerMillionUSD: inputPrice,
            outputPricePerMillionUSD: outputPrice,
            estimatedCostUSD: cost,
            reason: reason
        )
    }

    public static func estimatedCost(
        inputTokens: Int,
        outputTokens: Int,
        inputPricePerMillionUSD: Double?,
        outputPricePerMillionUSD: Double?
    ) -> Double? {
        guard let inputPricePerMillionUSD, let outputPricePerMillionUSD else {
            return nil
        }
        return (Double(inputTokens) / 1_000_000 * inputPricePerMillionUSD)
            + (Double(outputTokens) / 1_000_000 * outputPricePerMillionUSD)
    }
}

public enum TokenEstimator {
    public static func estimateTokens(in text: String) -> Int {
        let scalarCount = text.unicodeScalars.count
        guard scalarCount > 0 else {
            return 0
        }
        return max(1, Int(ceil(Double(scalarCount) / 3.2)))
    }
}
