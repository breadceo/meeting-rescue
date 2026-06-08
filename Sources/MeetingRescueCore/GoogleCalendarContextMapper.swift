import Foundation

public enum GoogleCalendarContextMapper {
    public static func map(
        _ response: GoogleCalendarEventsListResponse,
        metadata: MeetingMetadata,
        meetingStart: Date?,
        meetingEnd: Date?,
        fetchedAt: Date = Date()
    ) -> CalendarContextState {
        let mapped = response.items.compactMap { event -> CalendarEventCandidate? in
            let confidence = confidence(
                for: event,
                metadata: metadata,
                meetingStart: meetingStart,
                meetingEnd: meetingEnd
            )
            guard confidence > 0.1 else {
                return nil
            }
            return CalendarEventCandidate(
                id: "google:\(event.id)",
                title: event.summary,
                startDateText: event.start.displayText,
                endDateText: event.end.displayText,
                organizer: event.organizer?.displayText.nonEmpty,
                attendees: event.attendees.map(\.displayText).filter { !$0.isEmpty },
                descriptionExcerpt: (event.description ?? "").capped(at: 1_200),
                recurrenceID: event.recurringEventID,
                confidence: confidence,
                status: confidence >= 0.85 ? .accepted : .candidate
            )
        }
        let sorted = mapped.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.startDateText < rhs.startDateText
            }
            return lhs.confidence > rhs.confidence
        }
        let accepted = sorted.first { $0.status == .accepted }

        return CalendarContextState(
            mcpStatus: .connected,
            eventCandidates: sorted,
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
        var score = 0.1

        if overlaps(event: event, meetingStart: meetingStart, meetingEnd: meetingEnd) {
            score += 0.35
        }
        if exactRoomMatch(eventLocation: event.location, metadataRoom: metadata.room) {
            score += 0.4
        }
        if participantOverlap(eventAttendees: event.attendees, metadataParticipants: metadata.participants) {
            score += 0.1
        }
        if titleOverlap(eventTitle: event.summary, metadataTitle: metadata.displayTitle) {
            score += 0.05
        }

        return min(1, max(0, score))
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

    private static func exactRoomMatch(eventLocation: String?, metadataRoom: String?) -> Bool {
        guard let eventLocation = normalized(eventLocation),
              let metadataRoom = normalized(metadataRoom) else {
            return false
        }
        return eventLocation == metadataRoom
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
