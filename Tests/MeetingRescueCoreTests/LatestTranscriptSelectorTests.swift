import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("LatestTranscriptSelector")
struct LatestTranscriptSelectorTests {
    @Test("modification time 기준 최신 txt 파일을 선택한다")
    func selectsNewestTextFile() {
        let old = TranscriptFileCandidate(
            url: URL(fileURLWithPath: "/tmp/old.txt"),
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let newest = TranscriptFileCandidate(
            url: URL(fileURLWithPath: "/tmp/new.txt"),
            modificationDate: Date(timeIntervalSince1970: 200)
        )
        let ignored = TranscriptFileCandidate(
            url: URL(fileURLWithPath: "/tmp/new.md"),
            modificationDate: Date(timeIntervalSince1970: 300)
        )

        #expect(LatestTranscriptSelector.latestTextFile(from: [old, newest, ignored]) == newest)
    }

    @Test("동일한 수정 시각이면 파일명으로 deterministic tie-break 한다")
    func deterministicTieBreak() {
        let alpha = TranscriptFileCandidate(
            url: URL(fileURLWithPath: "/tmp/alpha.txt"),
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let beta = TranscriptFileCandidate(
            url: URL(fileURLWithPath: "/tmp/beta.txt"),
            modificationDate: Date(timeIntervalSince1970: 100)
        )

        #expect(LatestTranscriptSelector.latestTextFile(from: [alpha, beta]) == beta)
    }

    @Test("textFiles는 txt regular file만 반환한다")
    func textFilesListsTxtFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRescueLatestFiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let txt = rootURL.appendingPathComponent("meeting.txt")
        let markdown = rootURL.appendingPathComponent("notes.md")
        try "meeting".write(to: txt, atomically: true, encoding: .utf8)
        try "notes".write(to: markdown, atomically: true, encoding: .utf8)

        let files = LatestTranscriptSelector.textFiles(in: rootURL)

        #expect(files.map(\.url.lastPathComponent) == ["meeting.txt"])

        try? FileManager.default.removeItem(at: rootURL)
    }

    @Test("history live badge는 baseline 이후 새 파일이나 수정이 있을 때만 켜진다")
    func liveUpdateDetectorComparesAgainstHistoryBaseline() {
        let firstURL = URL(fileURLWithPath: "/tmp/first.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/second.txt")
        let baseline = TranscriptFileCandidate(
            url: firstURL,
            modificationDate: Date(timeIntervalSince1970: 100)
        )

        #expect(!LiveTranscriptUpdateDetector.isUpdated(latest: baseline, baseline: baseline))
        #expect(!LiveTranscriptUpdateDetector.isUpdated(latest: baseline, baseline: nil))
        #expect(LiveTranscriptUpdateDetector.isUpdated(
            latest: TranscriptFileCandidate(url: firstURL, modificationDate: Date(timeIntervalSince1970: 101)),
            baseline: baseline
        ))
        #expect(LiveTranscriptUpdateDetector.isUpdated(
            latest: TranscriptFileCandidate(url: secondURL, modificationDate: Date(timeIntervalSince1970: 90)),
            baseline: baseline
        ))
    }
}
