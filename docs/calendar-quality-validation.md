# Google Calendar 품질 검증

이 문서는 Google Calendar context가 Meeting Rescue 품질에 실제로 도움이 되는지 판단하기 위한 검증 기록이다. 실제 개인 calendar title, description, attendee, token, OAuth client secret은 이 문서에 저장하지 않는다.

## 판단 기준

- Calendar context는 transcript보다 낮은 우선순위의 보조 근거다.
- Calendar event가 현재 회의와 정확히 맞을 때만 meeting identity와 prompt context에 강하게 반영한다.
- 반복 회의는 `recurringEventId` 기반 series identity를 우선 사용한다.
- 관련 없는 event는 후보와 prompt context를 오염시키지 않는다.
- Calendar description의 링크는 자동 주입 근거가 아니라 사용자가 확인할 후보로만 보여준다.
- Test Run은 live Google API나 Calendar MCP를 호출하지 않고 저장된 `CalendarContextState` snapshot만 재사용한다.

## 익명화된 검증 매트릭스

| 시나리오 | Snapshot / Fixture | 기대 개선 | 관찰 결과 | 상태 |
| --- | --- | --- | --- | --- |
| 현재 event 정확 매칭 | 동일한 time window, 정확한 `Zigbang(2F)_Meeting Room L3` location, recurring event id | meeting identity가 calendar series를 사용하고, event가 자동 accepted 처리되며, calendar metadata가 supplemental context로 prompt에 들어간다 | `GoogleCalendarContextMapperTests.mapsEventsToCalendarContextState`가 accepted candidate, `calendar:series-1`, 제한된 description, calendar metadata source를 검증한다 | 통과 |
| 겹치는 후보가 있는 경우 | 두 개의 overlapping event: participant-only event 1개, exact room/time event 1개 | exact room/time event가 participant-only overlap보다 높은 순위를 갖는다 | `exactRoomAndTimeOutranksParticipantOnlyOverlap`가 exact room/time candidate가 첫 번째로 정렬되고 identity가 되는지 검증한다 | 통과 |
| 회의실 불일치 | `Zigbang(2F)` vs `Zigbang(2F)_Meeting Room L3` | 비슷해 보이는 room name이 강한 identity를 만들지 않는다 | `keepsLowConfidenceCandidateWhenRoomDiffers`가 event를 candidate로만 유지하고 identity/context를 만들지 않는지 검증한다 | 통과 |
| 관련 없는 event | time, room, title, attendee가 모두 다름 | event가 노출되지 않고 analysis를 오염시키지 않는다 | `dropsEventsWithoutUsefulOverlap`가 candidates/context/identity가 비어 있는지 검증한다 | 통과 |
| 링크가 많은 description | accepted event description에 Google Docs와 일반 URL이 포함됨 | link는 prompt에 주입되는 evidence가 아니라 accepted되지 않은 supplemental candidate로만 표시된다 | `mapsDescriptionLinksToSupplementalContextCandidates`가 `isAccepted == false`인 `.linkedSourceCandidate` source 2개를 검증한다 | 통과 |
| Calendar/transcript 충돌 | Calendar context의 room/attendee가 transcript와 다름 | prompt가 transcript-derived meeting metadata를 우선하도록 model에 지시한다 | `promptForbidsCalendarMetadataFromReplacingTranscriptMetadata`가 명시적 instruction을 검증한다 | 통과 |
| Test Run 재생 | 저장된 calendar context에 accepted/dismissed candidates, metadata source, identity가 있음 | replay가 live API/MCP fetch 없이 cached snapshot을 사용하고 candidate state를 보존한다 | `AppViewModelTestRunContextTests`가 `cachedReplay`, candidate state 보존, source 보존, Test Run path에 live fetch symbol이 없음을 검증한다 | 통과 |

## 제품 판단

현재 deterministic evidence는 Google Calendar context가 supplemental context로 명확히 제한될 때 계속 노출해도 된다는 쪽을 지지한다:

- high-confidence event match가 있을 때 recurring meeting identity가 개선된다.
- `recurringEventId`를 안정적인 series key로 보존해 carry-over risk를 낮춘다.
- time, room, participant, title signal이 없는 event를 제거해 noise를 줄인다.
- prompt에 transcript-derived metadata를 calendar metadata로 덮어쓰지 말라고 명시해 transcript authority를 보호한다.
- linked docs를 prompt에 조용히 주입하지 않고, 사용자가 확인할 수 있는 후보로 만든다.
- 저장된 calendar context를 `cachedReplay`로 재생하므로 Test Run 재현성이 유지된다.

