import Foundation
import MeetingRescueCore
import SwiftUI
import UniformTypeIdentifiers

enum AnalysisRuntimeStatus: Equatable {
    case idle
    case running
    case stale(String)
    case failed(String)
    case completed

    var displayText: String {
        switch self {
        case .idle:
            return "analysis 대기"
        case .running:
            return "analysis 실행 중"
        case .stale(let message):
            return "stale: \(Self.compact(message))"
        case .failed(let message):
            return "실패: \(Self.compact(message))"
        case .completed:
            return "회의 완료"
        }
    }

    var failureMessage: String? {
        switch self {
        case .stale(let message), .failed(let message):
            return Self.compact(message, limit: 180)
        default:
            return nil
        }
    }

    private static func compact(_ message: String, limit: Int = 80) -> String {
        let oneLine = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? message
        if oneLine.count <= limit {
            return oneLine
        }
        return String(oneLine.prefix(limit - 1)) + "…"
    }
}

enum TranscriptRunMode: Equatable {
    case liveWatch
    case history
    case testRun

    var displayText: String {
        switch self {
        case .liveWatch:
            return "Live Watch"
        case .history:
            return "History"
        case .testRun:
            return "Test Run"
        }
    }
}

enum TestRunPlaybackStatus: Equatable {
    case idle
    case running
    case paused
    case completed

    var displayText: String {
        switch self {
        case .idle:
            return "대기"
        case .running:
            return "재생 중"
        case .paused:
            return "일시정지"
        case .completed:
            return "완료"
        }
    }
}

struct MeetingHistoryItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let modificationDate: Date
    let fileSize: Int
    let metadata: MeetingMetadata
    let summary: String?
    let topicCount: Int
    let decisionCount: Int
    let actionCount: Int
    let hasAnalysis: Bool
    let isCompleted: Bool
    let searchIndex: String
    let searchSections: [MeetingHistorySearchSection]
    let summaryPreview: String?

    var title: String {
        if !metadata.displayTitle.isEmpty && metadata.displayTitle != "활성 회의" {
            return metadata.displayTitle
        }
        return url.deletingPathExtension().lastPathComponent
    }

    var subtitle: String {
        let participants = metadata.participants.prefix(3).joined(separator: ", ")
        return [metadata.dateTime, participants.isEmpty ? nil : participants]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var searchableText: String {
        searchSections.map(\.text).joined(separator: " ").lowercased()
    }

    var filterDocument: MeetingHistoryFilterDocument {
        MeetingHistoryFilterDocument(
            modificationDate: modificationDate,
            participants: metadata.participants,
            room: metadata.room,
            isCompleted: isCompleted,
            decisionCount: decisionCount,
            actionCount: actionCount
        )
    }

    func matches(_ query: String) -> Bool {
        searchMatch(for: query) != nil
    }

    func searchMatch(for query: String) -> MeetingHistorySearchMatch? {
        MeetingHistorySearch.match(sections: searchSections, query: query)
    }

    func searchAnchorMatch(for query: String) -> MeetingHistorySearchMatch? {
        MeetingHistorySearch.timestampedMatch(sections: searchSections, query: query)
    }
}

struct MeetingHistorySearchResult: Identifiable, Equatable, Sendable {
    let item: MeetingHistoryItem
    let match: MeetingHistorySearchMatch?
    let anchorTimestamp: String?

    var id: String {
        item.id
    }
}

enum MeetingHistorySortOrder: String, CaseIterable, Equatable, Sendable {
    case newest
    case relevance

    var displayName: String {
        switch self {
        case .newest:
            return "최신순"
        case .relevance:
            return "관련도순"
        }
    }
}

struct TranscriptFocusRequest: Equatable {
    let lineID: Int
    let token: Int
}

private struct MeetingHistoryBuildResult: Sendable {
    let fileSignature: String
    let searchIndexFileSignature: String
    let signature: String
    let items: [MeetingHistoryItem]
    let includesRawTranscriptSearch: Bool
}

struct MeetingSearchIndexProgress: Equatable {
    enum State: Equatable {
        case idle
        case checking
        case indexing
        case ready
        case failed(String)
    }

    var state: State
    var completed: Int
    var total: Int

    static let idle = MeetingSearchIndexProgress(state: .idle, completed: 0, total: 0)

    var isReady: Bool {
        state == .ready
    }

    var isVisible: Bool {
        switch state {
        case .checking, .indexing, .failed:
            return true
        case .idle, .ready:
            return false
        }
    }

    var fraction: Double {
        guard total > 0 else {
            return 0
        }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    var displayText: String {
        switch state {
        case .idle:
            return "검색 DB 대기"
        case .checking:
            return "검색 DB 확인 중"
        case .indexing:
            return "검색 DB 생성 중 \(completed)/\(total)"
        case .ready:
            return "검색 DB 준비 완료"
        case .failed(let message):
            return "검색 DB 실패: \(message)"
        }
    }
}

private final class SearchIndexProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0
    private var total = 0

    func update(completed: Int, total: Int) {
        lock.lock()
        self.completed = completed
        self.total = total
        lock.unlock()
    }

    func snapshot() -> (completed: Int, total: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (completed, total)
    }
}

private struct MeetingHistoryBuilder: Sendable {
    let stateStore: ApplicationStateStore
    let rawTranscriptSearchLineLimit: Int
    let includeRawTranscriptSearch: Bool
    let searchIndexExclusionURL: URL?

    func build(folderURL: URL) -> MeetingHistoryBuildResult {
        let candidates = LatestTranscriptSelector.textFiles(in: folderURL)
        let fileSignature = candidates
            .sorted { $0.url.path < $1.url.path }
            .map { "\($0.url.path):\($0.modificationDate.timeIntervalSince1970)" }
            .joined(separator: "|")
        let excludedPath = searchIndexExclusionURL?.path
        let searchIndexFileSignature = candidates
            .filter { $0.url.path != excludedPath }
            .sorted { $0.url.path < $1.url.path }
            .map { "\($0.url.path):\($0.modificationDate.timeIntervalSince1970)" }
            .joined(separator: "|")
        let signature = "\(includeRawTranscriptSearch ? "raw" : "structured")|\(fileSignature)"
        let items = candidates
            .sorted { lhs, rhs in
                if lhs.modificationDate == rhs.modificationDate {
                    return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedDescending
                }
                return lhs.modificationDate > rhs.modificationDate
            }
            .map(makeHistoryItem)
        return MeetingHistoryBuildResult(
            fileSignature: fileSignature,
            searchIndexFileSignature: searchIndexFileSignature,
            signature: signature,
            items: items,
            includesRawTranscriptSearch: includeRawTranscriptSearch
        )
    }

    private func makeHistoryItem(from candidate: TranscriptFileCandidate) -> MeetingHistoryItem {
        let analysis = stateStore.loadAnalysisState(for: candidate.url)
        let metadata = stateStore.loadSession(for: candidate.url)?.metadata
            ?? loadMetadataPreview(from: candidate.url)
        let values = try? candidate.url.resourceValues(forKeys: [.fileSizeKey])
        let snapshot = analysis.latestSnapshot
        let searchSections = makeHistorySearchSections(
            url: candidate.url,
            metadata: metadata,
            snapshot: snapshot
        )
        let searchIndex = searchSections.map(\.text).joined(separator: " ")
        return MeetingHistoryItem(
            id: candidate.url.path,
            url: candidate.url,
            modificationDate: candidate.modificationDate,
            fileSize: values?.fileSize ?? 0,
            metadata: metadata,
            summary: snapshot?.currentIssue.summary,
            topicCount: snapshot?.topicTimeline.count ?? 0,
            decisionCount: snapshot?.decisionCandidates.filter { $0.status != .deleted }.count ?? 0,
            actionCount: snapshot?.actionItemCandidates.filter { $0.status != .deleted }.count ?? 0,
            hasAnalysis: snapshot != nil,
            isCompleted: analysis.isCompleted,
            searchIndex: searchIndex,
            searchSections: searchSections,
            summaryPreview: snapshot?.currentIssue.summary.truncatedForHistoryRow()
        )
    }

    private func makeHistorySearchSections(
        url: URL,
        metadata: MeetingMetadata,
        snapshot: AnalysisSnapshot?
    ) -> [MeetingHistorySearchSection] {
        var sections: [MeetingHistorySearchSection] = [
            .init(field: .title, text: metadata.displayTitle, weight: 92),
            .init(field: .file, text: url.deletingPathExtension().lastPathComponent, weight: 60)
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

        if let snapshot {
            sections.append(.init(field: .currentIssue, text: snapshot.currentIssue.summary, weight: 80))
            if !snapshot.currentIssue.openQuestions.isEmpty {
                sections.append(.init(field: .currentIssue, text: snapshot.currentIssue.openQuestions.joined(separator: " "), weight: 70))
            }

            for topic in snapshot.topicTimeline {
                sections.append(
                    .init(
                        field: .topic,
                        text: "\(topic.title) \(topic.summary)",
                        weight: 58,
                        timestamp: topic.startTimestamp
                    )
                )
            }

            for decision in snapshot.decisionCandidates where decision.status != .deleted {
                sections.append(
                    .init(
                        field: decision.status == .confirmed ? .confirmedDecision : .decision,
                        text: [decision.text, decision.speaker].compactMap { $0 }.joined(separator: " "),
                        weight: decision.status == .confirmed ? 96 : 68,
                        timestamp: decision.evidenceTimestamp
                    )
                )
            }

            for action in snapshot.actionItemCandidates where action.status != .deleted {
                sections.append(
                    .init(
                        field: action.status == .confirmed ? .confirmedAction : .action,
                        text: [action.assignee, action.task, action.deadline, action.speaker].compactMap { $0 }.joined(separator: " "),
                        weight: action.status == .confirmed ? 96 : 68,
                        timestamp: action.evidenceTimestamp
                    )
                )
            }

            if !snapshot.risksOrNotes.isEmpty {
                sections.append(.init(field: .note, text: snapshot.risksOrNotes.joined(separator: " "), weight: 42))
            }
        }

        if includeRawTranscriptSearch {
            let rawPreview = loadTranscriptSearchPreview(from: url)
            if !rawPreview.isEmpty {
                sections.append(contentsOf: rawTranscriptSearchSections(from: rawPreview))
            }
        }

        return sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func loadMetadataPreview(from url: URL) -> MeetingMetadata {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return MeetingMetadata()
        }
        defer {
            try? handle.close()
        }
        let data = (try? handle.read(upToCount: 16_384)) ?? Data()
        guard !data.isEmpty else {
            return MeetingMetadata()
        }
        let text = TranscriptTextDecoder.decode(data)
        return TranscriptParser.parse(text).metadata
    }

    private func loadTranscriptSearchPreview(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ""
        }
        defer {
            try? handle.close()
        }
        let data = (try? handle.read(upToCount: 32_768)) ?? Data()
        guard !data.isEmpty else {
            return ""
        }
        return TranscriptTextDecoder.decode(data)
    }

