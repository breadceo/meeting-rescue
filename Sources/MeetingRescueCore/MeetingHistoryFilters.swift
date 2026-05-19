import Foundation

public enum MeetingHistoryDateFacet: String, CaseIterable, Equatable, Sendable {
    case all
    case today
    case last7Days
    case last30Days

    public var displayName: String {
        switch self {
        case .all:
            return "전체 기간"
        case .today:
            return "오늘"
        case .last7Days:
            return "최근 7일"
        case .last30Days:
            return "최근 30일"
        }
    }
}

public enum MeetingHistoryCompletionFacet: String, CaseIterable, Equatable, Sendable {
    case all
    case completed
    case active

    public var displayName: String {
        switch self {
        case .all:
            return "전체 상태"
        case .completed:
            return "완료"
        case .active:
            return "진행 중"
        }
    }
}

public enum MeetingHistoryCandidateFacet: String, CaseIterable, Equatable, Sendable {
    case all
    case hasDecision
    case hasAction
    case hasDecisionOrAction

    public var displayName: String {
        switch self {
        case .all:
            return "후보 전체"
        case .hasDecision:
            return "결정 있음"
        case .hasAction:
            return "액션 있음"
        case .hasDecisionOrAction:
            return "결정/액션 있음"
        }
    }
}

public struct MeetingHistoryFilterDocument: Equatable, Sendable {
    public var modificationDate: Date
    public var participants: [String]
    public var room: String?
    public var isCompleted: Bool
    public var decisionCount: Int
    public var actionCount: Int

    public init(
        modificationDate: Date,
        participants: [String],
        room: String?,
        isCompleted: Bool,
        decisionCount: Int,
        actionCount: Int
    ) {
        self.modificationDate = modificationDate
        self.participants = participants
        self.room = room
        self.isCompleted = isCompleted
        self.decisionCount = decisionCount
        self.actionCount = actionCount
    }
}

public struct MeetingHistoryFacetSelection: Equatable, Sendable {
    public var date: MeetingHistoryDateFacet
    public var participant: String?
    public var room: String?
    public var completion: MeetingHistoryCompletionFacet
    public var candidate: MeetingHistoryCandidateFacet

    public init(
        date: MeetingHistoryDateFacet = .all,
        participant: String? = nil,
        room: String? = nil,
        completion: MeetingHistoryCompletionFacet = .all,
        candidate: MeetingHistoryCandidateFacet = .all
    ) {
        self.date = date
        self.participant = participant
        self.room = room
        self.completion = completion
        self.candidate = candidate
    }

    public var hasActiveFilters: Bool {
        date != .all
            || participant?.isEmpty == false
            || room?.isEmpty == false
            || completion != .all
            || candidate != .all
    }

    public func matches(
        _ document: MeetingHistoryFilterDocument,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        matchesDate(document.modificationDate, now: now, calendar: calendar)
            && matchesParticipant(document.participants)
            && matchesRoom(document.room)
            && matchesCompletion(document.isCompleted)
            && matchesCandidate(decisionCount: document.decisionCount, actionCount: document.actionCount)
    }

    private func matchesDate(_ dateValue: Date, now: Date, calendar: Calendar) -> Bool {
        switch date {
        case .all:
            return true
        case .today:
            return calendar.isDate(dateValue, inSameDayAs: now)
        case .last7Days:
            return dateValue >= calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            return dateValue >= calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
    }

    private func matchesParticipant(_ participants: [String]) -> Bool {
        guard let participant, !participant.isEmpty else {
            return true
        }
        return participants.contains(participant)
    }

    private func matchesRoom(_ documentRoom: String?) -> Bool {
        guard let room, !room.isEmpty else {
            return true
        }
        return documentRoom == room
    }

    private func matchesCompletion(_ isCompleted: Bool) -> Bool {
        switch completion {
        case .all:
            return true
        case .completed:
            return isCompleted
        case .active:
            return !isCompleted
        }
    }

    private func matchesCandidate(decisionCount: Int, actionCount: Int) -> Bool {
        switch candidate {
        case .all:
            return true
        case .hasDecision:
            return decisionCount > 0
        case .hasAction:
            return actionCount > 0
        case .hasDecisionOrAction:
            return decisionCount > 0 || actionCount > 0
        }
    }
}
