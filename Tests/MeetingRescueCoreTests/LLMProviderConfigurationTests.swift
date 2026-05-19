import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("LLM provider configuration")
struct LLMProviderConfigurationTests {
    @Test("기존 settings JSON은 model preset이 없어도 economy 기본값으로 decode된다")
    func decodesLegacySettingsWithoutModelPreset() throws {
        let json = """
        {
          "selectedProvider": "customCommand",
          "analysisCadenceSeconds": 90,
          "providerTimeoutSeconds": 5,
          "customProviderCommand": "run-llm"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(settings.selectedProvider == .customCommand)
        #expect(settings.modelPreset == .economy)
        #expect(settings.automaticAnalysisEnabled)
        #expect(settings.analysisTriggerPreset == .balanced)
        #expect(settings.analysisCadenceSeconds == 90)
        #expect(settings.providerTimeoutSeconds == 10)
        #expect(settings.customProviderCommand == "run-llm")
    }

    @Test("automatic analysis 설정을 저장하고 불러온다")
    func encodesAutomaticAnalysisToggle() throws {
        let settings = AppSettings(automaticAnalysisEnabled: false)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(!decoded.automaticAnalysisEnabled)
    }

    @Test("analysis trigger preset 기본값과 설정값을 저장한다")
    func encodesAnalysisTriggerPreset() throws {
        #expect(AppSettings().analysisTriggerPreset == .balanced)

        let settings = AppSettings(analysisTriggerPreset: .economy)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.analysisTriggerPreset == .economy)
    }

    @Test("analysis trigger preset은 샘플 검토 기반 threshold를 제공한다")
    func analysisTriggerPresetConfigurations() {
        let responsive = AnalysisTriggerPreset.responsive.configuration
        #expect(responsive.minBatchWaitSeconds == 120)
        #expect(responsive.maxBatchWaitSeconds == 240)
        #expect(responsive.minNewDialogueLines == 20)
        #expect(responsive.minNewTranscriptCharacters == 1_500)

        let balanced = AnalysisTriggerPreset.balanced.configuration
        #expect(balanced.minBatchWaitSeconds == 180)
        #expect(balanced.maxBatchWaitSeconds == 300)
        #expect(balanced.minNewDialogueLines == 24)
        #expect(balanced.minNewTranscriptCharacters == 1_800)

        let economy = AnalysisTriggerPreset.economy.configuration
        #expect(economy.minBatchWaitSeconds == 300)
        #expect(economy.maxBatchWaitSeconds == 300)
        #expect(economy.minNewDialogueLines == 30)
        #expect(economy.minNewTranscriptCharacters == 2_200)
    }

    @Test("timeout 설정은 10초에서 300초 사이로 보정된다")
    func timeoutSettingsAreClamped() {
        #expect(AppSettings(providerTimeoutSeconds: 5).providerTimeoutSeconds == 10)
        #expect(AppSettings(providerTimeoutSeconds: 360).providerTimeoutSeconds == 300)
    }

    @Test("manual과 final analysis는 one-shot timeout을 사용하고 live는 최소 10초를 보장한다")
    func analysisTimeoutPolicyByReason() {
        #expect(AnalysisTimeoutPolicy.timeoutSeconds(configuredTimeoutSeconds: 10, reason: "manual") == 180)
        #expect(AnalysisTimeoutPolicy.timeoutSeconds(configuredTimeoutSeconds: 10, reason: "manual-continue") == 180)
        #expect(AnalysisTimeoutPolicy.timeoutSeconds(configuredTimeoutSeconds: 60, reason: "final") == 180)
        #expect(AnalysisTimeoutPolicy.timeoutSeconds(configuredTimeoutSeconds: 60, reason: "final-continue") == 180)
        #expect(AnalysisTimeoutPolicy.timeoutSeconds(configuredTimeoutSeconds: 6, reason: "automatic") == 10)
        #expect(AnalysisTimeoutPolicy.timeoutSeconds(configuredTimeoutSeconds: 30, reason: "automatic") == 30)
    }

    @Test("Codex preset은 --model argument로 변환된다")
    func codexArgumentsIncludePresetModel() {
        let schemaURL = URL(fileURLWithPath: "/tmp/schema.json")
        let arguments = CodexExecProvider.arguments(schemaURL: schemaURL, modelPreset: .economy)

        #expect(arguments.contains("--model"))
        #expect(arguments.contains("gpt-5.4-mini"))
        #expect(arguments.contains("--output-schema"))
        #expect(arguments.contains(schemaURL.path))
        #expect(arguments.contains("--ignore-user-config"))
        #expect(arguments.contains("--ignore-rules"))
        #expect(disabledFeatures(in: arguments).isSuperset(of: [
            "hooks",
            "plugins",
            "memories",
            "apps",
            "browser_use",
            "computer_use",
            "multi_agent",
            "tool_search"
        ]))
    }

    @Test("automatic preset은 Codex CLI 기본 model을 유지한다")
    func automaticPresetDoesNotPassModelArgument() {
        let schemaURL = URL(fileURLWithPath: "/tmp/schema.json")
        let arguments = CodexExecProvider.arguments(schemaURL: schemaURL, modelPreset: .automatic)

        #expect(!arguments.contains("--model"))
    }

    @Test("Claude Code provider는 print mode와 JSON schema를 사용한다")
    func claudeCodeArgumentsUsePrintModeAndSchema() throws {
        let schemaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-rescue-claude-schema-\(UUID().uuidString).json")
        try #"{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]}"#
            .write(to: schemaURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: schemaURL) }

        let arguments = try ClaudeCodeProvider.arguments(schemaURL: schemaURL, modelPreset: .economy)

        #expect(arguments.starts(with: ["claude", "-p"]))
        #expect(arguments.contains("--output-format"))
        #expect(arguments.contains("json"))
        #expect(arguments.contains("--json-schema"))
        #expect(arguments.contains("--no-session-persistence"))
        #expect(arguments.contains("--model"))
        #expect(arguments.contains("sonnet"))
        #expect(arguments.contains("--effort"))
        #expect(arguments.contains("low"))
    }

    @Test("Claude Code provider는 structured_output wrapper를 해제한다")
    func claudeCodeExtractsStructuredOutput() throws {
        let wrapped = """
        {"type":"result","result":"ignored","structured_output":{"ok":true,"items":["a"]},"total_cost_usd":0.001}
        """

        let output = try ClaudeCodeProvider.extractStructuredOutput(from: wrapped)

        #expect(output.contains(#""ok":true"#))
        #expect(output.contains(#""items":["a"]"#))
    }

    @Test("Custom provider가 사용할 수 있도록 preset environment를 만든다")
    func presetEnvironment() {
        let environment = CodexExecProvider.environment(for: .frontier)

        #expect(environment["MEETING_RESCUE_LLM_MODEL_PRESET"] == "frontier")
        #expect(environment["MEETING_RESCUE_LLM_MODEL"] == "gpt-5.5")
    }

    @Test("Codex provider PATH는 GUI app 환경에서도 CLI 후보 경로를 포함한다")
    func codexEnvironmentIncludesFallbackSearchPath() throws {
        let environment = CodexExecProvider.environment(for: .economy)
        let path = try #require(environment["PATH"])

        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/usr/local/bin"))
        #expect(path.contains("/Applications/Codex.app/Contents/Resources"))
    }

    @Test("Claude Code provider PATH는 GUI app 환경에서도 CLI 후보 경로를 포함한다")
    func claudeCodeEnvironmentIncludesFallbackSearchPath() throws {
        let environment = ClaudeCodeProvider.environment(for: .frontier)
        let path = try #require(environment["PATH"])

        #expect(environment["MEETING_RESCUE_LLM_PROVIDER"] == "claudeCode")
        #expect(environment["MEETING_RESCUE_LLM_MODEL"] == "opus")
        #expect(environment["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] == "1")
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/usr/local/bin"))
    }

    private func disabledFeatures(in arguments: [String]) -> Set<String> {
        var features = Set<String>()
        for index in arguments.indices where arguments[index] == "--disable" {
            let nextIndex = arguments.index(after: index)
            guard arguments.indices.contains(nextIndex) else {
                continue
            }
            features.insert(arguments[nextIndex])
        }
        return features
    }
}