    private func rawTranscriptSearchSections(from rawPreview: String) -> [MeetingHistorySearchSection] {
        rawPreview
            .components(separatedBy: .newlines)
            .prefix(rawTranscriptSearchLineLimit)
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

private extension String {
    func truncatedForHistoryRow(limit: Int = 180) -> String {
        guard count > limit else {
            return self
        }
        return String(prefix(limit - 1)) + "…"
    }
}

private func sortedUnique(_ values: [String]) -> [String] {
    Array(
        Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    )
    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

private func buildMeetingHistorySearchResults(
    items: [MeetingHistoryItem],
    query: String,
    facetSelection: MeetingHistoryFacetSelection,
    sortOrder: MeetingHistorySortOrder,
    databaseMatchesByPath: [String: MeetingHistorySearchMatch]
) -> [MeetingHistorySearchResult] {
    let facetFilteredItems = items.filter {
        facetSelection.matches($0.filterDocument)
    }
    let matchedResults = facetFilteredItems.compactMap { item -> MeetingHistorySearchResult? in
        let databaseMatch = databaseMatchesByPath[item.id]
        guard let match = databaseMatch ?? item.searchMatch(for: query) else {
            return nil
        }
        let anchorTimestamp = match.timestamp ?? databaseMatch?.timestamp ?? item.searchAnchorMatch(for: query)?.timestamp
        return MeetingHistorySearchResult(item: item, match: match, anchorTimestamp: anchorTimestamp)
    }
    return sortMeetingHistorySearchResults(
        matchedResults,
        sortOrder: sortOrder,
        queryIsEmpty: false
    )
}

private func sortMeetingHistorySearchResults(
    _ results: [MeetingHistorySearchResult],
    sortOrder: MeetingHistorySortOrder,
    queryIsEmpty: Bool
) -> [MeetingHistorySearchResult] {
    results.sorted { lhs, rhs in
        if sortOrder == .newest || queryIsEmpty {
            if lhs.item.modificationDate == rhs.item.modificationDate {
                let lhsScore = lhs.match?.score ?? 0
                let rhsScore = rhs.match?.score ?? 0
                if lhsScore == rhsScore {
                    return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
                }
                return lhsScore > rhsScore
            }
            return lhs.item.modificationDate > rhs.item.modificationDate
        }
        let lhsScore = lhs.match?.score ?? 0
        let rhsScore = rhs.match?.score ?? 0
        if lhsScore == rhsScore {
            if lhs.item.modificationDate == rhs.item.modificationDate {
                return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
            }
            return lhs.item.modificationDate > rhs.item.modificationDate
        }
        return lhsScore > rhsScore
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedFolderURL: URL?
    @Published var activeTranscriptURL: URL?
    @Published var liveActiveTranscriptURL: URL?
    @Published var meetingHistoryItems: [MeetingHistoryItem] = [] {
        didSet {
            refreshFilteredMeetingHistoryResults()
        }
    }
    @Published private(set) var filteredMeetingHistorySearchResults: [MeetingHistorySearchResult] = []
    @Published var historySearchText = "" {
        didSet {
            scheduleHistorySearchRefresh(for: historySearchText)
        }
    }
    @Published var historyDateFilter: MeetingHistoryDateFacet = .all {
        didSet {
            refreshFilteredMeetingHistoryResults()
        }
    }
    @Published var historyParticipantFilter: String? {
        didSet {
            refreshFilteredMeetingHistoryResults()
        }
    }
    @Published var historyRoomFilter: String? {
        didSet {
            refreshFilteredMeetingHistoryResults()
        }
    }
    @Published var historyCompletionFilter: MeetingHistoryCompletionFacet = .all {
        didSet {
            refreshFilteredMeetingHistoryResults()
        }
    }
    @Published var historyCandidateFilter: MeetingHistoryCandidateFacet = .all {
        didSet {
            refreshFilteredMeetingHistoryResults()
        }
    }
    @Published var historySortOrder: MeetingHistorySortOrder = .newest {
        didSet {
            refreshFilteredMeetingHistoryResults()
        }
    }
    @Published var liveMeetingUpdated = false
    @Published var rawTranscript = ""
    @Published var rawTranscriptPreviewLines: [String] = []
    @Published var rawTranscriptRevision = 0
    @Published var transcriptFocusRequest: TranscriptFocusRequest?
    @Published var highlightedTranscriptLineID: Int?
    @Published var rawTranscriptLineCount = 0
    @Published var metadata = MeetingMetadata()
    @Published var statusMessage = "transcript 폴더를 선택해 주세요."
    @Published var settings: AppSettings
    @Published var analysisState = MeetingAnalysisState()
    @Published var analysisStatus: AnalysisRuntimeStatus = .idle
    @Published var transcriptUpdatedAt: Date?
    @Published var transcriptRunMode: TranscriptRunMode = .liveWatch
    @Published var testRunPlaybackStatus: TestRunPlaybackStatus = .idle
    @Published var testRunProgressText = ""
    @Published var testRunSpeedMultiplier = 1.0
    @Published private(set) var searchIndexProgress = MeetingSearchIndexProgress.idle
    @Published var isShowingOnboarding = false
    @Published private(set) var detectedSomaRecordingsFolder: SomaRecordingsFolderDetection?
    @Published private(set) var providerAvailability = LLMProviderAvailability(
        isCodexAvailable: false,
        isClaudeCodeAvailable: false
    )

    private let bookmarkStore: FolderBookmarkStore
    private let stateStore: ApplicationStateStore
    private let searchDatabase: MeetingSearchDatabase?
    private let scheduler = AnalysisScheduler()
    private var timer: Timer?
    private var replayTimer: Timer?
    private var replayCursor: TranscriptReplayCursor?
    private var replaySourceURL: URL?
    private var analysisTask: Task<Void, Never>?
    private var activeAnalysisRequest: AnalysisRequest?
    private var activeAnalysisWindow: AnalysisTranscriptWindow?
    private var activeAnalysisAttemptID: String?
    private var latestSnapshotIsLocalFallback = false
    private var rawReadOffset: UInt64 = 0
    private var securityScopeActive = false
    private var lastAutomaticAnalysisAt: Date?
    private var finalAnalysisTriggeredForMeetingID: String?
    private var finalAnalysisRetryCounts: [String: Int] = [:]
    private var lastHistoryRefreshAt: Date?
    private var lastHistorySignature = ""
    private let rawTranscriptSearchLineLimit = 240
    private var debouncedHistorySearchText = ""
    private var historySearchDebounceTask: Task<Void, Never>?
    private var historyRefreshTask: Task<Void, Never>?
    private var historyIncludesRawTranscriptSearch = false
    private var searchIndexBuildTask: Task<Void, Never>?
    private var lastReadySearchIndexSignature: String?
    private var searchDatabaseQueryTask: Task<Void, Never>?
    private var searchDatabaseQueryGeneration = 0
    private var searchDatabaseMatchesByPath: [String: MeetingHistorySearchMatch] = [:]
    private var searchDatabaseMatchQuery = ""
    private let historySearchDebounceDelayNanoseconds: UInt64 = 300_000_000
    private var transcriptHighlightClearTask: Task<Void, Never>?
    private var transcriptFocusToken = 0
    private var historyLiveBaselineCandidate: TranscriptFileCandidate?
    private let replayFallbackDelaySeconds: TimeInterval = 0.35
    private let replayMinimumDelaySeconds: TimeInterval = 0.05
    private let failedAnalysisRetryDelaySeconds = 8
    private let finalAnalysisMaxRetries = 2
    private let finalAnalysisRetryDelaySeconds = 6
    private let automaticCatchUpChunkCharacters = 5_000
    private let minimumAutomaticAnalysisElapsedSeconds = 60

    init(stateStore: ApplicationStateStore = ApplicationStateStore()) {
        self.stateStore = stateStore
        self.bookmarkStore = FolderBookmarkStore(stateStore: stateStore)
        self.searchDatabase = (try? stateStore.searchIndexDatabaseURL()).map(MeetingSearchDatabase.init(databaseURL:))
        self.settings = stateStore.loadSettings()
        self.detectedSomaRecordingsFolder = SomaRecordingsFolderDetector().detect()
        self.providerAvailability = LLMProviderAvailabilityDetector().detect()
        applyInitialProviderAvailability()
        self.isShowingOnboarding = !settings.hasCompletedOnboarding
        restoreLastFolder()
    }

    private func applyInitialProviderAvailability() {
        guard !settings.hasCompletedOnboarding else {
            return
        }

        if !providerAvailability.hasSubscriptionProvider {
            settings.automaticAnalysisEnabled = false
        }
        try? stateStore.saveSettings(settings)
    }

    var selectedProvider: LLMProviderKind {
        settings.selectedProvider
    }

    var isAnalysisRunning: Bool {
        if case .running = analysisStatus {
            return true
        }
        return false
    }

    var isTestRunActive: Bool {
        transcriptRunMode == .testRun
    }

    var isHistoryMode: Bool {
        transcriptRunMode == .history
    }

    var filteredMeetingHistoryItems: [MeetingHistoryItem] {
        filteredMeetingHistorySearchResults.map(\.item)
    }

    var historyFacetSelection: MeetingHistoryFacetSelection {
        MeetingHistoryFacetSelection(
            date: historyDateFilter,
            participant: historyParticipantFilter,
            room: historyRoomFilter,
            completion: historyCompletionFilter,
            candidate: historyCandidateFilter
        )
    }

    var hasActiveHistoryFilters: Bool {
        historyFacetSelection.hasActiveFilters
    }

    var historyAvailableParticipants: [String] {
        sortedUnique(meetingHistoryItems.flatMap(\.metadata.participants))
    }

    var historyAvailableRooms: [String] {
        sortedUnique(meetingHistoryItems.compactMap(\.metadata.room).filter { !$0.isEmpty })
    }

    private func makeFilteredMeetingHistorySearchResults() -> [MeetingHistorySearchResult] {
        let trimmed = debouncedHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let facetSelection = historyFacetSelection
        let facetFilteredItems = meetingHistoryItems.filter {
            facetSelection.matches($0.filterDocument)
        }
        guard !trimmed.isEmpty else {
            return sortedHistorySearchResults(
                facetFilteredItems.map { MeetingHistorySearchResult(item: $0, match: nil, anchorTimestamp: nil) },
                queryIsEmpty: true
            )
        }
        let matchedResults = facetFilteredItems
            .compactMap { item -> MeetingHistorySearchResult? in
                let databaseMatch = searchDatabaseMatchQuery == trimmed ? searchDatabaseMatchesByPath[item.id] : nil
                guard let match = databaseMatch ?? item.searchMatch(for: trimmed) else {
                    return nil
                }
                let anchorTimestamp = match.timestamp ?? databaseMatch?.timestamp ?? item.searchAnchorMatch(for: trimmed)?.timestamp
                return MeetingHistorySearchResult(item: item, match: match, anchorTimestamp: anchorTimestamp)
            }
        return sortedHistorySearchResults(matchedResults, queryIsEmpty: false)
    }

    private func sortedHistorySearchResults(
        _ results: [MeetingHistorySearchResult],
        queryIsEmpty: Bool
    ) -> [MeetingHistorySearchResult] {
        sortMeetingHistorySearchResults(
            results,
            sortOrder: historySortOrder,
            queryIsEmpty: queryIsEmpty
        )
    }

    private func refreshFilteredMeetingHistoryResults() {
        let trimmed = debouncedHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchDatabaseQueryGeneration += 1
            searchDatabaseQueryTask?.cancel()
            searchDatabaseMatchesByPath = [:]
            searchDatabaseMatchQuery = ""
            filteredMeetingHistorySearchResults = makeFilteredMeetingHistorySearchResults()
            return
        }
        refreshSearchDatabaseMatches(for: trimmed)
    }

    private func scheduleHistorySearchRefresh(for query: String) {
        historySearchDebounceTask?.cancel()
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            debouncedHistorySearchText = ""
            searchDatabaseQueryTask?.cancel()
            searchDatabaseMatchesByPath = [:]
            searchDatabaseMatchQuery = ""
            refreshFilteredMeetingHistoryResults()
            return
        }

        historySearchDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.historySearchDebounceDelayNanoseconds ?? 300_000_000)
            guard !Task.isCancelled, let self else {
                return
            }
            debouncedHistorySearchText = query
            refreshSearchDatabaseMatches(for: query)
        }
    }

