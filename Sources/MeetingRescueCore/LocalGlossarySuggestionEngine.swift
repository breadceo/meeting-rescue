import Foundation

public struct LocalGlossarySourceDocument: Equatable, Sendable {
    public var id: String
    public var title: String
    public var sections: [MeetingHistorySearchSection]

    public init(id: String, title: String, sections: [MeetingHistorySearchSection]) {
        self.id = id
        self.title = title
        self.sections = sections
    }
}

public enum LocalGlossarySuggestionEngine {
    private static let tokenPattern = #"\b[A-Za-z][A-Za-z0-9_-]{2,23}\b"#
    private static let minimumClusterSize = 2

    public static func suggestions(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int = 8
    ) -> [LocalGlossarySuggestion] {
        let acceptedValues = Set(existingState.enabledTerms.flatMap(\.allMatchValues).map(MeetingHistorySearch.compactNormalize))
        let occurrences = collectOccurrences(from: documents, acceptedValues: acceptedValues)
        let clusters = clusterOccurrences(occurrences)

        return clusters.compactMap { cluster -> LocalGlossarySuggestion? in
            let aliases = cluster.map(\.token).normalizedSuggestionAliases()
            guard aliases.count >= minimumClusterSize else {
                return nil
            }
            let id = suggestionID(for: aliases)
            guard !existingState.dismissedSuggestionIDs.contains(id) else {
                return nil
            }
            let meetingIDs = Set(cluster.map(\.documentID))
            let occurrenceCount = cluster.count
            let confidence = confidenceForSuggestion(
                aliasCount: aliases.count,
                occurrenceCount: occurrenceCount,
                meetingCount: meetingIDs.count
            )
            guard confidence >= 0.55 else {
                return nil
            }
            let evidence = cluster.prefix(5).map {
                LocalGlossaryEvidence(
                    sourceID: $0.documentID,
                    sourceTitle: $0.documentTitle,
                    excerpt: $0.excerpt,
                    timestamp: $0.timestamp
                )
            }
            return LocalGlossarySuggestion(
                id: id,
                suggestedCanonical: aliases.sortedByUsefulCanonical.first ?? aliases[0],
                aliases: aliases,
                evidence: evidence,
                occurrenceCount: occurrenceCount,
                meetingCount: meetingIDs.count,
                confidence: confidence
            )
        }
        .sorted {
            if $0.confidence == $1.confidence {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.confidence > $1.confidence
        }
        .prefix(maxSuggestions)
        .map { $0 }
    }

    private static func collectOccurrences(
        from documents: [LocalGlossarySourceDocument],
        acceptedValues: Set<String>
    ) -> [TermOccurrence] {
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else {
            return []
        }
        return documents.flatMap { document in
            document.sections.flatMap { section -> [TermOccurrence] in
                let text = section.text
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                return regex.matches(in: text, range: range).compactMap { match in
                    guard let matchRange = Range(match.range, in: text) else {
                        return nil
                    }
                    let token = String(text[matchRange])
                    let normalized = MeetingHistorySearch.compactNormalize(token)
                    guard isCandidateToken(normalized),
                          !acceptedValues.contains(normalized) else {
                        return nil
                    }
                    return TermOccurrence(
                        token: token.lowercased(),
                        documentID: document.id,
                        documentTitle: document.title,
                        timestamp: section.timestamp,
                        excerpt: section.text
                    )
                }
            }
        }
    }

    private static func clusterOccurrences(_ occurrences: [TermOccurrence]) -> [[TermOccurrence]] {
        var clusters: [[TermOccurrence]] = []
        for occurrence in occurrences {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.contains { areLikelyVariants(lhs: $0.token, rhs: occurrence.token) }
            }) {
                clusters[index].append(occurrence)
            } else {
                clusters.append([occurrence])
            }
        }
        return clusters
    }

    private static func areLikelyVariants(lhs: String, rhs: String) -> Bool {
        let lhsKey = phoneticKey(lhs)
        let rhsKey = phoneticKey(rhs)
        if lhsKey == rhsKey {
            return true
        }
        return editDistance(lhsKey, rhsKey) <= 1 || bigramSimilarity(lhsKey, rhsKey) >= 0.50
    }

    private static func phoneticKey(_ value: String) -> String {
        MeetingHistorySearch.compactNormalize(value)
            .replacingOccurrences(of: "cks", with: "x")
            .replacingOccurrences(of: "ks", with: "x")
            .replacingOccurrences(of: "ck", with: "k")
            .replacingOccurrences(of: "zz", with: "z")
            .replacingOccurrences(of: "je", with: "ja")
    }

    private static func isCandidateToken(_ token: String) -> Bool {
        guard token.count >= 3, token.count <= 24 else {
            return false
        }
        return !commonTokens.contains(token)
    }

    private static func confidenceForSuggestion(aliasCount: Int, occurrenceCount: Int, meetingCount: Int) -> Double {
        let aliasScore = min(0.35, Double(aliasCount - 1) * 0.18)
        let occurrenceScore = min(0.30, Double(occurrenceCount) * 0.08)
        let meetingScore = min(0.25, Double(meetingCount) * 0.10)
        return min(0.95, 0.20 + aliasScore + occurrenceScore + meetingScore)
    }

    private static func suggestionID(for aliases: [String]) -> String {
        "suggestion:\(aliases.map(MeetingHistorySearch.compactNormalize).sorted().joined(separator: "|"))"
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            var current = [lhsIndex + 1]
            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                let substitution = previous[rhsIndex] + (lhsCharacter == rhsCharacter ? 0 : 1)
                let insertion = current[rhsIndex] + 1
                let deletion = previous[rhsIndex + 1] + 1
                current.append(min(substitution, insertion, deletion))
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private static func bigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsGrams = Set(bigrams(lhs))
        let rhsGrams = Set(bigrams(rhs))
        guard !lhsGrams.isEmpty, !rhsGrams.isEmpty else {
            return 0
        }
        return Double(lhsGrams.intersection(rhsGrams).count * 2) / Double(lhsGrams.count + rhsGrams.count)
    }

    private static func bigrams(_ value: String) -> [String] {
        let chars = Array(value)
        guard chars.count >= 2 else {
            return value.isEmpty ? [] : [value]
        }
        return (0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) }
    }
}

private struct TermOccurrence {
    var token: String
    var documentID: String
    var documentTitle: String
    var timestamp: String?
    var excerpt: String
}

private let commonTokens: Set<String> = [
    "about", "action", "after", "again", "agenda", "alex", "also", "and", "are", "back", "because",
    "before", "blair", "calendar", "can", "check", "context", "decision", "for", "from", "have",
    "meeting", "next", "not", "now", "owner", "plan", "review", "summary", "sync",
    "task", "team", "test", "that", "the", "then", "this", "today", "with", "work", "workflow"
]

private extension Array where Element == String {
    func normalizedSuggestionAliases() -> [String] {
        Array(Set(map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var sortedByUsefulCanonical: [String] {
        sorted {
            if $0.count == $1.count {
                return $0.localizedStandardCompare($1) == .orderedAscending
            }
            return $0.count < $1.count
        }
    }
}
