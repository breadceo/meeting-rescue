import Foundation

public struct LocalGlossaryKoreanSuggestionDiagnostics: Codable, Equatable, Sendable {
    public var occurrenceCount: Int
    public var candidateCount: Int
    public var supportedCandidateCount: Int
    public var comparisonCandidateCount: Int
    public var pairCount: Int
    public var clusterCount: Int
    public var collectMilliseconds: Int
    public var summarizeMilliseconds: Int
    public var pairMilliseconds: Int
    public var clusterMilliseconds: Int
    public var buildMilliseconds: Int
    public var totalMilliseconds: Int

    public init(
        occurrenceCount: Int = 0,
        candidateCount: Int = 0,
        supportedCandidateCount: Int = 0,
        comparisonCandidateCount: Int = 0,
        pairCount: Int = 0,
        clusterCount: Int = 0,
        collectMilliseconds: Int = 0,
        summarizeMilliseconds: Int = 0,
        pairMilliseconds: Int = 0,
        clusterMilliseconds: Int = 0,
        buildMilliseconds: Int = 0,
        totalMilliseconds: Int = 0
    ) {
        self.occurrenceCount = max(0, occurrenceCount)
        self.candidateCount = max(0, candidateCount)
        self.supportedCandidateCount = max(0, supportedCandidateCount)
        self.comparisonCandidateCount = max(0, comparisonCandidateCount)
        self.pairCount = max(0, pairCount)
        self.clusterCount = max(0, clusterCount)
        self.collectMilliseconds = max(0, collectMilliseconds)
        self.summarizeMilliseconds = max(0, summarizeMilliseconds)
        self.pairMilliseconds = max(0, pairMilliseconds)
        self.clusterMilliseconds = max(0, clusterMilliseconds)
        self.buildMilliseconds = max(0, buildMilliseconds)
        self.totalMilliseconds = max(0, totalMilliseconds)
    }
}

public struct LocalGlossaryKoreanSuggestionResult: Sendable {
    public var suggestions: [LocalGlossarySuggestion]
    public var reviewCandidates: [LocalGlossarySuggestion]
    public var diagnostics: LocalGlossaryKoreanSuggestionDiagnostics

    public init(
        suggestions: [LocalGlossarySuggestion],
        reviewCandidates: [LocalGlossarySuggestion],
        diagnostics: LocalGlossaryKoreanSuggestionDiagnostics
    ) {
        self.suggestions = suggestions
        self.reviewCandidates = reviewCandidates
        self.diagnostics = diagnostics
    }
}

