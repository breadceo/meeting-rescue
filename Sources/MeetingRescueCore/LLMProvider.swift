import Foundation

public protocol LLMProvider: Sendable {
    var kind: LLMProviderKind { get }
    func analyze(_ request: AnalysisRequest) async throws -> AnalysisProviderResult
}

public enum LLMProviderError: Error, LocalizedError, Equatable {
    case missingCustomCommand
    case invalidOutput
    case processFailed(String, AnalysisRunTrace? = nil)
    case timedOut(AnalysisRunTrace? = nil)

    public var errorDescription: String? {
        switch self {
        case .missingCustomCommand:
            return "Custom LLM command가 비어 있습니다."
        case .invalidOutput:
            return "LLM provider output을 JSON schema 형태로 해석하지 못했습니다."
        case .processFailed(let message, _):
            return message
        case .timedOut:
            return "LLM provider 실행 시간이 초과되었습니다."
        }
    }

    public var runTrace: AnalysisRunTrace? {
        switch self {
        case .processFailed(_, let trace), .timedOut(let trace):
            return trace
        case .missingCustomCommand, .invalidOutput:
            return nil
        }
    }
}

private struct ProcessRunOutput: Sendable {
    var output: String
    var trace: AnalysisRunTrace
}

public struct CodexExecProvider: LLMProvider {
    public let kind: LLMProviderKind = .codexExec
    private let executableURL: URL
    private let schemaURL: URL
    private let patchSchemaURL: URL?
    private let timeoutSeconds: Int
    private let workingDirectoryURL: URL
    private let modelPreset: LLMModelPreset

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        schemaURL: URL,
        patchSchemaURL: URL? = nil,
        timeoutSeconds: Int,
        workingDirectoryURL: URL,
        modelPreset: LLMModelPreset = .economy
    ) {
        self.executableURL = executableURL
        self.schemaURL = schemaURL
        self.patchSchemaURL = patchSchemaURL
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectoryURL = workingDirectoryURL
        self.modelPreset = modelPreset
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AnalysisProviderResult {
        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)
        let processOutput = try await ProcessRunner.runWithTrace(
            executableURL: executableURL,
            arguments: Self.arguments(schemaURL: schemaURL(for: request), modelPreset: modelPreset),
            environment: Self.environment(for: modelPreset),
            standardInput: prompt,
            timeoutSeconds: timeoutSeconds,
            workingDirectoryURL: workingDirectoryURL
        )
        var runTrace = processOutput.trace
        let output = processOutput.output
        let snapshot = try decodeProviderOutput(from: output, request: request, provider: kind)
        runTrace.events.append(.instant("decode provider output", since: runTraceStart(runTrace), detail: request.outputMode.rawValue))
        let usage = LLMUsagePricing.usageSample(
            provider: kind,
            modelPreset: modelPreset,
            reason: request.reason,
            inputText: prompt,
            outputText: output
        )
        return AnalysisProviderResult(snapshot: snapshot, usage: usage, rawOutput: output, runTrace: runTrace)
    }

    private func schemaURL(for request: AnalysisRequest) -> URL {
        request.outputMode == .livePatch ? (patchSchemaURL ?? schemaURL) : schemaURL
    }

    static func arguments(schemaURL: URL, modelPreset: LLMModelPreset) -> [String] {
        var arguments = [
            "codex",
            "exec"
        ]
        if let modelName = modelPreset.codexModelName {
            arguments.append(contentsOf: ["--model", modelName])
        }
        arguments.append(contentsOf: [
            "--ignore-user-config",
            "--ignore-rules",
            "--disable",
            "hooks",
            "--disable",
            "plugins",
            "--disable",
            "memories",
            "--disable",
            "apps",
            "--disable",
            "browser_use",
            "--disable",
            "computer_use",
            "--disable",
            "multi_agent",
            "--disable",
            "tool_search",
            "--skip-git-repo-check",
            "--ephemeral",
            "--sandbox",
            "read-only",
            "--output-schema",
            schemaURL.path,
            "-"
        ])
        return arguments
    }

    public static func environment(for modelPreset: LLMModelPreset) -> [String: String] {
        [
            "MEETING_RESCUE_LLM_MODEL_PRESET": modelPreset.rawValue,
            "MEETING_RESCUE_LLM_MODEL": modelPreset.codexModelName ?? "",
            "PATH": codexSearchPath()
        ]
    }

    private static func codexSearchPath() -> String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fallbackPaths = [
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/.local/share/mise/shims",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/Applications/Codex.app/Contents/Resources",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        var seen = Set<String>()
        return (existingPath.split(separator: ":").map(String.init) + fallbackPaths)
            .filter { path in
                guard !path.isEmpty, !seen.contains(path) else {
                    return false
                }
                seen.insert(path)
                return true
            }
            .joined(separator: ":")
    }
}

