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
}
