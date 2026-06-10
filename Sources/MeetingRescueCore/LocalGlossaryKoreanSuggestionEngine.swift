import Foundation

public enum LocalGlossaryKoreanSuggestionEngine {
    private static let maxCandidatesPerBucket = 40
    private static let maxComparisonCandidates = 900
    private static let minimumOccurrenceSupportForPairing = 2

    public static func suggestions(
        from documents: [LocalGlossarySourceDocument],
        existingState: LocalGlossaryState,
        maxSuggestions: Int = 8
    ) -> [LocalGlossarySuggestion] {
        let acceptedValues = Set(existingState.enabledTerms.flatMap(\.allMatchValues).map(MeetingHistorySearch.compactNormalize))
        let occurrences = collectOccurrences(from: documents, acceptedValues: acceptedValues)
        let candidates = summarizeCandidates(occurrences)
        let pairs = candidatePairs(from: candidates)
        let clusters = clusters(from: pairs)
        return clusters.compactMap { cluster in
            suggestion(from: cluster, pairs: pairs, dismissedIDs: existingState.dismissedSuggestionIDs)
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
                                contextOverlap: contextOverlap
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
        dismissedIDs: Set<String>
    ) -> LocalGlossarySuggestion? {
        let aliases = cluster
            .map(\.display)
            .normalizedKoreanSuggestionAliases()
        guard aliases.count >= 2 else {
            return nil
        }
        let id = "suggestion:ko:\(cluster.map(\.compact).sorted().joined(separator: "|"))"
        guard !dismissedIDs.contains(id) else {
            return nil
        }
        let compactValues = Set(cluster.map(\.compact))
        let confidence = pairs
            .filter { compactValues.contains($0.lhs.compact) && compactValues.contains($0.rhs.compact) }
            .map(\.score)
            .max() ?? 0.80
        let occurrences = cluster.flatMap(\.occurrences)
        let meetingIDs = Set(occurrences.map(\.documentID))
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
            confidence: confidence
        )
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
        return true
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
    "정도", "방식", "방향", "상황", "기능", "작업", "일정", "시간"
]

private let koreanGenericSuffixes: [String] = [
    "같아", "같고", "같은", "같긴", "같기", "같아서", "싶어", "싶기", "싶긴", "싶어서",
    "합니다", "했습니다", "있습니다", "나왔습니다", "나왔고", "필요하다", "필요하다고",
    "필요할", "필요한", "되는데", "되는지", "좋겠다", "좋겠다고", "좋을", "주시면",
    "주세요", "만들어", "만들어서", "하는지", "있어서", "있어", "봅니다"
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
