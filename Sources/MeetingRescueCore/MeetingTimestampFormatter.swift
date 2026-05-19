import Foundation

public enum MeetingTimestampFormatter {
    public static func display(_ timestamp: String, meetingDateTime: String?) -> String {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "-"
        }

        if let seconds = bracketTimestampSeconds(trimmed) {
            return bracketedElapsed(seconds)
        }

        if let seconds = numericTimestampSeconds(trimmed) {
            return bracketedElapsed(seconds)
        }

        if let absoluteDate = isoDate(from: trimmed),
           let meetingStart = meetingStartDate(from: meetingDateTime) {
            let elapsed = absoluteDate.timeIntervalSince(meetingStart)
            if elapsed >= 0 {
                return bracketedElapsed(elapsed)
            }
            if let transcriptElapsed = isoLikeTranscriptElapsedSeconds(from: trimmed, meetingDateTime: meetingDateTime) {
                return bracketedElapsed(transcriptElapsed)
            }
            return bracketedElapsed(0)
        }

        return trimmed
    }

    public static func displayRange(_ startTimestamp: String, endTimestamp: String?, meetingDateTime: String?) -> String {
        let start = display(startTimestamp, meetingDateTime: meetingDateTime)
        guard let endTimestamp, !endTimestamp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return start
        }
        let end = display(endTimestamp, meetingDateTime: meetingDateTime)
        return "\(start)-\(end)"
    }

    private static func bracketTimestampSeconds(_ value: String) -> TimeInterval? {
        guard value.hasPrefix("["),
              let end = value.firstIndex(of: "]") else {
            return nil
        }
        let inner = String(value[value.index(after: value.startIndex)..<end])
        return numericTimestampSeconds(inner)
    }

    private static func numericTimestampSeconds(_ value: String) -> TimeInterval? {
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

    private static func bracketedElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "[%02d:%02d:%02d]", hours, minutes, seconds)
        }
        return String(format: "[%02d:%02d]", minutes, seconds)
    }

    private static func isoDate(from value: String) -> Date? {
        let localWallClock = DateFormatter()
        localWallClock.locale = Locale(identifier: "en_US_POSIX")
        localWallClock.timeZone = TimeZone.current
        localWallClock.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        if let date = localWallClock.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = formatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }

    private static func isoLikeTranscriptElapsedSeconds(from value: String, meetingDateTime: String?) -> TimeInterval? {
        guard let meetingDate = meetingDateTime?.prefix(10),
              value.hasPrefix(meetingDate),
              let timeParts = isoTimeParts(from: value) else {
            return nil
        }

        let hour = timeParts.hour
        let minute = timeParts.minute
        let second = timeParts.second
        if second == 0 {
            return TimeInterval(hour * 60 + minute)
        }
        if hour == 0 {
            return TimeInterval(minute * 60 + second)
        }
        return TimeInterval(hour * 3600 + minute * 60 + second)
    }

    private static func isoTimeParts(from value: String) -> (hour: Int, minute: Int, second: Int)? {
        guard let tIndex = value.firstIndex(of: "T") else {
            return nil
        }
        let afterT = value.index(after: tIndex)
        let timePrefix = value[afterT...].prefix { character in
            character.isNumber || character == ":"
        }
        let parts = timePrefix.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }
        return (parts[0], parts[1], parts[2])
    }

    private static func meetingStartDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss'Z'"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return isoDate(from: value)
    }
}
