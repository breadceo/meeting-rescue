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

public struct LocalGlossarySuggestion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var suggestedCanonical: String
    public var aliases: [String]
    public var evidence: [LocalGlossaryEvidence]
    public var occurrenceCount: Int
    public var meetingCount: Int
    public var confidence: Double
    public var createdAt: Date

    public init(
        id: String,
        suggestedCanonical: String,
        aliases: [String],
        evidence: [LocalGlossaryEvidence],
        occurrenceCount: Int,
        meetingCount: Int,
        confidence: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.suggestedCanonical = suggestedCanonical.trimmedGlossaryText
        self.aliases = aliases.normalizedGlossaryValues(excluding: [suggestedCanonical])
        self.evidence = Array(evidence.prefix(5))
        self.occurrenceCount = max(0, occurrenceCount)
        self.meetingCount = max(0, meetingCount)
        self.confidence = min(1, max(0, confidence))
        self.createdAt = createdAt
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
    public var dismissedSuggestionIDs: Set<String>
    public var updatedAt: Date

    public init(
        terms: [LocalGlossaryTerm] = [],
        suggestions: [LocalGlossarySuggestion] = [],
        dismissedSuggestionIDs: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.terms = terms
        self.suggestions = suggestions
        self.dismissedSuggestionIDs = dismissedSuggestionIDs
        self.updatedAt = updatedAt
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
        terms.removeAll { existing in
            MeetingHistorySearch.compactNormalize(existing.canonical) == MeetingHistorySearch.compactNormalize(term.canonical)
        }
        terms.append(term)
        updatedAt = now
    }

    public mutating func dismissSuggestion(id: String) {
        suggestions.removeAll { $0.id == id }
        dismissedSuggestionIDs.insert(id)
        updatedAt = Date()
    }

    public mutating func upsertSuggestion(_ suggestion: LocalGlossarySuggestion) {
        guard !dismissedSuggestionIDs.contains(suggestion.id) else {
            return
        }
        if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
            suggestions[index] = suggestion
        } else {
            suggestions.append(suggestion)
        }
        suggestions.sort {
            if $0.confidence == $1.confidence {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.confidence > $1.confidence
        }
        updatedAt = Date()
    }

    public mutating func deleteTerm(id: String) {
        terms.removeAll { $0.id == id }
        updatedAt = Date()
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
