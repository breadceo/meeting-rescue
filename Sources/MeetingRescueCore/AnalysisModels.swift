import Foundation

public enum LLMProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codexExec
    case claudeCode
    case customCommand

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codexExec:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .customCommand:
            return "Custom Command"
        }
    }
}

public enum LLMModelPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case economy
    case balanced
    case frontier

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic:
            return "CLI default"
        case .economy:
            return "Economy"
        case .balanced:
            return "Balanced"
        case .frontier:
            return "Frontier"
        }
    }

    public var detail: String {
        switch self {
        case .automatic:
            return "provider 기본 model을 그대로 사용합니다."
        case .economy:
            return "반복적인 회의 요약과 후보 추출에 맞춘 저비용 preset입니다."
        case .balanced:
            return "복잡한 회의 흐름과 결정 후보 품질을 조금 더 중시합니다."
        case .frontier:
            return "최종 정리나 난도가 높은 회의에만 권장하는 최신 상위 preset입니다."
        }
    }

    public var codexModelName: String? {
        switch self {
        case .automatic:
            return nil
        case .economy:
            return "gpt-5.4-mini"
        case .balanced:
            return "gpt-5.4"
        case .frontier:
            return "gpt-5.5"
        }
    }

    public var claudeCodeModelName: String? {
        switch self {
        case .automatic:
            return nil
        case .economy, .balanced:
            return "sonnet"
        case .frontier:
            return "opus"
        }
    }

    public var claudeCodeEffort: String? {
        switch self {
        case .automatic:
            return nil
        case .economy:
            return "low"
        case .balanced:
            return "medium"
        case .frontier:
            return "high"
        }
    }
}

public enum CodexExecutionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case cliExec
    case appServerExperimental

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cliExec:
            return "CLI exec"
        case .appServerExperimental:
            return "App Server experimental"
        }
    }

    public var detail: String {
        switch self {
        case .cliExec:
            return "현재 안정 경로입니다. 매 analysis마다 codex exec --ephemeral을 실행합니다."
        case .appServerExperimental:
            return "Codex app-server protocol을 사용합니다. 실험 기능이며 실패하거나 느리면 CLI exec로 되돌려 사용하세요."
        }
    }
}

public enum AnalysisTriggerPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case responsive
    case balanced
    case economy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .responsive:
            return "Responsive"
        case .balanced:
            return "Balanced"
        case .economy:
            return "Economy"
        }
    }

    public var configuration: AnalysisTriggerPolicy.Configuration {
        switch self {
        case .responsive:
            return AnalysisTriggerPolicy.Configuration(
                minNewDialogueLines: 20,
                minNewTranscriptCharacters: 1_500,
                minBatchWaitSeconds: 90,
                maxBatchWaitSeconds: 240
            )
        case .balanced:
            return AnalysisTriggerPolicy.Configuration(
                minNewDialogueLines: 24,
                minNewTranscriptCharacters: 1_800,
                minBatchWaitSeconds: 120,
                maxBatchWaitSeconds: 300
            )
        case .economy:
            return AnalysisTriggerPolicy.Configuration(
                minNewDialogueLines: 30,
                minNewTranscriptCharacters: 2_200,
                minBatchWaitSeconds: 240,
                maxBatchWaitSeconds: 300
            )
        }
    }

    public var detail: String {
        let config = configuration
        return "새 발화 \(config.minNewDialogueLines)줄, 새 transcript \(config.minNewTranscriptCharacters)자, 최소 \(config.minBatchWaitSeconds)초, 최대 \(config.maxBatchWaitSeconds)초"
    }
}

public enum LiveContextRetrievalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case memoryLiveIndex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .memoryLiveIndex:
            return "Memory live index"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            return "기존 방식처럼 새 transcript chunk와 짧은 recent context만 사용합니다."
        case .memoryLiveIndex:
            return "현재 live/test run 회의의 메모리 index에서 관련 과거 chunk를 최대 0-3개 추가합니다."
        }
    }
}

public enum MeetingTypePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case decision
    case planning
    case incident
    case oneOnOne
    case brainstorm
    case status

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic:
            return "Auto"
        case .decision:
            return "Decision"
        case .planning:
            return "Planning"
        case .incident:
            return "Incident"
        case .oneOnOne:
            return "1:1"
        case .brainstorm:
            return "Brainstorm"
        case .status:
            return "Status"
        }
    }

    public var detail: String {
        switch self {
        case .automatic:
            return "회의 초반 transcript로 유형을 추정하고 사용자가 필요하면 override합니다."
        case .decision:
            return "선택지, 판단 기준, 결정 근거, 남은 승인자를 우선 정리합니다."
        case .planning:
            return "목표, 범위, 일정, owner, dependency를 우선 정리합니다."
        case .incident:
            return "증상, 영향, 원인 가설, mitigation, follow-up을 우선 정리합니다."
        case .oneOnOne:
            return "관심사, 피드백, 약속, 다음 대화를 우선 정리합니다."
        case .brainstorm:
            return "아이디어, 가설, 근거, 수렴 지점을 우선 정리합니다."
        case .status:
            return "진행 상황, block, 다음 action, escalation을 우선 정리합니다."
        }
    }

    public static var concreteCases: [MeetingTypePreset] {
        allCases.filter { $0 != .automatic }
    }
}

public struct EvidenceReference: Codable, Equatable, Sendable, Identifiable {
    public var timestamp: String
    public var speaker: String?
    public var excerpt: String

    public var id: String {
        [timestamp, speaker ?? "", excerpt].joined(separator: "|")
    }

    public init(timestamp: String, speaker: String? = nil, excerpt: String) {
        self.timestamp = timestamp
        self.speaker = speaker
        self.excerpt = excerpt
    }
}

public struct MeetingSummaryItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var evidence: [EvidenceReference]

    public init(id: String = UUID().uuidString, text: String, evidence: [EvidenceReference] = []) {
        self.id = id
        self.text = text
        self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case evidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString,
            text: (try? container.decode(String.self, forKey: .text)) ?? "",
            evidence: (try? container.decode([EvidenceReference].self, forKey: .evidence)) ?? []
        )
    }
}

public struct MeetingSummary: Codable, Equatable, Sendable {
    public var overview: String
    public var keyPoints: [MeetingSummaryItem]
    public var openQuestions: [MeetingSummaryItem]