남은 제품 질문은 data path가 동작하는지가 아니라 실제 회의 output이 눈에 띄게 좋아지는지다. 이를 확인하려면 private data를 redaction한 뒤 live 또는 saved real-world comparison을 수행해야 한다.

## 수동 Smoke 메모

- Release-style build는 다음 명령으로 실행한다:
  - `scripts/build_app.sh`
  - 기본 OAuth config path는 gitignored `private/GoogleCalendarOAuthConfig.json`이다.
  - 다른 위치를 써야 할 때만 `GOOGLE_CALENDAR_OAUTH_CONFIG_FILE=/path/to/client_secret_*.json scripts/build_app.sh`로 override한다.
- token이 없는 local smoke에서 기대하는 결과:
  - config lookup 성공,
  - smoke가 예상된 login/token state에서 중단,
  - `OAuth config가 없습니다`가 표시되면 안 됨.
- 실제 OAuth fetch validation은 count와 익명화된 관찰값만 기록한다:
  - connected/disconnected state,
  - fetched event count,
  - persisted candidate count,
  - Test Run replay가 `cachedReplay`를 사용했는지,
  - disconnect가 Keychain refresh token을 제거했는지.

### 2026-06-08 Local Smoke 결과

- Build:
  - `scripts/build_app.sh`
  - 결과: 통과. `dist/Meeting Rescue.app`이 bundled `GoogleCalendarOAuthConfig.json`을 포함해 build되었다.
- Smoke:
  - `"dist/Meeting Rescue.app/Contents/MacOS/MeetingRescue" --google-calendar-smoke --allow-empty-events`
  - 결과: 통과.
  - 익명화된 output:
    - OAuth Keychain token present.
    - Google Calendar events fetched: 7.
    - persisted candidates: 7.
    - cached replay status: `cachedReplay`.
    - disconnect: skipped.
- event title, attendee, description, access token, refresh token, client secret value는 이 문서에 복사하지 않았다.

### 2026-06-09 GUI Test Run 결과

- Build:
  - `scripts/build_app.sh`
  - 결과: 통과. gitignored `private/GoogleCalendarOAuthConfig.json`이 app bundle의 `GoogleCalendarOAuthConfig.json`으로 복사되었다.
- UI 경로:
  - `dist/Meeting Rescue.app` 직접 실행.
  - Context tab에서 Google Calendar API 연결 상태 확인.
  - `가져오기`로 현재 회의 시간대 event 후보 7개 저장.
  - History의 play action으로 같은 transcript를 Test Run replay.
  - 수동 analysis 1회 실행 후 Live Watch로 전환해 후속 automatic analysis를 중단.
- 익명화된 state 확인:
  - saved calendar context status: `connected`.
  - Test Run calendar context status: `cachedReplay`.
  - replayed candidate count: 7.
  - accepted event count: 0.
  - supplemental source count: 0.
  - meeting identity present: false.
  - manual Test Run analysis: succeeded.
  - interrupted follow-up automatic analysis: skipped by Live Watch transition.
- 제품 판단:
  - Google Calendar API fetch, 저장, Test Run replay 경로는 실제 UI에서도 동작한다.
  - 그러나 실제 recurring meeting 1건에서는 calendar event가 후보로만 남고 자동 accepted/identity/supplemental context로 승격되지 않았다.
  - 따라서 현재 구현만으로는 calendar context가 analysis 품질을 개선한다고 판단하기 어렵다.
  - 다음 hardening은 room/title normalization을 보강해 recurring meeting 후보가 충분히 높은 confidence일 때 자동 accepted/identity/supplemental context까지 이어지는지 검증해야 한다.
- 이 문서에는 실제 event title, attendee, description, linked document URL, transcript 원문을 저장하지 않았다.

## 후속 결정

D3/team feature로 넘어가기 전에 실제 recurring meeting 1-2개로 다음을 비교한다:

1. Calendar context 없음.
2. 저장된 Google Calendar context 있음.
3. 저장된 context를 사용하는 Test Run replay.

예를 들어 다음과 같이 익명화된 delta만 기록한다:

| 회의 유형 | Calendar context 효과 | 유지 / 조정 |
| --- | --- | --- |
| Weekly recurring | carry-over가 올바른 이전 open question을 선택했는가? | 실제 run 이후 TBD |
| Spot meeting | attendee/title overlap이 도움이 되었는가, noise를 만들었는가? | 실제 run 이후 TBD |
| Conflicting event | transcript-first instruction이 잘못된 metadata 반영을 막았는가? | 실제 run 이후 TBD |
