import Foundation

public enum LocalGlossaryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case project
    case product
    case team
    case person
    case acronym
    case domainTerm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .project:
            return "Project"
        case .product:
            return "Product"
        case .team:
            return "Team"
        case .person:
            return "Person"
        case .acronym:
            return "Acronym"
        case .domainTerm:
            return "Domain term"
        }
    }
}

public enum LocalGlossaryTermSource: String, Codable, Sendable {
    case manual
    case suggested
}

public enum LocalGlossaryCandidateLane: String, Codable, Sendable {
    case strict
    case review
}

public struct LocalGlossaryTerm: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var canonical: String
    public var aliases: [String]
    public var category: LocalGlossaryCategory
    public var note: String
    public var isEnabled: Bool
    public var source: LocalGlossaryTermSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        canonical: String,
        aliases: [String],
        category: LocalGlossaryCategory = .domainTerm,
        note: String = "",
        isEnabled: Bool = true,
        source: LocalGlossaryTermSource = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.canonical = canonical.trimmedGlossaryText
        self.aliases = aliases.normalizedGlossaryValues(excluding: [canonical])
        self.category = category
        self.note = note.trimmedGlossaryText
        self.isEnabled = isEnabled
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var allMatchValues: [String] {
        ([canonical] + aliases).normalizedGlossaryValues()
    }
}

public struct LocalGlossaryEvidence: Codable, Equatable, Sendable {
    public var sourceID: String
    public var sourceTitle: String
    public var excerpt: String
    public var timestamp: String?

    public init(sourceID: String, sourceTitle: String, excerpt: String, timestamp: String? = nil) {
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.excerpt = excerpt.trimmedGlossaryText
        self.timestamp = timestamp?.trimmedGlossaryText.nonEmptyGlossaryText
    }
}

public struct LocalGlossaryCandidateImpactLabel: Codable, Equatable, Sendable {
    public var summarySearchImpact: Double
    public var summarySearchReasons: [String]
    public var qualityTier: String

    public static let low = LocalGlossaryCandidateImpactLabel(
        summarySearchImpact: 0,
        summarySearchReasons: ["strict-filter"],
        qualityTier: "low"
    )

    public init(
        summarySearchImpact: Double = 0,
        summarySearchReasons: [String] = ["strict-filter"],
        qualityTier: String = "low"
    ) {
        self.summarySearchImpact = min(1, max(0, summarySearchImpact))
        self.summarySearchReasons = summarySearchReasons
            .map(\.trimmedGlossaryText)
            .filter { !$0.isEmpty }
        if self.summarySearchReasons.isEmpty {
            self.summarySearchReasons = ["strict-filter"]
        }
        self.qualityTier = qualityTier.trimmedGlossaryText.nonEmptyGlossaryText ?? "low"
    }

    public static func estimated(
        aliases: [String],
        phoneticSimilarity: Double,
        graphemicSimilarity: Double,
        contextOverlap: Double,
        termhood: Double,
        recurrence: Double,
        noisePenalty: Double,
        finalScore: Double
    ) -> LocalGlossaryCandidateImpactLabel {
        let similarity = max(phoneticSimilarity, graphemicSimilarity)
        var reasons: [String] = []
        if aliases.count >= 2, similarity >= 0.70 {
            reasons.append("canonical-would-normalize-summary")
        }
        if recurrence >= 0.45 {
            reasons.append("improves-history-search")
        }
        if contextOverlap >= 0.12 {
            reasons.append("shared-context-overlap")
        }
        if termhood >= 0.65 {
            reasons.append("domain-termhood")
        }
        if finalScore >= 0.75 {
            reasons.append("high-confidence")
        }
        let criteriaSupport = min(1, Double(reasons.count) / 5)
        let impact = min(
            1,
            max(
                0,
                0.30 * finalScore
                    + 0.25 * similarity
                    + 0.20 * contextOverlap
                    + 0.15 * recurrence
                    + 0.10 * termhood
                    + 0.10 * criteriaSupport
                    - 0.40 * noisePenalty
            )
        )
        let tier: String
        if impact >= 0.80, reasons.count >= 3 {
            tier = "high"
        } else if impact >= 0.40, reasons.count >= 2 {
            tier = "medium"
        } else {
            tier = "low"
        }
        return LocalGlossaryCandidateImpactLabel(
            summarySearchImpact: impact,
            summarySearchReasons: reasons.isEmpty ? ["strict-filter"] : reasons,
            qualityTier: tier
        )
    }
}

