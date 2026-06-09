import Foundation

public enum GoogleCalendarContextMapper {
    public static func map(
        _ response: GoogleCalendarEventsListResponse,
        metadata: MeetingMetadata,
        meetingStart: Date?,
        meetingEnd: Date?,
        fetchedAt: Date = Date()
    ) -> CalendarContextState {
        let mapped = response.items.compactMap { event -> MappedCalendarCandidate? in
            let details = matchDetails(
                for: event,
                metadata: metadata,
                meetingStart: meetingStart,
                meetingEnd: meetingEnd
            )
            guard details.confidence > 0.1 else {
                return nil
            }
            return MappedCalendarCandidate(
                candidate: CalendarEventCandidate(
                    id: "google:\(event.id)",
                    title: event.summary,
                    startDateText: event.start.displayText,
                    endDateText: event.end.displayText,
                    organizer: event.organizer?.displayText.nonEmpty,
                    attendees: event.attendees.map(\.displayText).filter { !$0.isEmpty },
                    descriptionExcerpt: (event.description ?? "").capped(at: 1_200),
                    recurrenceID: event.recurringEventID,
                    confidence: details.confidence,
                    status: details.shouldAutoAccept ? .accepted : .candidate
                ),
                details: details
            )
        }
        let sorted = mapped.sorted { lhs, rhs in
            if lhs.candidate.status != rhs.candidate.status {
                return lhs.candidate.status == .accepted
            }
            if lhs.candidate.confidence != rhs.candidate.confidence {
                return lhs.candidate.confidence > rhs.candidate.confidence
            }
            return lhs.candidate.startDateText < rhs.candidate.startDateText
        }
        let acceptedID = sorted.first { $0.candidate.status == .accepted }?.candidate.id
            ?? defaultAcceptedCandidateID(in: sorted)
        let normalizedCandidates = sorted.map { mappedCandidate in
            var candidate = mappedCandidate.candidate
            if let acceptedID, candidate.id == acceptedID {
                candidate.status = .accepted
                return candidate
            }
            if candidate.status == .accepted {
                candidate.status = .candidate
            }
            return candidate
        }
        let accepted = normalizedCandidates.first { $0.status == .accepted }

        return CalendarContextState(
            mcpStatus: .connected,
            eventCandidates: normalizedCandidates,
            supplementalSources: accepted.map { candidate in
                [supplementalSource(for: candidate, location: location(for: candidate, in: response))]
                    + linkedSourceCandidates(for: candidate)
            } ?? [],
            meetingIdentity: accepted.map {
                MeetingIdentity(
                    calendarEventID: $0.id,
                    recurrenceID: $0.recurrenceID,
                    fallbackFingerprint: fallbackFingerprint(metadata: metadata),
                    confidence: $0.confidence,
                    isConfirmed: true
                )
            },
            lastFetchedAt: fetchedAt,
            lastError: nil
        )
    }

    public static func confidence(
        for event: GoogleCalendarEvent,
        metadata: MeetingMetadata,
        meetingStart: Date?,
        meetingEnd: Date?
    ) -> Double {
        matchDetails(
            for: event,
            metadata: metadata,
            meetingStart: meetingStart,
            meetingEnd: meetingEnd
        ).confidence
    }

    private static func defaultAcceptedCandidateID(in sorted: [MappedCalendarCandidate]) -> String? {
        guard let best = sorted.first else {
            return nil
        }

        let details = best.details
        guard details.hasSpecificTimedOverlap,
              !details.isAllDay,
              !details.hasRoomCodeConflict,
              details.confidence >= 0.50,
              details.roomSignal.isStrong || details.hasParticipantOverlap || details.hasTitleOverlap else {
            return nil
        }

        if let second = sorted.dropFirst().first,
           details.confidence - second.details.confidence < 0.20 {
            return nil
        }

        return best.candidate.id
    }

    private static func supplementalSource(for candidate: CalendarEventCandidate, location: String?) -> SupplementalContextSource {
        SupplementalContextSource(
            id: "calendar:\(candidate.id)",
            kind: .calendarMetadata,
            title: candidate.title,
            sourceName: "Google Calendar",
            excerpt: calendarExcerpt(candidate, location: location),
            priority: .calendarMetadata,
            confidence: candidate.confidence
        )
    }

