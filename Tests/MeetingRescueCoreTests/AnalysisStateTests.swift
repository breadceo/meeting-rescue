import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Analysis state")
struct AnalysisStateTests {
    @Test("D0 snapshot은 meeting type과 evidence-backed summary를 decode한다")
    func decodesD0SnapshotContract() throws {
        let json = """
        {
          "meetingType": "decision",
          "meetingSummary": {
            "overview": "배포 방식과 책임자를 좁힌 회의다.",
            "keyPoints": [
              {
                "id": "summary-1",
                "text": "금요일 배포를 기준으로 준비한다.",
                "evidence": [
                  {
                    "timestamp": "00:10",
                    "speaker": "Alex",
                    "excerpt": "금요일 배포로 가죠."
                  }
                ]
              }
            ],
            "openQuestions": [
              {
                "id": "question-1",
                "text": "롤백 담당자를 확정해야 한다.",
                "evidence": [
                  {
                    "timestamp": "00:30",
                    "speaker": "Blair",
                    "excerpt": "롤백 담당자는 아직 없나요?"
                  }
                ]
              }
            ]
          },
          "currentIssue": {
            "summary": "롤백 담당자 확정이 남아 있다.",
            "openQuestions": ["롤백 담당자는 누구인가?"]
          },
          "topicTimeline": [],
          "decisionCandidates": [],
          "actionItemCandidates": [],
          "risksOrNotes": []
        }
        """

        let snapshot = try JSONDecoder().decode(AnalysisSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.meetingType == .decision)
        #expect(snapshot.meetingSummary.overview == "배포 방식과 책임자를 좁힌 회의다.")
        #expect(snapshot.meetingSummary.keyPoints.first?.evidence.first?.timestamp == "00:10")
        #expect(snapshot.meetingSummary.openQuestions.first?.text == "롤백 담당자를 확정해야 한다.")
    }

    @Test("legacy snapshot은 D0 필드 없이도 기본값으로 decode한다")
    func decodesLegacySnapshotWithoutD0Fields() throws {
        let json = """
        {
          "currentIssue": {
            "summary": "기존 요약",
            "openQuestions": []
          },
          "topicTimeline": [],
          "decisionCandidates": [],
          "actionItemCandidates": [],
          "risksOrNotes": []
        }
        """

        let snapshot = try JSONDecoder().decode(AnalysisSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.meetingType == .automatic)
        #expect(snapshot.meetingSummary.isEmpty)
    }

    @Test("partial meeting summary JSON preserves available summary text")
    func decodesPartialMeetingSummaryWithDefaults() throws {
        let json = """
        {
          "meetingType": "planning",
          "meetingSummary": {
            "overview": "계획을 정리했다.",
            "keyPoints": [
              {
                "id": "summary-1",
                "text": "마일스톤을 다음 주로 잡았다."
              }
            ]
          },
          "currentIssue": {
            "summary": "다음 주 마일스톤",
            "openQuestions": []
          },
          "topicTimeline": [],
          "decisionCandidates": [],
          "actionItemCandidates": [],
          "risksOrNotes": []
        }
        """

        let snapshot = try JSONDecoder().decode(AnalysisSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.meetingSummary.overview == "계획을 정리했다.")
        #expect(snapshot.meetingSummary.keyPoints.first?.text == "마일스톤을 다음 주로 잡았다.")
        #expect(snapshot.meetingSummary.keyPoints.first?.evidence.isEmpty == true)
        #expect(snapshot.meetingSummary.openQuestions.isEmpty)
    }

    @Test("AppSettings stores meeting type preset with automatic legacy default")
    func appSettingsStoresMeetingTypePreset() throws {
        let legacyJSON = #"{"selectedProvider":"codexExec"}"#
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))
        #expect(legacy.meetingTypePreset == .automatic)

        let settings = AppSettings(meetingTypePreset: .incident)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.meetingTypePreset == .incident)
    }

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
            meetingType: .automatic,
            meetingSummary: MeetingSummary(overview: "이전 요약"),
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
            meetingType: .planning,
            meetingSummary: MeetingSummary(
                overview: "새 계획 요약",
                keyPoints: [
                    MeetingSummaryItem(
                        id: "summary-plan",
                        text: "마일스톤을 다음 주로 맞춘다.",
                        evidence: [
                            EvidenceReference(
                                timestamp: "02:10",
                                speaker: "Casey",
                                excerpt: "다음 주 마일스톤으로 맞추겠습니다."
                            )
                        ]
                    )
                ]
            ),
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

        #expect(merged.meetingType == .planning)
        #expect(merged.meetingSummary.overview == "새 계획 요약")
        #expect(merged.meetingSummary.keyPoints.first?.text == "마일스톤을 다음 주로 맞춘다.")
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

    @Test("meeting bookmarks를 저장하고 다시 불러온다")
    func persistsMeetingBookmarks() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRescueBookmarks-\(UUID().uuidString)", isDirectory: true)
        let store = ApplicationStateStore(rootURL: rootURL)
        let transcriptURL = rootURL.appendingPathComponent("meeting.txt")
        var state = MeetingAnalysisState()
        state.addBookmark(
            MeetingBookmark(
                id: "bookmark-1",
                timestamp: "[04:13]",
                label: "결정 기준",
                createdAt: Date(timeIntervalSince1970: 100),
                excerpt: "결정 기준은 비용과 속도입니다."
            )
        )

        try store.saveAnalysisState(state, for: transcriptURL)
        let loaded = store.loadAnalysisState(for: transcriptURL)

        #expect(loaded.bookmarks.map(\.id) == ["bookmark-1"])
        #expect(loaded.bookmarks.first?.timestamp == "[04:13]")
        #expect(loaded.bookmarks.first?.label == "결정 기준")

        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test("final analysis는 previous snapshot이 있어도 full snapshot output을 쓴다")
    func finalAnalysisUsesFullSnapshotOutput() {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:10] Alex: 정리합니다.",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "final",
            lastAnalyzedTranscriptCharacterCount: 8
        )

        #expect(request.outputMode == .fullSnapshot)
        #expect(AnalysisRequest.usesFullSnapshotOutput("final"))
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