    public init(
        overview: String = "",
        keyPoints: [MeetingSummaryItem] = [],
        openQuestions: [MeetingSummaryItem] = []
    ) {
        self.overview = overview
        self.keyPoints = keyPoints
        self.openQuestions = openQuestions
    }

    public var isEmpty: Bool {
        overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && keyPoints.isEmpty
            && openQuestions.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case overview
        case keyPoints
        case openQuestions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            overview: (try? container.decode(String.self, forKey: .overview)) ?? "",
            keyPoints: (try? container.decode([MeetingSummaryItem].self, forKey: .keyPoints)) ?? [],
            openQuestions: (try? container.decode([MeetingSummaryItem].self, forKey: .openQuestions)) ?? []
        )
    }
}

public struct MeetingBookmark: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var timestamp: String
    public var label: String?
    public var createdAt: Date
    public var excerpt: String

    public init(
        id: String = UUID().uuidString,
        timestamp: String,
        label: String? = nil,
        createdAt: Date = Date(),
        excerpt: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.label = trimmedLabel.isEmpty ? nil : trimmedLabel
        self.createdAt = createdAt
        self.excerpt = excerpt
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedProvider: LLMProviderKind
    public var codexExecutionMode: CodexExecutionMode
    public var codexAppServerDiagnosticsEnabled: Bool
    public var modelPreset: LLMModelPreset
    public var meetingTypePreset: MeetingTypePreset
    public var automaticAnalysisEnabled: Bool
    public var hasCompletedOnboarding: Bool
    public var analysisTriggerPreset: AnalysisTriggerPreset
    public var analysisCadenceSeconds: Int
    public var providerTimeoutSeconds: Int
    public var liveContextRetrievalMode: LiveContextRetrievalMode
    public var localGlossaryEnabled: Bool
    public var customProviderCommand: String

    public init(
        selectedProvider: LLMProviderKind = .codexExec,
        codexExecutionMode: CodexExecutionMode = .cliExec,
        codexAppServerDiagnosticsEnabled: Bool = false,
        modelPreset: LLMModelPreset = .economy,
        meetingTypePreset: MeetingTypePreset = .automatic,
        automaticAnalysisEnabled: Bool = true,
        hasCompletedOnboarding: Bool = false,
        analysisTriggerPreset: AnalysisTriggerPreset = .balanced,
        analysisCadenceSeconds: Int = 45,
        providerTimeoutSeconds: Int = 60,
        liveContextRetrievalMode: LiveContextRetrievalMode = .memoryLiveIndex,
        localGlossaryEnabled: Bool = true,
        customProviderCommand: String = ""
    ) {
        self.selectedProvider = selectedProvider
        self.codexExecutionMode = codexExecutionMode
        self.codexAppServerDiagnosticsEnabled = codexAppServerDiagnosticsEnabled
        self.modelPreset = modelPreset
        self.meetingTypePreset = meetingTypePreset
        self.automaticAnalysisEnabled = automaticAnalysisEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.analysisTriggerPreset = analysisTriggerPreset
        self.analysisCadenceSeconds = min(max(analysisCadenceSeconds, 30), 300)
        self.providerTimeoutSeconds = AnalysisTimeoutPolicy.normalizedConfiguredTimeout(providerTimeoutSeconds)
        self.liveContextRetrievalMode = liveContextRetrievalMode
        self.localGlossaryEnabled = localGlossaryEnabled
        self.customProviderCommand = customProviderCommand
    }

    private enum CodingKeys: String, CodingKey {
        case selectedProvider
        case codexExecutionMode
        case codexAppServerDiagnosticsEnabled
        case modelPreset
        case meetingTypePreset
        case automaticAnalysisEnabled
        case hasCompletedOnboarding
        case analysisTriggerPreset
        case analysisCadenceSeconds
        case providerTimeoutSeconds
        case liveContextRetrievalMode
        case localGlossaryEnabled
        case customProviderCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedProvider: (try? container.decode(LLMProviderKind.self, forKey: .selectedProvider)) ?? .codexExec,
            codexExecutionMode: (try? container.decode(CodexExecutionMode.self, forKey: .codexExecutionMode)) ?? .cliExec,
            codexAppServerDiagnosticsEnabled: (try? container.decode(Bool.self, forKey: .codexAppServerDiagnosticsEnabled)) ?? false,
            modelPreset: (try? container.decode(LLMModelPreset.self, forKey: .modelPreset)) ?? .economy,
            meetingTypePreset: (try? container.decode(MeetingTypePreset.self, forKey: .meetingTypePreset)) ?? .automatic,
            automaticAnalysisEnabled: (try? container.decode(Bool.self, forKey: .automaticAnalysisEnabled)) ?? true,
            hasCompletedOnboarding: (try? container.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false,
            analysisTriggerPreset: (try? container.decode(AnalysisTriggerPreset.self, forKey: .analysisTriggerPreset)) ?? .balanced,
            analysisCadenceSeconds: (try? container.decode(Int.self, forKey: .analysisCadenceSeconds)) ?? 45,
            providerTimeoutSeconds: (try? container.decode(Int.self, forKey: .providerTimeoutSeconds)) ?? 60,
            liveContextRetrievalMode: (try? container.decode(LiveContextRetrievalMode.self, forKey: .liveContextRetrievalMode)) ?? .memoryLiveIndex,
            localGlossaryEnabled: (try? container.decode(Bool.self, forKey: .localGlossaryEnabled)) ?? true,
            customProviderCommand: (try? container.decode(String.self, forKey: .customProviderCommand)) ?? ""
        )
    }
}

public enum AnalysisTimeoutPolicy {
    public static let minimumLiveTimeoutSeconds = 10
    public static let oneShotTimeoutSeconds = 180
    public static let maximumConfiguredTimeoutSeconds = 300

    public static func normalizedConfiguredTimeout(_ timeoutSeconds: Int) -> Int {
        min(max(timeoutSeconds, minimumLiveTimeoutSeconds), maximumConfiguredTimeoutSeconds)
    }

    public static func timeoutSeconds(configuredTimeoutSeconds: Int, reason: String) -> Int {
        let configuredTimeoutSeconds = normalizedConfiguredTimeout(configuredTimeoutSeconds)
        if reason.hasPrefix("manual") || reason.hasPrefix("final") {
            return max(configuredTimeoutSeconds, oneShotTimeoutSeconds)
        }
        return max(configuredTimeoutSeconds, minimumLiveTimeoutSeconds)
    }
}

