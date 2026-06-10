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

public struct LocalGlossarySuggestionEngineDiagnostics: Codable, Equatable, Sendable {
    public var documentCount: Int
    public var sectionCount: Int
    public var latinSuggestionCount: Int
    public var koreanSuggestionCount: Int
    public var mergedSuggestionCount: Int
    public var latinMilliseconds: Int
    public var koreanMilliseconds: Int
    public var mergeMilliseconds: Int
    public var totalMilliseconds: Int
    public var korean: LocalGlossaryKoreanSuggestionDiagnostics
    public var rejectionSummary: [String: Int]

    public init(
        documentCount: Int = 0,
        sectionCount: Int = 0,
        latinSuggestionCount: Int = 0,
        koreanSuggestionCount: Int = 0,
        mergedSuggestionCount: Int = 0,
        latinMilliseconds: Int = 0,
        koreanMilliseconds: Int = 0,
        mergeMilliseconds: Int = 0,
        totalMilliseconds: Int = 0,
        korean: LocalGlossaryKoreanSuggestionDiagnostics = .init(),
        rejectionSummary: [String: Int] = [:]
    ) {
        self.documentCount = max(0, documentCount)
        self.sectionCount = max(0, sectionCount)
        self.latinSuggestionCount = max(0, latinSuggestionCount)
        self.koreanSuggestionCount = max(0, koreanSuggestionCount)
        self.mergedSuggestionCount = max(0, mergedSuggestionCount)
        self.latinMilliseconds = max(0, latinMilliseconds)
        self.koreanMilliseconds = max(0, koreanMilliseconds)
        self.mergeMilliseconds = max(0, mergeMilliseconds)
        self.totalMilliseconds = max(0, totalMilliseconds)
        self.korean = korean
        self.rejectionSummary = rejectionSummary
    }
}

public enum LocalGlossarySuggestionEngine {
    private static let tokenPattern = #"\b[A-Za-z][A-Za-z0-9_-]{2,23}\b"#
    private static let emailPattern = #"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b"#
    private static let minimumClusterSize = 2
    private static let latinSuggestionLaneEnabled = false

    public static func suggestions(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int = 8
    ) -> [LocalGlossarySuggestion] {
        suggestionsWithDiagnostics(
            from: documents,
            existingState: existingState,
            maxSuggestions: maxSuggestions
        ).suggestions
    }

    public static func suggestionsWithDiagnostics(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int = 8,
        includeLatin: Bool = false
    ) -> (suggestions: [LocalGlossarySuggestion], diagnostics: LocalGlossarySuggestionEngineDiagnostics) {
        let totalStartedAt = Date()
        let latin: [LocalGlossarySuggestion]
        let latinMilliseconds: Int
        var rejectionSummary: [String: Int] = [:]
        if includeLatin || latinSuggestionLaneEnabled {
            let latinStartedAt = Date()
            let latinResult = latinSuggestions(from: documents, existingState: existingState, maxSuggestions: maxSuggestions)
            latin = latinResult.suggestions
            rejectionSummary.merge(latinResult.rejectionSummary) { $0 + $1 }
            latinMilliseconds = elapsedMilliseconds(since: latinStartedAt)
        } else {
            latin = []
            rejectionSummary["latin-lane-disabled", default: 0] += 1
            latinMilliseconds = 0
        }
        let koreanStartedAt = Date()
        let koreanResult = LocalGlossaryKoreanSuggestionEngine.suggestionsWithDiagnostics(
            from: documents,
            existingState: existingState,
            maxSuggestions: maxSuggestions
        )
        let koreanMilliseconds = elapsedMilliseconds(since: koreanStartedAt)
        let mergeStartedAt = Date()
        let merged = mergedSuggestions(latin + koreanResult.suggestions, maxSuggestions: maxSuggestions)
        let mergeMilliseconds = elapsedMilliseconds(since: mergeStartedAt)
        return (
            merged,
            LocalGlossarySuggestionEngineDiagnostics(
                documentCount: documents.count,
                sectionCount: documents.reduce(0) { $0 + $1.sections.count },
                latinSuggestionCount: latin.count,
                koreanSuggestionCount: koreanResult.suggestions.count,
                mergedSuggestionCount: merged.count,
                latinMilliseconds: latinMilliseconds,
                koreanMilliseconds: koreanMilliseconds,
                mergeMilliseconds: mergeMilliseconds,
                totalMilliseconds: elapsedMilliseconds(since: totalStartedAt),
                korean: koreanResult.diagnostics,
                rejectionSummary: rejectionSummary
            )
        )
    }

