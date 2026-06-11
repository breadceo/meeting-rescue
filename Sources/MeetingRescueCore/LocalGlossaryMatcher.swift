import Foundation

public enum LocalGlossaryMatcher {
    public struct PreparedState: Sendable {
        fileprivate var terms: [PreparedTerm]

        public init(state: LocalGlossaryState) {
            terms = state.enabledTerms.map(PreparedTerm.init(term:))
        }

        public var isEmpty: Bool {
            terms.isEmpty
        }
    }

    fileprivate struct PreparedTerm: Sendable {
        var id: String
        var canonical: String
        var category: LocalGlossaryCategory
        var values: [PreparedValue]

        init(term: LocalGlossaryTerm) {
            id = term.id
            canonical = term.canonical
            category = term.category
            values = term.allMatchValues.map(PreparedValue.init(original:))
        }
    }

    fileprivate struct PreparedValue: Sendable {
        var original: String
        var normalized: String
        var compact: String

        init(original: String) {
            self.original = original
            normalized = MeetingHistorySearch.normalize(original)
            compact = MeetingHistorySearch.compactNormalize(normalized)
        }
    }

    public static func matches(
        in text: String,
        state: LocalGlossaryState,
        maxMatches: Int = 8
    ) -> [LocalGlossaryMatch] {
        matches(
            in: text,
            preparedState: PreparedState(state: state),
            maxMatches: maxMatches
        )
    }

    public static func matches(
        in text: String,
        preparedState: PreparedState,
        maxMatches: Int = 8,
        includeEvidence: Bool = true
    ) -> [LocalGlossaryMatch] {
        let normalizedText = MeetingHistorySearch.normalize(text)
        guard !normalizedText.isEmpty, !preparedState.isEmpty else {
            return []
        }

        var compactText: String?
        return preparedState.terms.compactMap { term -> LocalGlossaryMatch? in
            let matchedValues = term.values.compactMap { value in
                containsGlossaryValue(value, in: normalizedText, compactText: &compactText) ? value.original : nil
            }
            guard !matchedValues.isEmpty else {
                return nil
            }
            return LocalGlossaryMatch(
                termID: term.id,
                canonical: term.canonical,
                category: term.category,
                matchedAliases: matchedValues,
                evidenceExcerpts: includeEvidence ? evidenceExcerpts(for: matchedValues, in: text) : [],
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

    public static func matches(
        in sections: [MeetingHistorySearchSection],
        preparedState: PreparedState,
        maxMatches: Int = 8,
        includeEvidence: Bool = false
    ) -> [LocalGlossaryMatch] {
        guard !sections.isEmpty, !preparedState.isEmpty else {
            return []
        }

        return preparedState.terms.compactMap { term -> LocalGlossaryMatch? in
            let matchedValues = term.values.compactMap { value in
                containsGlossaryValue(value, in: sections) ? value.original : nil
            }
            guard !matchedValues.isEmpty else {
                return nil
            }
            return LocalGlossaryMatch(
                termID: term.id,
                canonical: term.canonical,
                category: term.category,
                matchedAliases: matchedValues,
                evidenceExcerpts: [],
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

    private static func containsGlossaryValue(
        _ value: PreparedValue,
        in normalizedText: String,
        compactText: inout String?
    ) -> Bool {
        let normalizedValue = value.normalized
        guard normalizedValue.count >= 2 else {
            return false
        }
        if normalizedText.contains(normalizedValue) {
            return true
        }
        let compactText = compactText ?? {
            let nextValue = MeetingHistorySearch.compactNormalize(normalizedText)
            compactText = nextValue
            return nextValue
        }()
        let compactValue = value.compact
        return compactValue.count >= 3 && compactText.contains(compactValue)
    }

    private static func containsGlossaryValue(
        _ value: PreparedValue,
        in sections: [MeetingHistorySearchSection]
    ) -> Bool {
        let normalizedValue = value.normalized
        guard normalizedValue.count >= 2 else {
            return false
        }
        let compactValue = value.compact
        let isSingleToken = !normalizedValue.contains(where: { $0.isWhitespace })
        for section in sections {
            if isSingleToken, section.searchTokens.contains(normalizedValue) {
                return true
            }
            if section.normalizedText.contains(normalizedValue) {
                return true
            }
            if compactValue.count >= 3, section.compactNormalizedText.contains(compactValue) {
                return true
            }
        }
        return false
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
