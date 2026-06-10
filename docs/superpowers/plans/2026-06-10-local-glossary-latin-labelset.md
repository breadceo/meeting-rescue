# Local Glossary Latin Performance And Label Set Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speed up the opt-in Latin glossary smoke lane and add a local label set that scores whether a candidate is likely to improve summary/search quality after canonical promotion.

**Architecture:** Keep the app default behavior unchanged: Latin suggestions remain off unless the scoring runner passes `--include-latin`. Optimize the Latin smoke lane inside `LocalGlossarySuggestionEngine` by grouping occurrences with normalized phonetic buckets before variant comparison. Add a small Codable label model and runner output field so offline reports can explain whether each candidate looks useful for summary/search canonicalization.

**Tech Stack:** Swift Package, Swift Testing, local JSON reports, existing `LocalGlossarySuggestionEngine` and `LocalGlossaryScoringRunner`.

---

## File Structure

- Modify `Sources/MeetingRescueCore/LocalGlossaryModels.swift`
  - Add `LocalGlossaryCandidateImpactLabel`.
  - Add `impactLabel` to `LocalGlossarySuggestionScore` with backward-compatible decoding.
- Modify `Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift`
  - Replace Latin sequential cluster scan with phonetic-key buckets.
  - Compute context overlap for Latin candidates.
  - Attach impact label to Latin and Korean scores.
- Modify `Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift`
  - Attach impact label to Korean score from existing scoring signals.
- Modify `Sources/MeetingRescue/LocalGlossaryScoringRunner.swift`
  - Include `impactLabel` in candidate report.
  - Make Latin smoke warning disappear when optimized below 15 seconds.
- Modify tests:
  - `Tests/MeetingRescueCoreTests/LocalGlossaryModelsTests.swift`
  - `Tests/MeetingRescueCoreTests/LocalGlossarySuggestionEngineTests.swift`
  - `Tests/MeetingRescueTests/LocalGlossaryScoringRunnerTests.swift`

## Task 1: Label Model And Report Surface

- [ ] Write failing model test proving `LocalGlossarySuggestionScore` round-trips an impact label and decodes older JSON without it.
- [ ] Run:

```bash
swift test --filter 'LocalGlossaryModelsTests'
```

Expected: FAIL because `impactLabel` does not exist.

- [ ] Add `LocalGlossaryCandidateImpactLabel` with fields:
  - `summarySearchImpact`
  - `summarySearchReasons`
  - `qualityTier`
- [ ] Add `impactLabel` to `LocalGlossarySuggestionScore`, defaulting to a strict-filter low-confidence label for old JSON.
- [ ] Run the same test and verify PASS.

## Task 2: Latin Bucketed Clustering

- [ ] Write failing engine test that checks the Latin implementation contains bucketed clustering and still keeps `faq/faqq/faqu`.
- [ ] Run:

```bash
swift test --filter 'LocalGlossarySuggestionEngineTests'
```

Expected: FAIL on bucketed clustering expectation.

- [ ] Replace sequential Latin clustering with `clusterOccurrencesByBucket`.
- [ ] Bucket by `phoneticKey` and neighbor keys, then union candidates only within each bucket.
- [ ] Preserve rejection reasons for known noise, name-like clusters, and broad acronym clusters.
- [ ] Run the engine tests and verify PASS.

## Task 3: Impact Label Scoring

- [ ] Write failing tests that `유자 안드로이드/유저 안드로이드` receives a strong impact label and `faq/faqq/faqu` receives at least a plausible label only in Latin smoke.
- [ ] Implement `impactLabelForCandidate` from existing score fields:
  - high when at least two of recurrence, similarity, context, termhood are strong.
  - medium when two are plausible.
  - low when only strict filters pass.
- [ ] Add impact label to runner candidate output.
- [ ] Run:

```bash
swift test --filter 'LocalGlossaryModelsTests|LocalGlossarySuggestionEngineTests|LocalGlossaryScoringRunnerTests'
```

Expected: PASS.

## Task 4: Offline Verification

- [ ] Run default app scoring:

```bash
swift run MeetingRescue --local-glossary-score --folder /Users/ethan/Documents/Recordings --limit 40 --output .build/local-glossary-score-report.json
```

Expected: exit 0, quality gate pass.

- [ ] Run Latin smoke scoring:

```bash
swift run MeetingRescue --local-glossary-score --folder /Users/ethan/Documents/Recordings --limit 40 --include-latin --output .build/local-glossary-score-latin-report.json
```

Expected: exit 0, `suggestionMilliseconds <= 15000`, no `latin-smoke-suggestion-over-15s` warning.

- [ ] Run final verification:

```bash
swift test --filter 'LocalGlossaryModelsTests|LocalGlossaryHistoryScannerTests|LocalGlossarySuggestionEngineTests|AppViewModelTestRunContextTests|ContentViewContextWiringTests|LocalGlossaryScoringRunnerTests'
swift build
scripts/build_app.sh
git diff --check
```

Expected: all pass.
