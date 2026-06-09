import Foundation
import MeetingRescueCore

enum CalendarQualityABRunner {
    static func runFromCommandLineIfRequested() -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.contains("--calendar-quality-ab") else {
            return false
        }

        let exitCode = run(arguments: arguments)
        Foundation.exit(exitCode)
    }

    private static func run(arguments: [String]) -> Int32 {
        do {
            let options = try ABOptions(arguments: arguments)
            let report = try waitForAsync {
                try await runEvaluation(options: options)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try FileManager.default.createDirectory(
                at: options.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: options.outputURL, options: [.atomic])
            log("calendar-quality-ab: wrote \(options.outputURL.path)")
            log("calendar-quality-ab: samples \(report.samples.count)")
            return report.samples.isEmpty ? 1 : 0
        } catch {
            fputs("calendar-quality-ab: failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func runEvaluation(options: ABOptions) async throws -> ABReport {
        let stateStore = ApplicationStateStore()
        let settings = stateStore.loadSettings()
        let provider = makeProvider(settings: settings, timeoutSeconds: options.timeoutSeconds)
        let service = try makeGoogleCalendarServiceIfAvailable()
        let candidates = try loadSessionCandidates()

        var samples: [ABSampleReport] = []
        var skipped: [ABSkipReport] = []

        for candidate in candidates {
            guard samples.count < options.sampleCount else {
                break
            }
            if options.excludeSampleIDs.contains(candidate.id) {
                skipped.append(.init(sampleID: candidate.id, reason: "excluded"))
                continue
            }
            guard candidate.transcriptCharacterCount >= options.minTranscriptCharacters else {
                skipped.append(.init(sampleID: candidate.id, reason: "transcript-too-short"))
                continue
            }

            let context: CalendarContextState
            if candidate.savedCalendarContext.hasPromptableCalendarMetadata {
                context = candidate.savedCalendarContext
            } else if let service {
                do {
                    context = try await fetchCalendarContext(for: candidate, service: service)
                } catch {
                    skipped.append(.init(sampleID: candidate.id, reason: "calendar-fetch-failed"))
                    continue
                }
            } else {
                skipped.append(.init(sampleID: candidate.id, reason: "calendar-unavailable"))
                continue
            }

            guard context.hasPromptableCalendarMetadata else {
                skipped.append(.init(sampleID: candidate.id, reason: "no-promptable-calendar-context"))
                continue
            }

            let runWithFirst = samples.count % 2 == 1
            log("calendar-quality-ab: sample \(samples.count + 1) \(candidate.id) \(runWithFirst ? "with-first" : "without-first")")
            do {
                let pair = try await runPair(
                    candidate: candidate,
                    context: context,
                    provider: provider,
                    settings: settings,
                    includeRawOutput: options.includeRawOutput,
                    runWithFirst: runWithFirst
                )
                samples.append(pair)
            } catch {
                skipped.append(.init(sampleID: candidate.id, reason: "analysis-failed"))
            }
        }

        return ABReport(
            generatedAt: Date(),
            modelPreset: settings.modelPreset.rawValue,
            provider: settings.selectedProvider.rawValue,
            codexExecutionMode: settings.selectedProvider == .codexExec
                ? CodexExecutionMode.cliExec.rawValue
                : settings.codexExecutionMode.rawValue,
            samples: samples,
            skipped: skipped
        )
    }

    private static func runPair(
        candidate: ABSessionCandidate,
        context: CalendarContextState,
        provider: LLMProvider,
        settings: AppSettings,
        includeRawOutput: Bool,
        runWithFirst: Bool
    ) async throws -> ABSampleReport {
        let withoutRequest = makeRequest(
            candidate: candidate,
            settings: settings,
            variant: "without-calendar",
            supplementalContextSources: []
        )
        let withRequest = makeRequest(
            candidate: candidate,
            settings: settings,
            variant: "with-calendar",
            supplementalContextSources: context.supplementalSources
        )

        let withoutResult: AnalysisProviderResult
        let withResult: AnalysisProviderResult
        if runWithFirst {
            withResult = try await provider.analyze(withRequest)
            withoutResult = try await provider.analyze(withoutRequest)
        } else {
            withoutResult = try await provider.analyze(withoutRequest)
            withResult = try await provider.analyze(withRequest)
        }

        return ABSampleReport(
            sampleID: candidate.id,
            sourceFileName: candidate.sourceURL.lastPathComponent,
            metadata: ABSampleMetadata(
                room: candidate.session.metadata.room,
                dateTime: candidate.session.metadata.dateTime,
                participantCount: candidate.session.metadata.participants.count,
                transcriptCharacterCount: candidate.transcriptCharacterCount
            ),
            calendar: ABCalendarSummary(context: context),
            withoutCalendar: ABVariantReport(result: withoutResult, includeRawOutput: includeRawOutput),
            withCalendar: ABVariantReport(result: withResult, includeRawOutput: includeRawOutput)
        )
    }

    private static func makeRequest(
        candidate: ABSessionCandidate,
        settings: AppSettings,
        variant: String,
        supplementalContextSources: [SupplementalContextSource]
    ) -> AnalysisRequest {
        AnalysisRequest(
            meetingID: "\(candidate.id)-ab-\(variant)",
            metadata: candidate.session.metadata,
            rawTranscript: candidate.rawTranscript,
            providerKind: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            meetingTypePreset: settings.meetingTypePreset,
            bookmarks: candidate.analysisState.bookmarks,
            reason: "final-calendar-ab",
            lastAnalyzedTranscriptCharacterCount: 0,
            supplementalContextSources: supplementalContextSources
        )
    }

    private static func makeProvider(settings: AppSettings, timeoutSeconds: Int) -> LLMProvider {
        let schemaURL = resourceURL(named: "analysis-output.schema.json")
        let patchSchemaURL = resourceURL(named: "analysis-patch-output.schema.json")
        let workingDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fallback = CodexExecProvider(
            schemaURL: schemaURL,
            patchSchemaURL: patchSchemaURL,
            timeoutSeconds: timeoutSeconds,
            workingDirectoryURL: workingDirectoryURL,
            modelPreset: settings.modelPreset
        )

        switch settings.selectedProvider {
        case .codexExec:
            // A/B runs are batch verification jobs. Prefer one-shot CLI exec over app-server reuse so
            // a stuck stdio turn cannot hold the whole experiment.
            return fallback
        case .claudeCode:
            return ClaudeCodeProvider(
                schemaURL: schemaURL,
                patchSchemaURL: patchSchemaURL,
                timeoutSeconds: timeoutSeconds,
                workingDirectoryURL: workingDirectoryURL,
                modelPreset: settings.modelPreset
            )
        case .customCommand:
            return CustomCommandProvider(
                command: settings.customProviderCommand,
                timeoutSeconds: timeoutSeconds,
                workingDirectoryURL: workingDirectoryURL,
                modelPreset: settings.modelPreset
            )
        }
    }

    private static func makeGoogleCalendarServiceIfAvailable() throws -> GoogleCalendarService? {
        do {
            let config = try GoogleCalendarOAuthConfigLoader.load()
            let store = GoogleCalendarKeychainTokenStore(account: config.clientID)
            let service = GoogleCalendarService(config: config, tokenStore: store)
            return service.hasStoredRefreshToken() ? service : nil
        } catch GoogleCalendarIntegrationError.missingConfig {
            return nil
        }
    }

    private static func fetchCalendarContext(
        for candidate: ABSessionCandidate,
        service: GoogleCalendarService
    ) async throws -> CalendarContextState {
        let meetingStart = parseMeetingDateTime(candidate.session.metadata.dateTime)
            ?? candidate.sourceModificationDate
        let meetingEnd = meetingStart.addingTimeInterval(3 * 60 * 60)
        let request = GoogleCalendarEventsListRequest(
            calendarID: "primary",
            timeMin: rfc3339String(from: meetingStart.addingTimeInterval(-15 * 60)),
            timeMax: rfc3339String(from: meetingEnd.addingTimeInterval(30 * 60)),
            maxResults: 10
        )
        let response = try await service.fetchEvents(request: request)
        return GoogleCalendarContextMapper.map(
            response,
            metadata: candidate.session.metadata,
            meetingStart: meetingStart,
            meetingEnd: meetingEnd
        )
    }

    private static func loadSessionCandidates() throws -> [ABSessionCandidate] {
        let sessionsURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("MeetingRescue/Sessions", isDirectory: true)
        let sessionFiles = try FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let baseSessionFiles = sessionFiles.filter {
            $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix("-analysis.json")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var candidates: [ABSessionCandidate] = []
        for sessionURL in baseSessionFiles {
            let id = sessionURL.deletingPathExtension().lastPathComponent
            let analysisURL = sessionsURL.appendingPathComponent("\(id)-analysis.json")
            guard FileManager.default.fileExists(atPath: analysisURL.path) else {
                continue
            }
            let session = try decoder.decode(MeetingSessionState.self, from: Data(contentsOf: sessionURL))
            let analysis = try decoder.decode(MeetingAnalysisState.self, from: Data(contentsOf: analysisURL))
            let sourceURL = URL(fileURLWithPath: session.sourceFilePath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                continue
            }
            let rawTranscript = try String(contentsOf: sourceURL, encoding: .utf8)
            let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            let modificationDate = (attributes[.modificationDate] as? Date) ?? Date.distantPast
            candidates.append(
                ABSessionCandidate(
                    id: id,
                    sourceURL: sourceURL,
                    sourceModificationDate: modificationDate,
                    session: session,
                    analysisState: analysis,
                    rawTranscript: rawTranscript
                )
            )
        }

        return candidates.sorted { lhs, rhs in
            let lhsContext = lhs.savedCalendarContext.hasPromptableCalendarMetadata
            let rhsContext = rhs.savedCalendarContext.hasPromptableCalendarMetadata
            if lhsContext != rhsContext {
                return lhsContext
            }
            return lhs.sourceModificationDate > rhs.sourceModificationDate
        }
    }

    private static func resourceURL(named fileName: String) -> URL {
        let relativePath = "MeetingRescue_MeetingRescue.bundle/Resources/\(fileName)"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(relativePath),
            Bundle.main.bundleURL.appendingPathComponent(relativePath),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(relativePath)
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? candidates[0]
    }

    private static func parseMeetingDateTime(_ value: String?) -> Date? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy.MM.dd HH:mm:ss",
            "yyyy.MM.dd HH:mm"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func rfc3339String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func waitForAsync<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ABResultBox<T>()
        Task {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }

    private static func log(_ message: String) {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }
}

private struct ABOptions {
    var sampleCount = 3
    var timeoutSeconds = 300
    var minTranscriptCharacters = 2_000
    var excludeSampleIDs = Set<String>()
    var includeRawOutput = false
    var outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("meeting-rescue-calendar-ab-\(Int(Date().timeIntervalSince1970)).json")

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--calendar-quality-ab":
                index += 1
            case "--samples":
                sampleCount = Int(try Self.value(after: argument, at: &index, in: arguments)) ?? sampleCount
            case "--timeout":
                timeoutSeconds = Int(try Self.value(after: argument, at: &index, in: arguments)) ?? timeoutSeconds
            case "--min-transcript-chars":
                minTranscriptCharacters = Int(try Self.value(after: argument, at: &index, in: arguments)) ?? minTranscriptCharacters
            case "--exclude-sample-ids":
                excludeSampleIDs = Set(
                    try Self.value(after: argument, at: &index, in: arguments)
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            case "--include-raw-output":
                includeRawOutput = true
                index += 1
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: argument, at: &index, in: arguments))
            default:
                throw ABError.invalidArgument(argument)
            }
        }
    }

    private static func value(after option: String, at index: inout Int, in arguments: [String]) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw ABError.missingValue(option)
        }
        index += 2
        return arguments[valueIndex]
    }
}

