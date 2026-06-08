# Google Calendar Quality Validation

이 문서는 Google Calendar context가 Meeting Rescue 품질에 실제로 도움이 되는지 판단하기 위한 검증 기록이다. 실제 개인 calendar title, description, attendee, token, OAuth client secret은 이 문서에 저장하지 않는다.

## 판단 기준

- Calendar context는 transcript보다 낮은 우선순위의 보조 근거다.
- Calendar event가 현재 회의와 정확히 맞을 때만 meeting identity와 prompt context에 강하게 반영한다.
- 반복 회의는 `recurringEventId` 기반 series identity를 우선 사용한다.
- 관련 없는 event는 후보와 prompt context를 오염시키지 않는다.
- Calendar description의 링크는 자동 주입 근거가 아니라 사용자가 확인할 후보로만 보여준다.
- Test Run은 live Google API나 Calendar MCP를 호출하지 않고 저장된 `CalendarContextState` snapshot만 재사용한다.

## Sanitized Validation Matrix

| Scenario | Snapshot / Fixture | Expected improvement | Observed result | Status |
| --- | --- | --- | --- | --- |
| Exact current event match | Same time window, exact `Zigbang(2F)_Meeting Room L3` location, recurring event id | Meeting identity uses calendar series; event is accepted automatically; calendar metadata enters prompt as supplemental context | `GoogleCalendarContextMapperTests.mapsEventsToCalendarContextState` verifies accepted candidate, `calendar:series-1`, capped description, and calendar metadata source | Pass |
| Competing overlap | Two overlapping events: one participant-only, one exact room/time | Exact room/time event outranks participant-only overlap | `exactRoomAndTimeOutranksParticipantOnlyOverlap` verifies exact room/time candidate sorts first and becomes identity | Pass |
| Room mismatch | `Zigbang(2F)` vs `Zigbang(2F)_Meeting Room L3` | Similar-looking room names do not create strong identity | `keepsLowConfidenceCandidateWhenRoomDiffers` keeps the event as candidate and does not create identity/context | Pass |
| Irrelevant event | Different time, room, title, attendee | Event is not surfaced and cannot pollute analysis | `dropsEventsWithoutUsefulOverlap` verifies empty candidates/context/identity | Pass |
| Link-rich description | Accepted event description contains Google Docs and generic URLs | Links appear as unaccepted supplemental candidates, not prompt-injected evidence | `mapsDescriptionLinksToSupplementalContextCandidates` verifies two `.linkedSourceCandidate` sources with `isAccepted == false` | Pass |
| Calendar/transcript conflict | Calendar context says different room/attendee than transcript | Prompt tells the model transcript-derived meeting metadata wins | `promptForbidsCalendarMetadataFromReplacingTranscriptMetadata` verifies explicit instruction | Pass |
| Test Run replay | Saved calendar context has accepted/dismissed candidates, metadata source, identity | Replay uses cached snapshot and preserves candidate state without live API/MCP fetch | `AppViewModelTestRunContextTests` verifies `cachedReplay`, candidate state preservation, source preservation, and no live fetch symbols in Test Run path | Pass |

## Product Readout

Current deterministic evidence supports keeping Google Calendar context visible when it is clearly scoped as supplemental context:

- It improves recurring meeting identity when a high-confidence event match exists.
- It reduces carry-over risk by preserving `recurringEventId` as a stable series key.
- It lowers noise by dropping events with no time, room, participant, or title signal.
- It protects transcript authority by explicitly telling the prompt not to overwrite transcript-derived metadata from calendar metadata.
- It makes linked docs discoverable without silently injecting them into the prompt.
- It keeps Test Run reproducible because saved calendar context is replayed as `cachedReplay`.

The remaining product question is not whether the data path works, but whether real meeting outputs are noticeably better. That requires a live or saved real-world comparison with private data redacted before any artifact is committed.

## Manual Smoke Notes

- Release-style build should be run with:
  - `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/path/to/client_secret_*.json scripts/build_app.sh`
- Expected no-token local smoke result:
  - config lookup succeeds,
  - smoke stops at the expected login/token state,
  - it must not show `OAuth config가 없습니다`.
- Real OAuth fetch validation should record only counts and sanitized observations:
  - connected/disconnected state,
  - fetched event count,
  - persisted candidate count,
  - whether Test Run replay used `cachedReplay`,
  - whether disconnect removed the Keychain refresh token.

### 2026-06-08 Local Smoke Result

- Build:
  - `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/Users/ethan/Downloads/client_secret_...json scripts/build_app.sh`
  - Result: pass. `dist/Meeting Rescue.app` was built with bundled `GoogleCalendarOAuthConfig.json`.
- Smoke:
  - `"dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue" --google-calendar-smoke --allow-empty-events`
  - Result: pass.
  - Sanitized output:
    - OAuth Keychain token present.
    - Google Calendar events fetched: 7.
    - persisted candidates: 7.
    - cached replay status: `cachedReplay`.
    - disconnect: skipped.
- No event titles, attendees, descriptions, access tokens, refresh tokens, or client secret values were copied into this document.

## Follow-Up Decision

Before D3/team features, use one or two real recurring meetings to compare:

1. Without calendar context.
2. With saved Google Calendar context.
3. Test Run replay using the saved context.

Record only sanitized deltas, for example:

| Meeting type | Calendar context effect | Keep / adjust |
| --- | --- | --- |
| Weekly recurring | Did carry-over choose the right previous open question? | TBD after real run |
| Spot meeting | Did attendee/title overlap help or create noise? | TBD after real run |
| Conflicting event | Did transcript-first instruction prevent wrong metadata? | TBD after real run |
