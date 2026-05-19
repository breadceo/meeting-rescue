import Foundation

public enum TranscriptTimestampLocator {
    public static func timestamp(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let end = trimmed.firstIndex(of: "]") else {
            return nil
        }

        let start = trimmed.index(after: trimmed.startIndex)
        let value = String(trimmed[start..<end])
        guard isElapsedTimestamp(value) else {
            return nil
        }
        return value
    }

    public static func elapsedSeconds(in line: String) -> Int? {
        timestamp(in: line).flatMap(elapsedSeconds(forTimestamp:))
    }

    public static func elapsedSeconds(forTimestamp timestamp: String) -> Int? {
        let value = timestamp
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let parts = value.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2:
            return parts[0] * 60 + parts[1]
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }

    public static func lineIndex(
        in lines: [String],
        matching timestamp: String,
        meetingDateTime: String?
    ) -> Int? {
        let candidates = displayCandidates(for: timestamp, meetingDateTime: meetingDateTime)
        guard !candidates.isEmpty else {
            return nil
        }

        return lines.firstIndex { line in
            candidates.contains { candidate in
                line.contains(candidate)
            }
        }
    }

    private static func displayCandidates(for timestamp: String, meetingDateTime: String?) -> [String] {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let formatted = MeetingTimestampFormatter.display(trimmed, meetingDateTime: meetingDateTime)
        var candidates = [formatted, trimmed]
        if !trimmed.hasPrefix("[") {
            candidates.append("[\(trimmed)]")
        }
        return Array(Set(candidates)).filter { !$0.isEmpty && $0 != "-" }
    }

    private static func isElapsedTimestamp(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else {
            return false
        }
        return parts.allSatisfy { Int($0) != nil }
    }
}
