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

struct ProcessRunOutput: Sendable {
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

public struct CodexAppServerProvider: LLMProvider {
    public let kind: LLMProviderKind = .codexExec
    private let executableURL: URL
    private let schemaURL: URL
    private let patchSchemaURL: URL?
    private let timeoutSeconds: Int
    private let workingDirectoryURL: URL
    private let modelPreset: LLMModelPreset
    private let diagnosticsEnabled: Bool
    private let fallbackProvider: CodexExecProvider?
    private let service: CodexAppServerService

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        schemaURL: URL,
        patchSchemaURL: URL? = nil,
        timeoutSeconds: Int,
        workingDirectoryURL: URL,
        modelPreset: LLMModelPreset = .economy,
        diagnosticsEnabled: Bool = false,
        fallbackProvider: CodexExecProvider? = nil
    ) {
        self.init(
            executableURL: executableURL,
            schemaURL: schemaURL,
            patchSchemaURL: patchSchemaURL,
            timeoutSeconds: timeoutSeconds,
            workingDirectoryURL: workingDirectoryURL,
            modelPreset: modelPreset,
            diagnosticsEnabled: diagnosticsEnabled,
            fallbackProvider: fallbackProvider,
            service: .shared
        )
    }

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        schemaURL: URL,
        patchSchemaURL: URL? = nil,
        timeoutSeconds: Int,
        workingDirectoryURL: URL,
        modelPreset: LLMModelPreset = .economy,
        diagnosticsEnabled: Bool = false,
        fallbackProvider: CodexExecProvider? = nil,
        service: CodexAppServerService
    ) {
        self.executableURL = executableURL
        self.schemaURL = schemaURL
        self.patchSchemaURL = patchSchemaURL
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectoryURL = workingDirectoryURL
        self.modelPreset = modelPreset
        self.diagnosticsEnabled = diagnosticsEnabled
        self.fallbackProvider = fallbackProvider
        self.service = service
    }

    public func analyze(_ request: AnalysisRequest) async throws -> AnalysisProviderResult {
        do {
            return try await analyzeWithAppServer(request)
        } catch let error as LLMProviderError {
            guard let fallbackProvider else {
                throw error
            }
            var fallbackResult = try await fallbackProvider.analyze(request)
            if var trace = fallbackResult.runTrace {
                trace.events.insert(.instant("app-server fallback to cli exec", since: runTraceStart(trace), detail: error.localizedDescription), at: 0)
                fallbackResult.runTrace = trace
            }
            return fallbackResult
        } catch {
            guard let fallbackProvider else {
                throw error
            }
            var fallbackResult = try await fallbackProvider.analyze(request)
            if var trace = fallbackResult.runTrace {
                trace.events.insert(.instant("app-server fallback to cli exec", since: runTraceStart(trace), detail: error.localizedDescription), at: 0)
                fallbackResult.runTrace = trace
            }
            return fallbackResult
        }
    }

    private func analyzeWithAppServer(_ request: AnalysisRequest) async throws -> AnalysisProviderResult {
        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)
        let output = try await runAppServerTurn(
            prompt: prompt,
            schemaURL: schemaURL(for: request),
            meetingID: request.meetingID
        )
        var runTrace = output.trace
        let snapshot = try decodeProviderOutput(from: output.output, request: request, provider: kind)
        runTrace.events.append(.instant("decode provider output", since: runTraceStart(runTrace), detail: "appServer \(request.outputMode.rawValue)"))
        let usage = LLMUsagePricing.usageSample(
            provider: kind,
            modelPreset: modelPreset,
            reason: request.reason,
            inputText: prompt,
            outputText: output.output
        )
        return AnalysisProviderResult(snapshot: snapshot, usage: usage, rawOutput: output.output, runTrace: runTrace)
    }

    private func schemaURL(for request: AnalysisRequest) -> URL {
        request.outputMode == .livePatch ? (patchSchemaURL ?? schemaURL) : schemaURL
    }

    private func runAppServerTurn(prompt: String, schemaURL: URL, meetingID: String) async throws -> ProcessRunOutput {
        let schemaData = try Data(contentsOf: schemaURL)
        return try await service.runTurn(
            prompt: prompt,
            schemaData: schemaData,
            meetingID: meetingID,
            executableURL: executableURL,
            workingDirectoryURL: workingDirectoryURL,
            modelPreset: modelPreset,
            diagnosticsEnabled: diagnosticsEnabled,
            timeoutSeconds: timeoutSeconds
        )
    }

    static func arguments(modelPreset: LLMModelPreset) -> [String] {
        [
            "codex",
            "app-server",
            "--listen",
            "stdio://",
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
            "tool_search"
        ]
    }

    static func sanitizedArgumentsSummary(_ arguments: [String]) -> String {
        arguments.map { argument in
            argument.count > 180 ? String(argument.prefix(177)) + "..." : argument
        }.joined(separator: " ")
    }
}

