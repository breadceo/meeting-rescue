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
    case glossary
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
            return "현재 논점"
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
        case .glossary:
            return "용어 사전"
        case .rawTranscript:
            return "원문"
        }
    }
}

public enum MeetingHistorySearchTokenization: Equatable, Sendable {
    case full
    case fast
}

public struct MeetingHistorySearchSection: Equatable, Sendable {
    public var field: MeetingHistorySearchField
    public var text: String
    public var normalizedText: String
    public var compactNormalizedText: String
    public var searchTokens: Set<String>
    public var tokenization: MeetingHistorySearchTokenization
    public var weight: Int
    public var timestamp: String?

    public init(
        field: MeetingHistorySearchField,
        text: String,
        weight: Int,
        timestamp: String? = nil,
        tokenization: MeetingHistorySearchTokenization = .full
    ) {
        self.field = field
        self.text = text
        self.normalizedText = MeetingHistorySearch.normalize(text)
        self.compactNormalizedText = MeetingHistorySearch.compactNormalize(text)
        self.searchTokens = MeetingHistorySearch.expandedTokens(text, tokenization: tokenization)
        self.tokenization = tokenization
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
    public static let semanticProviderName = "local-semantic-v2"

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
        tokenize(query, tokenization: .full)
    }

    public static func tokenize(
        _ query: String,
        tokenization: MeetingHistorySearchTokenization
    ) -> [String] {
        let normalizedTerms = normalize(query)
            .split { character in
                character.isWhitespace || character.isPunctuation || character.isSymbol
            }
            .map(String.init)
            .filter { !$0.isEmpty }
        let naturalTerms = tokenization == .full ? naturalLanguageTokens(query) : []
        return Array(Set(normalizedTerms + naturalTerms)).sorted()
    }

    public static func expandedTokens(_ value: String) -> Set<String> {
        expandedTokens(value, tokenization: .full)
    }

    public static func expandedTokens(
        _ value: String,
        tokenization: MeetingHistorySearchTokenization
    ) -> Set<String> {
        let baseTokens = tokenize(value, tokenization: tokenization)
        let grams = baseTokens.flatMap { token in
            token.count >= 3 && token.containsHangul ? characterNGrams(token, sizes: 2...4) : []
        }
        return Set(baseTokens + grams)
    }

    public static func indexText(for value: String) -> String {
        indexText(for: value, tokenization: .full)
    }

