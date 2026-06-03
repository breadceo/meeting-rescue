import Testing
@testable import MeetingRescueCore

@Suite("Markdown exporter")
struct MarkdownExporterTests {
    @Test("Meeting Intelligence markdown은 elapsed timestamp를 포함하고 내부 usage/log는 제외한다")
    func exportsMarkdown() {
        let metadata = MeetingMetadata(
            room: "Room A",
            dateTime: "2025-12-29 17:01:15",
            participants: ["A", "B"]
        )
        var state = MeetingAnalysisState(
            latestSnapshot: AnalysisSnapshot(
                meetingType: .decision,
                meetingSummary: MeetingSummary(
                    overview: "배포 방식과 follow-up을 정리한 회의다.",
                    keyPoints: [
                        MeetingSummaryItem(
                            id: "summary-release",
                            text: "금요일 배포로 수렴했다.",
                            evidence: [
                                EvidenceReference(
                                    timestamp: "00:10",
                                    speaker: "A",
                                    excerpt: "금요일 배포로 진행합니다."
                                )
                            ]
                        )
                    ],
                    openQuestions: [
                        MeetingSummaryItem(
                            id: "question-owner",
                            text: "롤백 owner를 확정해야 한다.",
                            evidence: [
                                EvidenceReference(
                                    timestamp: "00:20",
                                    speaker: "B",
                                    excerpt: "롤백 owner는 아직 없습니다."
                                )
                            ]
                        )
                    ]
                ),
                currentIssue: CurrentIssue(summary: "요약"),
                topicTimeline: [
                    TopicTimelineItem(
                        id: "topic-1",
                        startTimestamp: "2025-12-29T17:05:28Z",
                        title: "논의",
                        summary: "내용"
                    )
                ],
                decisionCandidates: [
                    DecisionCandidate(id: "decision-1", text: "원문 결정", status: .confirmed, evidenceTimestamp: "00:10")
                ],
                actionItemCandidates: [
                    ActionItemCandidate(id: "action-1", assignee: "A", task: "원문 액션", deadline: "금요일", status: .confirmed, evidenceTimestamp: "00:20")
                ]
            )
        )
        state.editDecisionCandidate(id: "decision-1", text: "수정된 결정")
        state.editActionItemCandidate(id: "action-1", assignee: "B", task: "수정된 액션", deadline: "월요일")
        state.appendUsage(
            LLMUsageSample(
                provider: .codexExec,
                modelPreset: .economy,
                modelName: "gpt-5.4-mini",
                inputTokens: 10,
                outputTokens: 5,
                inputPricePerMillionUSD: 0.375,
                outputPricePerMillionUSD: 2.25,
                estimatedCostUSD: 0.00001
            )
        )

        let markdown = MeetingIntelligenceMarkdownExporter.markdown(
            metadata: metadata,
            sourceFileName: "meeting.txt",
            state: state
        )

        #expect(markdown.contains("## 회의 요약"))
        #expect(markdown.contains("- 유형: Decision"))
        #expect(markdown.contains("배포 방식과 follow-up을 정리한 회의다."))
        #expect(markdown.contains("- 금요일 배포로 수렴했다. ([00:10] · A · 금요일 배포로 진행합니다.)"))
        #expect(markdown.contains("### 열린 질문"))
        #expect(markdown.contains("- 롤백 owner를 확정해야 한다. ([00:20] · B · 롤백 owner는 아직 없습니다.)"))
        #expect(markdown.contains("## 현재 논점"))
        #expect(!markdown.contains("## 현재 이슈"))
        #expect(markdown.contains("[04:13]"))
        #expect(markdown.contains("수정된 결정"))
        #expect(markdown.contains("@B 수정된 액션 / deadline: 월요일"))
        #expect(!markdown.contains("## LLM 사용량 추정"))
        #expect(!markdown.contains("누적 input tokens: 10"))
        #expect(!markdown.contains("## Analysis 실행 로그"))
    }
}
