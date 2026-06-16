import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Transcript file read anchor")
struct TranscriptFileReadAnchorTests {
    @Test("append-only update는 appended로 분류한다")
    func classifiesAppendOnlyUpdate() throws {
        let initial = Data("""
        Room
        2026-06-16 10:29:43
        Aiden Hwang, Claire Kang

        [00:00][SYSTEM] 대화 기록 시작됨
        [00:13] Claire Kang: 시작할게요.
        """.utf8)
        let appended = Data("[00:49][SYSTEM] Gina Chang이(가) 그룹에 입장했습니다.\n".utf8)
        let current = initial + appended
        let anchor = TranscriptFileReadAnchor(data: initial, sampleByteLimit: 24)

        let plan = TranscriptFileAppendPlanner.plan(
            fileSize: UInt64(current.count),
            previousAnchor: anchor,
            currentPrefixSample: current.prefixSample(byteLimit: anchor.sampleByteLimit),
            currentSuffixSampleAtPreviousEnd: current.suffixSample(endingAt: anchor.byteCount, byteLimit: anchor.sampleByteLimit)
        )

        #expect(plan == .appended)
    }

    @Test("header가 재작성되어 기존 offset 앞의 byte가 밀리면 reload로 분류한다")
    func classifiesHeaderRewriteAsReload() throws {
        let initial = Data("""
        Zigbang(2F)_R3
        2026-06-16 10:29:43
        Aiden Hwang(woong@zigbang.com), Claire Kang(claire@zigbang.com)
        ############################################################

        [00:00][SYSTEM] 대화 기록 시작됨
        [00:13] Claire Kang: 어 우유가 오시면 시작할게요.
        """.utf8)
        let rewritten = Data("""
        Zigbang(2F)_R3
        2026-06-16 10:29:43
        Aiden Hwang(woong@zigbang.com), Claire Kang(claire@zigbang.com), Gina Chang(ginachang@zigbang.com), Olga Yeon(hjyeon@zigbang.com)
        ############################################################

        [00:00][SYSTEM] 대화 기록 시작됨
        [00:13] Claire Kang: 어 우유가 오시면 시작할게요.
        [00:49][SYSTEM] Gina Chang이(가) 그룹에 입장했습니다.
        """.utf8)
        let anchor = TranscriptFileReadAnchor(data: initial, sampleByteLimit: 32)

        let plan = TranscriptFileAppendPlanner.plan(
            fileSize: UInt64(rewritten.count),
            previousAnchor: anchor,
            currentPrefixSample: rewritten.prefixSample(byteLimit: anchor.sampleByteLimit),
            currentSuffixSampleAtPreviousEnd: rewritten.suffixSample(endingAt: anchor.byteCount, byteLimit: anchor.sampleByteLimit)
        )

        #expect(plan == .reload)
    }

    @Test("동일 byte 크기라도 sample이 바뀌면 reload로 분류한다")
    func classifiesSameSizeRewriteAsReload() throws {
        let initial = Data("Room\n[00:01] A: hello\n".utf8)
        let rewritten = Data("Room\n[00:01] B: hello\n".utf8)
        let anchor = TranscriptFileReadAnchor(data: initial, sampleByteLimit: 16)

        let plan = TranscriptFileAppendPlanner.plan(
            fileSize: UInt64(rewritten.count),
            previousAnchor: anchor,
            currentPrefixSample: rewritten.prefixSample(byteLimit: anchor.sampleByteLimit),
            currentSuffixSampleAtPreviousEnd: rewritten.suffixSample(endingAt: anchor.byteCount, byteLimit: anchor.sampleByteLimit)
        )

        #expect(plan == .reload)
    }
}