public enum LocalGlossaryKoreanSuggestionEngine {
    private static let maxCandidatesPerBucket = 40
    private static let maxComparisonCandidates = 900
    private static let minimumOccurrenceSupportForPairing = 2

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
        maxSuggestions: Int = 8
    ) -> (suggestions: [LocalGlossarySuggestion], diagnostics: LocalGlossaryKoreanSuggestionDiagnostics) {
        let result = suggestionsAndReviewCandidatesWithDiagnostics(
            from: documents,
            existingState: existingState,
            maxSuggestions: maxSuggestions,
            maxReviewCandidates: 0
        )
        return (result.suggestions, result.diagnostics)
    }

    public static func suggestionsAndReviewCandidatesWithDiagnostics(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int = 8,
        maxReviewCandidates: Int = 50
    ) -> LocalGlossaryKoreanSuggestionResult {
        let totalStartedAt = Date()
        let acceptedValues = Set(existingState.enabledTerms.flatMap(\.allMatchValues).map(MeetingHistorySearch.compactNormalize))
        let collectStartedAt = Date()
        let occurrences = collectOccurrences(from: documents, acceptedValues: acceptedValues)
        let collectMilliseconds = elapsedMilliseconds(since: collectStartedAt)
        let summarizeStartedAt = Date()
        let candidates = summarizeCandidates(occurrences)
        let summarizeMilliseconds = elapsedMilliseconds(since: summarizeStartedAt)
        let supportedCandidateCount = candidates.filter { candidate in
            candidate.documentCount >= minimumOccurrenceSupportForPairing
                || candidate.occurrenceCount >= minimumOccurrenceSupportForPairing
        }
        .count
        let comparisonCandidateCount = min(supportedCandidateCount, maxComparisonCandidates)
        let pairStartedAt = Date()
        let pairs = candidatePairs(from: candidates)
        let pairMilliseconds = elapsedMilliseconds(since: pairStartedAt)
        let clusterStartedAt = Date()
        let strictClusters = clusters(from: pairs)
        let reviewPairs = maxReviewCandidates > 0 ? reviewCandidatePairs(from: candidates) : []
        let reviewClusters = maxReviewCandidates > 0 ? clusters(from: reviewPairs) : []
        let clusterMilliseconds = elapsedMilliseconds(since: clusterStartedAt)
        let buildStartedAt = Date()
        let suggestions = strictClusters.compactMap { cluster in
            suggestion(
                from: cluster,
                pairs: pairs,
                dismissedIDs: existingState.dismissedSuggestionIDs,
                rejectedIDs: existingState.rejectedSuggestionIDs,
                acceptedValues: acceptedValues,
                lane: .strict
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
        let strictAliasKeys = Set(suggestions.map { aliasKey(for: $0.aliases) })
        let reviewCandidates = reviewClusters.compactMap { cluster in
            suggestion(
                from: cluster,
                pairs: reviewPairs,
                dismissedIDs: existingState.dismissedSuggestionIDs,
                rejectedIDs: existingState.rejectedSuggestionIDs,
                acceptedValues: acceptedValues,
                lane: .review
            )
        }
        .filter { !strictAliasKeys.contains(aliasKey(for: $0.aliases)) }
        .sorted {
            if $0.confidence == $1.confidence {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.confidence > $1.confidence
        }
        .prefix(maxReviewCandidates)
        .map { $0 }
        let buildMilliseconds = elapsedMilliseconds(since: buildStartedAt)
        return LocalGlossaryKoreanSuggestionResult(
            suggestions: suggestions,
            reviewCandidates: reviewCandidates,
            diagnostics: LocalGlossaryKoreanSuggestionDiagnostics(
                occurrenceCount: occurrences.count,
                candidateCount: candidates.count,
                supportedCandidateCount: supportedCandidateCount,
                comparisonCandidateCount: comparisonCandidateCount,
                pairCount: pairs.count,
                clusterCount: strictClusters.count,
                collectMilliseconds: collectMilliseconds,
                summarizeMilliseconds: summarizeMilliseconds,
                pairMilliseconds: pairMilliseconds,
                clusterMilliseconds: clusterMilliseconds,
                buildMilliseconds: buildMilliseconds,
                totalMilliseconds: elapsedMilliseconds(since: totalStartedAt)
            )
        )
    }

    private static func collectOccurrences(
        from documents: [LocalGlossarySourceDocument],
        acceptedValues: Set<String>
    ) -> [KoreanPhraseOccurrence] {
        documents.flatMap { document in
            document.sections.flatMap { section -> [KoreanPhraseOccurrence] in
                let tokens = koreanTokens(in: section.text)
                guard !tokens.isEmpty else {
                    return []
                }
                let contextValues = Set(tokens.map(\.compact))
                return phraseCandidates(from: tokens).compactMap { phrase in
                    guard isCandidate(phrase.compact),
                          !acceptedValues.contains(MeetingHistorySearch.compactNormalize(phrase.compact)) else {
                        return nil
                    }
                    return KoreanPhraseOccurrence(
                        display: phrase.display,
                        compact: phrase.compact,
                        documentID: document.id,
                        documentTitle: document.title,
                        timestamp: section.timestamp,
                        excerpt: section.text,
                        contextValues: contextValues.subtracting([phrase.compact])
                    )
                }
            }
        }
    }

    private static func summarizeCandidates(_ occurrences: [KoreanPhraseOccurrence]) -> [KoreanPhraseCandidate] {
        let grouped = Dictionary(grouping: occurrences, by: \.compact)
        return grouped.compactMap { compact, occurrences -> KoreanPhraseCandidate? in
            guard !occurrences.isEmpty else {
                return nil
            }
            let display = occurrences
                .map(\.display)
                .reduce(into: [:]) { (counts: inout [String: Int], display) in
                    counts[display, default: 0] += 1
                }
                .sorted {
                    if $0.value == $1.value {
                        return $0.key.localizedStandardCompare($1.key) == .orderedAscending
                    }
                    return $0.value > $1.value
                }
                .first?.key ?? compact
            return KoreanPhraseCandidate(display: display, compact: compact, occurrences: occurrences)
        }
    }

    private static func candidatePairs(from candidates: [KoreanPhraseCandidate]) -> [KoreanPhraseCandidatePair] {
        let supportedCandidates = candidates.filter { candidate in
            candidate.documentCount >= minimumOccurrenceSupportForPairing
                || candidate.occurrenceCount >= minimumOccurrenceSupportForPairing
        }
        let comparisonCandidates = supportedCandidates.sorted {
            if $0.priority == $1.priority {
                return $0.compact.localizedStandardCompare($1.compact) == .orderedAscending
            }
            return $0.priority > $1.priority
        }
        .prefix(maxComparisonCandidates)
        .map { $0 }
        let buckets = cappedBuckets(for: comparisonCandidates)
        var pairs: [KoreanPhraseCandidatePair] = []
        var seen: Set<String> = []

        for (bucketKey, group) in buckets {
            let candidatePool = comparisonPool(for: bucketKey, buckets: buckets)
            for lhs in group {
                for rhs in candidatePool where lhs.compact != rhs.compact {
                    let pairID = [lhs.compact, rhs.compact].sorted().joined(separator: "|")
                    guard !seen.contains(pairID) else {
                        continue
                    }
                    seen.insert(pairID)
                    guard abs(lhs.compact.count - rhs.compact.count) <= 2,
                          !isLikelyGenericExtension(lhs.compact, rhs.compact) else {
                        continue
                    }
                    let score = koreanScore(lhs.compact, rhs.compact)
                    guard score.value >= 0.80 else {
                        continue
                    }
                    let contextOverlap = overlap(lhs.contextValues, rhs.contextValues)
                    if acceptsPair(lhs: lhs, rhs: rhs, score: score.value, contextOverlap: contextOverlap) {
                        pairs.append(
                            KoreanPhraseCandidatePair(
                                lhs: lhs,
                                rhs: rhs,
                                score: score.value,
                                contextOverlap: contextOverlap,
                                scoreBreakdown: score
                            )
                        )
                    }
                }
            }
        }

        return pairs.sorted {
            if $0.score == $1.score {
                return $0.contextOverlap > $1.contextOverlap
            }
            return $0.score > $1.score
        }
    }

    private static func reviewCandidatePairs(from candidates: [KoreanPhraseCandidate]) -> [KoreanPhraseCandidatePair] {
        let comparisonCandidates = candidates.sorted {
            if $0.priority == $1.priority {
                return $0.compact.localizedStandardCompare($1.compact) == .orderedAscending
            }
            return $0.priority > $1.priority
        }
        .prefix(maxComparisonCandidates)
        .map { $0 }
        let buckets = cappedBuckets(for: comparisonCandidates)
        var pairs: [KoreanPhraseCandidatePair] = []
        var seen: Set<String> = []

        for (bucketKey, group) in buckets {
            let candidatePool = comparisonPool(for: bucketKey, buckets: buckets)
            for lhs in group {
                for rhs in candidatePool where lhs.compact != rhs.compact {
                    let pairID = [lhs.compact, rhs.compact].sorted().joined(separator: "|")
                    guard !seen.contains(pairID) else {
                        continue
                    }
                    seen.insert(pairID)
                    guard abs(lhs.compact.count - rhs.compact.count) <= 2,
                          !isLikelyGenericExtension(lhs.compact, rhs.compact) else {
                        continue
                    }
                    let score = koreanScore(lhs.compact, rhs.compact)
                    guard score.value >= 0.72 else {
                        continue
                    }
                    let contextOverlap = overlap(lhs.contextValues, rhs.contextValues)
                    if acceptsReviewPair(lhs: lhs, rhs: rhs, score: score.value, contextOverlap: contextOverlap) {
                        pairs.append(
                            KoreanPhraseCandidatePair(
                                lhs: lhs,
                                rhs: rhs,
                                score: score.value,
                                contextOverlap: contextOverlap,
                                scoreBreakdown: score
                            )
                        )
                    }
                }
            }
        }

        return pairs.sorted {
            if $0.score == $1.score {
                return $0.contextOverlap > $1.contextOverlap
            }
            return $0.score > $1.score
        }
    }

    private static func acceptsReviewPair(
        lhs: KoreanPhraseCandidate,
        rhs: KoreanPhraseCandidate,
        score: Double,
        contextOverlap: Double
    ) -> Bool {
        let combinedDocumentSupport = lhs.documentCount + rhs.documentCount
        let recurringSupport = lhs.documentCount >= 2 || rhs.documentCount >= 2
            || lhs.occurrenceCount >= 3 || rhs.occurrenceCount >= 3
        return score >= 0.72
            && contextOverlap >= 0.05
            && combinedDocumentSupport >= 3
            && recurringSupport
    }

    private static func acceptsPair(
        lhs: KoreanPhraseCandidate,
        rhs: KoreanPhraseCandidate,
        score: Double,
        contextOverlap: Double
    ) -> Bool {
        if score >= 0.85, lhs.documentCount >= 2, rhs.documentCount >= 2 {
            return true
        }

        let combinedDocumentSupport = lhs.documentCount + rhs.documentCount
        let hasRecurringSide = lhs.documentCount >= 3 || rhs.documentCount >= 3
            || lhs.occurrenceCount >= 4 || rhs.occurrenceCount >= 4
        return score >= 0.80
            && contextOverlap >= 0.12
            && combinedDocumentSupport >= 5
            && hasRecurringSide
    }

    private static func clusters(from pairs: [KoreanPhraseCandidatePair]) -> [[KoreanPhraseCandidate]] {
        var parent: [String: String] = [:]
        var candidatesByCompact: [String: KoreanPhraseCandidate] = [:]

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

        for pair in pairs {
            candidatesByCompact[pair.lhs.compact] = pair.lhs
            candidatesByCompact[pair.rhs.compact] = pair.rhs
            parent[pair.lhs.compact, default: pair.lhs.compact] = parent[pair.lhs.compact] ?? pair.lhs.compact
            parent[pair.rhs.compact, default: pair.rhs.compact] = parent[pair.rhs.compact] ?? pair.rhs.compact
            connect(pair.lhs.compact, pair.rhs.compact)
        }

        var clustersByRoot: [String: [KoreanPhraseCandidate]] = [:]
        for candidate in candidatesByCompact.values {
            clustersByRoot[root(candidate.compact), default: []].append(candidate)
        }
        return clustersByRoot.values.filter { $0.count >= 2 }
    }

    private static func suggestion(
        from cluster: [KoreanPhraseCandidate],
        pairs: [KoreanPhraseCandidatePair],
        dismissedIDs: Set<String>,
        rejectedIDs: Set<String>,
        acceptedValues: Set<String>,
        lane: LocalGlossaryCandidateLane
    ) -> LocalGlossarySuggestion? {
        let aliases = cluster
            .map(\.display)
            .normalizedKoreanSuggestionAliases()
            .filter { !isNonGlossaryKoreanAlias(MeetingHistorySearch.compactNormalize($0)) }
        guard aliases.count >= 2 else {
            return nil
        }
        guard looksLikeGlossaryNounCandidate(aliases: aliases, cluster: cluster) else {
            return nil
        }
        guard aliases
            .map(MeetingHistorySearch.compactNormalize)
            .allSatisfy({ !acceptedValues.contains($0) }) else {
            return nil
        }
        let prefix = lane == .review ? "suggestion:review:ko" : "suggestion:ko"
        let id = "\(prefix):\(cluster.map(\.compact).sorted().joined(separator: "|"))"
        guard !dismissedIDs.contains(id),
              !rejectedIDs.contains(id) else {
            return nil
        }
        let compactValues = Set(cluster.map(\.compact))
        let relevantPairs = pairs.filter {
            compactValues.contains($0.lhs.compact) && compactValues.contains($0.rhs.compact)
        }
        let occurrences = cluster.flatMap(\.occurrences)
        let meetingIDs = Set(occurrences.map(\.documentID))
        let score = scoreForSuggestion(
            aliases: aliases,
            cluster: cluster,
            pairs: relevantPairs,
            occurrenceCount: occurrences.count,
            meetingCount: meetingIDs.count
        )
        let suggestedCanonical = cluster
            .sorted {
                if $0.documentCount == $1.documentCount {
                    if $0.occurrenceCount == $1.occurrenceCount {
                        return $0.compact.count < $1.compact.count
                    }
                    return $0.occurrenceCount > $1.occurrenceCount
                }
                return $0.documentCount > $1.documentCount
            }
            .first?.display ?? aliases[0]
        let evidence = occurrences.prefix(5).map {
            LocalGlossaryEvidence(
                sourceID: $0.documentID,
                sourceTitle: $0.documentTitle,
                excerpt: $0.excerpt,
                timestamp: $0.timestamp
            )
        }
        return LocalGlossarySuggestion(
            id: id,
            suggestedCanonical: suggestedCanonical,
            aliases: aliases,
            evidence: evidence,
            occurrenceCount: occurrences.count,
            meetingCount: meetingIDs.count,
            confidence: lane == .review ? min(score.finalScore, 0.74) : score.finalScore,
            score: score,
            lane: lane,
            reviewReason: lane == .review ? "반복/맥락 근거는 있으나 strict threshold 미만" : ""
        )
    }

    private static func aliasKey(for aliases: [String]) -> String {
        aliases.map(MeetingHistorySearch.compactNormalize).sorted().joined(separator: "|")
    }

    private static func scoreForSuggestion(
        aliases: [String],
        cluster: [KoreanPhraseCandidate],
        pairs: [KoreanPhraseCandidatePair],
        occurrenceCount: Int,
        meetingCount: Int
    ) -> LocalGlossarySuggestionScore {
        let phoneticSimilarity = pairs
            .map { 0.75 * $0.scoreBreakdown.jamo + 0.25 * $0.scoreBreakdown.initials }
            .max() ?? 0
        let graphemicSimilarity = pairs
            .map { 0.65 * $0.scoreBreakdown.syllable + 0.35 * $0.scoreBreakdown.bigram }
            .max() ?? 0
        let contextOverlap = pairs.map(\.contextOverlap).max() ?? 0
        let termhood = termhoodScore(aliases: aliases, cluster: cluster)
        let recurrence = recurrenceScore(occurrenceCount: occurrenceCount, meetingCount: meetingCount)
        let noisePenalty = noisePenaltyForKoreanAliases(aliases)
        let finalScore = min(
            0.95,
            max(
                0,
                0.30 * phoneticSimilarity
                    + 0.15 * graphemicSimilarity
                    + 0.15 * contextOverlap
                    + 0.20 * termhood
                    + 0.20 * recurrence
                    - 0.35 * noisePenalty
            )
        )
        let impactLabel = LocalGlossaryCandidateImpactLabel.estimated(
            aliases: aliases,
            phoneticSimilarity: phoneticSimilarity,
            graphemicSimilarity: graphemicSimilarity,
            contextOverlap: contextOverlap,
            termhood: termhood,
            recurrence: recurrence,
            noisePenalty: noisePenalty,
            finalScore: finalScore
        )
        return LocalGlossarySuggestionScore(
            phoneticSimilarity: phoneticSimilarity,
            graphemicSimilarity: graphemicSimilarity,
            contextOverlap: contextOverlap,
            termhood: termhood,
            recurrence: recurrence,
            noisePenalty: noisePenalty,
            finalScore: finalScore,
            matchedCriteria: matchedCriteria(
                phoneticSimilarity: phoneticSimilarity,
                graphemicSimilarity: graphemicSimilarity,
                contextOverlap: contextOverlap,
                termhood: termhood,
                recurrence: recurrence
            ),
            impactLabel: impactLabel
        )
    }

    private static func termhoodScore(aliases: [String], cluster: [KoreanPhraseCandidate]) -> Double {
        let occurrences = cluster.flatMap(\.occurrences)
        let contextValues = occurrences.reduce(into: Set<String>()) { result, occurrence in
            result.formUnion(occurrence.contextValues)
        }
        var score = 0.40
        if aliases.contains(where: { $0.contains(" ") }) {
            score += 0.14
        }
        if aliases.map({ MeetingHistorySearch.compactNormalize($0).count }).max() ?? 0 >= 5 {
            score += 0.12
        }
        if !contextValues.intersection(koreanDomainContextTokens).isEmpty {
            score += 0.24
        }
        if Set(occurrences.map(\.documentTitle)).count <= max(2, Set(occurrences.map(\.documentID)).count) {
            score += 0.06
        }
        if aliases.contains(where: { isGenericPointerPhrase(MeetingHistorySearch.compactNormalize($0)) }) {
            score -= 0.60
        }
        if aliases.contains(where: { isPredicativeKoreanCandidate(MeetingHistorySearch.compactNormalize($0)) }) {
            score -= 0.35
        }
        return min(1, max(0, score))
    }

    private static func recurrenceScore(occurrenceCount: Int, meetingCount: Int) -> Double {
        min(1, min(Double(meetingCount) / 6, 1) * 0.70 + min(Double(occurrenceCount) / 12, 1) * 0.30)
    }

    private static func noisePenaltyForKoreanAliases(_ aliases: [String]) -> Double {
        if aliases.contains(where: { isGenericPointerPhrase(MeetingHistorySearch.compactNormalize($0)) }) {
            return 1
        }
        if aliases.allSatisfy({ isPredicativeKoreanCandidate(MeetingHistorySearch.compactNormalize($0)) }) {
            return 1
        }
        if aliases.count > 4 {
            return 0.60
        }
        let compactAliases = aliases.map(MeetingHistorySearch.compactNormalize)
        if compactAliases.allSatisfy({ koreanStopWords.contains($0) }) {
            return 1
        }
        return 0
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

    private static func cappedBuckets(
        for candidates: [KoreanPhraseCandidate]
    ) -> [KoreanCandidateBucketKey: [KoreanPhraseCandidate]] {
        let grouped = Dictionary(grouping: candidates, by: KoreanCandidateBucketKey.init(candidate:))
        return grouped.mapValues { values in
            values.sorted {
                if $0.priority == $1.priority {
                    return $0.compact.localizedStandardCompare($1.compact) == .orderedAscending
                }
                return $0.priority > $1.priority
            }
            .prefix(maxCandidatesPerBucket)
            .map { $0 }
        }
    }

    private static func comparisonPool(
        for key: KoreanCandidateBucketKey,
        buckets: [KoreanCandidateBucketKey: [KoreanPhraseCandidate]]
    ) -> [KoreanPhraseCandidate] {
        similarInitials(for: key.initial).flatMap { initial in
            (max(3, key.length - 2)...min(8, key.length + 2)).flatMap { length in
                buckets[KoreanCandidateBucketKey(initial: initial, length: length)] ?? []
            }
        }
    }

    private static func koreanTokens(in text: String) -> [KoreanToken] {
        let cleaned = cleanTranscriptLine(text)
        guard let regex = try? NSRegularExpression(pattern: #"[가-힣]{2,}"#) else {
            return []
        }
        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        return regex.matches(in: cleaned, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: cleaned) else {
                return nil
            }
            let token = stripParticle(String(cleaned[matchRange]))
            let compact = MeetingHistorySearch.compactNormalize(token)
            guard token.count >= 2,
                  compact.count >= 2,
                  !koreanStopWords.contains(compact) else {
                return nil
            }
            return KoreanToken(display: token, compact: compact)
        }
    }

    private static func phraseCandidates(from tokens: [KoreanToken]) -> [KoreanToken] {
        var phrases: [KoreanToken] = []
        for index in tokens.indices {
            phrases.append(tokens[index])
            for length in 2...3 where index + length <= tokens.count {
                let slice = tokens[index..<(index + length)]
                phrases.append(
                    KoreanToken(
                        display: slice.map(\.display).joined(separator: " "),
                        compact: slice.map(\.compact).joined()
                    )
                )
            }
        }
        return phrases
    }

    private static func isCandidate(_ compact: String) -> Bool {
        guard compact.count >= 3, compact.count <= 8 else {
            return false
        }
        guard !koreanStopWords.contains(compact) else {
            return false
        }
        guard !koreanGenericSuffixes.contains(where: { suffix in
            compact.hasSuffix(suffix)
        }) else {
            return false
        }
        guard !isGenericPointerPhrase(compact) else {
            return false
        }
        guard !isGenericConversationalCandidate(compact) else {
            return false
        }
        guard !isPredicativeKoreanCandidate(compact) else {
            return false
        }
        guard !isNonGlossaryKoreanAlias(compact) else {
            return false
        }
        return true
    }

    private static func looksLikeGlossaryNounCandidate(
        aliases: [String],
        cluster: [KoreanPhraseCandidate]
    ) -> Bool {
        let compactAliases = aliases.map(MeetingHistorySearch.compactNormalize)
        guard compactAliases.contains(where: { !isPredicativeKoreanCandidate($0) }) else {
            return false
        }
        if compactAliases.contains(where: hasKoreanGlossaryNounSignal) {
            return true
        }

        let contextValues = cluster.reduce(into: Set<String>()) { result, candidate in
            result.formUnion(candidate.contextValues)
        }
        if !contextValues.intersection(koreanDomainContextTokens).isEmpty {
            return true
        }

        return compactAliases.contains { compact in
            compact.count >= 3
                && !isGenericPointerPhrase(compact)
                && !isGenericConversationalCandidate(compact)
                && !hasWeakConversationalSuffix(compact)
        }
    }

    private static func isGenericPointerPhrase(_ compact: String) -> Bool {
        let hasPointerPrefix = koreanGenericPointerPrefixes.contains { prefix in
            compact.hasPrefix(prefix)
        }
        guard hasPointerPrefix else {
            return false
        }
        return koreanGenericPointerSuffixes.contains { suffix in
            compact.hasSuffix(suffix)
        }
    }

    private static func isGenericConversationalCandidate(_ compact: String) -> Bool {
        koreanGenericConversationalPrefixes.contains { prefix in
            compact.hasPrefix(prefix)
        }
    }

    private static func isNonGlossaryKoreanAlias(_ compact: String) -> Bool {
        isGenericPointerPhrase(compact)
            || isGenericConversationalCandidate(compact)
            || isPredicativeKoreanCandidate(compact)
            || hasWeakConversationalSuffix(compact)
            || koreanGenericConversationalFragments.contains { compact.contains($0) }
    }

    private static func isPredicativeKoreanCandidate(_ compact: String) -> Bool {
        if isGenericConversationalCandidate(compact) {
            return true
        }
        guard koreanPredicativeSurfaceHints.contains(where: { compact.contains($0) }) else {
            return false
        }
        if koreanPredicativeFragments.contains(where: { compact.contains($0) }) {
            return true
        }
        return koreanPredicativeRoots.contains { root in
            guard let range = compact.range(of: root) else {
                return false
            }
            let suffix = String(compact[range.upperBound...])
            guard !suffix.isEmpty else {
                return false
            }
            return koreanPredicativeSuffixes.contains { suffix.hasPrefix($0) }
        }
    }

    private static func hasKoreanGlossaryNounSignal(_ compact: String) -> Bool {
        koreanGlossaryNounSignals.contains { signal in
            compact.contains(signal)
        }
    }

    private static func hasWeakConversationalSuffix(_ compact: String) -> Bool {
        koreanWeakConversationalSuffixes.contains { suffix in
            compact.hasSuffix(suffix)
        }
    }

    private static func cleanTranscriptLine(_ line: String) -> String {
        var value = line.replacingOccurrences(
            of: #"\[[0-9:.]+\]"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\b[\w.+-]+@[\w.-]+\b"#,
            with: " ",
            options: .regularExpression
        )
        if let colon = value.firstIndex(of: ":"),
           value.distance(from: value.startIndex, to: colon) < 40 {
            value = String(value[value.index(after: colon)...])
        }
        return value
    }

    private static func stripParticle(_ value: String) -> String {
        for suffix in koreanParticles {
            if value.count - suffix.count >= 2, value.hasSuffix(suffix) {
                return String(value.dropLast(suffix.count))
            }
        }
        return value
    }

    private static func isLikelyGenericExtension(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.contains(rhs) || rhs.contains(lhs) {
            let longer = lhs.count >= rhs.count ? lhs : rhs
            let shorter = lhs.count >= rhs.count ? rhs : lhs
            guard longer.hasPrefix(shorter) else {
                return false
            }
            let suffix = String(longer.dropFirst(shorter.count))
            return koreanParticles.contains(suffix) || koreanGenericExtensionSuffixes.contains(suffix)
        }
        return false
    }

    private static func koreanScore(_ lhs: String, _ rhs: String) -> KoreanPhraseScore {
        let syllable = 1 - Double(editDistance(lhs, rhs)) / Double(max(lhs.count, rhs.count))
        let lhsJamo = hangulJamo(lhs)
        let rhsJamo = hangulJamo(rhs)
        let jamoLength = max(max(lhsJamo.count, rhsJamo.count), 1)
        let jamo = 1 - Double(editDistance(lhsJamo, rhsJamo)) / Double(jamoLength)
        let bigram = bigramDice(lhs, rhs)
        let lhsInitials = hangulInitials(lhs)
        let rhsInitials = hangulInitials(rhs)
        let initialLength = max(max(lhsInitials.count, rhsInitials.count), 1)
        let initials = 1 - Double(editDistance(lhsInitials, rhsInitials)) / Double(initialLength)
        return KoreanPhraseScore(
            value: 0.35 * syllable + 0.35 * jamo + 0.20 * bigram + 0.10 * initials,
            syllable: syllable,
            jamo: jamo,
            bigram: bigram,
            initials: initials
        )
    }

    private static func overlap(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private static func hangulInitials(_ value: String) -> String {
        String(value.compactMap { character in
            hangulComponents(for: character)?.initial
        })
    }

    private static func hangulJamo(_ value: String) -> String {
        value.compactMap { character -> String? in
            guard let components = hangulComponents(for: character) else {
                return nil
            }
            return "\(components.initial)\(components.medial)\(components.final)"
        }
        .joined()
    }

    private static func hangulComponents(for character: Character) -> (initial: Character, medial: Character, final: String)? {
        guard let scalar = character.unicodeScalars.first else {
            return nil
        }
        let value = Int(scalar.value) - 0xAC00
        guard value >= 0, value <= 11171 else {
            return nil
        }
        let initial = value / 588
        let medial = (value % 588) / 28
        let final = value % 28
        return (hangulInitialsTable[initial], hangulMedialsTable[medial], hangulFinalsTable[final])
    }

    private static func similarInitials(for initial: Character) -> [Character] {
        for group in similarInitialGroups where group.contains(initial) {
            return Array(group)
        }
        return [initial]
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

    private static func bigramDice(_ lhs: String, _ rhs: String) -> Double {
        let lhsBigrams = bigrams(lhs)
        let rhsBigrams = bigrams(rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return 0
        }
        let lhsCounts = lhsBigrams.reduce(into: [:]) { (counts: inout [String: Int], value) in
            counts[value, default: 0] += 1
        }
        let rhsCounts = rhsBigrams.reduce(into: [:]) { (counts: inout [String: Int], value) in
            counts[value, default: 0] += 1
        }
        let intersection = lhsCounts.reduce(0) { partial, element in
            partial + min(element.value, rhsCounts[element.key] ?? 0)
        }
        return Double(intersection * 2) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private static func bigrams(_ value: String) -> [String] {
        let values = Array(value)
        guard values.count >= 2 else {
            return []
        }
        return (0..<(values.count - 1)).map { String(values[$0...($0 + 1)]) }
    }

    private static func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }
}

private struct KoreanToken: Equatable {
    var display: String
    var compact: String
}

private struct KoreanPhraseOccurrence {
    var display: String
    var compact: String
    var documentID: String
    var documentTitle: String
    var timestamp: String?
    var excerpt: String
    var contextValues: Set<String>
}

private struct KoreanPhraseCandidate {
    var display: String
    var compact: String
    var occurrences: [KoreanPhraseOccurrence]

    var documentCount: Int {
        Set(occurrences.map(\.documentID)).count
    }

    var occurrenceCount: Int {
        occurrences.count
    }

    var contextValues: Set<String> {
        occurrences.reduce(into: Set<String>()) { result, occurrence in
            result.formUnion(occurrence.contextValues)
        }
    }

    var priority: Double {
        Double(documentCount * 2) + min(Double(occurrenceCount), 20) * 0.4
    }
}

private struct KoreanPhraseCandidatePair {
    var lhs: KoreanPhraseCandidate
    var rhs: KoreanPhraseCandidate
    var score: Double
    var contextOverlap: Double
    var scoreBreakdown: KoreanPhraseScore
}

private struct KoreanPhraseScore {
    var value: Double
    var syllable: Double
    var jamo: Double
    var bigram: Double
    var initials: Double
}

private struct KoreanCandidateBucketKey: Hashable {
    var initial: Character
    var length: Int

    init(initial: Character, length: Int) {
        self.initial = initial
        self.length = length
    }

    init(candidate: KoreanPhraseCandidate) {
        self.initial = KoreanCandidateBucketKey.firstInitial(in: candidate.compact) ?? " "
        self.length = candidate.compact.count
    }

    private static func firstInitial(in value: String) -> Character? {
        value.compactMap { character -> Character? in
            guard let scalar = character.unicodeScalars.first else {
                return nil
            }
            let hangulValue = Int(scalar.value) - 0xAC00
            guard hangulValue >= 0, hangulValue <= 11171 else {
                return nil
            }
            return hangulInitialsTable[hangulValue / 588]
        }
        .first
    }
}

private extension Array where Element == String {
    func normalizedKoreanSuggestionAliases() -> [String] {
        Array(Set(map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

private let koreanStopWords: Set<String> = [
    "그리고", "그래서", "그러면", "그런데", "근데", "이제", "지금", "그냥", "약간",
    "저희", "제가", "저는", "제게", "우리", "우리가", "이거", "그거", "저거", "여기", "거기",
    "오늘", "내일", "다음", "이번", "지난", "계속", "조금", "진짜", "일단", "혹시",
    "경우", "부분", "관련", "대한", "대해서", "때문에", "회의", "회의록", "회의실",
    "말씀", "생각", "사람", "분들", "내용", "얘기", "이야기", "질문", "답변",
    "확인", "진행", "정리", "공유", "준비", "업데이트", "문제", "이슈", "느낌",
    "정도", "방식", "방향", "상황", "기능", "작업", "일정", "시간",
    "그다음", "그러니까", "그니까", "예를", "보면", "보니까", "가지고", "갖고",
    "수도", "해야", "있는", "있을", "거고", "거라고", "같아서", "한번",
    "해보려고", "해볼려고", "보여주", "보여주고", "보여줄", "기본적", "기본적인",
    "부분이", "부분이고", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일",
    "일요일", "보려고", "볼려고", "예정", "예정이", "예정이라", "있어서",
    "요거", "고거", "주전", "전주", "초의", "고민", "고민하고", "고민하다",
    "없으시면", "있으시면", "가능하시면", "상황인", "상황인데"
]

private let koreanGenericSuffixes: [String] = [
    "같아", "같고", "같은", "같긴", "같기", "같아서", "싶어", "싶기", "싶긴", "싶어서",
    "합니다", "했습니다", "있습니다", "나왔습니다", "나왔고", "필요하다", "필요하다고",
    "필요할", "필요한", "되는데", "되는지", "좋겠다", "좋겠다고", "좋을", "주시면",
    "주세요", "만들어", "만들어서", "하는지", "있어서", "있어", "봅니다",
    "없습니다", "않습니다", "습니다"
]

private let koreanGenericPointerPrefixes: [String] = [
    "이런", "요런", "그런", "고런", "저런", "어떤"
]

private let koreanGenericPointerSuffixes: [String] = [
    "부분", "부분들", "것", "것들", "내용", "얘기", "이야기"
]

private let koreanGenericConversationalPrefixes: [String] = [
    "하고", "되어", "예를들어", "진행하", "진행해", "업데이트하", "업데이트해",
    "작업하", "요렇게", "이렇게", "그렇게", "고렇게", "나오", "가능하",
    "들어가", "들어간", "들어갈", "나온", "나올", "있었", "상황이", "상태입",
    "필요없", "필요하", "전달해", "모르겠", "그다음", "그러니까", "그니까",
    "그러니", "예를", "보면", "보니까", "일단은", "어쨌든", "초의", "해야",
    "보여주", "보여지", "만들어", "가지고", "갖고", "있는거", "없는거", "하는거",
    "있을거", "수도", "수는", "해보", "해볼", "기본적", "부분이", "같아서", "주시",
    "얘기하", "보려고", "볼려고", "예정", "있어서", "요거", "고거", "초의",
    "고민", "고민하", "없으시면", "있으시면", "가능하시면", "상황인", "상황인데"
]

private let koreanGenericConversationalFragments: [String] = [
    "해야되", "해야될", "해야하", "보여주", "보여줄", "보여지", "하는거", "있는거",
    "없는거", "있을거", "가지고있는", "갖고있는", "수도있는", "수도있을", "있기때문",
    "없기때문", "때문", "만들어", "떨어지", "보면", "수는", "해보려고",
    "해볼려고", "부분이고", "부분이", "같아서", "주시고", "주시기", "얘기하면",
    "얘기하면서", "보려고", "볼려고", "예정이에", "예정이라", "있어서",
    "요거", "고거", "주전", "초의", "고민하고", "고민하다", "없으시면",
    "있으시면", "가능하시면", "상황인", "상황인데"
]

private let koreanPredicativeRoots: [String] = [
    "가능", "개선", "검토", "계산", "공유", "관리", "등록", "반영", "배포", "변경",
    "비교", "삭제", "사용", "생각", "생성", "수정", "실행", "연결", "요청", "완료",
    "이해", "입력", "작업", "전달", "적용", "정리", "조정", "준비", "진행", "처리",
    "추가", "출력", "통합", "확인", "확장", "협의", "호출", "만들", "중요", "얘기",
    "노출", "고민"
]

private let koreanPredicativeSuffixes: [String] = [
    "하", "하기", "한", "할", "함", "해", "해서", "하게", "하고", "하는", "하면", "하며", "했고",
    "했", "해야", "하다", "된", "될", "되는", "되면", "돼", "되어", "된다", "됩", "한지",
    "할지", "하는지", "했는지", "했을지"
]

private let koreanPredicativeSurfaceHints: [String] = [
    "하", "한", "할", "함", "해", "했", "해야", "하는", "하면", "하며", "된", "될",
    "되는", "되면", "돼", "되어", "됩", "하고"
]

private let koreanPredicativeFragments: [String] = [
    "가능한", "가능할", "작업한", "작업할", "진행한", "진행할", "업데이트한", "업데이트할",
    "공유한", "공유할", "확인한", "확인할", "정리한", "정리할", "전달한", "전달할",
    "전달해", "반영한", "반영할", "수정한", "수정할", "변경한", "변경할", "적용한",
    "적용할", "생성한", "생성할", "호출한", "호출할", "계산한", "계산할", "검토한",
    "검토할", "처리한", "처리할", "배포한", "배포할", "연결한", "연결할", "추가한",
    "추가할", "삭제한", "삭제할", "등록한", "등록할", "사용한", "사용할", "요청한",
    "요청할", "들어간", "들어갈", "나온", "나올", "되는", "되어", "하고있는",
    "하고있는데"
]

private let koreanWeakConversationalSuffixes: [String] = [
    "한데", "하는데", "할지", "한지", "해서", "하게", "했고", "합니다", "됩니다",
    "있고", "있는데", "있어서", "같은", "같고", "싶은", "싶고", "보면", "보니",
    "봐야", "되는", "된다", "되면", "되게", "거는", "거를", "거죠", "되나",
    "되지", "되고", "하기", "해야", "때문", "적인", "이고", "하", "해", "할",
    "주전", "초의", "으시면", "시면", "인데"
]

private let koreanGlossaryNounSignals: [String] = [
    "건수", "검색", "계약", "결제", "금액", "매물", "문의", "상품", "상담", "서비스",
    "신규", "아이오에스", "안드로이드", "어드민", "오가닉", "오피스텔", "응답률", "이용금액",
    "임대인", "전환", "전환율", "주문", "중개사", "지표", "채팅", "활성", "활성제",
    "환불", "비율", "비중", "유저", "율", "률", "액"
]

private let koreanDomainContextTokens: Set<String> = [
    "개발", "검색", "계약", "결제", "기능", "데이터", "마케팅", "매물", "분석", "상품",
    "신규", "안드로이드", "아이오에스", "오가닉", "유저", "이용금액", "전환", "주문",
    "지표", "활성", "환불"
]

private let koreanGenericExtensionSuffixes: [String] = [
    "하", "할", "한", "함", "해", "해서", "하게", "하죠", "하자", "자", "에", "은", "는", "이", "가",
    "을", "를", "에서", "으로", "로"
]

private let koreanParticles: [String] = [
    "이라고요", "이라고", "라는거", "라는", "라고요", "라고", "으로는", "으로도", "으로서", "으로써",
    "에서는", "에서", "에게는", "에게", "께서", "부터", "까지", "처럼", "보다", "하고", "이며",
    "이고", "라서", "으로", "은", "는", "이", "가", "을", "를", "에", "의", "도", "만", "와", "과",
    "로", "랑", "요"
]

private let hangulInitialsTable: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
private let hangulMedialsTable: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
private let hangulFinalsTable: [String] = [
    "", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ",
    "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
]
private let similarInitialGroups: [Set<Character>] = [
    Set("ㄱㅋㄲ"),
    Set("ㄷㅌㄸ"),
    Set("ㅂㅍㅃ"),
    Set("ㅈㅊㅉ"),
    Set("ㅅㅆ"),
    Set("ㅇㅎ"),
    Set("ㄴㄹ")
]