    private static func calendarExcerpt(_ candidate: CalendarEventCandidate, location: String?) -> String {
        [
            "title: \(candidate.title)",
            "time: \(candidate.startDateText)-\(candidate.endDateText)",
            location?.nonEmpty.map { "location: \($0)" },
            candidate.organizer.map { "organizer: \($0)" },
            candidate.attendees.isEmpty ? nil : "attendees: \(candidate.attendees.joined(separator: ", "))",
            candidate.descriptionExcerpt.isEmpty ? nil : "description: \(candidate.descriptionExcerpt)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private static func linkedSourceCandidates(for candidate: CalendarEventCandidate) -> [SupplementalContextSource] {
        links(in: candidate.descriptionExcerpt).enumerated().map { index, link in
            SupplementalContextSource(
                id: "calendar-link:\(candidate.id):\(index + 1)",
                kind: .linkedSourceCandidate,
                title: linkTitle(for: link, index: index),
                sourceName: sourceName(for: link),
                excerpt: link,
                priority: .linkedSourceCandidate,
                confidence: candidate.confidence,
                isAccepted: false
            )
        }
    }

    private static func links(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>)"]+"#) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        var links: [String] = []
        for match in matches {
            guard let matchRange = Range(match.range, in: value) else {
                continue
            }
            let link = String(value[matchRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?]}'\""))
            if !links.contains(link) {
                links.append(link)
            }
        }
        return links
    }

    private static func sourceName(for link: String) -> String {
        guard let host = URL(string: link)?.host?.lowercased() else {
            return "Calendar Link"
        }
        if host.contains("docs.google.com") {
            return "Google Docs"
        }
        if host.contains("slack.com") {
            return "Slack"
        }
        if host.contains("atlassian.net") || host.contains("jira") {
            return "Jira"
        }
        return host
    }

    private static func linkTitle(for link: String, index: Int) -> String {
        if let host = URL(string: link)?.host, !host.isEmpty {
            return "Calendar linked source \(index + 1): \(host)"
        }
        return "Calendar linked source \(index + 1)"
    }

    private static func location(for candidate: CalendarEventCandidate, in response: GoogleCalendarEventsListResponse) -> String? {
        let eventID = candidate.id.replacingOccurrences(of: "google:", with: "")
        return response.items.first(where: { $0.id == eventID })?.location
    }

    private static func overlaps(event: GoogleCalendarEvent, meetingStart: Date?, meetingEnd: Date?) -> Bool {
        guard let meetingStart,
              let meetingEnd,
              let eventStart = parseDate(event.start.displayText),
              let eventEnd = parseDate(event.end.displayText) else {
            return false
        }
        return eventStart < meetingEnd && eventEnd > meetingStart
    }

    private static func matchDetails(
        for event: GoogleCalendarEvent,
        metadata: MeetingMetadata,
        meetingStart: Date?,
        meetingEnd: Date?
    ) -> CalendarEventMatchDetails {
        let timeOverlap = overlaps(event: event, meetingStart: meetingStart, meetingEnd: meetingEnd)
        let room = roomSignal(event: event, metadataRoom: metadata.room)
        let roomConflict = roomCodeConflict(event: event, metadataRoom: metadata.room)
        let specificTimedOverlap = hasSpecificTimedOverlap(
            event: event,
            meetingStart: meetingStart,
            meetingEnd: meetingEnd,
            roomSignal: room
        )
        let participant = participantOverlap(
            eventAttendees: event.attendees,
            metadataParticipants: metadata.participants
        )
        let title = titleOverlap(eventTitle: event.summary, metadataTitle: metadata.displayTitle)
        let allDay = isAllDay(event)
        let long = isLongEvent(event)
        let recurring = !(event.recurringEventID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        var score = 0.05
        if timeOverlap {
            score += specificTimedOverlap ? 0.35 : 0.18
        }
        score += room.score
        if participant {
            score += 0.10
        }
        if title {
            score += 0.08
        }
        if recurring {
            score += 0.07
        }
        if allDay {
            score -= 0.30
        } else if long && !room.isStrong {
            score -= 0.20
        }

        let confidence = min(1, max(0, score))
        let recurringParticipantTitleSignal = recurring && participant && title
        let shouldAutoAccept = specificTimedOverlap
            && confidence >= 0.80
            && !allDay
            && !roomConflict
            && (room.isStrong || recurringParticipantTitleSignal)

        return CalendarEventMatchDetails(
            confidence: confidence,
            shouldAutoAccept: shouldAutoAccept,
            roomSignal: room,
            hasTimeOverlap: timeOverlap,
            hasSpecificTimedOverlap: specificTimedOverlap,
            hasParticipantOverlap: participant,
            hasTitleOverlap: title,
            hasRoomCodeConflict: roomConflict,
            isAllDay: allDay,
            isLongEvent: long
        )
    }

    private static func exactRoomMatch(eventLocation: String?, metadataRoom: String?) -> Bool {
        guard let eventLocation = normalized(eventLocation),
              let metadataRoom = normalized(metadataRoom) else {
            return false
        }
        return eventLocation == metadataRoom
    }

    private static func roomSignal(event: GoogleCalendarEvent, metadataRoom: String?) -> CalendarRoomSignal {
        guard let metadataRoom,
              !metadataRoom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }

        if exactRoomMatch(eventLocation: event.location, metadataRoom: metadataRoom) {
            return .exact
        }

        let metadataCodes = roomCodes(in: metadataRoom)
        guard !metadataCodes.isEmpty else {
            return .none
        }

        let sharedCodes = metadataCodes.intersection(roomCodes(in: roomSearchText(for: event)))
        guard let code = sharedCodes.sorted().first else {
            return .none
        }

        return .codeMatch(code)
    }

