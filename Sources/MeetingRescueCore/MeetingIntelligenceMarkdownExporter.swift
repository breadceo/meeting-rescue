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

        appendMeetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType, to: &lines, metadata: metadata)
        lines.append("")

        lines.append("## 현재 논점")
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

        return lines.joined(separator: "\n")
    }

    private static func appendMeetingSummary(
        _ summary: MeetingSummary,
        meetingType: MeetingTypePreset,
        to lines: inout [String],
        metadata: MeetingMetadata
    ) {
        lines.append("## 회의 요약")
        lines.append("")
        lines.append("- 유형: \(meetingType.displayName)")
        lines.append("")
        lines.append(summary.overview.isEmpty ? "-" : summary.overview)

        if !summary.keyPoints.isEmpty {
            lines.append("")
            lines.append("### 핵심 포인트")
            for item in summary.keyPoints {
                lines.append("- \(item.text) \(summaryEvidenceText(item.evidence, metadata: metadata))")
            }
        }

        if !summary.openQuestions.isEmpty {
            lines.append("")
            lines.append("### 열린 질문")
            for item in summary.openQuestions {
                lines.append("- \(item.text) \(summaryEvidenceText(item.evidence, metadata: metadata))")
            }
        }
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

    private static func summaryEvidenceText(_ evidence: [EvidenceReference], metadata: MeetingMetadata) -> String {
        guard let first = evidence.first else {
            return ""
        }
        let elapsed = MeetingTimestampFormatter.display(first.timestamp, meetingDateTime: metadata.dateTime)
        let speaker = first.speaker.map { " · \($0)" } ?? ""
        let excerpt = first.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerptText = excerpt.isEmpty ? "" : " · \(excerpt)"
        return "(\(elapsed)\(speaker)\(excerptText))"
    }
}
