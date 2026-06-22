import Foundation
import MeetingRescueCore
import Testing
@testable import MeetingRescue

struct AppViewModelTestRunContextTests {
    @Test("Test Run loads saved Google Calendar context as cached replay")
    @MainActor
    func testRunLoadsSavedCalendarContextAsCachedReplay() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRescueTestRun-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let transcriptURL = rootURL.appendingPathComponent("calendar-context-test.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        Zigbang(2F)_Meeting Room L3
        2026-06-08 11:30
        Ethan, Alex

        [00:00] Ethan: Calendar context smoke.
        """.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
        let savedContext = CalendarContextState(
            mcpStatus: .connected,
            eventCandidates: [
                CalendarEventCandidate(
                    id: "google:event-1",
                    title: "원오빌 통합광고 싱크업",
                    startDateText: "2026-06-08T11:30:00+09:00",
                    endDateText: "2026-06-08T12:00:00+09:00",
                    recurrenceID: "series-1",
                    confidence: 0.92,
                    status: .accepted
                ),
                CalendarEventCandidate(
                    id: "google:event-ignored",
                    title: "다른 회의",
                    startDateText: "2026-06-08T11:30:00+09:00",
                    endDateText: "2026-06-08T12:00:00+09:00",
                    confidence: 0.45,
                    status: .dismissed
                )
            ],
            supplementalSources: [
                SupplementalContextSource(
                    id: "calendar:sync",
                    kind: .calendarMetadata,
                    title: "원오빌 통합광고 싱크업",
                    sourceName: "Google Calendar",
                    excerpt: "Calendar context that should replay during Test Run.",
                    priority: .calendarMetadata,
                    confidence: 0.92
                )
            ],
            meetingIdentity: MeetingIdentity(
                calendarEventID: "google:event-1",
                recurrenceID: "series-1",
                fallbackFingerprint: "fallback",
                confidence: 0.92,
                isConfirmed: true
            ),
            lastFetchedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        try stateStore.saveAnalysisState(MeetingAnalysisState(calendarContext: savedContext), for: transcriptURL)

        let viewModel = AppViewModel(stateStore: stateStore)
        let item = MeetingHistoryItem(
            id: transcriptURL.path,
            url: transcriptURL,
            modificationDate: Date(),
            fileSize: 1,
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3"),
            summary: nil,
            topicCount: 0,
            decisionCount: 0,
            actionCount: 0,
            hasAnalysis: true,
            isCompleted: false,
            searchIndex: "",
            searchSections: [],
            summaryPreview: nil
        )

        viewModel.startTestRunFromHistory(item)

        #expect(viewModel.transcriptRunMode == .testRun)
        #expect(viewModel.analysisState.calendarContext.mcpStatus == .cachedReplay)
        #expect(viewModel.analysisState.calendarContext.eventCandidates == savedContext.eventCandidates)
        #expect(viewModel.analysisState.calendarContext.supplementalSources == savedContext.supplementalSources)
        #expect(viewModel.analysisState.calendarContext.meetingIdentity?.seriesKey == "calendar:series-1")
        #expect(viewModel.calendarContextStatusMessage == "저장된 Google Calendar context를 Test Run에 적용했습니다.")
    }

    @Test("Test Run start path does not fetch live Google Calendar or Calendar MCP context")
    func testRunStartPathDoesNotFetchLiveCalendarContext() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let startTestRun = try #require(source.slice(from: "private func startTestRun(fileURL: URL)", to: "private func appendReplayPreambleIfNeeded()"))

        #expect(startTestRun.contains("cachedForTestRunReplay()"))
        #expect(!startTestRun.contains("fetchGoogleCalendarAPIContext()"))
        #expect(!startTestRun.contains("fetchGoogleCalendarContext()"))
        #expect(!startTestRun.contains("makeGoogleCalendarService()"))
        #expect(!startTestRun.contains("CalendarMCPContextFetcher"))
    }

    @Test("Live Watch active transcript path auto-fetches Google Calendar API context once when connected")
    func liveWatchActiveTranscriptPathAutoFetchesCalendarAPIContextOnce() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let loadTranscript = try #require(source.slice(from: "private func loadTranscriptForViewing", to: "private func readFullContent"))
        let autoFetch = try #require(source.slice(from: "private func autoFetchGoogleCalendarAPIContextForLiveWatchIfNeeded()", to: "private func triggerAutomaticAnalysisIfNeeded()"))

        #expect(loadTranscript.contains("autoFetchGoogleCalendarAPIContextForLiveWatchIfNeeded()"))
        #expect(autoFetch.contains("transcriptRunMode == .liveWatch"))
        #expect(autoFetch.contains("activeTranscriptURL"))
        #expect(autoFetch.contains("hasStoredRefreshToken()"))
        #expect(autoFetch.contains("autoFetchedGoogleCalendarMeetingIDs"))
        #expect(autoFetch.contains("fetchGoogleCalendarAPIContext()"))
    }

    @Test("analysis request includes local glossary supplemental context")
    @MainActor
    func analysisRequestIncludesLocalGlossaryContext() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-request-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
        try stateStore.saveLocalGlossaryState(LocalGlossaryState(terms: [
            LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax"], category: .project)
        ]))
        let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "[03:12] Alex: jax workflow를 봅시다.".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let viewModel = AppViewModel(stateStore: stateStore)
        viewModel.loadTranscriptForTesting(url: transcriptURL, rawTranscript: "[03:12] Alex: jax workflow를 봅시다.")

        let request = try #require(viewModel.analysisRequestForTesting(reason: "manual-test"))

        #expect(request.supplementalContextSources.contains { $0.kind == .domainGlossary && $0.excerpt.contains("canonical: zax") })
    }

    @Test("active local glossary match count is cached and refreshed on transcript or term changes")
    @MainActor
    func activeLocalGlossaryMatchCountIsCachedAndRefreshed() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-cache-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
        try stateStore.saveLocalGlossaryState(LocalGlossaryState(terms: [
            LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax"], category: .project)
        ]))
        let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "[03:12] Alex: jax workflow를 봅시다.".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let viewModel = AppViewModel(stateStore: stateStore)
        viewModel.loadTranscriptForTesting(url: transcriptURL, rawTranscript: "[03:12] Alex: jax workflow를 봅시다.")

        #expect(await waitForActiveLocalGlossaryMatchCount(1, in: viewModel))

        viewModel.setLocalGlossaryEnabled(false)
        #expect(viewModel.activeLocalGlossaryMatchCount == 0)

        viewModel.setLocalGlossaryEnabled(true)
        #expect(await waitForActiveLocalGlossaryMatchCount(1, in: viewModel))

        viewModel.deleteLocalGlossaryTerm(id: "term-zax")
        #expect(viewModel.activeLocalGlossaryMatchCount == 0)
    }

    @MainActor
    private func waitForActiveLocalGlossaryMatchCount(
        _ expectedCount: Int,
        in viewModel: AppViewModel
    ) async -> Bool {
        for _ in 0..<50 {
            if viewModel.activeLocalGlossaryMatchCount == expectedCount {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return viewModel.activeLocalGlossaryMatchCount == expectedCount
    }

    @Test("active local glossary match count does not scan from a SwiftUI getter")
    func activeLocalGlossaryMatchCountDoesNotScanFromGetter() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let declaration = try #require(source.slice(from: "@Published private(set) var activeLocalGlossaryMatchCount", to: "var localGlossarySuggestionCount"))

        #expect(declaration.contains("@Published private(set) var activeLocalGlossaryMatchCount"))
        #expect(!declaration.contains("LocalGlossaryMatcher.matches"))
        #expect(source.contains("private func refreshActiveLocalGlossaryMatchCountIfNeeded()"))
    }

    @Test("active transcript append updates speakers and glossary counts incrementally")
    func activeTranscriptAppendUpdatesSpeakersAndGlossaryIncrementally() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let appendPreview = try #require(source.slice(from: "private func appendTranscriptPreview", to: "private func transcriptSpeakerList"))
        let glossaryRefresh = try #require(source.slice(from: "private func refreshActiveLocalGlossaryMatchCountIfNeeded", to: "private func activeLocalGlossaryMatchSignatureForCurrentState"))

        #expect(source.contains("private var transcriptSpeakerOrder: [String]"))
        #expect(source.contains("private var activeLocalGlossaryMatchedTermIDs: Set<String>"))
        #expect(appendPreview.contains("appendTranscriptSpeakers(from:"))
        #expect(appendPreview.contains("scheduleActiveLocalGlossaryMatchCountRefresh(appendedText: text)"))
        #expect(!appendPreview.contains("transcriptSpeakerList(from: rawTranscriptPreviewLines)"))
        #expect(glossaryRefresh.contains("scanActiveLocalGlossaryMatchTermIDs"))
        #expect(source.contains("includeEvidence: false"))
        #expect(!glossaryRefresh.contains("activeLocalGlossaryMatchCount = LocalGlossaryMatcher.matches"))
    }

    @Test("test run replay throttles local fallback snapshot refresh")
    func testRunReplayThrottlesLocalFallbackSnapshotRefresh() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let applyReplayFrame = try #require(source.slice(from: "private func applyReplayFrame", to: "private func updateTestRunProgress"))
        let fallbackRefresh = try #require(source.slice(from: "private func scheduleTestRunFallbackRefreshIfNeeded", to: "private func refreshMeetingHistory"))

        #expect(source.contains("private var testRunFallbackRefreshTask: Task<Void, Never>?"))
        #expect(source.contains("private let testRunFallbackMinimumIntervalNanoseconds"))
        #expect(applyReplayFrame.contains("scheduleTestRunFallbackRefreshIfNeeded"))
        #expect(!applyReplayFrame.contains("refreshTestRunFallbackIfNeeded"))
        #expect(fallbackRefresh.contains("testRunFallbackRefreshTask"))
        #expect(fallbackRefresh.contains("refreshTestRunFallbackIfNeeded"))
    }

    @Test("automatic trigger UI and runner reuse parsed transcript stats")
    func automaticTriggerUIAndRunnerReuseParsedTranscriptStats() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let summary = try #require(source.slice(from: "var nextAutomaticAnalysisSummary", to: "var filteredMeetingHistoryItems"))
        let trigger = try #require(source.slice(from: "private func triggerAutomaticAnalysisIfNeeded", to: "private func automaticTriggerPolicyForCurrentMode"))

        #expect(source.contains("private var automaticAnalysisTranscriptStatsCache"))
        #expect(summary.contains("automaticAnalysisTranscriptStatsForCurrentState()"))
        #expect(trigger.contains("automaticAnalysisTranscriptStatsForCurrentState()"))
        #expect(summary.contains("policy.evaluate("))
        #expect(summary.contains("stats: stats"))
        #expect(trigger.contains("stats: stats"))
        #expect(!summary.contains("TranscriptParser.parse(newText)"))
        #expect(!trigger.contains("rawTranscript: rawTranscript"))
    }

    @Test("Live Watch skips history refresh when active transcript has no appended content")
    func liveWatchSkipsHistoryRefreshWhenTranscriptIsUnchanged() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let scanFolder = try #require(source.slice(from: "private func scanFolder()", to: "private func switchActiveTranscript"))
        let readAppend = try #require(source.slice(from: "private func readAppendedContent", to: "private func refreshParsedState"))

        #expect(scanFolder.contains("let didReadAppendedContent = readAppendedContent(from: latestURL)"))
        #expect(scanFolder.contains("if didReadAppendedContent {\n                refreshMeetingHistory()\n            }"))
        #expect(!scanFolder.contains("readAppendedContent(from: latestURL)\n        }\n        refreshMeetingHistory()"))
        #expect(readAppend.contains("private func readAppendedContent(from url: URL) -> Bool"))
        #expect(readAppend.contains("return true"))
        #expect(readAppend.contains("return false"))
    }

    @Test("Live Watch timer avoids no-op published updates")
    func liveWatchTimerAvoidsNoOpPublishedUpdates() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let scanFolder = try #require(source.slice(from: "private func scanFolder()", to: "private func switchActiveTranscript"))
        let missingTranscript = try #require(source.slice(from: "private func publishMissingTranscriptStateIfNeeded()", to: "private func switchActiveTranscript"))
        let skippedAttempt = try #require(source.slice(from: "private func appendSkippedAutomaticAttempt", to: "private func updateCandidate"))

        #expect(source.contains("private var liveWatchMissingTranscriptStateIsPublished = false"))
        #expect(source.contains("private var lastSkippedAutomaticAttemptSignature: String?"))
        #expect(scanFolder.contains("if liveActiveTranscriptURL != latestURL"))
        #expect(scanFolder.contains("if liveMeetingUpdated != updated"))
        #expect(scanFolder.contains("publishMissingTranscriptStateIfNeeded()"))
        #expect(missingTranscript.contains("guard !liveWatchMissingTranscriptStateIsPublished else"))
        #expect(missingTranscript.contains("publishRawTranscriptDisplayReload()"))
        #expect(skippedAttempt.contains("guard lastSkippedAutomaticAttemptSignature != signature else"))
    }

    @Test("Live Watch reloads rewritten transcript files instead of tailing shifted bytes")
    func liveWatchReloadsRewrittenTranscriptFilesInsteadOfTailingShiftedBytes() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let readAppend = try #require(source.slice(from: "private func readAppendedContent", to: "private func refreshParsedState"))

        #expect(readAppend.contains("TranscriptFileAppendPlanner.plan"))
        #expect(readAppend.contains("currentPrefixSample"))
        #expect(readAppend.contains("currentSuffixSample"))
        #expect(readAppend.contains("case .reload:"))
        #expect(readAppend.contains("readFullContent(from: url, allowFinalTrigger: true)"))
        #expect(readAppend.contains("rawTranscriptIncrementalDecoder.decode(data)"))
        #expect(readAppend.contains("rawReadAnchor.advanced(withAppendedData: data)"))
    }

    @Test("raw transcript display publishes append and reload intent separately")
    func rawTranscriptDisplayPublishesAppendAndReloadIntentSeparately() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let readFull = try #require(source.slice(from: "private func readFullContent", to: "private func readAppendedContent"))
        let readAppend = try #require(source.slice(from: "private func readAppendedContent", to: "private func refreshParsedState"))
        let applyReplayFrame = try #require(source.slice(from: "private func applyReplayFrame", to: "private func updateTestRunProgress"))

        #expect(source.contains("struct RawTranscriptDisplayUpdate"))
        #expect(source.contains("@Published private(set) var rawTranscriptDisplayUpdate"))
        #expect(readFull.contains("publishRawTranscriptDisplayReload()"))
        #expect(readAppend.contains("publishRawTranscriptDisplayAppend(appendedText)"))
        #expect(applyReplayFrame.contains("publishRawTranscriptDisplayAppend(frame.text)"))
    }

    @Test("Live Watch caches latest transcript directory scan between ticks")
    func liveWatchCachesLatestTranscriptDirectoryScanBetweenTicks() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let startWatching = try #require(source.slice(from: "func startWatching(folderURL: URL)", to: "private func ensureFolderScanTimer()"))
        let latestCandidate = try #require(source.slice(from: "private func currentLatestTranscriptCandidate", to: "private func captureHistoryLiveBaseline"))
        let captureBaseline = try #require(source.slice(from: "private func captureHistoryLiveBaseline", to: "private func scanFolder()"))

        #expect(source.contains("latestTranscriptFullScanInterval"))
        #expect(source.contains("cachedLatestTranscriptCandidate"))
        #expect(source.contains("lastLatestTranscriptScanAt"))
        #expect(startWatching.contains("cachedLatestTranscriptCandidate = nil"))
        #expect(startWatching.contains("lastLatestTranscriptScanAt = nil"))
        #expect(latestCandidate.contains("force: Bool = false"))
        #expect(latestCandidate.contains("refreshCachedLatestTranscriptCandidate()"))
        #expect(latestCandidate.contains("latestTranscriptFullScanInterval"))
        #expect(captureBaseline.contains("currentLatestTranscriptCandidate(force: true)"))
    }

    @Test("local glossary refresh scans the full selected raw transcript folder")
    func localGlossaryRefreshScansSelectedRawTranscriptFolder() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let refresh = try #require(source.slice(from: "func refreshLocalGlossarySuggestions()", to: "func acceptLocalGlossarySuggestion"))

        #expect(refresh.contains("selectedFolderURL"))
        #expect(refresh.contains("LocalGlossaryHistoryScanner.documents"))
        #expect(refresh.contains("maxDocuments: Int.max"))
        #expect(refresh.contains("rawTranscriptLineLimit: 160"))
        #expect(refresh.contains("LocalGlossaryRefreshProgress"))
        #expect(refresh.contains("LocalGlossaryProgressBox"))
        #expect(refresh.contains("logLocalGlossaryRefreshStage"))
        #expect(refresh.contains("appendLocalGlossaryRefreshDiagnostic"))
        #expect(refresh.contains("LocalGlossaryRefreshDiagnostic"))
        #expect(refresh.contains("progress: { progress in"))
        #expect(refresh.contains("suggestionsAndReviewCandidatesWithDiagnostics"))
        #expect(refresh.contains("replaceSuggestions(strict: suggestions, review: reviewCandidates)"))
        #expect(refresh.contains("reviewCandidates=\\(reviewCandidates.count)"))
        #expect(!refresh.contains("meetingHistoryItems.map"))
    }

    @Test("history and search index glossary work uses term signature and prepared matcher")
    func historyAndSearchIndexGlossaryWorkUsesTermSignatureAndPreparedMatcher() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let builder = try #require(source.slice(from: "private struct MeetingHistoryBuilder", to: "@MainActor\nfinal class AppViewModel"))
        let glossarySections = try #require(source.slice(from: "private func localGlossarySearchSections", to: "private extension String"))
        let historyRefresh = try #require(source.slice(from: "private func refreshMeetingHistory", to: "private func activeSearchIndexExclusionURL"))
        let searchIndexBuild = try #require(source.slice(from: "private func startSearchIndexBuildIfNeeded", to: "private func isTranscriptOpenForSearchIndex"))
        let searchDatabaseRefresh = try #require(source.slice(from: "private func refreshSearchDatabaseMatches", to: "func openHistorySearchResult"))

        #expect(builder.contains("localGlossaryHistorySignature"))
        #expect(!builder.contains("localGlossaryState.updatedAt"))
        #expect(builder.contains("buildIfChanged"))
        #expect(historyRefresh.contains("previousHistorySignature"))
        #expect(builder.contains("includeLocalGlossarySearchSections"))
        #expect(builder.contains("LocalGlossaryMatcher.PreparedState"))
        #expect(builder.contains("private let historySearchTokenization: MeetingHistorySearchTokenization = .fast"))
        #expect(builder.contains("tokenization: historySearchTokenization"))
        #expect(builder.contains("MeetingHistorySearchSection.perspectiveAlignment(alignment, tokenization: historySearchTokenization)"))
        #expect(glossarySections.contains("preparedState:"))
        #expect(glossarySections.contains("includeEvidence: false"))
        #expect(!glossarySections.contains("sourceText"))
        #expect(searchIndexBuild.contains("includeLocalGlossarySearchSections: false"))
        #expect(searchDatabaseRefresh.contains("localGlossarySearchQueries(for: trimmed)"))
    }

    @Test("history builder bounds eager metadata preview during idle refresh")
    func historyBuilderBoundsEagerMetadataPreviewDuringIdleRefresh() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let builder = try #require(source.slice(from: "private struct MeetingHistoryBuilder", to: "@MainActor\nfinal class AppViewModel"))

        #expect(builder.contains("eagerMetadataPreviewLimit"))
        #expect(builder.contains(".enumerated()"))
        #expect(builder.contains("sortedIndex: offset"))
        #expect(builder.contains("stateStore.hasAnalysisState(for: candidate.url)"))
        #expect(builder.contains("stateStore.hasSession(for: candidate.url)"))
        #expect(builder.contains("shouldLoadMetadataPreview(sortedIndex: sortedIndex, analysis: analysis)"))
        #expect(builder.contains("sortedIndex < eagerMetadataPreviewLimit"))
        #expect(builder.contains("includeRawTranscriptSearch"))
        #expect(builder.contains("TranscriptParser.parseMetadataPreview(text)"))
        #expect(!builder.contains("TranscriptParser.parse(text).metadata"))
    }

    @Test("search index rebuild is deferred until history search needs it")
    func searchIndexRebuildIsDeferredUntilHistorySearchNeedsIt() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let searchDatabaseRefresh = try #require(source.slice(from: "private func refreshSearchDatabaseMatches", to: "func openHistorySearchResult"))
        let searchIndexBuild = try #require(source.slice(from: "private func startSearchIndexBuildIfNeeded", to: "private func isTranscriptOpenForSearchIndex"))

        #expect(source.contains("private struct SearchIndexBuildRequest"))
        #expect(source.contains("private var pendingSearchIndexBuildRequest: SearchIndexBuildRequest?"))
        #expect(searchIndexBuild.contains("pendingSearchIndexBuildRequest = SearchIndexBuildRequest("))
        #expect(searchIndexBuild.contains("debouncedHistorySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"))
        #expect(searchDatabaseRefresh.contains("let pendingSearchIndexBuildRequest = pendingSearchIndexBuildRequest"))
        #expect(searchDatabaseRefresh.contains("startSearchIndexBuildIfNeeded("))
    }

    @Test("database ready search does not fuzzy scan every history item")
    func databaseReadySearchDoesNotFuzzyScanEveryHistoryItem() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let searchResultsBuilder = try #require(source.slice(from: "private func buildMeetingHistorySearchResults", to: "private func sortMeetingHistorySearchResults"))
        let searchDatabaseRefresh = try #require(source.slice(from: "private func refreshSearchDatabaseMatches", to: "func openHistorySearchResult"))

        #expect(searchResultsBuilder.contains("inMemoryFallbackItemIDs"))
        #expect(searchResultsBuilder.contains("guard inMemoryFallbackItemIDs?.contains(item.id) ?? true else"))
        #expect(searchDatabaseRefresh.contains("let inMemoryFallbackItemIDs: Set<String>? = databaseIsReady ? [] : nil"))
        #expect(searchDatabaseRefresh.contains("inMemoryFallbackItemIDs: inMemoryFallbackItemIDs"))
    }

    @Test("live metadata refresh avoids full transcript dialogue parsing")
    func liveMetadataRefreshAvoidsFullTranscriptDialogueParsing() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let refreshParsedState = try #require(source.slice(from: "private func refreshParsedState", to: "private func autoFetchGoogleCalendarAPIContextForLiveWatchIfNeeded"))

        #expect(refreshParsedState.contains("TranscriptParser.parseMetadataPreview(rawTranscript)"))
        #expect(!refreshParsedState.contains("TranscriptParser.parse(rawTranscript).metadata"))
    }

    @Test("AppViewModel exposes review candidate actions")
    func appViewModelExposesReviewCandidateActions() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/AppViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("func acceptLocalGlossaryReviewCandidateAsNewTerm"))
        #expect(source.contains("func addLocalGlossaryReviewCandidate"))
        #expect(source.contains("func markLocalGlossaryReviewCandidateAsNotSame"))
        #expect(source.contains("func dismissLocalGlossaryReviewCandidate"))
    }

    @Test("view model adds selected raw transcript text as a manual glossary term")
    @MainActor
    func viewModelAddsSelectedTranscriptTextAsManualGlossaryTerm() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-manual-glossary-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
        let viewModel = AppViewModel(stateStore: stateStore)

        viewModel.rawTranscript = "Ethan: 워크 플로 쪽을 다시 보겠습니다."
        viewModel.addManualLocalGlossaryTerm(
            selectedText: "워크 플로",
            canonical: "워크플로우",
            category: .domainTerm
        )

        let term = try #require(viewModel.localGlossaryState.terms.first)
        #expect(term.canonical == "워크플로우")
        #expect(term.aliases.contains("워크 플로"))
        #expect(term.source == .manualSelection)
        #expect(viewModel.localGlossaryStatusMessage.contains("Raw Transcript"))
    }

    @Test("view model adds selected raw transcript text as alias to existing term")
    @MainActor
    func viewModelAddsSelectedTranscriptTextAsAlias() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-manual-glossary-alias-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let stateStore = ApplicationStateStore(rootURL: rootURL.appendingPathComponent("state", isDirectory: true))
        let viewModel = AppViewModel(stateStore: stateStore)

        viewModel.localGlossaryState = LocalGlossaryState(terms: [
            LocalGlossaryTerm(
                id: "term-ios",
                canonical: "iOS",
                aliases: ["아이오에스"],
                category: .acronym
            )
        ])
        viewModel.addManualLocalGlossaryAlias(selectedText: "아이유에스", toTermID: "term-ios")

        let term = try #require(viewModel.localGlossaryState.terms.first)
        #expect(term.aliases.contains("아이유에스"))
        #expect(viewModel.localGlossaryStatusMessage.contains("alias"))
    }
}

private extension String {
    func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker),
              let end = range(of: endMarker, range: start.upperBound..<endIndex) else {
            return nil
        }
        return String(self[start.lowerBound..<end.lowerBound])
    }
}
