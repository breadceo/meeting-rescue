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