public struct CurrentIssue: Codable, Equatable, Sendable {
    public var summary: String
    public var openQuestions: [String]

    public init(summary: String = "", openQuestions: [String] = []) {
        self.summary = summary
        self.openQuestions = openQuestions
    }
}

public struct TopicTimelineItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startTimestamp: String
    public var endTimestamp: String?
    public var title: String
    public var summary: String

    public init(id: String, startTimestamp: String, endTimestamp: String? = nil, title: String, summary: String) {
        self.id = id
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.title = title
        self.summary = summary
    }
}

public enum CandidateStatus: String, Codable, Equatable, Sendable {
    case candidate
    case confirmed
    case deleted
}

public struct DecisionCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var status: CandidateStatus
    public var evidenceTimestamp: String
    public var speaker: String?

    public init(id: String, text: String, status: CandidateStatus = .candidate, evidenceTimestamp: String, speaker: String? = nil) {
        self.id = id
        self.text = text
        self.status = status
        self.evidenceTimestamp = evidenceTimestamp
        self.speaker = speaker
    }
}

public struct ActionItemCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var assignee: String?
    public var task: String
    public var deadline: String?
    public var status: CandidateStatus
    public var evidenceTimestamp: String
    public var speaker: String?

    public init(
        id: String,
        assignee: String? = nil,
        task: String,
        deadline: String? = nil,
        status: CandidateStatus = .candidate,
        evidenceTimestamp: String,
        speaker: String? = nil
    ) {
        self.id = id
        self.assignee = assignee
        self.task = task
        self.deadline = deadline
        self.status = status
        self.evidenceTimestamp = evidenceTimestamp
        self.speaker = speaker
    }
}

public struct DecisionCandidateEdit: Codable, Equatable, Sendable {
    public var originalText: String
    public var text: String

    public init(originalText: String, text: String) {
        self.originalText = originalText
        self.text = text
    }
}

public struct ActionItemCandidateEdit: Codable, Equatable, Sendable {
    public var originalAssignee: String?
    public var originalTask: String
    public var originalDeadline: String?
    public var assignee: String?
    public var task: String
    public var deadline: String?

    public init(
        originalAssignee: String?,
        originalTask: String,
        originalDeadline: String?,
        assignee: String?,
        task: String,
        deadline: String?
    ) {
        self.originalAssignee = originalAssignee
        self.originalTask = originalTask
        self.originalDeadline = originalDeadline
        self.assignee = assignee
        self.task = task
        self.deadline = deadline
    }
}

public struct AnalysisSnapshot: Codable, Equatable, Sendable {
    public var meetingType: MeetingTypePreset
    public var meetingSummary: MeetingSummary
    public var currentIssue: CurrentIssue
    public var topicTimeline: [TopicTimelineItem]
    public var decisionCandidates: [DecisionCandidate]
    public var actionItemCandidates: [ActionItemCandidate]
    public var risksOrNotes: [String]
    public var generatedAt: Date
    public var provider: LLMProviderKind

    public init(
        meetingType: MeetingTypePreset = .automatic,
        meetingSummary: MeetingSummary = MeetingSummary(),
        currentIssue: CurrentIssue = CurrentIssue(),
        topicTimeline: [TopicTimelineItem] = [],
        decisionCandidates: [DecisionCandidate] = [],
        actionItemCandidates: [ActionItemCandidate] = [],
        risksOrNotes: [String] = [],
        generatedAt: Date = Date(),
        provider: LLMProviderKind = .codexExec
    ) {
        self.meetingType = meetingType
        self.meetingSummary = meetingSummary
        self.currentIssue = currentIssue
        self.topicTimeline = topicTimeline
        self.decisionCandidates = decisionCandidates
        self.actionItemCandidates = actionItemCandidates
        self.risksOrNotes = risksOrNotes
        self.generatedAt = generatedAt
        self.provider = provider
    }

    private enum CodingKeys: String, CodingKey {
        case meetingType
        case meetingSummary
        case currentIssue
        case topicTimeline
        case decisionCandidates
        case actionItemCandidates
        case risksOrNotes
        case generatedAt
        case provider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.meetingType = (try? container.decode(MeetingTypePreset.self, forKey: .meetingType)) ?? .automatic
        self.meetingSummary = (try? container.decode(MeetingSummary.self, forKey: .meetingSummary)) ?? MeetingSummary()
        self.currentIssue = try container.decode(CurrentIssue.self, forKey: .currentIssue)
        self.topicTimeline = try container.decode([TopicTimelineItem].self, forKey: .topicTimeline)
        self.decisionCandidates = try container.decode([DecisionCandidate].self, forKey: .decisionCandidates)
        self.actionItemCandidates = try container.decode([ActionItemCandidate].self, forKey: .actionItemCandidates)
        self.risksOrNotes = try container.decode([String].self, forKey: .risksOrNotes)
        self.generatedAt = (try? container.decode(Date.self, forKey: .generatedAt)) ?? Date()
        self.provider = (try? container.decode(LLMProviderKind.self, forKey: .provider)) ?? .codexExec
    }

    public func applyingPatch(_ patch: AnalysisSnapshotPatch, provider: LLMProviderKind) -> AnalysisSnapshot {
        var copy = self
        if let meetingType = patch.meetingType {
            copy.meetingType = meetingType
        }
        if let meetingSummary = patch.meetingSummary {
            copy.meetingSummary = meetingSummary
        }
        if let currentIssue = patch.currentIssue {
            copy.currentIssue = currentIssue
        } else if copy.currentIssue.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let fallbackIssue = Self.currentIssueFallback(from: patch) {
            copy.currentIssue = fallbackIssue
        }
        copy.topicTimeline = Self.upsertTimeline(copy.topicTimeline, with: patch.topicTimelineUpserts)
        copy.decisionCandidates = Self.upsertDecisions(copy.decisionCandidates, with: patch.decisionCandidateUpserts)
        copy.actionItemCandidates = Self.upsertActions(copy.actionItemCandidates, with: patch.actionItemCandidateUpserts)
        copy.risksOrNotes = Self.appendingUnique(copy.risksOrNotes, patch.risksOrNotesAppend, limit: 12)
        copy.generatedAt = Date()
        copy.provider = provider
        return copy
    }

