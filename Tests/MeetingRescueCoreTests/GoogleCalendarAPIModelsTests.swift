import Foundation
import Testing
@testable import MeetingRescueCore

struct GoogleCalendarAPIModelsTests {
    @Test("events.list request는 현재 회의 window를 query parameter로 만든다")
    func buildsEventsListURL() throws {
        let request = GoogleCalendarEventsListRequest(
            calendarID: "primary",
            timeMin: "2026-06-08T10:45:00+09:00",
            timeMax: "2026-06-08T12:30:00+09:00",
            maxResults: 10
        )

        let url = try request.url()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(components.scheme == "https")
        #expect(components.host == "www.googleapis.com")
        #expect(components.path == "/calendar/v3/calendars/primary/events")
        #expect(url.absoluteString.contains("timeMin=2026-06-08T10%3A45%3A00%2B09%3A00"))
        #expect(url.absoluteString.contains("timeMax=2026-06-08T12%3A30%3A00%2B09%3A00"))
        #expect(queryItems["timeMin"] == "2026-06-08T10:45:00+09:00")
        #expect(queryItems["timeMax"] == "2026-06-08T12:30:00+09:00")
        #expect(queryItems["singleEvents"] == "true")
        #expect(queryItems["orderBy"] == "startTime")
        #expect(queryItems["maxResults"] == "10")
    }

    @Test("Google Calendar event response는 timed, all-day, recurring event를 decode한다")
    func decodesEventsListResponse() throws {
        let json = """
        {
          "items": [
            {
              "id": "timed-1",
              "summary": "Weekly Product Sync",
              "start": {"dateTime": "2026-06-08T11:00:00+09:00"},
              "end": {"dateTime": "2026-06-08T12:00:00+09:00"},
              "organizer": {"email": "owner@example.com"},
              "attendees": [
                {"email": "owner@example.com"},
                {"displayName": "Teammate"}
              ],
              "location": "Zigbang(2F)_Meeting Room L3",
              "description": "Agenda",
              "recurringEventId": "series-1"
            },
            {
              "id": "all-day-1",
              "summary": "Focus Day",
              "start": {"date": "2026-06-08"},
              "end": {"date": "2026-06-09"}
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(GoogleCalendarEventsListResponse.self, from: Data(json.utf8))

        #expect(response.items.count == 2)
        #expect(response.items[0].id == "timed-1")
        #expect(response.items[0].summary == "Weekly Product Sync")
        #expect(response.items[0].start.displayText == "2026-06-08T11:00:00+09:00")
        #expect(response.items[0].end.displayText == "2026-06-08T12:00:00+09:00")
        #expect(response.items[0].organizer?.displayText == "owner@example.com")
        #expect(response.items[0].attendees.map(\.displayText) == ["owner@example.com", "Teammate"])
        #expect(response.items[0].location == "Zigbang(2F)_Meeting Room L3")
        #expect(response.items[0].description == "Agenda")
        #expect(response.items[0].recurringEventID == "series-1")
        #expect(response.items[1].start.displayText == "2026-06-08")
        #expect(response.items[1].end.displayText == "2026-06-09")
    }
}
