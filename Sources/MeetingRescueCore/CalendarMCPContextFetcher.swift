import Foundation

public struct CalendarLinkedSourceCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var sourceName: String
    public var confidence: Double

    public init(
        id: String,
        title: String,
        url: String,
        sourceName: String,
        confidence: Double
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.sourceName = sourceName
        self.confidence = min(1, max(0, confidence))
    }
}

public struct CalendarMCPFetchResult: Codable, Equatable, Sendable {
    public var events: [CalendarEventCandidate]
    public var linkedSourceCandidates: [CalendarLinkedSourceCandidate]

    public init(
        events: [CalendarEventCandidate] = [],
        linkedSourceCandidates: [CalendarLinkedSourceCandidate] = []
    ) {
        self.events = events
        self.linkedSourceCandidates = linkedSourceCandidates
    }
}

public struct CalendarMCPFetchRequest: Equatable, Sendable {
    public var metadata: MeetingMetadata
    public var rawTranscriptPrefix: String
    public var now: Date

    public init(metadata: MeetingMetadata, rawTranscriptPrefix: String, now: Date = Date()) {
        self.metadata = metadata
        self.rawTranscriptPrefix = rawTranscriptPrefix
        self.now = now
    }
}

public enum CalendarMCPCommandBuilder {
    public static func codexArguments(schemaURL: URL, modelPreset: LLMModelPreset) -> [String] {
        var arguments = ["codex", "exec"]
        if let modelName = modelPreset.codexModelName {
            arguments.append(contentsOf: ["--model", modelName])
        }
        arguments.append(contentsOf: [
            "--skip-git-repo-check",
            "--ephemeral",
            "--disable",
            "apps",
            "--disable",
            "tool_search",
            "--sandbox",
            "read-only",
            "--output-schema",
            schemaURL.path,
            "-"
        ])
        return arguments
    }

    public static func claudeArguments(schemaURL: URL, modelPreset: LLMModelPreset) throws -> [String] {
        let schema = try String(contentsOf: schemaURL, encoding: .utf8)
        var arguments = [
            "claude",
            "-p",
            "--output-format",
            "json",
            "--input-format",
            "text",
            "--no-session-persistence",
            "--json-schema",
            schema
        ]
        if let modelName = modelPreset.claudeCodeModelName {
            arguments.append(contentsOf: ["--model", modelName])
        }
        if let effort = modelPreset.claudeCodeEffort {
            arguments.append(contentsOf: ["--effort", effort])
        }
        return arguments
    }
}

public enum CalendarMCPContextFetcher {
    public static func prompt(for request: CalendarMCPFetchRequest) -> String {
        """
        Use the connected Google Calendar MCP server. Fetch calendar events that overlap this meeting or are likely to refer to it.

        Matching signals:
        - current time: \(ISO8601DateFormatter().string(from: request.now))
        - transcript room/title: \(request.metadata.displayTitle)
        - transcript date/time: \(request.metadata.dateTime ?? "-")
        - transcript participants: \(request.metadata.participants.joined(separator: ", "))
        - transcript prefix:
        \(request.rawTranscriptPrefix)

        Return only JSON matching the schema. Include at most 5 event candidates. Include linkedSourceCandidates only for links found in calendar descriptions. Do not fetch linked documents.
        """
    }

    public static func decode(_ output: String) throws -> CalendarMCPFetchResult {
        let data = try structuredOutputData(from: output)
        return try JSONDecoder().decode(CalendarMCPFetchResult.self, from: data)
    }

    public static func fetch(
        request: CalendarMCPFetchRequest,
        providerKind: LLMProviderKind,
        modelPreset: LLMModelPreset,
        schemaURL: URL,
        timeoutSeconds: Int,
        workingDirectoryURL: URL
    ) async throws -> CalendarMCPFetchResult {
        let arguments: [String]
        let environment: [String: String]
        switch providerKind {
        case .codexExec:
            arguments = CalendarMCPCommandBuilder.codexArguments(schemaURL: schemaURL, modelPreset: modelPreset)
            environment = CodexExecProvider.environment(for: modelPreset)
        case .claudeCode:
            arguments = try CalendarMCPCommandBuilder.claudeArguments(schemaURL: schemaURL, modelPreset: modelPreset)
            environment = ClaudeCodeProvider.environment(for: modelPreset)
        case .customCommand:
            throw LLMProviderError.missingCustomCommand
        }

        let output = try await ProcessRunner.runWithTrace(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: arguments,
            environment: environment,
            standardInput: prompt(for: request),
            timeoutSeconds: timeoutSeconds,
            workingDirectoryURL: workingDirectoryURL
        )
        return try decode(output.output)
    }

    private static func structuredOutputData(from output: String) throws -> Data {
        guard let data = output.data(using: .utf8) else {
            throw LLMProviderError.invalidOutput
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let structured = object["structured_output"] {
            if let string = structured as? String,
               let structuredData = string.data(using: .utf8) {
                return structuredData
            }
            if JSONSerialization.isValidJSONObject(structured) {
                return try JSONSerialization.data(withJSONObject: structured)
            }
        }
        return data
    }
}
