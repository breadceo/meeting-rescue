import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Analysis state")
struct AnalysisStateTests {
    @Test("candidate id는 normalized text와 evidence timestamp 기준으로 stable하다")
    func stableCandidateIDs() {
        let first = CandidateIDGenerator.decisionID(text: "  배포를   금요일에 진행한다 ", evidenceTimestamp: "12:30")
        let second = CandidateIDGenerator.decisionID(text: "배포를 금요일에 진행한다", evidenceTimestamp: "12:30")
        let differentTimestamp = CandidateIDGenerator.decisionID(text: "배포를 금요일에 진행한다", evidenceTimestamp: "12:31")

        #expect(first == second)
        #expect(first != differentTimestamp)
    }

    @Test("confirmed/deleted candidate ids를 저장하고 다시 불러온다")
    func persistsCandidateState() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRescueTests-\(UUID().uuidString)", isDirectory: true)
        let store = ApplicationStateStore(rootURL: rootURL)
        let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
        let state = MeetingAnalysisState(
            latestSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "요약")),
            confirmedCandidateIDs: ["decision-1"],
            deletedCandidateIDs: ["action-1"],
            analyzedTranscriptCharacterCount: 1234
        )

        try store.saveAnalysisState(state, for: transcriptURL)
        let loaded = store.loadAnalysisState(for: transcriptURL)

        #expect(loaded.latestSnapshot?.currentIssue.summary == "요약")
        #expect(loaded.confirmedCandidateIDs == ["decision-1"])
        #expect(loaded.deletedCandidateIDs == ["action-1"])
        #expect(loaded.analyzedTranscriptCharacterCount == 1234)

        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test("confirmed/deleted state가 refresh snapshot에 유지된다")
    func reappliesCandidateStateToSnapshot() {
        let decision = DecisionCandidate(id: "decision-1", text: "결정", evidenceTimestamp: "00:10")
        let action = ActionItemCandidate(id: "action-1", task: "할 일", evidenceTimestamp: "00:20")
        let snapshot = AnalysisSnapshot(decisionCandidates: [decision], actionItemCandidates: [action])
        let state = MeetingAnalysisState(
            confirmedCandidateIDs: ["decision-1"],
            deletedCandidateIDs: ["action-1"]
        )

        let applied = state.applyingCandidateState(to: snapshot)

        #expect(applied.decisionCandidates.first?.status == .confirmed)
        #expect(applied.actionItemCandidates.first?.status == .deleted)
    }

    @Test("live patch는 기존 snapshot에 변경분만 merge한다")
    func livePatchMergesIntoExistingSnapshot() {
        let previous = AnalysisSnapshot(
            currentIssue: CurrentIssue(summary: "이전 이슈"),
            topicTimeline: [
                TopicTimelineItem(id: "topic-1", startTimestamp: "00:10", title: "기존 주제", summary: "기존 요약")
            ],
            decisionCandidates: [
                DecisionCandidate(id: "decision-1", text: "기존 결정", evidenceTimestamp: "00:20")
            ],
            risksOrNotes: ["기존 note"]
        )
        let patch = AnalysisSnapshotPatch(
            currentIssue: CurrentIssue(summary: "새 이슈"),
            topicTimelineUpserts: [
                TopicTimelineItem(id: "topic-1", startTimestamp: "00:10", endTimestamp: "01:00", title: "기존 주제", summary: "닫힌 요약"),
                TopicTimelineItem(id: "topic-2", startTimestamp: "01:01", title: "새 주제", summary: "새 요약")
            ],
            decisionCandidateUpserts: [
                DecisionCandidate(id: "decision-2", text: "새 결정", evidenceTimestamp: "01:05")
            ],
            actionItemCandidateUpserts: [
                ActionItemCandidate(id: "action-1", assignee: "Alex", task: "후속 확인", evidenceTimestamp: "01:10")
            ],
            risksOrNotesAppend: ["기존 note", "새 note"]
        )

        let merged = previous.applyingPatch(patch, provider: .customCommand)

        #expect(merged.currentIssue.summary == "새 이슈")
        #expect(merged.topicTimeline.map(\.id) == ["topic-1", "topic-2"])
        #expect(merged.topicTimeline.first?.endTimestamp == "01:00")
        #expect(merged.decisionCandidates.map(\.id) == ["decision-1", "decision-2"])
        #expect(merged.actionItemCandidates.map(\.id) == ["action-1"])
        #expect(merged.risksOrNotes == ["기존 note", "새 note"])
        #expect(merged.provider == .customCommand)
    }

    @Test("ISO처럼 들어온 transcript elapsed timestamp도 timeline 정렬에 사용한다")
    func livePatchSortsISOLikeElapsedTimestamps() {
        let previous = AnalysisSnapshot()
        let patch = AnalysisSnapshotPatch(
            topicTimelineUpserts: [
                TopicTimelineItem(id: "topic-3", startTimestamp: "2026-05-19T03:57:00Z", title: "세 번째", summary: "요약"),
                TopicTimelineItem(id: "topic-1", startTimestamp: "2026-05-19T00:05:00Z", title: "첫 번째", summary: "요약"),
                TopicTimelineItem(id: "topic-2", startTimestamp: "2026-05-19T01:25:00Z", title: "두 번째", summary: "요약")
            ]
        )

        let merged = previous.applyingPatch(patch, provider: .codexExec)

        #expect(merged.topicTimeline.map(\.id) == ["topic-1", "topic-2", "topic-3"])
    }

    @Test("candidate status는 confirm/delete 이후 다시 candidate로 되돌릴 수 있다")
    func candidateStatusCanBeReverted() {
        var state = MeetingAnalysisState()

        state.setCandidateStatus(id: "decision-1", status: .confirmed)
        #expect(state.confirmedCandidateIDs == ["decision-1"])
        #expect(state.deletedCandidateIDs.isEmpty)

        state.setCandidateStatus(id: "decision-1", status: .candidate)
        #expect(state.confirmedCandidateIDs.isEmpty)
        #expect(state.deletedCandidateIDs.isEmpty)

        state.setCandidateStatus(id: "decision-1", status: .deleted)
        #expect(state.confirmedCandidateIDs.isEmpty)
        #expect(state.deletedCandidateIDs == ["decision-1"])
    }

    @Test("reload 시 이전 running attempt를 skipped 처리할 수 있다")
    func marksInterruptedRunningAttemptsSkipped() {
        let completedAt = Date(timeIntervalSince1970: 100)
        let running = AnalysisAttemptLog(
            reason: "automatic",
            status: .running,
            provider: .codexExec,
            modelPreset: .economy,
            modelName: "test",
            inputTokens: 10
        )
        let succeeded = AnalysisAttemptLog(
            reason: "automatic",
            status: .succeeded,
            provider: .codexExec,
            modelPreset: .economy,
            modelName: "test",
            completedAt: completedAt,
            inputTokens: 5,
            outputTokens: 3
        )
        var state = MeetingAnalysisState(attemptLogs: [running, succeeded])

        let changed = state.markInterruptedRunningAttemptsSkipped(
            message: "interrupted",
            completedAt: completedAt
        )

        #expect(changed)
        #expect(state.attemptLogs[0].status == .skipped)
        #expect(state.attemptLogs[0].completedAt == completedAt)
        #expect(state.attemptLogs[0].message == "interrupted")
        #expect(state.attemptLogs[1].status == .succeeded)
    }

    @Test("attempt log는 provider 응답 duration을 저장한다")
    func attemptLogStoresDurationMilliseconds() throws {
        let attempt = AnalysisAttemptLog(
            reason: "automatic",
            status: .succeeded,
            provider: .codexExec,
            modelPreset: .economy,
            modelName: "test",
            durationMilliseconds: 1234
        )

        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(AnalysisAttemptLog.self, from: data)

        #expect(decoded.durationMilliseconds == 1234)
        #expect(decoded.elapsedMilliseconds == 1234)
    }

    @Test("attempt log는 transcript batch stats를 저장한다")
    func attemptLogStoresBatchStats() throws {
        let stats = AnalysisAttemptBatchStats(
            triggerReason: "cadence 45초",
            newTranscriptCharacters: 900,
            includedTranscriptCharacters: 700,
            newDialogueLines: 12,
            includedDialogueLines: 9,
            lastAnalyzedTranscriptCharacterCount: 100,
            targetTranscriptCharacterCount: 800,
            sourceTranscriptCharacterCount: 1000,
            skippedReason: "system-only"
        )
        let attempt = AnalysisAttemptLog(
            reason: "automatic",
            status: .skipped,
            provider: .codexExec,
            modelPreset: .economy,
            modelName: "test",
            batchStats: stats
        )

        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(AnalysisAttemptLog.self, from: data)

        #expect(decoded.batchStats == stats)
        #expect(decoded.batchStats?.compactSummary.contains("새 12줄/900자") == true)
        #expect(decoded.batchStats?.compactSummary.contains("skip system-only") == true)
    }

    @Test("attempt log는 run trace를 저장한다")
    func attemptLogStoresRunTrace() throws {
        let trace = AnalysisRunTrace(
            providerExecutable: "/usr/bin/env",
            argumentsSummary: "codex exec -",
            workingDirectory: "/tmp",
            inputBytes: 128,
            outputBytes: 64,
            stderrBytes: 8,
            exitCode: 0,
            timedOut: false,
            startedAtUnixMilliseconds: 1_000,
            events: [
                AnalysisRunTraceEvent(
                    name: "wait for process",
                    startedAtMilliseconds: 10,
                    durationMilliseconds: 320,
                    detail: "exit 0"
                )
            ]
        )
        let attempt = AnalysisAttemptLog(
            reason: "automatic",
            status: .succeeded,
            provider: .codexExec,
            modelPreset: .economy,
            modelName: "test",
            runTrace: trace
        )

        let data = try JSONEncoder().encode(attempt)
        let decoded = try JSONDecoder().decode(AnalysisAttemptLog.self, from: data)

        #expect(decoded.runTrace == trace)
        #expect(decoded.runTrace?.events.first?.name == "wait for process")
    }

    @Test("기존 attempt log JSON은 batch stats 없이도 decode된다")
    func decodesExistingAttemptWithoutBatchStats() throws {
        let json = """
        {
          "id": "attempt-1",
          "reason": "automatic",
          "status": "succeeded",
          "provider": "codexExec",
          "modelPreset": "economy",
          "modelName": "test",
          "startedAt": 100,
          "inputTokens": 10,
          "outputTokens": 3
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let decoded = try decoder.decode(AnalysisAttemptLog.self, from: Data(json.utf8))

        #expect(decoded.id == "attempt-1")
        #expect(decoded.batchStats == nil)
    }

    @Test("attempt log는 기존 completedAt 로그에서도 duration을 계산한다")
    func attemptLogComputesDurationForExistingAttempts() {
        let attempt = AnalysisAttemptLog(
            reason: "automatic",
            status: .succeeded,
            provider: .codexExec,
            modelPreset: .economy,
            modelName: "test",
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 12.25)
        )

        #expect(attempt.elapsedMilliseconds == 2250)
    }

    @Test("confirmed 후보 수정본은 저장되고 refresh snapshot에도 유지된다")
    func candidateEditsSurviveSnapshotRefresh() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRescueTests-\(UUID().uuidString)", isDirectory: true)
        let store = ApplicationStateStore(rootURL: rootURL)
        let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
        let decision = DecisionCandidate(id: "decision-1", text: "원문 결정", evidenceTimestamp: "00:10")
        let action = ActionItemCandidate(id: "action-1", assignee: "A", task: "원문 액션", deadline: "금요일", evidenceTimestamp: "00:20")

        var state = MeetingAnalysisState(
            latestSnapshot: AnalysisSnapshot(decisionCandidates: [decision], actionItemCandidates: [action])
        )
        state.editDecisionCandidate(id: "decision-1", text: "수정된 결정")
        state.editActionItemCandidate(id: "action-1", assignee: "B", task: "수정된 액션", deadline: "월요일")

        #expect(state.latestSnapshot?.decisionCandidates.first?.text == "수정된 결정")
        #expect(state.latestSnapshot?.decisionCandidates.first?.status == .confirmed)
        #expect(state.latestSnapshot?.actionItemCandidates.first?.assignee == "B")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.task == "수정된 액션")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.deadline == "월요일")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.status == .confirmed)

        let refreshed = AnalysisSnapshot(decisionCandidates: [decision], actionItemCandidates: [action])
        let applied = state.applyingCandidateState(to: refreshed)

        #expect(applied.decisionCandidates.first?.text == "수정된 결정")
        #expect(applied.actionItemCandidates.first?.task == "수정된 액션")

        try store.saveAnalysisState(state, for: transcriptURL)
        let loaded = store.loadAnalysisState(for: transcriptURL)
        let loadedApplied = loaded.applyingCandidateState(to: refreshed)

        #expect(loaded.decisionCandidateEdits["decision-1"]?.text == "수정된 결정")
        #expect(loaded.actionItemCandidateEdits["action-1"]?.task == "수정된 액션")
        #expect(loadedApplied.decisionCandidates.first?.text == "수정된 결정")
        #expect(loadedApplied.actionItemCandidates.first?.assignee == "B")

        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test("수정된 후보는 원문으로 복원할 수 있다")
    func candidateEditsCanBeRestored() {
        let decision = DecisionCandidate(id: "decision-1", text: "원문 결정", evidenceTimestamp: "00:10")
        let action = ActionItemCandidate(id: "action-1", assignee: "A", task: "원문 액션", deadline: "금요일", evidenceTimestamp: "00:20")
        var state = MeetingAnalysisState(
            latestSnapshot: AnalysisSnapshot(decisionCandidates: [decision], actionItemCandidates: [action])
        )

        state.editDecisionCandidate(id: "decision-1", text: "수정된 결정")
        state.editActionItemCandidate(id: "action-1", assignee: nil, task: "수정된 액션", deadline: nil)
        state.restoreOriginalDecisionCandidate(id: "decision-1")
        state.restoreOriginalActionItemCandidate(id: "action-1")

        #expect(state.decisionCandidateEdits.isEmpty)
        #expect(state.actionItemCandidateEdits.isEmpty)
        #expect(state.latestSnapshot?.decisionCandidates.first?.text == "원문 결정")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.assignee == "A")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.task == "원문 액션")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.deadline == "금요일")
        #expect(state.latestSnapshot?.decisionCandidates.first?.status == .confirmed)
        #expect(state.latestSnapshot?.actionItemCandidates.first?.status == .confirmed)
    }

    @Test("수정된 후보를 confirm 취소하면 수정본을 제거하고 원문 후보로 돌아간다")
    func unconfirmEditedCandidateRestoresOriginal() {
        let decision = DecisionCandidate(id: "decision-1", text: "원문 결정", evidenceTimestamp: "00:10")
        let action = ActionItemCandidate(id: "action-1", assignee: "A", task: "원문 액션", deadline: "금요일", evidenceTimestamp: "00:20")
        var state = MeetingAnalysisState(
            latestSnapshot: AnalysisSnapshot(decisionCandidates: [decision], actionItemCandidates: [action])
        )

        state.editDecisionCandidate(id: "decision-1", text: "수정된 결정")
        state.editActionItemCandidate(id: "action-1", assignee: "B", task: "수정된 액션", deadline: "월요일")
        state.setCandidateStatus(id: "decision-1", status: .candidate)
        state.setCandidateStatus(id: "action-1", status: .candidate)
        if let snapshot = state.latestSnapshot {
            state.latestSnapshot = state.applyingCandidateState(to: snapshot)
        }

        #expect(state.confirmedCandidateIDs.isEmpty)
        #expect(state.decisionCandidateEdits.isEmpty)
        #expect(state.actionItemCandidateEdits.isEmpty)
        #expect(state.latestSnapshot?.decisionCandidates.first?.text == "원문 결정")
        #expect(state.latestSnapshot?.decisionCandidates.first?.status == .candidate)
        #expect(state.latestSnapshot?.actionItemCandidates.first?.assignee == "A")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.task == "원문 액션")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.deadline == "금요일")
        #expect(state.latestSnapshot?.actionItemCandidates.first?.status == .candidate)
    }
}