private struct ABSessionCandidate {
    var id: String
    var sourceURL: URL
    var sourceModificationDate: Date
    var session: MeetingSessionState
    var analysisState: MeetingAnalysisState
    var rawTranscript: String

    var savedCalendarContext: CalendarContextState {
        analysisState.calendarContext
    }

    var transcriptCharacterCount: Int {
        rawTranscript.count
    }
}

private struct ABReport: Encodable {
    var generatedAt: Date
    var modelPreset: String
    var provider: String
    var codexExecutionMode: String
    var samples: [ABSampleReport]
    var skipped: [ABSkipReport]
}

private struct ABSampleReport: Encodable {
    var sampleID: String
    var sourceFileName: String
    var metadata: ABSampleMetadata
    var calendar: ABCalendarSummary
    var withoutCalendar: ABVariantReport
    var withCalendar: ABVariantReport
}

private struct ABSampleMetadata: Encodable {
    var room: String?
    var dateTime: String?
    var participantCount: Int
    var transcriptCharacterCount: Int
}

private struct ABCalendarSummary: Encodable {
    var status: String
    var eventCandidateCount: Int
    var acceptedEventCount: Int
    var promptableSupplementalCount: Int
    var hasMeetingIdentity: Bool
    var acceptedTitles: [String]

    init(context: CalendarContextState) {
        self.status = context.mcpStatus.rawValue
        self.eventCandidateCount = context.eventCandidates.count
        self.acceptedEventCount = context.eventCandidates.filter { $0.status == .accepted }.count
        self.promptableSupplementalCount = context.supplementalSources.sortedForPrompt().count
        self.hasMeetingIdentity = context.meetingIdentity != nil
        self.acceptedTitles = context.eventCandidates
            .filter { $0.status == .accepted }
            .map(\.title)
    }
}

