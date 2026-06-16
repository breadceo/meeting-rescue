import Foundation

public struct AnalysisTriggerPolicy: Equatable, Sendable {
    private static let softGateBypassMultiplier = 1.5

    public struct Configuration: Equatable, Sendable {
        public var minNewDialogueLines: Int
        public var minNewTranscriptCharacters: Int
        public var minBatchWaitSeconds: Int
        public var maxBatchWaitSeconds: Int
        public var minimumMeetingElapsedSeconds: Int

        public init(
            minNewDialogueLines: Int = 8,
            minNewTranscriptCharacters: Int = 900,
            minBatchWaitSeconds: Int = 45,
            maxBatchWaitSeconds: Int = 150,
            minimumMeetingElapsedSeconds: Int = 60
        ) {
            self.minNewDialogueLines = max(1, minNewDialogueLines)
            self.minNewTranscriptCharacters = max(1, minNewTranscriptCharacters)
            self.minBatchWaitSeconds = max(1, minBatchWaitSeconds)
            self.maxBatchWaitSeconds = max(self.minBatchWaitSeconds, maxBatchWaitSeconds)
            self.minimumMeetingElapsedSeconds = max(0, minimumMeetingElapsedSeconds)
        }

        public func withMinimumMeetingElapsedSeconds(_ seconds: Int) -> Configuration {
            Configuration(
                minNewDialogueLines: minNewDialogueLines,
                minNewTranscriptCharacters: minNewTranscriptCharacters,
                minBatchWaitSeconds: minBatchWaitSeconds,
                maxBatchWaitSeconds: maxBatchWaitSeconds,
                minimumMeetingElapsedSeconds: seconds
            )
        }
    }

    public enum Decision: Equatable, Sendable {
        case run(reason: String)
        case skip(reason: String)
        case wait(reason: String)
    }

    public struct TranscriptStats: Equatable, Sendable {
        public var sourceCharacterCount: Int
        public var startCharacterCount: Int
        public var newCharacterCount: Int
        public var dialogueLineCount: Int
        public var meaningfulDialogueLineCount: Int