    private static func currentIssueFallback(from patch: AnalysisSnapshotPatch) -> CurrentIssue? {
        if let topic = patch.topicTimelineUpserts.last {
            return CurrentIssue(summary: topic.summary)
        }
        if let decision = patch.decisionCandidateUpserts.last {
            return CurrentIssue(summary: "결정 후보: \(decision.text)")
        }
        if let action = patch.actionItemCandidateUpserts.last {
            let assigneePrefix = action.assignee.map { "\($0): " } ?? ""
            return CurrentIssue(summary: "액션 후보: \(assigneePrefix)\(action.task)")
        }
        if let note = patch.risksOrNotesAppend.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return CurrentIssue(summary: note)
        }
        return nil
    }

    private static func upsertTimeline(
        _ existing: [TopicTimelineItem],
        with upserts: [TopicTimelineItem]
    ) -> [TopicTimelineItem] {
        upsert(existing, with: upserts, id: \.id) { lhs, rhs in
            timestampSortKey(lhs.startTimestamp) < timestampSortKey(rhs.startTimestamp)
        }
    }

    private static func upsertDecisions(
        _ existing: [DecisionCandidate],
        with upserts: [DecisionCandidate]
    ) -> [DecisionCandidate] {
        upsert(existing, with: upserts, id: \.id) { lhs, rhs in
            timestampSortKey(lhs.evidenceTimestamp) < timestampSortKey(rhs.evidenceTimestamp)
        }
    }

    private static func upsertActions(
        _ existing: [ActionItemCandidate],
        with upserts: [ActionItemCandidate]
    ) -> [ActionItemCandidate] {
        upsert(existing, with: upserts, id: \.id) { lhs, rhs in
            timestampSortKey(lhs.evidenceTimestamp) < timestampSortKey(rhs.evidenceTimestamp)
        }
    }

    private static func upsert<T>(
        _ existing: [T],
        with upserts: [T],
        id: KeyPath<T, String>,
        areInIncreasingOrder: (T, T) -> Bool
    ) -> [T] {
        var values = existing
        for upsert in upserts {
            if let index = values.firstIndex(where: { $0[keyPath: id] == upsert[keyPath: id] }) {
                values[index] = upsert
            } else {
                values.append(upsert)
            }
        }
        return values.sorted(by: areInIncreasingOrder)
    }

    private static func appendingUnique(_ existing: [String], _ additions: [String], limit: Int) -> [String] {
        var values = existing
        var seen = Set(existing.map(normalizedNote))
        for addition in additions {
            let trimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = normalizedNote(trimmed)
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            values.append(trimmed)
        }
        return Array(values.suffix(limit))
    }

    private static func normalizedNote(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    private static func timestampSortKey(_ value: String) -> Int {
        let parts = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ":")
            .compactMap { Int($0) }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if let isoLikeElapsed = isoLikeElapsedSortKey(value) {
            return isoLikeElapsed
        }
        return Int.max
    }

    private static func isoLikeElapsedSortKey(_ value: String) -> Int? {
        guard let tIndex = value.firstIndex(of: "T") else {
            return nil
        }
        let afterT = value.index(after: tIndex)
        let timePrefix = value[afterT...].prefix { character in
            character.isNumber || character == ":"
        }
        let parts = timePrefix.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }
        let hour = parts[0]
        let minute = parts[1]
        let second = parts[2]
        if second == 0 {
            return hour * 60 + minute
        }
        if hour == 0 {
            return minute * 60 + second
        }
        return hour * 3600 + minute * 60 + second
    }
}

public struct AnalysisSnapshotPatch: Codable, Equatable, Sendable {
    public var meetingType: MeetingTypePreset?
    public var meetingSummary: MeetingSummary?
    public var currentIssue: CurrentIssue?
    public var topicTimelineUpserts: [TopicTimelineItem]
    public var closeTopicIDs: [String]
    public var decisionCandidateUpserts: [DecisionCandidate]
    public var actionItemCandidateUpserts: [ActionItemCandidate]
    public var risksOrNotesAppend: [String]

    public init(
        meetingType: MeetingTypePreset? = nil,
        meetingSummary: MeetingSummary? = nil,
        currentIssue: CurrentIssue? = nil,
        topicTimelineUpserts: [TopicTimelineItem] = [],
        closeTopicIDs: [String] = [],
        decisionCandidateUpserts: [DecisionCandidate] = [],
        actionItemCandidateUpserts: [ActionItemCandidate] = [],
        risksOrNotesAppend: [String] = []
    ) {
        self.meetingType = meetingType
        self.meetingSummary = meetingSummary
        self.currentIssue = currentIssue
        self.topicTimelineUpserts = topicTimelineUpserts
        self.closeTopicIDs = closeTopicIDs
        self.decisionCandidateUpserts = decisionCandidateUpserts
        self.actionItemCandidateUpserts = actionItemCandidateUpserts
        self.risksOrNotesAppend = risksOrNotesAppend
    }

    private enum CodingKeys: String, CodingKey {
        case meetingType
        case meetingSummary
        case currentIssue
        case topicTimelineUpserts
        case closeTopicIDs
        case decisionCandidateUpserts
        case actionItemCandidateUpserts
        case risksOrNotesAppend
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            meetingType: try container.decodeIfPresent(MeetingTypePreset.self, forKey: .meetingType),
            meetingSummary: try container.decodeIfPresent(MeetingSummary.self, forKey: .meetingSummary),
            currentIssue: try container.decodeIfPresent(CurrentIssue.self, forKey: .currentIssue),
            topicTimelineUpserts: try container.decode([TopicTimelineItem].self, forKey: .topicTimelineUpserts),
            closeTopicIDs: try container.decode([String].self, forKey: .closeTopicIDs),
            decisionCandidateUpserts: try container.decode([DecisionCandidate].self, forKey: .decisionCandidateUpserts),
            actionItemCandidateUpserts: try container.decode([ActionItemCandidate].self, forKey: .actionItemCandidateUpserts),
            risksOrNotesAppend: try container.decode([String].self, forKey: .risksOrNotesAppend)
        )
    }
}

public enum AnalysisOutputMode: String, Equatable, Sendable {
    case fullSnapshot
    case livePatch
}

