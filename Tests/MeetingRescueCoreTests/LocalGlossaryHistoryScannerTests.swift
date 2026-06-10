import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossaryHistoryScannerTests {
    @Test("scanner builds raw transcript documents from folder files")
    func scannerBuildsRawTranscriptDocuments() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-scanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("20260610_103000_Zigbang_R3.txt")
        let second = root.appendingPathComponent("20260611_103000_Zigbang_R3.txt")
        try """
        Room: Zigbang_R3
        Date/Time: 2026-06-10 10:30
        Participants: Ethan
        [00:10] Ethan: jax workflow를 봅니다.
        [00:20] Ethan: 중계사 응답률 채팅을 확인합니다.
        """.write(to: first, atomically: true, encoding: .utf8)
        try """
        Room: Zigbang_R3
        Date/Time: 2026-06-11 10:30
        Participants: Ethan
        [00:10] Ethan: jecks workflow를 봅니다.
        [00:20] Ethan: 중개사 응답률 채팅을 확인합니다.
        """.write(to: second, atomically: true, encoding: .utf8)

        let documents = LocalGlossaryHistoryScanner.documents(
            in: root,
            configuration: .init(maxDocuments: 10, maxBytesPerDocument: 16_384, rawTranscriptLineLimit: 20)
        )

        #expect(documents.count == 2)
        #expect(documents.allSatisfy { document in
            document.sections.contains { $0.field == .rawTranscript }
        })
        #expect(documents.map(\.id).contains { $0.hasSuffix(first.lastPathComponent) })
        #expect(documents.flatMap(\.sections).contains { section in
            section.field == .rawTranscript && section.text.contains("중개사 응답률 채팅")
        })
    }

    @Test("scanner respects max document and line limits")
    func scannerRespectsLimits() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-scanner-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<3 {
            let url = root.appendingPathComponent("meeting-\(index).txt")
            try """
            [00:01] Ethan: 첫 줄 \(index)
            [00:02] Ethan: 둘째 줄 \(index)
            """.write(to: url, atomically: true, encoding: .utf8)
        }

        let documents = LocalGlossaryHistoryScanner.documents(
            in: root,
            configuration: .init(maxDocuments: 2, maxBytesPerDocument: 16_384, rawTranscriptLineLimit: 1)
        )

        #expect(documents.count == 2)
        #expect(documents.allSatisfy { document in
            document.sections.filter { $0.field == .rawTranscript }.count == 1
        })
    }
}
