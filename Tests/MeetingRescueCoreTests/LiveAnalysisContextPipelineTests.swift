import Testing
@testable import MeetingRescueCore

@Suite("Live analysis context pipeline")
struct LiveAnalysisContextPipelineTests {
    @Test("live memory index retrieves related previous chunks with topK limit")
    func liveIndexRetrievesRelatedChunks() {
        var index = LiveTranscriptIndex(
            configuration: .init(maxDialogueLinesPerSegment: 2, scoreThreshold: 0.05)
        )
        index.append("""
        [00:10] Alex: 지도 핀 확대와 매물 카드 노출 방식을 논의합니다.
        [00:20] Blair: 매물 카드에서 광고 상품 노출 우려가 있습니다.
        [05:10] Casey: 결제 화면 색상은 다음 주에 보겠습니다.
        [05:30] Dana: 결제 CTA 문구도 정리하겠습니다.
        """)

        let chunks = index.retrieve(
            queryText: "[12:00] Alex: 지도 핀과 광고 노출 이슈를 다시 확인합니다.",
            excludingText: "[12:00] Alex: 지도 핀과 광고 노출 이슈를 다시 확인합니다.",
            topK: 1
        )

        #expect(chunks.count == 1)
        #expect(chunks[0].text.contains("지도 핀"))
        #expect(chunks[0].text.contains("광고 상품"))
    }

    @Test("context planner keeps retrieval off compatible with existing prompt path")
    func retrievalOffProducesNoChunks() throws {
        var index = LiveTranscriptIndex()
        index.append("[00:10] Alex: 오래된 지도 핀 논의입니다.")
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room", participants: ["Alex", "Observer"]),
            rawTranscript: "[00:10] Alex: 오래된 지도 핀 논의입니다.\n[02:00] Alex: 새 지도 논의입니다.",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "지도 논의")),
            modelPreset: .balanced,
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 25
        )

        let plan = AnalysisContextPlanner.makePlan(
            for: request,
            retrievalMode: .off,
            liveIndex: index
        )
        var requestWithPlan = request
        requestWithPlan.contextPlan = plan
        let prompt = try AnalysisPromptBuilder.buildPrompt(for: requestWithPlan)

        #expect(plan.retrievedChunks.isEmpty)
        #expect(prompt.contains("\"retrievalMode\" : \"off\""))
        #expect(prompt.contains("relatedTranscriptChunks"))
    }

    @Test("context planner includes memory live chunks in prompt payload")
    func memoryRetrievalChunksArePromptContext() throws {
        var index = LiveTranscriptIndex(
            configuration: .init(maxDialogueLinesPerSegment: 2, scoreThreshold: 0.05)
        )
        index.append("""
        [00:10] Alex: 지도 핀 확대와 매물 카드 노출 방식을 논의합니다.
        [00:20] Blair: 광고 상품 노출 우려가 있습니다.
        [05:10] Casey: 결제 화면 색상은 다음 주에 보겠습니다.
        """)
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room", participants: ["Alex", "Blair", "Casey"]),
            rawTranscript: """
            [00:10] Alex: 지도 핀 확대와 매물 카드 노출 방식을 논의합니다.
            [00:20] Blair: 광고 상품 노출 우려가 있습니다.
            [12:00] Alex: 지도 핀과 광고 노출 이슈를 다시 확인합니다.
            """,
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "지도 핀 논의")),
            modelPreset: .balanced,
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 78
        )

        let plan = AnalysisContextPlanner.makePlan(
            for: request,
            retrievalMode: .memoryLiveIndex,
            liveIndex: index
        )
        var requestWithPlan = request
        requestWithPlan.contextPlan = plan
        let prompt = try AnalysisPromptBuilder.buildPrompt(for: requestWithPlan)

        #expect(plan.retrievedChunks.count <= 2)
        #expect(!plan.retrievedChunks.isEmpty)
        #expect(prompt.contains("\"retrievalMode\" : \"memoryLiveIndex\""))
        #expect(prompt.contains("relatedTranscriptChunks"))
        #expect(prompt.contains("지도 핀 확대"))
    }

    @Test("previous snapshot forces patch output for manual analysis")
    func previousSnapshotForcesPatchOutputForManual() {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:10] Alex: 기존 분석 이후 수동 분석입니다.",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "manual"
        )

        #expect(request.outputMode == .livePatch)
    }
}