struct CodexAppServerRuntimeConfiguration: Sendable, Equatable {
    var executableURL: URL
    var arguments: [String]
    var environment: [String: String]
    var workingDirectoryURL: URL
    var modelPreset: LLMModelPreset
    var diagnosticsEnabled: Bool

    var reuseKey: String {
        [
            executableURL.path,
            workingDirectoryURL.path,
            modelPreset.rawValue,
            diagnosticsEnabled ? "diagnostics-on" : "diagnostics-off",
            arguments.joined(separator: "\u{1f}")
        ].joined(separator: "\u{1e}")
    }
}

struct CodexAppServerTurnResult: Sendable, Equatable {
    var output: String
    var turnStartLatencyMilliseconds: Int
    var firstDeltaLatencyMilliseconds: Int?
    var finalAnswerLatencyMilliseconds: Int
    var observedEvents: [AnalysisRunTraceEvent]
    var outputBytes: Int
    var stderrBytes: Int
    var exitCode: Int32?
}

protocol CodexAppServerRuntime: Sendable {
    var configuration: CodexAppServerRuntimeConfiguration { get async }
    func outputBytesRead() async -> Int
    func initialize(deadline: Date) async throws
    func startThread(modelName: String?, diagnosticsEnabled: Bool, deadline: Date) async throws -> String
    func startTurn(
        threadID: String,
        prompt: String,
        schemaData: Data,
        modelName: String?,
        deadline: Date
    ) async throws -> CodexAppServerTurnResult
    nonisolated func terminate()
}

