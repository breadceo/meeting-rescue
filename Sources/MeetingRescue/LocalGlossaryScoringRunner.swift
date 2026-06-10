import Foundation
import MeetingRescueCore

enum LocalGlossaryScoringRunner {
    static func runFromCommandLineIfRequested() -> Bool {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.contains("--local-glossary-score") else {
            return false
        }

        let exitCode = run(arguments: arguments)
        Foundation.exit(exitCode)
    }

    private static func run(arguments: [String]) -> Int32 {
        do {
            let options = try ScoringOptions(arguments: arguments)
            let report = try runScoring(options: options)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)

            if let outputURL = options.outputURL {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: outputURL, options: [.atomic])
                print("local-glossary-score: wrote \(outputURL.path)")
            } else if let text = String(data: data, encoding: .utf8) {
                print(text)
            }

            return report.qualityGate.passed ? 0 : 1
        } catch {
            fputs("local-glossary-score: failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func runScoring(options: ScoringOptions) throws -> LocalGlossaryScoringReport {
        let totalStartedAt = Date()
        let scanStartedAt = Date()
        let documents = LocalGlossaryHistoryScanner.documents(
            in: options.folderURL,
            configuration: .init(
                maxDocuments: options.limit,
                maxBytesPerDocument: 48_000,
                rawTranscriptLineLimit: 160
            )
        )
        let scanMilliseconds = elapsedMilliseconds(since: scanStartedAt)

        let stateStore = ApplicationStateStore()
        let state = stateStore.loadLocalGlossaryState()
        let suggestStartedAt = Date()
        let result = LocalGlossarySuggestionEngine.suggestionsWithDiagnostics(
            from: documents,
            existingState: state,
            maxSuggestions: 12,
            includeLatin: options.includeLatin
        )
        let suggestionMilliseconds = elapsedMilliseconds(since: suggestStartedAt)
        let totalMilliseconds = elapsedMilliseconds(since: totalStartedAt)

        var rejectionSummary = result.diagnostics.rejectionSummary
        if result.suggestions.isEmpty {
            rejectionSummary["strict-filter-no-candidates", default: 0] += 1
        }
        let candidates = result.suggestions.map(LocalGlossaryCandidateScoreReport.init(suggestion:))
        let noiseCount = candidates.filter(\.isObviousNoise).count
        let qualityGate = LocalGlossaryQualityGateReport(
            scope: options.includeLatin ? "latin-smoke" : "default-app",
            passed: totalMilliseconds <= 60_000
                && (options.includeLatin || suggestionMilliseconds <= 15_000)
                && noiseCount <= 2,
            reasons: qualityGateReasons(
                totalMilliseconds: totalMilliseconds,
                suggestionMilliseconds: suggestionMilliseconds,
                noiseCount: noiseCount,
                includeLatin: options.includeLatin
            ),
            obviousNoiseCount: noiseCount,
            warnings: qualityGateWarnings(
                suggestionMilliseconds: suggestionMilliseconds,
                includeLatin: options.includeLatin
            )
        )

        return LocalGlossaryScoringReport(
            generatedAt: Date(),
            folderPath: options.folderURL.path,
            limit: options.limit,
            includeLatin: options.includeLatin,
            documentCount: documents.count,
            candidateCount: candidates.count,
            timing: LocalGlossaryScoringTimingReport(
                scanMilliseconds: scanMilliseconds,
                suggestionMilliseconds: suggestionMilliseconds,
                totalMilliseconds: totalMilliseconds,
                engineDiagnostics: result.diagnostics
            ),
            candidates: candidates,
            rejectionSummary: rejectionSummary,
            qualityGate: qualityGate
        )
    }

    private static func qualityGateReasons(
        totalMilliseconds: Int,
        suggestionMilliseconds: Int,
        noiseCount: Int,
        includeLatin: Bool
    ) -> [String] {
        var reasons: [String] = []
        if totalMilliseconds > 60_000 {
            reasons.append("total-over-60s")
        }
        if !includeLatin, suggestionMilliseconds > 15_000 {
            reasons.append("suggestion-over-15s")
        }
        if noiseCount > 2 {
            reasons.append("noise-over-2")
        }
        return reasons.isEmpty ? ["pass"] : reasons
    }

    private static func qualityGateWarnings(
        suggestionMilliseconds: Int,
        includeLatin: Bool
    ) -> [String] {
        if includeLatin, suggestionMilliseconds > 15_000 {
            return ["latin-smoke-suggestion-over-15s"]
        }
        return []
    }

    private static func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }
}