public struct LocalGlossarySuggestionScore: Codable, Equatable, Sendable {
    public var phoneticSimilarity: Double
    public var graphemicSimilarity: Double
    public var contextOverlap: Double
    public var termhood: Double
    public var recurrence: Double
    public var noisePenalty: Double
    public var finalScore: Double
    public var matchedCriteria: [String]
    public var impactLabel: LocalGlossaryCandidateImpactLabel

    public static let empty = LocalGlossarySuggestionScore()

    public init(
        phoneticSimilarity: Double = 0,
        graphemicSimilarity: Double = 0,
        contextOverlap: Double = 0,
        termhood: Double = 0,
        recurrence: Double = 0,
        noisePenalty: Double = 0,
        finalScore: Double = 0,
        matchedCriteria: [String] = [],
        impactLabel: LocalGlossaryCandidateImpactLabel = .low
    ) {
        self.phoneticSimilarity = Self.clamped(phoneticSimilarity)
        self.graphemicSimilarity = Self.clamped(graphemicSimilarity)
        self.contextOverlap = Self.clamped(contextOverlap)
        self.termhood = Self.clamped(termhood)
        self.recurrence = Self.clamped(recurrence)
        self.noisePenalty = Self.clamped(noisePenalty)
        self.finalScore = Self.clamped(finalScore)
        self.matchedCriteria = matchedCriteria
            .map(\.trimmedGlossaryText)
            .filter { !$0.isEmpty }
        self.impactLabel = impactLabel
    }