public struct ClaudeCodeProvider: LLMProvider {
    public let kind: LLMProviderKind = .claudeCode
    private let executableURL: URL
    private let schemaURL: URL
    private let patchSchemaURL: URL?
    private let timeoutSeconds: Int
    private let workingDirectoryURL: URL
    private let modelPreset: LLMModelPreset

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        schemaURL: URL,
        patchSchemaURL: URL? = nil,
        timeoutSeconds: Int,
        workingDirectoryURL: URL,
        modelPreset: LLMModelPreset = .economy
    ) {
        self.executableURL = executableURL
        self.schemaURL = schemaURL
        self.patchSchemaURL = patchSchemaURL
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectoryURL = workingDirectoryURL
        self.modelPreset = modelPreset
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AnalysisProviderResult {
        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)
        let processOutput = try await ProcessRunner.runWithTrace(
            executableURL: executableURL,
            arguments: try Self.arguments(schemaURL: schemaURL(for: request), modelPreset: modelPreset),
            environment: Self.environment(for: modelPreset),
            standardInput: prompt,
            timeoutSeconds: timeoutSeconds,
            workingDirectoryURL: workingDirectoryURL
        )
        var runTrace = processOutput.trace
        let output = processOutput.output
        let structuredOutput = try Self.extractStructuredOutput(from: output)
        runTrace.events.append(.instant("extract structured output", since: runTraceStart(runTrace), detail: "\(structuredOutput.utf8.count) bytes"))
        let snapshot = try decodeProviderOutput(from: structuredOutput, request: request, provider: kind)
        runTrace.events.append(.instant("decode provider output", since: runTraceStart(runTrace), detail: request.outputMode.rawValue))
        let usage = LLMUsagePricing.usageSample(
            provider: kind,
            modelPreset: modelPreset,
            reason: request.reason,
            inputText: prompt,
            outputText: structuredOutput
        )
        return AnalysisProviderResult(snapshot: snapshot, usage: usage, rawOutput: output, runTrace: runTrace)
    }

    private func schemaURL(for request: AnalysisRequest) -> URL {
        request.outputMode == .livePatch ? (patchSchemaURL ?? schemaURL) : schemaURL
    }

    public static func arguments(schemaURL: URL, modelPreset: LLMModelPreset) throws -> [String] {
        let schema = try String(contentsOf: schemaURL, encoding: .utf8)
        var arguments = [
            "claude",
            "-p",
            "--output-format",
            "json",
            "--input-format",
            "text",
            "--no-session-persistence",
            "--tools",
            "",
            "--json-schema",
            schema
        ]
        if let modelName = modelPreset.claudeCodeModelName {
            arguments.append(contentsOf: ["--model", modelName])
        }
        if let effort = modelPreset.claudeCodeEffort {
            arguments.append(contentsOf: ["--effort", effort])
        }
        return arguments
    }

    public static func environment(for modelPreset: LLMModelPreset) -> [String: String] {
        var environment = CodexExecProvider.environment(for: modelPreset)
        environment["MEETING_RESCUE_LLM_PROVIDER"] = LLMProviderKind.claudeCode.rawValue
        environment["MEETING_RESCUE_LLM_MODEL"] = modelPreset.claudeCodeModelName ?? ""
        environment["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
        return environment
    }

    public static func extractStructuredOutput(from output: String) throws -> String {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return output
        }
        if let structuredOutput = object["structured_output"] {
            if let string = structuredOutput as? String {
                return string
            }
            guard JSONSerialization.isValidJSONObject(structuredOutput),
                  let structuredData = try? JSONSerialization.data(withJSONObject: structuredOutput),
                  let structuredString = String(data: structuredData, encoding: .utf8) else {
                throw LLMProviderError.invalidOutput
            }
            return structuredString
        }
        if let result = object["result"] as? String {
            return result
        }
        return output
    }
}

