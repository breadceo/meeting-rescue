import Foundation
import MeetingRescueCore
import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

private let localGlossaryLogger = Logger(subsystem: "MeetingRescue", category: "LocalGlossary")

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

enum GitHubIssueDraftKind: String, CaseIterable, Identifiable {
    case bug
    case feature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bug:
            return "버그 신고"
        case .feature:
            return "기능 제안"
        }
    }

    var systemImage: String {
        switch self {
        case .bug:
            return "exclamationmark.triangle"
        case .feature:
            return "lightbulb"
        }
    }

    var githubLabel: String {
        switch self {
        case .bug:
            return "bug"
        case .feature:
            return "enhancement"
        }
    }

    var titlePrefix: String {
        switch self {
        case .bug:
            return "[Bug]"
        case .feature:
            return "[Feature]"
        }
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

private extension TranscriptRunMode {
    var momentMarkerRunMode: MomentMarkerRunMode {
        switch self {
        case .liveWatch:
            return .liveWatch
        case .history:
            return .history
        case .testRun:
            return .testRun
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

private struct MeetingHistoryBuildSignatures: Sendable {
    let fileSignature: String
    let searchIndexFileSignature: String
    let signature: String
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

struct LocalGlossaryRefreshProgress: Equatable {
    enum Stage: Equatable {
        case idle
        case scanning
        case reading
        case generating
        case saving
        case completed
        case failed(String)
    }

    var stage: Stage
    var completed: Int
    var total: Int
    var detail: String

    static let idle = LocalGlossaryRefreshProgress(stage: .idle, completed: 0, total: 0, detail: "")

    var isVisible: Bool {
        switch stage {
        case .scanning, .reading, .generating, .saving, .failed:
            return true
        case .idle, .completed:
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
        switch stage {
        case .idle:
            return "용어 후보 대기"
        case .scanning:
            return "transcript 파일 목록 확인 중"
        case .reading:
            if total > 0 {
                return "회의 읽는 중 \(completed)/\(total)"
            }
            return "읽을 회의 확인 중"
        case .generating:
            return "용어 후보 계산 중"
        case .saving:
            return "용어 후보 저장 중"
        case .completed:
            return "용어 후보 찾기 완료"
        case .failed(let message):
            return "용어 후보 찾기 실패: \(message)"
        }
    }

    static func scanner(_ progress: LocalGlossaryHistoryScannerProgress) -> LocalGlossaryRefreshProgress {
        switch progress.phase {
        case .listing:
            return LocalGlossaryRefreshProgress(
                stage: .scanning,
                completed: 0,
                total: 0,
                detail: "파일 목록 확인 중"
            )
        case .reading:
            return LocalGlossaryRefreshProgress(
                stage: .reading,
                completed: progress.completed,
                total: progress.total,
                detail: progress.currentFile ?? ""
            )
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

private final class LocalGlossaryProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var progress = LocalGlossaryHistoryScannerProgress(phase: .listing, completed: 0, total: 0)

    func update(_ progress: LocalGlossaryHistoryScannerProgress) {
        lock.lock()
        self.progress = progress
        lock.unlock()
    }

    func snapshot() -> LocalGlossaryHistoryScannerProgress {
        lock.lock()
        defer { lock.unlock() }
        return progress
    }
}

private struct GoogleCalendarFetchWindow {
    var request: GoogleCalendarEventsListRequest
    var meetingStart: Date
    var meetingEnd: Date
}

private func localGlossaryHistorySignature(
    state: LocalGlossaryState,
    isEnabled: Bool
) -> String {
    guard isEnabled else {
        return "glossary:off"
    }
    let termSignature = state.enabledTerms
        .map { term in
            [
                term.id,
                term.canonical,
                term.category.rawValue,
                term.aliases.joined(separator: ","),
                "\(term.updatedAt.timeIntervalSince1970)"
            ].joined(separator: ":")
        }
        .joined(separator: ";")
    return "glossary:\(termSignature)"
}

private struct MeetingHistoryBuilder: Sendable {
    let stateStore: ApplicationStateStore
    let rawTranscriptSearchLineLimit: Int
    let includeRawTranscriptSearch: Bool
    let includeLocalGlossarySearchSections: Bool
    let searchIndexExclusionURL: URL?
    let localGlossaryState: LocalGlossaryState
    let localGlossaryEnabled: Bool
    private let eagerMetadataPreviewLimit = 120

    func build(folderURL: URL) -> MeetingHistoryBuildResult {
        buildIfChanged(folderURL: folderURL, previousSignature: nil)!
    }

    func buildIfChanged(
        folderURL: URL,
        previousSignature: String?
    ) -> MeetingHistoryBuildResult? {
        let candidates = LatestTranscriptSelector.textFiles(in: folderURL)
        let signatures = makeSignatures(candidates: candidates)
        if let previousSignature, previousSignature == signatures.signature {
            return nil
        }
        return build(candidates: candidates, signatures: signatures)
    }

    private func makeSignatures(candidates: [TranscriptFileCandidate]) -> MeetingHistoryBuildSignatures {
        let glossarySignature = includeLocalGlossarySearchSections
            ? localGlossaryHistorySignature(state: localGlossaryState, isEnabled: localGlossaryEnabled)
            : "glossary:query-time"
        let fileSignature = candidates
            .sorted { $0.url.path < $1.url.path }
            .map { "\($0.url.path):\($0.modificationDate.timeIntervalSince1970)" }
            .joined(separator: "|")
        let excludedPath = searchIndexExclusionURL?.path
        let rawSearchIndexFileSignature = candidates
            .filter { $0.url.path != excludedPath }
            .sorted { $0.url.path < $1.url.path }
            .map { "\($0.url.path):\($0.modificationDate.timeIntervalSince1970)" }
            .joined(separator: "|")
        let searchIndexFileSignature = "\(glossarySignature)|\(rawSearchIndexFileSignature)"
        let signature = "\(includeRawTranscriptSearch ? "raw" : "structured")|\(glossarySignature)|\(fileSignature)"
        return MeetingHistoryBuildSignatures(
            fileSignature: fileSignature,
            searchIndexFileSignature: searchIndexFileSignature,
            signature: signature
        )
    }

    private func build(
        candidates: [TranscriptFileCandidate],
        signatures: MeetingHistoryBuildSignatures
    ) -> MeetingHistoryBuildResult {
        let preparedGlossaryState = LocalGlossaryMatcher.PreparedState(state: localGlossaryState)
        let items = candidates
            .sorted { lhs, rhs in
                if lhs.modificationDate == rhs.modificationDate {
                    return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedDescending
                }
                return lhs.modificationDate > rhs.modificationDate
            }
            .enumerated()
            .map { offset, candidate in
                makeHistoryItem(
                    from: candidate,
                    sortedIndex: offset,
                    preparedGlossaryState: preparedGlossaryState
                )
            }
        return MeetingHistoryBuildResult(
            fileSignature: signatures.fileSignature,
            searchIndexFileSignature: signatures.searchIndexFileSignature,
            signature: signatures.signature,
            items: items,
            includesRawTranscriptSearch: includeRawTranscriptSearch
        )
    }

    private func makeHistoryItem(
        from candidate: TranscriptFileCandidate,
        sortedIndex: Int,
        preparedGlossaryState: LocalGlossaryMatcher.PreparedState
    ) -> MeetingHistoryItem {
        let analysis = stateStore.hasAnalysisState(for: candidate.url)
            ? stateStore.loadAnalysisState(for: candidate.url)
            : MeetingAnalysisState()
        let metadata = if stateStore.hasSession(for: candidate.url),
                          let session = stateStore.loadSession(for: candidate.url) {
            session.metadata
        } else if shouldLoadMetadataPreview(sortedIndex: sortedIndex, analysis: analysis) {
            loadMetadataPreview(from: candidate.url)
        } else {
            MeetingMetadata()
        }
        let values = try? candidate.url.resourceValues(forKeys: [.fileSizeKey])
        let snapshot = analysis.latestSnapshot
        let searchSections = makeHistorySearchSections(
            url: candidate.url,
            metadata: metadata,
            snapshot: snapshot,
            preparedGlossaryState: preparedGlossaryState
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

    private func shouldLoadMetadataPreview(sortedIndex: Int, analysis: MeetingAnalysisState) -> Bool {
        includeRawTranscriptSearch
            || sortedIndex < eagerMetadataPreviewLimit
            || analysis.latestSnapshot != nil
            || analysis.isCompleted
    }

    private func makeHistorySearchSections(
        url: URL,
        metadata: MeetingMetadata,
        snapshot: AnalysisSnapshot?,
        preparedGlossaryState: LocalGlossaryMatcher.PreparedState
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

        sections.append(contentsOf: localGlossarySearchSections(
            from: sections,
            state: localGlossaryState,
            isEnabled: localGlossaryEnabled && includeLocalGlossarySearchSections,
            preparedState: preparedGlossaryState
        ))

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

private func localGlossarySearchSections(
    from sections: [MeetingHistorySearchSection],
    state: LocalGlossaryState,
    isEnabled: Bool,
    preparedState: LocalGlossaryMatcher.PreparedState
) -> [MeetingHistorySearchSection] {
    guard isEnabled, !preparedState.isEmpty else {
        return []
    }
    let matches = LocalGlossaryMatcher.matches(
        in: sections,
        preparedState: preparedState,
        includeEvidence: false
    )
    guard !matches.isEmpty else {
        return []
    }
    let termsByID = Dictionary(uniqueKeysWithValues: state.enabledTerms.map { ($0.id, $0) })
    return matches.map { match in
        let values = termsByID[match.termID]?.allMatchValues ?? ([match.canonical] + match.matchedAliases)
        return MeetingHistorySearchSection(
            field: .glossary,
            text: values.joined(separator: " "),
            weight: 66
        )
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
    @Published var rawTranscript = "" {
        didSet {
            if rawTranscript.isEmpty {
                resetActiveLocalGlossaryMatchCount()
            }
        }
    }
    @Published var rawTranscriptPreviewLines: [String] = []
    @Published private(set) var transcriptSpeakers: [String] = []
    @Published var rawTranscriptRevision = 0
    @Published var transcriptFocusRequest: TranscriptFocusRequest?
    @Published var highlightedTranscriptLineID: Int?
    @Published var rawTranscriptLineCount = 0
    @Published var metadata = MeetingMetadata()
    @Published var statusMessage = "transcript 폴더를 선택해 주세요."
    @Published var settings: AppSettings
    @Published var localGlossaryState = LocalGlossaryState()
    @Published var localGlossaryStatusMessage = "로컬 용어 사전 준비"
    @Published private(set) var localGlossaryRefreshProgress = LocalGlossaryRefreshProgress.idle
    @Published var isGeneratingLocalGlossarySuggestions = false
    @Published var analysisState = MeetingAnalysisState()
    @Published var analysisStatus: AnalysisRuntimeStatus = .idle
    @Published var calendarContextStatusMessage = "Google Calendar context 확인 전"
    @Published var isFetchingCalendarContext = false
    @Published var googleCalendarStatusMessage = "Google Calendar API 확인 전"
    @Published var isGoogleCalendarConnecting = false
    @Published var isFetchingGoogleCalendarAPIContext = false
    @Published var pendingMarkdownReadinessWarnings: [ShareReadinessWarning] = []
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
    private var liveTranscriptIndex = LiveTranscriptIndex()
    private var timer: Timer?
    private var replayTimer: Timer?
    private var replayCursor: TranscriptReplayCursor?
    private var replaySourceURL: URL?
    private var analysisTask: Task<Void, Never>?
    private var activeAnalysisRequest: AnalysisRequest?
    private var activeAnalysisWindow: AnalysisTranscriptWindow?
    private var activeAnalysisAttemptID: String?
    private var analysisRunGeneration = 0
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
    private var googleCalendarService: GoogleCalendarService?
    private var autoFetchedGoogleCalendarMeetingIDs: Set<String> = []
    private let historySearchDebounceDelayNanoseconds: UInt64 = 300_000_000
    private var transcriptHighlightClearTask: Task<Void, Never>?
    private var transcriptFocusToken = 0
    private var historyLiveBaselineCandidate: TranscriptFileCandidate?
    private let latestTranscriptFullScanInterval: TimeInterval = 5
    private var cachedLatestTranscriptCandidate: TranscriptFileCandidate?
    private var lastLatestTranscriptScanAt: Date?
    private var activeLocalGlossaryMatchSignature = ""
    private var activeLocalGlossaryMatchTask: Task<Void, Never>?
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
        self.localGlossaryState = stateStore.loadLocalGlossaryState()
        self.detectedSomaRecordingsFolder = SomaRecordingsFolderDetector().detect()
        self.providerAvailability = LLMProviderAvailabilityDetector().detect()
        applyInitialProviderAvailability()
        self.isShowingOnboarding = !settings.hasCompletedOnboarding
        restoreLastFolder()
        refreshGoogleCalendarConnectionStatus()
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

    var nextAutomaticAnalysisSummary: String {
        guard settings.automaticAnalysisEnabled else {
            return "auto off"
        }
        guard activeTranscriptURL != nil,
              transcriptRunMode != .history,
              !analysisState.isCompleted else {
            return "-"
        }
        if isAnalysisRunning {
            return "running"
        }
        let policy = automaticTriggerPolicyForCurrentMode()
        let config = policy.configuration
        let lastAnalyzedCount = analysisState.analyzedTranscriptCharacterCount
        let newCharacterCount = max(0, rawTranscript.count - lastAnalyzedCount)
        let newText = transcriptSlice(rawTranscript, from: lastAnalyzedCount, to: rawTranscript.count)
        let newLines = TranscriptParser.parse(newText).dialogueLines.count
        let latestElapsedSeconds = latestTranscriptElapsedSeconds()
        if latestElapsedSeconds < config.minimumMeetingElapsedSeconds {
            return "초기 \(config.minimumMeetingElapsedSeconds - latestElapsedSeconds)초 skip"
        }
        let now = automaticTriggerReferenceDate(now: Date(), latestTranscriptElapsedSeconds: latestElapsedSeconds)
        let elapsedSinceLast = lastAutomaticAnalysisAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        let minWaitRemaining = max(0, config.minBatchWaitSeconds - elapsedSinceLast)
        let maxWaitRemaining = max(0, config.maxBatchWaitSeconds - elapsedSinceLast)
        let progress = "\(newLines)/\(config.minNewDialogueLines)줄 · \(newCharacterCount)/\(config.minNewTranscriptCharacters)자"
        let decision = policy.evaluate(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: lastAnalyzedCount,
            latestTranscriptElapsedSeconds: latestElapsedSeconds,
            now: now,
            lastAutomaticAnalysisAt: lastAutomaticAnalysisAt
        )

        switch decision {
        case .run:
            return "곧 분석 · \(progress)"
        case .skip(let reason):
            return "\(automaticWaitLabel(for: reason)) · \(progress)"
        case .wait(let reason):
            switch reason {
            case "min-batch-wait":
                return "최소 대기 \(formatDuration(minWaitRemaining)) 남음 · \(progress)"
            case "batch-threshold-not-reached":
                return "새 \(progress) · 최대 \(formatDuration(maxWaitRemaining))"
            case "no-new-transcript":
                return "새 0/\(config.minNewDialogueLines)줄 · 0/\(config.minNewTranscriptCharacters)자"
            default:
                return "\(automaticWaitLabel(for: reason)) · \(progress)"
            }
        }
    }

    var filteredMeetingHistoryItems: [MeetingHistoryItem] {
        filteredMeetingHistorySearchResults.map(\.item)
    }

    var personalWorkflowSnapshot: PersonalWorkflowSnapshot {
        guard activeTranscriptURL != nil || analysisState.latestSnapshot != nil else {
            return PersonalWorkflowSnapshot()
        }
        return PersonalWorkflowAnalyzer.snapshot(
            currentMeetingID: currentWorkflowMeetingID,
            metadata: metadata,
            state: analysisState,
            currentOccurredAt: currentWorkflowOccurredAt,
            historySources: workflowHistorySources(excluding: activeTranscriptURL)
        )
    }

    var currentShareReadinessWarnings: [ShareReadinessWarning] {
        personalWorkflowSnapshot.readinessWarnings
    }

    var canRefreshCarryOverQuestions: Bool {
        selectedFolderURL != nil && (activeTranscriptURL != nil || analysisState.latestSnapshot != nil)
    }

    @Published private(set) var activeLocalGlossaryMatchCount = 0

    var localGlossarySuggestionCount: Int {
        localGlossaryState.suggestions.count
    }

    private func refreshActiveLocalGlossaryMatchCountIfNeeded() {
        let signature = activeLocalGlossaryMatchSignatureForCurrentState()
        guard signature != activeLocalGlossaryMatchSignature else {
            return
        }
        activeLocalGlossaryMatchTask?.cancel()
        activeLocalGlossaryMatchTask = nil
        activeLocalGlossaryMatchSignature = signature
        guard settings.localGlossaryEnabled, !rawTranscript.isEmpty else {
            activeLocalGlossaryMatchCount = 0
            return
        }
        activeLocalGlossaryMatchCount = LocalGlossaryMatcher.matches(
            in: rawTranscript,
            state: localGlossaryState
        ).count
    }

    private func scheduleActiveLocalGlossaryMatchCountRefresh() {
        let signature = activeLocalGlossaryMatchSignatureForCurrentState()
        guard signature != activeLocalGlossaryMatchSignature else {
            return
        }
        activeLocalGlossaryMatchTask?.cancel()
        activeLocalGlossaryMatchSignature = signature
        guard settings.localGlossaryEnabled, !rawTranscript.isEmpty else {
            activeLocalGlossaryMatchTask = nil
            activeLocalGlossaryMatchCount = 0
            return
        }
        let transcript = rawTranscript
        let state = localGlossaryState
        activeLocalGlossaryMatchTask = Task { @MainActor [weak self, signature, transcript, state] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else {
                return
            }
            let count = await Task.detached(priority: .utility) {
                LocalGlossaryMatcher.matches(in: transcript, state: state).count
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.activeLocalGlossaryMatchSignature == signature else {
                return
            }
            self.activeLocalGlossaryMatchCount = count
            self.activeLocalGlossaryMatchTask = nil
        }
    }

    private func resetActiveLocalGlossaryMatchCount() {
        activeLocalGlossaryMatchTask?.cancel()
        activeLocalGlossaryMatchTask = nil
        activeLocalGlossaryMatchSignature = ""
        activeLocalGlossaryMatchCount = 0
    }

    private func activeLocalGlossaryMatchSignatureForCurrentState() -> String {
        let termSignature = localGlossaryState.enabledTerms
            .map { term in
                [
                    term.id,
                    term.canonical,
                    term.category.rawValue,
                    term.aliases.joined(separator: ","),
                    "\(term.updatedAt.timeIntervalSince1970)"
                ].joined(separator: ":")
            }
            .joined(separator: ";")
        return [
            settings.localGlossaryEnabled ? "on" : "off",
            "\(rawTranscriptRevision)",
            "\(rawTranscript.count)",
            termSignature
        ].joined(separator: "|")
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
        let searchQueries = localGlossarySearchQueries(for: trimmed)
        searchDatabaseQueryGeneration += 1
        let generation = searchDatabaseQueryGeneration

        searchDatabaseQueryTask?.cancel()
        searchDatabaseQueryTask = Task(priority: .utility) { [weak self, searchDatabase, trimmed, searchQueries, items, facetSelection, sortOrder, databaseIsReady, generation] in
            let results: ([String: MeetingHistorySearchMatch], [MeetingHistorySearchResult]) = await Task.detached(priority: .utility) {
                let databaseResults: [MeetingSearchDatabaseResult] = if databaseIsReady, let searchDatabase {
                    searchQueries.flatMap { query in
                        (try? searchDatabase.search(query: query, includeSemantic: false)) ?? []
                    }
                } else {
                    []
                }
                guard !Task.isCancelled else {
                    return ([:], [])
                }
                var databaseMatchesByPath: [String: MeetingHistorySearchMatch] = [:]
                for result in databaseResults {
                    if let existing = databaseMatchesByPath[result.path],
                       existing.score >= result.match.score {
                        continue
                    }
                    databaseMatchesByPath[result.path] = result.match
                }
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

    private func localGlossarySearchQueries(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.localGlossaryEnabled, !trimmed.isEmpty else {
            return trimmed.isEmpty ? [] : [trimmed]
        }
        let normalizedQuery = MeetingHistorySearch.normalize(trimmed)
        let compactQuery = MeetingHistorySearch.compactNormalize(normalizedQuery)
        guard !normalizedQuery.isEmpty else {
            return [trimmed]
        }

        var values = [trimmed]
        for term in localGlossaryState.enabledTerms {
            let matchValues = term.allMatchValues
            let queryMatchesTerm = matchValues.contains { value in
                let normalizedValue = MeetingHistorySearch.normalize(value)
                guard normalizedValue.count >= 2 else {
                    return false
                }
                let compactValue = MeetingHistorySearch.compactNormalize(normalizedValue)
                return normalizedQuery == normalizedValue
                    || compactQuery == compactValue
                    || normalizedQuery.contains(normalizedValue)
                    || (compactValue.count >= 3 && compactQuery.contains(compactValue))
            }
            if queryMatchesTerm {
                values.append(contentsOf: matchValues)
            }
        }

        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { value in
                let key = MeetingHistorySearch.compactNormalize(value)
                return seen.insert(key).inserted
            }
            .prefix(12)
            .map { $0 }
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
        cancelActiveAnalysis(message: "폴더 전환으로 실행 중이던 analysis를 중단했습니다.")
        stopReplayTimer()
        transcriptRunMode = .liveWatch
        liveTranscriptIndex.reset()
        testRunPlaybackStatus = .idle
        testRunProgressText = ""
        liveMeetingUpdated = false
        historyLiveBaselineCandidate = nil
        cachedLatestTranscriptCandidate = nil
        lastLatestTranscriptScanAt = nil
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
        cancelActiveAnalysis(message: "History 화면 전환으로 실행 중이던 analysis를 중단했습니다.")
        latestSnapshotIsLocalFallback = false
        replayCursor = nil
        replaySourceURL = nil
        transcriptRunMode = .history
        liveTranscriptIndex.reset()
        testRunPlaybackStatus = .idle
        testRunProgressText = ""
        captureHistoryLiveBaseline()
        loadTranscriptForViewing(url, statusPrefix: "History")
        ensureFolderScanTimer()
    }

    func returnToLiveWatch() {
        stopReplayTimer()
        cancelActiveAnalysis(message: "Live Watch 전환으로 실행 중이던 analysis를 중단했습니다.")
        latestSnapshotIsLocalFallback = false
        replayCursor = nil
        replaySourceURL = nil
        transcriptRunMode = .liveWatch
        liveTranscriptIndex.reset()
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
            transcriptSpeakers = []
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
            codexExecutionMode: settings.codexExecutionMode,
            codexAppServerDiagnosticsEnabled: settings.codexAppServerDiagnosticsEnabled,
            modelPreset: settings.modelPreset,
            meetingTypePreset: settings.meetingTypePreset,
            automaticAnalysisEnabled: settings.automaticAnalysisEnabled,
            hasCompletedOnboarding: settings.hasCompletedOnboarding,
            analysisTriggerPreset: settings.analysisTriggerPreset,
            analysisCadenceSeconds: settings.analysisCadenceSeconds,
            providerTimeoutSeconds: settings.providerTimeoutSeconds,
            liveContextRetrievalMode: settings.liveContextRetrievalMode,
            localGlossaryEnabled: settings.localGlossaryEnabled,
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

    func setLocalGlossaryEnabled(_ isEnabled: Bool) {
        settings.localGlossaryEnabled = isEnabled
        saveSettings()
        refreshActiveLocalGlossaryMatchCountIfNeeded()
        refreshMeetingHistory(force: true)
    }

    func refreshLocalGlossarySuggestions() {
        guard !isGeneratingLocalGlossarySuggestions else {
            return
        }
        guard let selectedFolderURL else {
            localGlossaryStatusMessage = "transcript 폴더를 먼저 선택하세요."
            return
        }
        let refreshStartedAt = Date()
        isGeneratingLocalGlossarySuggestions = true
        localGlossaryRefreshProgress = LocalGlossaryRefreshProgress(
            stage: .scanning,
            completed: 0,
            total: 0,
            detail: "파일 목록 확인 중"
        )
        localGlossaryStatusMessage = localGlossaryRefreshProgress.displayText
        let currentState = localGlossaryState
        let progressBox = LocalGlossaryProgressBox()
        logLocalGlossaryRefreshStage("start", startedAt: refreshStartedAt, detail: "folder=\(selectedFolderURL.path)")

        Task { @MainActor [weak self, selectedFolderURL, currentState, progressBox, refreshStartedAt] in
            guard let self else {
                return
            }
            let scanStartedAt = Date()
            let progressTask = Task { @MainActor [weak self, progressBox, selectedFolderURL] in
                while !Task.isCancelled {
                    guard let self, self.selectedFolderURL == selectedFolderURL else {
                        return
                    }
                    let progress = LocalGlossaryRefreshProgress.scanner(progressBox.snapshot())
                    self.localGlossaryRefreshProgress = progress
                    self.localGlossaryStatusMessage = progress.displayText
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
            let documents = await Task.detached(priority: .utility) {
                LocalGlossaryHistoryScanner.documents(
                    in: selectedFolderURL,
                    configuration: .init(maxDocuments: Int.max, maxBytesPerDocument: 48_000, rawTranscriptLineLimit: 160),
                    progress: { progress in
                        progressBox.update(progress)
                    }
                )
            }.value
            progressTask.cancel()
            let scanMilliseconds = self.logLocalGlossaryRefreshStage(
                "scan",
                startedAt: scanStartedAt,
                detail: "documents=\(documents.count)"
            )
            guard self.selectedFolderURL == selectedFolderURL else {
                self.localGlossaryRefreshProgress = .idle
                self.isGeneratingLocalGlossarySuggestions = false
                return
            }
            self.localGlossaryRefreshProgress = LocalGlossaryRefreshProgress(
                stage: .generating,
                completed: documents.count,
                total: documents.count,
                detail: "후보 계산 중"
            )
            self.localGlossaryStatusMessage = self.localGlossaryRefreshProgress.displayText
            let suggestionStartedAt = Date()
            let suggestionResult = await Task.detached(priority: .utility) {
                LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
                    from: documents,
                    existingState: currentState,
                    maxSuggestions: 12,
                    maxReviewCandidates: 50
                )
            }.value
            let suggestions = suggestionResult.suggestions
            let reviewCandidates = suggestionResult.reviewCandidates
            let suggestionMilliseconds = self.logLocalGlossaryRefreshStage(
                "suggest",
                startedAt: suggestionStartedAt,
                detail: "documents=\(documents.count) suggestions=\(suggestions.count) reviewCandidates=\(reviewCandidates.count) latin_ms=\(suggestionResult.diagnostics.latinMilliseconds) korean_ms=\(suggestionResult.diagnostics.koreanMilliseconds) korean_candidates=\(suggestionResult.diagnostics.korean.candidateCount) korean_pairs=\(suggestionResult.diagnostics.korean.pairCount)"
            )
            guard self.selectedFolderURL == selectedFolderURL else {
                self.localGlossaryRefreshProgress = .idle
                self.isGeneratingLocalGlossarySuggestions = false
                return
            }
            let generatedCandidateCount = suggestions.count + reviewCandidates.count
            self.localGlossaryRefreshProgress = LocalGlossaryRefreshProgress(
                stage: .saving,
                completed: generatedCandidateCount,
                total: max(generatedCandidateCount, 1),
                detail: "저장 중"
            )
            self.localGlossaryStatusMessage = self.localGlossaryRefreshProgress.displayText
            let saveStartedAt = Date()
            self.localGlossaryState.replaceSuggestions(strict: suggestions, review: reviewCandidates)
            try? self.stateStore.saveLocalGlossaryState(self.localGlossaryState)
            let saveMilliseconds = self.logLocalGlossaryRefreshStage(
                "save",
                startedAt: saveStartedAt,
                detail: "suggestions=\(suggestions.count) reviewCandidates=\(reviewCandidates.count)"
            )
            let totalMilliseconds = self.logLocalGlossaryRefreshStage(
                "complete",
                startedAt: refreshStartedAt,
                detail: "documents=\(documents.count) suggestions=\(suggestions.count) reviewCandidates=\(reviewCandidates.count) scan_ms=\(scanMilliseconds) suggest_ms=\(suggestionMilliseconds) save_ms=\(saveMilliseconds)"
            )
            let diagnostic = LocalGlossaryRefreshDiagnostic(
                createdAt: Date(),
                folderPath: selectedFolderURL.path,
                documentCount: documents.count,
                suggestionCount: suggestions.count,
                scanMilliseconds: scanMilliseconds,
                suggestionMilliseconds: suggestionMilliseconds,
                saveMilliseconds: saveMilliseconds,
                totalMilliseconds: totalMilliseconds,
                stages: [
                    .init(name: "scan", elapsedMilliseconds: scanMilliseconds, detail: "documents=\(documents.count)"),
                    .init(name: "suggest", elapsedMilliseconds: suggestionMilliseconds, detail: "suggestions=\(suggestions.count) reviewCandidates=\(reviewCandidates.count)"),
                    .init(name: "suggest-latin", elapsedMilliseconds: suggestionResult.diagnostics.latinMilliseconds, detail: "suggestions=\(suggestionResult.diagnostics.latinSuggestionCount)"),
                    .init(name: "suggest-korean", elapsedMilliseconds: suggestionResult.diagnostics.koreanMilliseconds, detail: "suggestions=\(suggestionResult.diagnostics.koreanSuggestionCount) candidates=\(suggestionResult.diagnostics.korean.candidateCount) pairs=\(suggestionResult.diagnostics.korean.pairCount)"),
                    .init(name: "suggest-korean-collect", elapsedMilliseconds: suggestionResult.diagnostics.korean.collectMilliseconds, detail: "occurrences=\(suggestionResult.diagnostics.korean.occurrenceCount)"),
                    .init(name: "suggest-korean-summarize", elapsedMilliseconds: suggestionResult.diagnostics.korean.summarizeMilliseconds, detail: "candidates=\(suggestionResult.diagnostics.korean.candidateCount)"),
                    .init(name: "suggest-korean-pair", elapsedMilliseconds: suggestionResult.diagnostics.korean.pairMilliseconds, detail: "supported=\(suggestionResult.diagnostics.korean.supportedCandidateCount) comparison=\(suggestionResult.diagnostics.korean.comparisonCandidateCount) pairs=\(suggestionResult.diagnostics.korean.pairCount)"),
                    .init(name: "suggest-korean-cluster", elapsedMilliseconds: suggestionResult.diagnostics.korean.clusterMilliseconds, detail: "clusters=\(suggestionResult.diagnostics.korean.clusterCount)"),
                    .init(name: "save", elapsedMilliseconds: saveMilliseconds, detail: "suggestions=\(suggestions.count) reviewCandidates=\(reviewCandidates.count)"),
                    .init(name: "complete", elapsedMilliseconds: totalMilliseconds, detail: "documents=\(documents.count) suggestions=\(suggestions.count) reviewCandidates=\(reviewCandidates.count)")
                ],
                suggestions: suggestions.map { suggestion in
                    LocalGlossaryRefreshDiagnostic.SuggestionSummary(
                        id: suggestion.id,
                        suggestedCanonical: suggestion.suggestedCanonical,
                        aliases: suggestion.aliases,
                        occurrenceCount: suggestion.occurrenceCount,
                        meetingCount: suggestion.meetingCount,
                        confidence: suggestion.confidence,
                        score: suggestion.score
                    )
                },
                engineDiagnostics: suggestionResult.diagnostics
            )
            do {
                try self.stateStore.appendLocalGlossaryRefreshDiagnostic(diagnostic)
                if let logURL = try? self.stateStore.localGlossaryRefreshDiagnosticsURL() {
                    self.logLocalGlossaryRefreshStage("diagnostic-log", startedAt: refreshStartedAt, detail: logURL.path)
                }
            } catch {
                self.logLocalGlossaryRefreshStage("diagnostic-log-failed", startedAt: refreshStartedAt, detail: error.localizedDescription)
            }
            self.localGlossaryStatusMessage = suggestions.isEmpty && reviewCandidates.isEmpty
                ? "회의 \(documents.count)개에서 새 용어 후보 없음 · \(totalMilliseconds)ms"
                : "회의 \(documents.count)개에서 용어 후보 \(suggestions.count)개 · 검토 \(reviewCandidates.count)개 · \(totalMilliseconds)ms"
            self.localGlossaryRefreshProgress = LocalGlossaryRefreshProgress(
                stage: .completed,
                completed: documents.count,
                total: documents.count,
                detail: "\(totalMilliseconds)ms"
            )
            self.isGeneratingLocalGlossarySuggestions = false
        }
    }

    @discardableResult
    private func logLocalGlossaryRefreshStage(_ stage: String, startedAt: Date, detail: String = "") -> Int {
        let elapsedMilliseconds = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        if detail.isEmpty {
            localGlossaryLogger.info("local-glossary-refresh stage=\(stage, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public)")
        } else {
            localGlossaryLogger.info("local-glossary-refresh stage=\(stage, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public) detail=\(detail, privacy: .public)")
        }
        return elapsedMilliseconds
    }

    func acceptLocalGlossarySuggestion(
        id: String,
        canonical: String,
        category: LocalGlossaryCategory = .domainTerm
    ) {
        localGlossaryState.acceptSuggestion(id: id, canonical: canonical, category: category)
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "용어 사전에 추가했습니다."
        refreshActiveLocalGlossaryMatchCountIfNeeded()
        refreshMeetingHistory(force: true)
    }

    func dismissLocalGlossarySuggestion(id: String) {
        localGlossaryState.dismissSuggestion(id: id)
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "용어 후보를 숨겼습니다."
    }

    func addManualLocalGlossaryTerm(
        selectedText: String,
        canonical: String,
        category: LocalGlossaryCategory = .domainTerm
    ) {
        guard localGlossaryState.addManualSelectionTerm(
            selectedText: selectedText,
            canonical: canonical,
            category: category
        ) != nil else {
            localGlossaryStatusMessage = "선택한 텍스트를 용어로 추가할 수 없습니다."
            return
        }
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "Raw Transcript 선택을 용어 사전에 추가했습니다."
        refreshActiveLocalGlossaryMatchCountIfNeeded()
        refreshMeetingHistory(force: true)
    }

    func addManualLocalGlossaryAlias(
        selectedText: String,
        toTermID termID: String
    ) {
        guard localGlossaryState.addManualSelectionAlias(selectedText: selectedText, toTermID: termID) else {
            localGlossaryStatusMessage = "선택한 텍스트를 alias로 추가할 수 없습니다."
            return
        }
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "Raw Transcript 선택을 기존 용어 alias로 추가했습니다."
        refreshActiveLocalGlossaryMatchCountIfNeeded()
        refreshMeetingHistory(force: true)
    }

    func acceptLocalGlossaryReviewCandidateAsNewTerm(
        id: String,
        canonical: String,
        category: LocalGlossaryCategory = .domainTerm
    ) {
        localGlossaryState.acceptReviewCandidateAsNewTerm(id: id, canonical: canonical, category: category)
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "검토 후보를 새 용어로 추가했습니다."
        refreshActiveLocalGlossaryMatchCountIfNeeded()
        refreshMeetingHistory(force: true)
    }

    func addLocalGlossaryReviewCandidate(id: String, toTermID termID: String) {
        localGlossaryState.addReviewCandidate(id: id, asAliasesToTermID: termID)
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "기존 용어 alias로 추가했습니다."
        refreshActiveLocalGlossaryMatchCountIfNeeded()
        refreshMeetingHistory(force: true)
    }

    func markLocalGlossaryReviewCandidateAsNotSame(id: String) {
        localGlossaryState.markReviewCandidateAsNotSame(id: id)
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "서로 다른 단어로 표시했습니다."
    }

    func dismissLocalGlossaryReviewCandidate(id: String) {
        localGlossaryState.dismissReviewCandidate(id: id)
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "검토 후보를 숨겼습니다."
    }

    func deleteLocalGlossaryTerm(id: String) {
        localGlossaryState.deleteTerm(id: id)
        try? stateStore.saveLocalGlossaryState(localGlossaryState)
        localGlossaryStatusMessage = "용어를 삭제했습니다."
        refreshActiveLocalGlossaryMatchCountIfNeeded()
        refreshMeetingHistory(force: true)
    }

    func updateProvider(_ provider: LLMProviderKind) {
        settings.selectedProvider = provider
        saveSettings()
    }

    func updateCodexExecutionMode(_ mode: CodexExecutionMode) {
        settings.codexExecutionMode = mode
        saveSettings()
    }

    func setCodexAppServerDiagnosticsEnabled(_ isEnabled: Bool) {
        settings.codexAppServerDiagnosticsEnabled = isEnabled
        saveSettings()
    }

    func updateModelPreset(_ modelPreset: LLMModelPreset) {
        settings.modelPreset = modelPreset
        saveSettings()
    }

    func updateMeetingTypePreset(_ preset: MeetingTypePreset) {
        settings.meetingTypePreset = preset
        saveSettings()
    }

    func updateAnalysisTriggerPreset(_ preset: AnalysisTriggerPreset) {
        settings.analysisTriggerPreset = preset
        saveSettings()
    }

    func updateLiveContextRetrievalMode(_ mode: LiveContextRetrievalMode) {
        settings.liveContextRetrievalMode = mode
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
        cancelActiveAnalysis(message: "선택 폴더 해제로 실행 중이던 analysis를 중단했습니다.")
        searchIndexBuildTask?.cancel()
        searchDatabaseQueryTask?.cancel()
        liveTranscriptIndex.reset()
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
        transcriptSpeakers = []
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

    func refreshGoogleCalendarConnectionStatus() {
        do {
            let service = try makeGoogleCalendarService()
            googleCalendarStatusMessage = service.hasStoredRefreshToken()
                ? GoogleCalendarConnectionState.connected.displayText
                : GoogleCalendarConnectionState.disconnected.displayText
        } catch GoogleCalendarIntegrationError.missingConfig {
            googleCalendarStatusMessage = GoogleCalendarConnectionState.notConfigured.displayText
        } catch {
            googleCalendarStatusMessage = GoogleCalendarConnectionState.failed(error.localizedDescription).displayText
        }
    }

    func connectGoogleCalendar() {
        guard !isGoogleCalendarConnecting else {
            return
        }
        isGoogleCalendarConnecting = true
        googleCalendarStatusMessage = "Google Calendar 인증 브라우저를 여는 중"

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let service = try makeGoogleCalendarService()
                try await service.connect()
                googleCalendarStatusMessage = GoogleCalendarConnectionState.connected.displayText
                calendarContextStatusMessage = "Google Calendar API 연결됨"
            } catch {
                googleCalendarStatusMessage = googleCalendarMessage(for: error)
            }
            isGoogleCalendarConnecting = false
        }
    }

    func disconnectGoogleCalendar() {
        do {
            let service = try makeGoogleCalendarService()
            try service.disconnect()
            googleCalendarStatusMessage = GoogleCalendarConnectionState.disconnected.displayText
        } catch {
            googleCalendarStatusMessage = googleCalendarMessage(for: error)
        }
    }

    func fetchGoogleCalendarAPIContext() {
        guard !isFetchingGoogleCalendarAPIContext else {
            return
        }
        guard activeTranscriptURL != nil else {
            calendarContextStatusMessage = "Calendar context를 저장할 transcript가 없습니다."
            return
        }

        let window = googleCalendarFetchWindow()
        isFetchingGoogleCalendarAPIContext = true
        googleCalendarStatusMessage = "Google Calendar API에서 현재 회의 context를 가져오는 중"

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let service = try makeGoogleCalendarService()
                let response = try await service.fetchEvents(request: window.request)
                let mapped = GoogleCalendarContextMapper.map(
                    response,
                    metadata: metadata,
                    meetingStart: window.meetingStart,
                    meetingEnd: window.meetingEnd
                )
                applyGoogleCalendarAPIContext(mapped)
                googleCalendarStatusMessage = GoogleCalendarConnectionState.connected.displayText
                calendarContextStatusMessage = "Google Calendar API 후보 \(mapped.eventCandidates.count)개를 저장했습니다."
                persistCandidateStateChange()
            } catch {
                let message = googleCalendarMessage(for: error)
                googleCalendarStatusMessage = message
                calendarContextStatusMessage = message
            }
            isFetchingGoogleCalendarAPIContext = false
        }
    }

    func fetchGoogleCalendarContext() {
        guard !isFetchingCalendarContext else {
            return
        }
        guard settings.selectedProvider != .customCommand else {
            analysisState.calendarContext.mcpStatus = .missing
            analysisState.calendarContext.lastError = "Google Calendar MCP는 Codex 또는 Claude Code provider에서만 사용할 수 있습니다."
            calendarContextStatusMessage = analysisState.calendarContext.lastError ?? "Google Calendar MCP 설정이 필요합니다."
            persistCandidateStateChange()
            return
        }
        guard !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            calendarContextStatusMessage = "Calendar context를 가져올 transcript가 없습니다."
            return
        }

        isFetchingCalendarContext = true
        calendarContextStatusMessage = "Google Calendar MCP에서 회의 후보를 가져오는 중"
        analysisState.calendarContext.mcpStatus = .unknown
        analysisState.calendarContext.lastError = nil

        let request = CalendarMCPFetchRequest(
            metadata: metadata,
            rawTranscriptPrefix: String(rawTranscript.prefix(3_000))
        )
        let providerKind = settings.selectedProvider
        let modelPreset = settings.modelPreset
        let timeoutSeconds = effectiveAnalysisTimeoutSeconds(for: "calendar-mcp")
        let schemaURL = calendarContextSchemaURL()
        let workingDirectoryURL = selectedFolderURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let result = try await CalendarMCPContextFetcher.fetch(
                    request: request,
                    providerKind: providerKind,
                    modelPreset: modelPreset,
                    schemaURL: schemaURL,
                    timeoutSeconds: timeoutSeconds,
                    workingDirectoryURL: workingDirectoryURL
                )
                self.analysisState.calendarContext.mcpStatus = .connected
                self.analysisState.calendarContext.eventCandidates = result.events
                self.analysisState.calendarContext.lastFetchedAt = Date()
                self.analysisState.calendarContext.lastError = nil
                self.mergeCalendarLinkedSourceCandidates(result.linkedSourceCandidates)
                self.calendarContextStatusMessage = "Calendar 후보 \(result.events.count)개 · linked source 후보 \(result.linkedSourceCandidates.count)개"
                self.isFetchingCalendarContext = false
                self.persistCandidateStateChange()
            } catch {
                self.analysisState.calendarContext.mcpStatus = .failed
                self.analysisState.calendarContext.lastError = error.localizedDescription
                self.calendarContextStatusMessage = "Calendar MCP 실패: \(error.localizedDescription)"
                self.isFetchingCalendarContext = false
                self.persistCandidateStateChange()
            }
        }
    }

    func acceptCalendarEventCandidate(id: String) {
        guard let index = analysisState.calendarContext.eventCandidates.firstIndex(where: { $0.id == id }) else {
            return
        }
        var candidate = analysisState.calendarContext.eventCandidates[index]
        candidate.status = .accepted
        analysisState.calendarContext.eventCandidates[index] = candidate
        analysisState.calendarContext.meetingIdentity = MeetingIdentity(
            calendarEventID: candidate.id,
            recurrenceID: candidate.recurrenceID,
            fallbackFingerprint: meetingIdentityFallbackFingerprint(),
            confidence: candidate.confidence,
            isConfirmed: true
        )
        analysisState.calendarContext.supplementalSources.removeAll { $0.id == "calendar:\(candidate.id)" }
        analysisState.calendarContext.supplementalSources.append(
            SupplementalContextSource(
                id: "calendar:\(candidate.id)",
                kind: .calendarMetadata,
                title: candidate.title,
                sourceName: "Google Calendar",
                excerpt: calendarExcerpt(candidate),
                priority: .calendarMetadata,
                confidence: candidate.confidence
            )
        )
        calendarContextStatusMessage = "Calendar event를 meeting identity로 사용합니다."
        persistCandidateStateChange()
    }

    func dismissCalendarEventCandidate(id: String) {
        guard let index = analysisState.calendarContext.eventCandidates.firstIndex(where: { $0.id == id }) else {
            return
        }
        analysisState.calendarContext.eventCandidates[index].status = .dismissed
        calendarContextStatusMessage = "Calendar 후보를 숨겼습니다."
        persistCandidateStateChange()
    }

    func chooseSupplementalContextFile() {
        let panel = NSOpenPanel()
        panel.title = "Supplemental Context 첨부"
        panel.prompt = "첨부"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            .plainText
        ]
        panel.directoryURL = activeTranscriptURL?.deletingLastPathComponent() ?? selectedFolderURL

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        attachSupplementalContextFile(url)
    }

    func attachSupplementalContextFile(_ url: URL) {
        do {
            let source = try SupplementalContextReader.source(from: url)
            analysisState.calendarContext.supplementalSources.removeAll { $0.id == source.id }
            analysisState.calendarContext.supplementalSources.append(source)
            calendarContextStatusMessage = "Context 첨부 완료: \(source.sourceName)"
            persistCandidateStateChange()
        } catch {
            calendarContextStatusMessage = "Context 첨부 실패: \(error.localizedDescription)"
        }
    }

    var shouldShowMomentMarker: Bool {
        MomentMarkerAvailability.isVisible(runMode: transcriptRunMode.momentMarkerRunMode)
    }

    var canAddLiveBookmark: Bool {
        MomentMarkerAvailability.canAdd(
            runMode: transcriptRunMode.momentMarkerRunMode,
            hasActiveTranscript: activeTranscriptURL != nil,
            hasTranscriptPreview: !rawTranscriptPreviewLines.isEmpty
        )
    }

    func addLiveBookmark(label: String? = nil) {
        guard let activeTranscriptURL, canAddLiveBookmark else {
            statusMessage = "중요 시점으로 표시할 transcript가 없습니다."
            return
        }

        let seconds = latestTranscriptElapsedSeconds()
        let bookmark = MeetingBookmark(
            timestamp: elapsedTimestamp(seconds),
            label: label,
            excerpt: latestTranscriptExcerpt()
        )
        analysisState.addBookmark(bookmark)
        analysisState.updatedAt = Date()
        try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
        statusMessage = "중요 시점 저장: \(bookmark.timestamp)"
    }

    func deleteLiveBookmark(id: String) {
        guard let activeTranscriptURL else {
            return
        }
        analysisState.deleteBookmark(id: id)
        analysisState.updatedAt = Date()
        try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
        statusMessage = "중요 시점을 삭제했습니다."
    }

    func dismissCarryOverQuestion(id: String) {
        setCarryOverQuestionStatus(id: id, status: .dismissed)
        statusMessage = "이어받은 질문을 숨겼습니다."
    }

    func resolveCarryOverQuestion(id: String) {
        setCarryOverQuestionStatus(id: id, status: .resolved)
        statusMessage = "이어받은 질문을 해결됨으로 표시했습니다."
    }

    func refreshCarryOverQuestions() {
        guard canRefreshCarryOverQuestions else {
            statusMessage = "이어받은 질문을 새로고침하려면 transcript 폴더와 분석 결과가 필요합니다."
            return
        }
        statusMessage = "이어받은 질문을 새로고침합니다."
        refreshMeetingHistory(force: true)
    }

    private func setCarryOverQuestionStatus(id: String, status: CarryOverQuestionStatus) {
        analysisState.setCarryOverQuestionStatus(id: id, status: status)
        analysisState.updatedAt = Date()
        if let activeTranscriptURL {
            try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
            patchMeetingHistoryItem(for: activeTranscriptURL)
        }
    }

    func openGitHubIssueDraft(kind: GitHubIssueDraftKind) {
        let title = "\(kind.titlePrefix) "
        let body = githubIssueDraftBody(kind: kind)
        var components = URLComponents(string: "https://github.com/breadceo/meeting-rescue/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "labels", value: kind.githubLabel),
            URLQueryItem(name: "body", value: body)
        ]

        guard let url = components?.url else {
            statusMessage = "GitHub issue URL 생성에 실패했습니다."
            return
        }
        NSWorkspace.shared.open(url)
        statusMessage = "\(kind.displayName) issue 작성 화면을 브라우저로 열었습니다."
    }

    func requestCurrentIntelligenceMarkdownExport() {
        let warnings = currentShareReadinessWarnings
        guard !warnings.isEmpty else {
            exportCurrentIntelligenceMarkdownIgnoringReadiness()
            return
        }
        pendingMarkdownReadinessWarnings = warnings
    }

    func exportCurrentIntelligenceMarkdownIgnoringReadiness() {
        pendingMarkdownReadinessWarnings = []
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

    func cancelMarkdownReadinessPreview() {
        pendingMarkdownReadinessWarnings = []
    }

    private func githubIssueDraftBody(kind: GitHubIssueDraftKind) -> String {
        let latestAttempt = analysisState.attemptLogs.last
        let usage = analysisState.usageSummary
        let appVersion = AppVersion.shortVersion ?? "-"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let sourceFile = activeTranscriptURL?.lastPathComponent ?? "-"
        let latestAttemptLines: [String]
        if let latestAttempt {
            latestAttemptLines = [
                "- Reason: \(latestAttempt.reason)",
                "- Status: \(latestAttempt.status.rawValue)",
                "- Model: \(latestAttempt.modelName) / \(latestAttempt.modelPreset.displayName)",
                "- Tokens: \(latestAttempt.inputTokens) in / \(latestAttempt.outputTokens) out",
                "- Duration: \(latestAttempt.elapsedMilliseconds.map { "\($0)ms" } ?? "-")",
                "- Message: \(compactIssueText(latestAttempt.message ?? "-", limit: 280))"
            ]
        } else {
            latestAttemptLines = ["- 없음"]
        }

        return """
        ## 종류
        - \(kind.displayName)

        ## 설명
        <!-- 어떤 문제가 있었는지, 또는 어떤 기능을 원하는지 적어주세요. -->

        ## 기대 동작
        <!-- 기대한 동작을 적어주세요. -->

        ## 실제 동작
        <!-- 버그인 경우 실제로 발생한 동작을 적어주세요. -->

        ## 앱 상태
        - App: Meeting Rescue \(appVersion) (\(buildNumber))
        - Mode: \(transcriptRunMode.displayText)
        - Source file: \(sourceFile)
        - Meeting title: \(compactIssueText(metadata.displayTitle, limit: 120))
        - Analysis status: \(compactIssueText(analysisStatus.displayText, limit: 160))
        - Provider: \(settings.selectedProvider.displayName) / \(settings.modelPreset.displayName)
        - Auto analysis: \(settings.automaticAnalysisEnabled ? "on" : "off")
        - Search DB: \(compactIssueText(searchIndexProgress.displayText, limit: 160))
        - Lines: \(rawTranscriptLineCount)
        - Usage: \(usage.totalInputTokens) in / \(usage.totalOutputTokens) out / \(String(format: "$%.4f", usage.totalEstimatedCostUSD))

        ## 최근 Analysis attempt
        \(latestAttemptLines.joined(separator: "\n"))

        ## 참고
        - 회의 원문, 참석자 전체 목록, 로컬 전체 경로는 기본으로 첨부하지 않았습니다.
        - 필요하면 민감정보를 제거한 뒤 로그/스크린샷을 추가해주세요.
        """
    }

    private func compactIssueText(_ text: String, limit: Int) -> String {
        let oneLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard oneLine.count > limit else {
            return oneLine
        }
        return String(oneLine.prefix(limit - 1)) + "…"
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
        cancelActiveAnalysis(message: "Test Run 시작으로 실행 중이던 analysis를 중단했습니다.")
        latestSnapshotIsLocalFallback = false
        liveTranscriptIndex.reset()

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
            transcriptSpeakers = []
            transcriptFocusRequest = nil
            highlightedTranscriptLineID = nil
            rawTranscriptLineCount = 0
            rawReadOffset = 0
            lastAutomaticAnalysisAt = nil
            finalAnalysisTriggeredForMeetingID = nil
            clearFinalRetryCounts(for: fileURL)
            metadata = MeetingMetadata()
            let cachedCalendarContext = stateStore.loadAnalysisState(for: fileURL).calendarContext.cachedForTestRunReplay()
            analysisState = MeetingAnalysisState(calendarContext: cachedCalendarContext)
            calendarContextStatusMessage = cachedCalendarContext.hasReusableContext
                ? "저장된 Google Calendar context를 Test Run에 적용했습니다."
                : "Google Calendar context 확인 전"
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
        liveTranscriptIndex.append(frame.text)
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
            previousSnapshot: providerPreviousSnapshot(),
            confirmedCandidateIDs: analysisState.confirmedCandidateIDs,
            deletedCandidateIDs: analysisState.deletedCandidateIDs,
            providerKind: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            meetingTypePreset: settings.meetingTypePreset,
            bookmarks: analysisState.bookmarks,
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
        let localGlossaryState = localGlossaryState
        let localGlossaryEnabled = settings.localGlossaryEnabled
        let previousHistorySignature = force ? nil : lastHistorySignature
        historyRefreshTask = Task { [weak self, selectedFolderURL, stateStore, lineLimit, shouldIncludeRawTranscriptSearch, searchIndexExclusionURL, localGlossaryState, localGlossaryEnabled, previousHistorySignature] in
            let result = await Task.detached(priority: .utility) {
                    MeetingHistoryBuilder(
                        stateStore: stateStore,
                        rawTranscriptSearchLineLimit: lineLimit,
                        includeRawTranscriptSearch: shouldIncludeRawTranscriptSearch,
                        includeLocalGlossarySearchSections: false,
                        searchIndexExclusionURL: searchIndexExclusionURL,
                        localGlossaryState: localGlossaryState,
                        localGlossaryEnabled: localGlossaryEnabled
                )
                .buildIfChanged(folderURL: selectedFolderURL, previousSignature: previousHistorySignature)
            }
            .value

            guard let self else {
                return
            }
            self.historyRefreshTask = nil
            guard !Task.isCancelled, self.selectedFolderURL == selectedFolderURL else {
                return
            }
            guard let result else {
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
        let localGlossaryState = localGlossaryState
        let localGlossaryEnabled = settings.localGlossaryEnabled
        searchIndexProgress = MeetingSearchIndexProgress(state: .checking, completed: 0, total: meetingHistoryItems.count)
        searchIndexBuildTask = Task(priority: .background) { [weak self, searchDatabase, stateStore, lineLimit, folderURL, fileSignature, excludedURL, localGlossaryState, localGlossaryEnabled] in
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
                        includeLocalGlossarySearchSections: false,
                        searchIndexExclusionURL: excludedURL,
                        localGlossaryState: localGlossaryState,
                        localGlossaryEnabled: localGlossaryEnabled
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

    private var currentWorkflowMeetingID: String {
        activeTranscriptURL?.path ?? metadata.displayTitle
    }

    private var currentWorkflowOccurredAt: Date? {
        guard let activeTranscriptURL else {
            return nil
        }
        return try? activeTranscriptURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func workflowHistorySources(excluding activeURL: URL?) -> [ActionLedgerMeetingSource] {
        meetingHistoryItems.compactMap { item in
            guard item.url != activeURL else {
                return nil
            }
            let state = stateStore.loadAnalysisState(for: item.url)
            guard let snapshot = state.latestSnapshot else {
                return nil
            }
            return ActionLedgerMeetingSource(
                meetingID: item.id,
                sourceFileName: item.url.lastPathComponent,
                metadata: item.metadata,
                occurredAt: item.modificationDate,
                snapshot: snapshot
            )
        }
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

        let preparedGlossaryState = LocalGlossaryMatcher.PreparedState(state: localGlossaryState)
        sections.append(contentsOf: localGlossarySearchSections(
            from: sections,
            state: localGlossaryState,
            isEnabled: settings.localGlossaryEnabled,
            preparedState: preparedGlossaryState
        ))

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

    private func currentLatestTranscriptCandidate(force: Bool = false) -> TranscriptFileCandidate? {
        guard let selectedFolderURL else {
            return nil
        }

        let now = Date()
        if !force,
           let lastLatestTranscriptScanAt,
           now.timeIntervalSince(lastLatestTranscriptScanAt) < latestTranscriptFullScanInterval,
           let cachedCandidate = refreshCachedLatestTranscriptCandidate() {
            return cachedCandidate
        }

        let candidate = LatestTranscriptSelector.latestTextFile(
            from: LatestTranscriptSelector.textFiles(in: selectedFolderURL)
        )
        cachedLatestTranscriptCandidate = candidate
        lastLatestTranscriptScanAt = now
        return candidate
    }

    private func refreshCachedLatestTranscriptCandidate() -> TranscriptFileCandidate? {
        guard let cachedLatestTranscriptCandidate,
              let values = try? cachedLatestTranscriptCandidate.url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
              ),
              values.isRegularFile != false else {
            self.cachedLatestTranscriptCandidate = nil
            lastLatestTranscriptScanAt = nil
            return nil
        }

        let refreshedCandidate = TranscriptFileCandidate(
            url: cachedLatestTranscriptCandidate.url,
            modificationDate: values.contentModificationDate ?? cachedLatestTranscriptCandidate.modificationDate
        )
        self.cachedLatestTranscriptCandidate = refreshedCandidate
        return refreshedCandidate
    }

    private func captureHistoryLiveBaseline() {
        historyLiveBaselineCandidate = currentLatestTranscriptCandidate(force: true)
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
                transcriptSpeakers = []
                transcriptFocusRequest = nil
                highlightedTranscriptLineID = nil
                rawTranscriptLineCount = 0
                metadata = MeetingMetadata()
                analysisState = MeetingAnalysisState()
                analysisStatus = .idle
                rawReadOffset = 0
                liveTranscriptIndex.reset()
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
            refreshMeetingHistory()
        } else {
            let didReadAppendedContent = readAppendedContent(from: latestURL)
            if didReadAppendedContent {
                refreshMeetingHistory()
            }
        }
    }

    private func switchActiveTranscript(to url: URL) {
        cancelActiveAnalysis(message: "active transcript 전환으로 실행 중이던 analysis를 중단했습니다.")
        latestSnapshotIsLocalFallback = false
        lastAutomaticAnalysisAt = Date()
        liveTranscriptIndex.reset()
        loadTranscriptForViewing(url, statusPrefix: "활성 transcript")
        liveMeetingUpdated = false
        historyLiveBaselineCandidate = nil
    }

    private func loadTranscriptForViewing(_ url: URL, statusPrefix: String) {
        activeTranscriptURL = url
        rawTranscript = ""
        rawTranscriptPreviewLines = []
        transcriptSpeakers = []
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
        latestSnapshotIsLocalFallback = LocalAnalysisFallback.isFallbackSnapshot(analysisState.latestSnapshot)
        analysisStatus = analysisState.isCompleted ? .completed : .idle

        if let session = stateStore.loadSession(for: url) {
            metadata = session.metadata
        } else {
            metadata = MeetingMetadata()
        }

        let id = meetingID(for: url)
        let seedSnapshot = providerPreviousSnapshot()
        Task {
            await scheduler.setActiveMeetingID(id)
            await scheduler.seedSnapshot(seedSnapshot, for: id)
        }

        readFullContent(from: url, allowFinalTrigger: false)
        autoFetchGoogleCalendarAPIContextForLiveWatchIfNeeded()
        statusMessage = "\(statusPrefix): \(url.lastPathComponent)"
    }

    private func readFullContent(from url: URL, allowFinalTrigger: Bool = true) {
        do {
            let data = try Data(contentsOf: url)
            rawTranscript = TranscriptTextDecoder.decode(data)
            if transcriptRunMode != .history {
                liveTranscriptIndex.rebuild(from: rawTranscript)
            }
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

    private func readAppendedContent(from url: URL) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            if fileSize < rawReadOffset {
                readFullContent(from: url, allowFinalTrigger: true)
                return true
            }

            guard fileSize > rawReadOffset else {
                return false
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }
            try handle.seek(toOffset: rawReadOffset)
            let data = try handle.readToEnd() ?? Data()

            guard !data.isEmpty else {
                return false
            }

            let appendedText = TranscriptTextDecoder.decode(data)
            rawTranscript += appendedText
            if transcriptRunMode != .history {
                liveTranscriptIndex.append(appendedText)
            }
            appendTranscriptPreview(appendedText)
            rawReadOffset = fileSize
            transcriptUpdatedAt = Date()
            refreshParsedState(
                for: url,
                parseMetadata: metadata.dateTime == nil && metadata.participants.isEmpty,
                endMarkerSource: String(rawTranscript.suffix(1_024)),
                allowFinalTrigger: true
            )
            return true
        } catch {
            statusMessage = "transcript tail 실패: \(error.localizedDescription)"
            return false
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

    private func autoFetchGoogleCalendarAPIContextForLiveWatchIfNeeded() {
        guard transcriptRunMode == .liveWatch,
              let activeTranscriptURL,
              !isFetchingGoogleCalendarAPIContext else {
            return
        }
        let id = meetingID(for: activeTranscriptURL)
        guard !autoFetchedGoogleCalendarMeetingIDs.contains(id) else {
            return
        }
        guard let service = try? makeGoogleCalendarService(),
              service.hasStoredRefreshToken() else {
            return
        }

        autoFetchedGoogleCalendarMeetingIDs.insert(id)
        fetchGoogleCalendarAPIContext()
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
        cancelActiveAnalysis(message: "Automatic Meeting Intelligence를 일시 중지했습니다.")
        statusMessage = "Automatic Meeting Intelligence를 일시 중지했습니다."
        analysisStatus = analysisState.isCompleted ? .completed : .stale(statusMessage)
    }

    private func cancelActiveAnalysis(message: String) {
        analysisRunGeneration += 1
        analysisTask?.cancel()
        analysisTask = nil

        if activeAnalysisAttemptID != nil {
            updateActiveAttempt(status: .skipped, outputTokens: 0, message: message)
            analysisState.updatedAt = Date()
            if let activeTranscriptURL {
                try? stateStore.saveAnalysisState(analysisState, for: activeTranscriptURL)
            }
        }

        activeAnalysisRequest = nil
        activeAnalysisWindow = nil
        activeAnalysisAttemptID = nil
        analysisStatus = analysisState.isCompleted ? .completed : .idle
    }

    private func isAutomaticAnalysisReason(_ reason: String) -> Bool {
        reason.hasPrefix("automatic") || reason.hasPrefix("final")
    }

    private func makeAnalysisRequest(
        reason: String,
        transcriptWindow: AnalysisTranscriptWindow,
        previousSnapshot: AnalysisSnapshot?
    ) -> AnalysisRequest? {
        guard let activeTranscriptURL else {
            return nil
        }
        let supplementalSources = analysisState.calendarContext.supplementalSources
            + glossarySupplementalSources(for: transcriptWindow.rawTranscript)
        return AnalysisRequest(
            meetingID: meetingID(for: activeTranscriptURL),
            metadata: metadata,
            rawTranscript: transcriptWindow.rawTranscript,
            previousSnapshot: previousSnapshot,
            confirmedCandidateIDs: analysisState.confirmedCandidateIDs,
            deletedCandidateIDs: analysisState.deletedCandidateIDs,
            providerKind: settings.selectedProvider,
            modelPreset: settings.modelPreset,
            meetingTypePreset: settings.meetingTypePreset,
            bookmarks: analysisState.bookmarks,
            reason: reason,
            lastAnalyzedTranscriptCharacterCount: transcriptWindow.lastAnalyzedTranscriptCharacterCount,
            supplementalContextSources: supplementalSources
        )
    }

    private func glossarySupplementalSources(for text: String) -> [SupplementalContextSource] {
        guard settings.localGlossaryEnabled else {
            return []
        }
        return LocalGlossaryMatcher.supplementalSources(for: text, state: localGlossaryState)
    }

    private func triggerAnalysis(reason: String) {
        guard analysisTask == nil,
              let activeTranscriptURL,
              !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let previousSnapshot = providerPreviousSnapshot() ?? patchBaselineSnapshot(for: reason)
        let transcriptWindow = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: analysisState.analyzedTranscriptCharacterCount,
            reason: reason,
            maxAutomaticCatchUpCharacters: automaticCatchUpChunkCharacters
        )
        guard var request = makeAnalysisRequest(
            reason: reason,
            transcriptWindow: transcriptWindow,
            previousSnapshot: previousSnapshot
        ) else {
            return
        }
        let contextPlan = AnalysisContextPlanner.makePlan(
            for: request,
            retrievalMode: liveContextRetrievalMode(for: reason),
            liveIndex: liveTranscriptIndex
        )
        request.contextPlan = contextPlan

        let timeoutSeconds = effectiveAnalysisTimeoutSeconds(for: reason)
        let provider = makeProvider(timeoutSeconds: timeoutSeconds)
        activeAnalysisRequest = request
        activeAnalysisWindow = transcriptWindow
        analysisRunGeneration += 1
        let runGeneration = analysisRunGeneration
        let draftPrompt = (try? AnalysisPromptBuilder.buildPrompt(for: request)) ?? rawTranscript
        let draftInputTokens = TokenEstimator.estimateTokens(in: draftPrompt)
        let finalContextPlan = AnalysisContextPlanner.planByUpdatingEstimatedTokens(
            contextPlan,
            estimatedPromptTokens: draftInputTokens
        )
        request.contextPlan = finalContextPlan
        activeAnalysisRequest = request
        let prompt = (try? AnalysisPromptBuilder.buildPrompt(for: request)) ?? rawTranscript
        let inputTokens = TokenEstimator.estimateTokens(in: prompt)
        let attemptMessage = ["timeout \(timeoutSeconds)초", transcriptWindow.messageSuffix]
            .compactMap { $0 }
            .joined(separator: " · ")
        let attempt = AnalysisAttemptLog(
            reason: reason,
            status: .running,
            provider: settings.selectedProvider,
            codexExecutionMode: currentCodexExecutionModeForAttempt(),
            modelPreset: settings.modelPreset,
            modelName: currentModelName(),
            inputTokens: inputTokens,
            message: attemptMessage,
            prompt: prompt,
            batchStats: makeAttemptBatchStats(for: transcriptWindow, reason: reason),
            contextPlan: finalContextPlan
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
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard self.analysisRunGeneration == runGeneration else {
                    return
                }
                self.applyAnalysisResult(result, for: activeTranscriptURL, reason: reason)
            }
        }
    }

    private func liveContextRetrievalMode(for reason: String) -> LiveContextRetrievalMode {
        guard transcriptRunMode != .history,
              !reason.hasPrefix("repair"),
              !reason.hasPrefix("full-refresh") else {
            return .off
        }
        return settings.liveContextRetrievalMode
    }

    private func latestTranscriptElapsedSeconds() -> Int {
        rawTranscriptPreviewLines
            .reversed()
            .compactMap { TranscriptTimestampLocator.elapsedSeconds(in: $0) }
            .first ?? 0
    }

    private func elapsedTimestamp(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "[%02d:%02d:%02d]", hours, minutes, seconds)
        }
        return String(format: "[%02d:%02d]", minutes, seconds)
    }

    private func latestTranscriptExcerpt() -> String {
        rawTranscriptPreviewLines
            .reversed()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func providerPreviousSnapshot() -> AnalysisSnapshot? {
        guard let latestSnapshot = analysisState.latestSnapshot,
              !latestSnapshotIsLocalFallback,
              !LocalAnalysisFallback.isFallbackSnapshot(latestSnapshot) else {
            return nil
        }
        return latestSnapshot
    }

    private func patchBaselineSnapshot(for reason: String) -> AnalysisSnapshot? {
        guard !AnalysisRequest.usesFullSnapshotOutput(reason) else {
            return nil
        }
        return AnalysisSnapshot(currentIssue: CurrentIssue(summary: ""))
    }

    #if DEBUG
    func loadTranscriptForTesting(url: URL, rawTranscript: String) {
        activeTranscriptURL = url
        metadata = TranscriptParser.parse(rawTranscript).metadata
        self.rawTranscript = rawTranscript
        rawTranscriptLineCount = rawTranscript.components(separatedBy: .newlines).count
        refreshActiveLocalGlossaryMatchCountIfNeeded()
    }

    func analysisRequestForTesting(reason: String) -> AnalysisRequest? {
        guard activeTranscriptURL != nil else {
            return nil
        }
        let window = AnalysisTranscriptWindow.make(
            rawTranscript: rawTranscript,
            lastAnalyzedTranscriptCharacterCount: analysisState.analyzedTranscriptCharacterCount,
            reason: reason,
            maxAutomaticCatchUpCharacters: automaticCatchUpChunkCharacters
        )
        return makeAnalysisRequest(
            reason: reason,
            transcriptWindow: window,
            previousSnapshot: providerPreviousSnapshot() ?? patchBaselineSnapshot(for: reason)
        )
    }
    #endif

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

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private func automaticWaitLabel(for reason: String) -> String {
        switch reason {
        case "initial-meeting-gate":
            return "초기 skip"
        case "system-only":
            return "system only"
        case "low-value-dialogue":
            return "낮은 신호"
        case "min-batch-wait":
            return "최소 대기"
        case "batch-threshold-not-reached":
            return "batch 대기"
        case "no-new-transcript":
            return "새 transcript 없음"
        default:
            return reason
        }
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
        return reason.hasPrefix("manual")
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
        return "manual-continue"
    }

    private func appendRetryScheduledAttempt(reason: String, sourceURL: URL, message: String) {
        let attempt = AnalysisAttemptLog(
            reason: reason,
            status: .retryScheduled,
            provider: settings.selectedProvider,
            codexExecutionMode: currentCodexExecutionModeForAttempt(),
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
            codexExecutionMode: currentCodexExecutionModeForAttempt(),
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

    private func mergeCalendarLinkedSourceCandidates(_ candidates: [CalendarLinkedSourceCandidate]) {
        analysisState.calendarContext.supplementalSources.removeAll { $0.kind == .linkedSourceCandidate }
        analysisState.calendarContext.supplementalSources.append(contentsOf: candidates.map { candidate in
            SupplementalContextSource(
                id: "calendar-link:\(candidate.id)",
                kind: .linkedSourceCandidate,
                title: candidate.title,
                sourceName: candidate.sourceName,
                excerpt: candidate.url,
                priority: .linkedSourceCandidate,
                confidence: candidate.confidence,
                isAccepted: false
            )
        })
    }

    private func makeGoogleCalendarService() throws -> GoogleCalendarService {
        if let googleCalendarService {
            return googleCalendarService
        }
        let config = try GoogleCalendarOAuthConfigLoader.load()
        let service = GoogleCalendarService(
            config: config,
            tokenStore: GoogleCalendarKeychainTokenStore(account: config.clientID)
        )
        googleCalendarService = service
        return service
    }

    private func applyGoogleCalendarAPIContext(_ context: CalendarContextState) {
        let preservedSupplementalSources = analysisState.calendarContext.supplementalSources.filter { source in
            source.kind != .calendarMetadata
        }
        var next = context
        next.supplementalSources.append(contentsOf: preservedSupplementalSources)
        analysisState.calendarContext = next
    }

    private func googleCalendarFetchWindow(now: Date = Date()) -> GoogleCalendarFetchWindow {
        let meetingStart = parseMeetingDateTime(metadata.dateTime) ?? now
        let meetingEnd = meetingStart.addingTimeInterval(3 * 60 * 60)
        let timeMin = meetingStart.addingTimeInterval(-15 * 60)
        let timeMax = meetingEnd.addingTimeInterval(30 * 60)
        return GoogleCalendarFetchWindow(
            request: GoogleCalendarEventsListRequest(
                calendarID: "primary",
                timeMin: rfc3339String(from: timeMin),
                timeMax: rfc3339String(from: timeMax),
                maxResults: 10
            ),
            meetingStart: meetingStart,
            meetingEnd: meetingEnd
        )
    }

    private func parseMeetingDateTime(_ value: String?) -> Date? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy.MM.dd HH:mm:ss",
            "yyyy.MM.dd HH:mm"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func rfc3339String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func googleCalendarMessage(for error: Error) -> String {
        if let integrationError = error as? GoogleCalendarIntegrationError {
            return integrationError.localizedDescription
        }
        return error.localizedDescription
    }

    private func calendarExcerpt(_ candidate: CalendarEventCandidate) -> String {
        [
            "title: \(candidate.title)",
            "time: \(candidate.startDateText)-\(candidate.endDateText)",
            candidate.organizer.map { "organizer: \($0)" },
            candidate.attendees.isEmpty ? nil : "attendees: \(candidate.attendees.joined(separator: ", "))",
            candidate.descriptionExcerpt.isEmpty ? nil : "description: \(candidate.descriptionExcerpt)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func meetingIdentityFallbackFingerprint() -> String {
        [
            metadata.room ?? "",
            metadata.displayTitle,
            metadata.participants.sorted().joined(separator: ",")
        ]
        .joined(separator: "|")
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .lowercased()
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
            switch settings.codexExecutionMode {
            case .cliExec:
                return CodexExecProvider(
                    schemaURL: analysisSchemaURL(),
                    patchSchemaURL: analysisPatchSchemaURL(),
                    timeoutSeconds: timeoutSeconds,
                    workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                    modelPreset: settings.modelPreset
                )
            case .appServerExperimental:
                return CodexAppServerProvider(
                    schemaURL: analysisSchemaURL(),
                    patchSchemaURL: analysisPatchSchemaURL(),
                    timeoutSeconds: timeoutSeconds,
                    workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                    modelPreset: settings.modelPreset,
                    diagnosticsEnabled: settings.codexAppServerDiagnosticsEnabled,
                    fallbackProvider: CodexExecProvider(
                        schemaURL: analysisSchemaURL(),
                        patchSchemaURL: analysisPatchSchemaURL(),
                        timeoutSeconds: timeoutSeconds,
                        workingDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                        modelPreset: settings.modelPreset
                    )
                )
            }
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

    private func currentCodexExecutionModeForAttempt() -> CodexExecutionMode? {
        settings.selectedProvider == .codexExec ? settings.codexExecutionMode : nil
    }

    private func analysisSchemaURL() -> URL {
        resourceURL(named: "analysis-output.schema.json")
    }

    private func analysisPatchSchemaURL() -> URL {
        resourceURL(named: "analysis-patch-output.schema.json")
    }

    private func calendarContextSchemaURL() -> URL {
        resourceURL(named: "calendar-mcp-context-output.schema.json")
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
        transcriptSpeakers = transcriptSpeakerList(from: lines)
        rawTranscriptRevision += 1
        refreshActiveLocalGlossaryMatchCountIfNeeded()
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
        transcriptSpeakers = transcriptSpeakerList(from: rawTranscriptPreviewLines)
        rawTranscriptRevision += 1
        scheduleActiveLocalGlossaryMatchCountRefresh()
    }

    private func transcriptSpeakerList(from lines: [String]) -> [String] {
        var seen = Set<String>()
        var speakers: [String] = []
        for line in lines {
            guard let speaker = transcriptSpeakerName(in: line) else {
                continue
            }
            let key = speaker.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            speakers.append(speaker)
        }
        return speakers
    }

    private func transcriptSpeakerName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let remainder: Substring
        if trimmed.hasPrefix("["),
           let closing = trimmed.firstIndex(of: "]") {
            remainder = trimmed[trimmed.index(after: closing)...]
        } else if trimmed.hasPrefix("("),
                  let closing = trimmed.firstIndex(of: ")") {
            remainder = trimmed[trimmed.index(after: closing)...]
        } else if let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) {
            let timestampCandidate = trimmed[..<firstSpace]
            guard timestampCandidate.contains(":") else {
                return nil
            }
            remainder = trimmed[trimmed.index(after: firstSpace)...]
        } else {
            return nil
        }

        guard let separator = remainder.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return nil
        }
        let speaker = remainder[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speaker.isEmpty,
              speaker.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).caseInsensitiveCompare("SYSTEM") != .orderedSame else {
            return nil
        }
        return speaker
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