actor CodexAppServerService {
    static let shared = CodexAppServerService()

    typealias RuntimeFactory = @Sendable (CodexAppServerRuntimeConfiguration) async throws -> any CodexAppServerRuntime

    private var runtime: (any CodexAppServerRuntime)?
    private var runtimeReuseKey: String?
    private var initializedRuntimeKey: String?
    private var threadsByMeetingKey: [String: String] = [:]
    private let runtimeFactory: RuntimeFactory

    init(runtimeFactory: @escaping RuntimeFactory = { configuration in
        try await CodexAppServerProcessRuntime(configuration: configuration)
    }) {
        self.runtimeFactory = runtimeFactory
    }

    func runTurn(
        prompt: String,
        schemaData: Data,
        meetingID: String,
        executableURL: URL,
        workingDirectoryURL: URL,
        modelPreset: LLMModelPreset,
        diagnosticsEnabled: Bool = false,
        timeoutSeconds: Int
    ) async throws -> ProcessRunOutput {
        let traceStart = Date()
        let deadline = Date().addingTimeInterval(TimeInterval(max(1, timeoutSeconds)))
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
                argumentsSummary: CodexAppServerProvider.sanitizedArgumentsSummary(CodexAppServerProvider.arguments(modelPreset: modelPreset)),
                workingDirectory: workingDirectoryURL.path,
                inputBytes: Data(prompt.utf8).count,
                outputBytes: outputBytes,
                stderrBytes: stderrBytes,
                exitCode: exitCode,
                timedOut: timedOut,
                startedAtUnixMilliseconds: Int(traceStart.timeIntervalSince1970 * 1000),
                events: events
            )
        }
        func remainingTimeoutSeconds() -> Int {
            max(1, Int(ceil(deadline.timeIntervalSinceNow)))
        }

        let configuration = CodexAppServerRuntimeConfiguration(
            executableURL: executableURL,
            arguments: CodexAppServerProvider.arguments(modelPreset: modelPreset),
            environment: ProcessInfo.processInfo.environment.merging(CodexExecProvider.environment(for: modelPreset)) { _, new in new },
            workingDirectoryURL: workingDirectoryURL,
            modelPreset: modelPreset,
            diagnosticsEnabled: diagnosticsEnabled
        )
        var outputBytesBefore = 0

        do {
            let processStartedAt = elapsedMilliseconds()
            let runtime: any CodexAppServerRuntime
            if let existingRuntime = self.runtime, runtimeReuseKey == configuration.reuseKey {
                runtime = existingRuntime
                appendEvent("app-server process", startedAt: processStartedAt, detail: "reused")
            } else {
                resetRuntime()
                let newRuntime = try await runtimeFactory(configuration)
                runtime = newRuntime
                self.runtime = newRuntime
                runtimeReuseKey = configuration.reuseKey
                appendEvent("app-server process", startedAt: processStartedAt, detail: "new")
            }
            outputBytesBefore = await runtime.outputBytesRead()

            let initializeStartedAt = elapsedMilliseconds()
            if initializedRuntimeKey == configuration.reuseKey {
                appendEvent("initialize app-server", startedAt: initializeStartedAt, detail: "reused")
            } else {
                try await withTimeout(seconds: remainingTimeoutSeconds(), runtime: runtime) {
                    try await runtime.initialize(deadline: deadline)
                }
                initializedRuntimeKey = configuration.reuseKey
                appendEvent("initialize app-server", startedAt: initializeStartedAt, detail: "new")
            }

            let threadKey = "\(configuration.reuseKey)\u{1e}\(meetingID)"
            let threadStartedAt = elapsedMilliseconds()
            let threadID: String
            if let existingThreadID = threadsByMeetingKey[threadKey] {
                threadID = existingThreadID
                appendEvent("thread/start", startedAt: threadStartedAt, detail: "reused \(existingThreadID)")
            } else {
                threadID = try await withTimeout(seconds: remainingTimeoutSeconds(), runtime: runtime) {
                    try await runtime.startThread(
                        modelName: modelPreset.codexModelName,
                        diagnosticsEnabled: diagnosticsEnabled,
                        deadline: deadline
                    )
                }
                threadsByMeetingKey[threadKey] = threadID
                appendEvent("thread/start", startedAt: threadStartedAt, detail: "new \(threadID)")
            }

            let turnStartedAt = elapsedMilliseconds()
            let result = try await withTimeout(seconds: remainingTimeoutSeconds(), runtime: runtime) {
                try await runtime.startTurn(
                    threadID: threadID,
                    prompt: prompt,
                    schemaData: schemaData,
                    modelName: modelPreset.codexModelName,
                    deadline: deadline
                )
            }
            events.append(AnalysisRunTraceEvent(
                name: "turn/start",
                startedAtMilliseconds: turnStartedAt,
                durationMilliseconds: result.turnStartLatencyMilliseconds,
                detail: nil
            ))
            let waitStartedAt = turnStartedAt + result.turnStartLatencyMilliseconds
            if let firstDeltaLatency = result.firstDeltaLatencyMilliseconds {
                events.append(AnalysisRunTraceEvent(
                    name: "first delta latency",
                    startedAtMilliseconds: waitStartedAt,
                    durationMilliseconds: firstDeltaLatency,
                    detail: nil
                ))
            }
            events.append(contentsOf: result.observedEvents.map { event in
                AnalysisRunTraceEvent(
                    name: event.name,
                    startedAtMilliseconds: waitStartedAt + event.startedAtMilliseconds,
                    durationMilliseconds: event.durationMilliseconds,
                    detail: event.detail
                )
            })
            events.append(AnalysisRunTraceEvent(
                name: "final answer latency",
                startedAtMilliseconds: waitStartedAt,
                durationMilliseconds: result.finalAnswerLatencyMilliseconds,
                detail: "\(Data(result.output.utf8).count) bytes"
            ))
            events.append(AnalysisRunTraceEvent(
                name: "total provider latency",
                startedAtMilliseconds: 0,
                durationMilliseconds: elapsedMilliseconds(),
                detail: nil
            ))
            return ProcessRunOutput(
                output: result.output,
                trace: makeTrace(
                    outputBytes: max(0, result.outputBytes - outputBytesBefore),
                    stderrBytes: result.stderrBytes,
                    exitCode: result.exitCode
                )
            )
        } catch let error as LLMProviderError {
            resetRuntime()
            if case .timedOut = error {
                appendEvent("app-server reset", startedAt: elapsedMilliseconds(), detail: "timeout")
                throw LLMProviderError.timedOut(makeTrace(outputBytes: outputBytesBefore, timedOut: true))
            }
            appendEvent("app-server reset", startedAt: elapsedMilliseconds(), detail: error.localizedDescription)
            throw LLMProviderError.processFailed(error.localizedDescription, makeTrace(outputBytes: outputBytesBefore))
        } catch {
            resetRuntime()
            appendEvent("app-server reset", startedAt: elapsedMilliseconds(), detail: error.localizedDescription)
            throw LLMProviderError.processFailed(error.localizedDescription, makeTrace(outputBytes: outputBytesBefore))
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: Int,
        runtime: any CodexAppServerRuntime,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await operation()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)
                    throw LLMProviderError.timedOut(nil)
                }
                do {
                    guard let result = try await group.next() else {
                        throw LLMProviderError.invalidOutput
                    }
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    runtime.terminate()
                    throw error
                }
            }
        } onCancel: {
            runtime.terminate()
        }
    }

    private func resetRuntime() {
        runtime?.terminate()
        runtime = nil
        runtimeReuseKey = nil
        initializedRuntimeKey = nil
        threadsByMeetingKey.removeAll()
    }
}

