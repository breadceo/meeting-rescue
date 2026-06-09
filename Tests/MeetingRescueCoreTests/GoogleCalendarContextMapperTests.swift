import Foundation
import Testing
@testable import MeetingRescueCore

struct GoogleCalendarContextMapperTests {
    @Test("Google event는 CalendarEventCandidate와 supplemental source로 변환된다")
    func mapsEventsToCalendarContextState() throws {
        let response = GoogleCalendarEventsListResponse(items: [
            GoogleCalendarEvent(
                id: "event-1",
                summary: "Weekly Product Sync",
                start: GoogleCalendarEventTime(dateTime: "2026-06-08T11:00:00+09:00"),
                end: GoogleCalendarEventTime(dateTime: "2026-06-08T12:00:00+09:00"),
                organizer: GoogleCalendarPerson(email: "owner@example.com"),
                attendees: [
                    GoogleCalendarPerson(email: "owner@example.com"),
                    GoogleCalendarPerson(displayName: "Ethan")
                ],
                location: "Zigbang(2F)_Meeting Room L3",
                description: String(repeating: "agenda ", count: 400),
                recurringEventID: "series-1"
            )
        ])
        let metadata = MeetingMetadata(
            room: "Zigbang(2F)_Meeting Room L3",
            dateTime: "2026-06-08 11:05",
            participants: ["Ethan"]
        )

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: metadata,
            meetingStart: ISO8601DateFormatter().date(from: "2026-06-08T11:00:00+09:00"),
            meetingEnd: ISO8601DateFormatter().date(from: "2026-06-08T12:00:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        let candidate = try #require(state.eventCandidates.first)
        #expect(state.mcpStatus == .connected)
        #expect(candidate.id == "google:event-1")
        #expect(candidate.title == "Weekly Product Sync")
        #expect(candidate.startDateText == "2026-06-08T11:00:00+09:00")
        #expect(candidate.endDateText == "2026-06-08T12:00:00+09:00")
        #expect(candidate.organizer == "owner@example.com")
        #expect(candidate.attendees == ["owner@example.com", "Ethan"])
        #expect(candidate.recurrenceID == "series-1")
        #expect(candidate.descriptionExcerpt.count <= 1_200)
        #expect(candidate.confidence >= 0.85)
        #expect(candidate.status == .accepted)
        #expect(state.meetingIdentity?.seriesKey == "calendar:series-1")

        let source = try #require(state.supplementalSources.first)
        #expect(source.id == "calendar:google:event-1")
        #expect(source.kind == .calendarMetadata)
        #expect(source.priority == .calendarMetadata)
        #expect(source.excerpt.contains("Weekly Product Sync"))
        #expect(source.excerpt.contains("Zigbang(2F)_Meeting Room L3"))
    }

    @Test("room이 다르면 같은 시간대여도 낮은 confidence candidate로 유지한다")
    func keepsLowConfidenceCandidateWhenRoomDiffers() throws {
        let response = GoogleCalendarEventsListResponse(items: [
            GoogleCalendarEvent(
                id: "event-2",
                summary: "Weekly Product Sync",
                start: GoogleCalendarEventTime(dateTime: "2026-06-08T11:00:00+09:00"),
                end: GoogleCalendarEventTime(dateTime: "2026-06-08T12:00:00+09:00"),
                location: "Zigbang(2F)",
                recurringEventID: "series-2"
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3", dateTime: "2026-06-08 11:05"),
            meetingStart: ISO8601DateFormatter().date(from: "2026-06-08T11:00:00+09:00"),
            meetingEnd: ISO8601DateFormatter().date(from: "2026-06-08T12:00:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        let candidate = try #require(state.eventCandidates.first)
        #expect(candidate.confidence < 0.75)
        #expect(candidate.status == .candidate)
        #expect(state.meetingIdentity == nil)
        #expect(state.supplementalSources.isEmpty)
    }

    @Test("calendar title에 active room code가 있으면 recurring event를 자동 accepted로 승격한다")
    func acceptsRecurringEventWhenRoomCodeAppearsInCalendarTitle() throws {
        let response = GoogleCalendarEventsListResponse(items: [
            event(
                id: "evt-recurring-r3",
                summary: "[table:HD-R3] Weekly Product Sync",
                start: "2026-06-09T10:30:00+09:00",
                end: "2026-06-09T11:00:00+09:00",
                attendees: [person(email: "ethan@example.com")],
                location: nil,
                description: "Notes: https://docs.example.com/meeting-r3",
                recurringEventID: "series-product-sync"
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(
                room: "Zigbang(2F)_R3",
                dateTime: "2026-06-09 10:32",
                participants: ["ethan@example.com"]
            ),
            meetingStart: date("2026-06-09T10:32:36+09:00"),
            meetingEnd: date("2026-06-09T11:02:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        let candidate = try #require(state.eventCandidates.first)
        #expect(candidate.id == "google:evt-recurring-r3")
        #expect(candidate.status == .accepted)
        #expect(state.meetingIdentity?.seriesKey == "calendar:series-product-sync")
        #expect(state.supplementalSources.first?.kind == .calendarMetadata)
        #expect(state.supplementalSources.contains { $0.kind == .linkedSourceCandidate })
    }

    @Test("all-day나 긴 generic busy event는 시간대가 겹쳐도 accepted로 승격하지 않는다")
    func doesNotAcceptAllDayOrLongBusyEventsAroundMeeting() {
        let response = GoogleCalendarEventsListResponse(items: [
            event(
                id: "evt-all-day",
                summary: "Office Day",
                startDate: "2026-06-09",
                endDate: "2026-06-10",
                attendees: [],
                location: "Zigbang(2F)",
                description: nil,
                recurringEventID: nil
            ),
            event(
                id: "evt-work-block",
                summary: "Work from office",
                start: "2026-06-09T09:30:00+09:00",
                end: "2026-06-09T18:30:00+09:00",
                attendees: [person(email: "ethan@example.com")],
                location: "Zigbang(2F)",
                description: nil,
                recurringEventID: nil
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(
                room: "Zigbang(2F)_R3",
                dateTime: "2026-06-09 10:32",
                participants: ["ethan@example.com"]
            ),
            meetingStart: date("2026-06-09T10:32:36+09:00"),
            meetingEnd: date("2026-06-09T11:02:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(!state.eventCandidates.contains { $0.status == .accepted })
        #expect(state.meetingIdentity == nil)
        #expect(state.supplementalSources.isEmpty)
    }

    @Test("다른 room code는 recurring event여도 candidate로 유지한다")
    func keepsDifferentRoomCodeCandidateOnly() throws {
        let response = GoogleCalendarEventsListResponse(items: [
            event(
                id: "evt-l3",
                summary: "[table:HD-L3] Weekly Product Sync",
                start: "2026-06-09T10:30:00+09:00",
                end: "2026-06-09T11:00:00+09:00",
                attendees: [person(email: "ethan@example.com")],
                location: nil,
                description: nil,
                recurringEventID: "series-product-sync"
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(
                room: "Zigbang(2F)_R3",
                dateTime: "2026-06-09 10:32",
                participants: ["ethan@example.com"]
            ),
            meetingStart: date("2026-06-09T10:32:36+09:00"),
            meetingEnd: date("2026-06-09T11:02:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        let candidate = try #require(state.eventCandidates.first)
        #expect(candidate.status == .candidate)
        #expect(state.meetingIdentity == nil)
        #expect(state.supplementalSources.isEmpty)
    }

    @Test("specific recurring room title match가 긴 busy overlap보다 먼저 accepted된다")
    func prefersSpecificRecurringRoomTitleMatchOverLongBusyOverlap() throws {
        let response = GoogleCalendarEventsListResponse(items: [
            event(
                id: "evt-work-block",
                summary: "Work from office",
                start: "2026-06-09T09:30:00+09:00",
                end: "2026-06-09T18:30:00+09:00",
                attendees: [person(email: "ethan@example.com")],
                location: "Zigbang(2F)",
                description: nil,
                recurringEventID: nil
            ),
            event(
                id: "evt-recurring-r3",
                summary: "[table:HD-R3] Weekly Product Sync",
                start: "2026-06-09T10:30:00+09:00",
                end: "2026-06-09T11:00:00+09:00",
                attendees: [person(email: "ethan@example.com")],
                location: nil,
                description: nil,
                recurringEventID: "series-product-sync"
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(
                room: "Zigbang(2F)_R3",
                dateTime: "2026-06-09 10:32",
                participants: ["ethan@example.com"]
            ),
            meetingStart: date("2026-06-09T10:32:36+09:00"),
            meetingEnd: date("2026-06-09T11:02:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        let first = try #require(state.eventCandidates.first)
        #expect(first.id == "google:evt-recurring-r3")
        #expect(first.status == .accepted)
        #expect(state.meetingIdentity?.seriesKey == "calendar:series-product-sync")
        #expect(state.eventCandidates.dropFirst().allSatisfy { $0.status == .candidate })
    }

    @Test("exact room and time match outranks participant-only overlap")
    func exactRoomAndTimeOutranksParticipantOnlyOverlap() throws {
        let response = GoogleCalendarEventsListResponse(items: [
            GoogleCalendarEvent(
                id: "participant-title-only",
                summary: "Product Planning",
                start: GoogleCalendarEventTime(dateTime: "2026-06-08T11:00:00+09:00"),
                end: GoogleCalendarEventTime(dateTime: "2026-06-08T12:00:00+09:00"),
                attendees: [GoogleCalendarPerson(displayName: "Ethan")],
                location: "Zigbang(2F)"
            ),
            GoogleCalendarEvent(
                id: "exact-room-time",
                summary: "Different Calendar Title",
                start: GoogleCalendarEventTime(dateTime: "2026-06-08T11:00:00+09:00"),
                end: GoogleCalendarEventTime(dateTime: "2026-06-08T12:00:00+09:00"),
                location: "Zigbang(2F)_Meeting Room L3"
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(
                room: "Zigbang(2F)_Meeting Room L3",
                dateTime: "2026-06-08 11:05",
                participants: ["Ethan"]
            ),
            meetingStart: ISO8601DateFormatter().date(from: "2026-06-08T11:00:00+09:00"),
            meetingEnd: ISO8601DateFormatter().date(from: "2026-06-08T12:00:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(Array(state.eventCandidates.map(\.id).prefix(2)) == ["google:exact-room-time", "google:participant-title-only"])
        #expect(state.eventCandidates[0].status == CalendarContextCandidateStatus.accepted)
        #expect(state.eventCandidates[1].status == CalendarContextCandidateStatus.candidate)
        #expect(state.meetingIdentity?.calendarEventID == "google:exact-room-time")
    }

    @Test("events without useful overlap are not surfaced as calendar candidates")
    func dropsEventsWithoutUsefulOverlap() {
        let response = GoogleCalendarEventsListResponse(items: [
            GoogleCalendarEvent(
                id: "irrelevant",
                summary: "Unrelated Offsite",
                start: GoogleCalendarEventTime(dateTime: "2026-06-08T15:00:00+09:00"),
                end: GoogleCalendarEventTime(dateTime: "2026-06-08T16:00:00+09:00"),
                attendees: [GoogleCalendarPerson(displayName: "Morgan")],
                location: "Other Room"
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(
                room: "Zigbang(2F)_Meeting Room L3",
                dateTime: "2026-06-08 11:05",
                participants: ["Ethan"]
            ),
            meetingStart: ISO8601DateFormatter().date(from: "2026-06-08T11:00:00+09:00"),
            meetingEnd: ISO8601DateFormatter().date(from: "2026-06-08T12:00:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(state.eventCandidates.isEmpty)
        #expect(state.meetingIdentity == nil)
        #expect(state.supplementalSources.isEmpty)
    }

    @Test("calendar description links become unaccepted supplemental context candidates")
    func mapsDescriptionLinksToSupplementalContextCandidates() throws {
        let response = GoogleCalendarEventsListResponse(items: [
            GoogleCalendarEvent(
                id: "link-rich",
                summary: "Weekly Product Sync",
                start: GoogleCalendarEventTime(dateTime: "2026-06-08T11:00:00+09:00"),
                end: GoogleCalendarEventTime(dateTime: "2026-06-08T12:00:00+09:00"),
                location: "Zigbang(2F)_Meeting Room L3",
                description: """
                Agenda:
                - review open launch questions
                Spec: https://docs.google.com/document/d/sanitized-doc-id/edit
                Board: https://example.com/team/board?item=42
                """
            )
        ])

        let state = GoogleCalendarContextMapper.map(
            response,
            metadata: MeetingMetadata(room: "Zigbang(2F)_Meeting Room L3", dateTime: "2026-06-08 11:05"),
            meetingStart: ISO8601DateFormatter().date(from: "2026-06-08T11:00:00+09:00"),
            meetingEnd: ISO8601DateFormatter().date(from: "2026-06-08T12:00:00+09:00"),
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )

        let linkedSources = state.supplementalSources.filter { $0.kind == .linkedSourceCandidate }
        #expect(linkedSources.count == 2)
        #expect(linkedSources.allSatisfy { !$0.isAccepted })
        #expect(linkedSources.map(\.excerpt).contains("https://docs.google.com/document/d/sanitized-doc-id/edit"))
        #expect(linkedSources.map(\.excerpt).contains("https://example.com/team/board?item=42"))
        #expect(linkedSources.allSatisfy { $0.priority == .linkedSourceCandidate })
    }

    private func event(
        id: String,
        summary: String,
        start: String? = nil,
        end: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        attendees: [GoogleCalendarPerson],
        location: String?,
        description: String?,
        recurringEventID: String?
    ) -> GoogleCalendarEvent {
        GoogleCalendarEvent(
            id: id,
            summary: summary,
            start: GoogleCalendarEventTime(dateTime: start, date: startDate),
            end: GoogleCalendarEventTime(dateTime: end, date: endDate),
            attendees: attendees,
            location: location,
            description: description,
            recurringEventID: recurringEventID
        )
    }

    private func person(email: String? = nil, displayName: String? = nil) -> GoogleCalendarPerson {
        GoogleCalendarPerson(email: email, displayName: displayName)
    }

    private func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
