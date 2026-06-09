# Calendar Room Title Normalization Auto Accept Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Google Calendar context matching so a real recurring meeting can be promoted from `candidate` to `accepted` when the calendar event matches the active transcript by meeting time plus normalized room/title signals, while noisy calendar entries remain candidates only.

**Architecture:** Keep the pipeline centered in `GoogleCalendarContextMapper`. Replace the current opaque confidence helpers with a deterministic match-details layer that extracts normalized room codes from event location, event title, and bounded event description. The mapper should compute confidence and auto-acceptability from those signals once, sort candidates, and allow only the best high-confidence event to produce `meetingIdentity` and supplemental context. Test Run replay remains unchanged and benefits from the persisted accepted context.

**Tech Stack:** Swift Package, XCTest, SwiftUI desktop app state, local Google Calendar API OAuth smoke command.

---

## Context

- Current verified UI behavior on 2026-06-09:
  - Google Calendar API fetch works.
  - Candidate snapshots are persisted.
  - Test Run reuses saved calendar candidates through `cachedReplay`.
  - The recurring meeting-like calendar event is still not auto accepted: `acceptedCount=0`, `supplementalCount=0`, `meetingIdentityPresent=false`.
- The current matcher only treats `event.location == metadata.room` as strong room evidence.
- Real calendar room evidence can appear in the title or description, for example a table/room code such as `R3`, while transcript metadata may contain a room string like `Zigbang(2F)_R3`.
- `Zigbang(2F)` and `Zigbang(2F)_Meeting Room L3` must not be treated as the same room.
- All-day, focus-time, work-from-office, and long busy blocks may overlap the meeting time but must not produce identity or supplemental context.

## Target Behavior

- A timed recurring calendar event that overlaps the active meeting and contains the same normalized room code in location, title, or bounded description is automatically accepted.
- Exact location match remains accepted when time overlap is specific.
- A different room code such as `L3` vs `R3` remains candidate-only even if time overlaps.
- A bare building/floor string such as `Zigbang(2F)` does not match a specific room code such as `Meeting Room L3`.
- All-day and long generic busy events remain candidate-only.
- Only the top accepted event produces `meetingIdentity` and calendar supplemental context.

## Files

- `Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift`
- `Tests/MeetingRescueCoreTests/GoogleCalendarContextMapperTests.swift`
- `docs/calendar-quality-validation.md`

## Task 1: Add Failing Mapper Tests First

- [ ] Open `Tests/MeetingRescueCoreTests/GoogleCalendarContextMapperTests.swift`.
- [ ] Add deterministic tests that reproduce the real issue without storing private calendar content.

Append the following tests inside `GoogleCalendarContextMapperTests`:

