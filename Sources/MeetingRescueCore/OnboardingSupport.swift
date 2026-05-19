import Foundation

public struct SomaRecordingsFolderDetection: Equatable, Sendable {
    public var url: URL
    public var sourceDescription: String

    public init(url: URL, sourceDescription: String) {
        self.url = url
        self.sourceDescription = sourceDescription
    }
}

public struct SomaRecordingsFolderDetector {
    public static let productionPreferenceURL = URL(
        fileURLWithPath: "Library/Preferences/com.somadevelopmentco.soma.plist",
        relativeTo: FileManager.default.homeDirectoryForCurrentUser
    )

    private let preferenceURL: URL
    private let fileManager: FileManager

    public init(
        preferenceURL: URL = Self.productionPreferenceURL,
        fileManager: FileManager = .default
    ) {
        self.preferenceURL = preferenceURL
        self.fileManager = fileManager
    }

    public func detect() -> SomaRecordingsFolderDetection? {
        guard let data = try? Data(contentsOf: preferenceURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let path = dictionary["CustomChatLogDirectory"] as? String else {
            return nil
        }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        return SomaRecordingsFolderDetection(
            url: url,
            sourceDescription: "\(preferenceURL.path) · CustomChatLogDirectory"
        )
    }
}

public struct LLMProviderAvailability: Equatable, Sendable {
    public var isCodexAvailable: Bool
    public var isClaudeCodeAvailable: Bool

    public init(isCodexAvailable: Bool, isClaudeCodeAvailable: Bool) {
        self.isCodexAvailable = isCodexAvailable
        self.isClaudeCodeAvailable = isClaudeCodeAvailable
    }

    public var hasSubscriptionProvider: Bool {
        isCodexAvailable || isClaudeCodeAvailable
    }

    public var preferredProvider: LLMProviderKind? {
        if isCodexAvailable {
            return .codexExec
        }
        if isClaudeCodeAvailable {
            return .claudeCode
        }
        return nil
    }
}

public struct LLMProviderAvailabilityDetector {
    private let fileManager: FileManager
    private let environment: [String: String]

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = CodexExecProvider.environment(for: .automatic)
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    public func detect() -> LLMProviderAvailability {
        LLMProviderAvailability(
            isCodexAvailable: executableExists(named: "codex"),
            isClaudeCodeAvailable: executableExists(named: "claude")
        )
    }

    private func executableExists(named name: String) -> Bool {
        let path = environment["PATH"] ?? ""
        return path
            .split(separator: ":")
            .map(String.init)
            .contains { directory in
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
                return fileManager.isExecutableFile(atPath: url.path)
            }
    }
}
