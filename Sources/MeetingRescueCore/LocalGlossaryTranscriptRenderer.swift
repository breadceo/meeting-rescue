import Foundation

public struct LocalGlossaryRenderedTranscript: Equatable, Sendable {
    public var text: String
    public var replacements: [LocalGlossaryTranscriptReplacement]

    public var replacementCount: Int {
        replacements.reduce(0) { $0 + $1.count }
    }

    public init(text: String, replacements: [LocalGlossaryTranscriptReplacement]) {
        self.text = text
        self.replacements = replacements
    }
}

public struct LocalGlossaryTranscriptReplacement: Equatable, Sendable {
    public var termID: String
    public var canonical: String
    public var alias: String
    public var count: Int

    public init(termID: String, canonical: String, alias: String, count: Int) {
        self.termID = termID
        self.canonical = canonical
        self.alias = alias
        self.count = count
    }
}

public enum LocalGlossaryTranscriptRenderer {
    public static func render(
        _ rawTranscript: String,
        state: LocalGlossaryState
    ) -> LocalGlossaryRenderedTranscript {
        guard !rawTranscript.isEmpty, !state.enabledTerms.isEmpty else {
            return LocalGlossaryRenderedTranscript(text: rawTranscript, replacements: [])
        }

        let aliases = replacementAliases(from: state.enabledTerms)
        let occurrences = selectedOccurrences(in: rawTranscript, aliases: aliases)
        guard !occurrences.isEmpty else {
            return LocalGlossaryRenderedTranscript(text: rawTranscript, replacements: [])
        }

        var renderedText = ""
        var cursor = rawTranscript.startIndex
        var replacementsByKey: [String: LocalGlossaryTranscriptReplacement] = [:]

        for occurrence in occurrences {
            renderedText += String(rawTranscript[cursor..<occurrence.range.lowerBound])
            renderedText += occurrence.alias.canonical
            cursor = occurrence.range.upperBound

            let key = "\(occurrence.alias.termID)|\(occurrence.alias.alias)"
            var replacement = replacementsByKey[key] ?? LocalGlossaryTranscriptReplacement(
                termID: occurrence.alias.termID,
                canonical: occurrence.alias.canonical,
                alias: occurrence.alias.alias,
                count: 0
            )
            replacement.count += 1
            replacementsByKey[key] = replacement
        }
        renderedText += String(rawTranscript[cursor..<rawTranscript.endIndex])

        let replacements = replacementsByKey.values.sorted {
            if $0.canonical == $1.canonical {
                return $0.alias.localizedStandardCompare($1.alias) == .orderedAscending
            }
            return $0.canonical.localizedStandardCompare($1.canonical) == .orderedAscending
        }
        return LocalGlossaryRenderedTranscript(text: renderedText, replacements: replacements)
    }

    private static func selectedOccurrences(
        in text: String,
        aliases: [ReplacementAlias]
    ) -> [ReplacementOccurrence] {
        var candidates: [ReplacementOccurrence] = []
        for alias in aliases {
            candidates.append(contentsOf: occurrences(of: alias, in: text))
        }

        var selected: [ReplacementOccurrence] = []
        for candidate in candidates.sorted(by: occurrenceSort) {
            guard !selected.contains(where: { rangesOverlap($0.range, candidate.range) }) else {
                continue
            }
            selected.append(candidate)
        }
        return selected.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func occurrences(
        of alias: ReplacementAlias,
        in text: String
    ) -> [ReplacementOccurrence] {
        var occurrences: [ReplacementOccurrence] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: alias.alias,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: searchStart..<text.endIndex
              ) {
            occurrences.append(ReplacementOccurrence(range: range, alias: alias))
            searchStart = range.upperBound
        }
        return occurrences
    }

    private static func occurrenceSort(_ lhs: ReplacementOccurrence, _ rhs: ReplacementOccurrence) -> Bool {
        if lhs.range.lowerBound == rhs.range.lowerBound {
            return lhs.alias.alias.count > rhs.alias.alias.count
        }
        return lhs.range.lowerBound < rhs.range.lowerBound
    }

    private static func rangesOverlap(_ lhs: Range<String.Index>, _ rhs: Range<String.Index>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private static func replacementAliases(from terms: [LocalGlossaryTerm]) -> [ReplacementAlias] {
        terms.flatMap { term in
            term.aliases
                .filter { alias in
                    let compactAlias = MeetingHistorySearch.compactNormalize(alias)
                    let compactCanonical = MeetingHistorySearch.compactNormalize(term.canonical)
                    return !compactAlias.isEmpty && compactAlias != compactCanonical
                }
                .map { alias in
                    ReplacementAlias(termID: term.id, canonical: term.canonical, alias: alias)
                }
        }
        .sorted {
            if $0.alias.count == $1.alias.count {
                return $0.alias.localizedStandardCompare($1.alias) == .orderedAscending
            }
            return $0.alias.count > $1.alias.count
        }
    }

    private struct ReplacementAlias {
        var termID: String
        var canonical: String
        var alias: String
    }

    private struct ReplacementOccurrence {
        var range: Range<String.Index>
        var alias: ReplacementAlias
    }
}