```swift
func acceptsRecurringEventWhenRoomCodeAppearsInCalendarTitle() {
    let response = GoogleCalendarEventsResponse(items: [
        event(
            id: "evt-recurring-r3",
            summary: "[table:HD-R3] Weekly Product Sync",
            start: "2026-06-09T10:30:00+09:00",
            end: "2026-06-09T11:00:00+09:00",
            attendees: [attendee("ethan@example.com")],
            location: nil,
            description: "Notes: https://docs.example.com/meeting-r3",
            recurringEventID: "series-product-sync"
        )
    ])
    let metadata = MeetingMetadata(
        room: "Zigbang(2F)_R3",
        dateTime: date("2026-06-09T10:32:36+09:00"),
        participants: ["Ethan Kim"]
    )

    let state = GoogleCalendarContextMapper.map(
        response,
        metadata: metadata,
        meetingStart: date("2026-06-09T10:32:36+09:00"),
        meetingEnd: date("2026-06-09T11:02:00+09:00")
    )

    XCTAssertEqual(state.candidates.first?.status, .accepted)
    XCTAssertEqual(state.meetingIdentity?.recurrenceID, "calendar:series-product-sync")
    XCTAssertEqual(state.supplementalSources.first?.type, .calendarEvent)
    XCTAssertTrue(state.supplementalSources.contains { $0.type == .linkedSourceCandidate })
}

func doesNotAcceptAllDayOrLongBusyEventsAroundMeeting() {
    let response = GoogleCalendarEventsResponse(items: [
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
            attendees: [attendee("ethan@example.com")],
            location: "Zigbang(2F)",
            description: nil,
            recurringEventID: nil
        )
    ])
    let metadata = MeetingMetadata(
        room: "Zigbang(2F)_R3",
        dateTime: date("2026-06-09T10:32:36+09:00"),
        participants: ["Ethan Kim"]
    )

    let state = GoogleCalendarContextMapper.map(
        response,
        metadata: metadata,
        meetingStart: date("2026-06-09T10:32:36+09:00"),
        meetingEnd: date("2026-06-09T11:02:00+09:00")
    )

    XCTAssertFalse(state.candidates.contains { $0.status == .accepted })
    XCTAssertNil(state.meetingIdentity)
    XCTAssertTrue(state.supplementalSources.isEmpty)
}

func keepsDifferentRoomCodeCandidateOnly() {
    let response = GoogleCalendarEventsResponse(items: [
        event(
            id: "evt-l3",
            summary: "[table:HD-L3] Weekly Product Sync",
            start: "2026-06-09T10:30:00+09:00",
            end: "2026-06-09T11:00:00+09:00",
            attendees: [attendee("ethan@example.com")],
            location: nil,
            description: nil,
            recurringEventID: "series-product-sync"
        )
    ])
    let metadata = MeetingMetadata(
        room: "Zigbang(2F)_R3",
        dateTime: date("2026-06-09T10:32:36+09:00"),
        participants: ["Ethan Kim"]
    )

    let state = GoogleCalendarContextMapper.map(
        response,
        metadata: metadata,
        meetingStart: date("2026-06-09T10:32:36+09:00"),
        meetingEnd: date("2026-06-09T11:02:00+09:00")
    )

    XCTAssertEqual(state.candidates.first?.status, .candidate)
    XCTAssertNil(state.meetingIdentity)
    XCTAssertTrue(state.supplementalSources.isEmpty)
}

func prefersSpecificRecurringRoomTitleMatchOverLongBusyOverlap() {
    let response = GoogleCalendarEventsResponse(items: [
        event(
            id: "evt-work-block",
            summary: "Work from office",
            start: "2026-06-09T09:30:00+09:00",
            end: "2026-06-09T18:30:00+09:00",
            attendees: [attendee("ethan@example.com")],
            location: "Zigbang(2F)",
            description: nil,
            recurringEventID: nil
        ),
        event(
            id: "evt-recurring-r3",
            summary: "[table:HD-R3] Weekly Product Sync",
            start: "2026-06-09T10:30:00+09:00",
            end: "2026-06-09T11:00:00+09:00",
            attendees: [attendee("ethan@example.com")],
            location: nil,
            description: nil,
            recurringEventID: "series-product-sync"
        )
    ])
    let metadata = MeetingMetadata(
        room: "Zigbang(2F)_R3",
        dateTime: date("2026-06-09T10:32:36+09:00"),
        participants: ["Ethan Kim"]
    )

    let state = GoogleCalendarContextMapper.map(
        response,
        metadata: metadata,
        meetingStart: date("2026-06-09T10:32:36+09:00"),
        meetingEnd: date("2026-06-09T11:02:00+09:00")
    )

    XCTAssertEqual(state.candidates.first?.id, "evt-recurring-r3")
    XCTAssertEqual(state.candidates.first?.status, .accepted)
    XCTAssertEqual(state.meetingIdentity?.recurrenceID, "calendar:series-product-sync")
    XCTAssertTrue(state.candidates.dropFirst().allSatisfy { $0.status == .candidate })
}
```

- [ ] Add or extend the local test helper to support all-day events:

```swift
private func event(
    id: String,
    summary: String,
    start: String? = nil,
    end: String? = nil,
    startDate: String? = nil,
    endDate: String? = nil,
    attendees: [GoogleCalendarEventAttendee],
    location: String?,
    description: String?,
    recurringEventID: String?
) -> GoogleCalendarEvent {
    GoogleCalendarEvent(
        id: id,
        summary: summary,
        start: GoogleCalendarEventTime(dateTime: start, date: startDate, timeZone: "Asia/Seoul"),
        end: GoogleCalendarEventTime(dateTime: end, date: endDate, timeZone: "Asia/Seoul"),
        organizer: nil,
        attendees: attendees,
        location: location,
        description: description,
        htmlLink: nil,
        recurringEventID: recurringEventID
    )
}
```

- [ ] Run the focused tests and confirm the new assertions fail before implementation:

```bash
swift test --filter GoogleCalendarContextMapperTests
```

Expected pre-implementation result:

- `acceptsRecurringEventWhenRoomCodeAppearsInCalendarTitle` fails because the event stays `.candidate`.
- `prefersSpecificRecurringRoomTitleMatchOverLongBusyOverlap` fails because the recurring event is not accepted.

## Task 2: Add Match Details and Room/Title Normalization

- [ ] Open `Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift`.
- [ ] Add private match-detail types near the existing private helper methods:

