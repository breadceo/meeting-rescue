import Foundation

public struct MeetingSessionState: Codable, Equatable, Sendable {
    public var sourceFilePath: String
    public var metadata: MeetingMetadata
    public var rawReadOffset: UInt64
    public var updatedAt: Date

    public init(sourceFilePath: String, metadata: MeetingMetadata, rawReadOffset: UInt64, updatedAt: Date = Date()) {
        self.sourceFilePath = sourceFilePath
        self.metadata = metadata
        self.rawReadOffset = rawReadOffset
        self.updatedAt = updatedAt
    }
}
public final class ApplicationStateStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let rootURL: URL

    public init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.rootURL = baseURL.appendingPathComponent("MeetingRescue", isDirectory: true)
        }
    }

    public var bookmarkURL: URL {
        rootURL.appendingPathComponent("last-opened-folder.bookmark")
    }

    public func searchIndexDatabaseURL() throws -> URL {
        try ensureRootDirectory()
        return rootURL.appendingPathComponent("meeting-search.sqlite")
    }

    public func saveFolderBookmark(_ data: Data) throws {
        try ensureRootDirectory()
        try data.write(to: bookmarkURL, options: [.atomic])
    }

    public func loadFolderBookmark() -> Data? {
        try? Data(contentsOf: bookmarkURL)
    }

    public func deleteFolderBookmark() throws {
        guard fileManager.fileExists(atPath: bookmarkURL.path) else {
            return
        }
        try fileManager.removeItem(at: bookmarkURL)
    }

    public func saveSession(_ state: MeetingSessionState, for sourceURL: URL) throws {
        try ensureSessionsDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: sessionURL(for: sourceURL), options: [.atomic])
    }

    public func loadSession(for sourceURL: URL) -> MeetingSessionState? {
        guard let data = try? Data(contentsOf: sessionURL(for: sourceURL)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MeetingSessionState.self, from: data)
    }

    public func hasSession(for sourceURL: URL) -> Bool {
        fileManager.fileExists(atPath: sessionURL(for: sourceURL).path)
    }

    public func saveAnalysisState(_ state: MeetingAnalysisState, for sourceURL: URL) throws {
        try ensureSessionsDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: analysisStateURL(for: sourceURL), options: [.atomic])
    }

    public func loadAnalysisState(for sourceURL: URL) -> MeetingAnalysisState {
        guard let data = try? Data(contentsOf: analysisStateURL(for: sourceURL)) else {
            return MeetingAnalysisState()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(MeetingAnalysisState.self, from: data)) ?? MeetingAnalysisState()
    }

    public func hasAnalysisState(for sourceURL: URL) -> Bool {
        fileManager.fileExists(atPath: analysisStateURL(for: sourceURL).path)
    }

    public func clearAnalysisState(for sourceURL: URL) throws {
        let url = analysisStateURL(for: sourceURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try ensureRootDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: settingsURL, options: [.atomic])
    }

    public func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return AppSettings()
        }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    public func saveLocalGlossaryState(_ state: LocalGlossaryState) throws {
        try ensureRootDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: localGlossaryURL, options: [.atomic])
    }

    public func loadLocalGlossaryState() -> LocalGlossaryState {
        guard let data = try? Data(contentsOf: localGlossaryURL) else {
            return LocalGlossaryState()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LocalGlossaryState.self, from: data)) ?? LocalGlossaryState()
    }

    public func localGlossaryRefreshDiagnosticsURL() throws -> URL {
        try ensureLogsDirectory()
        return localGlossaryRefreshDiagnosticsLogURL
    }

    public func appendLocalGlossaryRefreshDiagnostic(_ diagnostic: LocalGlossaryRefreshDiagnostic) throws {
        try ensureLogsDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(diagnostic)
        data.append(0x0A)
        if fileManager.fileExists(atPath: localGlossaryRefreshDiagnosticsLogURL.path) {
            let handle = try FileHandle(forWritingTo: localGlossaryRefreshDiagnosticsLogURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: localGlossaryRefreshDiagnosticsLogURL, options: [.atomic])
        }
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func ensureLogsDirectory() throws {
        try ensureRootDirectory()
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("Logs", isDirectory: true), withIntermediateDirectories: true)
    }

    private func ensureSessionsDirectory() throws {
        try ensureRootDirectory()
        try fileManager.createDirectory(at: rootURL.appendingPathComponent("Sessions", isDirectory: true), withIntermediateDirectories: true)
    }

    private func sessionURL(for sourceURL: URL) -> URL {
        rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent("\(stableID(for: sourceURL.path)).json")
    }

    private var settingsURL: URL {
        rootURL.appendingPathComponent("settings.json")
    }

    private var localGlossaryURL: URL {
        rootURL.appendingPathComponent("local-glossary.json")
    }

    private var localGlossaryRefreshDiagnosticsLogURL: URL {
        rootURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("local-glossary-refresh.jsonl")
    }

    private func analysisStateURL(for sourceURL: URL) -> URL {
        rootURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent("\(stableID(for: sourceURL.path))-analysis.json")
    }

    private func stableID(for value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

public final class FolderBookmarkStore {
    private let stateStore: ApplicationStateStore

    public init(stateStore: ApplicationStateStore = ApplicationStateStore()) {
        self.stateStore = stateStore
    }

    public func save(folderURL: URL) throws {
        let data = try folderURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        try stateStore.saveFolderBookmark(data)
    }

    public func load() -> URL? {
        guard let data = stateStore.loadFolderBookmark() else {
            return nil
        }

        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