    private enum CodingKeys: String, CodingKey {
        case phoneticSimilarity
        case graphemicSimilarity
        case contextOverlap
        case termhood
        case recurrence
        case noisePenalty
        case finalScore
        case matchedCriteria
        case impactLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            phoneticSimilarity: try container.decodeIfPresent(Double.self, forKey: .phoneticSimilarity) ?? 0,
            graphemicSimilarity: try container.decodeIfPresent(Double.self, forKey: .graphemicSimilarity) ?? 0,
            contextOverlap: try container.decodeIfPresent(Double.self, forKey: .contextOverlap) ?? 0,
            termhood: try container.decodeIfPresent(Double.self, forKey: .termhood) ?? 0,
            recurrence: try container.decodeIfPresent(Double.self, forKey: .recurrence) ?? 0,
            noisePenalty: try container.decodeIfPresent(Double.self, forKey: .noisePenalty) ?? 0,
            finalScore: try container.decodeIfPresent(Double.self, forKey: .finalScore) ?? 0,
            matchedCriteria: try container.decodeIfPresent([String].self, forKey: .matchedCriteria) ?? [],
            impactLabel: try container.decodeIfPresent(LocalGlossaryCandidateImpactLabel.self, forKey: .impactLabel) ?? .low
        )
    }

    public var summaryText: String {
        let criteria = matchedCriteria.isEmpty ? "strict filter" : matchedCriteria.joined(separator: " · ")
        return "근거 \(criteria) · 최종 \(Int(finalScore * 100))%"
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct LocalGlossarySuggestion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var suggestedCanonical: String
    public var aliases: [String]
    public var evidence: [LocalGlossaryEvidence]
    public var occurrenceCount: Int
    public var meetingCount: Int
    public var confidence: Double
    public var score: LocalGlossarySuggestionScore
    public var lane: LocalGlossaryCandidateLane
    public var reviewReason: String
    public var createdAt: Date

    public init(
        id: String,
        suggestedCanonical: String,
        aliases: [String],
        evidence: [LocalGlossaryEvidence],
        occurrenceCount: Int,
        meetingCount: Int,
        confidence: Double,
        score: LocalGlossarySuggestionScore = .empty,
        lane: LocalGlossaryCandidateLane = .strict,
        reviewReason: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.suggestedCanonical = suggestedCanonical.trimmedGlossaryText
        self.aliases = aliases.normalizedGlossaryValues()
        self.evidence = Array(evidence.prefix(5))
        self.occurrenceCount = max(0, occurrenceCount)
        self.meetingCount = max(0, meetingCount)
        self.confidence = min(1, max(0, confidence))
        self.score = score.finalScore == 0
            ? LocalGlossarySuggestionScore(finalScore: min(1, max(0, confidence)))
            : score
        self.lane = lane
        self.reviewReason = reviewReason.trimmedGlossaryText
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case suggestedCanonical
        case aliases
        case evidence
        case occurrenceCount
        case meetingCount
        case confidence
        case score
        case lane
        case reviewReason
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        suggestedCanonical = try container.decode(String.self, forKey: .suggestedCanonical)
        aliases = try container.decode([String].self, forKey: .aliases)
        evidence = try container.decode([LocalGlossaryEvidence].self, forKey: .evidence)
        occurrenceCount = try container.decode(Int.self, forKey: .occurrenceCount)
        meetingCount = try container.decode(Int.self, forKey: .meetingCount)
        confidence = try container.decode(Double.self, forKey: .confidence)
        score = try container.decodeIfPresent(LocalGlossarySuggestionScore.self, forKey: .score)
            ?? LocalGlossarySuggestionScore(finalScore: confidence)
        lane = try container.decodeIfPresent(LocalGlossaryCandidateLane.self, forKey: .lane) ?? .strict
        reviewReason = try container.decodeIfPresent(String.self, forKey: .reviewReason) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

public struct LocalGlossaryRefreshDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public struct StageTiming: Codable, Equatable, Sendable {
        public var name: String
        public var elapsedMilliseconds: Int
        public var detail: String

        public init(name: String, elapsedMilliseconds: Int, detail: String = "") {
            self.name = name.trimmedGlossaryText
            self.elapsedMilliseconds = max(0, elapsedMilliseconds)
            self.detail = detail.trimmedGlossaryText
        }
    }

    public struct SuggestionSummary: Codable, Equatable, Sendable {
        public var id: String
        public var suggestedCanonical: String
        public var aliases: [String]
        public var occurrenceCount: Int
        public var meetingCount: Int
        public var confidence: Double
        public var score: LocalGlossarySuggestionScore

        public init(
            id: String,
            suggestedCanonical: String,
            aliases: [String],
            occurrenceCount: Int,
            meetingCount: Int,
            confidence: Double,
            score: LocalGlossarySuggestionScore = .empty
        ) {
            self.id = id.trimmedGlossaryText
            self.suggestedCanonical = suggestedCanonical.trimmedGlossaryText
            self.aliases = aliases.normalizedGlossaryValues()
            self.occurrenceCount = max(0, occurrenceCount)
            self.meetingCount = max(0, meetingCount)
            self.confidence = min(1, max(0, confidence))
            self.score = score.finalScore == 0
                ? LocalGlossarySuggestionScore(finalScore: self.confidence)
                : score
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case suggestedCanonical
            case aliases
            case occurrenceCount
            case meetingCount
            case confidence
            case score
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            suggestedCanonical = try container.decode(String.self, forKey: .suggestedCanonical)
            aliases = try container.decode([String].self, forKey: .aliases)
            occurrenceCount = try container.decode(Int.self, forKey: .occurrenceCount)
            meetingCount = try container.decode(Int.self, forKey: .meetingCount)
            confidence = try container.decode(Double.self, forKey: .confidence)
            score = try container.decodeIfPresent(LocalGlossarySuggestionScore.self, forKey: .score)
                ?? LocalGlossarySuggestionScore(finalScore: confidence)
        }
    }

    public var id: String
    public var createdAt: Date
    public var folderPath: String
    public var documentCount: Int
    public var suggestionCount: Int
    public var scanMilliseconds: Int
    public var suggestionMilliseconds: Int
    public var saveMilliseconds: Int
    public var totalMilliseconds: Int
    public var stages: [StageTiming]
    public var suggestions: [SuggestionSummary]
    public var engineDiagnostics: LocalGlossarySuggestionEngineDiagnostics?

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        folderPath: String,
        documentCount: Int,
        suggestionCount: Int,
        scanMilliseconds: Int,
        suggestionMilliseconds: Int,
        saveMilliseconds: Int,
        totalMilliseconds: Int,
        stages: [StageTiming],
        suggestions: [SuggestionSummary],
        engineDiagnostics: LocalGlossarySuggestionEngineDiagnostics? = nil
    ) {
        self.id = id.trimmedGlossaryText
        self.createdAt = createdAt
        self.folderPath = folderPath
        self.documentCount = max(0, documentCount)
        self.suggestionCount = max(0, suggestionCount)
        self.scanMilliseconds = max(0, scanMilliseconds)
        self.suggestionMilliseconds = max(0, suggestionMilliseconds)
        self.saveMilliseconds = max(0, saveMilliseconds)
        self.totalMilliseconds = max(0, totalMilliseconds)
        self.stages = stages
        self.suggestions = Array(suggestions.prefix(12))
        self.engineDiagnostics = engineDiagnostics
    }
}

