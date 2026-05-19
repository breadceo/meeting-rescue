import Foundation

public enum AnalysisPromptBuilder {
    private static let maxInitialTranscriptCharacters = 8_000
    private static let maxNewTranscriptCharacters = 5_000
    private static let recentTranscriptContextCharacters = 800
    private static let compactTimelineLimit = 4
    private static let compactCandidateLimit = 6
    private static let compactNotesLimit = 5

    public static func buildPrompt(for request: AnalysisRequest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let transcriptContext = transcriptContext(for: request)
        let payload = PromptPayload(
            meetingMetadata: promptMetadata(from: request.metadata, transcriptContext: transcriptContext),
            providerKind: request.providerKind.rawValue,
            modelPreset: request.modelPreset.rawValue,
            transcriptContext: transcriptContext,
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

        아래 JSON payload를 읽고 지정된 JSON schema에 맞는 하나의 JSON 객체만 반환하세요.
        previousAnalysisSnapshot은 누적 회의 상태를 압축한 compact state입니다.
        transcriptContext.newTranscriptChunk가 있으면 그것을 이번 refresh의 primary source로 사용하고, recentTranscriptContext는 연결 맥락으로만 사용하세요.
        transcriptContext.fullTranscript가 있으면 아직 성공적으로 분석된 구간이 없다는 뜻이므로 제공된 transcript 전체를 기준으로 snapshot을 만드세요.
        기존 compact state의 결정/action 후보와 timeline은 새 transcript chunk에서 반박되거나 갱신할 필요가 있을 때만 바꾸고, 유지할 수 있으면 유지하세요.
        topicTimeline은 사용자가 회의 흐름을 스캔하기 위한 breakdown입니다. 하나의 topic에 모든 내용을 합치지 말고, 3-6분 이상 이어지는 장문 발제라도 하위 agenda, 논점, 대상, 실행 방향이 바뀌면 별도 topic item으로 나누세요.
        incremental refresh에서는 previousAnalysisSnapshot.topicTimeline의 마지막 topic을 무한히 확장하지 마세요. newTranscriptChunk가 기존 topic의 직접 연장일 때만 마지막 topic을 갱신하고, 새 논점이나 다음 agenda가 시작되면 기존 topic의 endTimestamp를 닫고 새 topic을 append하세요.
        topicTimeline은 시간순으로 정렬하고, 각 topic의 startTimestamp는 해당 구간 첫 근거 발화 timestamp로, endTimestamp는 구간 마지막 근거 발화 timestamp로 채우세요.
        timestamp는 transcript 원문에 있는 회의 경과 시간만 사용하세요. 예: "04:13" 또는 "[04:13]". 날짜가 붙은 ISO timestamp를 새로 만들지 마세요.
        출력은 live UI 갱신용이므로 장황하게 쓰지 마세요. currentIssue.summary는 3-5문장, topicTimeline은 전체 8개 이하, decisionCandidates와 actionItemCandidates는 각각 8개 이하로 유지하세요.
        previousAnalysisSnapshot에 이미 있는 오래된 항목은 새 transcript chunk와 직접 관련되지 않으면 반복 설명하지 말고, 필요하면 더 짧게 유지하세요.
        결정 후보와 action item 후보의 id는 제공된 id가 없으면 normalized text와 evidence timestamp에서 안정적으로 파생될 수 있게 유지하세요.
        명확하지 않은 내용은 확정하지 말고 candidate 또는 note로 남기세요.
        optional 값이 없으면 해당 key를 생략하지 말고 null 또는 빈 배열로 채우세요.

        Payload:
        \(payloadJSON)
        """
    }

    private static func livePatchPrompt(payloadJSON: String) -> String {
        """
        당신은 실시간 회의 분석 assistant입니다. 모든 사용자-facing 응답은 한글로 작성하세요.

        아래 JSON payload를 읽고 지정된 JSON schema에 맞는 하나의 JSON patch 객체만 반환하세요.
        이 요청은 incremental patch refresh입니다. live automatic 또는 final catch-up 중이며, previousAnalysisSnapshot은 이미 앱에 저장된 compact state입니다.
        transcriptContext.newTranscriptChunk가 있으면 그것을 이번 refresh의 primary source로 사용하세요. incremental refresh에서는 fullTranscript 재전송을 피하고 compact state와 새 chunk만 기준으로 판단하세요.
        전체 AnalysisSnapshot을 다시 쓰지 마세요. 제공된 transcript 때문에 추가/수정이 필요한 항목만 patch 배열에 넣으세요.
        바뀐 current issue가 있으면 currentIssue를 채우고, 변화가 거의 없으면 currentIssue는 null로 두세요.
        topicTimelineUpserts에는 새 topic 또는 실제로 수정해야 하는 기존 topic만 넣으세요. 기존 topic을 닫아야 하면 endTimestamp가 반영된 topic item을 upsert하고 closeTopicIDs에도 id를 넣으세요.
        하나의 topic을 5분 이상 계속 열어두지 마세요. 새 agenda, 논점, speaker focus, 실행 방향이 바뀌면 기존 topic을 닫고 새 topic을 upsert하세요.
        timestamp는 transcript 원문에 있는 회의 경과 시간만 사용하세요. 예: "04:13" 또는 "[04:13]". 날짜가 붙은 ISO timestamp를 새로 만들지 마세요.
        final catch-up에서는 남은 transcript chunk를 반영하는 것이 목적입니다. 전체 회의를 다시 요약하지 말고 이번 chunk의 추가 흐름, 결정, action, note만 patch로 반영하세요.
        decisionCandidateUpserts와 actionItemCandidateUpserts에는 새 후보 또는 수정이 필요한 후보만 넣으세요. confirmed/deleted 상태는 앱이 보존하므로 사용자가 확정/삭제한 상태를 되돌리지 마세요.
        risksOrNotesAppend에는 새롭게 발견한 risk/note만 넣고, 기존 note를 반복하지 마세요.
        출력은 live UI 갱신용입니다. patch는 작아야 하며, 각 배열은 보통 0-3개, 최대 5개 이하로 유지하세요.
        명확하지 않은 내용은 확정하지 말고 candidate 또는 note로 남기세요.
        optional 값이 없으면 해당 key를 생략하지 말고 null 또는 빈 배열로 채우세요.

        Payload:
        \(payloadJSON)
        """
    }

    private struct PromptPayload: Encodable {
        var meetingMetadata: MeetingMetadata
        var providerKind: String
        var modelPreset: String
        var transcriptContext: TranscriptContext
        var previousAnalysisSnapshot: AnalysisSnapshot?
        var confirmedCandidateIDs: [String]
        var deletedCandidateIDs: [String]
    }

    private struct TranscriptContext: Encodable {
        var mode: String
        var fullTranscript: String?
        var newTranscriptChunk: String?
        var recentTranscriptContext: String?
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
            omittedTranscriptNote: omittedParts.isEmpty ? nil : omittedParts.joined(separator: " "),
            rawTranscriptCharacterCount: rawCount,
            lastAnalyzedTranscriptCharacterCount: clampedAnalyzedCount
        )
    }

    private static func compactSnapshot(from snapshot: AnalysisSnapshot?) -> AnalysisSnapshot? {
        guard var snapshot else {
            return nil
        }
        snapshot.currentIssue.openQuestions = Array(snapshot.currentIssue.openQuestions.prefix(5))
        snapshot.topicTimeline = Array(snapshot.topicTimeline.suffix(compactTimelineLimit))
        snapshot.decisionCandidates = Array(snapshot.decisionCandidates.suffix(compactCandidateLimit))
        snapshot.actionItemCandidates = Array(snapshot.actionItemCandidates.suffix(compactCandidateLimit))
        snapshot.risksOrNotes = Array(snapshot.risksOrNotes.suffix(compactNotesLimit))
        return snapshot
    }

    private static func promptMetadata(
        from metadata: MeetingMetadata,
        transcriptContext: TranscriptContext
    ) -> MeetingMetadata {
        let speakers = speakerNames(
            in: [
                transcriptContext.fullTranscript,
                transcriptContext.newTranscriptChunk,
                transcriptContext.recentTranscriptContext
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        )
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
        if filteredParticipants.isEmpty {
            copy.participants = speakers
        } else {
            copy.participants = filteredParticipants
        }
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
