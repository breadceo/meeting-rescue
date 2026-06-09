import Foundation
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

    @Test("빈 previous currentIssue가 있으면 patch prompt에서 currentIssue 생성을 요구한다")
    func emptyPreviousCurrentIssueRequiresCurrentIssueInPatchPrompt() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:01] Alex: 임대인 온보딩 소개 페이지를 추가합니다.",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "")),
            reason: "automatic-min-dialogue-lines",
            lastAnalyzedTranscriptCharacterCount: 0
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(request.outputMode == .livePatch)
        #expect(prompt.contains("previousAnalysisSnapshot.currentIssue.summary가 비어 있으면"))
        #expect(prompt.contains("currentIssue를 반드시 채우세요"))
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

    @Test("final analysis with previous snapshot asks for full wrap-up output")
    func finalAnalysisUsesFullWrapUpPromptWhenSnapshotExists() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[10:00] Alex: 기존 내용\n[20:00] Alex: 후반부 결정 후보",
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            reason: "final",
            lastAnalyzedTranscriptCharacterCount: 18
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(request.outputMode == .fullSnapshot)
        #expect(prompt.contains("meetingSummary"))
        #expect(prompt.contains("회의 전체 wrap-up"))
        #expect(prompt.contains("후반부 결정 후보"))
        #expect(!prompt.contains("전체 AnalysisSnapshot을 쓰지 마세요"))
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

    @Test("prompt payload includes meeting type preset and bookmarks")
    func promptIncludesMeetingTypePresetAndBookmarks() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:10] Alex: 금요일 배포 기준으로 보겠습니다.",
            meetingTypePreset: .decision,
            bookmarks: [
                MeetingBookmark(
                    id: "bookmark-1",
                    timestamp: "[00:10]",
                    label: "결정 기준",
                    createdAt: Date(timeIntervalSince1970: 10),
                    excerpt: "금요일 배포 기준으로 보겠습니다."
                )
            ]
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains(#""meetingTypePreset":"decision""#))
        #expect(prompt.contains(#""bookmarks""#))
        #expect(prompt.contains("결정 기준"))
        #expect(prompt.contains("중요 시점 주변 발화를 summary evidence로 우선 고려하세요"))
    }

    @Test("full prompt explains current issue as live focus and summary as whole-meeting wrap-up")
    func fullPromptSeparatesLiveFocusAndWrapUp() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Room"),
            rawTranscript: "[00:10] Alex: 사고 원인을 봅니다.",
            meetingTypePreset: .incident
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("currentIssue는 현재 논점 또는 Live Focus입니다"))
        #expect(prompt.contains("meetingSummary는 회의 전체 wrap-up입니다"))
        #expect(prompt.contains("meetingType이 incident이면 증상, 영향, 원인 가설, mitigation"))
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

    @Test("prompt metadata participants는 새 chunk 발화자를 빠뜨리지 않는다")
    func promptMetadataKeepsCurrentChunkSpeakers() throws {
        let previousTranscript = """
        [00:10] Dulee Lee: GitHub Docs 분리 기준을 봅니다.
        [00:20] Dulee Lee: 직방닥스와 호갱독스를 나누는 안입니다.
        """
        let newTranscript = """
        [06:19] Mason Choi: 네, 알겠습니다.
        [06:20] Mason Choi: 문서 형식 제약도 궁금합니다.
        [06:52] Dulee Lee: 팀 전용 문서는 자유로워야 하지 않을까요?
        [07:31] Glen Lee: 쓰면 안 된다는 의견부터 볼까요?
        [08:13] Rad Kim: 어떤 문서 성격이 들어가나요?
        """
        let rawTranscript = previousTranscript + "\n" + newTranscript
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(
                room: "Room",
                dateTime: "2026-05-27 15:01",
                participants: [
                    "Dulee Lee(dulee@example.com)",
                    "Glen Lee(glen@example.com)",
                    "Mason Choi(mason@example.com)",
                    "Rad Kim(rad@example.com)",
                    "Observer(observer@example.com)"
                ]
            ),
            rawTranscript: rawTranscript,
            previousSnapshot: AnalysisSnapshot(currentIssue: CurrentIssue(summary: "기존 요약")),
            lastAnalyzedTranscriptCharacterCount: previousTranscript.count
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("Mason Choi(mason@example.com)"))
        #expect(prompt.contains("Dulee Lee(dulee@example.com)"))
        #expect(prompt.contains("Glen Lee(glen@example.com)"))
        #expect(prompt.contains("Rad Kim(rad@example.com)"))
        #expect(!prompt.contains("Observer(observer@example.com)"))
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
        #expect(prompt.count < longChunk.count + 3_400)
    }

    @Test("prompt includes supplemental context with transcript priority warning")
    func promptIncludesSupplementalContextPriority() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-03 10:00", participants: ["Alex"]),
            rawTranscript: "[00:01] Alex: transcript가 source of truth입니다.",
            reason: "manual",
            supplementalContextSources: [
                SupplementalContextSource(
                    id: "calendar-1",
                    kind: .calendarMetadata,
                    title: "Launch Review",
                    sourceName: "Google Calendar",
                    excerpt: "Calendar says launch review with Blair.",
                    priority: .calendarMetadata,
                    confidence: 0.86
                )
            ]
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains(#""supplementalContext""#))
        #expect(prompt.contains("Google Calendar"))
        #expect(prompt.contains("transcript가 supplemental context와 충돌하면 transcript를 우선"))
    }

    @Test("prompt forbids calendar metadata from replacing transcript-derived meeting metadata")
    func promptForbidsCalendarMetadataFromReplacingTranscriptMetadata() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Transcript Room", dateTime: "2026-06-03 10:00", participants: ["Alex"]),
            rawTranscript: "[00:01] Alex: transcript 기준 회의입니다.",
            reason: "manual",
            supplementalContextSources: [
                SupplementalContextSource(
                    id: "calendar-1",
                    kind: .calendarMetadata,
                    title: "Calendar Room",
                    sourceName: "Google Calendar",
                    excerpt: "Calendar says different room and Blair attendee.",
                    priority: .calendarMetadata,
                    confidence: 0.90
                )
            ]
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("calendar metadata로 meetingMetadata를 덮어쓰지 마세요"))
    }

    @Test("unaccepted calendar linked source candidates are not injected into prompt")
    func unacceptedCalendarLinkedSourceCandidatesAreNotInjected() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "Launch", dateTime: "2026-06-03 10:00", participants: ["Alex"]),
            rawTranscript: "[00:01] Alex: transcript가 source of truth입니다.",
            reason: "manual",
            supplementalContextSources: [
                SupplementalContextSource(
                    id: "calendar-link-1",
                    kind: .linkedSourceCandidate,
                    title: "Calendar linked source 1",
                    sourceName: "Google Docs",
                    excerpt: "https://docs.google.com/document/d/sanitized-doc-id/edit",
                    priority: .linkedSourceCandidate,
                    confidence: 0.86,
                    isAccepted: false
                )
            ]
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(!prompt.contains("https://docs.google.com/document/d/sanitized-doc-id/edit"))
    }

    @Test("prompt includes domain glossary as low-priority interpretation hints")
    func promptIncludesDomainGlossaryPriorityRules() throws {
        let request = AnalysisRequest(
            meetingID: "meeting-1",
            metadata: MeetingMetadata(room: "R3"),
            rawTranscript: "[03:12] Alex: jax 품질을 봅시다.",
            supplementalContextSources: [
                SupplementalContextSource(
                    id: "glossary:term-zax",
                    kind: .domainGlossary,
                    title: "용어 힌트: zax",
                    sourceName: "Local Glossary",
                    excerpt: "canonical: zax\nmatched aliases: jax\nrule: low-priority interpretation hint",
                    priority: .domainGlossary,
                    confidence: 0.9
                )
            ]
        )

        let prompt = try AnalysisPromptBuilder.buildPrompt(for: request)

        #expect(prompt.contains("domainGlossary"))
        #expect(prompt.contains("canonical: zax"))
        #expect(prompt.contains("Domain glossary"))
        #expect(prompt.contains("raw transcript를 수정하지 말고"))
        #expect(prompt.contains("glossary만 보고 decision/action을 만들지 마세요"))
    }
}