public struct LLMUsageSample: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var provider: LLMProviderKind
    public var modelPreset: LLMModelPreset
    public var modelName: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var inputPricePerMillionUSD: Double?
    public var outputPricePerMillionUSD: Double?
    public var estimatedCostUSD: Double?
    public var reason: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        provider: LLMProviderKind,
        modelPreset: LLMModelPreset,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        inputPricePerMillionUSD: Double?,
        outputPricePerMillionUSD: Double?,
        estimatedCostUSD: Double?,
        reason: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.modelPreset = modelPreset
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.inputPricePerMillionUSD = inputPricePerMillionUSD
        self.outputPricePerMillionUSD = outputPricePerMillionUSD
        self.estimatedCostUSD = estimatedCostUSD
        self.reason = reason
        self.createdAt = createdAt
    }
}

public struct LLMUsageSummary: Codable, Equatable, Sendable {
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalEstimatedCostUSD: Double
    public var samples: [LLMUsageSample]

    public init(
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0,
        totalEstimatedCostUSD: Double = 0,
        samples: [LLMUsageSample] = []
    ) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalEstimatedCostUSD = totalEstimatedCostUSD
        self.samples = samples
    }

    public var latestSample: LLMUsageSample? {
        samples.last
    }

    public mutating func append(_ sample: LLMUsageSample) {
        totalInputTokens += sample.inputTokens
        totalOutputTokens += sample.outputTokens
        totalEstimatedCostUSD += sample.estimatedCostUSD ?? 0
        samples.append(sample)
        if samples.count > 30 {
            samples.removeFirst(samples.count - 30)
        }
    }
}

public enum AnalysisAttemptStatus: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failed
    case skipped
    case retryScheduled
}

public struct AnalysisAttemptBatchStats: Codable, Equatable, Sendable {
    public var triggerReason: String
    public var newTranscriptCharacters: Int
    public var includedTranscriptCharacters: Int
    public var newDialogueLines: Int
    public var includedDialogueLines: Int
    public var lastAnalyzedTranscriptCharacterCount: Int
    public var targetTranscriptCharacterCount: Int
    public var sourceTranscriptCharacterCount: Int
    public var skippedReason: String?

    public init(
        triggerReason: String,
        newTranscriptCharacters: Int,
        includedTranscriptCharacters: Int,
        newDialogueLines: Int,
        includedDialogueLines: Int,
        lastAnalyzedTranscriptCharacterCount: Int,
        targetTranscriptCharacterCount: Int,
        sourceTranscriptCharacterCount: Int,
        skippedReason: String? = nil
    ) {
        self.triggerReason = triggerReason
        self.newTranscriptCharacters = newTranscriptCharacters
        self.includedTranscriptCharacters = includedTranscriptCharacters
        self.newDialogueLines = newDialogueLines
        self.includedDialogueLines = includedDialogueLines
        self.lastAnalyzedTranscriptCharacterCount = lastAnalyzedTranscriptCharacterCount
        self.targetTranscriptCharacterCount = targetTranscriptCharacterCount
        self.sourceTranscriptCharacterCount = sourceTranscriptCharacterCount
        self.skippedReason = skippedReason
    }

    public var compactSummary: String {
        var parts = [
            "새 \(newDialogueLines)줄/\(newTranscriptCharacters)자",
            "포함 \(includedDialogueLines)줄/\(includedTranscriptCharacters)자",
            "cursor \(lastAnalyzedTranscriptCharacterCount)-\(targetTranscriptCharacterCount)/\(sourceTranscriptCharacterCount)"
        ]
        if let skippedReason, !skippedReason.isEmpty {
            parts.append("skip \(skippedReason)")
        }
        return parts.joined(separator: " · ")
    }
}

public struct AnalysisContextPlan: Codable, Equatable, Sendable {
    public var retrievalMode: LiveContextRetrievalMode
    public var retrievalTopK: Int
    public var retrievalLatencyMilliseconds: Int
    public var retrievedChunks: [RetrievedTranscriptChunk]
    public var speakingParticipantCount: Int
    public var metadataParticipantCount: Int
    public var omittedParticipantCount: Int
    public var newTranscriptCharacters: Int
    public var newDialogueLines: Int
    public var recentContextCharacters: Int
    public var estimatedPromptTokens: Int

    public init(
        retrievalMode: LiveContextRetrievalMode,
        retrievalTopK: Int = 0,
        retrievalLatencyMilliseconds: Int = 0,
        retrievedChunks: [RetrievedTranscriptChunk] = [],
        speakingParticipantCount: Int = 0,
        metadataParticipantCount: Int = 0,
        omittedParticipantCount: Int = 0,
        newTranscriptCharacters: Int = 0,
        newDialogueLines: Int = 0,
        recentContextCharacters: Int = 0,
        estimatedPromptTokens: Int = 0
    ) {
        self.retrievalMode = retrievalMode
        self.retrievalTopK = retrievalTopK
        self.retrievalLatencyMilliseconds = retrievalLatencyMilliseconds
        self.retrievedChunks = retrievedChunks
        self.speakingParticipantCount = speakingParticipantCount
        self.metadataParticipantCount = metadataParticipantCount
        self.omittedParticipantCount = omittedParticipantCount
        self.newTranscriptCharacters = newTranscriptCharacters
        self.newDialogueLines = newDialogueLines
        self.recentContextCharacters = recentContextCharacters
        self.estimatedPromptTokens = estimatedPromptTokens
    }

    public var compactSummary: String {
        let ranges = retrievedChunks
            .map(\.timeRange)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let chunkSummary = ranges.isEmpty ? "\(retrievedChunks.count) chunks" : ranges
        return "\(retrievalMode.displayName) · top \(retrievalTopK) · \(chunkSummary) · \(retrievalLatencyMilliseconds)ms"
    }
}

public struct RetrievedTranscriptChunk: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var timeRange: String
    public var text: String
    public var score: Double

    public init(id: String, timeRange: String, text: String, score: Double) {
        self.id = id
        self.timeRange = timeRange
        self.text = text
        self.score = score
    }
}

public struct AnalysisRunTraceEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var startedAtMilliseconds: Int
    public var durationMilliseconds: Int?
    public var detail: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        startedAtMilliseconds: Int,
        durationMilliseconds: Int? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startedAtMilliseconds = startedAtMilliseconds
        self.durationMilliseconds = durationMilliseconds
        self.detail = detail
    }
}