    private static func latinSuggestions(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int
    ) -> (suggestions: [LocalGlossarySuggestion], rejectionSummary: [String: Int]) {
        let acceptedValues = Set(existingState.enabledTerms.flatMap(\.allMatchValues).map(MeetingHistorySearch.compactNormalize))
        let occurrences = collectOccurrences(from: documents, acceptedValues: acceptedValues)
        let clusters = clusterOccurrences(occurrences)
        var rejectionSummary: [String: Int] = [:]

        let suggestions = clusters.compactMap { cluster -> LocalGlossarySuggestion? in
            let aliases = cluster.map(\.token).normalizedSuggestionAliases()
            guard aliases.count >= minimumClusterSize else {
                rejectionSummary["latin-singleton", default: 0] += 1
                return nil
            }
            let id = suggestionID(for: aliases)
            guard !existingState.dismissedSuggestionIDs.contains(id) else {
                rejectionSummary["dismissed", default: 0] += 1
                return nil
            }
            let meetingIDs = Set(cluster.map(\.documentID))
            let occurrenceCount = cluster.count
            if let reason = latinRejectionReason(
                aliases: aliases,
                occurrenceCount: occurrenceCount,
                meetingCount: meetingIDs.count
            ) {
                rejectionSummary[reason, default: 0] += 1
                return nil
            }
            let confidence = confidenceForSuggestion(
                aliasCount: aliases.count,
                occurrenceCount: occurrenceCount,
                meetingCount: meetingIDs.count
            )
            guard confidence >= 0.55 else {
                rejectionSummary["latin-low-score", default: 0] += 1
                return nil
            }
            let score = scoreForLatinSuggestion(
                aliases: aliases,
                occurrenceCount: occurrenceCount,
                meetingCount: meetingIDs.count
            )
            guard score.finalScore >= 0.55 else {
                rejectionSummary["latin-low-final-score", default: 0] += 1
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
                confidence: score.finalScore,
                score: score
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
        return (suggestions, rejectionSummary)
    }

    private static func mergedSuggestions(
        _ suggestions: [LocalGlossarySuggestion],
        maxSuggestions: Int
    ) -> [LocalGlossarySuggestion] {
        var seenIDs = Set<String>()
        return suggestions
            .sorted {
                if $0.confidence == $1.confidence {
                    return $0.occurrenceCount > $1.occurrenceCount
                }
                return $0.confidence > $1.confidence
            }
            .compactMap { suggestion in
                guard seenIDs.insert(suggestion.id).inserted else {
                    return nil
                }
                return suggestion
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
                guard shouldScanLatinSection(section.field) else {
                    return []
                }
                let text = cleanedLatinCandidateText(section.text)
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
        let occurrencesByToken = Dictionary(grouping: occurrences, by: \.token)
        let clusterTokenGroups = clusterTokenGroups(Array(occurrencesByToken.keys))
        return clusterTokenGroups.map { tokens in
            tokens.flatMap { occurrencesByToken[$0] ?? [] }
        }
    }

    private static func clusterTokenGroups(_ tokens: [String]) -> [[String]] {
        guard !tokens.isEmpty else {
            return []
        }
        let sortedTokens = tokens.sorted()
        var parent = Dictionary(uniqueKeysWithValues: sortedTokens.map { ($0, $0) })

        func root(_ value: String) -> String {
            var value = value
            while let next = parent[value], next != value {
                value = next
            }
            return value
        }

        func connect(_ lhs: String, _ rhs: String) {
            let lhsRoot = root(lhs)
            let rhsRoot = root(rhs)
            guard lhsRoot != rhsRoot else {
                return
            }
            parent[rhsRoot] = lhsRoot
        }

        var bucketedTokens: [LatinCandidateBucketKey: [String]] = [:]
        for token in sortedTokens {
            for key in latinBucketKeys(for: token) {
                bucketedTokens[key, default: []].append(token)
            }
        }

        var seenPairs = Set<String>()
        for bucketTokens in bucketedTokens.values where bucketTokens.count >= 2 {
            let values = Array(Set(bucketTokens)).sorted()
            for lhsIndex in values.indices {
                for rhsIndex in values.indices where lhsIndex < rhsIndex {
                    let lhs = values[lhsIndex]
                    let rhs = values[rhsIndex]
                    let pairID = "\(lhs)|\(rhs)"
                    guard seenPairs.insert(pairID).inserted,
                          areLikelyVariants(lhs: lhs, rhs: rhs) else {
                        continue
                    }
                    connect(lhs, rhs)
                }
            }
        }

        var groups: [String: [String]] = [:]
        for token in sortedTokens {
            groups[root(token), default: []].append(token)
        }
        return groups.values
            .map { $0.sorted() }
            .sorted { lhs, rhs in
                (lhs.first ?? "").localizedStandardCompare(rhs.first ?? "") == .orderedAscending
            }
    }

    private static func latinBucketKeys(for token: String) -> [LatinCandidateBucketKey] {
        let key = phoneticKey(token)
        let length = max(1, key.count)
        return (max(1, length - 1)...(length + 1)).map { LatinCandidateBucketKey(length: $0) }
    }

    private static func shouldScanLatinSection(_ field: MeetingHistorySearchField) -> Bool {
        switch field {
        case .rawTranscript, .currentIssue, .confirmedDecision, .decision, .confirmedAction, .action, .topic, .note:
            return true
        case .title, .file, .date, .participant, .room, .glossary:
            return false
        }
    }

    private static func cleanedLatinCandidateText(_ text: String) -> String {
        var value = text.replacingOccurrences(
            of: emailPattern,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\[[0-9:.]+\]"#,
            with: " ",
            options: .regularExpression
        )
        if let colon = value.firstIndex(of: ":"),
           value.distance(from: value.startIndex, to: colon) < 80 {
            value = String(value[value.index(after: colon)...])
        }
        return value
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

    private static func latinRejectionReason(
        aliases: [String],
        occurrenceCount: Int,
        meetingCount: Int
    ) -> String? {
        if aliases.count > 4 {
            return "latin-broad-cluster"
        }
        if aliases.contains(where: { latinHardNoiseTokens.contains(MeetingHistorySearch.compactNormalize($0)) }) {
            return "latin-known-noise"
        }
        if !aliases.contains(where: { latinDomainTermTokens.contains(MeetingHistorySearch.compactNormalize($0)) }),
           aliases.allSatisfy(isLatinNameLikeToken) {
            return "latin-name-like"
        }
        if aliases.count >= 3, aliases.allSatisfy({ $0.count <= 3 }) {
            return "latin-broad-acronym"
        }
        if aliases.count >= 3, occurrenceCount > 80, meetingCount > 10 {
            return "latin-too-generic"
        }
        return nil
    }

    private static func scoreForLatinSuggestion(
        aliases: [String],
        occurrenceCount: Int,
        meetingCount: Int
    ) -> LocalGlossarySuggestionScore {
        let pairs = aliasPairs(aliases)
        let phoneticSimilarity = pairs
            .map { pair in
                let lhs = phoneticKey(pair.0)
                let rhs = phoneticKey(pair.1)
                return normalizedEditSimilarity(lhs, rhs)
            }
            .max() ?? 0
        let graphemicSimilarity = pairs
            .map { normalizedEditSimilarity($0.0, $0.1) }
            .max() ?? 0
        let recurrence = recurrenceScore(occurrenceCount: occurrenceCount, meetingCount: meetingCount)
        let termhood = min(1, 0.35 + Double(aliases.filter { $0.count >= 4 }.count) * 0.16 + recurrence * 0.25)
        let noisePenalty: Double = latinRejectionReason(
            aliases: aliases,
            occurrenceCount: occurrenceCount,
            meetingCount: meetingCount
        ) == nil ? 0 : 1
        let weightedScore = 0.30 * phoneticSimilarity
            + 0.20 * graphemicSimilarity
            + 0.25 * termhood
            + 0.25 * recurrence
            - 0.40 * noisePenalty
        let finalScore = min(0.95, max(0, weightedScore))
        let impactLabel = LocalGlossaryCandidateImpactLabel.estimated(
            aliases: aliases,
            phoneticSimilarity: phoneticSimilarity,
            graphemicSimilarity: graphemicSimilarity,
            contextOverlap: 0,
            termhood: termhood,
            recurrence: recurrence,
            noisePenalty: noisePenalty,
            finalScore: finalScore
        )
        return LocalGlossarySuggestionScore(
            phoneticSimilarity: phoneticSimilarity,
            graphemicSimilarity: graphemicSimilarity,
            contextOverlap: 0,
            termhood: termhood,
            recurrence: recurrence,
            noisePenalty: noisePenalty,
            finalScore: finalScore,
            matchedCriteria: matchedCriteria(
                phoneticSimilarity: phoneticSimilarity,
                graphemicSimilarity: graphemicSimilarity,
                contextOverlap: 0,
                termhood: termhood,
                recurrence: recurrence
            ),
            impactLabel: impactLabel
        )
    }

    private static func isLatinNameLikeToken(_ token: String) -> Bool {
        let normalized = MeetingHistorySearch.compactNormalize(token)
        guard normalized.count >= 3, normalized.count <= 6 else {
            return false
        }
        return normalized.unicodeScalars.allSatisfy { scalar in
            CharacterSet.lowercaseLetters.contains(scalar)
        }
    }

    private static func suggestionID(for aliases: [String]) -> String {
        "suggestion:\(aliases.map(MeetingHistorySearch.compactNormalize).sorted().joined(separator: "|"))"
    }

    private static func normalizedEditSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let length = max(lhs.count, rhs.count)
        guard length > 0 else {
            return 0
        }
        return 1 - Double(editDistance(lhs, rhs)) / Double(length)
    }

    private static func recurrenceScore(occurrenceCount: Int, meetingCount: Int) -> Double {
        min(1, min(Double(meetingCount) / 8, 1) * 0.70 + min(Double(occurrenceCount) / 16, 1) * 0.30)
    }

    private static func aliasPairs(_ aliases: [String]) -> [(String, String)] {
        guard aliases.count >= 2 else {
            return []
        }
        var pairs: [(String, String)] = []
        for lhsIndex in aliases.indices {
            for rhsIndex in aliases.indices where lhsIndex < rhsIndex {
                pairs.append((aliases[lhsIndex], aliases[rhsIndex]))
            }
        }
        return pairs
    }

    private static func matchedCriteria(
        phoneticSimilarity: Double,
        graphemicSimilarity: Double,
        contextOverlap: Double,
        termhood: Double,
        recurrence: Double
    ) -> [String] {
        var criteria: [String] = []
        if phoneticSimilarity >= 0.80 {
            criteria.append("발음 유사")
        }
        if graphemicSimilarity >= 0.75 {
            criteria.append("철자 유사")
        }
        if contextOverlap > 0 {
            criteria.append("주변 맥락")
        }
        if termhood >= 0.65 {
            criteria.append("용어성")
        }
        if recurrence >= 0.45 {
            criteria.append("반복 등장")
        }
        return criteria
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

    private static func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }
}

private struct TermOccurrence {
    var token: String
    var documentID: String
    var documentTitle: String
    var timestamp: String?
    var excerpt: String
}

private struct LatinCandidateBucketKey: Hashable {
    var length: Int
}

private let commonTokens: Set<String> = [
    "about", "action", "after", "again", "agenda", "alex", "also", "and", "are", "back", "because",
    "before", "blair", "calendar", "can", "check", "context", "decision", "for", "from", "have",
    "meeting", "next", "not", "now", "owner", "plan", "review", "summary", "sync",
    "task", "team", "test", "that", "the", "then", "this", "today", "with", "work", "workflow"
]

private let latinHardNoiseTokens: Set<String> = [
    "aiden", "ayaan", "api", "billy", "ceo", "choi", "com", "eden", "ella", "elva", "erin",
    "ethan", "flynn", "goo", "hong", "jay", "kim", "lee", "lilly", "lynn", "noah", "noh",
    "pid", "prd", "prin", "pro", "ryan", "sally", "woo", "zena", "zigbang"
]

private let latinDomainTermTokens: Set<String> = [
    "faq", "faqq", "faqu", "jax", "jecks", "utm", "zax"
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
