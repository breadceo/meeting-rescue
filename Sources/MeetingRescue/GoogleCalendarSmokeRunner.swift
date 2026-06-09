import Foundation
import MeetingRescueCore

enum GoogleCalendarSmokeRunner {
    static func runFromCommandLineIfRequested() -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.contains("--google-calendar-smoke") else {
            return false
        }

        let exitCode = run(arguments: arguments)
        Foundation.exit(exitCode)
    }

    private static func run(arguments: [String]) -> Int32 {
        do {
            let options = try SmokeOptions(arguments: arguments)
            let config = try loadConfig(options: options)
            let store = GoogleCalendarKeychainTokenStore(account: config.clientID)
            let service = GoogleCalendarService(config: config, tokenStore: store)

            if options.resetBeforeConnect {
                try service.disconnect()
            }

            if options.connect {
                print("google-calendar-smoke: opening browser oauth")
                try waitForAsync {
                    try await service.connect(timeoutSeconds: options.authTimeoutSeconds)
                }
            }

            guard service.hasStoredRefreshToken() else {
                throw SmokeError.missingKeychainToken
            }

            let request = GoogleCalendarEventsListRequest(
                calendarID: "primary",
                timeMin: options.timeMin,
                timeMax: options.timeMax,
                maxResults: options.maxResults
            )
            let response = try waitForAsync {
                try await service.fetchEvents(request: request)
            }
            if response.items.isEmpty && !options.allowEmptyEvents {
                throw SmokeError.emptyCalendarEvents
            }

            let metadata = MeetingMetadata(
                room: options.room,
                dateTime: options.metadataDateTime,
                participants: options.participants
            )
            let context = GoogleCalendarContextMapper.map(
                response,
                metadata: metadata,
                meetingStart: parseRFC3339(options.timeMin),
                meetingEnd: parseRFC3339(options.timeMax)
            )
            if context.eventCandidates.isEmpty && !options.allowEmptyEvents {
                throw SmokeError.emptyCalendarCandidates
            }

            let transcriptURL = try options.makeTranscriptURL()
            try options.makeTranscriptText().write(to: transcriptURL, atomically: true, encoding: .utf8)
            defer {
                if options.cleanupTranscript {
                    try? FileManager.default.removeItem(at: transcriptURL)
                }
            }

            let stateStore = ApplicationStateStore()
            try stateStore.saveAnalysisState(MeetingAnalysisState(calendarContext: context), for: transcriptURL)
            let persisted = stateStore.loadAnalysisState(for: transcriptURL)
            guard persisted.calendarContext.eventCandidates.count == context.eventCandidates.count else {
                throw SmokeError.persistenceMismatch
            }
            let replay = persisted.calendarContext.cachedForTestRunReplay()
            guard replay.mcpStatus == .cachedReplay, replay.hasReusableContext else {
                throw SmokeError.cachedReplayMismatch
            }

            if options.disconnectAfter {
                try service.disconnect()
                if service.hasStoredRefreshToken() {
                    throw SmokeError.disconnectFailed
                }
            }

            print("google-calendar-smoke: oauth keychain token present")
            print("google-calendar-smoke: fetched events \(response.items.count)")
            print("google-calendar-smoke: persisted candidates \(persisted.calendarContext.eventCandidates.count)")
            print("google-calendar-smoke: cached replay \(replay.mcpStatus.rawValue)")
            print("google-calendar-smoke: disconnect \(options.disconnectAfter ? "verified" : "skipped")")
            return 0
        } catch {
            fputs("google-calendar-smoke: failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func loadConfig(options: SmokeOptions) throws -> GoogleCalendarOAuthClientConfig {
        if let configPath = options.configPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            return try JSONDecoder().decode(GoogleCalendarOAuthClientConfig.self, from: data)
        }
        return try GoogleCalendarOAuthConfigLoader.load()
    }

    private static func waitForAsync<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = SmokeResultBox<T>()
        Task {
            do {
                box.result = Result<T, Error>.success(try await operation())
            } catch {
                box.result = Result<T, Error>.failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }

    private static func parseRFC3339(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private final class SmokeResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private struct SmokeOptions {
    var configPath: String?
    var connect = false
    var resetBeforeConnect = false
    var disconnectAfter = false
    var allowEmptyEvents = false
    var authTimeoutSeconds: TimeInterval = 180
    var maxResults = 10
    var timeMin = "2026-06-08T00:00:00+09:00"
    var timeMax = "2026-06-09T00:00:00+09:00"
    var room = "Meeting Rescue Smoke"
    var metadataDateTime = "2026-06-08 00:00"
    var participants: [String] = []
    var transcriptPath: String?
    var cleanupTranscript = true

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--google-calendar-smoke":
                index += 1
            case "--config":
                configPath = try Self.value(after: argument, at: &index, in: arguments)
            case "--connect":
                connect = true
                index += 1
            case "--reset-before-connect":
                resetBeforeConnect = true
                index += 1
            case "--disconnect-after":
                disconnectAfter = true
                index += 1
            case "--allow-empty-events":
                allowEmptyEvents = true
                index += 1
            case "--auth-timeout":
                authTimeoutSeconds = TimeInterval(try Self.value(after: argument, at: &index, in: arguments)) ?? authTimeoutSeconds
            case "--time-min":
                timeMin = try Self.value(after: argument, at: &index, in: arguments)
            case "--time-max":
                timeMax = try Self.value(after: argument, at: &index, in: arguments)
            case "--max-results":
                maxResults = Int(try Self.value(after: argument, at: &index, in: arguments)) ?? maxResults
            case "--room":
                room = try Self.value(after: argument, at: &index, in: arguments)
            case "--date-time":
                metadataDateTime = try Self.value(after: argument, at: &index, in: arguments)
            case "--participants":
                participants = try Self.value(after: argument, at: &index, in: arguments)
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            case "--transcript":
                transcriptPath = try Self.value(after: argument, at: &index, in: arguments)
                cleanupTranscript = false
            default:
                throw SmokeError.invalidArgument(argument)
            }
        }
    }

    func makeTranscriptURL() throws -> URL {
        if let transcriptPath {
            return URL(fileURLWithPath: transcriptPath)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-rescue-google-calendar-smoke-\(UUID().uuidString).txt")
    }

    func makeTranscriptText() -> String {
        """
        제목: \(room)
        일시: \(metadataDateTime)
        참석자: \(participants.joined(separator: ", "))

        [00:00] Smoke: Google Calendar context smoke.
        """
    }

    private static func value(after option: String, at index: inout Int, in arguments: [String]) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw SmokeError.missingValue(option)
        }
        index += 2
        return arguments[valueIndex]
    }
}

private enum SmokeError: LocalizedError {
    case invalidArgument(String)
    case missingValue(String)
    case missingKeychainToken
    case emptyCalendarEvents
    case emptyCalendarCandidates
    case persistenceMismatch
    case cachedReplayMismatch
    case disconnectFailed

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument):
            return "invalid argument \(argument)"
        case .missingValue(let option):
            return "missing value for \(option)"
        case .missingKeychainToken:
            return "Keychain refresh token was not stored"
        case .emptyCalendarEvents:
            return "Google Calendar API returned no events"
        case .emptyCalendarCandidates:
            return "Calendar context mapper produced no candidates"
        case .persistenceMismatch:
            return "persisted CalendarContextState did not match fetched context"
        case .cachedReplayMismatch:
            return "cachedForTestRunReplay did not preserve calendar context"
        case .disconnectFailed:
            return "Keychain refresh token still exists after disconnect"
        }
    }
}
