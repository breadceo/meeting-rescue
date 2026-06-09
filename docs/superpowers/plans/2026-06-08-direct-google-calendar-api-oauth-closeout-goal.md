# Direct Google Calendar API OAuth Closeout Goal Prompt

Use this prompt to finish the Direct Google Calendar API OAuth lane for Meeting Rescue.

```text
Goal: Close the Direct Google Calendar API OAuth lane for Meeting Rescue end to end.

Context:
- Repo: /Users/ethan/Documents/git/meeting-rescue
- User language: Korean.
- Current date context: 2026-06-08.
- The app is a local-first macOS Swift app.
- Direct Google Calendar API OAuth is the chosen path, not GAS Bridge and not Calendar MCP as the primary production path.
- GC0 POC succeeded on 2026-06-08:
  - Browser OAuth consent worked with the downloaded Desktop OAuth client JSON.
  - Google Calendar `primary` `events.list` returned schema-valid JSON.
  - Workspace admin allow was NOT required in the current Workspace configuration.
- Product decision:
  - Default v1 path is user-consent OAuth with a company-owned Google OAuth client.
  - Workspace admin allow is an operational fallback only when OAuth/API returns `admin_policy_enforced`, app access block, or equivalent 403.
  - Do not require each user to open Google Cloud Console or enable Calendar API.
  - Do not send raw transcript to Google; Google receives only calendar id and time window.
  - Test Run must reuse stored calendar context snapshots and must not call live Google APIs.
  - Calendar context is supplemental evidence and lower priority than transcript and user-confirmed artifacts.
- OAuth client distribution decision:
  - Do not commit or bundle `client_secret_*.json` as a security boundary.
  - Desktop/installed client secret is not considered secret for token protection.
  - 2026-06-08 verification showed the current Desktop OAuth client returns `client_secret is missing` for refresh token grant without a client secret.
  - App code must support `clientID`, optional `clientSecret`, redirect host/prefix, and scope allowlist in a config such as `GoogleCalendarOAuthConfig.json`.
  - Do not commit the actual `clientSecret` value to tracked source. Inject it from `private/` or release-only local config into the release bundle.
  - Treat bundled `clientSecret` as a public-client identifier, not as a real secret. If exposed or rotated, require re-login/client rotation.
  - Protection comes from user consent, PKCE/state validation, refresh token Keychain storage, and optional Workspace admin allow when policy requires it.

Already implemented:
- `scripts/google_calendar_oauth_poc.py`
- `Tests/google_calendar_oauth_poc_tests.py`
- `Sources/MeetingRescueCore/GoogleCalendarOAuthModels.swift`
- `Tests/MeetingRescueCoreTests/GoogleCalendarOAuthModelsTests.swift`
- `Sources/MeetingRescueCore/GoogleCalendarTokenState.swift`
- `Tests/MeetingRescueCoreTests/GoogleCalendarTokenStateTests.swift`
- `Sources/MeetingRescueCore/GoogleCalendarAPIModels.swift`
- `Tests/MeetingRescueCoreTests/GoogleCalendarAPIModelsTests.swift`
- `Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift`
- `Tests/MeetingRescueCoreTests/GoogleCalendarContextMapperTests.swift`
- `Sources/MeetingRescue/GoogleCalendarIntegration.swift`
- `Sources/MeetingRescue/AppViewModel.swift` Google Calendar API connection/fetch wiring.
- `Sources/MeetingRescue/ContentView.swift` Settings > Analysis > Google Calendar card.
- `scripts/build_app.sh` supports `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE` to inject release-only OAuth config into the app resource bundle.
- `tasks.md` has the Direct Google Calendar API OAuth lane under D2 / 11a. Note: `tasks.md` is gitignored but should still be kept current.

Constraints:
- Use TDD for new production behavior. Write the focused failing test first, verify RED, implement, then verify GREEN.
- Use `apply_patch` for manual edits.
- Never commit OAuth downloaded client JSON, access tokens, refresh tokens, or secrets.
- Preserve unrelated user changes. Do not reset or checkout files.
- Keep scope narrow: finish the Google Calendar context lane, do not refactor unrelated Meeting Intelligence features.
- Prefer existing local model names and CalendarContextState flow.

Closeout work:
1. GC2 Keychain token store:
   - Add app-target Keychain storage for refresh token load/save/delete.
   - Keep access token in memory or short-lived state only.
   - Ensure logs/settings/attempt logs never persist token values.
   - Add tests for token state in Core and testable store behavior via protocol/fake where possible.

2. GC3 OAuth service:
   - Add loopback OAuth listener, default browser open, authorization code exchange, refresh grant.
   - Use existing Core OAuth models and PKCE.
   - Map failure states explicitly:
     - user cancel/access denied
     - admin policy/app access block
     - network failure
     - invalid_grant/token revoked
     - redirect/state mismatch
   - UI/status copy should be Korean:
     - `Google Calendar 연결됨`
     - `Google Calendar 다시 로그인 필요`
     - `Google Calendar 접근 권한이 필요합니다`
     - `관리자 승인 또는 앱 접근 권한이 필요합니다`
     - `Google Calendar 연결 해제`

3. GC4 Calendar API HTTP client:
   - Use `events.list` with:
     - `calendarId=primary`
     - `singleEvents=true`
     - `orderBy=startTime`
     - `maxResults=10`
     - `timeMin=currentMeetingStart - 15m`
     - `timeMax=currentMeetingEnd + 30m`, or live unknown -> `now + 3h`
   - On HTTP 401, refresh token and retry once.
   - On HTTP 403/admin-policy response, surface permission/admin issue state.

4. GC5 Calendar context mapping:
   - Map Google events to existing `CalendarEventCandidate`.
   - Preserve `recurringEventId` as `recurrenceID`.
   - Cap description excerpt at 1200 characters.
   - Attendees should use email or displayName and tolerate null/empty values.
   - Produce supplemental context source(s) using existing priority model.
   - Confidence should favor time overlap and exact room/location match; participant/topic/title overlap is secondary.

5. GC6 App wiring and UI:
   - Add Settings connection controls for Google Calendar.
   - Add fetch/status affordance where context is introduced.
   - Keep Calendar MCP status separate from Google Calendar API status.
   - Calendar context fetch failure must not block analysis.

6. GC7 Persistence and Test Run replay:
   - Persist fetched Google Calendar context in `analysisState.calendarContext`.
   - Test Run must call `cachedForTestRunReplay()` and show cached replay status.
   - Verify Test Run uses the saved context snapshot without live Google API calls.

7. GC8 Context tab re-enable gate:
   - Re-enable the Context tab now that Google Calendar API UX/data path is usable.
   - Add/adjust feature gate tests.

8. Documentation/tasks:
   - Keep `tasks.md` statuses current after each GC step.
   - Document that Workspace admin allow is fallback, not current default.
   - Document manual smoke command and expected failure modes.

Manual smoke setup:
- Debug/dev app can read the downloaded Google OAuth client JSON through:
  - `MEETING_RESCUE_GOOGLE_CALENDAR_OAUTH_CONFIG=/path/to/client_secret_*.json swift run MeetingRescue`
- Release app build can inject an untracked config through:
  - `private/GoogleCalendarOAuthConfig.json` plus `scripts/build_app.sh`
  - or `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/path/to/client_secret_*.json scripts/build_app.sh` when overriding the local path
- Do not commit the downloaded OAuth client JSON.

Verification required before closing:
- `swift test`
- `python3 -m unittest Tests/google_calendar_oauth_poc_tests.py`
- Build app with the repo's existing build command/script if app-target files changed.
- Manual smoke with an actual Google account:
  - Connect Google Calendar.
  - Fetch current meeting window.
  - Verify CalendarContextState persists event candidate(s).
  - Run Test Run and verify it reuses stored snapshot without live API call.
  - Disconnect and verify refresh token is removed from Keychain.
- Confirm no client secret JSON, access token, or refresh token appears in git diff or logs.

Acceptance criteria:
- A fresh user can connect Google Calendar with browser OAuth and no Google Cloud Console steps.
- Current meeting window can fetch calendar context from Google Calendar API.
- Stored calendar context is injected into analysis as supplemental context.
- Test Run uses cached calendar context only.
- Token storage is in Keychain; tokens are not persisted in settings/state/logs.
- Restrictive Workspace policy failure is shown as an actionable admin/access message, but admin allow is not required for the normal path.
- `tasks.md` marks Direct Google Calendar API OAuth complete only after the above verification is done.

Closeout evidence captured on 2026-06-08:
- `swift test`: passed, 170 tests / 33 suites.
- `python3 -m unittest Tests/google_calendar_oauth_poc_tests.py`: passed, 4 tests.
- `swift run MeetingRescue --google-calendar-smoke ... --connect --reset-before-connect --disconnect-after`: passed. OAuth connect, Keychain token present, Calendar fetch 7 events, persisted candidates 7, cached replay `cachedReplay`, disconnect verified.
- Release-style build with local untracked OAuth config injection: passed, and `GoogleCalendarOAuthConfig.json` exists in the app bundle resource directory.
- Secret/token leak check: passed for tracked diff and untracked repo files.
- Fixes verified during closeout:
  - loopback server waits for a nonzero assigned port before creating the redirect URI.
  - loopback redirect parser waits for a complete HTTP request before reading the authorization code.
  - Calendar API query builder percent-encodes RFC3339 timezone `+` as `%2B`.
- Context tab re-enable follow-up:
  - `MeetingIntelligenceFeatureGate` now exposes the `context` lane.
  - `AppViewModel` Test Run coverage verifies saved calendar context loads as `cachedReplay` with Google Calendar supplemental context preserved.

Non-goals for this closeout:
- Full calendar sync.
- Background sync.
- Calendar push notifications.
- Google Calendar write scopes.
- Calendar list metadata unless primary calendar is insufficient.
- Sending transcript text to Google.
```
