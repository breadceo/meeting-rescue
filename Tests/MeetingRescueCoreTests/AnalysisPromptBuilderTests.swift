import Testing
@testable import MeetingRescueCore

@Suite("Analysis prompt builder")
struct AnalysisPromptBuilderTests {
    @Test("성공적으로 분석한 위치 이후 새 transcript chunk를 primary input으로 보낸다")
    func usesIncrementalTranscriptChunk() throws {
        let previousTranscript = "OLD_PREFIX_SENTINEL\n" + String(repeating: "[00:01] Alex: 오래된 내용\n", count: 400)
        let newTranscript = "\n[20:00] Alex: NEW_CHUNK_LINE"
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: previousTranscript + newTranscript,
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "이전 요약")),
            lastAnalyzedTranscriptCharacterCount: previousTranscript.count
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains(#""mode":"incremental""#))
        #expect(prompt.contains("NEW_CHUNK_LINE"))
        #expect(prompt.contains("recentTranscriptContext"))
        #expect(!prompt.contains("OLD_PREFIX_SENTINEL"))
        #expect(!prompt.contains("\n  \"mode\""))
    }

    @Test("automatic refresh with previous snapshot asks for live patch output")
    func automaticRefreshUsesPatchPrompt() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:01] Alex: 이전 내용\n[00:20] Alex: 새 결정 후보",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "이전 요약")),
            reason: "automatic",
            lastAnalyzedTranscriptCharacterCount: 17
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(request.outputMode == .livePatch)
        #expect(prompt.contains("JSON patch 객체"))
        #expect(prompt.contains("topicTimelineUpserts"))
        #expect(prompt.contains("전체 AnalysisSnapshot을 쓰지 마세요"))
    }

    @Test("automatic retry also uses live patch output when previous snapshot exists")
    func automaticRetryUsesPatchPrompt() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:01] Alex: 이전 내용\n[01:20] Alex: 새 결정 후보",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "이전 요약")),
            reason: "automatic-retry",
            lastAnalyzedTranscriptCharacterCount: 0
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(request.outputMode == .livePatch)
        #expect(prompt.contains("JSON patch 객체"))
        #expect(prompt.contains(#""mode":"initial_live_patch""#))
        #expect(prompt.contains("newTranscriptChunk"))
        #expect(!prompt.contains("\"fullTranscript\""))
    }

    @Test("final analysis with previous snapshot also asks for patch output")
    func finalAnalysisUsesPatchPromptWhenSnapshotExists() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[10:00] Alex: 기존 내용\n[20:00] Alex: 후반부 결정 후보",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "final",
            lastAnalyzedTranscriptCharacterCount: 18
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(request.outputMode == .livePatch)
        #expect(prompt.contains("final catch-up"))
        #expect(prompt.contains("전체 AnalysisSnapshot을 쓰지 마세요"))
        #expect(prompt.contains("후반부 결정 후보"))
    }

    @Test("previous snapshot은 최근 topic과 후보 중심으로 compact 한다")
    func compactsPreviousSnapshot() throws {
        let topics = (1...20).map { index in
            TopicTimelineItem(
                id: "topic-\(index)",
                startTimestamp: "[00:\(index)]",
                title: "topic-\(index)-title",
                summary: "summary-\(index)"
            )
        }
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:01] Alex: 새 내용",
            previousSnapshot: AnalysisSnapshot(topicTimeline: topics),
            lastAnalyzedTranscriptCharacterCount: 1
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("topic-20-title"))
        #expect(!prompt.contains("topic-16-title"))
        #expect(!prompt.contains("topic-1-title"))
    }

    @Test("prompt는 live topic breakdown 기준을 명시한다")
    func promptIncludesTopicBreakdownGuidance() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:01] Morgan: 2026년 전략을 공유하겠습니다."
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("agenda/논점/대상/실행 방향이 바뀌면 나누세요"))
        #expect(prompt.contains("전체 6개 이하"))
        #expect(prompt.contains("currentIssue.summary는 2-4문장"))
        #expect(prompt.contains("decision/action 후보는 각각 6개 이하"))
    }

    @Test("prompt metadata participants는 실제 발화자 중심으로 줄인다")
    func promptMetadataKeepsOnlySpeakingParticipants() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(
                room: "Room",
                dateTime: "2026-05-18 10:00",
                participants: [
                    "Morgan Lee(morgan@example.com)",
                    "Taylor Chen(taylor@example.com)",
                    "Observer(observer@example.com)"
                ]
            ),
            rawTranscript: """
            Room
            2026-05-18 10:00
            Morgan Lee(morgan@example.com), Taylor Chen(taylor@example.com), Observer(observer@example.com)
            ############################################################
            [00:00][SYSTEM] 대화 기록 시작됨
            [00:03][SYSTEM] Observer(observer@example.com)이 그룹에 입장했습니다.
            [00:10] Morgan Lee: 오늘 운영 자료를 보겠습니다.
            [00:20] Taylor Chen: 이어서 정리하겠습니다.
            """
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("Morgan Lee(morgan@example.com)"))
        #expect(prompt.contains("Taylor Chen(taylor@example.com)"))
        #expect(!prompt.contains("Observer(observer@example.com)"))
        #expect(!prompt.contains("그룹에 입장했습니다"))
        #expect(!prompt.contains("############################################################"))
    }

    @Test("retrieved chunk text는 prompt에서 짧게 제한된다")
    func capsRetrievedChunkText() throws {
        let longChunk = String(repeating: "[00:01] Alex: 오래된 지도 논의입니다.\n", count: 80)
        let plan = AnalysisContextPlan(
            retrievalMode: .memoryLiveIndex,
            retrievalTopK: 1,
            retrievedChunks: [
                RetrievedTranscriptChunk(id: "chunk-1", timeRange: "[00:01]-[03:00]", text: longChunk, score: 0.8)
            ]
        )
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room", participants: ["Alex"]),
            rawTranscript: "[10:00] Alex: 지도 논의를 다시 확인합니다.",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "이전 요약")),
            lastAnalyzedTranscriptCharacterCount: 1,
            contextPlan: plan
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("앞부분은 길이 제한으로 생략됨"))
        #expect(prompt.count < longChunk.count + 2_700)
    }
}
