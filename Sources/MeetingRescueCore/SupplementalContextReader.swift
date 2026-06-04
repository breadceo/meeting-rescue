import Foundation

public enum SupplementalContextReader {
    public static func source(from url: URL, characterLimit: Int = 4_000) throws -> SupplementalContextSource {
        let extensionValue = url.pathExtension.lowercased()
        guard ["md", "txt"].contains(extensionValue) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(text.prefix(max(1, characterLimit)))
        return SupplementalContextSource(
            id: "attached:\(url.path)",
            kind: .attachedText,
            title: url.deletingPathExtension().lastPathComponent,
            sourceName: url.lastPathComponent,
            excerpt: capped,
            priority: .userAttachedContext,
            confidence: 1.0
        )
    }
}
