import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Transcript text decoder")
struct TranscriptTextDecoderTests {
    @Test("잘린 UTF-8 snippet을 UTF-16으로 오인하지 않는다")
    func decodesTruncatedUTF8AsUTF8() {
        var data = Data("Sample Room R2\n회의록".utf8)
        data.removeLast()

        let text = TranscriptTextDecoder.decode(data)

        #expect(text.contains("Sample Room R2"))
        #expect(!text.contains("\u{FFFD}"))
        #expect(!text.contains("婩杢"))
    }

    @Test("split UTF-8 append chunk를 pending byte와 합쳐 decode한다")
    func incrementalDecoderPreservesSplitUTF8Characters() {
        let bytes = Array("[01:00][SYSTEM] Olga Yeon이(가) 그룹에 입장했습니다.\n".utf8)
        let splitIndex = bytes.firstIndex(of: 0xEC)! + 1
        var decoder = TranscriptIncrementalTextDecoder()

        let first = decoder.decode(Data(bytes[..<splitIndex]))
        let second = decoder.decode(Data(bytes[splitIndex...]))

        #expect(first == "[01:00][SYSTEM] Olga Yeon")
        #expect(second == "이(가) 그룹에 입장했습니다.\n")
        #expect(!first.contains("\u{FFFD}"))
        #expect(!second.contains("\u{FFFD}"))
    }

    @Test("대부분이 leading NUL인 손상 transcript는 tail만 잘라내 표시하지 않는다")
    func doesNotSalvageDominantLeadingNULTail() {
        let tail = "[55:38] Daniel Min: 감사합니다.\n[55:37][SYSTEM] 대화 기록 종료\n"
        var data = Data(repeating: 0, count: 1024)
        data.append(Data(tail.utf8))

        let text = TranscriptTextDecoder.decode(data)

        #expect(TranscriptTextDecoder.encodingKind(for: data) == .utf8)
        #expect(text == "")
        #expect(!text.contains("㕛"))
        #expect(!text.contains("慄"))
    }

    @Test("UTF-16LE BOM transcript를 decode한다")
    func decodesUTF16LEWithBOM() {
        var data = Data([0xFF, 0xFE])
        data.append("Room A".data(using: .utf16LittleEndian)!)

        let text = TranscriptTextDecoder.decode(data)

        #expect(text.contains("Room A"))
    }

    @Test("BOM 없는 UTF-16LE transcript 감지를 유지한다")
    func keepsDetectingUTF16LEWithoutBOM() {
        let data = "Room A\n2026-06-16".data(using: .utf16LittleEndian)!

        let text = TranscriptTextDecoder.decode(data)

        #expect(TranscriptTextDecoder.encodingKind(for: data) == .utf16LittleEndian)
        #expect(text.contains("Room A"))
        #expect(text.contains("2026-06-16"))
    }
}
