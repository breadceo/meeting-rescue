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
        #expect(!text.contains("婩杢"))
    }

    @Test("UTF-16LE BOM transcript를 decode한다")
    func decodesUTF16LEWithBOM() {
        var data = Data([0xFF, 0xFE])
        data.append("Room A".data(using: .utf16LittleEndian)!)

        let text = TranscriptTextDecoder.decode(data)

        #expect(text.contains("Room A"))
    }
}
