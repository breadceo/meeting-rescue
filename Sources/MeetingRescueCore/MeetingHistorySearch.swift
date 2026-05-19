import Foundation
import NaturalLanguage

public enum MeetingHistorySearchField: String, Equatable, Sendable {
    case title
    case file
    case date
    case participant
    case room
    case currentIssue
    case confirmedDecision
    case decision
    case confirmedAction
    case action
    case topic
    case note
    case rawTranscript

    public var displayName: String {
        switch self {
        case .title:
            return "제목"
        case .file:
            return "파일"
        case .date:
            return "일시"
        case .participant:
            return "참석자"
        case .room:
            return "room"
        case .currentIssue:
            return "현재 이슈"
        case .confirmedDecision:
            return "확정 결정"
        case .decision:
            return "결정 후보"
        case .confirmedAction:
            return "확정 액션"
        case .action:
            return "액션 후보"
        case .topic:
            return "흐름"
        case .note:
            return "note"
        case .rawTranscript:
            return "원문"
        }
    }
}

public struct MeetingHistorySearchSection: Equatable, Sendable {
    public var field: MeetingHistorySearchField
    public var text: String
    public var normalizedText: String
    public var compactNormalizedText: String
    public var searchTokens: Set<String>
    public var weight: Int
    public var timestamp: String?

    public init(
        field: MeetingHistorySearchField,
        text: String,
        weight: Int,
        timestamp: String? = nil
    ) {
        self.field = field
        self.text = text
        self.normalizedText = MeetingHistorySearch.normalize(text)
        self.compactNormalizedText = MeetingHistorySearch.compactNormalize(text)
        self.searchTokens = MeetingHistorySearch.expandedTokens(text)
        self.weight = weight
        self.timestamp = timestamp
    }
}

public struct MeetingHistorySearchMatch: Equatable, Sendable {
    public var score: Int
    public var field: MeetingHistorySearchField
    public var snippet: String
    public var timestamp: String?

    public init(score: Int, field: MeetingHistorySearchField, snippet: String, timestamp: String? = nil) {
        self.score = score
        self.field = field
        self.snippet = snippet
        self.timestamp = timestamp
    }

    public var displayText: String {
        let prefix = timestamp.map { "[\($0)] " } ?? ""
        return "\(prefix)\(field.displayName): \(snippet)"
    }
}

public enum MeetingHistorySearch {
    public static func match(
        sections: [MeetingHistorySearchSection],
        query: String
    ) -> MeetingHistorySearchMatch? {
        bestMatch(sections: sections, query: query)
    }

    public static func timestampedMatch(
        sections: [MeetingHistorySearchSection],
        query: String
    ) -> MeetingHistorySearchMatch? {
        bestMatch(sections: sections.filter { $0.timestamp != nil }, query: query)
    }

    private static func bestMatch(
        sections: [MeetingHistorySearchSection],
        query: String
    ) -> MeetingHistorySearchMatch? {
        let terms = tokenize(query)
        guard !terms.isEmpty else {
            return MeetingHistorySearchMatch(
                score: 0,
                field: .title,
                snippet: sections.first(where: { !$0.text.isBlank })?.text.trimmedSearchSnippet() ?? ""
            )
        }

        var score = 0
        var bestSectionMatch: (section: MeetingHistorySearchSection, term: String, score: Int)?
        let normalizedQuery = normalize(query)
        let compactQuery = compactNormalize(query)

        for term in terms {
            guard let termMatch = bestMatch(for: term, in: sections) else {
                return nil
            }
            score += termMatch.score
            if bestSectionMatch == nil || termMatch.score > bestSectionMatch!.score {
                bestSectionMatch = termMatch
            }
        }

        if let phraseMatch = bestPhraseMatch(
            normalizedPhrase: normalizedQuery,
            compactPhrase: compactQuery,
            in: sections
        ) {
            score += phraseMatch.score / 2
            if bestSectionMatch == nil || phraseMatch.score > bestSectionMatch!.score {
                bestSectionMatch = phraseMatch
            }
        }

        guard let bestSectionMatch else {
            return nil
        }
        return MeetingHistorySearchMatch(
            score: score,
            field: bestSectionMatch.section.field,
            snippet: bestSectionMatch.section.text.searchSnippet(around: bestSectionMatch.term),
            timestamp: bestSectionMatch.section.timestamp
        )
    }

    public static func tokenize(_ query: String) -> [String] {
        let normalizedTerms = normalize(query)
            .split { character in
                character.isWhitespace || character.isPunctuation || character.isSymbol
            }
            .map(String.init)
            .filter { !$0.isEmpty }
        let naturalTerms = naturalLanguageTokens(query)
        return Array(Set(normalizedTerms + naturalTerms)).sorted()
    }

    public static func expandedTokens(_ value: String) -> Set<String> {
        let baseTokens = tokenize(value)
        let grams = baseTokens.flatMap { token in
            token.count >= 3 && token.containsHangul ? characterNGrams(token, sizes: 2...4) : []
        }
        return Set(baseTokens + grams)
    }

    public static func indexText(for value: String) -> String {
        let compact = compactNormalize(value)
        var values = [value, normalize(value), compact]
        values.append(contentsOf: expandedTokens(value))
        if compact.count >= 3 {
            values.append(contentsOf: characterNGrams(compact, sizes: 2...4))
        }
        return Array(Set(values.filter { !$0.isEmpty })).joined(separator: " ")
    }

