import Testing
@testable import MeetingRescueCore

@Suite("TranscriptParser")
struct TranscriptParserTests {
    @Test("header metadata와 timestamped dialogue를 parse하고 SYSTEM line은 제외한다")
    func parsesMetadataAndDialogue() {
        let raw = """
        Room: Weekly Sync
        Date/Time: 2026-05-14 09:30
        Participants: Alex, Mina, Joon

        [00:00:01] Alex: 안녕하세요.
        [00:00:03] [SYSTEM]: 대화 기록 시작
        00:00:05 Mina: 오늘 목표를 정리하겠습니다.
        (00:00:10) Joon: 배포 리스크를 확인해야 합니다.
        """

        let parsed = TranscriptParser.parse(raw)

        #expect(parsed.metadata.room == "Weekly Sync")
        #expect(parsed.metadata.dateTime == "2026-05-14 09:30")
        #expect(parsed.metadata.participants == ["Alex", "Mina", "Joon"])
        #expect(parsed.dialogueLines == [
            DialogueLine(timestamp: "00:00:01", speaker: "Alex", text: "안녕하세요."),
            DialogueLine(timestamp: "00:00:05", speaker: "Mina", text: "오늘 목표를 정리하겠습니다."),
            DialogueLine(timestamp: "00:00:10", speaker: "Joon", text: "배포 리스크를 확인해야 합니다.")
        ])
    }

    @Test("한글 header key도 지원한다")
    func parsesKoreanHeaders() {
        let raw = """
        회의실: 제품 회의
        일시: 2026년 5월 14일 10:00
        참석자: 수아; 민준
        [0:01] 수아: 시작할게요.
        """

        let parsed = TranscriptParser.parse(raw)

        #expect(parsed.metadata.room == "제품 회의")
        #expect(parsed.metadata.dateTime == "2026년 5월 14일 10:00")
        #expect(parsed.metadata.participants == ["수아", "민준"])
        #expect(parsed.dialogueLines == [
            DialogueLine(timestamp: "0:01", speaker: "수아", text: "시작할게요.")
        ])
    }

    @Test("Recordings 파일의 unlabeled 3-line header 형식을 지원한다")
    func parsesUnlabeledRecordingsHeader() {
        let raw = """
        Sample Room L4
        2026-05-14 17:32:45
        Jordan Park(jordan@example.com), Alex Rivera(alex@example.com)
        ############################################################

        [00:00][SYSTEM] 대화 기록 시작됨
        [00:05] Riley Chen: 녹음 감사합니다.
        """

        let parsed = TranscriptParser.parse(raw)

        #expect(parsed.metadata.room == "Sample Room L4")
        #expect(parsed.metadata.dateTime == "2026-05-14 17:32:45")
        #expect(parsed.metadata.participants == [
            "Jordan Park(jordan@example.com)",
            "Alex Rivera(alex@example.com)"
        ])
        #expect(parsed.dialogueLines == [
            DialogueLine(timestamp: "00:05", speaker: "Riley Chen", text: "녹음 감사합니다.")
        ])
    }

    @Test("meeting end marker를 감지한다")
    func detectsEndMarkers() {
        #expect(TranscriptParser.containsEndMarker("[00:01][SYSTEM] 대화 기록 종료"))
        #expect(TranscriptParser.containsEndMarker("[00:01][SYSTEM] Chat Logs has been ended"))
        #expect(!TranscriptParser.containsEndMarker("[00:01] Alex: 계속 진행합니다."))
    }

    @Test("metadata preview parses headers without dialogue lines")
    func metadataPreviewParsesHeadersWithoutDialogueLines() {
        let raw = """
        Room: Weekly Sync
        Date/Time: 2026-05-14 09:30
        Participants: Alex, Mina, Joon

        [00:00:01] Alex: 안녕하세요.
        [00:00:03] Mina: 오늘 목표를 정리하겠습니다.
        """

        let metadata = TranscriptParser.parseMetadataPreview(raw)

        #expect(metadata.room == "Weekly Sync")
        #expect(metadata.dateTime == "2026-05-14 09:30")
        #expect(metadata.participants == ["Alex", "Mina", "Joon"])
    }

    @Test("metadata preview supports unlabeled recordings header")
    func metadataPreviewSupportsUnlabeledRecordingsHeader() {
        let raw = """
        Sample Room L4
        2026-05-14 17:32:45
        Jordan Park(jordan@example.com), Alex Rivera(alex@example.com)
        ############################################################

        [00:00][SYSTEM] 대화 기록 시작됨
        [00:05] Riley Chen: 녹음 감사합니다.
        """

        let metadata = TranscriptParser.parseMetadataPreview(raw)

        #expect(metadata.room == "Sample Room L4")
        #expect(metadata.dateTime == "2026-05-14 17:32:45")
        #expect(metadata.participants == [
            "Jordan Park(jordan@example.com)",
            "Alex Rivera(alex@example.com)"
        ])
    }
}
