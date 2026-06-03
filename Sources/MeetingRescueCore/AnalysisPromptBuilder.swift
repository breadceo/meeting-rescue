import Foundation

public enum AnalysisPromptBuilder {
    private static let maxInitialTranscriptCharacters = 6_000
    private static let maxNewTranscriptCharacters = 3_200
    private static let recentTranscriptContextCharacters = 500
    private static let maxRelatedTranscriptChunkCharacters = 700
    private static let compactTimelineLimit = 3
    private static let compactCandidateLimit = 4
    private static let compactNotesLimit = 3

    public static func buildPrompt(for request: AnalysisRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let transcriptContext = transcriptContext(for: request)
        let payload = PromptPayload(
            meetingMetadata: promptMetadata(from: request.metadata, transcriptContext: transcriptContext),
            meetingTypePreset: request.meetingTypePreset,
            bookmarks: compactBookmarks(request.bookmarks),
            transcriptContext: transcriptContext,
            contextPlan: request.contextPlan,
            previousAnalysisSnapshot: compactSnapshot(from: request.previousSnapshot),
            confirmedCandidateIDs: Array(request.confirmedCandidateIDs).sorted(),
            deletedCandidateIDs: Array(request.deletedCandidateIDs).sorted()
        )
        let payloadData = try encoder.encode(payload)
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"

        switch request.outputMode {
        case .fullSnapshot:
            return fullSnapshotPrompt(payloadJSON: payloadJSON)
        case .livePatch:
            return livePatchPrompt(payloadJSON: payloadJSON)
        }
    }

    private static func fullSnapshotPrompt(payloadJSON: String) -> String {
        """
        당신은 실시간 회의 분석 assistant입니다. 모든 사용자-facing 응답은 한글로 작성하세요.

        아래 payload만 근거로 지정된 JSON schema의 JSON 객체 하나만 반환하세요.
        fullTranscript가 있으면 첫 분석입니다. 제공된 범위로 작고 읽기 쉬운 snapshot을 만드세요.
        newTranscriptChunk가 있으면 primary source로 쓰고 recentTranscriptContext/relatedTranscriptChunks는 연결 맥락으로만 쓰세요.
        final/full-refresh에서는 회의 전체 wrap-up을 다시 구성하세요.
        과거 맥락을 새 결정처럼 반복하지 말고, 불확실하면 candidate/note로 남기세요.

        meetingTypePreset이 automatic이면 transcript를 보고 meetingType을 decision/planning/incident/oneOnOne/brainstorm/status 중 하나로 추정하세요.
        meetingTypePreset이 automatic이 아니면 그 값을 meetingType으로 사용하세요.
        meetingType이 decision이면 선택지, 판단 기준, 결정 근거, 남은 승인자를 우선 정리하세요.
        meetingType이 planning이면 목표, 범위, 일정, owner, dependency를 우선 정리하세요.
        meetingType이 incident이면 증상, 영향, 원인 가설, mitigation, follow-up을 우선 정리하세요.
        meetingType이 oneOnOne이면 관심사, 피드백, 약속, 다음 대화를 우선 정리하세요.
        meetingType이 brainstorm이면 아이디어, 가설, 근거, 수렴 지점을 우선 정리하세요.
        meetingType이 status이면 진행 상황, block, 다음 action, escalation을 우선 정리하세요.

        meetingSummary는 회의 전체 wrap-up입니다. overview는 2-4문장으로 작성하고, keyPoints/openQuestions는 각 항목마다 evidence를 1개 이상 붙이세요.
        evidence.timestamp는 원문 회의 경과 시간만 사용하세요. 예: "04:13" 또는 "[04:13]". ISO 날짜를 만들지 마세요.
        evidence.excerpt는 payload 원문에서 근거가 되는 짧은 발화 일부를 그대로 옮기세요.
        bookmarks가 있으면 bookmark 주변 발화를 summary evidence로 우선 고려하세요.
        currentIssue는 현재 논점 또는 Live Focus입니다. meetingSummary와 중복되는 전체 요약을 쓰지 마세요.
        timestamp는 원문 회의 경과 시간만 사용하세요. 예: "04:13" 또는 "[04:13]". ISO 날짜를 만들지 마세요.
        topicTimeline은 시간순이며 agenda/논점/대상/실행 방향이 바뀌면 나누세요. 전체 6개 이하를 권장합니다.
        currentIssue.summary는 2-4문장, decision/action 후보는 각각 6개 이하로 간결하게 유지하세요.
        optional 값은 null 또는 빈 배열로 채우세요.

        Payload:
        \(payloadJSON)
        """
    }

