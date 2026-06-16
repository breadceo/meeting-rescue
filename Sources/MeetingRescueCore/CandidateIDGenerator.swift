import Foundation

public enum CandidateIDGenerator {
    public static func decisionID(text: String, evidenceTimestamp: String) -> String {
        stableID(prefix: "decision", text: text, evidenceTimestamp: evidenceTimestamp)
    }

    public static func actionItemID(task: String, evidenceTimestamp: String) -> String {
        stableID(prefix: "action", text: task, evidenceTimestamp: evidenceTimestamp)
    }

    public static func perspectiveAlignmentID(topic: String, axis: String, evidenceTimestamp: String) -> String {
        stableID(prefix: "alignment", text: "\(topic)|\(axis)", evidenceTimestamp: evidenceTimestamp)
    }

    public static func stableID(prefix: String, text: String, evidenceTimestamp: String) -> String {
        let normalized = "\(prefix)|\(evidenceTimestamp)|\(normalize(text))"
        return "\(prefix)-\(fnv1a64(normalized))"
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
