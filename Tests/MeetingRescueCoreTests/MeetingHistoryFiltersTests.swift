import Foundation
import Testing
@testable import MeetingRescueCore

@Suite("Meeting history filters")
struct MeetingHistoryFiltersTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_715_731_200) // 2024-05-15 00:00:00 UTC

    @Test("date facet filters by today and recent ranges")
    func dateFacetFiltersByRange() {
        let today = document(daysAgo: 0)
        let older = document(daysAgo: 12)

        let todaySelection = MeetingHistoryFacetSelection(date: .today)
        let weekSelection = MeetingHistoryFacetSelection(date: .last7Days)
        let monthSelection = MeetingHistoryFacetSelection(date: .last30Days)

        #expect(todaySelection.matches(today, now: now, calendar: calendar))
        #expect(!todaySelection.matches(older, now: now, calendar: calendar))
        #expect(!weekSelection.matches(older, now: now, calendar: calendar))
        #expect(monthSelection.matches(older, now: now, calendar: calendar))
    }

    @Test("participant and room facets require exact metadata matches")
    func participantAndRoomFacetsUseMetadata() {
        let document = document(participants: ["Alex", "Mina"], room: "L17")

        let matching = MeetingHistoryFacetSelection(participant: "Alex", room: "L17")
        let wrongRoom = MeetingHistoryFacetSelection(participant: "Alex", room: "R2")
        let wrongParticipant = MeetingHistoryFacetSelection(participant: "Sam", room: "L17")

        #expect(matching.matches(document, now: now, calendar: calendar))
        #expect(!wrongRoom.matches(document, now: now, calendar: calendar))
        #expect(!wrongParticipant.matches(document, now: now, calendar: calendar))
    }

    @Test("completion and candidate facets filter meeting state")
    func completionAndCandidateFacetsFilterState() {
        let completedWithDecision = document(isCompleted: true, decisionCount: 2, actionCount: 0)
        let activeWithAction = document(isCompleted: false, decisionCount: 0, actionCount: 1)

        let completed = MeetingHistoryFacetSelection(completion: .completed)
        let active = MeetingHistoryFacetSelection(completion: .active)
        let hasDecision = MeetingHistoryFacetSelection(candidate: .hasDecision)
        let hasAction = MeetingHistoryFacetSelection(candidate: .hasAction)
        let hasEither = MeetingHistoryFacetSelection(candidate: .hasDecisionOrAction)

        #expect(completed.matches(completedWithDecision, now: now, calendar: calendar))
        #expect(!completed.matches(activeWithAction, now: now, calendar: calendar))
        #expect(active.matches(activeWithAction, now: now, calendar: calendar))
        #expect(hasDecision.matches(completedWithDecision, now: now, calendar: calendar))
        #expect(!hasDecision.matches(activeWithAction, now: now, calendar: calendar))
        #expect(hasAction.matches(activeWithAction, now: now, calendar: calendar))
        #expect(hasEither.matches(completedWithDecision, now: now, calendar: calendar))
        #expect(hasEither.matches(activeWithAction, now: now, calendar: calendar))
    }

    private func document(
        daysAgo: Int = 0,
        participants: [String] = ["Alex"],
        room: String? = "L17",
        isCompleted: Bool = false,
        decisionCount: Int = 0,
        actionCount: Int = 0
    ) -> MeetingHistoryFilterDocument {
        MeetingHistoryFilterDocument(
            modificationDate: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
            participants: participants,
            room: room,
            isCompleted: isCompleted,
            decisionCount: decisionCount,
            actionCount: actionCount
        )
    }
}