    private static func roomCodeConflict(event: GoogleCalendarEvent, metadataRoom: String?) -> Bool {
        guard !exactRoomMatch(eventLocation: event.location, metadataRoom: metadataRoom) else {
            return false
        }
        let metadataCodes = roomCodes(in: metadataRoom)
        let eventCodes = roomCodes(in: roomSearchText(for: event))
        guard !metadataCodes.isEmpty, !eventCodes.isEmpty else {
            return false
        }
        return metadataCodes.isDisjoint(with: eventCodes)
    }

    private static func roomSearchText(for event: GoogleCalendarEvent) -> String {
        [
            event.location,
            event.summary,
            boundedDescriptionText(event.description)
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func participantOverlap(
        eventAttendees: [GoogleCalendarPerson],
        metadataParticipants: [String]
    ) -> Bool {
        let attendeeValues = Set(eventAttendees.map(\.displayText).map(normalizedToken).filter { !$0.isEmpty })
        guard !attendeeValues.isEmpty else {
            return false
        }
        return metadataParticipants
            .map(normalizedToken)
            .filter { !$0.isEmpty }
            .contains { participant in
                attendeeValues.contains(participant)
            }
    }

    private static func titleOverlap(eventTitle: String, metadataTitle: String) -> Bool {
        let eventTokens = Set(tokens(in: eventTitle))
        guard !eventTokens.isEmpty else {
            return false
        }
        return !eventTokens.isDisjoint(with: tokens(in: metadataTitle))
    }

    private static func tokens(in value: String) -> [String] {
        normalizedToken(value)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[\[\]\(\)\{\}_:/\\|,.;]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"-"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func roomCodes(in value: String?) -> Set<String> {
        let normalized = normalizedSearchText(value ?? "")
        guard !normalized.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"\b([rl]\d{1,2})\b"#, options: [.caseInsensitive])
        else {
            return []
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return Set(regex.matches(in: normalized, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let codeRange = Range(match.range(at: 1), in: normalized) else {
                return nil
            }
            return String(normalized[codeRange]).lowercased()
        })
    }

    private static func boundedDescriptionText(_ description: String?) -> String? {
        guard let description else {
            return nil
        }
        return String(description.prefix(700))
    }

    private static func isAllDay(_ event: GoogleCalendarEvent) -> Bool {
        event.start.date != nil || event.end.date != nil
    }

    private static func eventDurationSeconds(_ event: GoogleCalendarEvent) -> TimeInterval? {
        guard let start = parseDate(event.start.displayText),
              let end = parseDate(event.end.displayText) else {
            return nil
        }
        return max(0, end.timeIntervalSince(start))
    }

    private static func isLongEvent(_ event: GoogleCalendarEvent) -> Bool {
        guard let duration = eventDurationSeconds(event) else {
            return false
        }
        return duration >= 3 * 60 * 60
    }

    private static func hasSpecificTimedOverlap(
        event: GoogleCalendarEvent,
        meetingStart: Date?,
        meetingEnd: Date?,
        roomSignal: CalendarRoomSignal
    ) -> Bool {
        guard overlaps(event: event, meetingStart: meetingStart, meetingEnd: meetingEnd),
              !isAllDay(event) else {
            return false
        }

        guard let duration = eventDurationSeconds(event) else {
            return roomSignal.isStrong
        }

        if duration <= 2 * 60 * 60 {
            return true
        }

        if roomSignal.isStrong && duration <= 3 * 60 * 60 {
            return true
        }

        return false
    }

    private static func fallbackFingerprint(metadata: MeetingMetadata) -> String {
        [
            metadata.room ?? "",
            metadata.displayTitle,
            metadata.participants.sorted().joined(separator: ",")
        ]
        .joined(separator: "|")
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .lowercased()
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .nonEmpty
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)
    }
}

private enum CalendarRoomSignal: Equatable {
    case none
    case exact
    case codeMatch(String)

    var score: Double {
        switch self {
        case .none:
            return 0
        case .exact:
            return 0.40
        case .codeMatch:
            return 0.35
        }
    }

    var isStrong: Bool {
        switch self {
        case .exact, .codeMatch:
            return true
        case .none:
            return false
        }
    }
}

private struct MappedCalendarCandidate {
    let candidate: CalendarEventCandidate
    let details: CalendarEventMatchDetails
}

private struct CalendarEventMatchDetails {
    let confidence: Double
    let shouldAutoAccept: Bool
    let roomSignal: CalendarRoomSignal
    let hasTimeOverlap: Bool
    let hasSpecificTimedOverlap: Bool
    let hasParticipantOverlap: Bool
    let hasTitleOverlap: Bool
    let hasRoomCodeConflict: Bool
    let isAllDay: Bool
    let isLongEvent: Bool
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }

    func capped(at limit: Int) -> String {
        guard count > limit else {
            return self
        }
        return String(prefix(limit))
    }
}