private struct ABVariantReport: Encodable {
    var metrics: ABSnapshotMetrics
    var usage: ABUsageReport
    var snapshot: AnalysisSnapshot?
    var rawOutput: String?

    init(result: AnalysisProviderResult, includeRawOutput: Bool) {
        self.metrics = ABSnapshotMetrics(snapshot: result.snapshot)
        self.usage = ABUsageReport(sample: result.usage)
        self.snapshot = includeRawOutput ? result.snapshot : nil
        self.rawOutput = includeRawOutput ? result.rawOutput : nil
    }
}

private struct ABSnapshotMetrics: Encodable {
    var meetingType: String
    var overviewCharacters: Int
    var keyPointCount: Int
    var summaryOpenQuestionCount: Int
    var currentIssueCharacters: Int
    var currentIssueOpenQuestionCount: Int
    var topicCount: Int
    var decisionCount: Int
    var confirmedDecisionCount: Int
    var actionCount: Int
    var confirmedActionCount: Int
    var riskCount: Int
    var evidenceReferenceCount: Int

    init(snapshot: AnalysisSnapshot) {
        self.meetingType = snapshot.meetingType.rawValue
        self.overviewCharacters = snapshot.meetingSummary.overview.count
        self.keyPointCount = snapshot.meetingSummary.keyPoints.count
        self.summaryOpenQuestionCount = snapshot.meetingSummary.openQuestions.count
        self.currentIssueCharacters = snapshot.currentIssue.summary.count
        self.currentIssueOpenQuestionCount = snapshot.currentIssue.openQuestions.count
        self.topicCount = snapshot.topicTimeline.count
        self.decisionCount = snapshot.decisionCandidates.count
        self.confirmedDecisionCount = snapshot.decisionCandidates.filter { $0.status == .confirmed }.count
        self.actionCount = snapshot.actionItemCandidates.count
        self.confirmedActionCount = snapshot.actionItemCandidates.filter { $0.status == .confirmed }.count
        self.riskCount = snapshot.risksOrNotes.count
        self.evidenceReferenceCount = snapshot.meetingSummary.keyPoints.reduce(0) { $0 + $1.evidence.count }
            + snapshot.meetingSummary.openQuestions.reduce(0) { $0 + $1.evidence.count }
    }
}

private struct ABUsageReport: Encodable {
    var inputTokens: Int
    var outputTokens: Int
    var estimatedCostUSD: Double

    init(sample: LLMUsageSample) {
        self.inputTokens = sample.inputTokens
        self.outputTokens = sample.outputTokens
        self.estimatedCostUSD = sample.estimatedCostUSD ?? 0
    }
}

private struct ABSkipReport: Encodable {
    var sampleID: String
    var reason: String
}

private final class ABResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private enum ABError: LocalizedError {
    case invalidArgument(String)
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let argument):
            return "invalid argument \(argument)"
        case .missingValue(let option):
            return "missing value for \(option)"
        }
    }
}

private extension CalendarContextState {
    var hasPromptableCalendarMetadata: Bool {
        !supplementalSources.sortedForPrompt().filter { $0.kind == .calendarMetadata }.isEmpty
    }
}
