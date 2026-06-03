import Foundation
import Testing
@testable import MeetingRescueCore

struct PersonalWorkflowAnalyzerTests {
    @Test("carry-over 상태는 MeetingAnalysisState에 저장되고 decode된다")
    func persistsCarryOverQuestionStatus() throws {
        var state = MeetingAnalysisState()
        state.setCarryOverQuestionStatus(id: "carry-over-a", status: .dismissed)
        state.setCarryOverQuestionStatus(id: "carry-over-b", status: .resolved)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingAnalysisState.self, from: data)

        #expect(decoded.dismissedCarryOverQuestionIDs == ["carry-over-a"])
        #expect(decoded.resolvedCarryOverQuestionIDs == ["carry-over-b"])
    }

    @Test("legacy analysis state는 carry-over 상태 없이도 decode된다")
    func decodesLegacyAnalysisStateWithoutCarryOverSets() throws {
        let json = """
        {
          "latestSnapshot": null,
          "confirmedCandidateIDs": [],
          "deletedCandidateIDs": [],
          "decisionCandidateEdits": {},
          "actionItemCandidateEdits": {},
          "updatedAt": "2026-06-03T00:00:00Z",
          "isCompleted": false,
          "usageSummary": {
            "totalInputTokens": 0,
            "totalOutputTokens": 0,
            "totalEstimatedCostUSD": 0,
            "samples": []
          },
          "attemptLogs": [],
          "analyzedTranscriptCharacterCount": 0,
          "bookmarks": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingAnalysisState.self, from: Data(json.utf8))

        #expect(decoded.dismissedCarryOverQuestionIDs.isEmpty)
        #expect(decoded.resolvedCarryOverQuestionIDs.isEmpty)
    }

    @Test("decision coach는 미확정 결정과 부족한 기준을 decision card로 만든다")
    func createsDecisionCoachCards() {
        let snapshot = AnalysisSnapshot(
            meetingType: .decision,
            meetingSummary: MeetingSummary(
                overview: "배포 방식을 논의했다.",
                openQuestions: [
                    MeetingSummaryItem(
                        id: "q1",
                        text: "최종 배포 방식은 무엇인가?",
                        evidence: [
                            EvidenceReference(timestamp: "00:12", speaker: "Alex", excerpt: "아직 최종 방식은 없네요.")
                        ]
                    )
                ]
            ),
            currentIssue: CurrentIssue(summary: "금요일 배포 방식 결정을 논의 중이다."),
            topicTimeline: [
                TopicTimelineItem(id: "t1", startTimestamp: "00:01", title: "배포", summary: "배포 방식 논의")
            ],
            decisionCandidates: [
                DecisionCandidate(id: "d1", text: "금요일에 배포한다.", status: .candidate, evidenceTimestamp: "00:20", speaker: "Blair")
            ],
            actionItemCandidates: []
        )

        let cards = PersonalWorkflowAnalyzer.decisionCoachCards(for: snapshot)

        #expect(cards.map(\.kind).contains(.unconfirmedDecision))
        #expect(cards.map(\.kind).contains(.missingCriteria))
        #expect(cards.map(\.kind).contains(.openQuestion))
        #expect(cards.first { $0.kind == .unconfirmedDecision }?.minimumDecision.contains("금요일에 배포한다.") == true)
    }

    @Test("share readiness는 공유 전 수정할 warning을 계산한다")
    func createsShareReadinessWarnings() {
        let snapshot = AnalysisSnapshot(
            meetingType: .planning,
            meetingSummary: MeetingSummary(),
            decisionCandidates: [
                DecisionCandidate(id: "d1", text: "일정을 다음 주로 미룬다.", status: .candidate, evidenceTimestamp: "00:20")
            ],
            actionItemCandidates: [
                ActionItemCandidate(id: "a1", assignee: nil, task: "릴리즈 체크리스트 정리", deadline: nil, status: .confirmed, evidenceTimestamp: "00:30")
            ]
        )
        let cards = [
            DecisionCoachCard(
                id: "coach-1",
                kind: .unconfirmedDecision,
                severity: .warning,
                title: "결정 확인 필요",
                stuckPoint: "결정 후보가 확정되지 않았습니다.",
                minimumDecision: "일정을 다음 주로 미룰지 결정",
                nextQuestion: "이 결정을 확정할까요?"
            )
        ]

        let warnings = PersonalWorkflowAnalyzer.shareReadinessWarnings(for: snapshot, coachCards: cards)

        #expect(warnings.map(\.kind).contains(.emptySummary))
        #expect(warnings.map(\.kind).contains(.unconfirmedDecision))
        #expect(warnings.map(\.kind).contains(.missingActionOwner))
        #expect(warnings.map(\.kind).contains(.missingActionDeadline))
        #expect(warnings.map(\.kind).contains(.unresolvedDecisionCoachCard))
    }

    @Test("action ledger는 confirmed action만 회의 source와 함께 모은다")
    func createsActionLedgerItems() {
        let source = ActionLedgerMeetingSource(
            meetingID: "meeting-a",
            sourceFileName: "meeting-a.txt",
            metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-03 10:00", participants: ["Alex"]),
            snapshot: AnalysisSnapshot(
                actionItemCandidates: [
                    ActionItemCandidate(id: "a1", assignee: "Alex", task: "공유 초안 작성", deadline: "금요일", status: .confirmed, evidenceTimestamp: "00:30", speaker: "Blair"),
                    ActionItemCandidate(id: "a2", assignee: "Casey", task: "후보 정리", status: .candidate, evidenceTimestamp: "00:40")
                ]
            )
        )

        let items = PersonalWorkflowAnalyzer.actionLedgerItems(from: [source])

        #expect(items.map(\.id) == ["meeting-a:a1"])
        #expect(items.first?.task == "공유 초안 작성")
        #expect(items.first?.meetingTitle == "Launch")
    }

    @Test("carry-over는 관련 history의 열린 질문을 후보로 만들고 dismissed 항목을 숨긴다")
    func createsCarryOverCandidates() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Launch", participants: ["Alex", "Blair"]),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "Launch 준비"))
        )
        let previous = CarryOverMeetingSource(
            meetingID: "previous",
            sourceFileName: "previous.txt",
            metadata: MeetingMetadata(room: "Launch", participants: ["Alex"]),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(
                    overview: "Launch 준비",
                    openQuestions: [
                        MeetingSummaryItem(
                            id: "q1",
                            text: "Slack 공유 대상은 누구인가?",
                            evidence: [
                                EvidenceReference(timestamp: "00:44", speaker: "Alex", excerpt: "공유 대상은 아직 없네요.")
                            ]
                        )
                    ]
                )
            )
        )

        let all = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previous],
            dismissedIDs: [],
            resolvedIDs: []
        )
        let hidden = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previous],
            dismissedIDs: [all[0].id],
            resolvedIDs: []
        )

        #expect(all.count == 1)
        #expect(all[0].question == "Slack 공유 대상은 누구인가?")
        #expect(all[0].reason.contains("room") == true)
        #expect(hidden.isEmpty)
    }
}
