import Foundation
import Testing

struct LocalGlossaryScoringRunnerTests {
    @Test("Local glossary scoring runner is wired as an opt-in CLI path")
    func runnerIsCommandLineOnly() throws {
        let appSource = try sourceFile("Sources/MeetingRescue/MeetingRescueApp.swift")
        let runnerSource = try sourceFile("Sources/MeetingRescue/LocalGlossaryScoringRunner.swift")

        #expect(appSource.contains("LocalGlossaryScoringRunner.runFromCommandLineIfRequested()"))
        #expect(runnerSource.contains("guard arguments.contains(\"--local-glossary-score\") else"))
        #expect(!runnerSource.contains("Button("))
    }

    @Test("Local glossary scoring runner supports folder limit include-latin and output options")
    func runnerSupportsQualityScoringOptions() throws {
        let runnerSource = try sourceFile("Sources/MeetingRescue/LocalGlossaryScoringRunner.swift")

        #expect(runnerSource.contains("case \"--folder\""))
        #expect(runnerSource.contains("case \"--limit\""))
        #expect(runnerSource.contains("case \"--include-latin\""))
        #expect(runnerSource.contains("case \"--output\""))
        #expect(runnerSource.contains("scoreBreakdown"))
        #expect(runnerSource.contains("impactLabel"))
        #expect(runnerSource.contains("rejectionSummary"))
        #expect(runnerSource.contains("timing"))
        #expect(runnerSource.contains("reviewCandidateCount"))
        #expect(runnerSource.contains("reviewCandidates"))
        #expect(runnerSource.contains("maxReviewCandidates"))
    }

    @Test("Latin scoring smoke is reported separately from the default app quality gate")
    func latinSmokeUsesSeparateQualityGateScope() throws {
        let runnerSource = try sourceFile("Sources/MeetingRescue/LocalGlossaryScoringRunner.swift")

        #expect(runnerSource.contains("scope: options.includeLatin ? \"latin-smoke\" : \"default-app\""))
        #expect(runnerSource.contains("if !includeLatin, suggestionMilliseconds > 15_000"))
        #expect(runnerSource.contains("latin-smoke-suggestion-over-15s"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
