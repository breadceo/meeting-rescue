import Foundation

public enum LocalGlossaryMatcher {
    public static func matches(
        in text: String,
        state: LocalGlossaryState,
        maxMatches: Int = 8
    ) -> [LocalGlossaryMatch] {
        let normalizedText = MeetingHistorySearch.normalize(text)
        guard !normalizedText.isEmpty else {
            return []
        }

        return state.enabledTerms.compactMap { term -> LocalGlossaryMatch? in
            let matchedValues = term.allMatchValues.filter { value in
                containsGlossaryValue(value, in: normalizedText)
            }
            guard !matchedValues.isEmpty else {
                return nil
            }
            return LocalGlossaryMatch(
                termID: term.id,
                canonical: term.canonical,
                category: term.category,
                matchedAliases: matchedValues,
                evidenceExcerpts: evidenceExcerpts(for: matchedValues, in: text),
                confidence: matchedValues.contains(term.canonical) ? 0.95 : 0.85
            )
        }
        .sorted {
            if $0.confidence == $1.confidence {
                return $0.canonical.localizedStandardCompare($1.canonical) == .orderedAscending
            }
            return $0.confidence > $1.confidence
        }
        .prefix(maxMatches)
        .map { $0 }
    }

    public static func supplementalSources(
        for text: String,
        state: LocalGlossaryState,
        maxMatches: Int = 8
    ) -> [SupplementalContextSource] {
        matches(in: text, state: state, maxMatches: maxMatches).map { match in
            SupplementalContextSource(
                id: "glossary:\(match.termID)",
                kind: .domainGlossary,
                title: "용어 힌트: \(match.canonical)",
                sourceName: "Local Glossary",
                excerpt: excerpt(for: match),
                priority: .domainGlossary,
                confidence: match.confidence
            )
        }
    }

    public static func canonicalizedSearchText(
        for text: String,
        state: LocalGlossaryState
    ) -> String {
        let matches = matches(in: text, state: state)
        guard !matches.isEmpty else {
            return text
        }
        let termsByID = Dictionary(uniqueKeysWithValues: state.enabledTerms.map { ($0.id, $0) })
        let additions = matches.flatMap { match -> [String] in
            termsByID[match.termID]?.allMatchValues ?? ([match.canonical] + match.matchedAliases)
        }
        return ([text] + additions).joined(separator: " ")
    }

    private static func containsGlossaryValue(_ value: String, in normalizedText: String) -> Bool {
        let normalizedValue = MeetingHistorySearch.normalize(value)
        guard normalizedValue.count >= 2 else {
            return false
        }
        if normalizedText.contains(normalizedValue) {
            return true
        }
        let compactText = MeetingHistorySearch.compactNormalize(normalizedText)
        let compactValue = MeetingHistorySearch.compactNormalize(normalizedValue)
        return compactValue.count >= 3 && compactText.contains(compactValue)
    }

    private static func evidenceExcerpts(for aliases: [String], in text: String) -> [String] {
        aliases.compactMap { alias in
            guard let range = text.range(
                of: alias,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) else {
                return nil
            }
            let distanceToStart = text.distance(from: text.startIndex, to: range.lowerBound)
            let distanceToEnd = text.distance(from: range.upperBound, to: text.endIndex)
            let start = text.index(
                range.lowerBound,
                offsetBy: -min(36, distanceToStart),
                limitedBy: text.startIndex
            ) ?? text.startIndex
            let end = text.index(
                range.upperBound,
                offsetBy: min(72, distanceToEnd),
                limitedBy: text.endIndex
            ) ?? text.endIndex
            return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func excerpt(for match: LocalGlossaryMatch) -> String {
        [
            "canonical: \(match.canonical)",
            "category: \(match.category.rawValue)",
            "matched aliases: \(match.matchedAliases.joined(separator: ", "))",
            "rule: low-priority interpretation hint; raw transcript를 수정하지 말고, transcript context가 맞을 때만 canonical term으로 해석하세요.",
            match.evidenceExcerpts.isEmpty ? nil : "evidence excerpts: \(match.evidenceExcerpts.joined(separator: " / "))"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
