import Foundation
import MeetingRescueCore

enum LocalGlossaryQualityABRunner {
    static func runFromCommandLineIfRequested() -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.contains("--local-glossary-ab") else {
            return false
        }

        let exitCode = run(arguments: arguments)
        Foundation.exit(exitCode)
    }

    private static func run(arguments: [String]) -> Int32 {
        do {
            let options = try GlossaryABOptions(arguments: arguments)
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
            log("local-glossary-ab: wrote \(options.outputURL.path)")
            log("local-glossary-ab: domain glossary sources \(report.domainGlossaryCount)")
            return 0
        } catch {
            fputs("local-glossary-ab: failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func runEvaluation(options: GlossaryABOptions) async throws -> GlossaryABReport {
        let stateStore = ApplicationStateStore()
        let settings = stateStore.loadSettings()
        let glossaryState = stateStore.loadLocalGlossaryState()
        let rawTranscript = try String(contentsOf: options.transcriptURL, encoding: .utf8)
        let metadata = stateStore.loadSession(for: options.transcriptURL)?.metadata
            ?? TranscriptParser.parse(rawTranscript).metadata
        let analysisState = stateStore.loadAnalysisState(for: options.transcriptURL)
        let provider = makeProvider(settings: settings, timeoutSeconds: options.timeoutSeconds)
        let glossarySources = LocalGlossaryMatcher.supplementalSources(
            for: rawTranscript,
            state: glossaryState,
            maxMatches: options.maxGlossaryMatches
        )
        let inventory = GlossaryABTermInventory(state: glossaryState, rawTranscript: rawTranscript)

        let withoutRequest = makeRequest(
            transcriptURL: options.transcriptURL,
            metadata: metadata,
            rawTranscript: rawTranscript,
            settings: settings,
            analysisState: analysisState,
            variant: "without-glossary",
            supplementalContextSources: []
        )
        let withRequest = makeRequest(
            transcriptURL: options.transcriptURL,
            metadata: metadata,
            rawTranscript: rawTranscript,
            settings: settings,
            analysisState: analysisState,
            variant: "with-glossary",
            supplementalContextSources: glossarySources
        )

        let withoutResult: AnalysisProviderResult
        let withResult: AnalysisProviderResult
        if options.runWithGlossaryFirst {
            withResult = try await provider.analyze(withRequest)
            withoutResult = try await provider.analyze(withoutRequest)
        } else {
            withoutResult = try await provider.analyze(withoutRequest)
            withResult = try await provider.analyze(withRequest)
        }

        return GlossaryABReport(
            generatedAt: Date(),
            sourceFileName: options.transcriptURL.lastPathComponent,
            sourceFilePath: options.transcriptURL.path,
            modelPreset: settings.modelPreset.rawValue,
            provider: settings.selectedProvider.rawValue,
            codexExecutionMode: settings.selectedProvider == .codexExec
                ? CodexExecutionMode.cliExec.rawValue
                : settings.codexExecutionMode.rawValue,
            transcriptCharacterCount: rawTranscript.count,
            glossaryTermCount: glossaryState.enabledTerms.count,
            matchedGlossaryTermCount: inventory.terms.count,
            domainGlossaryCount: glossarySources.count,
            domainGlossarySources: glossarySources.map(GlossaryABSourceReport.init(source:)),
            withoutGlossary: GlossaryABVariantReport(
                result: withoutResult,
                inventory: inventory,
                rawTranscript: rawTranscript,
                includeRawOutput: options.includeRawOutput
            ),
            withGlossary: GlossaryABVariantReport(
                result: withResult,
                inventory: inventory,
                rawTranscript: rawTranscript,
                includeRawOutput: options.includeRawOutput
            )
        )
    }

    private static func makeRequest(
        transcriptURL: URL,
        metadata: MeetingMetadata,
        rawTranscript: String,
        settings: AppSettings,
        analysisState: MeetingAnalysisState,
        variant: String,
        supplementalContextSources: [SupplementalContextSource]
    ) -> AnalysisRequest {
        AnalysisRequest(
            meetingID: "\(transcriptURL.deletingPathExtension().lastPathComponent)-glossary-ab-\(variant)",
            metadata: metadata,
            rawTranscript: rawTranscript,
            providerKind: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            meetingTypePreset: settings.meetingTypePreset,
            bookmarks: analysisState.bookmarks,
            reason: "final-glossary-ab",
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

    private static func waitForAsync<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = GlossaryABResultBox<T>()
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

private struct GlossaryABOptions {
    var transcriptURL: URL
    var timeoutSeconds = 300
    var maxGlossaryMatches = 16
    var includeRawOutput = false
    var runWithGlossaryFirst = false
    var outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("meeting-rescue-glossary-ab-\(Int(Date().timeIntervalSince1970)).json")

    init(arguments: [String]) throws {
        var transcriptPath: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--local-glossary-ab":
                index += 1
            case "--transcript":
                transcriptPath = try Self.value(after: argument, at: &index, in: arguments)
            case "--timeout":
                timeoutSeconds = Int(try Self.value(after: argument, at: &index, in: arguments)) ?? timeoutSeconds
            case "--max-glossary-matches":
                maxGlossaryMatches = Int(try Self.value(after: argument, at: &index, in: arguments)) ?? maxGlossaryMatches
            case "--include-raw-output":
                includeRawOutput = true
                index += 1
            case "--with-glossary-first":
                runWithGlossaryFirst = true
                index += 1
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: argument, at: &index, in: arguments))
            default:
                throw GlossaryABError.invalidArgument(argument)
            }
        }

        guard let transcriptPath else {
            throw GlossaryABError.missingValue("--transcript")
        }
        transcriptURL = URL(fileURLWithPath: transcriptPath)
        timeoutSeconds = max(30, min(timeoutSeconds, 900))
        maxGlossaryMatches = max(1, min(maxGlossaryMatches, 64))
    }

    private static func value(after option: String, at index: inout Int, in arguments: [String]) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw GlossaryABError.missingValue(option)
        }
        index += 2
        return arguments[valueIndex]
    }
}