        public init(
            sourceCharacterCount: Int,
            startCharacterCount: Int,
            newCharacterCount: Int,
            dialogueLineCount: Int,
            meaningfulDialogueLineCount: Int
        ) {
            self.sourceCharacterCount = sourceCharacterCount
            self.startCharacterCount = startCharacterCount
            self.newCharacterCount = newCharacterCount
            self.dialogueLineCount = dialogueLineCount
            self.meaningfulDialogueLineCount = meaningfulDialogueLineCount
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func transcriptStats(
        rawTranscript: String,
        lastAnalyzedTranscriptCharacterCount: Int
    ) -> TranscriptStats {
        let sourceCount = rawTranscript.count
        let startCount = min(max(0, lastAnalyzedTranscriptCharacterCount), sourceCount)
        guard startCount < sourceCount else {
            return TranscriptStats(
                sourceCharacterCount: sourceCount,
                startCharacterCount: startCount,
                newCharacterCount: 0,
                dialogueLineCount: 0,
                meaningfulDialogueLineCount: 0
            )
        }

        let newTranscript = transcriptSlice(rawTranscript, from: startCount, to: sourceCount)
        let dialogueLines = TranscriptParser.parse(newTranscript).dialogueLines
        let meaningfulLineCount = dialogueLines.filter(Self.isMeaningfulDialogueLine).count
        return TranscriptStats(
            sourceCharacterCount: sourceCount,
            startCharacterCount: startCount,
            newCharacterCount: sourceCount - startCount,
            dialogueLineCount: dialogueLines.count,
            meaningfulDialogueLineCount: meaningfulLineCount
        )
    }

    public func evaluate(
        rawTranscript: String,
        lastAnalyzedTranscriptCharacterCount: Int,
        latestTranscriptElapsedSeconds: Int,
        now: Date,
        lastAutomaticAnalysisAt: Date?
    ) -> Decision {
        let stats = transcriptStats(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: lastAnalyzedTranscriptCharacterCount
        )
        return evaluate(
            stats: stats,
            latestTranscriptElapsedSeconds: latestTranscriptElapsedSeconds,
            now: now,
            lastAutomaticAnalysisAt: lastAutomaticAnalysisAt
        )
    }

    public func evaluate(
        stats: TranscriptStats,
        latestTranscriptElapsedSeconds: Int,
        now: Date,
        lastAutomaticAnalysisAt: Date?
    ) -> Decision {
        guard latestTranscriptElapsedSeconds >= configuration.minimumMeetingElapsedSeconds else {
            return .wait(reason: "initial-meeting-gate")
        }

        guard stats.newCharacterCount > 0 else {
            return .wait(reason: "no-new-transcript")
        }

        guard stats.dialogueLineCount > 0 else {
            return .skip(reason: "system-only")
        }

        if stats.meaningfulDialogueLineCount == 0, stats.dialogueLineCount <= 2 {
            return .skip(reason: "low-value-dialogue")
        }

        let elapsedSinceLastAttempt = lastAutomaticAnalysisAt.map { now.timeIntervalSince($0) }
        if let elapsedSinceLastAttempt,
           elapsedSinceLastAttempt < TimeInterval(configuration.minBatchWaitSeconds),
           !shouldBypassMinimumWait(
               meaningfulLineCount: stats.meaningfulDialogueLineCount,
               newCharacterCount: stats.newCharacterCount
           ) {
            return .wait(reason: "min-batch-wait")
        }

        if stats.meaningfulDialogueLineCount >= configuration.minNewDialogueLines {
            return .run(reason: "min-dialogue-lines")
        }

        if stats.newCharacterCount >= configuration.minNewTranscriptCharacters {
            return .run(reason: "min-transcript-characters")
        }

        if let elapsedSinceLastAttempt,
           elapsedSinceLastAttempt >= TimeInterval(configuration.maxBatchWaitSeconds),
           stats.meaningfulDialogueLineCount > 0 {
            return .run(reason: "max-wait-flush")
        }

        return .wait(reason: "batch-threshold-not-reached")
    }

    private func shouldBypassMinimumWait(
        meaningfulLineCount: Int,
        newCharacterCount: Int
    ) -> Bool {
        let lineBypassThreshold = Int(ceil(Double(configuration.minNewDialogueLines) * Self.softGateBypassMultiplier))
        let characterBypassThreshold = Int(ceil(Double(configuration.minNewTranscriptCharacters) * Self.softGateBypassMultiplier))
        return meaningfulLineCount >= lineBypassThreshold
            || newCharacterCount >= characterBypassThreshold
    }

    private static func isMeaningfulDialogueLine(_ line: DialogueLine) -> Bool {
        let normalized = normalizedMeaningText(line.text)
        guard !normalized.isEmpty else {
            return false
        }
        if normalized.count >= 8 {
            return true
        }
        if trivialUtterances.contains(normalized) {
            return false
        }
        return meaningfulKeywords.contains { normalized.contains($0) }
    }

    private static let trivialUtterances: Set<String> = [
        "네", "넵", "예", "응", "어", "음", "아", "오", "맞아요", "좋아요", "감사합니다", "고맙습니다",
        "잠시만요", "안녕하세요", "수고하셨습니다", "ok", "okay", "yes", "no", "thanks", "thankyou"
    ]

    private static let meaningfulKeywords: [String] = [
        "결정", "진행", "필요", "일정", "담당", "액션", "이슈", "문제", "공유", "확인",
        "자료", "운영", "출시", "개발", "배포", "마케팅", "정책", "계획", "리스크"
    ]

    private static func normalizedMeaningText(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func transcriptSlice(_ text: String, from startOffset: Int, to endOffset: Int) -> String {
        let sourceCount = text.count
        let lower = min(max(0, startOffset), sourceCount)
        let upper = min(max(lower, endOffset), sourceCount)
        let startIndex = text.index(text.startIndex, offsetBy: lower)
        let endIndex = text.index(text.startIndex, offsetBy: upper)
        return String(text[startIndex..<endIndex])
    }
}
