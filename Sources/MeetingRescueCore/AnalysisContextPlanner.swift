import Foundation

public enum AnalysisContextPlanner {
    private static let recentContextCharacterLimit = 500

    public static func makePlan(
        for request: AnalysisRequest,
        retrievalMode: LiveContextRetrievalMode,
        liveIndex: LiveTranscriptIndex
    ) -> AnalysisContextPlan {
        let started = Date()
        let newTranscript = newTranscriptText(for: request)
        let query = retrievalQuery(for: request, newTranscript: newTranscript)
        let topK = request.lastAnalyzedTranscriptCharacterCount > 0
            ? topK(for: request.modelPreset, mode: retrievalMode)
            : 0
        let retrievedChunks: [RetrievedTranscriptChunk]
        switch retrievalMode {
        case .off:
            retrievedChunks = []
        case .memoryLiveIndex:
            retrievedChunks = liveIndex.retrieve(
                queryText: query,
                excludingText: newTranscript,
                topK: topK
            )
        }
        let elapsedMilliseconds = max(0, Int(Date().timeIntervalSince(started) * 1_000))
        let participantCount = request.metadata.participants.count
        let speakingParticipants = speakers(in: request.rawTranscript)
        return AnalysisContextPlan(
            retrievalMode: retrievalMode,
            retrievalTopK: topK,
            retrievalLatencyMilliseconds: elapsedMilliseconds,
            retrievedChunks: retrievedChunks,
            speakingParticipantCount: speakingParticipants.count,
            metadataParticipantCount: participantCount,
            omittedParticipantCount: max(0, participantCount - speakingParticipants.count),
            newTranscriptCharacters: newTranscript.count,
            newDialogueLines: dialogueLineCount(in: newTranscript),
            recentContextCharacters: recentContextCharacters(for: request),
            estimatedPromptTokens: 0
        )
    }

    public static func planByUpdatingEstimatedTokens(
        _ plan: AnalysisContextPlan?,
        estimatedPromptTokens: Int
    ) -> AnalysisContextPlan? {
        guard var plan else {
            return nil
        }
        plan.estimatedPromptTokens = estimatedPromptTokens
        return plan
    }

    private static func topK(for preset: LLMModelPreset, mode: LiveContextRetrievalMode) -> Int {
        guard mode != .off else {
            return 0
        }
        switch preset {
        case .automatic, .balanced:
            return 2
        case .economy:
            return 1
        case .frontier:
            return 3
        }
    }

    private static func newTranscriptText(for request: AnalysisRequest) -> String {
        let rawTranscript = request.rawTranscript
        let rawCount = rawTranscript.count
        let clampedAnalyzedCount = min(max(0, request.lastAnalyzedTranscriptCharacterCount), rawCount)
        guard clampedAnalyzedCount > 0 else {
            return promptDialogueText(from: rawTranscript)
        }
        let startIndex = rawTranscript.index(rawTranscript.startIndex, offsetBy: clampedAnalyzedCount)
        return promptDialogueText(from: String(rawTranscript[startIndex...]))
    }

    private static func recentContextCharacters(for request: AnalysisRequest) -> Int {
        let rawTranscript = request.rawTranscript
        let rawCount = rawTranscript.count
        let clampedAnalyzedCount = min(max(0, request.lastAnalyzedTranscriptCharacterCount), rawCount)
        guard clampedAnalyzedCount > 0 else {
            return 0
        }
        let analyzedIndex = rawTranscript.index(rawTranscript.startIndex, offsetBy: clampedAnalyzedCount)
        let previousTranscript = String(rawTranscript[..<analyzedIndex])
        return min(previousTranscript.count, recentContextCharacterLimit)
    }

    private static func retrievalQuery(for request: AnalysisRequest, newTranscript: String) -> String {
        var parts = [newTranscript]
        if let snapshot = request.previousSnapshot {
            parts.append(snapshot.currentIssue.summary)
            parts.append(contentsOf: snapshot.topicTimeline.suffix(3).flatMap { [$0.title, $0.summary] })
            parts.append(contentsOf: snapshot.decisionCandidates.suffix(3).map(\.text))
            parts.append(contentsOf: snapshot.actionItemCandidates.suffix(3).map(\.task))
        }
        return parts.joined(separator: "\n")
    }

    private static func promptDialogueText(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .compactMap(promptDialogueLine)
        guard !lines.isEmpty else {
            return text
        }
        return lines.joined(separator: "\n")
    }

    private static func promptDialogueLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closeBracket = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let timestamp = String(trimmed[trimmed.startIndex...closeBracket])
        let remainder = trimmed[trimmed.index(after: closeBracket)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = remainder.firstIndex(of: ":") else {
            return nil
        }
        let speaker = remainder[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speaker.isEmpty, speaker.uppercased() != "SYSTEM" else {
            return nil
        }
        let body = remainder[remainder.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(timestamp) \(speaker): \(body)"
    }

    private static func dialogueLineCount(in text: String) -> Int {
        text.components(separatedBy: .newlines).filter { promptDialogueLine($0) != nil }.count
    }

    private static func speakers(in text: String) -> Set<String> {
        Set(
            text.components(separatedBy: .newlines).compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("["),
                      let closeBracket = trimmed.firstIndex(of: "]") else {
                    return nil
                }
                let remainder = trimmed[trimmed.index(after: closeBracket)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let colon = remainder.firstIndex(of: ":") else {
                    return nil
                }
                let speaker = remainder[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !speaker.isEmpty, speaker.uppercased() != "SYSTEM" else {
                    return nil
                }
                return speaker.lowercased()
            }
        )
    }
}
