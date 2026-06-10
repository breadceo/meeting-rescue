import Foundation

public struct LocalGlossaryHistoryScannerConfiguration: Equatable, Sendable {
    public var maxDocuments: Int
    public var maxBytesPerDocument: Int
    public var rawTranscriptLineLimit: Int

    public init(
        maxDocuments: Int = 120,
        maxBytesPerDocument: Int = 96_000,
        rawTranscriptLineLimit: Int = 360
    ) {
        self.maxDocuments = max(1, maxDocuments)
        self.maxBytesPerDocument = max(1_024, maxBytesPerDocument)
        self.rawTranscriptLineLimit = max(1, rawTranscriptLineLimit)
    }
}

public struct LocalGlossaryHistoryScannerProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case listing
        case reading
    }

    public var phase: Phase
    public var completed: Int
    public var total: Int
    public var currentFile: String?

    public init(
        phase: Phase,
        completed: Int,
        total: Int,
        currentFile: String? = nil
    ) {
        self.phase = phase
        self.completed = max(0, completed)
        self.total = max(0, total)
        self.currentFile = currentFile
    }
}

public enum LocalGlossaryHistoryScanner {
    public static func documents(
        in folderURL: URL,
        configuration: LocalGlossaryHistoryScannerConfiguration = .init(),
        fileManager: FileManager = .default,
        progress: ((LocalGlossaryHistoryScannerProgress) -> Void)? = nil
    ) -> [LocalGlossarySourceDocument] {
        progress?(.init(phase: .listing, completed: 0, total: 0))
        let candidates = LatestTranscriptSelector.textFiles(in: folderURL, fileManager: fileManager)
            .sorted { lhs, rhs in
                if lhs.modificationDate == rhs.modificationDate {
                    return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedDescending
                }
                return lhs.modificationDate > rhs.modificationDate
            }
            .prefix(configuration.maxDocuments)
            .map { $0 }
        let total = candidates.count
        progress?(.init(phase: .reading, completed: 0, total: total))
        return candidates.enumerated().compactMap { index, candidate in
            let document = document(from: candidate, configuration: configuration)
            progress?(.init(
                phase: .reading,
                completed: index + 1,
                total: total,
                currentFile: candidate.url.lastPathComponent
            ))
            return document
            }
    }

    private static func document(
        from candidate: TranscriptFileCandidate,
        configuration: LocalGlossaryHistoryScannerConfiguration
    ) -> LocalGlossarySourceDocument? {
        let text = readPrefix(from: candidate.url, byteLimit: configuration.maxBytesPerDocument)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let parsed = TranscriptParser.parse(text)
        let metadata = parsed.metadata
        let title = metadata.displayTitle.isEmpty
            ? candidate.url.deletingPathExtension().lastPathComponent
            : metadata.displayTitle
        var sections: [MeetingHistorySearchSection] = [
            .init(field: .title, text: title, weight: 92),
            .init(field: .file, text: candidate.url.deletingPathExtension().lastPathComponent, weight: 60)
        ]
        if let room = metadata.room, !room.isEmpty {
            sections.append(.init(field: .room, text: room, weight: 78))
        }
        if let dateTime = metadata.dateTime, !dateTime.isEmpty {
            sections.append(.init(field: .date, text: dateTime, weight: 52))
        }
        if !metadata.participants.isEmpty {
            sections.append(.init(field: .participant, text: metadata.participants.joined(separator: " "), weight: 84))
        }
        sections.append(contentsOf: rawTranscriptSections(from: text, lineLimit: configuration.rawTranscriptLineLimit))
        return LocalGlossarySourceDocument(
            id: candidate.url.path,
            title: title,
            sections: sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }

    private static func readPrefix(from url: URL, byteLimit: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ""
        }
        defer {
            try? handle.close()
        }
        let data = (try? handle.read(upToCount: byteLimit)) ?? Data()
        return TranscriptTextDecoder.decode(data)
    }

    private static func rawTranscriptSections(from text: String, lineLimit: Int) -> [MeetingHistorySearchSection] {
        text.components(separatedBy: .newlines)
            .prefix(lineLimit)
            .compactMap { line -> MeetingHistorySearchSection? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }
                return MeetingHistorySearchSection(
                    field: .rawTranscript,
                    text: trimmed,
                    weight: 24,
                    timestamp: TranscriptTimestampLocator.timestamp(in: trimmed)
                )
            }
    }
}
