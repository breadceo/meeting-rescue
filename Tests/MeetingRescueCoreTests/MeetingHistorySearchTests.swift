import Testing
@testable import MeetingRescueCore

@Suite("Meeting history search")
struct MeetingHistorySearchTests {
    @Test("perspective alignment field has display name")
    func perspectiveAlignmentFieldDisplayName() {
        #expect(MeetingHistorySearchField.perspectiveAlignment.displayName == "관점 정렬")
    }

    @Test("perspective alignment search section includes context and first evidence timestamp")
    func perspectiveAlignmentSearchSectionIncludesContext() {
        let alignment = PerspectiveAlignment(
            id: "alignment-release-scope",
            topic: "실험 기능 릴리즈 범위",
            axis: "속도와 안정성의 균형",
            sharedGround: "이번 주 안에 범위를 정해야 한다.",
            nextQuestion: "오늘 결정할 최소 릴리즈 범위는 어디까지인가?",
            perspectives: [
                PerspectivePosition(
                    speaker: "Alex",
                    summary: "이번 릴리즈에 포함해야 한다.",
                    reasoning: "피드백을 빨리 받아야 한다.",
                    evidence: [
                        EvidenceReference(
                            timestamp: "00:30",
                            speaker: "Alex",
                            excerpt: "이번에 넣죠."
                        )
                    ]
                ),
                PerspectivePosition(
                    speaker: "Blair",
                    summary: "다음 릴리즈로 미뤄야 한다.",
                    reasoning: "QA 시간이 부족하다.",
                    evidence: [
                        EvidenceReference(
                            timestamp: "00:40",
                            speaker: "Blair",
                            excerpt: "QA가 부족해요."
                        )
                    ]
                )
            ]
        )

        let section = MeetingHistorySearchSection.perspectiveAlignment(alignment)

        #expect(section.field == .perspectiveAlignment)
        #expect(section.weight == 76)
        #expect(section.timestamp == "00:30")
        #expect(section.text.contains("실험 기능 릴리즈 범위"))
        #expect(section.text.contains("속도와 안정성의 균형"))
        #expect(section.text.contains("이번 주 안에 범위를 정해야 한다."))
        #expect(section.text.contains("오늘 결정할 최소 릴리즈 범위는 어디까지인가?"))
        #expect(section.text.contains("Alex"))
        #expect(section.text.contains("이번 릴리즈에 포함해야 한다."))
        #expect(section.text.contains("피드백을 빨리 받아야 한다."))
        #expect(section.text.contains("Blair"))
        #expect(section.text.contains("다음 릴리즈로 미뤄야 한다."))
        #expect(section.text.contains("QA 시간이 부족하다."))
    }

    @Test("confirmed decision matches outrank raw transcript matches")
    func confirmedDecisionOutranksRawTranscript() {
        let decisionSections = [
            MeetingHistorySearchSection(field: .confirmedDecision, text: "가격 정책은 6월 파일럿 이후 고정한다", weight: 96, timestamp: "04:13"),
            MeetingHistorySearchSection(field: .rawTranscript, text: "가격 이야기가 잠깐 나왔다", weight: 24, timestamp: "02:01")
        ]
        let rawOnlySections = [
            MeetingHistorySearchSection(field: .rawTranscript, text: "가격 정책은 아직 논의 중이다", weight: 24, timestamp: "02:01")
        ]

        let decisionMatch = MeetingHistorySearch.match(sections: decisionSections, query: "가격 정책")
        let rawMatch = MeetingHistorySearch.match(sections: rawOnlySections, query: "가격 정책")

        #expect(decisionMatch?.field == .confirmedDecision)
        #expect((decisionMatch?.score ?? 0) > (rawMatch?.score ?? 0))
        #expect(decisionMatch?.displayText.contains("[04:13] 확정 결정:") == true)
    }

    @Test("query terms can match across participant and decision fields")
    func multiTermQueryMatchesAcrossFields() {
        let sections = [
            MeetingHistorySearchSection(field: .participant, text: "Alex Mina", weight: 84),
            MeetingHistorySearchSection(field: .decision, text: "검색 결과에는 match snippet을 보여준다", weight: 68, timestamp: "12:10")
        ]

        let match = MeetingHistorySearch.match(sections: sections, query: "Alex snippet")

        #expect(match != nil)
        #expect(match?.displayText.contains("snippet") == true || match?.displayText.contains("Alex") == true)
    }

    @Test("short Korean substring query matches without whitespace tokenization")
    func shortKoreanSubstringQueryMatches() {
        let sections = [
            MeetingHistorySearchSection(field: .topic, text: "검색품질 개선 방향을 논의했다", weight: 58, timestamp: "00:30")
        ]

        let match = MeetingHistorySearch.match(sections: sections, query: "품질")

        #expect(match?.field == .topic)
        #expect(match?.displayText.contains("품질") == true)
    }

    @Test("spacing-insensitive Korean phrase query matches compound words")
    func spacingInsensitiveKoreanPhraseMatches() {
        let sections = [
            MeetingHistorySearchSection(field: .topic, text: "검색품질 개선 방향을 논의했다", weight: 58, timestamp: "00:30")
        ]

        let match = MeetingHistorySearch.match(sections: sections, query: "검색 품질")

        #expect(match?.field == .topic)
        #expect(match?.timestamp == "00:30")
    }

