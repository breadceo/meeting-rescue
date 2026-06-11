import Foundation
import Testing

struct LocalGlossaryQualityABRunnerTests {
    @Test("Local glossary quality A/B runner is wired as an opt-in CLI path")
    func runnerIsCommandLineOnly() throws {
        let appSource = try sourceFile("Sources/MeetingRescue/MeetingRescueApp.swift")
        let runnerSource = try sourceFile("Sources/MeetingRescue/LocalGlossaryQualityABRunner.swift")

        #expect(appSource.contains("LocalGlossaryQualityABRunner.runFromCommandLineIfRequested()"))
        #expect(runnerSource.contains("guard arguments.contains(\"--local-glossary-ab\") else"))
        #expect(!runnerSource.contains("Button("))
    }

    @Test("Local glossary quality A/B runner compares without and with glossary variants")
    func runnerComparesGlossaryVariants() throws {
        let runnerSource = try sourceFile("Sources/MeetingRescue/LocalGlossaryQualityABRunner.swift")

        #expect(runnerSource.contains("variant: \"without-glossary\""))
        #expect(runnerSource.contains("variant: \"with-glossary\""))
        #expect(runnerSource.contains("LocalGlossaryMatcher.supplementalSources"))
        #expect(runnerSource.contains("domainGlossaryCount"))
        #expect(runnerSource.contains("canonicalHitCount"))
        #expect(runnerSource.contains("aliasLeakCount"))
        #expect(runnerSource.contains("unsupportedDecisionOrActionCount"))
    }

    @Test("Local glossary quality A/B runner supports transcript output and raw output options")
    func runnerSupportsTranscriptAndOutputOptions() throws {
        let runnerSource = try sourceFile("Sources/MeetingRescue/LocalGlossaryQualityABRunner.swift")

        #expect(runnerSource.contains("case \"--transcript\""))
        #expect(runnerSource.contains("case \"--output\""))
        #expect(runnerSource.contains("case \"--include-raw-output\""))
        #expect(runnerSource.contains("case \"--timeout\""))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