    public static func indexQueryTerms(for query: String) -> [String] {
        let terms = tokenize(query)
        let compact = compactNormalize(query)
        var values = terms
            .filter { $0.count >= 2 }
        if compact.count >= 2 {
            values.append(compact)
        }
        return Array(Set(values)).sorted()
    }

    private static func bestMatch(
        for term: String,
        in sections: [MeetingHistorySearchSection]
    ) -> (section: MeetingHistorySearchSection, term: String, score: Int)? {
        return sections.compactMap { section -> (section: MeetingHistorySearchSection, term: String, score: Int)? in
            let matchScore = lexicalScore(term: term, section: section)
            guard matchScore > 0 else {
                return nil
            }
            var score = section.weight + matchScore
            if section.normalizedText.hasPrefix(term) {
                score += 8
            }
            if section.normalizedText == term {
                score += 20
            }
            if term.count <= 2 {
                score += 4
            }
            return (section, term, score)
        }
        .max { lhs, rhs in
            lhs.score < rhs.score
        }
    }

    private static func bestPhraseMatch(
        normalizedPhrase: String,
        compactPhrase: String,
        in sections: [MeetingHistorySearchSection]
    ) -> (section: MeetingHistorySearchSection, term: String, score: Int)? {
        guard !normalizedPhrase.isEmpty || !compactPhrase.isEmpty else {
            return nil
        }
        return sections.compactMap { section -> (section: MeetingHistorySearchSection, term: String, score: Int)? in
            if !normalizedPhrase.isEmpty,
               section.normalizedText.contains(normalizedPhrase) {
                return (section, normalizedPhrase, section.weight + 24)
            }
            if !compactPhrase.isEmpty,
               section.compactNormalizedText.contains(compactPhrase) {
                return (section, compactPhrase, section.weight + 20)
            }
            let similarity = phraseSimilarity(compactPhrase, section.compactNormalizedText)
            guard similarity >= 0.72 else {
                return nil
            }
            return (section, compactPhrase, section.weight + Int((similarity * 16).rounded()))
        }
        .max { lhs, rhs in
            lhs.score < rhs.score
        }
    }

    public static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func compactNormalize(_ value: String) -> String {
        normalize(value).filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
    }

    private static func lexicalScore(term: String, section: MeetingHistorySearchSection) -> Int {
        if section.normalizedText.contains(term) {
            return 24
        }
        if section.compactNormalizedText.contains(term) {
            return 20
        }
        if section.searchTokens.contains(term) {
            return 18
        }
        if let bestSimilarity = section.searchTokens.map({ fuzzySimilarity(term, $0) }).max(),
           bestSimilarity >= 0.82 {
            return Int((bestSimilarity * 14).rounded())
        }
        let termGrams = Set(characterNGrams(term, size: 2))
        if termGrams.count >= 2 {
            let overlap = termGrams.intersection(section.searchTokens).count
            if Double(overlap) / Double(termGrams.count) >= 0.67 {
                return 10 + overlap
            }
        }
        return 0
    }

    private static func naturalLanguageTokens(_ value: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = value
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: value.startIndex..<value.endIndex) { range, _ in
            let token = normalize(String(value[range]))
            if !token.isEmpty {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }

    private static func characterNGrams(_ value: String, size: Int) -> [String] {
        let characters = Array(value)
        guard characters.count >= size else {
            return [value].filter { !$0.isEmpty }
        }
        return (0...(characters.count - size)).map { index in
            String(characters[index..<(index + size)])
        }
    }

    private static func characterNGrams(_ value: String, sizes: ClosedRange<Int>) -> [String] {
        sizes.flatMap { characterNGrams(value, size: $0) }
    }

    private static func fuzzySimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }
        if lhs == rhs {
            return 1
        }
        let distance = editDistance(lhs, rhs)
        return 1 - (Double(distance) / Double(max(lhs.count, rhs.count)))
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)
        guard !lhs.isEmpty else {
            return rhs.count
        }
        guard !rhs.isEmpty else {
            return lhs.count
        }
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

    private static func phraseSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard lhs.count >= 3, rhs.count >= 3 else {
            return 0
        }
        let lhsGrams = Set(characterNGrams(lhs, size: 2))
        let rhsGrams = Set(characterNGrams(rhs, size: 2))
        guard !lhsGrams.isEmpty, !rhsGrams.isEmpty else {
            return 0
        }
        let overlap = lhsGrams.intersection(rhsGrams).count
        return Double(overlap * 2) / Double(lhsGrams.count + rhsGrams.count)
    }
}

private extension String {
    var containsHangul: Bool {
        unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(Int(scalar.value))
        }
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func searchSnippet(around term: String, limit: Int = 96) -> String {
        let trimmed = trimmedSearchSnippet(limit: 400)
        guard let range = trimmed.range(
            of: term,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        ) else {
            return trimmed.trimmedSearchSnippet(limit: limit)
        }

        let leadingCount = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
        let startOffset = max(0, leadingCount - 28)
        let start = trimmed.index(trimmed.startIndex, offsetBy: startOffset)
        let end = trimmed.index(start, offsetBy: min(limit, trimmed.distance(from: start, to: trimmed.endIndex)))
        let snippet = String(trimmed[start..<end])
        return "\(start == trimmed.startIndex ? "" : "...")\(snippet)\(end == trimmed.endIndex ? "" : "...")"
    }

    func trimmedSearchSnippet(limit: Int = 96) -> String {
        let oneLine = components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard oneLine.count > limit else {
            return oneLine
        }
        return String(oneLine.prefix(limit - 1)) + "…"
    }
}
