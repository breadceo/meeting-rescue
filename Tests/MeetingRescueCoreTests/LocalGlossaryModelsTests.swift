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

    @Test("replace suggestions removes stale generated candidates")
    func replaceSuggestionsRemovesStaleGeneratedCandidates() {
        var state = LocalGlossaryState(
            terms: [LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax"], category: .project)],
            suggestions: [
                LocalGlossarySuggestion(
                    id: "suggestion-stale",
                    suggestedCanonical: "cia",
                    aliases: ["ethan", "kim"],
                    evidence: [],
                    occurrenceCount: 20,
                    meetingCount: 10,
                    confidence: 0.95
                )
            ],
            dismissedSuggestionIDs: ["suggestion-dismissed"]
        )
        let replacement = LocalGlossarySuggestion(
            id: "suggestion-fresh",
            suggestedCanonical: "중개사 응답률",
            aliases: ["중개사 응답률", "중계사 응답률"],
            evidence: [],
            occurrenceCount: 4,
            meetingCount: 3,
            confidence: 0.84
        )
        let dismissed = LocalGlossarySuggestion(
            id: "suggestion-dismissed",
            suggestedCanonical: "숨긴 후보",
            aliases: ["숨긴 후보", "수긴 후보"],
            evidence: [],
            occurrenceCount: 4,
            meetingCount: 3,
            confidence: 0.84
        )

        state.replaceSuggestions([replacement, dismissed])

        #expect(state.terms.map(\.id) == ["term-zax"])
        #expect(state.suggestions.map(\.id) == ["suggestion-fresh"])
        #expect(state.dismissedSuggestionIDs == ["suggestion-dismissed"])
    }

    @Test("ApplicationStateStore appends local glossary refresh diagnostics as JSONL")
    func stateStoreAppendsLocalGlossaryRefreshDiagnostics() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meeting-rescue-glossary-diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ApplicationStateStore(rootURL: root)
        let entry = LocalGlossaryRefreshDiagnostic(
            id: "refresh-1",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            folderPath: "/tmp/transcripts",
            documentCount: 4,
            suggestionCount: 2,
            scanMilliseconds: 11,
            suggestionMilliseconds: 22,
            saveMilliseconds: 3,
            totalMilliseconds: 36,
            stages: [
                .init(name: "scan", elapsedMilliseconds: 11, detail: "documents=4"),
                .init(name: "suggest", elapsedMilliseconds: 22, detail: "suggestions=2")
            ],
            suggestions: [
                .init(
                    id: "suggestion:ko:1",
                    suggestedCanonical: "중개사 응답률",
                    aliases: ["중개사 응답률", "중계사 응답률"],
                    occurrenceCount: 5,
                    meetingCount: 4,
                    confidence: 0.87
                )
            ]
        )

        try store.appendLocalGlossaryRefreshDiagnostic(entry)

        let logURL = try store.localGlossaryRefreshDiagnosticsURL()
        let lines = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
        let data = try #require(lines.first?.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LocalGlossaryRefreshDiagnostic.self, from: data)

        #expect(logURL.path.hasSuffix("Logs/local-glossary-refresh.jsonl"))
        #expect(lines.count == 1)
        #expect(decoded == entry)
    }

    @Test("suggestion score carries summary search impact label with legacy fallback")
    func suggestionScoreCarriesSummarySearchImpactLabel() throws {
        let score = LocalGlossarySuggestionScore(
            phoneticSimilarity: 0.9,
            graphemicSimilarity: 0.8,
            contextOverlap: 0.7,
            termhood: 0.9,
            recurrence: 0.8,
            finalScore: 0.88,
            matchedCriteria: ["발음 유사", "주변 맥락"],
            impactLabel: LocalGlossaryCandidateImpactLabel(
                summarySearchImpact: 0.86,
                summarySearchReasons: ["canonical-would-normalize-summary", "improves-history-search"],
                qualityTier: "high"
            )
        )
        let data = try JSONEncoder().encode(score)
        let decoded = try JSONDecoder().decode(LocalGlossarySuggestionScore.self, from: data)

        #expect(decoded.impactLabel.qualityTier == "high")
        #expect(decoded.impactLabel.summarySearchImpact == 0.86)
        #expect(decoded.impactLabel.summarySearchReasons.contains("improves-history-search"))

        let legacyJSON = """
        {
          "phoneticSimilarity": 0.9,
          "graphemicSimilarity": 0.8,
          "contextOverlap": 0.7,
          "termhood": 0.9,
          "recurrence": 0.8,
          "noisePenalty": 0,
          "finalScore": 0.88,
          "matchedCriteria": ["발음 유사"]
        }
        """
        let legacyData = try #require(legacyJSON.data(using: .utf8))
        let legacy = try JSONDecoder().decode(LocalGlossarySuggestionScore.self, from: legacyData)

        #expect(legacy.impactLabel.qualityTier == "low")
        #expect(legacy.impactLabel.summarySearchImpact == 0)
        #expect(legacy.impactLabel.summarySearchReasons == ["strict-filter"])
    }
}