public struct AnalysisRunTrace: Codable, Equatable, Sendable {
    public var providerExecutable: String
    public var argumentsSummary: String
    public var workingDirectory: String
    public var inputBytes: Int
    public var outputBytes: Int
    public var stderrBytes: Int
    public var exitCode: Int32?
    public var timedOut: Bool
    public var startedAtUnixMilliseconds: Int
    public var events: [AnalysisRunTraceEvent]

    public init(
        providerExecutable: String,
        argumentsSummary: String,
        workingDirectory: String,
        inputBytes: Int,
        outputBytes: Int = 0,
        stderrBytes: Int = 0,
        exitCode: Int32? = nil,
        timedOut: Bool = false,
        startedAtUnixMilliseconds: Int = Int(Date().timeIntervalSince1970 * 1000),
        events: [AnalysisRunTraceEvent] = []
    ) {
        self.providerExecutable = providerExecutable
        self.argumentsSummary = argumentsSummary
        self.workingDirectory = workingDirectory
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.stderrBytes = stderrBytes
        self.exitCode = exitCode
        self.timedOut = timedOut
        self.startedAtUnixMilliseconds = startedAtUnixMilliseconds
        self.events = events
    }
}

public struct AnalysisAttemptLog: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var reason: String
    public var status: AnalysisAttemptStatus
    public var provider: LLMProviderKind
    public var codexExecutionMode: CodexExecutionMode?
    public var modelPreset: LLMModelPreset
    public var modelName: String
    public var startedAt: Date
    public var completedAt: Date?
    public var inputTokens: Int
    public var outputTokens: Int
    public var durationMilliseconds: Int?
    public var message: String?
    public var prompt: String?
    public var providerOutput: String?
    public var batchStats: AnalysisAttemptBatchStats?
    public var contextPlan: AnalysisContextPlan?
    public var runTrace: AnalysisRunTrace?

    public init(
        id: String = UUID().uuidString,
        reason: String,
        status: AnalysisAttemptStatus,
        provider: LLMProviderKind,
        codexExecutionMode: CodexExecutionMode? = nil,
        modelPreset: LLMModelPreset,
        modelName: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        durationMilliseconds: Int? = nil,
        message: String? = nil,
        prompt: String? = nil,
        providerOutput: String? = nil,
        batchStats: AnalysisAttemptBatchStats? = nil,
        contextPlan: AnalysisContextPlan? = nil,
        runTrace: AnalysisRunTrace? = nil
    ) {
        self.id = id
        self.reason = reason
        self.status = status
        self.provider = provider
        self.codexExecutionMode = codexExecutionMode
        self.modelPreset = modelPreset
        self.modelName = modelName
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.durationMilliseconds = durationMilliseconds
        self.message = message
        self.prompt = prompt
        self.providerOutput = providerOutput
        self.batchStats = batchStats
        self.contextPlan = contextPlan
        self.runTrace = runTrace
    }

    public var elapsedMilliseconds: Int? {
        if let durationMilliseconds {
            return durationMilliseconds
        }
        guard let completedAt else {
            return nil
        }
        return max(0, Int((completedAt.timeIntervalSince(startedAt) * 1000).rounded()))
    }

    public var executionProviderDisplayName: String {
        guard provider == .codexExec else {
            return provider.displayName
        }
        switch inferredCodexExecutionMode {
        case .appServerExperimental:
            return "Codex App Server"
        case .cliExec:
            return "Codex CLI exec"
        }
    }

    private var inferredCodexExecutionMode: CodexExecutionMode {
        if let codexExecutionMode {
            return codexExecutionMode
        }
        if let argumentsSummary = runTrace?.argumentsSummary,
           argumentsSummary.contains("app-server") {
            return .appServerExperimental
        }
        if runTrace?.events.contains(where: { $0.name.contains("app-server") }) == true {
            return .appServerExperimental
        }
        return .cliExec
    }
}

public struct MeetingAnalysisState: Codable, Equatable, Sendable {
    public var latestSnapshot: AnalysisSnapshot?
    public var confirmedCandidateIDs: Set<String>
    public var deletedCandidateIDs: Set<String>
    public var decisionCandidateEdits: [String: DecisionCandidateEdit]
    public var actionItemCandidateEdits: [String: ActionItemCandidateEdit]
    public var lastError: String?
    public var updatedAt: Date
    public var isCompleted: Bool
    public var usageSummary: LLMUsageSummary
    public var attemptLogs: [AnalysisAttemptLog]
    public var analyzedTranscriptCharacterCount: Int
    public var bookmarks: [MeetingBookmark]
    public var dismissedCarryOverQuestionIDs: Set<String>
    public var resolvedCarryOverQuestionIDs: Set<String>
    public var calendarContext: CalendarContextState

    public init(
        latestSnapshot: AnalysisSnapshot? = nil,
        confirmedCandidateIDs: Set<String> = [],
        deletedCandidateIDs: Set<String> = [],
        decisionCandidateEdits: [String: DecisionCandidateEdit] = [:],
        actionItemCandidateEdits: [String: ActionItemCandidateEdit] = [:],
        lastError: String? = nil,
        updatedAt: Date = Date(),
        isCompleted: Bool = false,
        usageSummary: LLMUsageSummary = LLMUsageSummary(),
        attemptLogs: [AnalysisAttemptLog] = [],
        analyzedTranscriptCharacterCount: Int = 0,
        bookmarks: [MeetingBookmark] = [],
        dismissedCarryOverQuestionIDs: Set<String> = [],
        resolvedCarryOverQuestionIDs: Set<String> = [],
        calendarContext: CalendarContextState = CalendarContextState()
    ) {
        self.latestSnapshot = latestSnapshot
        self.confirmedCandidateIDs = confirmedCandidateIDs
        self.deletedCandidateIDs = deletedCandidateIDs
        self.decisionCandidateEdits = decisionCandidateEdits
        self.actionItemCandidateEdits = actionItemCandidateEdits
        self.lastError = lastError
        self.updatedAt = updatedAt
        self.isCompleted = isCompleted
        self.usageSummary = usageSummary
        self.attemptLogs = attemptLogs
        self.analyzedTranscriptCharacterCount = analyzedTranscriptCharacterCount
        self.bookmarks = bookmarks
        self.dismissedCarryOverQuestionIDs = dismissedCarryOverQuestionIDs
        self.resolvedCarryOverQuestionIDs = resolvedCarryOverQuestionIDs
        self.calendarContext = calendarContext
    }