private struct GlossaryABReport: Encodable {
    var generatedAt: Date
    var sourceFileName: String
    var sourceFilePath: String
    var modelPreset: String
    var provider: String
    var codexExecutionMode: String
    var transcriptCharacterCount: Int
    var glossaryTermCount: Int
    var matchedGlossaryTermCount: Int
    var domainGlossaryCount: Int
    var domainGlossarySources: [GlossaryABSourceReport]
    var withoutGlossary: GlossaryABVariantReport
    var withGlossary: GlossaryABVariantReport
}

private struct GlossaryABSourceReport: Encodable {
    var title: String
    var excerpt: String
    var confidence: Double

    init(source: SupplementalContextSource) {
        title = source.title
        excerpt = source.excerpt
        confidence = source.confidence
    }
}

private struct GlossaryABVariantReport: Encodable {
    var termMetrics: GlossaryABTermMetrics
    var unsupportedDecisionOrActionCount: Int
    var usage: GlossaryABUsageReport
    var snapshot: AnalysisSnapshot?
    var rawOutput: String?

    init(
        result: AnalysisProviderResult,
        inventory: GlossaryABTermInventory,
        rawTranscript: String,
        includeRawOutput: Bool
    ) {
        termMetrics = GlossaryABTermMetrics(snapshot: result.snapshot, inventory: inventory)
        unsupportedDecisionOrActionCount = Self.unsupportedDecisionOrActionCount(
            snapshot: result.snapshot,
            rawTranscript: rawTranscript
        )
        usage = GlossaryABUsageReport(sample: result.usage)
        snapshot = includeRawOutput ? result.snapshot : nil
        rawOutput = includeRawOutput ? result.rawOutput : nil
    }

