import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Onboarding support")
struct OnboardingSupportTests {
    @Test("Soma detector는 production plist의 CustomChatLogDirectory만 사용한다")
    func somaDetectorUsesOnlyCustomChatLogDirectory() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let plistURL = root.appendingPathComponent("com.somadevelopmentco.soma.plist")
        try writePlist(["CustomChatLogDirectory": recordings.path], to: plistURL)

        let detector = SomaRecordingsFolderDetector(preferenceURL: plistURL)
        let detected = try #require(detector.detect())

        #expect(detected.url.path == recordings.path)
        #expect(detected.sourceDescription.contains("CustomChatLogDirectory"))
    }

    @Test("Soma detector는 fallback 없이 값이 없으면 nil을 반환한다")
    func somaDetectorDoesNotFallbackWhenKeyIsMissing() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let plistURL = root.appendingPathComponent("com.somadevelopmentco.soma.plist")
        try writePlist(["OtherDirectory": root.path], to: plistURL)

        let detector = SomaRecordingsFolderDetector(preferenceURL: plistURL)

        #expect(detector.detect() == nil)
    }

    @Test("Soma detector는 존재하지 않는 경로를 무시한다")
    func somaDetectorRequiresExistingDirectory() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let plistURL = root.appendingPathComponent("com.somadevelopmentco.soma.plist")
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        try writePlist(["CustomChatLogDirectory": missing.path], to: plistURL)

        let detector = SomaRecordingsFolderDetector(preferenceURL: plistURL)

        #expect(detector.detect() == nil)
    }

    @Test("Provider availability detector는 PATH의 실행 파일만 확인한다")
    func providerAvailabilityUsesExecutablePath() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let codex = bin.appendingPathComponent("codex")
        try "#!/bin/sh\n".write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        let detector = LLMProviderAvailabilityDetector(environment: ["PATH": bin.path])
        let availability = detector.detect()

        #expect(availability.isCodexAvailable)
        #expect(!availability.isClaudeCodeAvailable)
        #expect(availability.preferredProvider == .codexExec)
    }

    @Test("onboarding 완료 상태를 settings에 저장한다")
    func appSettingsStoresOnboardingCompletion() throws {
        let settings = AppSettings(hasCompletedOnboarding: true)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.hasCompletedOnboarding)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-rescue-onboarding-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writePlist(_ dictionary: [String: String], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
        try data.write(to: url, options: [.atomic])
    }
}
