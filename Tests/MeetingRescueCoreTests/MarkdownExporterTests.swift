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
                perspectiveAlignments: [
                    PerspectiveAlignment(
                        id: "alignment-release-scope",
                        topic: "실험 기능 릴리즈 범위",
                        axis: "속도와 안정성의 균형",
                        sharedGround: "이번 주 안에 범위를 정해야 한다.",
                        nextQuestion: "오늘 결정할 최소 릴리즈 범위는 어디까지인가?",
                        perspectives: [
                            PerspectivePosition(
                                speaker: "A",
                                summary: "이번 릴리즈에 포함해야 한다.",
                                reasoning: "피드백을 빨리 받아야 한다.",
                                evidence: [
                                    EvidenceReference(
                                        timestamp: "00:30",
                                        speaker: "A",
                                        excerpt: "이번에 넣죠."
                                    )
                                ]
                            ),
                            PerspectivePosition(
                                speaker: "B",
                                summary: "다음 릴리즈로 미뤄야 한다.",
                                reasoning: "QA 시간이 부족하다.",
                                evidence: [
                                    EvidenceReference(
                                        timestamp: "00:40",
                                        speaker: "B",
                                        excerpt: "QA가 부족해요."
                                    )
                                ]
                            )
                        ]
                    )
                ],
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
        #expect(markdown.contains("## 관점 정렬"))
        #expect(markdown.contains("### 실험 기능 릴리즈 범위"))
        #expect(markdown.contains("- 축: 속도와 안정성의 균형"))
        #expect(markdown.contains("- 공통 전제: 이번 주 안에 범위를 정해야 한다."))
        #expect(markdown.contains("- A: 이번 릴리즈에 포함해야 한다. / 근거: 피드백을 빨리 받아야 한다. ([00:30] · A · 이번에 넣죠.)"))
        #expect(markdown.contains("- 정렬 질문: 오늘 결정할 최소 릴리즈 범위는 어디까지인가?"))
        let currentIssueRange = markdown.range(of: "## 현재 논점")
        let alignmentRange = markdown.range(of: "## 관점 정렬")
        let flowRange = markdown.range(of: "## 흐름")
        #expect(currentIssueRange != nil)
        #expect(alignmentRange != nil)
        #expect(flowRange != nil)
        if let currentIssueRange, let alignmentRange, let flowRange {
            #expect(currentIssueRange.lowerBound < alignmentRange.lowerBound)
            #expect(alignmentRange.lowerBound < flowRange.lowerBound)
        }
        #expect(markdown.contains("[04:13]"))
        #expect(markdown.contains("수정된 결정"))
        #expect(markdown.contains("@B 수정된 액션 / deadline: 월요일"))
        #expect(!markdown.contains("## LLM 사용량 추정"))
        #expect(!markdown.contains("누적 input tokens: 10"))
        #expect(!markdown.contains("## Analysis 실행 로그"))
    }
}