    private static func unsupportedDecisionOrActionCount(
        snapshot: AnalysisSnapshot,
        rawTranscript: String
    ) -> Int {
        let decisionCount = snapshot.decisionCandidates.filter {
            !hasEvidenceTimestamp($0.evidenceTimestamp, in: rawTranscript)
        }.count
        let actionCount = snapshot.actionItemCandidates.filter {
            !hasEvidenceTimestamp($0.evidenceTimestamp, in: rawTranscript)
        }.count
        return decisionCount + actionCount
    }

    private static func hasEvidenceTimestamp(_ timestamp: String, in rawTranscript: String) -> Bool {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return rawTranscript.contains("[\(trimmed)]") || rawTranscript.contains(trimmed)
    }
}

private struct GlossaryABTermInventory {
    var terms: [GlossaryABTerm]

    init(state: LocalGlossaryState, rawTranscript: String) {
        let matches = LocalGlossaryMatcher.matches(
            in: rawTranscript,
            state: state,
            maxMatches: Int.max
        )
        let termsByID = Dictionary(uniqueKeysWithValues: state.enabledTerms.map { ($0.id, $0) })
        terms = matches.compactMap { match in
            guard let term = termsByID[match.termID] else {
                return nil
            }
            return GlossaryABTerm(
                canonical: term.canonical,
                aliases: term.aliases.filter { alias in
                    match.matchedAliases.contains(alias)
                }
            )
        }
    }
}

private struct GlossaryABTerm {
    var canonical: String
    var aliases: [String]
}

private struct GlossaryABTermMetrics: Encodable {
    var canonicalHitCount: Int
    var aliasLeakCount: Int
    var matchedTermCount: Int
    var canonicalTerms: [String]
    var leakedAliases: [String]

    init(snapshot: AnalysisSnapshot, inventory: GlossaryABTermInventory) {
        let text = Self.snapshotText(snapshot)
        let canonicalTerms = inventory.terms
            .filter { Self.contains($0.canonical, in: text) }
            .map(\.canonical)
        let leakedAliases = inventory.terms
            .flatMap(\.aliases)
            .filter { Self.contains($0, in: text) }

        self.canonicalHitCount = canonicalTerms.count
        self.aliasLeakCount = leakedAliases.count
        self.matchedTermCount = inventory.terms.count
        self.canonicalTerms = canonicalTerms
        self.leakedAliases = leakedAliases
    }

    private static func snapshotText(_ snapshot: AnalysisSnapshot) -> String {
        var values = [
            snapshot.meetingSummary.overview,
            snapshot.currentIssue.summary
        ]
        values.append(contentsOf: snapshot.meetingSummary.keyPoints.map(\.text))
        values.append(contentsOf: snapshot.meetingSummary.openQuestions.map(\.text))
        values.append(contentsOf: snapshot.currentIssue.openQuestions)
        values.append(contentsOf: snapshot.topicTimeline.flatMap { [$0.title, $0.summary] })
        values.append(contentsOf: snapshot.decisionCandidates.map(\.text))
        values.append(contentsOf: snapshot.actionItemCandidates.map(\.task))
        values.append(contentsOf: snapshot.risksOrNotes)
        return values.joined(separator: "\n")
    }

    private static func contains(_ needle: String, in haystack: String) -> Bool {
        let compactNeedle = MeetingHistorySearch.compactNormalize(needle)
        guard !compactNeedle.isEmpty else {
            return false
        }
        return MeetingHistorySearch.compactNormalize(haystack).contains(compactNeedle)
    }
}

private struct GlossaryABUsageReport: Encodable {
    var inputTokens: Int
    var outputTokens: Int
    var estimatedCostUSD: Double

    init(sample: LLMUsageSample) {
        inputTokens = sample.inputTokens
        outputTokens = sample.outputTokens
        estimatedCostUSD = sample.estimatedCostUSD ?? 0
    }
}

private final class GlossaryABResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

private enum GlossaryABError: LocalizedError {
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
