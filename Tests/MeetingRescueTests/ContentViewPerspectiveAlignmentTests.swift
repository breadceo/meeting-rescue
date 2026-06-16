import Foundation
import Testing

@Suite("ContentView perspective alignment wiring")
struct ContentViewPerspectiveAlignmentTests {
    @Test("overview renders perspective alignment between current issue and meeting summary")
    func overviewRendersPerspectiveAlignmentAfterCurrentIssue() throws {
        let source = try contentViewSource()
        let overview = try #require(source.slice(
            from: "private func overview(_ snapshot: AnalysisSnapshot)",
            to: "private func workflow("
        ))

        let currentIssue = try #require(overview.range(of: "currentIssue(snapshot.currentIssue)"))
        let perspectiveAlignment = try #require(overview.range(of: "perspectiveAlignments(snapshot.activePerspectiveAlignments)"))
        let meetingSummary = try #require(overview.range(of: "meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)"))

        #expect(currentIssue.lowerBound < perspectiveAlignment.lowerBound)
        #expect(perspectiveAlignment.lowerBound < meetingSummary.lowerBound)
    }

    @Test("perspective alignment section uses product-safe language")
    func perspectiveAlignmentUsesSafeLanguage() throws {
        let source = try contentViewSource()
        let section = try #require(source.slice(
            from: "private func perspectiveAlignments",
            to: "private func currentIssue"
        ))

        #expect(section.contains("관점 정렬"))
        #expect(section.contains("정렬 질문"))
        #expect(!section.contains("갈등"))
        #expect(!section.contains("대립"))
    }

    @Test("perspective alignment section renders evidence-backed alignment fields")
    func perspectiveAlignmentRendersEvidenceBackedFields() throws {
        let source = try contentViewSource()
        let section = try #require(source.slice(
            from: "private func perspectiveAlignments",
            to: "private func currentIssue"
        ))

        #expect(section.contains("if !alignments.isEmpty"))
        #expect(section.contains("alignment.topic"))
        #expect(section.contains("alignment.axis"))
        #expect(section.contains("perspective.speaker"))
        #expect(section.contains("perspective.summary"))
        #expect(section.contains("perspective.reasoning"))
        #expect(section.contains("summaryEvidenceText(evidence)"))
        #expect(section.contains("alignment.sharedGround"))
        #expect(section.contains("alignment.nextQuestion"))
        #expect(section.contains(".smoothCard(tint: Color.smoothMint)"))
    }
}

private func contentViewSource() throws -> String {
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
}

private extension String {
    func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker),
              let end = range(of: endMarker, range: start.upperBound..<endIndex) else {
            return nil
        }
        return String(self[start.lowerBound..<end.lowerBound])
    }
}
