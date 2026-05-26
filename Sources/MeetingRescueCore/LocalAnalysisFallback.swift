import Foundation

public enum LocalAnalysisFallback {
    public static func isFallbackSnapshot(_ snapshot: AnalysisSnapshot?) -> Bool {
        guard let snapshot else {
            return false
        }
        if snapshot.currentIssue.summary.hasPrefix("LLM provider 결과를 아직 받지 못해 로컬 fallback") {
            return true
        }
        if snapshot.currentIssue.summary.hasPrefix("초기 1분 이후 live patch 분석을 기다리는 중입니다.") {
            return true
        }
        return snapshot.risksOrNotes.contains { $0.hasPrefix("Fallback reason:") }
    }

    public static func snapshot(for request: AnalysisRequest, message: String) -> AnalysisSnapshot {
        let parsed = TranscriptParser.parse(request.rawTranscript)
        let dialogue = parsed.dialogueLines
        let lastLines = dialogue.suffix(80)
        let speakerCounts = Dictionary(grouping: lastLines, by: \.speaker)
            .mapValues(\.count)
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }

        let summary: String
        if let latest = dialogue.last {
            summary = "LLM provider 결과를 아직 받지 못해 로컬 fallback으로 표시합니다. 최근 발화는 \(latest.speaker)의 “\(latest.text)”입니다."
        } else {
            summary = "LLM provider 결과를 아직 받지 못해 로컬 fallback으로 표시합니다. 아직 분석할 dialogue line이 충분하지 않습니다."
        }

        let timeline = makeTimeline(from: dialogue)
        let speakerNote = speakerCounts.prefix(4)
            .map { "\($0.key) \($0.value)회" }
            .joined(separator: ", ")

        return AnalysisSnapshot(
            currentIssue: CurrentIssue(
                summary: summary,
                openQuestions: ["LLM provider 연결 또는 schema 오류를 확인해야 합니다."]
            ),
            topicTimeline: timeline,
            decisionCandidates: [],
            actionItemCandidates: [],
            risksOrNotes: [
                "Fallback reason: \(message)",
                speakerNote.isEmpty ? "최근 speaker 정보를 아직 만들 수 없습니다." : "최근 주요 speaker: \(speakerNote)"
            ],
            provider: request.providerKind
        )
    }

    private static func makeTimeline(from dialogue: [DialogueLine]) -> [TopicTimelineItem] {
        guard !dialogue.isEmpty else {
            return []
        }

        let chunks = dialogue.chunked(into: 25)
        return chunks.enumerated().map { index, lines in
            let first = lines.first
            let last = lines.last
            let titleSpeaker = first?.speaker ?? "Unknown"
            let summaryText = lines.prefix(3)
                .map { "\($0.speaker): \($0.text)" }
                .joined(separator: " / ")
            return TopicTimelineItem(
                id: "local-topic-\(index + 1)-\(first?.timestamp ?? "0")",
                startTimestamp: first?.timestamp ?? "",
                endTimestamp: last?.timestamp,
                title: "\(titleSpeaker) 중심 구간",
                summary: summaryText
            )
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return []
        }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