public struct LocalGlossaryMatch: Codable, Equatable, Sendable {
    public var termID: String
    public var canonical: String
    public var category: LocalGlossaryCategory
    public var matchedAliases: [String]
    public var evidenceExcerpts: [String]
    public var confidence: Double

    public init(
        termID: String,
        canonical: String,
        category: LocalGlossaryCategory,
        matchedAliases: [String],
        evidenceExcerpts: [String],
        confidence: Double
    ) {
        self.termID = termID
        self.canonical = canonical.trimmedGlossaryText
        self.category = category
        self.matchedAliases = matchedAliases.normalizedGlossaryValues(excluding: [canonical])
        self.evidenceExcerpts = Array(evidenceExcerpts.map(\.trimmedGlossaryText).filter { !$0.isEmpty }.prefix(3))
        self.confidence = min(1, max(0, confidence))
    }
}

public struct LocalGlossaryState: Codable, Equatable, Sendable {
    public var terms: [LocalGlossaryTerm]
    public var suggestions: [LocalGlossarySuggestion]
    public var reviewCandidates: [LocalGlossarySuggestion]
    public var dismissedSuggestionIDs: Set<String>
    public var rejectedSuggestionIDs: Set<String>
    public var updatedAt: Date

    public init(
        terms: [LocalGlossaryTerm] = [],
        suggestions: [LocalGlossarySuggestion] = [],
        reviewCandidates: [LocalGlossarySuggestion] = [],
        dismissedSuggestionIDs: Set<String> = [],
        rejectedSuggestionIDs: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.terms = terms
        self.suggestions = suggestions
        self.reviewCandidates = reviewCandidates
        self.dismissedSuggestionIDs = dismissedSuggestionIDs
        self.rejectedSuggestionIDs = rejectedSuggestionIDs
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case terms
        case suggestions
        case reviewCandidates
        case dismissedSuggestionIDs
        case rejectedSuggestionIDs
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        terms = try container.decodeIfPresent([LocalGlossaryTerm].self, forKey: .terms) ?? []
        suggestions = try container.decodeIfPresent([LocalGlossarySuggestion].self, forKey: .suggestions) ?? []
        reviewCandidates = try container.decodeIfPresent([LocalGlossarySuggestion].self, forKey: .reviewCandidates) ?? []
        dismissedSuggestionIDs = try container.decodeIfPresent(Set<String>.self, forKey: .dismissedSuggestionIDs) ?? []
        rejectedSuggestionIDs = try container.decodeIfPresent(Set<String>.self, forKey: .rejectedSuggestionIDs) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    public var enabledTerms: [LocalGlossaryTerm] {
        terms.filter { $0.isEnabled && !$0.canonical.isEmpty }
    }

    public mutating func acceptSuggestion(
        id: String,
        canonical: String,
        category: LocalGlossaryCategory
    ) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else {
            return
        }
        let now = Date()
        let term = LocalGlossaryTerm(
            canonical: canonical,
            aliases: suggestion.aliases,
            category: category,
            note: "history 기반 제안에서 추가됨",
            source: .suggested,
            createdAt: now,
            updatedAt: now
        )
        suggestions.removeAll { $0.id == id }
        dismissedSuggestionIDs.remove(id)
        rejectedSuggestionIDs.remove(id)
        terms.removeAll { existing in
            MeetingHistorySearch.compactNormalize(existing.canonical) == MeetingHistorySearch.compactNormalize(term.canonical)
        }
        terms.append(term)
        updatedAt = now
    }

    public mutating func dismissSuggestion(id: String) {
        suggestions.removeAll { $0.id == id }
        reviewCandidates.removeAll { $0.id == id }
        dismissedSuggestionIDs.insert(id)
        updatedAt = Date()
    }