    private enum CodingKeys: String, CodingKey {
        case latestSnapshot
        case confirmedCandidateIDs
        case deletedCandidateIDs
        case decisionCandidateEdits
        case actionItemCandidateEdits
        case lastError
        case updatedAt
        case isCompleted
        case usageSummary
        case attemptLogs
        case analyzedTranscriptCharacterCount
        case bookmarks
        case dismissedCarryOverQuestionIDs
        case resolvedCarryOverQuestionIDs
        case calendarContext
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            latestSnapshot: try? container.decode(AnalysisSnapshot.self, forKey: .latestSnapshot),
            confirmedCandidateIDs: (try? container.decode(Set<String>.self, forKey: .confirmedCandidateIDs)) ?? [],
            deletedCandidateIDs: (try? container.decode(Set<String>.self, forKey: .deletedCandidateIDs)) ?? [],
            decisionCandidateEdits: (try? container.decode([String: DecisionCandidateEdit].self, forKey: .decisionCandidateEdits)) ?? [:],
            actionItemCandidateEdits: (try? container.decode([String: ActionItemCandidateEdit].self, forKey: .actionItemCandidateEdits)) ?? [:],
            lastError: try? container.decode(String.self, forKey: .lastError),
            updatedAt: (try? container.decode(Date.self, forKey: .updatedAt)) ?? Date(),
            isCompleted: (try? container.decode(Bool.self, forKey: .isCompleted)) ?? false,
            usageSummary: (try? container.decode(LLMUsageSummary.self, forKey: .usageSummary)) ?? LLMUsageSummary(),
            attemptLogs: (try? container.decode([AnalysisAttemptLog].self, forKey: .attemptLogs)) ?? [],
            analyzedTranscriptCharacterCount: (try? container.decode(Int.self, forKey: .analyzedTranscriptCharacterCount)) ?? 0,
            bookmarks: (try? container.decode([MeetingBookmark].self, forKey: .bookmarks)) ?? [],
            dismissedCarryOverQuestionIDs: (try? container.decode(Set<String>.self, forKey: .dismissedCarryOverQuestionIDs)) ?? [],
            resolvedCarryOverQuestionIDs: (try? container.decode(Set<String>.self, forKey: .resolvedCarryOverQuestionIDs)) ?? [],
            calendarContext: (try? container.decode(CalendarContextState.self, forKey: .calendarContext)) ?? CalendarContextState()
        )
    }

    public func applyingCandidateState(to snapshot: AnalysisSnapshot) -> AnalysisSnapshot {
        var copy = snapshot
        copy.decisionCandidates = copy.decisionCandidates.map { candidate in
            var candidate = candidate
            candidate.status = status(for: candidate.id)
            if let edit = decisionCandidateEdits[candidate.id] {
                candidate.text = edit.text
            }
            return candidate
        }
        copy.actionItemCandidates = copy.actionItemCandidates.map { candidate in
            var candidate = candidate
            candidate.status = status(for: candidate.id)
            if let edit = actionItemCandidateEdits[candidate.id] {
                candidate.assignee = edit.assignee
                candidate.task = edit.task
                candidate.deadline = edit.deadline
            }
            return candidate
        }
        return copy
    }

    public mutating func setCandidateStatus(id: String, status: CandidateStatus) {
        switch status {
        case .candidate:
            confirmedCandidateIDs.remove(id)
            deletedCandidateIDs.remove(id)
            restoreOriginalValuesBeforeRemovingEdits(id: id)
        case .confirmed:
            deletedCandidateIDs.remove(id)
            confirmedCandidateIDs.insert(id)
        case .deleted:
            confirmedCandidateIDs.remove(id)
            deletedCandidateIDs.insert(id)
            restoreOriginalValuesBeforeRemovingEdits(id: id)
        }
    }

    public mutating func addBookmark(_ bookmark: MeetingBookmark) {
        guard !bookmarks.contains(where: { $0.id == bookmark.id }) else {
            return
        }
        bookmarks.append(bookmark)
    }

    public mutating func deleteBookmark(id: String) {
        bookmarks.removeAll { $0.id == id }
    }

    public mutating func setCarryOverQuestionStatus(id: String, status: CarryOverQuestionStatus) {
        switch status {
        case .active:
            dismissedCarryOverQuestionIDs.remove(id)
            resolvedCarryOverQuestionIDs.remove(id)
        case .dismissed:
            resolvedCarryOverQuestionIDs.remove(id)
            dismissedCarryOverQuestionIDs.insert(id)
        case .resolved:
            dismissedCarryOverQuestionIDs.remove(id)
            resolvedCarryOverQuestionIDs.insert(id)
        }
    }

    public mutating func editDecisionCandidate(id: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let current = latestSnapshot?.decisionCandidates.first { $0.id == id }
        let originalText = decisionCandidateEdits[id]?.originalText ?? current?.text ?? trimmed
        decisionCandidateEdits[id] = DecisionCandidateEdit(originalText: originalText, text: trimmed)
        setCandidateStatus(id: id, status: .confirmed)
        reapplyCandidateStateToLatestSnapshot()
    }

    public mutating func editActionItemCandidate(id: String, assignee: String?, task: String, deadline: String?) {
        let normalizedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else {
            return
        }

        let normalizedAssignee = normalizedOptionalText(assignee)
        let normalizedDeadline = normalizedOptionalText(deadline)
        let current = latestSnapshot?.actionItemCandidates.first { $0.id == id }
        let existingEdit = actionItemCandidateEdits[id]
        actionItemCandidateEdits[id] = ActionItemCandidateEdit(
            originalAssignee: existingEdit?.originalAssignee ?? current?.assignee,
            originalTask: existingEdit?.originalTask ?? current?.task ?? normalizedTask,
            originalDeadline: existingEdit?.originalDeadline ?? current?.deadline,
            assignee: normalizedAssignee,
            task: normalizedTask,
            deadline: normalizedDeadline
        )
        setCandidateStatus(id: id, status: .confirmed)
        reapplyCandidateStateToLatestSnapshot()
    }

    public mutating func restoreOriginalDecisionCandidate(id: String) {
        guard let edit = decisionCandidateEdits.removeValue(forKey: id) else {
            return
        }
        restoreOriginalDecisionValue(id: id, edit: edit)
        reapplyCandidateStateToLatestSnapshot()
    }

    public mutating func restoreOriginalActionItemCandidate(id: String) {
        guard let edit = actionItemCandidateEdits.removeValue(forKey: id) else {
            return
        }
        restoreOriginalActionItemValue(id: id, edit: edit)
        reapplyCandidateStateToLatestSnapshot()
    }

    public mutating func appendUsage(_ usage: LLMUsageSample) {
        usageSummary.append(usage)
    }

    public mutating func appendAttempt(_ attempt: AnalysisAttemptLog) {
        attemptLogs.append(attempt)
        if attemptLogs.count > 40 {
            attemptLogs.removeFirst(attemptLogs.count - 40)
        }
    }

    @discardableResult
    public mutating func markInterruptedRunningAttemptsSkipped(
        message: String,
        completedAt: Date = Date()
    ) -> Bool {
        var changed = false
        for index in attemptLogs.indices where attemptLogs[index].status == .running {
            attemptLogs[index].status = .skipped
            attemptLogs[index].completedAt = completedAt
            attemptLogs[index].message = message
            changed = true
        }
        if changed {
            updatedAt = completedAt
        }
        return changed
    }

    private mutating func restoreOriginalValuesBeforeRemovingEdits(id: String) {
        if let edit = decisionCandidateEdits.removeValue(forKey: id) {
            restoreOriginalDecisionValue(id: id, edit: edit)
        }
        if let edit = actionItemCandidateEdits.removeValue(forKey: id) {
            restoreOriginalActionItemValue(id: id, edit: edit)
        }
    }

    private mutating func restoreOriginalDecisionValue(id: String, edit: DecisionCandidateEdit) {
        if var snapshot = latestSnapshot {
            snapshot.decisionCandidates = snapshot.decisionCandidates.map { candidate in
                var candidate = candidate
                if candidate.id == id {
                    candidate.text = edit.originalText
                }
                return candidate
            }
            latestSnapshot = snapshot
        }
    }

    private mutating func restoreOriginalActionItemValue(id: String, edit: ActionItemCandidateEdit) {
        if var snapshot = latestSnapshot {
            snapshot.actionItemCandidates = snapshot.actionItemCandidates.map { candidate in
                var candidate = candidate
                if candidate.id == id {
                    candidate.assignee = edit.originalAssignee
                    candidate.task = edit.originalTask
                    candidate.deadline = edit.originalDeadline
                }
                return candidate
            }
            latestSnapshot = snapshot
        }
    }

    private func status(for id: String) -> CandidateStatus {
        if deletedCandidateIDs.contains(id) {
            return .deleted
        }
        if confirmedCandidateIDs.contains(id) {
            return .confirmed
        }
        return .candidate
    }

    private mutating func reapplyCandidateStateToLatestSnapshot() {
        if let latestSnapshot {
            self.latestSnapshot = applyingCandidateState(to: latestSnapshot)
        }
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct AnalysisRequest: Equatable, Sendable {
    public var meetingID: String
    public var metadata: MeetingMetadata
    public var rawTranscript: String
    public var previousSnapshot: AnalysisSnapshot?
    public var confirmedCandidateIDs: Set<String>
    public var deletedCandidateIDs: Set<String>
    public var providerKind: LLMProviderKind
    public var modelPreset: LLMModelPreset
    public var meetingTypePreset: MeetingTypePreset
    public var bookmarks: [MeetingBookmark]
    public var reason: String
    public var lastAnalyzedTranscriptCharacterCount: Int
    public var contextPlan: AnalysisContextPlan?
    public var supplementalContextSources: [SupplementalContextSource]

    public init(
        meetingID: String,
        metadata: MeetingMetadata,
        rawTranscript: String,
        previousSnapshot: AnalysisSnapshot? = nil,
        confirmedCandidateIDs: Set<String> = [],
        deletedCandidateIDs: Set<String> = [],
        providerKind: LLMProviderKind = .codexExec,
        modelPreset: LLMModelPreset = .economy,
        meetingTypePreset: MeetingTypePreset = .automatic,
        bookmarks: [MeetingBookmark] = [],
        reason: String = "",
        lastAnalyzedTranscriptCharacterCount: Int = 0,
        contextPlan: AnalysisContextPlan? = nil,
        supplementalContextSources: [SupplementalContextSource] = []
    ) {
        self.meetingID = meetingID
        self.metadata = metadata
        self.rawTranscript = rawTranscript
        self.previousSnapshot = previousSnapshot
        self.confirmedCandidateIDs = confirmedCandidateIDs
        self.deletedCandidateIDs = deletedCandidateIDs
        self.providerKind = providerKind
        self.modelPreset = modelPreset
        self.meetingTypePreset = meetingTypePreset
        self.bookmarks = bookmarks
        self.reason = reason
        self.lastAnalyzedTranscriptCharacterCount = lastAnalyzedTranscriptCharacterCount
        self.contextPlan = contextPlan
        self.supplementalContextSources = supplementalContextSources
    }

    public var outputMode: AnalysisOutputMode {
        previousSnapshot != nil && !Self.usesFullSnapshotOutput(reason) ? .livePatch : .fullSnapshot
    }

    public static func usesFullSnapshotOutput(_ reason: String) -> Bool {
        reason.hasPrefix("repair") || reason.hasPrefix("full-refresh") || reason.hasPrefix("final")
    }

    public static func isAutomaticReason(_ reason: String) -> Bool {
        reason.hasPrefix("automatic")
    }
}

public struct AnalysisProviderResult: Equatable, Sendable {
    public var snapshot: AnalysisSnapshot
    public var usage: LLMUsageSample
    public var rawOutput: String
    public var runTrace: AnalysisRunTrace?

    public init(
        snapshot: AnalysisSnapshot,
        usage: LLMUsageSample,
        rawOutput: String = "",
        runTrace: AnalysisRunTrace? = nil
    ) {
        self.snapshot = snapshot
        self.usage = usage
        self.rawOutput = rawOutput
        self.runTrace = runTrace
    }
}

public enum AnalysisRunResult: Equatable, Sendable {
    case success(AnalysisSnapshot, usage: LLMUsageSample, rawOutput: String, runTrace: AnalysisRunTrace?)
    case skippedAlreadyRunning
    case staleIgnored(previousSnapshot: AnalysisSnapshot?)
    case failurePreserved(previousSnapshot: AnalysisSnapshot?, message: String, runTrace: AnalysisRunTrace?)
}