```swift
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

private struct CalendarEventMatchDetails {
    let confidence: Double
    let shouldAutoAccept: Bool
    let roomSignal: CalendarRoomSignal
    let hasTimeOverlap: Bool
    let hasSpecificTimedOverlap: Bool
    let hasParticipantOverlap: Bool
    let hasTitleOverlap: Bool
    let isAllDay: Bool
    let isLongEvent: Bool
}
```

- [ ] Add normalized search text and room-code extraction helpers:

```swift
private static func normalizedSearchText(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .lowercased()
        .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"[\[\]\(\)\{\}_:/\\|,.;]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"-"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private static func roomCodes(in value: String?) -> Set<String> {
    let normalized = normalizedSearchText(value ?? "")
    guard !normalized.isEmpty else { return [] }

    let pattern = #"\b([rl]\d{1,2})\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }

    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    return Set(regex.matches(in: normalized, range: range).compactMap { match in
        guard match.numberOfRanges > 1,
              let codeRange = Range(match.range(at: 1), in: normalized)
        else {
            return nil
        }
        return String(normalized[codeRange]).lowercased()
    })
}

private static func boundedDescriptionText(_ description: String?) -> String? {
    guard let description else { return nil }
    return String(description.prefix(700))
}
```

- [ ] Add event room-signal extraction. Use event `location`, `summary`, and bounded `description` for room-code detection. Keep exact room matching restricted to the event location and metadata room:

```swift
private static func roomSignal(event: GoogleCalendarEvent, metadataRoom: String?) -> CalendarRoomSignal {
    guard let metadataRoom,
          !metadataRoom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return .none
    }

    if exactRoomMatch(eventLocation: event.location, metadataRoom: metadataRoom) {
        return .exact
    }

    let metadataCodes = roomCodes(in: metadataRoom)
    guard !metadataCodes.isEmpty else {
        return .none
    }

    let eventRoomText = [
        event.location,
        event.summary,
        boundedDescriptionText(event.description)
    ]
        .compactMap { $0 }
        .joined(separator: " ")

    let sharedCodes = metadataCodes.intersection(roomCodes(in: eventRoomText))
    guard let code = sharedCodes.sorted().first else {
        return .none
    }

    return .codeMatch(code)
}
```

- [ ] Add all-day and long-event guards:

```swift
private static func isAllDay(_ event: GoogleCalendarEvent) -> Bool {
    event.start.date != nil || event.end.date != nil
}

private static func eventDurationSeconds(_ event: GoogleCalendarEvent) -> TimeInterval? {
    guard let start = parseDate(event.start.displayText),
          let end = parseDate(event.end.displayText)
    else {
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
          !isAllDay(event)
    else {
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
```

- [ ] Add a single match-details function and route the old `confidence(...)` helper through it:

```swift
private static func matchDetails(
    event: GoogleCalendarEvent,
    metadata: MeetingMetadata,
    meetingStart: Date?,
    meetingEnd: Date?
) -> CalendarEventMatchDetails {
    let timeOverlap = overlaps(event: event, meetingStart: meetingStart, meetingEnd: meetingEnd)
    let room = roomSignal(event: event, metadataRoom: metadata.room)
    let specificTimedOverlap = hasSpecificTimedOverlap(
        event: event,
        meetingStart: meetingStart,
        meetingEnd: meetingEnd,
        roomSignal: room
    )
    let participant = participantOverlap(event: event, metadataParticipants: metadata.participants)
    let title = titleOverlap(eventTitle: event.summary, metadataTitle: metadata.displayTitle)
    let allDay = isAllDay(event)
    let long = isLongEvent(event)
    let recurring = !(event.recurringEventID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

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
    let hasRecurringParticipantTitleSignal = recurring && participant && title
    let shouldAutoAccept = specificTimedOverlap
        && confidence >= 0.80
        && !allDay
        && (room.isStrong || hasRecurringParticipantTitleSignal)

    return CalendarEventMatchDetails(
        confidence: confidence,
        shouldAutoAccept: shouldAutoAccept,
        roomSignal: room,
        hasTimeOverlap: timeOverlap,
        hasSpecificTimedOverlap: specificTimedOverlap,
        hasParticipantOverlap: participant,
        hasTitleOverlap: title,
        isAllDay: allDay,
        isLongEvent: long
    )
}

private static func confidence(
    event: GoogleCalendarEvent,
    metadata: MeetingMetadata,
    meetingStart: Date?,
    meetingEnd: Date?
) -> Double {
    matchDetails(
        event: event,
        metadata: metadata,
        meetingStart: meetingStart,
        meetingEnd: meetingEnd
    ).confidence
}
```

