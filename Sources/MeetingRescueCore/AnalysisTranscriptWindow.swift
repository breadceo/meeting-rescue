import Foundation

public struct AnalysisTranscriptWindow: Equatable, Sendable {
    public var rawTranscript: String
    public var lastAnalyzedTranscriptCharacterCount: Int
    public var targetTranscriptCharacterCount: Int
    public var sourceTranscriptCharacterCount: Int

    public var isChunked: Bool {
        targetTranscriptCharacterCount < sourceTranscriptCharacterCount
    }

    public var backlogCharacterCount: Int {
        max(0, sourceTranscriptCharacterCount - lastAnalyzedTranscriptCharacterCount)
    }

    public var messageSuffix: String? {
        guard isChunked else {
            return nil
        }
        return "catch-up \(lastAnalyzedTranscriptCharacterCount)-\(targetTranscriptCharacterCount)/\(sourceTranscriptCharacterCount)자"
    }

    public static func make(
        rawTranscript: String,
        lastAnalyzedTranscriptCharacterCount: Int,
        reason: String,
        maxAutomaticCatchUpCharacters: Int
    ) -> AnalysisTranscriptWindow {
        let sourceCount = rawTranscript.count
        let clampedAnalyzedCount = min(max(0, lastAnalyzedTranscriptCharacterCount), sourceCount)
        let shouldLimit = shouldLimitTranscript(for: reason) && maxAutomaticCatchUpCharacters > 0
        let targetCount = shouldLimit
            ? boundedTargetCount(
                rawTranscript: rawTranscript,
                startCount: clampedAnalyzedCount,
                maxChunkCharacters: maxAutomaticCatchUpCharacters
            )
            : sourceCount

        return AnalysisTranscriptWindow(
            rawTranscript: String(rawTranscript.prefix(targetCount)),
            lastAnalyzedTranscriptCharacterCount: clampedAnalyzedCount,
            targetTranscriptCharacterCount: targetCount,
            sourceTranscriptCharacterCount: sourceCount
        )
    }

    public static func shouldLimitTranscript(for reason: String) -> Bool {
        reason.hasPrefix("automatic")
            || reason.hasPrefix("manual")
            || reason.hasPrefix("final")
    }

    private static func boundedTargetCount(
        rawTranscript: String,
        startCount: Int,
        maxChunkCharacters: Int
    ) -> Int {
        let sourceCount = rawTranscript.count
        let hardTarget = min(sourceCount, startCount + maxChunkCharacters)
        guard hardTarget < sourceCount else {
            return sourceCount
        }

        let startIndex = rawTranscript.index(rawTranscript.startIndex, offsetBy: startCount)
        let hardTargetIndex = rawTranscript.index(rawTranscript.startIndex, offsetBy: hardTarget)
        let searchRange = startIndex..<hardTargetIndex
        if let newlineIndex = rawTranscript.range(of: "\n", options: .backwards, range: searchRange)?.lowerBound,
           newlineIndex > startIndex {
            let afterNewline = rawTranscript.index(after: newlineIndex)
            return rawTranscript.distance(from: rawTranscript.startIndex, to: afterNewline)
        }
        return hardTarget
    }
}
