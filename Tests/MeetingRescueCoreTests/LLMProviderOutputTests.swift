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

    @Test("live patch output은 full snapshot fallback 없이 patch만 허용한다")
    func livePatchRejectsFullSnapshotFallback() throws {
        let fullSnapshotOutput = """
        {
          "currentIssue": {
            "summary": "전체 스냅샷으로 잘못 응답",
            "openQuestions": []
          },
          "topicTimeline": [],
          "decisionCandidates": [],
          "actionItemCandidates": [],
          "risksOrNotes": []
        }
        """
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:10] Alex: 새 내용",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 1
        )

        #expect(request.outputMode == .livePatch)
        #expect(throws: LLMProviderError.self) {
            _ = try decodeProviderOutput(from: fullSnapshotOutput, request: request, provider: .codexExec)
        }
    }

    @Test("live patch output은 previous snapshot에 patch를 merge한다")
    func livePatchMergesPatchOutput() throws {
        let patchOutput = """
        {
          "currentIssue": {
            "summary": "새 이슈",
            "openQuestions": []
          },
          "topicTimelineUpserts": [],
          "closeTopicIDs": [],
          "decisionCandidateUpserts": [],
          "actionItemCandidateUpserts": [],
          "risksOrNotesAppend": []
        }
        """
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:10] Alex: 새 내용",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 1
        )

        let snapshot = try decodeProviderOutput(from: patchOutput, request: request, provider: .codexExec)

        #expect(snapshot.currentIssue.summary == "새 이슈")
    }
}
