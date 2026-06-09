import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossaryModelsTests {
    @Test("accepted suggestion creates enabled local glossary term and removes suggestion")
    func acceptedSuggestionCreatesEnabledTerm() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        var state = LocalGlossaryState(
            suggestions: [
                LocalGlossarySuggestion(
                    id: "suggestion-zax",
                    suggestedCanonical: "zax",
                    aliases: ["jax", "jecks", "zacks"],
                    evidence: [
                        LocalGlossaryEvidence(
                            sourceID: "meeting-1",
                            sourceTitle: "Product Sync",
                            excerpt: "Alex: jax 쪽 workflow를 다시 봅시다.",
                            timestamp: "03:12"
                        )
                    ],
                    occurrenceCount: 7,
                    meetingCount: 3,
                    confidence: 0.82,
                    createdAt: fixedDate
                )
            ],
            updatedAt: fixedDate
        )

        state.acceptSuggestion(id: "suggestion-zax", canonical: "zax", category: .project)

        #expect(state.suggestions.isEmpty)
        #expect(state.terms.count == 1)
        #expect(state.terms[0].canonical == "zax")
        #expect(state.terms[0].aliases == ["jax", "jecks", "zacks"])
        #expect(state.terms[0].category == .project)
        #expect(state.terms[0].isEnabled)
        #expect(state.terms[0].source == .suggested)
    }

    @Test("dismissed suggestion ids survive encode and decode")
    func dismissedSuggestionIDsSurviveRoundTrip() throws {
        var state = LocalGlossaryState(updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        state.dismissSuggestion(id: "suggestion-zax")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LocalGlossaryState.self, from: data)

        #expect(decoded.dismissedSuggestionIDs == Set(["suggestion-zax"]))
        #expect(decoded.suggestions.isEmpty)
    }

    @Test("ApplicationStateStore saves and loads local glossary state")
    func stateStorePersistsLocalGlossary() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ApplicationStateStore(rootURL: root)
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let state = LocalGlossaryState(
            terms: [
                LocalGlossaryTerm(
                    id: "term-zax",
                    canonical: "zax",
                    aliases: ["jax", "jecks"],
                    category: .project,
                    note: "STT가 자주 틀리는 사내 프로젝트명",
                    source: .manual,
                    createdAt: fixedDate,
                    updatedAt: fixedDate
                )
            ],
            updatedAt: fixedDate
        )

        try store.saveLocalGlossaryState(state)
        let loaded = store.loadLocalGlossaryState()

        #expect(loaded == state)
    }
}
