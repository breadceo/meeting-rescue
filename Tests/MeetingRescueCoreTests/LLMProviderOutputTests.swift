import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("LLM provider output")
struct LLMProviderOutputTests {
    @Test("generatedAt/provider가 없는 schema output도 기본값으로 decode한다")
    func decodesOutputWithoutRuntimeFields() throws {
        let json = """
        {
          "currentIssue": {
            "summary": "논의 중",
            "openQuestions": []
          },
          "topicTimeline": [],
          "decisionCandidates": [],
          "actionItemCandidates": [],
          "risksOrNotes": []
        }
        """

        let snapshot = try JSONDecoder().decode(AnalysisSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.currentIssue.summary == "논의 중")
        #expect(snapshot.provider == .codexExec)
    }
}
