import Foundation
import Testing
@testable import MeetingRescueCore

struct LocalGlossaryMatcherTests {
    @Test("matcher returns accepted glossary hints without rewriting transcript")
    func matcherReturnsHintsWithoutRewritingTranscript() {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(
                id: "term-zax",
                canonical: "zax",
                aliases: ["jax", "jecks", "zacks"],
                category: .project,
                source: .manual
            )
        ])
        let transcript = "[03:12] Alex: jax 쪽 workflow와 jecks 요약 품질을 봅시다."

        let matches = LocalGlossaryMatcher.matches(in: transcript, state: state)

        #expect(matches.count == 1)
        #expect(matches[0].canonical == "zax")
        #expect(matches[0].matchedAliases == ["jax", "jecks"])
        #expect(transcript.contains("jax"))
        #expect(!transcript.contains("zax 쪽 workflow"))
    }

    @Test("matcher builds domain glossary supplemental sources")
    func matcherBuildsSupplementalSources() throws {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax"], category: .project)
        ])

        let sources = LocalGlossaryMatcher.supplementalSources(
            for: "[03:12] Alex: jax 쪽으로 정리합시다.",
            state: state
        )

        let source = try #require(sources.first)
        #expect(source.id == "glossary:term-zax")
        #expect(source.kind == .domainGlossary)
        #expect(source.priority == .domainGlossary)
        #expect(source.title == "용어 힌트: zax")
        #expect(source.excerpt.contains("canonical: zax"))
        #expect(source.excerpt.contains("matched aliases: jax"))
        #expect(source.excerpt.contains("low-priority interpretation hint"))
    }

    @Test("canonicalized search text adds canonical and aliases for matched terms")
    func canonicalizedSearchTextAddsCanonicalAndAliases() {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(id: "term-zax", canonical: "zax", aliases: ["jax", "jecks"], category: .project)
        ])

        let value = LocalGlossaryMatcher.canonicalizedSearchText(
            for: "회의에서 jax 정리를 논의했다",
            state: state
        )

        #expect(value.contains("회의에서 jax 정리를 논의했다"))
        #expect(value.contains("zax"))
        #expect(value.contains("jecks"))
    }

    @Test("prepared matcher can skip evidence for search index paths")
    func preparedMatcherCanSkipEvidenceForSearchIndexPaths() {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(
                id: "term-zax",
                canonical: "zax",
                aliases: ["jax", "jecks"],
                category: .project
            )
        ])
        let preparedState = LocalGlossaryMatcher.PreparedState(state: state)

        let matches = LocalGlossaryMatcher.matches(
            in: "[03:12] Alex: jax workflow와 jecks 검색을 맞춥니다.",
            preparedState: preparedState,
            includeEvidence: false
        )

        #expect(matches.count == 1)
        #expect(matches[0].canonical == "zax")
        #expect(matches[0].matchedAliases == ["jax", "jecks"])
        #expect(matches[0].evidenceExcerpts.isEmpty)
    }

    @Test("prepared matcher can scan pre-normalized search sections")
    func preparedMatcherCanScanPreNormalizedSearchSections() {
        let state = LocalGlossaryState(terms: [
            LocalGlossaryTerm(
                id: "term-zax",
                canonical: "zax",
                aliases: ["jax", "제이엑스"],
                category: .project
            )
        ])
        let preparedState = LocalGlossaryMatcher.PreparedState(state: state)
        let sections = [
            MeetingHistorySearchSection(
                field: .rawTranscript,
                text: "[03:12] Alex: 제이 엑스 workflow를 검색합니다.",
                weight: 24
            )
        ]

        let matches = LocalGlossaryMatcher.matches(
            in: sections,
            preparedState: preparedState
        )

        #expect(matches.count == 1)
        #expect(matches[0].canonical == "zax")
        #expect(matches[0].matchedAliases == ["제이엑스"])
        #expect(matches[0].evidenceExcerpts.isEmpty)
    }
}
