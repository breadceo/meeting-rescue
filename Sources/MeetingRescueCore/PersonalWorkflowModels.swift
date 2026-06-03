import Foundation

public enum WorkflowSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
}

public enum DecisionCoachCardKind: String, Codable, Equatable, Sendable {
    case unconfirmedDecision
    case missingOwner
    case missingCriteria
    case openQuestion
    case mixedScope
}

public struct DecisionCoachCard: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: DecisionCoachCardKind
    public var severity: WorkflowSeverity
    public var title: String
    public var stuckPoint: String
    public var minimumDecision: String
    public var options: [String]
    public var missingInfo: [String]
    public var nextQuestion: String
    public var evidence: [EvidenceReference]

    public init(
        id: String,
        kind: DecisionCoachCardKind,
        severity: WorkflowSeverity,
        title: String,
        stuckPoint: String,
        minimumDecision: String,
        options: [String] = [],
        missingInfo: [String] = [],
        nextQuestion: String,
        evidence: [EvidenceReference] = []
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.stuckPoint = stuckPoint
        self.minimumDecision = minimumDecision
        self.options = options
        self.missingInfo = missingInfo
        self.nextQuestion = nextQuestion
        self.evidence = evidence
    }
}

public enum ShareReadinessWarningKind: String, Codable, Equatable, Sendable {
    case emptySummary
    case unconfirmedDecision
    case unconfirmedAction
    case missingActionOwner
    case missingActionDeadline
    case weakDecisionEvidence
    case openQuestion
    case unresolvedDecisionCoachCard
}

public struct ShareReadinessWarning: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: ShareReadinessWarningKind
    public var severity: WorkflowSeverity
    public var title: String
    public var detail: String
    public var relatedID: String?

    public init(
        id: String,
        kind: ShareReadinessWarningKind,
        severity: WorkflowSeverity,
        title: String,
        detail: String,
        relatedID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.relatedID = relatedID
    }
}

public struct ActionLedgerMeetingSource: Codable, Equatable, Sendable {
    public var meetingID: String
    public var sourceFileName: String
    public var metadata: MeetingMetadata
    public var snapshot: AnalysisSnapshot

    public init(
        meetingID: String,
        sourceFileName: String,
        metadata: MeetingMetadata,
        snapshot: AnalysisSnapshot
    ) {
        self.meetingID = meetingID
        self.sourceFileName = sourceFileName
        self.metadata = metadata
        self.snapshot = snapshot
    }
}

public struct ActionLedgerItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var task: String
    public var assignee: String?
    public var deadline: String?
    public var meetingID: String
    public var meetingTitle: String
    public var sourceFileName: String
    public var evidenceTimestamp: String
    public var speaker: String?

    public init(
        id: String,
        task: String,
        assignee: String?,
        deadline: String?,
        meetingID: String,
        meetingTitle: String,
        sourceFileName: String,
        evidenceTimestamp: String,
        speaker: String?
    ) {
        self.id = id
        self.task = task
        self.assignee = assignee
        self.deadline = deadline
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.sourceFileName = sourceFileName
        self.evidenceTimestamp = evidenceTimestamp
        self.speaker = speaker
    }
}

public enum CarryOverQuestionStatus: String, Codable, Equatable, Sendable {
    case active
    case dismissed
    case resolved
}

public struct CarryOverMeetingSource: Codable, Equatable, Sendable {
    public var meetingID: String
    public var sourceFileName: String
    public var metadata: MeetingMetadata
    public var snapshot: AnalysisSnapshot

    public init(
        meetingID: String,
        sourceFileName: String,
        metadata: MeetingMetadata,
        snapshot: AnalysisSnapshot
    ) {
        self.meetingID = meetingID
        self.sourceFileName = sourceFileName
        self.metadata = metadata
        self.snapshot = snapshot
    }
}

public struct OpenQuestionCarryOverCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var question: String
    public var sourceMeetingID: String
    public var sourceTitle: String
    public var sourceFileName: String
    public var reason: String
    public var status: CarryOverQuestionStatus
    public var evidence: [EvidenceReference]

    public init(
        id: String,
        question: String,
        sourceMeetingID: String,
        sourceTitle: String,
        sourceFileName: String,
        reason: String,
        status: CarryOverQuestionStatus = .active,
        evidence: [EvidenceReference] = []
    ) {
        self.id = id
        self.question = question
        self.sourceMeetingID = sourceMeetingID
        self.sourceTitle = sourceTitle
        self.sourceFileName = sourceFileName
        self.reason = reason
        self.status = status
        self.evidence = evidence
    }
}

public struct PersonalWorkflowSnapshot: Codable, Equatable, Sendable {
    public var coachCards: [DecisionCoachCard]
    public var readinessWarnings: [ShareReadinessWarning]
    public var actionLedgerItems: [ActionLedgerItem]
    public var carryOverCandidates: [OpenQuestionCarryOverCandidate]

    public init(
        coachCards: [DecisionCoachCard] = [],
        readinessWarnings: [ShareReadinessWarning] = [],
        actionLedgerItems: [ActionLedgerItem] = [],
        carryOverCandidates: [OpenQuestionCarryOverCandidate] = []
    ) {
        self.coachCards = coachCards
        self.readinessWarnings = readinessWarnings
        self.actionLedgerItems = actionLedgerItems
        self.carryOverCandidates = carryOverCandidates
    }
}
