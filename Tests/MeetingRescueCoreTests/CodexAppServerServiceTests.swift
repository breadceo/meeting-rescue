import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Codex app-server service")
struct CodexAppServerServiceTests {
    @Test("같은 meeting analysis는 app-server process와 thread를 재사용한다")
    func reusesProcessAndThreadForSameMeeting() async throws {
        let factory = FakeAppServerRuntimeFactory(turnBehaviors: [])
        let service = CodexAppServerService { configuration in
            await factory.makeRuntime(configuration)
        }

        let first = try await service.runTurn(
            prompt: "first prompt",
            schemaData: Data("{}".utf8),
            meetingID: "meeting-1",
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            modelPreset: .economy,
            timeoutSeconds: 10
        )
        let second = try await service.runTurn(
            prompt: "second prompt",
            schemaData: Data("{}".utf8),
            meetingID: "meeting-1",
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            modelPreset: .economy,
            timeoutSeconds: 10
        )

        #expect(await factory.runtimeCount() == 1)
        let stats = await factory.runtime(at: 0)?.stats()
        #expect(stats?.initializeCount == 1)
        #expect(stats?.threadStartCount == 1)
        #expect(stats?.turnCount == 2)
        #expect(first.trace.events.contains { $0.name == "app-server process" && $0.detail == "new" })
        #expect(second.trace.events.contains { $0.name == "app-server process" && $0.detail == "reused" })
        #expect(second.trace.events.contains { $0.name == "initialize app-server" && $0.detail == "reused" })
        #expect(second.trace.events.contains { $0.name == "thread/start" && ($0.detail?.hasPrefix("reused") == true) })
        #expect(second.trace.events.contains { $0.name == "first delta latency" })
        #expect(second.trace.events.contains { $0.name == "final answer latency" })
        #expect(second.trace.events.contains { $0.name == "app-server event: item/started" && $0.detail == "count 1" })
        #expect(second.trace.events.contains { $0.name == "app-server event: item/agentMessage/delta" && $0.detail == "count 2" })
    }

    @Test("turn failure는 app-server service를 reset하고 다음 run은 새 process를 만든다")
    func resetsServiceAfterTurnFailure() async throws {
        let factory = FakeAppServerRuntimeFactory(turnBehaviors: [.failure, .success])
        let service = CodexAppServerService { configuration in
            await factory.makeRuntime(configuration)
        }

        do {
            _ = try await service.runTurn(
                prompt: "failing prompt",
                schemaData: Data("{}".utf8),
                meetingID: "meeting-1",
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                modelPreset: .economy,
                timeoutSeconds: 10
            )
            Issue.record("첫 turn은 실패해야 합니다.")
        } catch let error as LLMProviderError {
            guard case .processFailed = error else {
                Issue.record("processFailed가 아닌 오류가 발생했습니다: \(error)")
                return
            }
        }

        let second = try await service.runTurn(
            prompt: "recovered prompt",
            schemaData: Data("{}".utf8),
            meetingID: "meeting-1",
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            modelPreset: .economy,
            timeoutSeconds: 10
        )

        #expect(await factory.runtimeCount() == 2)
        #expect(await factory.runtime(at: 0)?.stats().terminated == true)
        #expect(await factory.runtime(at: 1)?.stats().turnCount == 1)
        #expect(second.trace.events.contains { $0.name == "app-server process" && $0.detail == "new" })
    }

    @Test("turn timeout은 app-server process를 terminate하고 service state를 reset한다")
    func resetsServiceAfterTurnTimeout() async throws {
        let factory = FakeAppServerRuntimeFactory(turnBehaviors: [.timeout, .success])
        let service = CodexAppServerService { configuration in
            await factory.makeRuntime(configuration)
        }

        do {
            _ = try await service.runTurn(
                prompt: "timeout prompt",
                schemaData: Data("{}".utf8),
                meetingID: "meeting-1",
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
                modelPreset: .economy,
                timeoutSeconds: 1
            )
            Issue.record("첫 turn은 timeout이어야 합니다.")
        } catch let error as LLMProviderError {
            guard case .timedOut = error else {
                Issue.record("timedOut이 아닌 오류가 발생했습니다: \(error)")
                return
            }
        }

        _ = try await service.runTurn(
            prompt: "recovered prompt",
            schemaData: Data("{}".utf8),
            meetingID: "meeting-1",
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            workingDirectoryURL: URL(fileURLWithPath: "/tmp"),
            modelPreset: .economy,
            timeoutSeconds: 10
        )

        #expect(await factory.runtimeCount() == 2)
        #expect(await factory.runtime(at: 0)?.stats().terminated == true)
        #expect(await factory.runtime(at: 1)?.stats().turnCount == 1)
    }
}