private struct ScoringOptions {
    var folderURL = URL(fileURLWithPath: "/Users/ethan/Documents/Recordings", isDirectory: true)
    var limit = 40
    var includeLatin = false
    var outputURL: URL?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--local-glossary-score":
                break
            case "--folder":
                folderURL = URL(fileURLWithPath: try Self.value(after: argument, at: &index, in: arguments), isDirectory: true)
            case "--limit":
                let value = try Self.value(after: argument, at: &index, in: arguments)
                limit = Int(value) ?? limit
            case "--include-latin":
                includeLatin = true
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: argument, at: &index, in: arguments))
            default:
                throw ScoringError.unknownArgument(argument)
            }
            index += 1
        }
        limit = max(1, min(limit, 200))
    }

    private static func value(after option: String, at index: inout Int, in arguments: [String]) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw ScoringError.missingValue(option)
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}

private struct LocalGlossaryScoringReport: Codable {
    var generatedAt: Date
    var folderPath: String
    var limit: Int
    var includeLatin: Bool
    var documentCount: Int
    var candidateCount: Int
    var timing: LocalGlossaryScoringTimingReport
    var candidates: [LocalGlossaryCandidateScoreReport]
    var rejectionSummary: [String: Int]
    var qualityGate: LocalGlossaryQualityGateReport
}

private struct LocalGlossaryScoringTimingReport: Codable {
    var scanMilliseconds: Int
    var suggestionMilliseconds: Int
    var totalMilliseconds: Int
    var engineDiagnostics: LocalGlossarySuggestionEngineDiagnostics
}

private struct LocalGlossaryCandidateScoreReport: Codable {
    var id: String
    var suggestedCanonical: String
    var aliases: [String]
    var occurrenceCount: Int
    var meetingCount: Int
    var confidence: Double
    var scoreBreakdown: LocalGlossarySuggestionScore
    var impactLabel: LocalGlossaryCandidateImpactLabel
    var evidence: [LocalGlossaryEvidence]
    var isObviousNoise: Bool

    init(suggestion: LocalGlossarySuggestion) {
        id = suggestion.id
        suggestedCanonical = suggestion.suggestedCanonical
        aliases = suggestion.aliases
        occurrenceCount = suggestion.occurrenceCount
        meetingCount = suggestion.meetingCount
        confidence = suggestion.confidence
        scoreBreakdown = suggestion.score
        impactLabel = suggestion.score.impactLabel
        evidence = suggestion.evidence
        isObviousNoise = Self.isObviousNoise(suggestion)
    }

    private static func isObviousNoise(_ suggestion: LocalGlossarySuggestion) -> Bool {
        let compactAliases = suggestion.aliases.map(MeetingHistorySearch.compactNormalize)
        if compactAliases.contains(where: { hardNoiseTokens.contains($0) }) {
            return true
        }
        if suggestion.aliases.count > 4 {
            return true
        }
        if compactAliases.allSatisfy({ $0.count <= 3 }), compactAliases.count >= 3 {
            return true
        }
        if compactAliases.contains(where: isGenericPointerPhrase) {
            return true
        }
        return false
    }

    private static func isGenericPointerPhrase(_ compact: String) -> Bool {
        let prefixes = ["이런", "요런", "그런", "고런", "저런", "어떤"]
        let suffixes = ["부분", "부분들", "것", "것들", "내용", "얘기", "이야기"]
        return prefixes.contains { compact.hasPrefix($0) }
            && suffixes.contains { compact.hasSuffix($0) }
    }
}

private struct LocalGlossaryQualityGateReport: Codable {
    var scope: String
    var passed: Bool
    var reasons: [String]
    var obviousNoiseCount: Int
    var warnings: [String]
}

private enum ScoringError: LocalizedError {
    case missingValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "missing value for \(option)"
        case .unknownArgument(let argument):
            return "unknown argument \(argument)"
        }
    }
}

private let hardNoiseTokens: Set<String> = [
    "api", "ceo", "choi", "com", "ethan", "hong", "jay", "kim", "lee", "pid", "prd", "pro",
    "zena", "zigbang"
]
