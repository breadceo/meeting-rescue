import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("LLM provider output")
struct LLMProviderOutputTests {
    @Test("full snapshot provider output은 D0 meeting summary contract를 decode한다")
    func fullSnapshotDecodesD0Contract() throws {
        let output = """
        {
          "meetingType": "decision",
          "meetingSummary": {
            "overview": "배포 방식을 결정하는 회의다.",
            "keyPoints": [
              {
                "id": "summary-release",
                "text": "금요일 배포로 수렴했다.",
                "evidence": [
                  {
                    "timestamp": "00:10",
                    "speaker": "Alex",
                    "excerpt": "금요일 배포로 갑시다."
                  }
                ]
              }
            ],
            "openQuestions": []
          },
          "currentIssue": {
            "summary": "배포 owner 확인이 남았다.",
            "openQuestions": ["owner는 누구인가?"]
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
            rawTranscript: "[00:10] Alex: 금요일 배포로 갑시다.",
            reason: "final"
        )

        let snapshot = try decodeProviderOutput(from: output, request: request, provider: .codexExec)

        #expect(snapshot.meetingType == .decision)
        #expect(snapshot.meetingSummary.keyPoints.first?.evidence.first?.speaker == "Alex")
        #expect(snapshot.provider == .codexExec)
    }

    @Test("live patch provider output은 nullable D0 fields를 merge한다")
    func livePatchMergesNullableD0Fields() throws {
        let output = """
        {
          "meetingType": "planning",
          "meetingSummary": {
            "overview": "계획 범위가 새로 정리됐다.",
            "keyPoints": [],
            "openQuestions": [
              {
                "id": "question-owner",
                "text": "디자인 owner를 확정해야 한다.",
                "evidence": [
                  {
                    "timestamp": "01:40",
                    "speaker": "Blair",
                    "excerpt": "디자인 owner는 아직 비어 있습니다."
                  }
                ]
              }
            ]
          },
          "currentIssue": null,
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
            rawTranscript: "[01:40] Blair: 디자인 owner는 아직 비어 있습니다.",
            previousSnapshot: AnalysisSnapshot(
                meetingType: .automatic,
                meetingSummary: MeetingSummary(overview: "이전 요약"),
                currentIssue: CurrentIssue(summary: "기존 요약")
            ),
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 1
        )

        let snapshot = try decodeProviderOutput(from: output, request: request, provider: .claudeCode)

        #expect(snapshot.meetingType == .planning)
        #expect(snapshot.meetingSummary.overview == "계획 범위가 새로 정리됐다.")
        #expect(snapshot.meetingSummary.openQuestions.first?.evidence.first?.timestamp == "01:40")
    }

    @Test("manual meeting type preset overrides provider meeting type")
    func manualMeetingTypePresetOverridesProviderOutput() throws {
        let output = """
        {
          "meetingType": "status",
          "meetingSummary": {
            "overview": "상태 공유처럼 응답했지만 사용자는 incident로 지정했다.",
            "keyPoints": [],
            "openQuestions": []
          },
          "currentIssue": {
            "summary": "장애 원인 확인",
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
            rawTranscript: "[00:10] Alex: 장애 원인을 봅니다.",
            meetingTypePreset: .incident,
            reason: "final"
        )

        let snapshot = try decodeProviderOutput(from: output, request: request, provider: .codexExec)

        #expect(snapshot.meetingType == .incident)
    }

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
          "meetingType": null,
          "meetingSummary": null,
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

    @Test("빈 baseline currentIssue에 null patch가 오면 patch 근거로 현재 이슈를 보강한다")
    func livePatchBackfillsEmptyCurrentIssueFromPatchEvidence() throws {
        let patchOutput = """
        {
          "meetingType": null,
          "meetingSummary": null,
          "currentIssue": null,
          "topicTimelineUpserts": [
            {
              "id": "topic-landlord-onboarding",
              "startTimestamp": "00:10",
              "endTimestamp": "01:20",
              "title": "임대인 온보딩",
              "summary": "임차인 모드에서 임대인 모드로 전환할 때 소개 페이지와 FAQ 이미지를 추가하는 방향을 논의했다."
            }
          ],
          "closeTopicIDs": [],
          "decisionCandidateUpserts": [],
          "actionItemCandidateUpserts": [],
          "risksOrNotesAppend": []
        }
        """
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:10] Alex: 임대인 온보딩 소개 페이지를 봅니다.",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "")),
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 0
        )

        let snapshot = try decodeProviderOutput(from: patchOutput, request: request, provider: .codexExec)

        #expect(snapshot.currentIssue.summary == "임차인 모드에서 임대인 모드로 전환할 때 소개 페이지와 FAQ 이미지를 추가하는 방향을 논의했다.")
    }

    @Test("live patch timeline endTimestamp가 없으면 현재 batch 마지막 발화로 보정한다")
    func livePatchBackfillsMissingTimelineEndTimestamp() throws {
        let patchOutput = """
        {
          "meetingType": null,
          "meetingSummary": null,
          "currentIssue": null,
          "topicTimelineUpserts": [
            {
              "id": "topic-docs",
              "startTimestamp": "00:20",
              "endTimestamp": null,
              "title": "문서 구조 논의",
              "summary": "문서 구조를 논의했다."
            }
          ],
          "closeTopicIDs": [],
          "decisionCandidateUpserts": [],
          "actionItemCandidateUpserts": [],
          "risksOrNotesAppend": []
        }
        """
        let previousText = "[00:10] Alex: 이전 내용입니다."
        let newText = """
        [00:20] Alex: 문서 구조를 봅니다.
        [00:40] Blair: 디렉토리 기준도 같이 봅니다.
        [00:55][SYSTEM] 대화 기록 종료
        """
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: previousText + "\n" + newText,
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: previousText.count
        )

        let snapshot = try decodeProviderOutput(from: patchOutput, request: request, provider: .codexExec)

        #expect(snapshot.topicTimeline.first?.endTimestamp == "00:40")
    }

    @Test("live patch timeline endTimestamp가 빈 문자열이면 startTimestamp로 fallback한다")
    func livePatchBackfillsEmptyTimelineEndTimestamp() throws {
        let patchOutput = """
        {
          "meetingType": null,
          "meetingSummary": null,
          "currentIssue": null,
          "topicTimelineUpserts": [
            {
              "id": "topic-docs",
              "startTimestamp": "00:20",
              "endTimestamp": "",
              "title": "문서 구조 논의",
              "summary": "문서 구조를 논의했다."
            }
          ],
          "closeTopicIDs": [],
          "decisionCandidateUpserts": [],
          "actionItemCandidateUpserts": [],
          "risksOrNotesAppend": []
        }
        """
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[SYSTEM] no dialogue",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 0
        )

        let snapshot = try decodeProviderOutput(from: patchOutput, request: request, provider: .codexExec)

        #expect(snapshot.topicTimeline.first?.endTimestamp == "00:20")
    }
}