    private static func livePatchPrompt(payloadJSON: String) -> String {
        """
        당신은 실시간 회의 분석 assistant입니다. 모든 사용자-facing 응답은 한글로 작성하세요.

        아래 payload만 근거로 지정된 JSON schema의 JSON patch 객체 하나만 반환하세요.
        전체 AnalysisSnapshot을 쓰지 마세요. 이번 newTranscriptChunk 때문에 추가/수정할 항목만 patch로 반환하세요.
        meetingType은 automatic 추정이 새로 확실해졌거나 수동 preset과 맞춰야 할 때만 채우고, 변화가 없으면 null로 두세요.
        meetingSummary는 이번 chunk 또는 bookmark 때문에 회의 전체 결론, 핵심 포인트, 열린 질문이 바뀌었을 때만 채우고, 변화가 없으면 null로 두세요.
        meetingSummary를 채울 때는 evidence.timestamp/speaker/excerpt를 함께 채우세요.
        currentIssue는 현재 논점 또는 Live Focus입니다. 실제 변화가 있을 때만 채우고, 변화가 작으면 null로 두세요.
        단, previousAnalysisSnapshot.currentIssue.summary가 비어 있으면 이번 chunk의 핵심 논점으로 currentIssue를 반드시 채우세요.
        topicTimelineUpserts/decisionCandidateUpserts/actionItemCandidateUpserts/risksOrNotesAppend는 보통 0-2개, 최대 3개로 제한하세요.
        기존 후보/노트/토픽을 반복하지 말고, confirmed/deleted 상태를 되돌리지 마세요.
        relatedTranscriptChunks는 생략된 현재 회의 맥락 연결용입니다. 관련성이 낮으면 무시하세요.
        timestamp는 원문 회의 경과 시간만 사용하세요. 예: "04:13" 또는 "[04:13]". ISO 날짜를 만들지 마세요.
        topicTimelineUpserts의 startTimestamp와 endTimestamp는 둘 다 채우세요. 한 발화짜리 topic이면 같은 timestamp를 넣으세요.
        optional 값은 null 또는 빈 배열로 채우세요.

        Payload:
        \(payloadJSON)
        """
    }

    private struct PromptPayload: Encodable {
        var meetingMetadata: MeetingMetadata
        var meetingTypePreset: MeetingTypePreset
        var bookmarks: [MeetingBookmark]
        var transcriptContext: TranscriptContext
        var contextPlan: AnalysisContextPlan?
        var previousAnalysisSnapshot: AnalysisSnapshot?
        var confirmedCandidateIDs: [String]
        var deletedCandidateIDs: [String]
    }

    private struct TranscriptContext: Encodable {
        var mode: String
        var fullTranscript: String?
        var newTranscriptChunk: String?
        var recentTranscriptContext: String?
        var relatedTranscriptChunks: [RetrievedTranscriptChunk]
        var omittedTranscriptNote: String?
        var rawTranscriptCharacterCount: Int
        var lastAnalyzedTranscriptCharacterCount: Int
    }

