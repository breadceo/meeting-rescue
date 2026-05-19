import Foundation

public enum MeetingIntelligenceMarkdownExporter {
    public static func markdown(
        metadata: MeetingMetadata,
        sourceFileName: String,
        state: MeetingAnalysisState
    ) -> String {
        guard let snapshot = state.latestSnapshot else {
            return "# Meeting Intelligence\n\n아직 저장할 Meeting Intelligence가 없습니다.\n"
        }

        var lines: [String] = []
        lines.append("# \(metadata.displayTitle)")
        lines.append("")
        lines.append("- 일시: \(metadata.dateTime ?? "-")")
        lines.append("- 참석자: \(metadata.participants.isEmpty ? "-" : metadata.participants.joined(separator: ", "))")
        lines.append("- 파일: \(sourceFileName)")
        lines.append("- 생성: \(snapshot.generatedAt.formatted(date: .numeric, time: .standard))")
        lines.append("- Provider: \(snapshot.provider.displayName)")
        lines.append("")

        lines.append("## 현재 이슈")
        lines.append("")
        lines.append(snapshot.currentIssue.summary.isEmpty ? "-" : snapshot.currentIssue.summary)
        if !snapshot.currentIssue.openQuestions.isEmpty {
            lines.append("")
            lines.append("### 열린 질문")
            for question in snapshot.currentIssue.openQuestions {
                lines.append("- \(question)")
            }
        }
        lines.append("")

        lines.append("## 흐름")
        if snapshot.topicTimeline.isEmpty {
            lines.append("")
            lines.append("- 아직 topic timeline이 없습니다.")
        } else {
            for item in snapshot.topicTimeline {
                lines.append("")
                lines.append("### \(MeetingTimestampFormatter.displayRange(item.startTimestamp, endTimestamp: item.endTimestamp, meetingDateTime: metadata.dateTime)) \(item.title)")
                lines.append("")
                lines.append(item.summary)
            }
        }
        lines.append("")

        lines.append("## 결정 후보")
        appendDecisionCandidates(snapshot.decisionCandidates, to: &lines, metadata: metadata)
        lines.append("")

        lines.append("## 액션 후보")
        appendActionCandidates(snapshot.actionItemCandidates, to: &lines, metadata: metadata)
        lines.append("")

        lines.append("## Risks / Notes")
        if snapshot.risksOrNotes.isEmpty {
            lines.append("- 없음")
        } else {
            for note in snapshot.risksOrNotes {
                lines.append("- \(note)")
            }
        }
        lines.append("")

        lines.append("## LLM 사용량 추정")
        lines.append("")
        lines.append("- 누적 input tokens: \(state.usageSummary.totalInputTokens)")
        lines.append("- 누적 output tokens: \(state.usageSummary.totalOutputTokens)")
        lines.append("- 누적 추정 비용: \(String(format: "$%.6f", state.usageSummary.totalEstimatedCostUSD))")
        if let latest = state.usageSummary.latestSample {
            lines.append("- 최근 run: \(latest.modelName), input \(latest.inputTokens), output \(latest.outputTokens)")
        }
        lines.append("")

        lines.append("## Analysis 실행 로그")
        if state.attemptLogs.isEmpty {
            lines.append("- 아직 기록된 실행 로그가 없습니다.")
        } else {
            for attempt in state.attemptLogs.suffix(10) {
                let completed = attempt.completedAt?.formatted(date: .omitted, time: .standard) ?? "running"
                let duration = attempt.elapsedMilliseconds.map { " · \($0)ms" } ?? ""
                let batch = attempt.batchStats.map { " · \($0.compactSummary)" } ?? ""
                lines.append("- \(attempt.reason) · \(attempt.status.rawValue) · \(attempt.modelName) · \(completed)\(duration)\(batch)\(attempt.message.map { " · \($0)" } ?? "")")
            }
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func appendDecisionCandidates(_ candidates: [DecisionCandidate], to lines: inout [String], metadata: MeetingMetadata) {
        let visible = candidates.filter { $0.status != .deleted }
        if visible.isEmpty {
            lines.append("")
            lines.append("- 아직 반응할 결정 후보가 없습니다.")
            return
        }
        for candidate in visible {
            let evidence = evidenceText(candidate.evidenceTimestamp, speaker: candidate.speaker, metadata: metadata)
            lines.append("- [\(candidate.status.rawValue)] \(candidate.text) \(evidence)")
        }
    }

    private static func appendActionCandidates(_ candidates: [ActionItemCandidate], to lines: inout [String], metadata: MeetingMetadata) {
        let visible = candidates.filter { $0.status != .deleted }
        if visible.isEmpty {
            lines.append("")
            lines.append("- 아직 반응할 action item 후보가 없습니다.")
            return
        }
        for candidate in visible {
            let assignee = candidate.assignee.map { "@\($0) " } ?? ""
            let deadline = candidate.deadline.map { " / deadline: \($0)" } ?? ""
            let evidence = evidenceText(candidate.evidenceTimestamp, speaker: candidate.speaker, metadata: metadata)
            lines.append("- [\(candidate.status.rawValue)] \(assignee)\(candidate.task)\(deadline) \(evidence)")
        }
    }

    private static func evidenceText(_ timestamp: String, speaker: String?, metadata: MeetingMetadata) -> String {
        let elapsed = MeetingTimestampFormatter.display(timestamp, meetingDateTime: metadata.dateTime)
        let speaker = speaker.map { " · \($0)" } ?? ""
        return "(\(elapsed)\(speaker))"
    }
}
