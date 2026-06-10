# Local Glossary Hardening Validation

Date: 2026-06-10

## Scope

D2.6 Local Glossary Hardening validates:

- raw transcript folder scanning
- Korean phrase suggestions
- Meeting Intelligence `용어` review flow
- canonical editing before accept
- raw transcript CTA

## Synthetic Fixtures

Latin fixture:

```text
[00:10] Ethan: jax workflow를 봅니다.
[00:20] Ethan: jecks workflow를 봅니다.
[00:30] Ethan: zacks workflow를 봅니다.
```

Korean fixture:

```text
[00:10] Ethan: 중개사 응답률 채팅 지표를 봅니다.
[00:20] Ethan: 중계사 응답률 채팅 전환을 봅니다.
[00:30] Ethan: 아이오에스 마케팅 지표를 봅니다.
[00:40] Ethan: 아이유에스 마케팅 전환을 봅니다.
```

## Expected Behavior

- Meeting Intelligence shows a `용어` lane.
- Raw Transcript footer shows local glossary candidate/match counts.
- `후보 새로 찾기` scans raw transcript files from the selected folder.
- Korean variants are shown only as suggestions.
- User can edit canonical text before accepting a suggestion.
- Accepted terms are the only glossary values injected as `domainGlossary` supplemental context.
- Settings no longer hosts the suggestion review list.

## Verification Commands

```bash
swift test --filter LocalGlossaryHistoryScannerTests
swift test --filter LocalGlossarySuggestionEngineTests
swift test --filter AppViewModelTestRunContextTests
swift test --filter ContentViewContextWiringTests
swift test
swift build
git diff --check
```