    private static func transcriptContext(for request: AnalysisRequest) -> TranscriptContext {
        let rawTranscript = request.rawTranscript
        let rawCount = rawTranscript.count
        let clampedAnalyzedCount = min(max(0, request.lastAnalyzedTranscriptCharacterCount), rawCount)

        guard clampedAnalyzedCount > 0 else {
            if request.outputMode == .livePatch {
                let newTranscriptChunk = promptDialogueText(
                    from: cappedSuffix(rawTranscript, limit: maxNewTranscriptCharacters)
                )
                let omitted = rawCount > maxNewTranscriptCharacters
                    ? "첫 live patch 입력은 마지막 \(maxNewTranscriptCharacters)자만 newTranscriptChunk로 포함했습니다."
                    : nil
                return TranscriptContext(
                    mode: "initial_live_patch",
                    fullTranscript: nil,
                    newTranscriptChunk: newTranscriptChunk.isEmpty ? nil : newTranscriptChunk,
                    recentTranscriptContext: nil,
                    relatedTranscriptChunks: relatedTranscriptChunks(for: request),
                    omittedTranscriptNote: omitted,
                    rawTranscriptCharacterCount: rawCount,
                    lastAnalyzedTranscriptCharacterCount: 0
                )
            }

            let fullTranscript = promptDialogueText(
                from: cappedSuffix(rawTranscript, limit: maxInitialTranscriptCharacters)
            )
            let omitted = rawCount > maxInitialTranscriptCharacters
                ? "초기 분석 입력은 마지막 \(maxInitialTranscriptCharacters)자만 포함했습니다."
                : nil
            return TranscriptContext(
                mode: "initial",
                fullTranscript: fullTranscript,
                newTranscriptChunk: nil,
                recentTranscriptContext: nil,
                relatedTranscriptChunks: relatedTranscriptChunks(for: request),
                omittedTranscriptNote: omitted,
                rawTranscriptCharacterCount: rawCount,
                lastAnalyzedTranscriptCharacterCount: 0
            )
        }

        let analyzedIndex = rawTranscript.index(rawTranscript.startIndex, offsetBy: clampedAnalyzedCount)
        let previousTranscript = String(rawTranscript[..<analyzedIndex])
        let newTranscript = String(rawTranscript[analyzedIndex...])
        let cappedNewTranscript = promptDialogueText(
            from: cappedSuffix(newTranscript, limit: maxNewTranscriptCharacters)
        )
        let recentContext = promptDialogueText(
            from: cappedSuffix(previousTranscript, limit: recentTranscriptContextCharacters)
        )

        var omittedParts: [String] = []
        if newTranscript.count > maxNewTranscriptCharacters {
            omittedParts.append("새 transcript chunk가 길어 마지막 \(maxNewTranscriptCharacters)자만 포함했습니다.")
        }
        if previousTranscript.count > recentTranscriptContextCharacters {
            omittedParts.append("이전 transcript 맥락은 마지막 \(recentTranscriptContextCharacters)자만 포함했습니다.")
        }

        return TranscriptContext(
            mode: newTranscript.isEmpty ? "refresh_without_new_chunk" : "incremental",
            fullTranscript: nil,
            newTranscriptChunk: newTranscript.isEmpty ? nil : cappedNewTranscript,
            recentTranscriptContext: recentContext.isEmpty ? nil : recentContext,
            relatedTranscriptChunks: relatedTranscriptChunks(for: request),
            omittedTranscriptNote: omittedParts.isEmpty ? nil : omittedParts.joined(separator: " "),
            rawTranscriptCharacterCount: rawCount,
            lastAnalyzedTranscriptCharacterCount: clampedAnalyzedCount
        )
    }

    private static func relatedTranscriptChunks(for request: AnalysisRequest) -> [RetrievedTranscriptChunk] {
        (request.contextPlan?.retrievedChunks ?? []).map { chunk in
            RetrievedTranscriptChunk(
                id: chunk.id,
                timeRange: chunk.timeRange,
                text: cappedSuffix(promptDialogueText(from: chunk.text), limit: maxRelatedTranscriptChunkCharacters),
                score: chunk.score
            )
        }
    }