## Task 3: Promote Only the Best Auto-Accepted Candidate

- [ ] Update `map(...)` in `Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift` to compute match details once per event.
- [ ] Set raw candidate status from `details.shouldAutoAccept`.
- [ ] After sorting, demote every accepted candidate except the top accepted event to `.candidate`.

Use this shape inside `map(...)`:

```swift
let mapped = response.items.compactMap { event -> GoogleCalendarCandidate? in
    let details = matchDetails(
        event: event,
        metadata: metadata,
        meetingStart: meetingStart,
        meetingEnd: meetingEnd
    )
    guard details.confidence > 0.1 else {
        return nil
    }
    return candidate(
        for: event,
        confidence: details.confidence,
        status: details.shouldAutoAccept ? .accepted : .candidate
    )
}

let sorted = mapped.sorted { lhs, rhs in
    if lhs.status != rhs.status {
        return lhs.status == .accepted
    }
    if lhs.confidence != rhs.confidence {
        return lhs.confidence > rhs.confidence
    }
    return lhs.startDate < rhs.startDate
}

let acceptedID = sorted.first { $0.status == .accepted }?.id
let normalizedCandidates = sorted.map { candidate in
    guard candidate.status == .accepted, candidate.id != acceptedID else {
        return candidate
    }
    var demoted = candidate
    demoted.status = .candidate
    return demoted
}

let accepted = normalizedCandidates.first { $0.status == .accepted }
```

- [ ] Keep the existing downstream behavior:
  - `supplementalSources` are generated only from `accepted`.
  - linked source candidates from accepted event descriptions remain `isAccepted=false`.
  - `meetingIdentity` uses `recurringEventID` when present and fallback fingerprint otherwise.
- [ ] Run:

```bash
swift test --filter GoogleCalendarContextMapperTests
```

Expected post-implementation result:

- Exact room match tests still pass.
- Different room code tests pass.
- Recurring room-code-in-title tests pass.
- All-day and long generic events do not auto accept.

## Task 4: Verify Replay and Prompt Integration Did Not Regress

- [ ] Run the context replay tests:

```bash
swift test --filter AppViewModelTestRunContextTests
```

- [ ] Run prompt builder tests that consume accepted supplemental context:

```bash
swift test --filter AnalysisPromptBuilderTests
```

- [ ] Run all package tests if focused tests pass:

```bash
swift test
```

Expected result:

- Test Run replay still preserves saved `calendarContext`.
- The analysis prompt still includes calendar supplemental context only when `supplementalSources` are accepted calendar event sources.
- No UI state schema change is required for this hardening.

## Task 5: Build and Run Calendar Smoke Validation

- [ ] Build the app with the private OAuth config default path:

```bash
scripts/build_app.sh
```

- [ ] Run the CLI smoke test:

```bash
"dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue" --google-calendar-smoke --allow-empty-events
```

Expected smoke result:

- OAuth config is loaded from `private/GoogleCalendarOAuthConfig.json`.
- Keychain token can be reused when already connected.
- Events are fetched or the smoke exits successfully with `--allow-empty-events`.
- Cached replay path is reported when a prior snapshot exists.

## Task 6: Manual GUI Validation With Sanitized Evidence

- [ ] Launch the dist app directly:

```bash
"dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue" > /tmp/meeting-rescue-dist-ui.log 2>&1 &
```

- [ ] In the app, use an active or recent transcript for a recurring meeting.
- [ ] Open `컨텍스트`.
- [ ] Click `가져오기` under Google Calendar API.
- [ ] Inspect the active session JSON with sanitized `jq` only:

```bash
jq '{
  mcpStatus: .calendarContext.mcpStatus,
  candidateCount: (.calendarContext.candidates // [] | length),
  acceptedCount: (.calendarContext.candidates // [] | map(select(.status == "accepted")) | length),
  supplementalCount: (.calendarContext.supplementalSources // [] | length),
  meetingIdentityPresent: (.calendarContext.meetingIdentity != null)
}' "$SESSION_JSON"
```

Expected GUI fetch result:

```json
{
  "mcpStatus": "connected",
  "candidateCount": 1,
  "acceptedCount": 1,
  "supplementalCount": 1,
  "meetingIdentityPresent": true
}
```

The exact `candidateCount` can be greater than `1` when nearby calendar entries overlap. The accepted count must be `1`, supplemental count must be at least `1`, and identity must be present.

