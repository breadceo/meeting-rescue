# Google Calendar Quality Validation Hardening Goal Prompt

Use this prompt to harden Google Calendar quality validation for Meeting Rescue before moving on to D3/team features.

```text
Goal: Harden and verify whether Google Calendar context measurably improves Meeting Rescue output quality, while keeping the integration reliable, low-noise, and test-run reproducible.

Context:
- Repo: /Users/ethan/Documents/git/meeting-rescue
- User language: Korean.
- Current date context: 2026-06-08.
- The app is a local-first macOS Swift app.
- Direct Google Calendar API OAuth is now the primary production path for calendar context.
- Calendar MCP is not the primary UX path and should stay hidden from the Context tab unless explicitly reintroduced.
- Test Run must never call live Google APIs. It must reuse saved `CalendarContextState` snapshots.
- Calendar context is supplemental evidence. Transcript and user-confirmed artifacts win on conflict.
- Raw transcript must never be sent to Google. Google API receives only calendar id and time window.

Current baseline to preserve:
- Recent uncommitted changes may exist. Before editing, inspect `git status --short --branch` and do not overwrite user or previous-agent changes.
- Known recent fixes to keep:
  - `GoogleCalendarOAuthConfigLoader` can load `GoogleCalendarOAuthConfig.json` from packaged app resource bundle paths.
  - Context tab hides the `Google Calendar MCP` card and uses Google Calendar API wording.
  - `ContentViewContextWiringTests` covers Context panel visibility and MCP control hiding.
  - `GoogleCalendarOAuthLoopbackServerTests` covers packaged app OAuth config lookup.
- If those fixes are still uncommitted, include them carefully in the first commit or ask the user before splitting them out.

Product question this work must answer:
- Does Google Calendar context improve Meeting Intelligence quality enough to justify keeping it visible?
- Quality means:
  - current meeting identity is more accurate,
  - recurring meeting carry-over chooses the right previous meetings,
  - decision/action/open-question output gets useful agenda/title/attendee/link context,
  - unrelated or stale calendar events do not pollute the analysis,
  - Test Run can reproduce the same context without live calendar access.

Non-goals:
- Do not start D3 Team shared memory.
- Do not add background calendar sync.
- Do not add Google Calendar write scopes.
- Do not reintroduce Calendar MCP as visible UI.
- Do not build a generic evaluation platform.
- Do not commit OAuth client JSON, client secret values, access tokens, refresh tokens, or real calendar data.

Required approach:
- Use TDD for production behavior changes.
- Prefer deterministic fixture-based tests over LLM judgment when possible.
- If LLM output quality must be checked, use a manual validation report with exact before/after evidence and do not claim deterministic pass/fail from vibes.
- Use sanitized calendar fixtures. Real event titles/descriptions/attendees should be redacted before committing.
- Keep changes narrow to Calendar context, analysis prompt wiring, Test Run replay, and validation docs/tests.

Hardening work:

1. Baseline inspection
- Read:
  - `tasks.md` D2 / 11a Direct Google Calendar API OAuth section.
  - `Sources/MeetingRescue/GoogleCalendarIntegration.swift`
  - `Sources/MeetingRescue/AppViewModel.swift`
  - `Sources/MeetingRescue/ContentView.swift`
  - `Sources/MeetingRescueCore/CalendarContextModels.swift`
  - `Sources/MeetingRescueCore/GoogleCalendarContextMapper.swift`
  - `Sources/MeetingRescueCore/AnalysisPromptBuilder.swift`
  - `Sources/MeetingRescueCore/PersonalWorkflowAnalyzer.swift`
  - Existing tests under `Tests/MeetingRescueCoreTests/*Calendar*` and `Tests/MeetingRescueTests/*Calendar*`.
- Confirm current behavior before changing:
  - Context tab shows Google Calendar API controls.
  - Context tab does not show Google Calendar MCP controls.
  - OAuth config loads from packaged app build.
  - Test Run uses cached calendar context.

2. Define a small quality fixture set
- Add sanitized fixtures for at least these scenarios:
  - exact current event match: event time overlaps transcript meeting time and room matches exactly.
  - recurring meeting match: event has `recurringEventId` and should produce stable series identity.
  - competing overlap: multiple calendar events overlap the same window; exact room/time match should outrank participant/title-only matches.
  - room mismatch: `Zigbang(2F)` and `Zigbang(2F)_Meeting Room L3` must be treated as different rooms.
  - no useful event: empty or irrelevant event list should not create strong identity.
  - calendar/transcript conflict: transcript title/participants should remain primary when calendar metadata disagrees.
  - link-rich description: Calendar description links should become supplemental candidates, capped and safe to display.
- Suggested location:
  - `Tests/MeetingRescueCoreTests/Fixtures/CalendarQuality/*.json`
  - or inline fixtures if the repo strongly prefers inline test data.

3. Add deterministic mapper quality tests
- Extend or add tests around `GoogleCalendarContextMapper`.
- Required assertions:
  - exact room/time overlap creates highest-confidence event candidate.
  - recurring event ID becomes `meetingIdentity.seriesKey` or the existing recurrence-aware identity field.
  - participant/title overlap is secondary to time and exact room.
  - `Zigbang(2F)` and `Zigbang(2F)_Meeting Room L3` do not match as the same room.
  - long descriptions are capped and links are extracted or preserved according to the current supplemental source model.
  - irrelevant events remain low-confidence or absent according to existing model semantics.

4. Add prompt quality guards
- Verify `AnalysisPromptBuilder` includes accepted/saved calendar context as supplemental context.
- Verify transcript priority is explicit in the prompt when calendar context exists.
- Verify calendar fields do not replace transcript-derived title/participants blindly.
- Add or extend tests so conflicts between transcript and calendar context keep transcript-first wording.

5. Add Test Run replay hardening
- Extend app-level tests around `AppViewModel.startTestRunFromHistory`.
- Required assertions:
  - saved Google Calendar context is loaded as `cachedReplay`.
  - Test Run does not call live Google Calendar API or Calendar MCP.
  - status copy clearly says stored Google Calendar context was applied.
  - supplemental sources survive replay.
  - event candidate acceptance/dismissal state is preserved if the current model supports it.

6. Add UI/source wiring guards
- Keep `ContentViewContextWiringTests` or equivalent source-level regression tests.
- Required assertions:
  - Context lane renders `contextPanel()`.
  - Context panel includes Google Calendar API status/actions.
  - Context panel does not call `calendarMCPStatusCard()`.
  - visible empty-state copy does not mention `Google Calendar MCP`.

7. Manual quality validation protocol
- Create or update a doc such as `docs/calendar-quality-validation.md`.
- Include a compact validation matrix:
  - transcript sample or sanitized meeting description,
  - calendar context snapshot used,
  - expected improvement,
  - observed result,
  - pass/fail,
  - notes and follow-up.
- Run at least three manual scenarios with real or sanitized saved snapshots:
  - recurring meeting with previous open question carry-over,
  - spot meeting with only title/attendee overlap,
  - conflicting or irrelevant calendar event.
- For each scenario, compare:
  - without calendar context,
  - with saved calendar context,
  - Test Run replay using the saved snapshot.
- Do not store real private calendar content in committed docs.

8. Build/smoke validation
- Build local app with OAuth config injection:
  - `scripts/build_app.sh` uses `private/GoogleCalendarOAuthConfig.json` automatically when present.
  - Use `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/path/to/client_secret_*.json scripts/build_app.sh` only to override the local path.
- Verify the config file exists inside the app bundle.
- Smoke behavior:
  - If no token is stored, smoke should pass config loading and fail at the expected login/token state, not `OAuth config가 없습니다`.
  - If the user completes OAuth, fetch current meeting window and verify saved `CalendarContextState`.
  - Run Test Run and verify it reuses saved context without live API.
- Keep any real OAuth client JSON and tokens outside git.

9. Update tracker and closeout evidence
- Update `tasks.md` with:
  - calendar quality validation hardening status,
  - validation scenarios covered,
  - commands run and results,
  - any accepted remaining gaps.
- If `execution-log.md` is used in this repo for evidence, add concise command/result notes there too.
- Do not mark this hardening complete until deterministic tests and at least one real/local smoke path are verified.

Verification required before closing:
- `swift test`
- If `.build` xctest signature cache fails on macOS, rerun with a scratch path:
  - `swift test --scratch-path .build-test`
  - remove `.build-test` after verification if it is not needed.
- `python3 -m unittest Tests/google_calendar_oauth_poc_tests.py`
- `git diff --check`
- App build with OAuth config injection if app target files changed.
- Manual smoke or documented reason why real OAuth smoke was deferred.
- Secret leak check:
  - no `client_secret_*.json` tracked,
  - no access token/refresh token/client secret values in git diff,
  - no real private calendar payload committed.

Acceptance criteria:
- The app can still connect/fetch Google Calendar context after the hardening changes.
- Calendar context matching is covered by deterministic tests for exact match, recurrence, competing overlap, room mismatch, no-match, conflict, and link-rich description cases.
- Prompt/test-run behavior proves calendar context is supplemental and replayable.
- Context UI stays focused on Google Calendar API and does not expose Calendar MCP controls.
- A short validation report exists so product can judge whether Calendar context actually improves Meeting Intelligence quality.
- `tasks.md` accurately reflects current status and remaining gaps.
```