    public mutating func upsertSuggestion(_ suggestion: LocalGlossarySuggestion) {
        guard !dismissedSuggestionIDs.contains(suggestion.id),
              !rejectedSuggestionIDs.contains(suggestion.id) else {
            return
        }
        var suggestion = suggestion
        if suggestion.lane == .review {
            if let index = reviewCandidates.firstIndex(where: { $0.id == suggestion.id }) {
                reviewCandidates[index] = suggestion
            } else {
                reviewCandidates.append(suggestion)
            }
            reviewCandidates = reviewCandidates.sortedByGlossaryConfidence
        } else {
            suggestion.lane = .strict
            if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                suggestions[index] = suggestion
            } else {
                suggestions.append(suggestion)
            }
            suggestions = suggestions.sortedByGlossaryConfidence
        }
        updatedAt = Date()
    }

    public mutating func replaceSuggestions(_ nextSuggestions: [LocalGlossarySuggestion]) {
        replaceSuggestions(strict: nextSuggestions, review: reviewCandidates)
    }

    public mutating func replaceSuggestions(
        strict strictSuggestions: [LocalGlossarySuggestion],
        review reviewSuggestions: [LocalGlossarySuggestion]
    ) {
        suggestions = strictSuggestions
            .filter { !dismissedSuggestionIDs.contains($0.id) && !rejectedSuggestionIDs.contains($0.id) }
            .map { suggestion in
                var value = suggestion
                value.lane = .strict
                return value
            }
            .sortedByGlossaryConfidence
        reviewCandidates = reviewSuggestions
            .filter { !dismissedSuggestionIDs.contains($0.id) && !rejectedSuggestionIDs.contains($0.id) }
            .map { suggestion in
                var value = suggestion
                value.lane = .review
                return value
            }
            .sortedByGlossaryConfidence
        updatedAt = Date()
    }

    public mutating func addReviewCandidate(
        id: String,
        asAliasesToTermID termID: String
    ) {
        guard let candidate = reviewCandidates.first(where: { $0.id == id }),
              let termIndex = terms.firstIndex(where: { $0.id == termID }) else {
            return
        }
        let aliases = (terms[termIndex].aliases + candidate.aliases)
            .normalizedGlossaryValues(excluding: [terms[termIndex].canonical])
        terms[termIndex].aliases = aliases
        terms[termIndex].updatedAt = Date()
        reviewCandidates.removeAll { $0.id == id }
        dismissedSuggestionIDs.remove(id)
        rejectedSuggestionIDs.remove(id)
        updatedAt = Date()
    }

    public mutating func acceptReviewCandidateAsNewTerm(
        id: String,
        canonical: String,
        category: LocalGlossaryCategory
    ) {
        guard let candidate = reviewCandidates.first(where: { $0.id == id }) else {
            return
        }
        let now = Date()
        terms.removeAll { existing in
            MeetingHistorySearch.compactNormalize(existing.canonical) == MeetingHistorySearch.compactNormalize(canonical)
        }
        terms.append(LocalGlossaryTerm(
            canonical: canonical,
            aliases: candidate.aliases,
            category: category,
            note: "review queue에서 추가됨",
            source: .suggested,
            createdAt: now,
            updatedAt: now
        ))
        reviewCandidates.removeAll { $0.id == id }
        dismissedSuggestionIDs.remove(id)
        rejectedSuggestionIDs.remove(id)
        updatedAt = now
    }

    public mutating func dismissReviewCandidate(id: String) {
        reviewCandidates.removeAll { $0.id == id }
        dismissedSuggestionIDs.insert(id)
        updatedAt = Date()
    }

    public mutating func markReviewCandidateAsNotSame(id: String) {
        reviewCandidates.removeAll { $0.id == id }
        rejectedSuggestionIDs.insert(id)
        updatedAt = Date()
    }

    public mutating func deleteTerm(id: String) {
        terms.removeAll { $0.id == id }
        updatedAt = Date()
    }
}

private extension Array where Element == LocalGlossarySuggestion {
    var sortedByGlossaryConfidence: [LocalGlossarySuggestion] {
        sorted {
            if $0.confidence == $1.confidence {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.confidence > $1.confidence
        }
    }
}

private extension String {
    var trimmedGlossaryText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmptyGlossaryText: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == String {
    func normalizedGlossaryValues(excluding excluded: [String] = []) -> [String] {
        let excludedValues = Set(excluded.map(MeetingHistorySearch.compactNormalize))
        var seen: Set<String> = []
        var values: [String] = []
        for value in self {
            let trimmed = value.trimmedGlossaryText
            let normalized = MeetingHistorySearch.compactNormalize(trimmed)
            guard !trimmed.isEmpty,
                  !excludedValues.contains(normalized),
                  !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            values.append(trimmed)
        }
        return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