    private func refreshSearchDatabaseMatches(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchDatabaseMatchesByPath = [:]
            searchDatabaseMatchQuery = trimmed
            return
        }

        let items = meetingHistoryItems
        let facetSelection = historyFacetSelection
        let sortOrder = historySortOrder
        let databaseIsReady = searchIndexProgress.isReady
        searchDatabaseQueryGeneration += 1
        let generation = searchDatabaseQueryGeneration

        searchDatabaseQueryTask?.cancel()
        searchDatabaseQueryTask = Task(priority: .utility) { [weak self, searchDatabase, trimmed, items, facetSelection, sortOrder, databaseIsReady, generation] in
            let results: ([String: MeetingHistorySearchMatch], [MeetingHistorySearchResult]) = await Task.detached(priority: .utility) {
                let databaseResults: [MeetingSearchDatabaseResult] = if databaseIsReady, let searchDatabase {
                    (try? searchDatabase.search(query: trimmed, includeSemantic: false)) ?? []
                } else {
                    []
                }
                guard !Task.isCancelled else {
                    return ([:], [])
                }
                let databaseMatchesByPath = Dictionary(
                    uniqueKeysWithValues: databaseResults.map { ($0.path, $0.match) }
                )
                let filteredResults = buildMeetingHistorySearchResults(
                    items: items,
                    query: trimmed,
                    facetSelection: facetSelection,
                    sortOrder: sortOrder,
                    databaseMatchesByPath: databaseMatchesByPath
                )
                return (databaseMatchesByPath, filteredResults)
            }
            .value
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      self.searchDatabaseQueryGeneration == generation,
                      self.debouncedHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed,
                      self.historyFacetSelection == facetSelection,
                      self.historySortOrder == sortOrder else {
                    return
                }
                self.searchDatabaseMatchesByPath = results.0
                self.searchDatabaseMatchQuery = trimmed
                self.filteredMeetingHistorySearchResults = results.1
            }
        }
    }

    func openHistorySearchResult(_ item: MeetingHistoryItem, anchorTimestamp: String?) {
        openHistoryTranscript(item.url)
        guard let timestamp = anchorTimestamp else {
            return
        }
        focusTranscriptLine(matching: timestamp, metadata: item.metadata)
    }

    func resetHistoryFilters() {
        historyDateFilter = .all
        historyParticipantFilter = nil
        historyRoomFilter = nil
        historyCompletionFilter = .all
        historyCandidateFilter = .all
    }

    var canPauseOrResumeTestRun: Bool {
        testRunPlaybackStatus == .running || testRunPlaybackStatus == .paused
    }

    var testRunSpeedText: String {
        "\(Int(testRunSpeedMultiplier))x"
    }

    func chooseFolder(initialDirectoryURL: URL? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Transcript 폴더 선택"
        panel.message = "Recordings 폴더 또는 transcript `.txt` 파일이 쌓이는 폴더를 선택하세요."
        panel.prompt = "선택"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = initialDirectoryURL ?? selectedFolderURL ?? detectedSomaRecordingsFolder?.url

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try bookmarkStore.save(folderURL: url)
            startWatching(folderURL: url)
        } catch {
            statusMessage = "폴더 권한 저장 실패: \(error.localizedDescription)"
        }
    }

    func chooseDetectedSomaRecordingsFolder() {
        guard let detectedSomaRecordingsFolder else {
            statusMessage = "Soma recordings folder를 감지하지 못했습니다."
            return
        }
        chooseFolder(initialDirectoryURL: detectedSomaRecordingsFolder.url)
    }

    func restoreLastFolder() {
        guard let url = bookmarkStore.load() else {
            return
        }
        startWatching(folderURL: url)
    }

    func startWatching(folderURL: URL) {
        stopReplayTimer()
        transcriptRunMode = .liveWatch
        testRunPlaybackStatus = .idle
        testRunProgressText = ""
        liveMeetingUpdated = false
        historyLiveBaselineCandidate = nil
        timer?.invalidate()
        timer = nil
        if securityScopeActive {
            selectedFolderURL?.stopAccessingSecurityScopedResource()
        }
        searchIndexBuildTask?.cancel()
        searchDatabaseQueryTask?.cancel()
        lastReadySearchIndexSignature = nil

        selectedFolderURL = folderURL
        securityScopeActive = folderURL.startAccessingSecurityScopedResource()
        statusMessage = "폴더 감시 중: \(folderURL.path)"

        refreshMeetingHistory(force: true)
        scanFolder()
        ensureFolderScanTimer()
    }

    private func ensureFolderScanTimer() {
        guard selectedFolderURL != nil, timer == nil else {
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanFolder()
                self?.triggerAutomaticAnalysisIfNeeded()
            }
        }
    }

    func chooseTestRunFile() {
        let panel = NSOpenPanel()
        panel.title = "Test Run transcript 선택"
        panel.message = "시간순으로 replay할 `.txt` 회의록 파일을 선택하세요."
        panel.prompt = "Test Run"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        if let selectedFolderURL {
            panel.directoryURL = selectedFolderURL
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        startTestRun(fileURL: url)
    }

    func startTestRunFromHistory(_ item: MeetingHistoryItem) {
        startTestRun(fileURL: item.url)
    }

    func toggleTestRunPause() {
        switch testRunPlaybackStatus {
        case .running:
            replayTimer?.invalidate()
            replayTimer = nil
            testRunPlaybackStatus = .paused
            statusMessage = "Test Run 일시정지: \(replaySourceURL?.lastPathComponent ?? "-")"
        case .paused:
            testRunPlaybackStatus = .running
            statusMessage = "Test Run 재생 중: \(replaySourceURL?.lastPathComponent ?? "-")"
            appendTimestampPacedReplayFrame()
        case .idle, .completed:
            break
        }
    }

    func updateTestRunSpeed(_ multiplier: Double) {
        testRunSpeedMultiplier = max(1.0, multiplier)
        if testRunPlaybackStatus == .running, replayTimer != nil {
            scheduleReplayTimer(after: replayMinimumDelaySeconds)
        }
    }

    func openHistoryTranscript(_ url: URL) {
        stopReplayTimer()
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRequest = nil
        activeAnalysisAttemptID = nil
        latestSnapshotIsLocalFallback = false
        replayCursor = nil
        replaySourceURL = nil
        transcriptRunMode = .history
        testRunPlaybackStatus = .idle
        testRunProgressText = ""
        captureHistoryLiveBaseline()
        loadTranscriptForViewing(url, statusPrefix: "History")
        ensureFolderScanTimer()
    }

    func returnToLiveWatch() {
        stopReplayTimer()
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRequest = nil
        activeAnalysisAttemptID = nil
        latestSnapshotIsLocalFallback = false
        replayCursor = nil
        replaySourceURL = nil
        transcriptRunMode = .liveWatch
        testRunPlaybackStatus = .idle
        testRunProgressText = ""
        liveMeetingUpdated = false
        historyLiveBaselineCandidate = nil
        statusMessage = "Live Watch로 돌아왔습니다."
        if selectedFolderURL != nil {
            scanFolder()
            ensureFolderScanTimer()
        } else {
            activeTranscriptURL = nil
            liveActiveTranscriptURL = nil
            rawTranscript = ""
            rawTranscriptPreviewLines = []
            transcriptFocusRequest = nil
            highlightedTranscriptLineID = nil
            rawTranscriptLineCount = 0
            metadata = MeetingMetadata()
            analysisState = MeetingAnalysisState()
            analysisStatus = .idle
            transcriptUpdatedAt = nil
            rawReadOffset = 0
            Task {
                await scheduler.setActiveMeetingID(nil)
            }
        }
    }

    func stopTestRunAndReturnToLive() {
        returnToLiveWatch()
    }

    func saveSettings() {
        settings = AppSettings(
            selectedProvider: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            automaticAnalysisEnabled: settings.automaticAnalysisEnabled,
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            analysisTriggerPreset: settings.analysisTriggerPreset,
            analysisCadenceSeconds: settings.analysisCadenceSeconds,
            providerTimeoutSeconds: settings.providerTimeoutSeconds,
            customProviderCommand: settings.customProviderCommand
        )
        try? stateStore.saveSettings(settings)
    }

    func setAutomaticAnalysisEnabled(_ isEnabled: Bool) {
        settings.automaticAnalysisEnabled = isEnabled
        saveSettings()

        if !isEnabled {
            cancelAutomaticAnalysisIfNeeded()
        }
    }

    func updateProvider(_ provider: LLMProviderKind) {
        settings.selectedProvider = provider
        saveSettings()
    }

    func updateModelPreset(_ modelPreset: LLMModelPreset) {
        settings.modelPreset = modelPreset
        saveSettings()
    }

    func updateAnalysisTriggerPreset(_ preset: AnalysisTriggerPreset) {
        settings.analysisTriggerPreset = preset
        saveSettings()
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        isShowingOnboarding = false
        saveSettings()
    }

    func showOnboarding() {
        isShowingOnboarding = true
    }

    func forgetSelectedFolder() {
        timer?.invalidate()
        timer = nil
        stopReplayTimer()
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRequest = nil
        activeAnalysisAttemptID = nil
        searchIndexBuildTask?.cancel()
        searchDatabaseQueryTask?.cancel()
        if securityScopeActive {
            selectedFolderURL?.stopAccessingSecurityScopedResource()
        }
        transcriptRunMode = .liveWatch
        testRunPlaybackStatus = .idle
        testRunProgressText = ""
        replayCursor = nil
        replaySourceURL = nil
        selectedFolderURL = nil
        activeTranscriptURL = nil
        liveActiveTranscriptURL = nil
        meetingHistoryItems = []
        historySearchText = ""
        searchIndexProgress = .idle
        lastReadySearchIndexSignature = nil
        searchDatabaseMatchesByPath = [:]
        searchDatabaseMatchQuery = ""
        liveMeetingUpdated = false
        historyLiveBaselineCandidate = nil
        rawTranscript = ""
        rawTranscriptPreviewLines = []
        transcriptFocusRequest = nil
        highlightedTranscriptLineID = nil
        rawTranscriptLineCount = 0
        metadata = MeetingMetadata()
        analysisState = MeetingAnalysisState()
        analysisStatus = .idle
        transcriptUpdatedAt = nil
        rawReadOffset = 0
        securityScopeActive = false
        try? stateStore.deleteFolderBookmark()
        statusMessage = "선택한 폴더를 잊었습니다."
        Task {
            await scheduler.setActiveMeetingID(nil)
        }
    }

    func clearCurrentAnalysisState() {
        guard let activeTranscriptURL else {
            return
        }
        try? stateStore.clearAnalysisState(for: activeTranscriptURL)
        analysisState = MeetingAnalysisState()
        analysisStatus = .idle
        latestSnapshotIsLocalFallback = false
        clearFinalRetryCounts(for: activeTranscriptURL)
        refreshMeetingHistory(force: true)
        Task {
            await scheduler.seedSnapshot(nil, for: meetingID(for: activeTranscriptURL))
        }
    }

    func triggerManualAnalysis() {
        triggerAnalysis(reason: "manual")
    }

    func exportCurrentIntelligenceMarkdown() {
        guard let activeTranscriptURL, analysisState.latestSnapshot != nil else {
            statusMessage = "저장할 Meeting Intelligence가 아직 없습니다."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Meeting Intelligence Markdown 저장"
        panel.prompt = "저장"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = activeTranscriptURL.deletingLastPathComponent()
        let baseName = activeTranscriptURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName)-meeting-intelligence.md"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let markdown = MeetingIntelligenceMarkdownExporter.markdown(
            metadata: metadata,
            sourceFileName: activeTranscriptURL.lastPathComponent,
            state: analysisState
        )
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Markdown 저장 완료: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Markdown 저장 실패: \(error.localizedDescription)"
        }
    }

    func confirmDecision(_ id: String) {
        updateCandidate(id: id, status: .confirmed)
    }

    func unconfirmDecision(_ id: String) {
        updateCandidate(id: id, status: .candidate)
    }

    func deleteDecision(_ id: String) {
        updateCandidate(id: id, status: .deleted)
    }

    func editDecision(_ id: String, text: String) {
        analysisState.editDecisionCandidate(id: id, text: text)
        persistCandidateStateChange()
    }

    func restoreOriginalDecision(_ id: String) {
        analysisState.restoreOriginalDecisionCandidate(id: id)
        persistCandidateStateChange()
    }

    func confirmActionItem(_ id: String) {
        updateCandidate(id: id, status: .confirmed)
    }

    func unconfirmActionItem(_ id: String) {
        updateCandidate(id: id, status: .candidate)
    }

    func deleteActionItem(_ id: String) {
        updateCandidate(id: id, status: .deleted)
    }

    func editActionItem(_ id: String, assignee: String?, task: String, deadline: String?) {
        analysisState.editActionItemCandidate(id: id, assignee: assignee, task: task, deadline: deadline)
        persistCandidateStateChange()
    }

    func restoreOriginalActionItem(_ id: String) {
        analysisState.restoreOriginalActionItemCandidate(id: id)
        persistCandidateStateChange()
    }

    private func startTestRun(fileURL: URL) {
        timer?.invalidate()
        timer = nil
        stopReplayTimer()
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRequest = nil
        activeAnalysisAttemptID = nil
        latestSnapshotIsLocalFallback = false

        do {
            let data = try Data(contentsOf: fileURL)
            let fullTranscript = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .unicode)
                ?? ""

            transcriptRunMode = .testRun
            testRunPlaybackStatus = .running
            replaySourceURL = fileURL
            replayCursor = TranscriptReplayCursor(rawTranscript: fullTranscript)
            activeTranscriptURL = fileURL
            rawTranscript = ""
            rawTranscriptPreviewLines = []
            transcriptFocusRequest = nil
            highlightedTranscriptLineID = nil
            rawTranscriptLineCount = 0
            rawReadOffset = 0
            lastAutomaticAnalysisAt = nil
            finalAnalysisTriggeredForMeetingID = nil
            clearFinalRetryCounts(for: fileURL)
            metadata = MeetingMetadata()
            analysisState = MeetingAnalysisState()
            analysisStatus = .idle
            transcriptUpdatedAt = nil
            updateTestRunProgress(currentLine: 0, totalLines: replayCursor?.totalLines ?? 0)
            statusMessage = "Test Run 재생 중: \(fileURL.lastPathComponent)"

            let id = meetingID(for: fileURL)
            Task {
                await scheduler.setActiveMeetingID(id)
                await scheduler.seedSnapshot(nil, for: id)
            }

            appendReplayPreambleIfNeeded()
            if testRunPlaybackStatus == .running {
                appendTimestampPacedReplayFrame()
            }
        } catch {
            statusMessage = "Test Run 파일 읽기 실패: \(error.localizedDescription)"
            testRunPlaybackStatus = .idle
        }
    }

    private func scheduleReplayTimer(after delay: TimeInterval) {
        stopReplayTimer()
        let adjustedDelay = TranscriptReplayCursor.adjustedDelay(
            delay,
            speedMultiplier: testRunSpeedMultiplier,
            minimumDelaySeconds: replayMinimumDelaySeconds
        )
        replayTimer = Timer.scheduledTimer(withTimeInterval: adjustedDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.appendTimestampPacedReplayFrame()
            }
        }
    }

    private func stopReplayTimer() {
        replayTimer?.invalidate()
        replayTimer = nil
    }

    private func appendReplayPreambleIfNeeded() {
        guard transcriptRunMode == .testRun,
              var cursor = replayCursor,
              let activeTranscriptURL,
              let frame = cursor.advancePreambleFrame(delayAfterSeconds: replayMinimumDelaySeconds) else {
            return
        }

        replayCursor = cursor
        applyReplayFrame(frame, sourceURL: activeTranscriptURL)
    }

    private func appendTimestampPacedReplayFrame() {
        guard transcriptRunMode == .testRun,
              var cursor = replayCursor,
              let activeTranscriptURL,
              let frame = cursor.advanceTimestampPacedFrame(
                fallbackDelaySeconds: replayFallbackDelaySeconds,
                minimumDelaySeconds: replayMinimumDelaySeconds
              ) else {
            return
        }

        replayCursor = cursor
        applyReplayFrame(frame, sourceURL: activeTranscriptURL)

        if frame.isCompleted {
            stopReplayTimer()
            testRunPlaybackStatus = .completed
            statusMessage = "Test Run 완료: \(activeTranscriptURL.lastPathComponent)"
            triggerAutomaticAnalysisIfNeeded()
        } else if testRunPlaybackStatus == .running {
            scheduleReplayTimer(after: frame.delayAfterSeconds)
        }
    }

    private func applyReplayFrame(_ frame: TranscriptReplayFrame, sourceURL: URL) {
        rawTranscript += frame.text
        rawReadOffset += UInt64(frame.text.data(using: .utf8)?.count ?? frame.text.count)
        appendTranscriptPreview(frame.text)
        transcriptUpdatedAt = Date()
        refreshParsedState(
            for: sourceURL,
            parseMetadata: metadata.dateTime == nil && metadata.participants.isEmpty,
            endMarkerSource: String(rawTranscript.suffix(1_024))
        )
        updateTestRunProgress(currentLine: frame.currentLine, totalLines: frame.totalLines)
        refreshTestRunFallbackIfNeeded(message: "Test Run replay에서 로컬 preview를 갱신했습니다.")
        triggerAutomaticAnalysisIfNeeded()
    }

    private func updateTestRunProgress(currentLine: Int, totalLines: Int) {
        guard totalLines > 0 else {
            testRunProgressText = "0 / 0 lines"
            return
        }
        testRunProgressText = "\(currentLine) / \(totalLines) lines"
    }

    private func refreshTestRunFallbackIfNeeded(message: String) {
        guard transcriptRunMode == .testRun,
              latestSnapshotIsLocalFallback || analysisState.latestSnapshot == nil,
              let activeTranscriptURL,
              !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let request = AnalysisRequest(
            meetingID: meetingID(for: activeTranscriptURL),
            metadata: metadata,
            rawTranscript: rawTranscript,
            previousSnapshot: analysisState.latestSnapshot,
            confirmedCandidateIDs: analysisState.confirmedCandidateIDs,
            deletedCandidateIDs: analysisState.deletedCandidateIDs,
            providerKind: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            lastAnalyzedTranscriptCharacterCount: analysisState.analyzedTranscriptCharacterCount
        )
        let fallbackSnapshot = LocalAnalysisFallback.snapshot(for: request, message: message)
        analysisState.latestSnapshot = analysisState.applyingCandidateState(to: fallbackSnapshot)
        analysisState.updatedAt = Date()
        latestSnapshotIsLocalFallback = true
        try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
    }

    private func refreshMeetingHistory(
        force: Bool = false,
        includeRawTranscriptSearch: Bool? = nil
    ) {
        guard let selectedFolderURL else {
            historyRefreshTask?.cancel()
            historyRefreshTask = nil
            meetingHistoryItems = []
            lastHistorySignature = ""
            lastHistoryRefreshAt = nil
            historyIncludesRawTranscriptSearch = false
            return
        }

        let shouldIncludeRawTranscriptSearch = includeRawTranscriptSearch
            ?? (historyIncludesRawTranscriptSearch
                || !debouncedHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let now = Date()
        if !force, let lastHistoryRefreshAt, now.timeIntervalSince(lastHistoryRefreshAt) < 10 {
            return
        }
        if let historyRefreshTask {
            if force {
                historyRefreshTask.cancel()
            } else {
                return
            }
        }

        lastHistoryRefreshAt = now
        let stateStore = stateStore
        let lineLimit = rawTranscriptSearchLineLimit
        let searchIndexExclusionURL = activeSearchIndexExclusionURL()
        historyRefreshTask = Task { [weak self, selectedFolderURL, stateStore, lineLimit, force, shouldIncludeRawTranscriptSearch, searchIndexExclusionURL] in
            let result = await Task.detached(priority: .utility) {
                MeetingHistoryBuilder(
                    stateStore: stateStore,
                    rawTranscriptSearchLineLimit: lineLimit,
                    includeRawTranscriptSearch: shouldIncludeRawTranscriptSearch,
                    searchIndexExclusionURL: searchIndexExclusionURL
                )
                .build(folderURL: selectedFolderURL)
            }
            .value

            guard let self else {
                return
            }
            self.historyRefreshTask = nil
            guard !Task.isCancelled, self.selectedFolderURL == selectedFolderURL else {
                return
            }
            guard force || result.signature != self.lastHistorySignature else {
                return
            }
            self.lastHistorySignature = result.signature
            self.historyIncludesRawTranscriptSearch = result.includesRawTranscriptSearch
            self.meetingHistoryItems = result.items
            self.startSearchIndexBuildIfNeeded(
                folderURL: selectedFolderURL,
                fileSignature: result.searchIndexFileSignature,
                excludedURL: searchIndexExclusionURL
            )
        }
    }

    private func activeSearchIndexExclusionURL() -> URL? {
        guard let liveURL = liveActiveTranscriptURL ?? activeTranscriptURL,
              isTranscriptOpenForSearchIndex(liveURL) else {
            return nil
        }
        return liveURL
    }

    private func startSearchIndexBuildIfNeeded(folderURL: URL, fileSignature: String, excludedURL: URL?) {
        guard let searchDatabase else {
            searchIndexProgress = MeetingSearchIndexProgress(
                state: .failed("SQLite database URL을 만들 수 없습니다."),
                completed: 0,
                total: 0
            )
            return
        }

        if excludedURL != nil {
            searchIndexBuildTask?.cancel()
            searchIndexBuildTask = nil
            if !searchIndexProgress.isReady {
                searchIndexProgress = .idle
            }
            return
        }

        if lastReadySearchIndexSignature == fileSignature, searchIndexProgress.isReady {
            return
        }

        if let searchIndexBuildTask, !searchIndexBuildTask.isCancelled {
            return
        }

        let stateStore = stateStore
        let lineLimit = rawTranscriptSearchLineLimit
        searchIndexProgress = MeetingSearchIndexProgress(state: .checking, completed: 0, total: meetingHistoryItems.count)
        searchIndexBuildTask = Task(priority: .background) { [weak self, searchDatabase, stateStore, lineLimit, folderURL, fileSignature, excludedURL] in
            do {
                let storedSignature = try await Task.detached(priority: .background) {
                    try searchDatabase.storedSignature()
                }
                .value
                try Task.checkCancellation()

                if storedSignature == fileSignature {
                    await MainActor.run {
                        guard let self, self.selectedFolderURL == folderURL else {
                            return
                        }
                        self.searchIndexProgress = MeetingSearchIndexProgress(
                            state: .ready,
                            completed: self.meetingHistoryItems.count,
                            total: self.meetingHistoryItems.count
                        )
                        self.lastReadySearchIndexSignature = fileSignature
                        self.searchIndexBuildTask = nil
                        if !self.debouncedHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.refreshSearchDatabaseMatches(for: self.debouncedHistorySearchText)
                        }
                    }
                    return
                }

                let rawResult = await Task.detached(priority: .background) {
                    MeetingHistoryBuilder(
                        stateStore: stateStore,
                        rawTranscriptSearchLineLimit: lineLimit,
                        includeRawTranscriptSearch: true,
                        searchIndexExclusionURL: excludedURL
                    )
                    .build(folderURL: folderURL)
                }
                .value
                try Task.checkCancellation()
                let indexedItems = if let excludedURL {
                    rawResult.items.filter { $0.url != excludedURL }
                } else {
                    rawResult.items
                }

                let progressBox = SearchIndexProgressBox()
                let progressTask = Task { @MainActor [weak self, progressBox, folderURL] in
                    while !Task.isCancelled {
                        let snapshot = progressBox.snapshot()
                        guard let self, self.selectedFolderURL == folderURL else {
                            return
                        }
                        if snapshot.total > 0 {
                            self.searchIndexProgress = MeetingSearchIndexProgress(
                                state: .indexing,
                                completed: snapshot.completed,
                                total: snapshot.total
                            )
                        }
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    }
                }
                try Task.checkCancellation()
                try await Task.detached(priority: .background) {
                    try searchDatabase.rebuild(items: indexedItems, signature: rawResult.searchIndexFileSignature) { completed, total in
                        progressBox.update(completed: completed, total: total)
                    }
                }
                .value
                progressTask.cancel()

                await MainActor.run {
                    guard let self, self.selectedFolderURL == folderURL else {
                        return
                    }
                    self.searchIndexProgress = MeetingSearchIndexProgress(
                        state: .ready,
                        completed: indexedItems.count,
                        total: indexedItems.count
                    )
                    self.lastReadySearchIndexSignature = rawResult.searchIndexFileSignature
                    self.searchIndexBuildTask = nil
                    if !self.debouncedHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.refreshSearchDatabaseMatches(for: self.debouncedHistorySearchText)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.searchIndexBuildTask = nil
                }
            } catch {
                await MainActor.run {
                    guard let self, self.selectedFolderURL == folderURL else {
                        return
                    }
                    self.searchIndexProgress = MeetingSearchIndexProgress(
                        state: .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription),
                        completed: 0,
                        total: self.meetingHistoryItems.count
                    )
                    self.searchIndexBuildTask = nil
                }
            }
        }
    }

    private func isTranscriptOpenForSearchIndex(_ url: URL) -> Bool {
        if url == activeTranscriptURL, analysisState.isCompleted {
            return false
        }
        if url != activeTranscriptURL, stateStore.loadAnalysisState(for: url).isCompleted {
            return false
        }
        return !transcriptFileContainsEndMarker(url)
    }

    private func transcriptFileContainsEndMarker(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer {
            try? handle.close()
        }
        do {
            let fileSize = try handle.seekToEnd()
            let maxTailBytes: UInt64 = 8_192
            try handle.seek(toOffset: fileSize > maxTailBytes ? fileSize - maxTailBytes : 0)
            let data = try handle.readToEnd() ?? Data()
            guard !data.isEmpty else {
                return false
            }
            return TranscriptParser.containsEndMarker(TranscriptTextDecoder.decode(data))
        } catch {
            return false
        }
    }

    private func makeHistoryItem(from candidate: TranscriptFileCandidate) -> MeetingHistoryItem {
        let analysis = stateStore.loadAnalysisState(for: candidate.url)
        let metadata = stateStore.loadSession(for: candidate.url)?.metadata
            ?? loadMetadataPreview(from: candidate.url)
        let values = try? candidate.url.resourceValues(forKeys: [.fileSizeKey])
        let snapshot = analysis.latestSnapshot
        let searchSections = makeHistorySearchSections(
            url: candidate.url,
            metadata: metadata,
            snapshot: snapshot
        )
        let searchIndex = searchSections.map(\.text).joined(separator: " ")
        return MeetingHistoryItem(
            id: candidate.url.path,
            url: candidate.url,
            modificationDate: candidate.modificationDate,
            fileSize: values?.fileSize ?? 0,
            metadata: metadata,
            summary: snapshot?.currentIssue.summary,
            topicCount: snapshot?.topicTimeline.count ?? 0,
            decisionCount: snapshot?.decisionCandidates.filter { $0.status != .deleted }.count ?? 0,
            actionCount: snapshot?.actionItemCandidates.filter { $0.status != .deleted }.count ?? 0,
            hasAnalysis: snapshot != nil,
            isCompleted: analysis.isCompleted,
            searchIndex: searchIndex,
            searchSections: searchSections,
            summaryPreview: snapshot?.currentIssue.summary.truncatedForHistoryRow()
        )
    }

    private func makeHistorySearchSections(
        url: URL,
        metadata: MeetingMetadata,
        snapshot: AnalysisSnapshot?
    ) -> [MeetingHistorySearchSection] {
        var sections: [MeetingHistorySearchSection] = [
            .init(field: .title, text: metadata.displayTitle, weight: 92),
            .init(field: .file, text: url.deletingPathExtension().lastPathComponent, weight: 60)
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

        if let snapshot {
            sections.append(.init(field: .currentIssue, text: snapshot.currentIssue.summary, weight: 80))
            if !snapshot.currentIssue.openQuestions.isEmpty {
                sections.append(.init(field: .currentIssue, text: snapshot.currentIssue.openQuestions.joined(separator: " "), weight: 70))
            }

            for topic in snapshot.topicTimeline {
                sections.append(
                    .init(
                        field: .topic,
                        text: "\(topic.title) \(topic.summary)",
                        weight: 58,
                        timestamp: topic.startTimestamp
                    )
                )
            }

            for decision in snapshot.decisionCandidates where decision.status != .deleted {
                sections.append(
                    .init(
                        field: decision.status == .confirmed ? .confirmedDecision : .decision,
                        text: [decision.text, decision.speaker].compactMap { $0 }.joined(separator: " "),
                        weight: decision.status == .confirmed ? 96 : 68,
                        timestamp: decision.evidenceTimestamp
                    )
                )
            }

            for action in snapshot.actionItemCandidates where action.status != .deleted {
                sections.append(
                    .init(
                        field: action.status == .confirmed ? .confirmedAction : .action,
                        text: [action.assignee, action.task, action.deadline, action.speaker].compactMap { $0 }.joined(separator: " "),
                        weight: action.status == .confirmed ? 96 : 68,
                        timestamp: action.evidenceTimestamp
                    )
                )
            }

            if !snapshot.risksOrNotes.isEmpty {
                sections.append(.init(field: .note, text: snapshot.risksOrNotes.joined(separator: " "), weight: 42))
            }
        }

        let rawPreview = loadTranscriptSearchPreview(from: url)
        if !rawPreview.isEmpty {
            sections.append(contentsOf: rawTranscriptSearchSections(from: rawPreview))
        }

        return sections.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func patchMeetingHistoryItem(for url: URL) {
        guard let index = meetingHistoryItems.firstIndex(where: { $0.url == url }) else {
            refreshMeetingHistory(force: true)
            return
        }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let candidate = TranscriptFileCandidate(
            url: url,
            modificationDate: values?.contentModificationDate ?? meetingHistoryItems[index].modificationDate
        )
        meetingHistoryItems[index] = makeHistoryItem(from: candidate)
    }

    private func loadMetadataPreview(from url: URL) -> MeetingMetadata {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return MeetingMetadata()
        }
        defer {
            try? handle.close()
        }
        let data = (try? handle.read(upToCount: 16_384)) ?? Data()
        guard !data.isEmpty else {
            return MeetingMetadata()
        }
        let text = TranscriptTextDecoder.decode(data)
        return TranscriptParser.parse(text).metadata
    }

    private func loadTranscriptSearchPreview(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ""
        }
        defer {
            try? handle.close()
        }
        let data = (try? handle.read(upToCount: 32_768)) ?? Data()
        guard !data.isEmpty else {
            return ""
        }
        return TranscriptTextDecoder.decode(data)
    }

    private func currentLatestTranscriptCandidate() -> TranscriptFileCandidate? {
        guard let selectedFolderURL else {
            return nil
        }
        return LatestTranscriptSelector.latestTextFile(
            from: LatestTranscriptSelector.textFiles(in: selectedFolderURL)
        )
    }

    private func captureHistoryLiveBaseline() {
        historyLiveBaselineCandidate = currentLatestTranscriptCandidate()
        if let historyLiveBaselineCandidate {
            liveActiveTranscriptURL = historyLiveBaselineCandidate.url
        }
        liveMeetingUpdated = false
    }

    private func scanFolder() {
        guard selectedFolderURL != nil else {
            return
        }

        guard let latestCandidate = currentLatestTranscriptCandidate() else {
            refreshMeetingHistory()
            liveActiveTranscriptURL = nil
            if transcriptRunMode == .history {
                liveMeetingUpdated = false
            }
            if transcriptRunMode == .liveWatch {
                activeTranscriptURL = nil
                rawTranscript = ""
                rawTranscriptPreviewLines = []
                transcriptFocusRequest = nil
                highlightedTranscriptLineID = nil
                rawTranscriptLineCount = 0
                metadata = MeetingMetadata()
                analysisState = MeetingAnalysisState()
                analysisStatus = .idle
                rawReadOffset = 0
                transcriptUpdatedAt = nil
                statusMessage = "선택한 폴더에서 `.txt` transcript를 기다리는 중입니다."
            }
            return
        }

        let latestURL = latestCandidate.url
        liveActiveTranscriptURL = latestURL
        if transcriptRunMode == .history {
            liveMeetingUpdated = LiveTranscriptUpdateDetector.isUpdated(
                latest: latestCandidate,
                baseline: historyLiveBaselineCandidate
            )
        }

        guard transcriptRunMode == .liveWatch else {
            refreshMeetingHistory()
            return
        }

        if activeTranscriptURL != latestURL {
            switchActiveTranscript(to: latestURL)
        } else {
            readAppendedContent(from: latestURL)
        }
        refreshMeetingHistory()
    }

    private func switchActiveTranscript(to url: URL) {
        analysisTask?.cancel()
        analysisTask = nil
        activeAnalysisRequest = nil
        activeAnalysisAttemptID = nil
        latestSnapshotIsLocalFallback = false
        lastAutomaticAnalysisAt = Date()
        loadTranscriptForViewing(url, statusPrefix: "활성 transcript")
        liveMeetingUpdated = false
        historyLiveBaselineCandidate = nil
    }

    private func loadTranscriptForViewing(_ url: URL, statusPrefix: String) {
        activeTranscriptURL = url
        rawTranscript = ""
        rawTranscriptPreviewLines = []
        transcriptFocusRequest = nil
        highlightedTranscriptLineID = nil
        rawTranscriptLineCount = 0
        rawReadOffset = 0
        finalAnalysisTriggeredForMeetingID = nil
        analysisState = stateStore.loadAnalysisState(for: url)
        if analysisState.markInterruptedRunningAttemptsSkipped(
            message: "앱 재시작 또는 meeting reload로 이전 running attempt를 중단 처리했습니다."
        ) {
            try? stateStore.saveAnalysisState(analysisState, for: url)
        }
        analysisStatus = analysisState.isCompleted ? .completed : .idle

        if let session = stateStore.loadSession(for: url) {
            metadata = session.metadata
        } else {
            metadata = MeetingMetadata()
        }

        let id = meetingID(for: url)
        Task {
            await scheduler.setActiveMeetingID(id)
            await scheduler.seedSnapshot(analysisState.latestSnapshot, for: id)
        }

        readFullContent(from: url, allowFinalTrigger: false)
        statusMessage = "\(statusPrefix): \(url.lastPathComponent)"
    }

    private func readFullContent(from url: URL, allowFinalTrigger: Bool = true) {
        do {
            let data = try Data(contentsOf: url)
            rawTranscript = TranscriptTextDecoder.decode(data)
            updateTranscriptPreview()
            rawReadOffset = UInt64(data.count)
            transcriptUpdatedAt = Date()
            refreshParsedState(
                for: url,
                parseMetadata: true,
                endMarkerSource: rawTranscript,
                allowFinalTrigger: allowFinalTrigger
            )
        } catch {
            statusMessage = "transcript 읽기 실패: \(error.localizedDescription)"
        }
    }

    private func readAppendedContent(from url: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            if fileSize < rawReadOffset {
                readFullContent(from: url, allowFinalTrigger: true)
                return
            }

            guard fileSize > rawReadOffset else {
                return
            }

            let handle = try FileHandle(forReadingFrom: url)
            try handle.seek(toOffset: rawReadOffset)
            let data = try handle.readToEnd() ?? Data()
            try handle.close()

            guard !data.isEmpty else {
                return
            }

            let appendedText = TranscriptTextDecoder.decode(data)
            rawTranscript += appendedText
            appendTranscriptPreview(appendedText)
            rawReadOffset = fileSize
            transcriptUpdatedAt = Date()
            refreshParsedState(
                for: url,
                parseMetadata: metadata.dateTime == nil && metadata.participants.isEmpty,
                endMarkerSource: String(rawTranscript.suffix(1_024)),
                allowFinalTrigger: true
            )
        } catch {
            statusMessage = "transcript tail 실패: \(error.localizedDescription)"
        }
    }

    private func refreshParsedState(
        for url: URL,
        parseMetadata: Bool = true,
        endMarkerSource: String? = nil,
        allowFinalTrigger: Bool = true
    ) {
        if parseMetadata {
            metadata = TranscriptParser.parse(rawTranscript).metadata
        }
        let state = MeetingSessionState(
            sourceFilePath: url.path,
            metadata: metadata,
            rawReadOffset: rawReadOffset
        )
        try? stateStore.saveSession(state, for: url)

        let wasCompleted = analysisState.isCompleted
        if TranscriptParser.containsEndMarker(endMarkerSource ?? rawTranscript) {
            analysisState.isCompleted = true
            try? stateStore.saveAnalysisState(analysisState, for: url)
            refreshMeetingHistory(force: true)
            if allowFinalTrigger,
               settings.automaticAnalysisEnabled,
               !wasCompleted,
               finalAnalysisTriggeredForMeetingID != meetingID(for: url) {
                finalAnalysisTriggeredForMeetingID = meetingID(for: url)
                if transcriptRunMode != .history {
                    triggerAnalysis(reason: "final")
                } else if !isAnalysisRunning {
                    analysisStatus = .completed
                }
            } else if !isAnalysisRunning {
                analysisStatus = .completed
            }
        }
    }

    private func triggerAutomaticAnalysisIfNeeded() {
        guard settings.automaticAnalysisEnabled,
              let activeTranscriptURL,
              !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              transcriptRunMode != .history,
              !analysisState.isCompleted,
              !isAnalysisRunning else {
            return
        }
        let now = Date()
        let latestElapsedSeconds = latestTranscriptElapsedSeconds()
        let triggerNow = automaticTriggerReferenceDate(
            now: now,
            latestTranscriptElapsedSeconds: latestElapsedSeconds
        )
        let policy = automaticTriggerPolicyForCurrentMode()
        let decision = policy.evaluate(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: analysisState.analyzedTranscriptCharacterCount,
            latestTranscriptElapsedSeconds: latestElapsedSeconds,
            now: triggerNow,
            lastAutomaticAnalysisAt: lastAutomaticAnalysisAt
        )

        switch decision {
        case .run(let reason):
            lastAutomaticAnalysisAt = triggerNow
            triggerAnalysis(reason: "automatic-\(reason)")
        case .skip(let reason):
            lastAutomaticAnalysisAt = triggerNow
            appendSkippedAutomaticAttempt(reason: reason, sourceURL: activeTranscriptURL)
        case .wait(let reason):
            if reason == "batch-threshold-not-reached", lastAutomaticAnalysisAt == nil {
                lastAutomaticAnalysisAt = triggerNow
            }
            return
        }
    }

    private func automaticTriggerPolicyForCurrentMode() -> AnalysisTriggerPolicy {
        return AnalysisTriggerPolicy(
            configuration: settings.analysisTriggerPreset.configuration.withMinimumMeetingElapsedSeconds(
                minimumAutomaticAnalysisElapsedSeconds
            )
        )
    }

    private func automaticTriggerReferenceDate(now: Date, latestTranscriptElapsedSeconds: Int) -> Date {
        guard transcriptRunMode == .testRun else {
            return now
        }
        return Date(timeIntervalSince1970: TimeInterval(latestTranscriptElapsedSeconds))
    }

    private func cancelAutomaticAnalysisIfNeeded() {
        guard let activeAnalysisRequest,
              isAutomaticAnalysisReason(activeAnalysisRequest.reason) else {
            return
        }
        analysisTask?.cancel()
        analysisTask = nil
        self.activeAnalysisRequest = nil
        activeAnalysisAttemptID = nil
        activeAnalysisWindow = nil
        statusMessage = "Automatic Meeting Intelligence를 일시 중지했습니다."
        analysisStatus = analysisState.isCompleted ? .completed : .stale(statusMessage)
    }

    private func isAutomaticAnalysisReason(_ reason: String) -> Bool {
        reason.hasPrefix("automatic") || reason.hasPrefix("final")
    }

    private func triggerAnalysis(reason: String) {
        guard analysisTask == nil,
              let activeTranscriptURL,
              !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let meetingID = meetingID(for: activeTranscriptURL)
        let previousSnapshot = automaticPreviousSnapshotIfNeeded(reason: reason)
        let transcriptWindow = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: analysisState.analyzedTranscriptCharacterCount,
            reason: reason,
            maxAutomaticCatchUpCharacters: automaticCatchUpChunkCharacters
        )
        let request = AnalysisRequest(
            meetingID: meetingID,
            metadata: metadata,
            rawTranscript: transcriptWindow.rawTranscript,
            previousSnapshot: previousSnapshot,
            confirmedCandidateIDs: analysisState.confirmedCandidateIDs,
            deletedCandidateIDs: analysisState.deletedCandidateIDs,
            providerKind: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            reason: reason,
            lastAnalyzedTranscriptCharacterCount: transcriptWindow.lastAnalyzedTranscriptCharacterCount
        )

        let timeoutSeconds = effectiveAnalysisTimeoutSeconds(for: reason)
        let provider = makeProvider(timeoutSeconds: timeoutSeconds)
        activeAnalysisRequest = request
        activeAnalysisWindow = transcriptWindow
        let prompt = (try? AnalysisPromptBuilder.buildPrompt(for: request)) ?? rawTranscript
        let inputTokens = TokenEstimator.estimateTokens(in: prompt)
        let attemptMessage = ["timeout \(timeoutSeconds)초", transcriptWindow.messageSuffix]
            .compactMap { $0 }
            .joined(separator: " · ")
        let attempt = AnalysisAttemptLog(
            reason: reason,
            status: .running,
            provider: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            modelName: currentModelName(),
            inputTokens: inputTokens,
            message: attemptMessage,
            prompt: prompt,
            batchStats: makeAttemptBatchStats(for: transcriptWindow, reason: reason)
        )
        activeAnalysisAttemptID = attempt.id
        analysisState.appendAttempt(attempt)
        analysisState.updatedAt = Date()
        if analysisState.latestSnapshot == nil {
            let fallbackSnapshot = LocalAnalysisFallback.snapshot(
                for: request,
                message: "선택된 LLM provider가 분석 중입니다. 결과를 받으면 자동으로 갱신됩니다."
            )
            analysisState.latestSnapshot = analysisState.applyingCandidateState(to: fallbackSnapshot)
            analysisState.updatedAt = Date()
            latestSnapshotIsLocalFallback = true
            try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
        }
        analysisStatus = .running
        analysisTask = Task { [weak self] in
            guard let self else {
                return
            }
            let result = await scheduler.runIfIdle(request: request, provider: provider)
            await MainActor.run {
                self.applyAnalysisResult(result, for: activeTranscriptURL, reason: reason)
            }
        }
    }

    private func latestTranscriptElapsedSeconds() -> Int {
        rawTranscriptPreviewLines
            .reversed()
            .compactMap { TranscriptTimestampLocator.elapsedSeconds(in: $0) }
            .first ?? 0
    }

    private func automaticPreviousSnapshotIfNeeded(reason: String) -> AnalysisSnapshot? {
        guard AnalysisRequest.isAutomaticReason(reason) else {
            return analysisState.latestSnapshot
        }
        if let latestSnapshot = analysisState.latestSnapshot {
            return latestSnapshot
        }

        let fallbackSnapshot = AnalysisSnapshot(
            currentIssue: CurrentIssue(summary: "초기 1분 이후 live patch 분석을 기다리는 중입니다."),
            provider: settings.selectedProvider
        )
        analysisState.latestSnapshot = analysisState.applyingCandidateState(to: fallbackSnapshot)
        analysisState.updatedAt = Date()
        latestSnapshotIsLocalFallback = true
        if let activeTranscriptURL {
            try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
        }
        return analysisState.latestSnapshot
    }

    private func applyAnalysisResult(_ result: AnalysisRunResult, for sourceURL: URL, reason: String) {
        analysisTask = nil
        let completedWindow = activeAnalysisWindow
        let shouldContinueChunk = shouldContinueAnalysisChunks(for: reason, window: completedWindow)
        switch result {
        case .success(let snapshot, let usage, let rawOutput, let runTrace):
            let snapshot = analysisState.applyingCandidateState(to: snapshot)
            analysisState.latestSnapshot = snapshot
            analysisState.appendUsage(usage)
            analysisState.lastError = nil
            analysisState.updatedAt = Date()
            analysisState.analyzedTranscriptCharacterCount = completedWindow?.targetTranscriptCharacterCount
                ?? activeAnalysisRequest?.rawTranscript.count
                ?? analysisState.analyzedTranscriptCharacterCount
            latestSnapshotIsLocalFallback = false
            updateActiveAttempt(
                status: .succeeded,
                outputTokens: usage.outputTokens,
                message: shouldContinueChunk ? "chunk 완료. 다음 chunk를 이어서 분석합니다." : nil,
                providerOutput: rawOutput,
                runTrace: runTrace
            )
            if reason.hasPrefix("final"), !shouldContinueChunk {
                analysisState.isCompleted = true
            }
            analysisStatus = shouldContinueChunk ? .running : (analysisState.isCompleted ? .completed : .idle)
            if shouldContinueChunk, let completedWindow {
                scheduleChunkContinuation(for: sourceURL, reason: reason, completedWindow: completedWindow)
            }
        case .skippedAlreadyRunning:
            updateActiveAttempt(status: .skipped, outputTokens: 0, message: "같은 meeting의 analysis가 이미 실행 중입니다.")
            analysisStatus = .running
        case .staleIgnored(let previousSnapshot):
            analysisState.latestSnapshot = previousSnapshot
            analysisState.lastError = "active meeting 전환으로 오래된 결과를 무시했습니다."
            updateActiveAttempt(status: .skipped, outputTokens: 0, message: analysisState.lastError)
            analysisStatus = .stale(analysisState.lastError ?? "")
        case .failurePreserved(let previousSnapshot, let message, let runTrace):
            if let previousSnapshot {
                analysisState.latestSnapshot = previousSnapshot
            } else if let activeAnalysisRequest {
                analysisState.latestSnapshot = LocalAnalysisFallback.snapshot(for: activeAnalysisRequest, message: message)
                latestSnapshotIsLocalFallback = true
            }
            analysisState.lastError = message
            analysisState.updatedAt = Date()
            updateActiveAttempt(status: .failed, outputTokens: 0, message: message, runTrace: runTrace)
            analysisStatus = .failed(message)
            scheduleRetryIfNeeded(for: sourceURL, reason: reason, failedWindow: completedWindow)
        }
        activeAnalysisRequest = nil
        activeAnalysisWindow = nil
        activeAnalysisAttemptID = nil
        try? stateStore.saveAnalysisState(analysisState, for: sourceURL)
        refreshMeetingHistory(force: true)
    }

    private func updateActiveAttempt(
        status: AnalysisAttemptStatus,
        outputTokens: Int,
        message: String?,
        providerOutput: String? = nil,
        runTrace: AnalysisRunTrace? = nil
    ) {
        guard let activeAnalysisAttemptID,
              let index = analysisState.attemptLogs.lastIndex(where: { $0.id == activeAnalysisAttemptID }) else {
            return
        }
        analysisState.attemptLogs[index].status = status
        let completedAt = Date()
        analysisState.attemptLogs[index].completedAt = completedAt
        analysisState.attemptLogs[index].durationMilliseconds = max(
            0,
            Int((completedAt.timeIntervalSince(analysisState.attemptLogs[index].startedAt) * 1000).rounded())
        )
        analysisState.attemptLogs[index].outputTokens = outputTokens
        analysisState.attemptLogs[index].message = message
        analysisState.attemptLogs[index].providerOutput = providerOutput
        analysisState.attemptLogs[index].runTrace = runTrace
    }

    private func makeAttemptBatchStats(
        for window: AnalysisTranscriptWindow,
        reason: String,
        skippedReason: String? = nil
    ) -> AnalysisAttemptBatchStats {
        let lastAnalyzedCount = window.lastAnalyzedTranscriptCharacterCount
        let targetCount = window.targetTranscriptCharacterCount
        let sourceCount = window.sourceTranscriptCharacterCount
        let newText = transcriptSlice(rawTranscript, from: lastAnalyzedCount, to: sourceCount)
        let includedText = transcriptSlice(rawTranscript, from: lastAnalyzedCount, to: targetCount)
        return AnalysisAttemptBatchStats(
            triggerReason: triggerDescription(for: reason),
            newTranscriptCharacters: max(0, sourceCount - lastAnalyzedCount),
            includedTranscriptCharacters: max(0, targetCount - lastAnalyzedCount),
            newDialogueLines: TranscriptParser.parse(newText).dialogueLines.count,
            includedDialogueLines: TranscriptParser.parse(includedText).dialogueLines.count,
            lastAnalyzedTranscriptCharacterCount: lastAnalyzedCount,
            targetTranscriptCharacterCount: targetCount,
            sourceTranscriptCharacterCount: sourceCount,
            skippedReason: skippedReason
        )
    }

    private func transcriptSlice(_ text: String, from startOffset: Int, to endOffset: Int) -> String {
        let sourceCount = text.count
        let lower = min(max(0, startOffset), sourceCount)
        let upper = min(max(lower, endOffset), sourceCount)
        let startIndex = text.index(text.startIndex, offsetBy: lower)
        let endIndex = text.index(text.startIndex, offsetBy: upper)
        return String(text[startIndex..<endIndex])
    }

    private func triggerDescription(for reason: String) -> String {
        if reason == "automatic" {
            return "hybrid trigger"
        }
        if reason.hasPrefix("automatic-retry") {
            return "automatic retry"
        }
        if reason.hasPrefix("automatic-") {
            return reason.replacingOccurrences(of: "automatic-", with: "hybrid ")
        }
        return reason
    }

    private func scheduleRetryIfNeeded(
        for sourceURL: URL,
        reason: String,
        failedWindow: AnalysisTranscriptWindow?
    ) {
        if reason.hasPrefix("final") {
            guard settings.automaticAnalysisEnabled else {
                return
            }
            let retryKey = finalRetryKey(for: sourceURL, window: failedWindow)
            let count = finalAnalysisRetryCounts[retryKey, default: 0]
            guard count < finalAnalysisMaxRetries else {
                return
            }
            let retryCount = count + 1
            finalAnalysisRetryCounts[retryKey] = retryCount
            let retryReason = finalRetryReason(after: reason, retryCount: retryCount)
            appendRetryScheduledAttempt(
                reason: retryReason,
                sourceURL: sourceURL,
                message: "\(finalAnalysisRetryDelaySeconds)초 뒤 final analysis chunk를 재시도합니다."
            )
            Task { [weak self] in
                guard let delay = self?.finalAnalysisRetryDelaySeconds else {
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                await MainActor.run {
                    guard let self,
                          self.settings.automaticAnalysisEnabled,
                          self.activeTranscriptURL == sourceURL,
                          self.analysisTask == nil else {
                        return
                    }
                    self.triggerAnalysis(reason: retryReason)
                }
            }
            return
        }

        let minBatchWaitSeconds = automaticTriggerPolicyForCurrentMode().configuration.minBatchWaitSeconds
        lastAutomaticAnalysisAt = Date().addingTimeInterval(-TimeInterval(max(0, minBatchWaitSeconds - failedAnalysisRetryDelaySeconds)))
        appendRetryScheduledAttempt(
            reason: "automatic-retry",
            sourceURL: sourceURL,
            message: "다음 automatic tick에서 이전 snapshot과 현재 transcript를 포함해 재시도합니다."
        )
    }

    private func finalRetryKey(for sourceURL: URL, window: AnalysisTranscriptWindow?) -> String {
        let meetingID = meetingID(for: sourceURL)
        guard let window else {
            return "\(meetingID):unknown"
        }
        return "\(meetingID):\(window.lastAnalyzedTranscriptCharacterCount)-\(window.targetTranscriptCharacterCount)"
    }

    private func clearFinalRetryCounts(for sourceURL: URL) {
        let prefix = "\(meetingID(for: sourceURL)):"
        finalAnalysisRetryCounts = finalAnalysisRetryCounts.filter { key, _ in
            !key.hasPrefix(prefix)
        }
    }

    private func finalRetryReason(after reason: String, retryCount: Int) -> String {
        if reason.hasPrefix("final-continue") {
            return "final-continue-retry-\(retryCount)"
        }
        return "final-retry-\(retryCount)"
    }

    private func shouldContinueAnalysisChunks(for reason: String, window: AnalysisTranscriptWindow?) -> Bool {
        guard let window, window.isChunked else {
            return false
        }
        return reason.hasPrefix("manual") || reason.hasPrefix("final")
    }

    private func scheduleChunkContinuation(
        for sourceURL: URL,
        reason: String,
        completedWindow: AnalysisTranscriptWindow
    ) {
        let nextReason = nextChunkReason(after: reason)
        appendRetryScheduledAttempt(
            reason: nextReason,
            sourceURL: sourceURL,
            message: "chunk \(completedWindow.lastAnalyzedTranscriptCharacterCount)-\(completedWindow.targetTranscriptCharacterCount)/\(completedWindow.sourceTranscriptCharacterCount)자 완료. 다음 chunk를 이어서 분석합니다."
        )
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                guard let self,
                      self.activeTranscriptURL == sourceURL,
                      self.analysisTask == nil else {
                    return
                }
                self.triggerAnalysis(reason: nextReason)
            }
        }
    }

    private func nextChunkReason(after reason: String) -> String {
        if reason.hasPrefix("final") {
            return "final-continue"
        }
        return "manual-continue"
    }

    private func appendRetryScheduledAttempt(reason: String, sourceURL: URL, message: String) {
        let attempt = AnalysisAttemptLog(
            reason: reason,
            status: .retryScheduled,
            provider: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            modelName: currentModelName(),
            startedAt: Date(),
            completedAt: Date(),
            message: message
        )
        analysisState.appendAttempt(attempt)
        analysisState.updatedAt = Date()
        try? stateStore.saveAnalysisState(analysisState, for: sourceURL)
    }

    private func appendSkippedAutomaticAttempt(reason: String, sourceURL: URL) {
        let window = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: analysisState.analyzedTranscriptCharacterCount,
            reason: "automatic-\(reason)",
            maxAutomaticCatchUpCharacters: automaticCatchUpChunkCharacters
        )
        let now = Date()
        let attempt = AnalysisAttemptLog(
            reason: "automatic-\(reason)",
            status: .skipped,
            provider: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            modelName: currentModelName(),
            startedAt: now,
            completedAt: now,
            inputTokens: 0,
            outputTokens: 0,
            durationMilliseconds: 0,
            message: "hybrid trigger skip: \(reason)",
            batchStats: makeAttemptBatchStats(for: window, reason: "automatic-\(reason)", skippedReason: reason)
        )
        analysisState.appendAttempt(attempt)
        analysisState.updatedAt = now
        try? stateStore.saveAnalysisState(analysisState, for: sourceURL)
    }

    private func updateCandidate(id: String, status: CandidateStatus) {
        analysisState.setCandidateStatus(id: id, status: status)

        if let snapshot = analysisState.latestSnapshot {
            analysisState.latestSnapshot = analysisState.applyingCandidateState(to: snapshot)
        }
        persistCandidateStateChange()
    }

    private func persistCandidateStateChange() {
        analysisState.updatedAt = Date()
        if let activeTranscriptURL {
            try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
            patchMeetingHistoryItem(for: activeTranscriptURL)
        }
    }

    private func effectiveAnalysisTimeoutSeconds(for reason: String) -> Int {
        AnalysisTimeoutPolicy.timeoutSeconds(
            configuredTimeoutSeconds: settings.providerTimeoutSeconds,
            reason: reason
        )
    }

    private func makeProvider(timeoutSeconds: Int) -> LLMProvider {
        switch settings.selectedProvider {
        case .codexExec:
            return CodexExecProvider(
                schemaURL: analysisSchemaURL(),
                patchSchemaURL: analysisPatchSchemaURL(),
                timeoutSeconds: timeoutSeconds,
                workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                modelPreset: settings.modelPreset
            )
        case .claudeCode:
            return ClaudeCodeProvider(
                schemaURL: analysisSchemaURL(),
                patchSchemaURL: analysisPatchSchemaURL(),
                timeoutSeconds: timeoutSeconds,
                workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                modelPreset: settings.modelPreset
            )
        case .customCommand:
            return CustomCommandProvider(
                command: settings.customProviderCommand,
                timeoutSeconds: timeoutSeconds,
                workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                modelPreset: settings.modelPreset
            )
        }
    }

    private func currentModelName() -> String {
        switch settings.selectedProvider {
        case .codexExec:
            return LLMUsagePricing.codexPrice(for: settings.modelPreset)?.modelName
                ?? settings.modelPreset.codexModelName
                ?? "Codex CLI default"
        case .claudeCode:
            return LLMUsagePricing.claudeCodePrice(for: settings.modelPreset)?.modelName
                ?? settings.modelPreset.claudeCodeModelName
                ?? "Claude Code default"
        case .customCommand:
            return settings.modelPreset.codexModelName ?? "custom provider default"
        }
    }

    private func analysisSchemaURL() -> URL {
        resourceURL(named: "analysis-output.schema.json")
    }

    private func analysisPatchSchemaURL() -> URL {
        resourceURL(named: "analysis-patch-output.schema.json")
    }

    private func resourceURL(named fileName: String) -> URL {
        let relativePath = "MeetingRescue_MeetingRescue.bundle/Resources/\(fileName)"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(relativePath),
            Bundle.main.bundleURL.appendingPathComponent(relativePath),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(relativePath)
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? candidates[0]
    }

    private func meetingID(for url: URL) -> String {
        CandidateIDGenerator.stableID(prefix: "meeting", text: url.path, evidenceTimestamp: "")
    }

    private func updateTranscriptPreview() {
        let lines = rawTranscript.components(separatedBy: .newlines)
        rawTranscriptLineCount = lines.count
        rawTranscriptPreviewLines = lines
        rawTranscriptRevision += 1
    }

    private func appendTranscriptPreview(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        let appendedLines = text.components(separatedBy: .newlines)
        if rawTranscriptPreviewLines.isEmpty {
            rawTranscriptPreviewLines = appendedLines
        } else if let first = appendedLines.first {
            rawTranscriptPreviewLines[rawTranscriptPreviewLines.count - 1] += first
            if appendedLines.count > 1 {
                rawTranscriptPreviewLines.append(contentsOf: appendedLines.dropFirst())
            }
        }
        rawTranscriptLineCount = rawTranscriptPreviewLines.count
        rawTranscriptRevision += 1
    }

    private func rawTranscriptSearchSections(from rawPreview: String) -> [MeetingHistorySearchSection] {
        rawPreview
            .components(separatedBy: .newlines)
            .prefix(rawTranscriptSearchLineLimit)
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

    private func focusTranscriptLine(matching timestamp: String, metadata: MeetingMetadata) {
        guard let lineID = TranscriptTimestampLocator.lineIndex(
            in: rawTranscriptPreviewLines,
            matching: timestamp,
            meetingDateTime: metadata.dateTime
        ) else {
            return
        }
        transcriptFocusToken += 1
        transcriptFocusRequest = TranscriptFocusRequest(lineID: lineID, token: transcriptFocusToken)
        highlightedTranscriptLineID = lineID
        scheduleTranscriptHighlightClear(for: lineID)
    }

    private func scheduleTranscriptHighlightClear(for lineID: Int) {
        transcriptHighlightClearTask?.cancel()
        transcriptHighlightClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, self?.highlightedTranscriptLineID == lineID else {
                return
            }
            self?.highlightedTranscriptLineID = nil
        }
    }
}