public struct CustomCommandProvider: LLMProvider {
    public let kind: LLMProviderKind = .customCommand
    private let command: String
    private let timeoutSeconds: Int
    private let workingDirectoryURL: URL
    private let modelPreset: LLMModelPreset

    public init(
        command: String,
        timeoutSeconds: Int,
        workingDirectoryURL: URL,
        modelPreset: LLMModelPreset = .economy
    ) {
        self.command = command
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectoryURL = workingDirectoryURL
        self.modelPreset = modelPreset
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AnalysisProviderResult {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingCustomCommand
        }
        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)
        let processOutput = try await ProcessRunner.runWithTrace(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", command],
            environment: CodexExecProvider.environment(for: modelPreset),
            standardInput: prompt,
            timeoutSeconds: timeoutSeconds,
            workingDirectoryURL: workingDirectoryURL
        )
        var runTrace = processOutput.trace
        let output = processOutput.output
        let snapshot = try decodeProviderOutput(from: output, request: request, provider: kind)
        runTrace.events.append(.instant("decode provider output", since: runTraceStart(runTrace), detail: request.outputMode.rawValue))
        let usage = LLMUsagePricing.usageSample(
            provider: kind,
            modelPreset: modelPreset,
            reason: request.reason,
            inputText: prompt,
            outputText: output
        )
        return AnalysisProviderResult(snapshot: snapshot, usage: usage, rawOutput: output, runTrace: runTrace)
    }
}

private func decodeSnapshot(from output: String, provider: LLMProviderKind) throws -> AnalysisSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = output.data(using: .utf8),
          var snapshot = try? decoder.decode(AnalysisSnapshot.self, from: data) else {
        throw LLMProviderError.invalidOutput
    }
    snapshot.provider = provider
    snapshot.generatedAt = Date()
    snapshot.decisionCandidates = snapshot.decisionCandidates.map { candidate in
        var candidate = candidate
        if candidate.id.isEmpty {
            candidate.id = CandidateIDGenerator.decisionID(text: candidate.text, evidenceTimestamp: candidate.evidenceTimestamp)
        }
        return candidate
    }
    snapshot.actionItemCandidates = snapshot.actionItemCandidates.map { candidate in
        var candidate = candidate
        if candidate.id.isEmpty {
            candidate.id = CandidateIDGenerator.actionItemID(task: candidate.task, evidenceTimestamp: candidate.evidenceTimestamp)
        }
        return candidate
    }
    return snapshot
}

private func decodeProviderOutput(
    from output: String,
    request: AnalysisRequest,
    provider: LLMProviderKind
) throws -> AnalysisSnapshot {
    switch request.outputMode {
    case .fullSnapshot:
        return try decodeSnapshot(from: output, provider: provider)
    case .livePatch:
        if let previousSnapshot = request.previousSnapshot,
           let patch = try? decodePatch(from: output) {
            return previousSnapshot.applyingPatch(patch, provider: provider)
        }
        return try decodeSnapshot(from: output, provider: provider)
    }
}

private func decodePatch(from output: String) throws -> AnalysisSnapshotPatch {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = output.data(using: .utf8),
          var patch = try? decoder.decode(AnalysisSnapshotPatch.self, from: data) else {
        throw LLMProviderError.invalidOutput
    }
    patch.decisionCandidateUpserts = patch.decisionCandidateUpserts.map { candidate in
        var candidate = candidate
        if candidate.id.isEmpty {
            candidate.id = CandidateIDGenerator.decisionID(text: candidate.text, evidenceTimestamp: candidate.evidenceTimestamp)
        }
        return candidate
    }
    patch.actionItemCandidateUpserts = patch.actionItemCandidateUpserts.map { candidate in
        var candidate = candidate
        if candidate.id.isEmpty {
            candidate.id = CandidateIDGenerator.actionItemID(task: candidate.task, evidenceTimestamp: candidate.evidenceTimestamp)
        }
        return candidate
    }
    return patch
}

private func runTraceStart(_ trace: AnalysisRunTrace) -> Date {
    Date(timeIntervalSince1970: Double(trace.startedAtUnixMilliseconds) / 1000)
}

private extension AnalysisRunTraceEvent {
    static func instant(_ name: String, since start: Date, detail: String? = nil) -> AnalysisRunTraceEvent {
        AnalysisRunTraceEvent(
            name: name,
            startedAtMilliseconds: max(0, Int((Date().timeIntervalSince(start) * 1000).rounded())),
            durationMilliseconds: 0,
            detail: detail
        )
    }
}

private enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        standardInput: String,
        timeoutSeconds: Int,
        workingDirectoryURL: URL
    ) async throws -> String {
        try await runWithTrace(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            standardInput: standardInput,
            timeoutSeconds: timeoutSeconds,
            workingDirectoryURL: workingDirectoryURL
        ).output
    }

    static func runWithTrace(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        standardInput: String,
        timeoutSeconds: Int,
        workingDirectoryURL: URL
    ) async throws -> ProcessRunOutput {
        let runner = Task.detached(priority: .utility) {
            let traceStart = Date()
            var events: [AnalysisRunTraceEvent] = []
            func elapsedMilliseconds() -> Int {
                max(0, Int((Date().timeIntervalSince(traceStart) * 1000).rounded()))
            }
            func appendEvent(_ name: String, startedAt: Int, detail: String? = nil) {
                events.append(AnalysisRunTraceEvent(
                    name: name,
                    startedAtMilliseconds: startedAt,
                    durationMilliseconds: max(0, elapsedMilliseconds() - startedAt),
                    detail: detail
                ))
            }
            func makeTrace(
                outputBytes: Int = 0,
                stderrBytes: Int = 0,
                exitCode: Int32? = nil,
                timedOut: Bool = false
            ) -> AnalysisRunTrace {
                AnalysisRunTrace(
                    providerExecutable: executableURL.path,
                    argumentsSummary: sanitizedArgumentsSummary(arguments),
                    workingDirectory: workingDirectoryURL.path,
                    inputBytes: Data(standardInput.utf8).count,
                    outputBytes: outputBytes,
                    stderrBytes: stderrBytes,
                    exitCode: exitCode,
                    timedOut: timedOut,
                    startedAtUnixMilliseconds: Int(traceStart.timeIntervalSince1970 * 1000),
                    events: events
                )
            }

            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectoryURL
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let spawnStartedAt = elapsedMilliseconds()
            try process.run()
            appendEvent("spawn process", startedAt: spawnStartedAt, detail: sanitizedArgumentsSummary(arguments))

            let stdinStartedAt = elapsedMilliseconds()
            let inputData = Data(standardInput.utf8)
            inputPipe.fileHandleForWriting.write(inputData)
            try inputPipe.fileHandleForWriting.close()
            appendEvent("write stdin", startedAt: stdinStartedAt, detail: "\(inputData.count) bytes")

            let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
            let waitStartedAt = elapsedMilliseconds()
            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    throw CancellationError()
                }
                if Date() >= deadline {
                    process.terminate()
                    appendEvent("wait for process", startedAt: waitStartedAt, detail: "timeout \(timeoutSeconds)s")
                    var trace = makeTrace(timedOut: true)
                    trace.events.append(.instant("terminate after timeout", since: traceStart))
                    throw LLMProviderError.timedOut(trace)
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            appendEvent("wait for process", startedAt: waitStartedAt, detail: "exit \(process.terminationStatus)")

            let stdoutStartedAt = elapsedMilliseconds()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            appendEvent("read stdout", startedAt: stdoutStartedAt, detail: "\(outputData.count) bytes")
            let stderrStartedAt = elapsedMilliseconds()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: errorData, encoding: .utf8) ?? ""
            appendEvent("read stderr", startedAt: stderrStartedAt, detail: "\(errorData.count) bytes")

            let trace = makeTrace(
                outputBytes: outputData.count,
                stderrBytes: errorData.count,
                exitCode: process.terminationStatus
            )
            guard process.terminationStatus == 0 else {
                throw LLMProviderError.processFailed(error.isEmpty ? output : error, trace)
            }
            return ProcessRunOutput(
                output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                trace: trace
            )
        }

        return try await withTaskCancellationHandler {
            try await runner.value
        } onCancel: {
            runner.cancel()
        }
    }

    private static func sanitizedArgumentsSummary(_ arguments: [String]) -> String {
        var values: [String] = []
        var skipNextValueForSchema = false
        for argument in arguments {
            if skipNextValueForSchema {
                values.append("<schema-json>")
                skipNextValueForSchema = false
                continue
            }
            if argument == "--json-schema" {
                values.append(argument)
                skipNextValueForSchema = true
                continue
            }
            if argument.count > 180 {
                values.append(String(argument.prefix(177)) + "...")
            } else {
                values.append(argument)
            }
        }
        return values.joined(separator: " ")
    }
}
