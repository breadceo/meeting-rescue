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

    @Test("decision coach는 AI 결정 후보를 유효한 결정으로 사용한다")
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

        #expect(cards.map(\.kind).contains(.unconfirmedDecision) == false)
        #expect(cards.map(\.kind).contains(.missingCriteria))
        #expect(cards.map(\.kind).contains(.openQuestion))
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
                kind: .missingOwner,
                severity: .warning,
                title: "담당자 확인 필요",
                stuckPoint: "액션 담당자가 비어 있습니다.",
                minimumDecision: "담당자 지정",
                nextQuestion: "누가 맡나요?"
            )
        ]

        let warnings = PersonalWorkflowAnalyzer.shareReadinessWarnings(for: snapshot, coachCards: cards)

        #expect(warnings.map(\.kind).contains(.emptySummary))
        #expect(warnings.map(\.kind).contains(.unconfirmedDecision) == false)
        #expect(warnings.map(\.kind).contains(.missingActionOwner))
        #expect(warnings.map(\.kind).contains(.missingActionDeadline))
        #expect(warnings.map(\.kind).contains(.unresolvedDecisionCoachCard))
    }

    @Test("workflow 사용자 문구는 한글 기능명과 용어로 표시된다")
    func localizesPersonalWorkflowCopy() {
        let snapshot = AnalysisSnapshot(
            meetingType: .planning,
            meetingSummary: MeetingSummary(
                overview: "릴리즈 공유 방식을 논의했다.",
                openQuestions: [
                    MeetingSummaryItem(id: "q1", text: "릴리즈 승인자는 누구인가?")
                ]
            ),
            actionItemCandidates: [
                ActionItemCandidate(id: "a1", assignee: nil, task: "릴리즈 체크리스트 정리", deadline: nil, status: .confirmed, evidenceTimestamp: "00:30"),
                ActionItemCandidate(id: "a2", assignee: "Alex", task: "릴리즈 공지 초안 작성", status: .candidate, evidenceTimestamp: "00:40")
            ]
        )

        let cards = PersonalWorkflowAnalyzer.decisionCoachCards(for: snapshot)
        let warnings = PersonalWorkflowAnalyzer.shareReadinessWarnings(for: snapshot, coachCards: cards)
        let visibleCopy = (
            cards.flatMap { [$0.title, $0.stuckPoint, $0.minimumDecision, $0.nextQuestion] + $0.missingInfo }
                + warnings.flatMap { [$0.title, $0.detail] }
        ).joined(separator: " ")

        #expect(cards.first { $0.kind == .missingOwner }?.title == "담당자 없는 액션")
        #expect(warnings.first { $0.kind == .unconfirmedAction }?.title == "확정되지 않은 액션 후보")
        #expect(visibleCopy.contains("owner") == false)
        #expect(visibleCopy.contains("action") == false)
        #expect(visibleCopy.contains("follow-up") == false)
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
            metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-10 10:00", participants: ["Alex", "Blair"]),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "Launch 준비"))
        )
        let previous = CarryOverMeetingSource(
            meetingID: "previous",
            sourceFileName: "previous.txt",
            metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-03 10:00", participants: ["Alex"]),
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
        #expect(all[0].reason == "반복 회의 이전 회차")
        #expect(all[0].category == .recurring)
        #expect(hidden.isEmpty)
    }

    @Test("carry-over는 같은 room의 주간 회의면 minute이 달라도 반복 회의로 본다")
    func treatsSameRoomWeeklyMeetingInSameHourAsRecurring() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3", dateTime: "2026-06-04 12:31", participants: ["Ethan"]),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "햄버거 메뉴 정리"))
        )
        let previous = CarryOverMeetingSource(
            meetingID: "previous",
            sourceFileName: "previous.txt",
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3", dateTime: "2026-05-28 12:03", participants: ["Ethan"]),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(openQuestions: [
                    MeetingSummaryItem(id: "q1", text: "상단 써머리 섹션을 어느 수준까지 핵심만 담도록 재구성할지?")
                ])
            )
        )

        let candidates = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previous],
            dismissedIDs: [],
            resolvedIDs: []
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.reason == "반복 회의 이전 회차")
        #expect(candidates.first?.category == .recurring)
    }

    @Test("carry-over는 같은 room의 주간 회의가 인접 hour여도 30분 이내면 반복 회의로 본다")
    func treatsSameRoomWeeklyMeetingWithinThirtyMinutesAsRecurring() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3", dateTime: "2026-06-04 13:05", participants: ["Ethan"]),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "햄버거 메뉴 정리"))
        )
        let previous = CarryOverMeetingSource(
            meetingID: "previous",
            sourceFileName: "previous.txt",
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3", dateTime: "2026-05-28 12:45", participants: ["Ethan"]),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(openQuestions: [
                    MeetingSummaryItem(id: "q1", text: "상단 써머리 섹션을 어느 수준까지 핵심만 담도록 재구성할지?")
                ])
            )
        )

        let candidates = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previous],
            dismissedIDs: [],
            resolvedIDs: []
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.reason == "반복 회의 이전 회차")
        #expect(candidates.first?.category == .recurring)
    }

    @Test("carry-over는 room이 다르면 같은 주간 시간대여도 반복 회의로 보지 않는다")
    func doesNotTreatDifferentRoomWeeklyMeetingAsRecurring() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3", dateTime: "2026-06-04 12:31"),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "햄버거 메뉴 정리"))
        )
        let previous = CarryOverMeetingSource(
            meetingID: "previous",
            sourceFileName: "previous.txt",
            metadata: MeetingMetadata(room: "Zigbang(2F)", dateTime: "2026-05-28 12:03"),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(openQuestions: [
                    MeetingSummaryItem(id: "q1", text: "상단 써머리 섹션을 어느 수준까지 핵심만 담도록 재구성할지?")
                ])
            )
        )

        let candidates = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previous],
            dismissedIDs: [],
            resolvedIDs: []
        )

        #expect(candidates.isEmpty)
    }

    @Test("carry-over는 반복 회의가 아니면 같은 room만으로 이전 질문을 붙이지 않는다")
    func ignoresSameRoomWhenNotRecurring() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-10 10:00"),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "이번 주 릴리즈 상태"))
        )
        let previousSameRoom = CarryOverMeetingSource(
            meetingID: "previous",
            sourceFileName: "previous.txt",
            metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-09 10:00"),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(openQuestions: [
                    MeetingSummaryItem(id: "q1", text: "어제 회의 질문은 무엇인가?")
                ])
            )
        )

        let candidates = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previousSameRoom],
            dismissedIDs: [],
            resolvedIDs: []
        )

        #expect(candidates.isEmpty)
    }

    @Test("carry-over는 오래된 같은 room이나 participant만으로 이전 질문을 붙이지 않는다")
    func ignoresStaleRoomOrParticipantOnlyCarryOverCandidates() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Weekly", participants: ["Alex", "Blair"]),
            occurredAt: Date(timeIntervalSince1970: 10_000_000),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "이번 주 릴리즈 상태"))
        )
        let staleSameRoom = CarryOverMeetingSource(
            meetingID: "stale-room",
            sourceFileName: "stale-room.txt",
            metadata: MeetingMetadata(room: "Weekly", participants: ["Alex"]),
            occurredAt: Date(timeIntervalSince1970: 10_000_000 - 60 * 86_400),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(openQuestions: [
                    MeetingSummaryItem(id: "q1", text: "오래된 주간 질문은 무엇인가?")
                ])
            )
        )

        let candidates = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [staleSameRoom],
            dismissedIDs: [],
            resolvedIDs: []
        )

        #expect(candidates.isEmpty)
    }

    @Test("carry-over는 최근 기타 회의에서 participant와 topic이 함께 맞으면 유지한다")
    func keepsRecentRelatedCarryOverWithParticipantAndTopicOverlap() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Ad hoc", dateTime: "2026-06-10 10:00", participants: ["Alex", "Blair"]),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "Calendar MCP 인증 경로를 다시 검토한다."))
        )
        let previousSpot = CarryOverMeetingSource(
            meetingID: "previous-spot",
            sourceFileName: "previous-spot.txt",
            metadata: MeetingMetadata(room: "Support", dateTime: "2026-06-04 13:00", participants: ["Alex"]),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(
                    overview: "Calendar MCP 인증 경로가 막혔다.",
                    openQuestions: [
                        MeetingSummaryItem(id: "q1", text: "Codex MCP 인증은 어떤 방식으로 우회할 수 있는가?")
                    ]
                )
            )
        )

        let candidates = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previousSpot],
            dismissedIDs: [],
            resolvedIDs: []
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.reason == "최근 참석자/주제 일치")
        #expect(candidates.first?.category == .related)
    }

    @Test("carry-over는 오래된 기타 회의의 participant/topic match를 붙이지 않는다")
    func ignoresStaleRelatedCarryOverWithParticipantAndTopicOverlap() {
        let current = CarryOverMeetingSource(
            meetingID: "current",
            sourceFileName: "current.txt",
            metadata: MeetingMetadata(room: "Ad hoc", dateTime: "2026-06-10 10:00", participants: ["Alex", "Blair"]),
            snapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "Calendar MCP 인증 경로를 다시 검토한다."))
        )
        let previousSpot = CarryOverMeetingSource(
            meetingID: "previous-spot",
            sourceFileName: "previous-spot.txt",
            metadata: MeetingMetadata(room: "Support", dateTime: "2026-04-26 13:00", participants: ["Alex"]),
            snapshot: AnalysisSnapshot(
                meetingSummary: MeetingSummary(
                    overview: "Calendar MCP 인증 경로가 막혔다.",
                    openQuestions: [
                        MeetingSummaryItem(id: "q1", text: "Codex MCP 인증은 어떤 방식으로 우회할 수 있는가?")
                    ]
                )
            )
        )

        let candidates = PersonalWorkflowAnalyzer.openQuestionCarryOverCandidates(
            current: current,
            previous: [previousSpot],
            dismissedIDs: [],
            resolvedIDs: []
        )

        #expect(candidates.isEmpty)
    }
}