    @Test("compound team names match spaced queries and keep raw transcript anchor")
    func compoundTeamNameMatchesSpacedQuery() {
        let sections = [
            MeetingHistorySearchSection(field: .currentIssue, text: "마케팅 계정 확인이 필요하다", weight: 80),
            MeetingHistorySearchSection(field: .rawTranscript, text: "[09:04] Casey Lee: 마케팅팀이랑 소통해서 확인하도록 하겠습니다.", weight: 24, timestamp: "09:04")
        ]

        let anchorMatch = MeetingHistorySearch.timestampedMatch(sections: sections, query: "마케팅 팀")

        #expect(anchorMatch?.field == .rawTranscript)
        #expect(anchorMatch?.timestamp == "09:04")
    }

    @Test("raw transcript fast tokenization keeps compact Korean phrase anchors")
    func rawTranscriptFastTokenizationKeepsCompactKoreanPhraseAnchors() {
        let sections = [
            MeetingHistorySearchSection(
                field: .rawTranscript,
                text: "[09:04] Casey Lee: 마케팅팀이랑 소통해서 확인하도록 하겠습니다.",
                weight: 24,
                timestamp: "09:04",
                tokenization: .fast
            )
        ]

        let anchorMatch = MeetingHistorySearch.timestampedMatch(sections: sections, query: "마케팅 팀")

        #expect(anchorMatch?.field == .rawTranscript)
        #expect(anchorMatch?.timestamp == "09:04")
    }

    @Test("fast tokenization keeps Hangul grams without natural language tokens")
    func fastTokenizationKeepsHangulGramsWithoutNaturalLanguageTokens() {
        let fastTokens = MeetingHistorySearch.tokenize("마케팅팀이랑", tokenization: .fast)
        let expandedTokens = MeetingHistorySearch.expandedTokens("마케팅팀이랑", tokenization: .fast)

        #expect(fastTokens == ["마케팅팀이랑"])
        #expect(expandedTokens.contains("마케팅팀이랑"))
        #expect(expandedTokens.contains("마케"))
        #expect(expandedTokens.contains("케팅팀"))
    }

    @Test("index text can reuse precomputed section tokens")
    func indexTextCanReusePrecomputedSectionTokens() {
        let section = MeetingHistorySearchSection(
            field: .rawTranscript,
            text: "[09:04] Casey Lee: 마케팅팀이랑 소통해서 확인하도록 하겠습니다.",
            weight: 24,
            timestamp: "09:04",
            tokenization: .fast
        )

        let indexedText = MeetingHistorySearch.indexText(for: section)

        #expect(indexedText.contains(section.normalizedText))
        #expect(indexedText.contains(section.compactNormalizedText))
        #expect(indexedText.contains("마케팅팀이랑"))
        #expect(indexedText.contains("케팅팀"))
    }

    @Test("minor typo in English query can still match local fuzzy tokens")
    func fuzzyEnglishTypoMatches() {
        let sections = [
            MeetingHistorySearchSection(field: .topic, text: "Meeting intelligence latency 개선", weight: 58, timestamp: "03:20"),
            MeetingHistorySearchSection(field: .rawTranscript, text: "[03:10] Alex: unrelated latency note", weight: 24, timestamp: "03:10")
        ]

        let match = MeetingHistorySearch.match(sections: sections, query: "meeting intellignece")

        #expect(match?.field == .topic)
        #expect(match?.timestamp == "03:20")
    }

    @Test("timestamped match can be used as navigation anchor when best match has no timestamp")
    func timestampedMatchProvidesNavigationAnchor() {
        let sections = [
            MeetingHistorySearchSection(field: .currentIssue, text: "주간 회의에서 마케팅 계정 확인이 현재 이슈로 정리되었다", weight: 80),
            MeetingHistorySearchSection(field: .rawTranscript, text: "[09:04] Casey Lee: 마케팅팀이랑 소통해서 확인하도록 하겠습니다.", weight: 24, timestamp: "09:04")
        ]

        let displayMatch = MeetingHistorySearch.match(sections: sections, query: "마케팅")
        let anchorMatch = MeetingHistorySearch.timestampedMatch(sections: sections, query: "마케팅")

        #expect(displayMatch?.field == .currentIssue)
        #expect(displayMatch?.timestamp == nil)
        #expect(anchorMatch?.field == .rawTranscript)
        #expect(anchorMatch?.timestamp == "09:04")
    }

    @Test("local semantic vector connects related meeting terms without exact keyword")
    func localSemanticVectorMatchesRelatedTerms() {
        let vector = MeetingHistorySearch.semanticVectorString(
            for: "브랜드 캠페인 비용을 다음 분기에는 축소하기로 결정했다"
        )

        let relatedScore = MeetingHistorySearch.semanticScore(
            query: "마케팅 예산 줄인 결정",
            vectorString: vector
        )
        let unrelatedScore = MeetingHistorySearch.semanticScore(
            query: "회의록 검색 성능",
            vectorString: vector
        )

        #expect(relatedScore > 0)
        #expect(relatedScore > unrelatedScore)
    }

    @Test("semantic vector serialization is deterministic")
    func semanticVectorSerializationIsDeterministic() {
        let first = MeetingHistorySearch.semanticVectorString(for: "검색 품질 개선")
        let second = MeetingHistorySearch.semanticVectorString(for: "검색 품질 개선")

        #expect(!first.isEmpty)
        #expect(first == second)
        #expect(MeetingHistorySearch.semanticSimilarity(lhs: first, rhs: second) > 0.99)
    }

    @Test("glossary field lets canonical query match alias-only history")
    func glossaryFieldMatchesCanonicalQuery() {
        let sections = [
            MeetingHistorySearchSection(field: .rawTranscript, text: "[03:12] Alex: jax workflow를 봤다", weight: 24, timestamp: "03:12"),
            MeetingHistorySearchSection(field: .glossary, text: "zax jax jecks", weight: 66)
        ]

        let match = MeetingHistorySearch.match(sections: sections, query: "zax")

        #expect(match?.field == .glossary)
    }
}
