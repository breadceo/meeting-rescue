import Testing
@testable import MeetingRescueCore

@Suite("Markdown exporter")
struct MarkdownExporterTests {
    @Test("Meeting Intelligence markdown은 elapsed timestamp와 usage를 포함한다")
    func exportsMarkdown() {
        let metadata = MeetingMetadata(
            room: "Room A",
            dateTime: "2025-12-29 17:01:15",
            participants: ["A", "B"]
        )
        var state = MeetingAnalysisState(
            latestSnapshot: AnalysisSnapshot(
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

        #expect(markdown.contains("## 현재 이슈"))
        #expect(markdown.contains("[04:13]"))
        #expect(markdown.contains("수정된 결정"))
        #expect(markdown.contains("@B 수정된 액션 / deadline: 월요일"))
        #expect(markdown.contains("누적 input tokens: 10"))
    }
}
