import Foundation

public struct MeetingMetadata: Codable, Equatable, Sendable {
    public var room: String?
    public var dateTime: String?
    public var participants: [String]

    public init(room: String? = nil, dateTime: String? = nil, participants: [String] = []) {
        self.room = room
        self.dateTime = dateTime
        self.participants = participants
    }

    public var displayTitle: String {
        room?.isEmpty == false ? room! : "활성 회의"
    }
}

public struct DialogueLine: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        "\(timestamp)|\(speaker)|\(text)"
    }

    public let timestamp: String
    public let speaker: String
    public let text: String

    public init(timestamp: String, speaker: String, text: String) {
        self.timestamp = timestamp
        self.speaker = speaker
        self.text = text
    }
}

public struct ParsedTranscript: Codable, Equatable, Sendable {
    public let metadata: MeetingMetadata
    public let dialogueLines: [DialogueLine]

    public init(metadata: MeetingMetadata, dialogueLines: [DialogueLine]) {
        self.metadata = metadata
        self.dialogueLines = dialogueLines
    }
}

public enum TranscriptParser {
    public static func containsEndMarker(_ rawTranscript: String) -> Bool {
        rawTranscript.contains("[SYSTEM] 대화 기록 종료")
            || rawTranscript.contains("[SYSTEM] Chat Logs has been ended")
    }

    public static func parse(_ rawTranscript: String) -> ParsedTranscript {
        var metadata = MeetingMetadata()
        var dialogueLines: [DialogueLine] = []
        var unlabeledHeaderLines: [String] = []
        var sawDialogue = false

        for line in rawTranscript.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            guard !trimmed.allSatisfy({ $0 == "#" }) else {
                continue
            }

            if applyHeaderLine(trimmed, to: &metadata) {
                continue
            }

            guard let dialogue = parseDialogueLine(trimmed) else {
                if !sawDialogue {
                    unlabeledHeaderLines.append(trimmed)
                }
                continue
            }

            sawDialogue = true
            guard !isSystem(dialogue.speaker) else {
                continue
            }
            dialogueLines.append(dialogue)
        }

        applyUnlabeledHeaderLines(unlabeledHeaderLines, to: &metadata)
        return ParsedTranscript(metadata: metadata, dialogueLines: dialogueLines)
    }

    private static func applyHeaderLine(_ line: String, to metadata: inout MeetingMetadata) -> Bool {
        let separators = [":", "："]
        guard let separator = separators.compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return false
        }

        let rawKey = String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawKey.isEmpty, !value.isEmpty else {
            return false
        }

        let key = rawKey.lowercased()
        switch key {
        case "room", "회의실", "방", "title", "meeting", "meeting room":
            metadata.room = value
            return true
        case "date", "time", "date/time", "datetime", "날짜", "시간", "날짜/시간", "일시":
            metadata.dateTime = value
            return true
        case "participants", "attendees", "참석자", "참여자":
            metadata.participants = value
                .split { character in
                    character == "," || character == "、" || character == ";"
                }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return true
        default:
            return false
        }
    }

    private static func parseDialogueLine(_ line: String) -> DialogueLine? {
        let patterns = [
            #"^\[(\d{1,2}:\d{2}(?::\d{2})?)\]\s*([^:：]+)[:：]\s*(.+)$"#,
            #"^\((\d{1,2}:\d{2}(?::\d{2})?)\)\s*([^:：]+)[:：]\s*(.+)$"#,
            #"^(\d{1,2}:\d{2}(?::\d{2})?)\s+([^:：]+)[:：]\s*(.+)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges == 4 else {
                continue
            }
            return DialogueLine(
                timestamp: substring(in: line, at: match.range(at: 1)),
                speaker: substring(in: line, at: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines),
                text: substring(in: line, at: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return nil
    }

    private static func applyUnlabeledHeaderLines(_ lines: [String], to metadata: inout MeetingMetadata) {
        guard !lines.isEmpty else {
            return
        }

        if metadata.room == nil {
            metadata.room = lines[safe: 0]
        }
        if metadata.dateTime == nil {
            metadata.dateTime = lines[safe: 1]
        }
        if metadata.participants.isEmpty, let participantLine = lines[safe: 2] {
            metadata.participants = splitParticipants(participantLine)
        }
    }

    private static func isSystem(_ speaker: String) -> Bool {
        let normalized = speaker.trimmingCharacters(in: CharacterSet(charactersIn: "[] ").union(.whitespacesAndNewlines))
        return normalized.caseInsensitiveCompare("SYSTEM") == .orderedSame
    }

    private static func substring(in line: String, at range: NSRange) -> String {
        guard let stringRange = Range(range, in: line) else {
            return ""
        }
        return String(line[stringRange])
    }

    private static func splitParticipants(_ value: String) -> [String] {
        value
            .split { character in
                character == "," || character == "、" || character == ";"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