    private static func compactSnapshot(from snapshot: AnalysisSnapshot?) -> AnalysisSnapshot? {
        guard var snapshot else {
            return nil
        }
        snapshot.meetingSummary.keyPoints = Array(snapshot.meetingSummary.keyPoints.prefix(4))
        snapshot.meetingSummary.openQuestions = Array(snapshot.meetingSummary.openQuestions.prefix(4))
        for index in snapshot.meetingSummary.keyPoints.indices {
            snapshot.meetingSummary.keyPoints[index].evidence = Array(snapshot.meetingSummary.keyPoints[index].evidence.prefix(2))
        }
        for index in snapshot.meetingSummary.openQuestions.indices {
            snapshot.meetingSummary.openQuestions[index].evidence = Array(snapshot.meetingSummary.openQuestions[index].evidence.prefix(2))
        }
        snapshot.currentIssue.openQuestions = Array(snapshot.currentIssue.openQuestions.prefix(5))
        snapshot.topicTimeline = Array(snapshot.topicTimeline.suffix(compactTimelineLimit))
        snapshot.decisionCandidates = Array(snapshot.decisionCandidates.suffix(compactCandidateLimit))
        snapshot.actionItemCandidates = Array(snapshot.actionItemCandidates.suffix(compactCandidateLimit))
        snapshot.risksOrNotes = Array(snapshot.risksOrNotes.suffix(compactNotesLimit))
        return snapshot
    }

    private static func compactBookmarks(_ bookmarks: [MeetingBookmark]) -> [MeetingBookmark] {
        Array(bookmarks.suffix(12))
    }

    private static func promptMetadata(
        from metadata: MeetingMetadata,
        transcriptContext: TranscriptContext
    ) -> MeetingMetadata {
        let primarySpeakers = speakerNames(
            in: [
                transcriptContext.fullTranscript,
                transcriptContext.newTranscriptChunk
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        )
        let contextSpeakers = speakerNames(
            in: [
                transcriptContext.fullTranscript,
                transcriptContext.newTranscriptChunk,
                transcriptContext.recentTranscriptContext,
                transcriptContext.relatedTranscriptChunks.map(\.text).joined(separator: "\n")
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        )
        let speakers = primarySpeakers.isEmpty ? contextSpeakers : primarySpeakers
        guard !speakers.isEmpty else {
            return metadata
        }

        var copy = metadata
        let filteredParticipants = metadata.participants.filter { participant in
            let normalizedParticipant = normalizedParticipantText(participant)
            return speakers.contains { speaker in
                let normalizedSpeaker = normalizedParticipantText(speaker)
                return normalizedParticipant.contains(normalizedSpeaker)
                    || normalizedSpeaker.contains(normalizedParticipant)
            }
        }
        var compactParticipants = filteredParticipants.isEmpty ? speakers : filteredParticipants
        let knownParticipantText = compactParticipants
            .map(normalizedParticipantText)
            .joined(separator: " ")
        for speaker in primarySpeakers {
            let normalizedSpeaker = normalizedParticipantText(speaker)
            guard !normalizedSpeaker.isEmpty,
                  !knownParticipantText.contains(normalizedSpeaker),
                  !compactParticipants.contains(where: { normalizedParticipantText($0) == normalizedSpeaker }) else {
                continue
            }
            compactParticipants.append(speaker)
        }
        copy.participants = compactParticipants
        return copy
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
        guard !trimmed.isEmpty else {
            return nil
        }
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
        let body = remainder[remainder.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speaker.isEmpty, speaker.uppercased() != "SYSTEM" else {
            return nil
        }
        return "\(timestamp) \(speaker): \(body)"
    }

    private static func speakerNames(in text: String) -> [String] {
        var seen = Set<String>()
        var speakers: [String] = []
        for line in text.components(separatedBy: .newlines) {
            guard let speaker = speakerName(in: line) else {
                continue
            }
            let normalized = normalizedParticipantText(speaker)
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            speakers.append(speaker)
        }
        return speakers
    }

    private static func speakerName(in line: String) -> String? {
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
        return speaker
    }

    private static func normalizedParticipantText(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func cappedSuffix(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return "[앞부분은 길이 제한으로 생략됨]\n" + String(value.suffix(limit))
    }
}