private actor CodexAppServerProcessRuntime: CodexAppServerRuntime {
    let configuration: CodexAppServerRuntimeConfiguration
    private let processBox = ProcessBox()
    private let writer: FileHandle
    private let errorPipe: Pipe
    private let lineBuffer: CodexAppServerLineBuffer
    private var nextRequestID = 1
    private var outputBytes = 0

    init(configuration: CodexAppServerRuntimeConfiguration) async throws {
        self.configuration = configuration
        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.workingDirectoryURL
        process.environment = configuration.environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        self.writer = inputPipe.fileHandleForWriting
        self.errorPipe = errorPipe
        let lineBuffer = CodexAppServerLineBuffer()
        self.lineBuffer = lineBuffer
        let outputReader = outputPipe.fileHandleForReading
        Task.detached(priority: .utility) {
            do {
                for try await line in outputReader.bytes.lines {
                    await lineBuffer.append(line)
                }
            } catch {
                // EOF and cancellation are both represented as a finished buffer for callers.
            }
            await lineBuffer.finish()
        }
        processBox.set(process)
        try process.run()
    }

    func outputBytesRead() -> Int {
        outputBytes
    }

    func initialize(deadline: Date) async throws {
        let id = nextID()
        try writeRequest(id: id, method: "initialize", params: [
            "clientInfo": [
                "name": "meeting-rescue",
                "version": "0.0.0"
            ],
            "capabilities": [
                "experimentalApi": true,
                "requestAttestation": false,
                "optOutNotificationMethods": [
                    "mcpServer/startupStatus/updated"
                ]
            ]
        ])
        _ = try await waitForResponse(id: id, deadline: deadline)
    }

    func startThread(modelName: String?, diagnosticsEnabled: Bool, deadline: Date) async throws -> String {
        let id = nextID()
        var params: [String: Any] = [
            "cwd": configuration.workingDirectoryURL.path,
            "approvalPolicy": "never",
            "sandbox": "read-only",
            "ephemeral": true,
            "experimentalRawEvents": diagnosticsEnabled,
            "persistExtendedHistory": false,
            "dynamicTools": [],
            "environments": [],
            "baseInstructions": "Return only the JSON object requested by the user. Do not run tools."
        ]
        if let modelName {
            params["model"] = modelName
        }
        try writeRequest(id: id, method: "thread/start", params: params)
        let response = try await waitForResponse(id: id, deadline: deadline)
        guard let result = response["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any],
              let threadID = thread["id"] as? String else {
            throw LLMProviderError.invalidOutput
        }
        return threadID
    }

    func startTurn(
        threadID: String,
        prompt: String,
        schemaData: Data,
        modelName: String?,
        deadline: Date
    ) async throws -> CodexAppServerTurnResult {
        guard let outputSchema = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            throw LLMProviderError.invalidOutput
        }

        let id = nextID()
        var params: [String: Any] = [
            "threadId": threadID,
            "input": [[
                "type": "text",
                "text": prompt,
                "text_elements": []
            ]],
            "approvalPolicy": "never",
            "sandboxPolicy": [
                "type": "readOnly",
                "networkAccess": false
            ],
            "outputSchema": outputSchema,
            "environments": []
        ]
        if let modelName {
            params["model"] = modelName
        }

        let turnStart = Date()
        try writeRequest(id: id, method: "turn/start", params: params)
        _ = try await waitForResponse(id: id, deadline: deadline)
        let waitStart = Date()
        var finalOutput = ""
        var firstDeltaLatencyMilliseconds: Int?
        var observedMethods: [String: (firstSeenMilliseconds: Int, count: Int, details: Set<String>)] = [:]
        var observedMethodOrder: [String] = []

        func elapsedSinceWaitStart() -> Int {
            max(0, Int((Date().timeIntervalSince(waitStart) * 1000).rounded()))
        }

        func observedDetail(for object: [String: Any], method: String) -> String? {
            guard method.hasPrefix("item/") || method == "rawResponseItem/completed",
                  let params = object["params"] as? [String: Any],
                  let item = params["item"] as? [String: Any] else {
                return nil
            }
            var components: [String] = []
            if let type = item["type"] as? String, !type.isEmpty {
                components.append(type)
            }
            if let phase = item["phase"] as? String, !phase.isEmpty {
                components.append(phase)
            }
            guard !components.isEmpty else {
                return nil
            }
            return components.joined(separator: "/")
        }

        func recordObservedMethod(_ method: String, detail: String?) {
            if var existing = observedMethods[method] {
                existing.count += 1
                if let detail {
                    existing.details.insert(detail)
                }
                observedMethods[method] = existing
            } else {
                observedMethods[method] = (
                    firstSeenMilliseconds: elapsedSinceWaitStart(),
                    count: 1,
                    details: detail.map { Set([$0]) } ?? []
                )
                observedMethodOrder.append(method)
            }
        }

        while let object = try await nextMessage(until: deadline) {
            if let method = object["method"] as? String {
                recordObservedMethod(method, detail: observedDetail(for: object, method: method))
            }
            if let method = object["method"] as? String,
               method == "item/agentMessage/delta",
               let params = object["params"] as? [String: Any],
               let delta = params["delta"] as? String {
                if firstDeltaLatencyMilliseconds == nil {
                    firstDeltaLatencyMilliseconds = elapsedSinceWaitStart()
                }
                finalOutput += delta
                continue
            }
            if let method = object["method"] as? String,
               method == "item/completed",
               let params = object["params"] as? [String: Any],
               let item = params["item"] as? [String: Any],
               let type = item["type"] as? String,
               type == "agentMessage",
               let phase = item["phase"] as? String,
               phase == "final_answer" {
                if let text = item["text"] as? String, !text.isEmpty {
                    finalOutput = text
                }
                break
            }
            if let method = object["method"] as? String,
               method == "turn/completed" {
                break
            }
            if let responseID = object["id"] as? Int, responseID == id,
               let error = object["error"] {
                throw LLMProviderError.processFailed("Codex app-server turn error: \(error)")
            }
        }

        let trimmedOutput = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw LLMProviderError.invalidOutput
        }
        return CodexAppServerTurnResult(
            output: trimmedOutput,
            turnStartLatencyMilliseconds: max(0, Int((waitStart.timeIntervalSince(turnStart) * 1000).rounded())),
            firstDeltaLatencyMilliseconds: firstDeltaLatencyMilliseconds,
            finalAnswerLatencyMilliseconds: max(0, Int((Date().timeIntervalSince(waitStart) * 1000).rounded())),
            observedEvents: observedMethodOrder.prefix(24).compactMap { method in
                guard let observed = observedMethods[method] else {
                    return nil
                }
                var detailParts = ["count \(observed.count)"]
                if !observed.details.isEmpty {
                    let details = observed.details.sorted().prefix(6).joined(separator: ", ")
                    detailParts.append("details \(details)")
                }
                return AnalysisRunTraceEvent(
                    name: "app-server event: \(method)",
                    startedAtMilliseconds: observed.firstSeenMilliseconds,
                    durationMilliseconds: nil,
                    detail: detailParts.joined(separator: " · ")
                )
            },
            outputBytes: outputBytes,
            stderrBytes: 0,
            exitCode: processBox.terminationStatus
        )
    }

    nonisolated func terminate() {
        processBox.terminate()
    }

    private func nextID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func writeRequest(id: Int, method: String, params: [String: Any]) throws {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: message)
        writer.write(data)
        writer.write(Data("\n".utf8))
    }

    private func nextMessage(until deadline: Date) async throws -> [String: Any]? {
        while Date() < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }
            guard let line = await lineBuffer.nextLine() else {
                return nil
            }
            outputBytes += Data(line.utf8).count
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return object
        }
        return nil
    }

    private func waitForResponse(id: Int, deadline: Date) async throws -> [String: Any] {
        while let object = try await nextMessage(until: deadline) {
            if let responseID = object["id"] as? Int, responseID == id {
                if let error = object["error"] {
                    throw LLMProviderError.processFailed("Codex app-server error: \(error)")
                }
                return object
            }
        }
        throw LLMProviderError.timedOut(nil)
    }
}

private actor CodexAppServerLineBuffer {
    private var lines: [String] = []
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var isFinished = false

    func append(_ line: String) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: line)
        } else {
            lines.append(line)
        }
    }

    func finish() {
        isFinished = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume(returning: nil)
        }
    }

    func nextLine() async -> String? {
        if !lines.isEmpty {
            return lines.removeFirst()
        }
        if isFinished {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    var terminationStatus: Int32? {
        lock.lock()
        let process = process
        lock.unlock()
        guard let process, !process.isRunning else {
            return nil
        }
        return process.terminationStatus
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
