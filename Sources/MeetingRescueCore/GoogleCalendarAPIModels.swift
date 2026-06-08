import Foundation

public struct GoogleCalendarEventsListRequest: Equatable, Sendable {
    public var calendarID: String
    public var timeMin: String
    public var timeMax: String
    public var maxResults: Int

    public init(
        calendarID: String = "primary",
        timeMin: String,
        timeMax: String,
        maxResults: Int = 10
    ) {
        self.calendarID = calendarID
        self.timeMin = timeMin
        self.timeMax = timeMax
        self.maxResults = max(1, min(2_500, maxResults))
    }

    public func url() throws -> URL {
        guard let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .calendarPathComponentAllowed) else {
            throw GoogleCalendarAPIError.invalidRequestURL
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = "/calendar/v3/calendars/\(encodedCalendarID)/events"
        components.percentEncodedQuery = Self.percentEncodedQuery([
            ("timeMin", timeMin),
            ("timeMax", timeMax),
            ("singleEvents", "true"),
            ("orderBy", "startTime"),
            ("maxResults", String(maxResults))
        ])

        guard let url = components.url else {
            throw GoogleCalendarAPIError.invalidRequestURL
        }
        return url
    }

    private static func percentEncodedQuery(_ values: [(String, String)]) -> String {
        values
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .calendarQueryAllowed) ?? value
    }
}

public struct GoogleCalendarEventsListResponse: Codable, Equatable, Sendable {
    public var items: [GoogleCalendarEvent]

    public init(items: [GoogleCalendarEvent] = []) {
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: (try? container.decode([GoogleCalendarEvent].self, forKey: .items)) ?? [])
    }
}

public struct GoogleCalendarEvent: Codable, Equatable, Sendable {
    public var id: String
    public var summary: String
    public var start: GoogleCalendarEventTime
    public var end: GoogleCalendarEventTime
    public var organizer: GoogleCalendarPerson?
    public var attendees: [GoogleCalendarPerson]
    public var location: String?
    public var description: String?
    public var recurringEventID: String?

    public init(
        id: String,
        summary: String,
        start: GoogleCalendarEventTime,
        end: GoogleCalendarEventTime,
        organizer: GoogleCalendarPerson? = nil,
        attendees: [GoogleCalendarPerson] = [],
        location: String? = nil,
        description: String? = nil,
        recurringEventID: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.start = start
        self.end = end
        self.organizer = organizer
        self.attendees = attendees
        self.location = location
        self.description = description
        self.recurringEventID = recurringEventID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case summary
        case start
        case end
        case organizer
        case attendees
        case location
        case description
        case recurringEventID = "recurringEventId"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decode(String.self, forKey: .id)) ?? "",
            summary: (try? container.decode(String.self, forKey: .summary)) ?? "",
            start: (try? container.decode(GoogleCalendarEventTime.self, forKey: .start)) ?? GoogleCalendarEventTime(),
            end: (try? container.decode(GoogleCalendarEventTime.self, forKey: .end)) ?? GoogleCalendarEventTime(),
            organizer: try container.decodeIfPresent(GoogleCalendarPerson.self, forKey: .organizer),
            attendees: (try? container.decode([GoogleCalendarPerson].self, forKey: .attendees)) ?? [],
            location: try container.decodeIfPresent(String.self, forKey: .location),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            recurringEventID: try container.decodeIfPresent(String.self, forKey: .recurringEventID)
        )
    }
}

public struct GoogleCalendarEventTime: Codable, Equatable, Sendable {
    public var dateTime: String?
    public var date: String?

    public init(dateTime: String? = nil, date: String? = nil) {
        self.dateTime = dateTime
        self.date = date
    }

    public var displayText: String {
        dateTime ?? date ?? ""
    }
}

public struct GoogleCalendarPerson: Codable, Equatable, Sendable {
    public var email: String?
    public var displayName: String?

    public init(email: String? = nil, displayName: String? = nil) {
        self.email = email
        self.displayName = displayName
    }

    public var displayText: String {
        email ?? displayName ?? ""
    }
}

public enum GoogleCalendarAPIError: Error, Equatable, Sendable {
    case invalidRequestURL
}

private extension CharacterSet {
    static let calendarPathComponentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    static let calendarQueryAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
