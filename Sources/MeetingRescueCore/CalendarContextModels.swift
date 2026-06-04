import Foundation

public enum CalendarMCPStatus: String, Codable, Equatable, Sendable {
    case unknown
    case missing
    case connected
    case failed
    case cachedReplay
}

public enum CalendarContextCandidateStatus: String, Codable, Equatable, Sendable {
    case candidate
    case accepted
    case dismissed
}

public struct CalendarEventCandidate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startDateText: String
    public var endDateText: String
    public var organizer: String?
    public var attendees: [String]
    public var descriptionExcerpt: String
    public var recurrenceID: String?
    public var confidence: Double
    public var status: CalendarContextCandidateStatus

    public init(
        id: String,
        title: String,
        startDateText: String,
        endDateText: String,
        organizer: String? = nil,
        attendees: [String] = [],
        descriptionExcerpt: String = "",
        recurrenceID: String? = nil,
        confidence: Double = 0,
        status: CalendarContextCandidateStatus = .candidate
    ) {
        self.id = id
        self.title = title
        self.startDateText = startDateText
        self.endDateText = endDateText
        self.organizer = organizer
        self.attendees = attendees
        self.descriptionExcerpt = descriptionExcerpt
        self.recurrenceID = recurrenceID
        self.confidence = min(1, max(0, confidence))
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDateText
        case endDateText
        case organizer
        case attendees
        case descriptionExcerpt
        case recurrenceID
        case confidence
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            startDateText: try container.decode(String.self, forKey: .startDateText),
            endDateText: try container.decode(String.self, forKey: .endDateText),
            organizer: try container.decodeIfPresent(String.self, forKey: .organizer),
            attendees: (try? container.decode([String].self, forKey: .attendees)) ?? [],
            descriptionExcerpt: (try? container.decode(String.self, forKey: .descriptionExcerpt)) ?? "",
            recurrenceID: try container.decodeIfPresent(String.self, forKey: .recurrenceID),
            confidence: (try? container.decode(Double.self, forKey: .confidence)) ?? 0,
            status: (try? container.decode(CalendarContextCandidateStatus.self, forKey: .status)) ?? .candidate
        )
    }
}

public enum SupplementalContextKind: String, Codable, Equatable, Sendable {
    case confirmedLocalArtifact
    case attachedText
    case calendarMetadata
    case linkedSourceCandidate
    case recurringMemory
}

public enum SupplementalContextPriority: Int, Codable, Equatable, Comparable, Sendable {
    case confirmedLocalArtifact = 10
    case userAttachedContext = 20
    case calendarMetadata = 30
    case linkedSourceCandidate = 40

    public static func < (lhs: SupplementalContextPriority, rhs: SupplementalContextPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SupplementalContextSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: SupplementalContextKind
    public var title: String
    public var sourceName: String
    public var excerpt: String
    public var priority: SupplementalContextPriority
    public var confidence: Double
    public var isAccepted: Bool

    public init(
        id: String,
        kind: SupplementalContextKind,
        title: String,
        sourceName: String,
        excerpt: String,
        priority: SupplementalContextPriority,
        confidence: Double,
        isAccepted: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceName = sourceName
        self.excerpt = excerpt
        self.priority = priority
        self.confidence = min(1, max(0, confidence))
        self.isAccepted = isAccepted
    }
}

public struct MeetingIdentity: Codable, Equatable, Sendable {
    public var calendarEventID: String?
    public var recurrenceID: String?
    public var fallbackFingerprint: String
    public var confidence: Double
    public var isConfirmed: Bool

    public init(
        calendarEventID: String? = nil,
        recurrenceID: String? = nil,
        fallbackFingerprint: String,
        confidence: Double,
        isConfirmed: Bool = false
    ) {
        self.calendarEventID = calendarEventID
        self.recurrenceID = recurrenceID
        self.fallbackFingerprint = fallbackFingerprint
        self.confidence = min(1, max(0, confidence))
        self.isConfirmed = isConfirmed
    }

    public var seriesKey: String {
        if let recurrenceID, !recurrenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "calendar:\(recurrenceID)"
        }
        return "fingerprint:\(fallbackFingerprint)"
    }
}

public struct CalendarContextState: Codable, Equatable, Sendable {
    public var mcpStatus: CalendarMCPStatus
    public var eventCandidates: [CalendarEventCandidate]
    public var supplementalSources: [SupplementalContextSource]
    public var meetingIdentity: MeetingIdentity?
    public var lastFetchedAt: Date?
    public var lastError: String?

    public init(
        mcpStatus: CalendarMCPStatus = .unknown,
        eventCandidates: [CalendarEventCandidate] = [],
        supplementalSources: [SupplementalContextSource] = [],
        meetingIdentity: MeetingIdentity? = nil,
        lastFetchedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.mcpStatus = mcpStatus
        self.eventCandidates = eventCandidates
        self.supplementalSources = supplementalSources
        self.meetingIdentity = meetingIdentity
        self.lastFetchedAt = lastFetchedAt
        self.lastError = lastError
    }

    public var hasReusableContext: Bool {
        !eventCandidates.isEmpty || !supplementalSources.isEmpty || meetingIdentity != nil
    }

    public func cachedForTestRunReplay() -> CalendarContextState {
        guard hasReusableContext else {
            return CalendarContextState()
        }

        return CalendarContextState(
            mcpStatus: .cachedReplay,
            eventCandidates: eventCandidates,
            supplementalSources: supplementalSources,
            meetingIdentity: meetingIdentity,
            lastFetchedAt: lastFetchedAt,
            lastError: nil
        )
    }
}

public extension Array where Element == SupplementalContextSource {
    func sortedForPrompt() -> [SupplementalContextSource] {
        filter { $0.isAccepted && !$0.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.confidence > $1.confidence
                }
                return $0.priority < $1.priority
            }
    }
}