private actor FakeAppServerRuntimeFactory {
    private var runtimes: [FakeAppServerRuntime] = []
    private var turnBehaviors: [FakeTurnBehavior]

    init(turnBehaviors: [FakeTurnBehavior]) {
        self.turnBehaviors = turnBehaviors
    }

    func makeRuntime(_ configuration: CodexAppServerRuntimeConfiguration) -> any CodexAppServerRuntime {
        let turnBehavior = turnBehaviors.isEmpty ? .success : turnBehaviors.removeFirst()
        let runtime = FakeAppServerRuntime(configuration: configuration, turnBehavior: turnBehavior)
        runtimes.append(runtime)
        return runtime
    }

    func runtimeCount() -> Int {
        runtimes.count
    }

    func runtime(at index: Int) -> FakeAppServerRuntime? {
        guard runtimes.indices.contains(index) else {
            return nil
        }
        return runtimes[index]
    }
}

private enum FakeTurnBehavior {
    case success
    case failure
    case timeout
}

private struct FakeAppServerRuntimeStats: Equatable {
    var initializeCount: Int
    var threadStartCount: Int
    var turnCount: Int
    var terminated: Bool
}

private final class FakeAppServerRuntime: CodexAppServerRuntime, @unchecked Sendable {
    let configuration: CodexAppServerRuntimeConfiguration
    private let lock = NSLock()
    private let turnBehavior: FakeTurnBehavior
    private var initializeCount = 0
    private var threadStartCount = 0
    private var turnCount = 0
    private var outputBytes = 0
    private var terminated = false

    init(configuration: CodexAppServerRuntimeConfiguration, turnBehavior: FakeTurnBehavior) {
        self.configuration = configuration
        self.turnBehavior = turnBehavior
    }

    func outputBytesRead() async -> Int {
        lock.withLock { outputBytes }
    }

    func initialize(deadline: Date) async throws {
        lock.withLock {
            initializeCount += 1
            outputBytes += 16
        }
    }

    func startThread(modelName: String?, deadline: Date) async throws -> String {
        lock.withLock {
            threadStartCount += 1
            outputBytes += 16
        }
        return "thread-1"
    }

    func startTurn(
        threadID: String,
        prompt: String,
        schemaData: Data,
        modelName: String?,
        deadline: Date
    ) async throws -> CodexAppServerTurnResult {
        lock.withLock {
            turnCount += 1
            outputBytes += 32
        }
        switch turnBehavior {
        case .success:
            break
        case .failure:
            throw LLMProviderError.processFailed("fake turn failure")
        case .timeout:
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return CodexAppServerTurnResult(
            output: #"{"ok":true}"#,
            turnStartLatencyMilliseconds: 3,
            firstDeltaLatencyMilliseconds: 5,
            finalAnswerLatencyMilliseconds: 9,
            observedEvents: [
                AnalysisRunTraceEvent(
                    name: "app-server event: item/started",
                    startedAtMilliseconds: 1,
                    detail: "count 1"
                ),
                AnalysisRunTraceEvent(
                    name: "app-server event: item/agentMessage/delta",
                    startedAtMilliseconds: 5,
                    detail: "count 2"
                )
            ],
            outputBytes: lock.withLock { outputBytes },
            stderrBytes: 0,
            exitCode: 0
        )
    }

    nonisolated func terminate() {
        lock.withLock {
            terminated = true
        }
    }

    func stats() -> FakeAppServerRuntimeStats {
        lock.withLock {
            FakeAppServerRuntimeStats(
                initializeCount: initializeCount,
                threadStartCount: threadStartCount,
                turnCount: turnCount,
                terminated: terminated
            )
        }
    }
}