- [ ] Start Test Run from the same transcript.
- [ ] Trigger manual analysis.
- [ ] Stop Test Run after analysis finishes or transitions back to Live Watch.
- [ ] Inspect sanitized replay state:

```bash
jq '{
  attempts: (.analysisHistory // [] | length),
  attemptStatuses: (.analysisHistory // [] | group_by(.status) | map({status: .[0].status, count: length})),
  calendar: {
    mcpStatus: .calendarContext.mcpStatus,
    candidateCount: (.calendarContext.candidates // [] | length),
    acceptedCount: (.calendarContext.candidates // [] | map(select(.status == "accepted")) | length),
    supplementalCount: (.calendarContext.supplementalSources // [] | length),
    meetingIdentityPresent: (.calendarContext.meetingIdentity != null)
  }
}' "$SESSION_JSON"
```

Expected Test Run result:

- `calendar.mcpStatus` is `cachedReplay`.
- `calendar.acceptedCount` remains `1`.
- `calendar.supplementalCount` remains at least `1`.
- `calendar.meetingIdentityPresent` remains `true`.
- No raw calendar title, attendee, URL, or description is added to public docs or commit messages.

## Task 7: Update Validation Document

- [ ] Update `docs/calendar-quality-validation.md`.
- [ ] Add a new subsection titled `### 2026-06-09 Room/Title Normalization Hardening 결과`.
- [ ] Record only sanitized counts and conclusion:

```md
### 2026-06-09 Room/Title Normalization Hardening 결과

- `swift test --filter GoogleCalendarContextMapperTests`: 통과.
- `swift test --filter AppViewModelTestRunContextTests`: 통과.
- `swift test --filter AnalysisPromptBuilderTests`: 통과.
- CLI smoke: OAuth config 로드, token 재사용, event fetch 또는 empty-events 허용 경로 통과.
- GUI fetch sanitized result:
  - `candidateCount`: <number recorded from jq>
  - `acceptedCount`: `1`
  - `supplementalCount`: `>=1`
  - `meetingIdentityPresent`: `true`
- Test Run sanitized replay result:
  - `mcpStatus`: `cachedReplay`
  - `acceptedCount`: `1`
  - `supplementalCount`: `>=1`
  - `meetingIdentityPresent`: `true`

결론: Google Calendar API fetch/replay는 기존처럼 동작하며, room/title normalization 이후 recurring meeting 후보가 accepted/identity/supplemental context로 승격된다. 이 단계는 품질 향상 검증의 입력 품질을 보장하는 hardening이다.
```

Replace `<number recorded from jq>` with the sanitized integer from the local validation command before committing.

## Task 8: Commit

- [ ] Review the diff:

```bash
git diff -- Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift Tests/MeetingRescueCoreTests/GoogleCalendarContextMapperTests.swift docs/calendar-quality-validation.md
git diff --check
```

- [ ] Ensure private OAuth config is not staged:

```bash
git status --short
```

Expected status:

- `private/GoogleCalendarOAuthConfig.json` does not appear because it is ignored.
- Only source, test, and documentation files for this hardening are staged.

- [ ] Commit:

```bash
git add Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift Tests/MeetingRescueCoreTests/GoogleCalendarContextMapperTests.swift docs/calendar-quality-validation.md
git commit -m "Harden Google Calendar room title matching"
```

## Acceptance Criteria

- [ ] `swift test --filter GoogleCalendarContextMapperTests` passes.
- [ ] `swift test --filter AppViewModelTestRunContextTests` passes.
- [ ] `swift test --filter AnalysisPromptBuilderTests` passes.
- [ ] `swift test` passes or any unrelated failure is documented with exact failing test names.
- [ ] `scripts/build_app.sh` succeeds.
- [ ] Google Calendar CLI smoke succeeds.
- [ ] GUI fetch produces exactly one accepted calendar candidate for the recurring room/title match.
- [ ] Test Run replay preserves that accepted candidate through `cachedReplay`.
- [ ] No private calendar data, OAuth secret, raw attendees, raw descriptions, or private URLs are committed.

## Risk Notes

- Room-code extraction deliberately recognizes only `R` or `L` followed by one or two digits. This keeps the first hardening pass narrow and prevents broad building/floor matches from becoming identity evidence.
- Description matching is capped at 700 characters and used only for room-code extraction, not broad title similarity. This allows room codes embedded in calendar metadata without turning linked docs into noisy title evidence.
- Long events can remain visible as candidates, but they cannot auto accept unless they have a strong room signal and a bounded duration no longer than three hours.
- Only the top accepted event remains accepted after sorting. This avoids multiple identities from overlapping calendar entries.
