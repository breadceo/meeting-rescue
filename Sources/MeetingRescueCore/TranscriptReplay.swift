import Foundation

public struct TranscriptReplayFrame: Equatable, Sendable {
    public var text: String
    public var currentLine: Int
    public var totalLines: Int
    public var isCompleted: Bool
    public var delayAfterSeconds: TimeInterval

    public init(
        text: String,
        currentLine: Int,
        totalLines: Int,
        isCompleted: Bool,
        delayAfterSeconds: TimeInterval = 0
    ) {
        self.text = text
        self.currentLine = currentLine
        self.totalLines = totalLines
        self.isCompleted = isCompleted
        self.delayAfterSeconds = delayAfterSeconds
    }
}

public struct TranscriptReplayCursor: Equatable, Sendable {
    private let lines: [String]
    private var nextLineIndex: Int

    public init(rawTranscript: String) {
        self.lines = rawTranscript.components(separatedBy: .newlines)
        self.nextLineIndex = 0
    }

    public var currentLine: Int {
        nextLineIndex
    }

    public var totalLines: Int {
        lines.count
    }

    public var isCompleted: Bool {
        nextLineIndex >= lines.count
    }

    public mutating func advance(maxLines: Int) -> TranscriptReplayFrame? {
        guard maxLines > 0, !isCompleted else {
            return nil
        }

        let endIndex = min(nextLineIndex + maxLines, lines.count)
        let chunk = lines[nextLineIndex..<endIndex].joined(separator: "\n")
        nextLineIndex = endIndex

        let completed = isCompleted
        return TranscriptReplayFrame(
            text: completed ? chunk : chunk + "\n",
            currentLine: nextLineIndex,
            totalLines: lines.count,
            isCompleted: completed
        )
    }

    public mutating func advancePreambleFrame(delayAfterSeconds: TimeInterval = 0) -> TranscriptReplayFrame? {
        guard !isCompleted else {
            return nil
        }

        let timestampIndex = lines[nextLineIndex...].firstIndex {
            Self.timestampSeconds(in: $0) != nil
        } ?? lines.endIndex
        guard timestampIndex > nextLineIndex else {
            return nil
        }

        let chunk = lines[nextLineIndex..<timestampIndex].joined(separator: "\n")
        nextLineIndex = timestampIndex
        let completed = isCompleted
        return TranscriptReplayFrame(
            text: completed ? chunk : chunk + "\n",
            currentLine: nextLineIndex,
            totalLines: lines.count,
            isCompleted: completed,
            delayAfterSeconds: delayAfterSeconds
        )
    }

    public mutating func advanceTimestampPacedFrame(
        fallbackDelaySeconds: TimeInterval = 0.35,
        minimumDelaySeconds: TimeInterval = 0.05
    ) -> TranscriptReplayFrame? {
        guard !isCompleted else {
            return nil
        }

        let line = lines[nextLineIndex]
        let currentTimestamp = Self.timestampSeconds(in: line)
        nextLineIndex += 1

        let completed = isCompleted
        let delay = completed ? 0 : delayAfterCurrentLine(
            currentTimestamp: currentTimestamp,
            fallbackDelaySeconds: fallbackDelaySeconds,
            minimumDelaySeconds: minimumDelaySeconds
        )
        return TranscriptReplayFrame(
            text: completed ? line : line + "\n",
            currentLine: nextLineIndex,
            totalLines: lines.count,
            isCompleted: completed,
            delayAfterSeconds: delay
        )
    }

    private func delayAfterCurrentLine(
        currentTimestamp: TimeInterval?,
        fallbackDelaySeconds: TimeInterval,
        minimumDelaySeconds: TimeInterval
    ) -> TimeInterval {
        guard let currentTimestamp else {
            return fallbackDelaySeconds
        }

        guard let nextTimestamp = lines[nextLineIndex...].lazy.compactMap({ Self.timestampSeconds(in: $0) }).first else {
            return fallbackDelaySeconds
        }

        return max(minimumDelaySeconds, nextTimestamp - currentTimestamp)
    }

    public static func timestampSeconds(in line: String) -> TimeInterval? {
        guard let start = line.firstIndex(of: "["),
              let end = line[start...].firstIndex(of: "]") else {
            return nil
        }

        let value = line[line.index(after: start)..<end]
        let parts = value.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2:
            return TimeInterval(parts[0] * 60 + parts[1])
        case 3:
            return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default:
            return nil
        }
    }

    public static func adjustedDelay(
        _ delaySeconds: TimeInterval,
        speedMultiplier: Double,
        minimumDelaySeconds: TimeInterval
    ) -> TimeInterval {
        let safeMultiplier = max(1, speedMultiplier)
        return max(minimumDelaySeconds, delaySeconds / safeMultiplier)
    }
}
