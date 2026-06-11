import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossarySuggestionEngineTests {
    @Test("default engine suppresses Latin-only suggestions until the quality gate is proven")
    func defaultEngineSuppressesLatinOnlySuggestions() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: jax workflow를 다시 보죠.", weight: 24, timestamp: "03:12"),
                    .init(field: .topic, text: "jecks 품질 검토", weight: 58, timestamp: "03:30")
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-2",
                title: "AI Workflow",
                sections: [
                    .init(field: .rawTranscript, text: "[04:01] Blair: zacks 쪽 summary가 흔들립니다.", weight: 24, timestamp: "04:01")
                ]
            )
        ]

        let suggestions = LocalGlossarySuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState()
        )

        #expect(suggestions.isEmpty)
    }

    @Test("suggestion engine returns diagnostics for later bottleneck review")
    func suggestionEngineReturnsDiagnostics() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: 중개사 응답률 채팅 지표를 봅니다.", weight: 24)
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-2",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: 중개사 응답률 채팅 전환을 봅니다.", weight: 24)
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-3",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: 중계사 응답률 채팅 지표를 봅니다.", weight: 24)
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-4",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: 중계사 응답률 채팅 전환을 봅니다.", weight: 24)
                ]
            )
        ]

        let result = LocalGlossarySuggestionEngine.suggestionsWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        #expect(result.diagnostics.documentCount == 4)
        #expect(result.diagnostics.sectionCount == 4)
        #expect(result.diagnostics.latinSuggestionCount == 0)
        #expect(result.diagnostics.latinMilliseconds == 0)
        #expect(result.diagnostics.koreanSuggestionCount >= 1)
        #expect(result.diagnostics.korean.occurrenceCount > 0)
        #expect(result.diagnostics.korean.candidateCount > 0)
        #expect(result.diagnostics.mergedSuggestionCount == result.suggestions.count)
    }

    @Test("suggestions expose scoring breakdown for quality calibration")
    func suggestionsExposeScoringBreakdown() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Growth Metrics 1",
                sections: [
                    .init(field: .rawTranscript, text: "[01:17] Ethan: 마케팅 유자가 안드로이드 지표를 봅니다.", weight: 24)
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-2",
                title: "Growth Metrics 2",
                sections: [
                    .init(field: .rawTranscript, text: "[01:20] Ethan: 마케팅 유저가 안드로이드 전환을 봅니다.", weight: 24)
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-3",
                title: "Growth Metrics 3",
                sections: [
                    .init(field: .rawTranscript, text: "[01:30] Ethan: 오가닉 유자가 안드로이드 지표를 봅니다.", weight: 24)
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-4",
                title: "Growth Metrics 4",
                sections: [
                    .init(field: .rawTranscript, text: "[01:40] Ethan: 오가닉 유저가 안드로이드 전환을 봅니다.", weight: 24)
                ]
            )
        ]

        let suggestion = try #require(
            LocalGlossarySuggestionEngine.suggestions(
                from: documents,
                existingState: LocalGlossaryState(),
                maxSuggestions: 8
            ).first { $0.aliases.contains("유자 안드로이드") }
        )

        #expect(suggestion.score.phoneticSimilarity >= 0.80)
        #expect(suggestion.score.graphemicSimilarity >= 0.70)
        #expect(suggestion.score.contextOverlap > 0)
        #expect(suggestion.score.termhood > 0)
        #expect(suggestion.score.recurrence > 0)
        #expect(suggestion.score.noisePenalty == 0)
        #expect(suggestion.score.finalScore == suggestion.confidence)
        #expect(suggestion.score.matchedCriteria.count >= 2)
        #expect(suggestion.score.impactLabel.qualityTier == "high")
        #expect(suggestion.score.impactLabel.summarySearchImpact >= 0.80)
        #expect(suggestion.score.impactLabel.summarySearchReasons.contains("canonical-would-normalize-summary"))
        #expect(suggestion.score.impactLabel.summarySearchReasons.contains("improves-history-search"))
    }

    @Test("default engine suppresses emails speaker labels and Latin name clusters")
    func defaultEngineSuppressesEmailsSpeakerLabelsAndLatinNameClusters() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .participant, text: "Ethan Kim(ethan@zigbang.com)", weight: 84),
                    .init(field: .rawTranscript, text: "[03:12] Ethan Kim(ethan@zigbang.com): jax workflow를 봅니다.", weight: 24)
                ]
            ),
            LocalGlossarySourceDocument(
                id: "meeting-2",
                title: "Product Sync",
                sections: [
                    .init(field: .participant, text: "Ethun Kym(ethun@zigbang.com)", weight: 84),
                    .init(field: .rawTranscript, text: "[04:01] Ethun Kym(ethun@zigbang.com): jecks workflow를 봅니다.", weight: 24)
                ]
            )
        ]

        let suggestions = LocalGlossarySuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )
        let aliases = Set(suggestions.flatMap(\.aliases))

        #expect(suggestions.isEmpty)
        #expect(!aliases.contains("ethan"))
        #expect(!aliases.contains("ethun"))
        #expect(!aliases.contains("zigbang"))
        #expect(!aliases.contains("com"))
        #expect(!aliases.contains("kim"))
        #expect(!aliases.contains("kym"))
    }

    @Test("Latin scoring smoke suppresses name-like clusters")
    func latinScoringSmokeSuppressesNameLikeClusters() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "People Sync 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: mila joined the sync.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "People Sync 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: nila joined the sync.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "People Sync 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: mila joined the sync.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "People Sync 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: nila joined the sync.", weight: 24)]
            )
        ]

        let result = LocalGlossarySuggestionEngine.suggestionsWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8,
            includeLatin: true
        )

        #expect(result.suggestions.isEmpty)
        #expect((result.diagnostics.rejectionSummary["latin-name-like"] ?? 0) >= 1)
    }

    @Test("Latin scoring smoke can keep allowlisted domain-looking variants")
    func latinScoringSmokeKeepsAllowlistedDomainVariants() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Support 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: faq import flow를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Support 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: faqq import flow를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Support 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: faqu import flow를 봅니다.", weight: 24)]
            )
        ]

        let suggestion = try #require(
            LocalGlossarySuggestionEngine.suggestionsWithDiagnostics(
                from: documents,
                existingState: LocalGlossaryState(),
                maxSuggestions: 8,
                includeLatin: true
            ).suggestions.first
        )

        #expect(suggestion.aliases.contains("faq"))
        #expect(suggestion.score.finalScore > 0)
        #expect(suggestion.score.impactLabel.qualityTier == "medium")
        #expect(suggestion.score.impactLabel.summarySearchImpact >= 0.40)
        #expect(suggestion.score.impactLabel.summarySearchReasons.contains("canonical-would-normalize-summary"))
    }

    @Test("Latin scoring smoke clusters unique tokens through bounded phonetic buckets")
    func latinScoringSmokeUsesBoundedPhoneticBuckets() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescueCore/LocalGlossarySuggestionEngine.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let clusterSource = try #require(source.slice(from: "private static func clusterOccurrences", to: "private static func shouldScanLatinSection"))

        #expect(clusterSource.contains("Dictionary(grouping: occurrences, by: \\.token)"))
        #expect(clusterSource.contains("latinBucketKeys(for:"))
        #expect(clusterSource.contains("clusterTokenGroups"))
        #expect(!clusterSource.contains("clusters.firstIndex"))
    }

    @Test("summary search impact label calibration set stays stable")
    func summarySearchImpactLabelCalibrationSet() throws {
        try assertImpactLabelFixture("local-glossary-impact-labels")
    }

    @Test("actual transcript derived impact label calibration set stays stable")
    func actualTranscriptDerivedImpactLabelCalibrationSet() throws {
        try assertImpactLabelFixture("local-glossary-impact-labels-actual")
    }

    @Test("suggestion engine exposes exploratory review candidates separately from strict suggestions")
    func suggestionEngineExposesReviewCandidates() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Growth 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Growth 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성 유전 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Growth 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성제 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Growth 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 전환을 봅니다.", weight: 24)]
            )
        ]

        let result = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8,
            maxReviewCandidates: 20
        )

        #expect(result.suggestions.allSatisfy { $0.lane == .strict })
        #expect(result.reviewCandidates.contains { candidate in
            candidate.lane == .review
                && candidate.aliases.contains("신규활성제")
                && candidate.aliases.contains("신규 활성 유저")
        })
    }

    @Test("rejected review candidates are excluded from future review results")
    func rejectedReviewCandidatesAreExcluded() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Metrics 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 대비 포인트를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Metrics 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 대비로 포인트를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Metrics 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 대비 포인트를 다시 봅니다.", weight: 24)]
            )
        ]
        let first = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8,
            maxReviewCandidates: 20
        )
        let rejectedID = try #require(first.reviewCandidates.first?.id)
        let state = LocalGlossaryState(rejectedSuggestionIDs: [rejectedID])

        let second = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: state,
            maxSuggestions: 8,
            maxReviewCandidates: 20
        )

        #expect(!second.reviewCandidates.contains { $0.id == rejectedID })
    }

    @Test("Korean review lane filters generic conversational variants")
    func koreanReviewLaneFiltersGenericConversationalVariants() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Daily 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 데이터 확인을 하고 있는 상태입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Daily 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 데이터 확인을 하고 있는데 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Daily 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 데이터 정리를 하고 있는 상황입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Daily 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 데이터 정리를 하고 있는데 공유합니다.", weight: 24)]
            )
        ]

        let result = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8,
            maxReviewCandidates: 20
        )

        #expect(!result.reviewCandidates.contains { candidate in
            candidate.aliases.contains("하고 있는")
                || candidate.aliases.contains("하고 있는데")
                || candidate.aliases.contains("요렇게")
                || candidate.aliases.contains("이렇게")
            })
    }

    @Test("Korean review lane keeps noun-like terms but filters predicative variants")
    func koreanReviewLanePrefersNounLikeTermsOverPredicativeVariants() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "noun-1",
                title: "Growth 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "noun-2",
                title: "Growth 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성 유전 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "noun-3",
                title: "Growth 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성제 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "noun-4",
                title: "Growth 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-1",
                title: "Delivery 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포 작업한 기준을 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-2",
                title: "Delivery 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포 작업할 기준을 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-3",
                title: "Delivery 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정산 작업한 기준을 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-4",
                title: "Delivery 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정산 작업할 기준을 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-5",
                title: "Planning 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 마케팅 가능한지 일정을 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-6",
                title: "Planning 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 마케팅 가능할지 일정을 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-7",
                title: "Planning 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포 가능한지 일정을 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "verb-8",
                title: "Planning 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포 가능할지 일정을 확인합니다.", weight: 24)]
            )
        ]

        let result = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8,
            maxReviewCandidates: 50
        )
        let allCandidates = result.suggestions + result.reviewCandidates

        #expect(allCandidates.contains { candidate in
            candidate.aliases.contains("신규활성제")
                && candidate.aliases.contains("신규 활성 유저")
        })
        #expect(!allCandidates.contains { candidate in
            let compactAliases = candidate.aliases.map(MeetingHistorySearch.compactNormalize)
            return compactAliases.contains { alias in
                alias.contains("작업한")
                    || alias.contains("작업할")
                    || alias.contains("가능한지")
                    || alias.contains("가능할지")
            }
        })
    }

    @Test("Korean review lane filters conversational prefix plus noun candidates")
    func koreanReviewLaneFiltersConversationalPrefixNounCandidates() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Growth 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 보면 오가닉 유저 지표가 달라집니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Growth 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 보면 오가닉 유전 지표가 달라집니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Growth 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 그다음 임대인 설정을 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Growth 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 그다음 임대인 섧정을 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m5",
                title: "Growth 5",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 그러니까 예를 들면 전환율 기준입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m6",
                title: "Growth 6",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 그러니까 예를 들면 전환률 기준입니다.", weight: 24)]
            )
        ]

        let result = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8,
            maxReviewCandidates: 50
        )
        let allCandidates = result.suggestions + result.reviewCandidates

        #expect(!allCandidates.contains { candidate in
            let compactAliases = candidate.aliases.map(MeetingHistorySearch.compactNormalize)
            return compactAliases.contains { alias in
                alias.hasPrefix("보면")
                    || alias.hasPrefix("그다음")
                    || alias.hasPrefix("그러니까")
            }
        })
    }

    @Test("Korean review lane filters transcript-derived predicate and filler variants")
    func koreanReviewLaneFiltersTranscriptDerivedPredicateAndFillerVariants() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "noun-1",
                title: "Growth 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "noun-2",
                title: "Growth 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성 유전 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "noun-3",
                title: "Growth 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규활성제 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "noun-4",
                title: "Growth 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 신규 활성 유저 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-1",
                title: "Ops 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포를 해야 되고 일정도 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-2",
                title: "Ops 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포를 해야 되나 일정도 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-3",
                title: "Ops 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 화면을 보여주고 기준을 맞춥니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-4",
                title: "Ops 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 화면을 보여줄 기준을 맞춥니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-5",
                title: "Ops 5",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 매물을 등록하 기준으로 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-6",
                title: "Ops 6",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 매물을 등록하기 기준으로 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-7",
                title: "Ops 7",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 리텐션 보면 디원 지표입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-8",
                title: "Ops 8",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 리텐션 보면 디월 지표입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-9",
                title: "Ops 9",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 데이터를 가지고 있는 상태입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-10",
                title: "Ops 10",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 데이터를 갖고 있는 상태입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-11",
                title: "Ops 11",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포할 수도 있는 상황입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-12",
                title: "Ops 12",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 배포할 수도 있을 상황입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-13",
                title: "Ops 13",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 이번에 해보려고 합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-14",
                title: "Ops 14",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 이번에 해볼려고 합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-15",
                title: "Ops 15",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중요한 기준을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-16",
                title: "Ops 16",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중요할 기준을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-17",
                title: "Ops 17",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 가능성이 있을 거고 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-18",
                title: "Ops 18",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 가능성이 있을 거라고 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-19",
                title: "Ops 19",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 같아서 한번 이따 보겠습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-20",
                title: "Ops 20",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 같아서 한번 있다 보겠습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-21",
                title: "Ops 21",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 자료를 주시고 확인합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-22",
                title: "Ops 22",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 자료를 주시기 바랍니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-23",
                title: "Ops 23",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 지표를 얘기하면 됩니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-24",
                title: "Ops 24",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 지표를 얘기하면서 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-25",
                title: "Ops 25",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 문제는 없습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-26",
                title: "Ops 26",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 문제는 않습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-27",
                title: "Ops 27",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 금요일 대비 증가했습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-28",
                title: "Ops 28",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 금요일 대비 증가는 없습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-29",
                title: "Ops 29",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 매물 노출하 기준을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-30",
                title: "Ops 30",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 매물 노출할 기준을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-31",
                title: "Ops 31",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 매물 노출해 기준을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-32",
                title: "Ops 32",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 다시 보려고 합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-33",
                title: "Ops 33",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 다시 볼려고 합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-34",
                title: "Ops 34",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 다음 주 예정이에 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-35",
                title: "Ops 35",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 다음 주 예정이라 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-36",
                title: "Ops 36",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 있어서 요거는 제외합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-37",
                title: "Ops 37",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 있어서 고거는 제외합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-38",
                title: "Ops 38",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 전주 대비 증가 주전 수치입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-39",
                title: "Ops 39",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 전주 대비 증가 주년 수치입니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-40",
                title: "Ops 40",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 전환율 초의 전환율은 제외합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-41",
                title: "Ops 41",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 이 부분을 고민 하고 있습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-42",
                title: "Ops 42",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 이 부분을 고민 하다 보면 됩니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-42b",
                title: "Ops 42b",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 이 기준을 고민 하고 있습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-42c",
                title: "Ops 42c",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 이 기준을 고민 하다 정리합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-43",
                title: "Ops 43",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 가능하시면 확인해 주세요.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-44",
                title: "Ops 44",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 없으시면 확인해 주세요.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-44b",
                title: "Ops 44b",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 있으시면 확인해 주세요.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-44c",
                title: "Ops 44c",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 없으시면 공유해 주세요.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-44d",
                title: "Ops 44d",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 있으시면 공유해 주세요.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-45",
                title: "Ops 45",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 지금 상황인 것 같습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-46",
                title: "Ops 46",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 지금 상황인데 공유합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-46b",
                title: "Ops 46b",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 현재 상황인 것 같습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "predicate-46c",
                title: "Ops 46c",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 현재 상황인데 공유합니다.", weight: 24)]
            )
        ]

        let result = LocalGlossarySuggestionEngine.suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8,
            maxReviewCandidates: 50
        )
        let allCandidates = result.suggestions + result.reviewCandidates

        #expect(allCandidates.contains { candidate in
            candidate.aliases.contains("신규활성제")
                && candidate.aliases.contains("신규 활성 유저")
        })
        #expect(!allCandidates.contains { candidate in
            let compactAliases = candidate.aliases.map(MeetingHistorySearch.compactNormalize)
            return compactAliases.contains { alias in
                alias.contains("해야되")
                    || alias.contains("보여주")
                    || alias.contains("등록하")
                    || alias.contains("보면")
                    || alias.contains("가지고있는")
                    || alias.contains("갖고있는")
                    || alias.contains("수도있는")
                    || alias.contains("수도있을")
                    || alias.contains("해보려고")
                    || alias.contains("해볼려고")
                    || alias.contains("중요한")
                    || alias.contains("중요할")
                    || alias.contains("있을거")
                    || alias.contains("같아서")
                    || alias.contains("주시")
                    || alias.contains("얘기하")
                    || alias.contains("없습니다")
                    || alias.contains("않습니다")
                    || alias.contains("금요일")
                    || alias.contains("노출하")
                    || alias.contains("노출할")
                    || alias.contains("노출해")
                    || alias.contains("보려고")
                    || alias.contains("볼려고")
                    || alias.contains("예정이")
                    || alias.contains("예정이라")
                    || alias.contains("있어서")
                    || alias.contains("요거")
                    || alias.contains("고거")
                    || alias.contains("주전")
                    || alias.contains("초의")
                    || alias.contains("고민하고")
                    || alias.contains("고민하다")
                    || alias.contains("없으시면")
                    || alias.contains("있으시면")
                    || alias.contains("가능하시면")
                    || alias.contains("상황인")
                    || alias.contains("상황인데")
            }
        })
    }

    private func assertImpactLabelFixture(_ resourceName: String) throws {
        let cases = try impactLabelFixtureCases(resourceName)
        for testCase in cases {
            let documents = testCase.documents.map { document in
                LocalGlossarySourceDocument(
                    id: document.id,
                    title: document.title,
                    sections: document.sections.map {
                        MeetingHistorySearchSection(
                            field: .rawTranscript,
                            text: $0,
                            weight: 24
                        )
                    }
                )
            }
            let suggestions = LocalGlossarySuggestionEngine.suggestionsWithDiagnostics(
                from: documents,
                existingState: LocalGlossaryState(),
                maxSuggestions: 8,
                includeLatin: testCase.includeLatin
            ).suggestions

            if testCase.expectCandidate {
                let suggestion = try #require(suggestions.first { suggestion in
                    suggestion.suggestedCanonical == testCase.expectedCanonical
                        || suggestion.aliases.contains(testCase.expectedCanonical)
                }, "missing expected candidate for \(testCase.name)")
                #expect(suggestion.score.impactLabel.qualityTier == testCase.expectedTier)
                #expect(suggestion.score.impactLabel.summarySearchImpact >= testCase.minimumImpact)
                for reason in testCase.expectedReasons {
                    #expect(suggestion.score.impactLabel.summarySearchReasons.contains(reason))
                }
            } else {
                #expect(!suggestions.contains { suggestion in
                    suggestion.suggestedCanonical == testCase.expectedCanonical
                        || suggestion.aliases.contains(testCase.expectedCanonical)
                })
            }
        }
    }

    private func impactLabelFixtureCases(_ resourceName: String) throws -> [ImpactLabelFixture] {
        let fixtureURL = try #require(Bundle.module.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode([ImpactLabelFixture].self, from: data)
    }

    @Test("accepted glossary aliases are excluded from new suggestions")
    func excludesAcceptedAliases() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: jax jecks zacks", weight: 24, timestamp: "03:12")
                ]
            )
        ]
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(canonical: "zax", aliases: ["jax", "jecks", "zacks"], category: .project)
        ])

        let suggestions = LocalGlossarySuggestionEngine.suggestions(from: documents, existingState: state)

        #expect(suggestions.isEmpty)
    }

    @Test("dismissed suggestions are not returned again")
    func excludesDismissedSuggestionIDs() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Product Sync 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Product Sync 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Product Sync 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중계사 응답률 채팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Product Sync 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중계사 응답률 채팅 전환을 봅니다.", weight: 24)]
            )
        ]
        let first = try #require(LocalGlossarySuggestionEngine.suggestions(from: documents, existingState: LocalGlossaryState()).first)
        let dismissed = LocalGlossaryState(dismissedSuggestionIDs: [first.id])

        let second = LocalGlossarySuggestionEngine.suggestions(from: documents, existingState: dismissed)

        #expect(second.isEmpty)
    }

    @Test("Korean lane groups recurring domain phrase variants")
    func koreanLaneGroupsDomainPhraseVariants() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Product Sync 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Product Sync 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Product Sync 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중계사 응답률 채팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Product Sync 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중계사 응답률 채팅 전환을 봅니다.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossaryKoreanSuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        let suggestion = try #require(suggestions.first { $0.aliases.contains("중개사 응답률 채팅") })
        #expect(suggestion.aliases.contains("중계사 응답률 채팅"))
        #expect(suggestion.meetingCount >= 4)
        #expect(suggestion.confidence >= 0.80)
    }

    @Test("Korean lane filters generic grammar ending variants")
    func koreanLaneFiltersGrammarEndingVariants() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Daily 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같아.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Daily 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같고.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Daily 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같아.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Daily 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 정리해 주시면 좋을 같고.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossaryKoreanSuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        #expect(suggestions.isEmpty)
    }

    @Test("Korean lane filters generic pointer phrase variants")
    func koreanLaneFiltersGenericPointerPhraseVariants() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Architecture Sync 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Peter: 요런 부분들을 계속 수정하고 있습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Architecture Sync 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Peter: 이런 부분들을 계속 수정하고 있습니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Architecture Sync 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Peter: 요런 부분들을 꼼꼼하게 확인해야 합니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Architecture Sync 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Peter: 이런 부분들을 꼼꼼하게 확인해야 합니다.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossaryKoreanSuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        #expect(!suggestions.contains { suggestion in
            suggestion.aliases.contains("요런 부분들") || suggestion.aliases.contains("이런 부분들")
        })
    }

    @Test("Korean lane does not pair one-off noisy variants")
    func koreanLaneDoesNotPairOneOffNoisyVariants() {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Product Sync 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Product Sync 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Product Sync 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 품질을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Product Sync 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중개사 응답률 채팅 전환 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m5",
                title: "Noisy One-Off",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 중계사 응답률 채팅 지표를 봅니다.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossaryKoreanSuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        #expect(!suggestions.contains { $0.aliases.contains("중계사 응답률 채팅") })
    }

    @Test("Korean lane bounds the comparison candidate pool")
    func koreanLaneBoundsComparisonCandidatePool() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescueCore/LocalGlossaryKoreanSuggestionEngine.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let candidatePairs = try #require(source.slice(from: "private static func candidatePairs", to: "private static func acceptsPair"))

        #expect(candidatePairs.contains("minimumOccurrenceSupportForPairing"))
        #expect(candidatePairs.contains("maxComparisonCandidates"))
        #expect(candidatePairs.contains(".prefix(maxComparisonCandidates)"))
    }

    @Test("merged suggestion engine includes Korean phrase suggestions")
    func mergedEngineIncludesKoreanPhraseSuggestions() throws {
        let documents = [
            LocalGlossarySourceDocument(
                id: "m1",
                title: "Marketing 1",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이오에스 마케팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m2",
                title: "Marketing 2",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이오에스 마케팅 전환을 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m3",
                title: "Marketing 3",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이유에스 마케팅 지표를 봅니다.", weight: 24)]
            ),
            LocalGlossarySourceDocument(
                id: "m4",
                title: "Marketing 4",
                sections: [.init(field: .rawTranscript, text: "[00:10] Ethan: 아이유에스 마케팅 전환을 봅니다.", weight: 24)]
            )
        ]

        let suggestions = LocalGlossarySuggestionEngine.suggestions(
            from: documents,
            existingState: LocalGlossaryState(),
            maxSuggestions: 8
        )

        let suggestion = try #require(suggestions.first { $0.aliases.contains("아이오에스 마케팅") })
        #expect(suggestion.aliases.contains("아이유에스 마케팅"))
    }
}

private struct ImpactLabelFixture: Decodable {
    var name: String
    var includeLatin: Bool
    var expectCandidate: Bool
    var expectedCanonical: String
    var expectedTier: String
    var minimumImpact: Double
    var expectedReasons: [String]
    var documents: [ImpactLabelFixtureDocument]
}

private struct ImpactLabelFixtureDocument: Decodable {
    var id: String
    var title: String
    var sections: [String]
}

private extension String {
    func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
              let end = range(of: endMarker, range: start..<endIndex)?.lowerBound else {
            return nil
        }
        return String(self[start..<end])
    }
}
