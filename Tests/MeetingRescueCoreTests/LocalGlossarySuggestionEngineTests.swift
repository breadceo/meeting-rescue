import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossarySuggestionEngineTests {
    @Test("history scan groups likely STT variants into one suggestion")
    func groupsLikelySTTVariants() throws {
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

        let suggestion = try #require(suggestions.first)
        #expect(suggestion.aliases == ["jax", "jecks", "zacks"])
        #expect(suggestion.occurrenceCount == 3)
        #expect(suggestion.meetingCount == 2)
        #expect(suggestion.confidence >= 0.60)
        #expect(suggestion.evidence.count == 3)
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
                id: "meeting-1",
                title: "Product Sync",
                sections: [
                    .init(field: .rawTranscript, text: "[03:12] Alex: jax workflow", weight: 24, timestamp: "03:12"),
                    .init(field: .rawTranscript, text: "[03:18] Alex: jecks workflow", weight: 24, timestamp: "03:18")
                ]
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
