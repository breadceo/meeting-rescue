import Foundation

public struct LiveTranscriptIndex: Equatable, Sendable {
    public struct Configuration: Equatable, Sendable {
        public var maxDialogueLinesPerSegment: Int
        public var scoreThreshold: Double

        public init(maxDialogueLinesPerSegment: Int = 12, scoreThreshold: Double = 0.16) {
            self.maxDialogueLinesPerSegment = max(4, maxDialogueLinesPerSegment)
            self.scoreThreshold = scoreThreshold
        }
    }

    private struct Segment: Equatable, Sendable {
        var id: String
        var lines: [String]
        var startTimestamp: String?
        var endTimestamp: String?
        var text: String { lines.joined(separator: "\n") }
    }

    private var configuration: Configuration
    private var segments: [Segment] = []
    private var pendingLines: [String] = []
    private var pendingStartTimestamp: String?
    private var pendingEndTimestamp: String?
    private var nextSegmentNumber = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        segments = []
        pendingLines = []
        pendingStartTimestamp = nil
        pendingEndTimestamp = nil
        nextSegmentNumber = 0
    }

    public mutating func rebuild(from rawTranscript: String) {
        reset()
        append(rawTranscript)
        flushPending()
    }

    public mutating func append(_ text: String) {
        for line in text.components(separatedBy: .newlines) {
            guard let dialogue = Self.dialogueLine(from: line) else {
                continue
            }
            if pendingStartTimestamp == nil {
                pendingStartTimestamp = dialogue.timestamp
            }
            pendingEndTimestamp = dialogue.timestamp
            pendingLines.append(dialogue.normalizedLine)
            if pendingLines.count >= configuration.maxDialogueLinesPerSegment {
                flushPending()
            }
        }
    }

    public func retrieve(
        queryText: String,
        excludingText excludedText: String,
        topK: Int
    ) -> [RetrievedTranscriptChunk] {
        guard topK > 0 else {
            return []
        }
        let queryTokens = Self.tokens(in: queryText)
        guard !queryTokens.isEmpty else {
            return []
        }
        let excludedFingerprint = Self.fingerprint(excludedText)
        return allSegments()
            .compactMap { segment -> RetrievedTranscriptChunk? in
                let text = segment.text
                guard !text.isEmpty, Self.fingerprint(text) != excludedFingerprint else {
                    return nil
                }
                let segmentTokens = Self.tokens(in: text)
                guard !segmentTokens.isEmpty else {
                    return nil
                }
                let overlap = queryTokens.intersection(segmentTokens)
                let score = Double(overlap.count) / sqrt(Double(max(queryTokens.count, 1) * max(segmentTokens.count, 1)))
                guard score >= configuration.scoreThreshold else {
                    return nil
                }
                return RetrievedTranscriptChunk(
                    id: segment.id,
                    timeRange: Self.timeRange(start: segment.startTimestamp, end: segment.endTimestamp),
                    text: text,
                    score: score
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.timeRange > rhs.timeRange
                }
                return lhs.score > rhs.score
            }
            .prefix(topK)
            .map { $0 }
    }

    private mutating func flushPending() {
        guard !pendingLines.isEmpty else {
            return
        }
        let id = "live-\(nextSegmentNumber)"
        nextSegmentNumber += 1
        segments.append(
            Segment(
                id: id,
                lines: pendingLines,
                startTimestamp: pendingStartTimestamp,
                endTimestamp: pendingEndTimestamp
            )
        )
        pendingLines = []
        pendingStartTimestamp = nil
        pendingEndTimestamp = nil
    }

    private func allSegments() -> [Segment] {
        guard !pendingLines.isEmpty else {
            return segments
        }
        return segments + [
            Segment(
                id: "live-pending",
                lines: pendingLines,
                startTimestamp: pendingStartTimestamp,
                endTimestamp: pendingEndTimestamp
            )
        ]
    }

    private static func dialogueLine(from line: String) -> (timestamp: String, normalizedLine: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let closeBracket = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let timestamp = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
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
        return (timestamp, "[\(timestamp)] \(speaker): \(body)")
    }

    private static func tokens(in text: String) -> Set<String> {
        let normalized = text
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : " "
            }
        return Set(String(normalized).split(separator: " ").map(String.init).filter { $0.count >= 2 })
    }

    private static func fingerprint(_ text: String) -> String {
        text
            .lowercased()
            .filter { !$0.isWhitespace }
            .prefix(1_000)
            .description
    }

    private static func timeRange(start: String?, end: String?) -> String {
        switch (start, end) {
        case (.some(let start), .some(let end)) where start != end:
            return "[\(start)]-[\(end)]"
        case (.some(let start), _):
            return "[\(start)]"
        case (_, .some(let end)):
            return "[\(end)]"
        default:
            return ""
        }
    }
}
