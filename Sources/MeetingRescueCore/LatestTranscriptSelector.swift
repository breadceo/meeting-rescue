import Foundation

public struct TranscriptFileCandidate: Equatable, Sendable {
    public let url: URL
    public let modificationDate: Date

    public init(url: URL, modificationDate: Date) {
        self.url = url
        self.modificationDate = modificationDate
    }
}
public enum LatestTranscriptSelector {
    public static func latestTextFile(in folderURL: URL, fileManager: FileManager = .default) -> URL? {
        latestTextFile(from: textFiles(in: folderURL, fileManager: fileManager))?.url
    }

    public static func textFiles(in folderURL: URL, fileManager: FileManager = .default) -> [TranscriptFileCandidate] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url -> TranscriptFileCandidate? in
            guard url.pathExtension.lowercased() == "txt" else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile != false else {
                return nil
            }
            return TranscriptFileCandidate(
                url: url,
                modificationDate: values?.contentModificationDate ?? .distantPast
            )
        }
    }

    public static func latestTextFile(from candidates: [TranscriptFileCandidate]) -> TranscriptFileCandidate? {
        candidates
            .filter { $0.url.pathExtension.lowercased() == "txt" }
            .max { lhs, rhs in
                if lhs.modificationDate == rhs.modificationDate {
                    return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
                }
                return lhs.modificationDate < rhs.modificationDate
            }
    }
}

public enum LiveTranscriptUpdateDetector {
    public static func isUpdated(latest: TranscriptFileCandidate?, baseline: TranscriptFileCandidate?) -> Bool {
        guard let latest, let baseline else {
            return false
        }
        if latest.url != baseline.url {
            return true
        }
        return latest.modificationDate > baseline.modificationDate
    }
}