    public static func indexText(
        for value: String,
        tokenization: MeetingHistorySearchTokenization
    ) -> String {
        let compact = compactNormalize(value)
        var values = [value, normalize(value), compact]
        values.append(contentsOf: expandedTokens(value, tokenization: tokenization))
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

    public static func semanticVectorString(for value: String) -> String {
        semanticVectorString(for: value, tokenization: .full)
    }

    public static func semanticVectorString(
        for value: String,
        tokenization: MeetingHistorySearchTokenization
    ) -> String {
        let terms = semanticTerms(for: value, tokenization: tokenization)
        guard !terms.isEmpty else {
            return ""
        }
        var buckets: [Int: Double] = [:]
        for term in terms {
            let bucket = stableHash(term) % semanticDimensions
            buckets[bucket, default: 0] += semanticWeight(for: term)
        }
        let magnitude = sqrt(buckets.values.reduce(0) { $0 + ($1 * $1) })
        guard magnitude > 0 else {
            return ""
        }
        return buckets
            .map { key, value in (key, value / magnitude) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0):\(String(format: "%.5f", $0.1))" }
            .joined(separator: ",")
    }

    public static func semanticScore(query: String, vectorString: String) -> Int {
        semanticScore(queryVector: semanticVector(for: query), vectorString: vectorString)
    }

    public static func semanticScore(queryVector: [Int: Double], vectorString: String) -> Int {
        let similarity = semanticSimilarity(lhsVector: queryVector, rhs: vectorString)
        guard similarity >= 0.12 else {
            return 0
        }
        return Int((similarity * 140).rounded())
    }

    public static func semanticVector(for value: String) -> [Int: Double] {
        parseSemanticVector(semanticVectorString(for: value))
    }

    public static func semanticSimilarity(lhs: String, rhs: String) -> Double {
        semanticSimilarity(lhsVector: parseSemanticVector(lhs), rhs: rhs)
    }

    public static func semanticSimilarity(lhsVector: [Int: Double], rhs: String) -> Double {
        let rhsVector = parseSemanticVector(rhs)
        guard !lhsVector.isEmpty, !rhsVector.isEmpty else {
            return 0
        }
        if lhsVector.count <= rhsVector.count {
            return lhsVector.reduce(0) { partial, element in
                partial + (element.value * (rhsVector[element.key] ?? 0))
            }
        }
        return rhsVector.reduce(0) { partial, element in
            partial + (element.value * (lhsVector[element.key] ?? 0))
        }
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

    private static func semanticTerms(
        for value: String,
        tokenization: MeetingHistorySearchTokenization
    ) -> [String] {
        let normalized = normalize(value)
        let compact = compactNormalize(value)
        var terms = Set(expandedTokens(value, tokenization: tokenization))
        if compact.count >= 3 {
            terms.formUnion(characterNGrams(compact, sizes: 2...4))
        }
        for concept in semanticConcepts where concept.matches(normalized: normalized, compact: compact, tokens: terms) {
            terms.formUnion(concept.aliases)
        }
        return terms
            .map(normalize)
            .filter { $0.count >= 2 }
    }

    private static func semanticWeight(for term: String) -> Double {
        term.count <= 2 ? 0.7 : 1.0
    }

    private static func parseSemanticVector(_ value: String) -> [Int: Double] {
        var vector: [Int: Double] = [:]
        for component in value.split(separator: ",") {
            let parts = component.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let index = Int(parts[0]),
                  let weight = Double(parts[1]) else {
                continue
            }
            vector[index] = weight
        }
        return vector
    }

    private static func stableHash(_ value: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(Int.max))
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

private let semanticDimensions = 256

private struct SemanticConcept {
    let aliases: Set<String>

    func matches(normalized: String, compact: String, tokens: Set<String>) -> Bool {
        aliases.contains { alias in
            let normalizedAlias = MeetingHistorySearch.normalize(alias)
            let compactAlias = MeetingHistorySearch.compactNormalize(alias)
            return tokens.contains(normalizedAlias)
                || normalized.contains(normalizedAlias)
                || (!compactAlias.isEmpty && compact.contains(compactAlias))
        }
    }
}

private let semanticConcepts: [SemanticConcept] = [
    SemanticConcept(aliases: ["결정", "확정", "의사결정", "합의", "정했다", "결론", "decision"]),
    SemanticConcept(aliases: ["액션", "할일", "후속", "담당", "todo", "action", "followup"]),
    SemanticConcept(aliases: ["예산", "비용", "금액", "가격", "단가", "budget", "cost", "price"]),
    SemanticConcept(aliases: ["축소", "감소", "절감", "줄이다", "줄인", "낮추다", "cut", "reduce"]),
    SemanticConcept(aliases: ["증가", "확대", "늘리다", "높이다", "increase", "expand"]),
    SemanticConcept(aliases: ["지연", "느림", "버벅", "성능", "latency", "slow", "performance"]),
    SemanticConcept(aliases: ["검색", "탐색", "찾기", "search", "find"]),
    SemanticConcept(aliases: ["업데이트", "배포", "릴리즈", "release", "deploy", "update"]),
    SemanticConcept(aliases: ["회의록", "원문", "transcript", "script", "recording"]),
    SemanticConcept(aliases: ["마케팅", "브랜드", "캠페인", "광고", "marketing", "brand", "campaign"])
]

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
