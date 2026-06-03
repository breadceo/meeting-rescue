import Foundation

public enum PersonalWorkflowAnalyzer {
    public static func snapshot(
        currentMeetingID: String,
        metadata: MeetingMetadata,
        state: MeetingAnalysisState,
        historySources: [ActionLedgerMeetingSource]
    ) -> PersonalWorkflowSnapshot {
        guard let latestSnapshot = state.latestSnapshot else {
            return PersonalWorkflowSnapshot()
        }

        let coachCards = decisionCoachCards(for: latestSnapshot)
        let readinessWarnings = shareReadinessWarnings(for: latestSnapshot, coachCards: coachCards)
        let currentSource = ActionLedgerMeetingSource(
            meetingID: currentMeetingID,
            sourceFileName: currentMeetingID,
            metadata: metadata,
            snapshot: latestSnapshot
        )
        let ledgerSources = ([currentSource] + historySources).deduplicatedByMeetingID()
        let carryOverCurrent = CarryOverMeetingSource(
            meetingID: currentMeetingID,
            sourceFileName: currentMeetingID,
            metadata: metadata,
            snapshot: latestSnapshot
        )
        let carryOverPrevious = historySources.map {
            CarryOverMeetingSource(
                meetingID: $0.meetingID,
                sourceFileName: $0.sourceFileName,
                metadata: $0.metadata,
                snapshot: $0.snapshot
            )
        }

        return PersonalWorkflowSnapshot(
            coachCards: coachCards,
            readinessWarnings: readinessWarnings,
            actionLedgerItems: actionLedgerItems(from: ledgerSources),
            carryOverCandidates: openQuestionCarryOverCandidates(
                current: carryOverCurrent,
                previous: carryOverPrevious,
                dismissedIDs: state.dismissedCarryOverQuestionIDs,
                resolvedIDs: state.resolvedCarryOverQuestionIDs
            )
        )
    }

    public static func decisionCoachCards(for snapshot: AnalysisSnapshot) -> [DecisionCoachCard] {
        var cards: [DecisionCoachCard] = []
        let visibleDecisions = snapshot.decisionCandidates.filter { $0.status != .deleted }
        let candidateDecisions = visibleDecisions.filter { $0.status == .candidate }
        let confirmedDecisions = visibleDecisions.filter { $0.status == .confirmed }
        let visibleActions = snapshot.actionItemCandidates.filter { $0.status != .deleted }

        if let first = candidateDecisions.first, confirmedDecisions.isEmpty {
            cards.append(
                DecisionCoachCard(
                    id: "coach:unconfirmed-decision:\(first.id)",
                    kind: .unconfirmedDecision,
                    severity: .warning,
                    title: "결정 후보 확인 필요",
                    stuckPoint: "결정 후보는 있지만 확정된 결정이 없습니다.",
                    minimumDecision: first.text,
                    options: candidateDecisions.prefix(3).map(\.text),
                    missingInfo: ["이 후보를 확정할 사람", "확정 여부"],
                    nextQuestion: "지금 확정할 결정은 무엇인가요?",
                    evidence: evidence(from: first)
                )
            )
        }

        if let action = visibleActions.first(where: { normalized($0.assignee).isEmpty }) {
            cards.append(
                DecisionCoachCard(
                    id: "coach:missing-owner:\(action.id)",
                    kind: .missingOwner,
                    severity: .warning,
                    title: "Owner가 없는 action",
                    stuckPoint: "액션은 잡혔지만 실행 담당자가 없습니다.",
                    minimumDecision: "\(action.task)의 owner 지정",
                    missingInfo: ["담당자"],
                    nextQuestion: "이 액션의 owner는 누구인가요?",
                    evidence: evidence(from: action)
                )
            )
        }

        if snapshot.meetingType == .decision && !hasDecisionCriteria(snapshot) {
            cards.append(
                DecisionCoachCard(
                    id: "coach:missing-criteria",
                    kind: .missingCriteria,
                    severity: .info,
                    title: "판단 기준 보강",
                    stuckPoint: "결정 논의지만 비용, 영향, 리스크, 우선순위 같은 판단 기준이 명확하지 않습니다.",
                    minimumDecision: "선택지를 평가할 기준 확정",
                    missingInfo: ["판단 기준", "선택지별 trade-off"],
                    nextQuestion: "이 결정에서 가장 중요한 기준은 무엇인가요?"
                )
            )
        }

        if let question = openQuestionItems(from: snapshot).first {
            cards.append(
                DecisionCoachCard(
                    id: "coach:open-question:\(stableKey(question.text))",
                    kind: .openQuestion,
                    severity: .info,
                    title: "열린 질문 정리",
                    stuckPoint: "회의 공유 전에 답이 필요한 질문이 남아 있습니다.",
                    minimumDecision: question.text,
                    missingInfo: ["답변 또는 다음 확인 owner"],
                    nextQuestion: "이 질문은 지금 답할 수 있나요, 아니면 follow-up owner를 정할까요?",
                    evidence: question.evidence
                )
            )
        }

        let recentTopicTitles = Set(snapshot.topicTimeline.suffix(4).map { stableKey($0.title) }.filter { !$0.isEmpty })
        if recentTopicTitles.count >= 3 && confirmedDecisions.isEmpty {
            cards.append(
                DecisionCoachCard(
                    id: "coach:mixed-scope",
                    kind: .mixedScope,
                    severity: .info,
                    title: "Scope가 섞이는 중",
                    stuckPoint: "최근 흐름이 여러 주제로 이동했지만 확정된 결정은 없습니다.",
                    minimumDecision: "이번 회의에서 끝낼 논점 1개 선택",
                    missingInfo: ["이번 회의의 종료 조건"],
                    nextQuestion: "지금 결정할 최소 논점 하나만 고르면 무엇인가요?"
                )
            )
        }

        return cards
    }

    public static func shareReadinessWarnings(
        for snapshot: AnalysisSnapshot,
        coachCards: [DecisionCoachCard]
    ) -> [ShareReadinessWarning] {
        var warnings: [ShareReadinessWarning] = []

        if snapshot.meetingSummary.isEmpty {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:empty-summary",
                    kind: .emptySummary,
                    severity: .warning,
                    title: "회의 요약이 비어 있음",
                    detail: "공유 전에 전체 회의 요약을 한 번 더 생성하거나 수동으로 정리하세요."
                )
            )
        }

        for decision in snapshot.decisionCandidates where decision.status == .candidate {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:unconfirmed-decision:\(decision.id)",
                    kind: .unconfirmedDecision,
                    severity: .warning,
                    title: "확정되지 않은 결정 후보",
                    detail: decision.text,
                    relatedID: decision.id
                )
            )
        }

        for decision in snapshot.decisionCandidates where decision.status == .confirmed && normalized(decision.evidenceTimestamp).isEmpty {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:weak-decision-evidence:\(decision.id)",
                    kind: .weakDecisionEvidence,
                    severity: .warning,
                    title: "결정 근거 timestamp 없음",
                    detail: decision.text,
                    relatedID: decision.id
                )
            )
        }

        for action in snapshot.actionItemCandidates where action.status == .candidate {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:unconfirmed-action:\(action.id)",
                    kind: .unconfirmedAction,
                    severity: .info,
                    title: "확정되지 않은 action 후보",
                    detail: action.task,
                    relatedID: action.id
                )
            )
        }

        for action in snapshot.actionItemCandidates where action.status == .confirmed {
            if normalized(action.assignee).isEmpty {
                warnings.append(
                    ShareReadinessWarning(
                        id: "readiness:missing-action-owner:\(action.id)",
                        kind: .missingActionOwner,
                        severity: .warning,
                        title: "담당자 없는 action",
                        detail: action.task,
                        relatedID: action.id
                    )
                )
            }
            if normalized(action.deadline).isEmpty {
                warnings.append(
                    ShareReadinessWarning(
                        id: "readiness:missing-action-deadline:\(action.id)",
                        kind: .missingActionDeadline,
                        severity: .info,
                        title: "기한 없는 action",
                        detail: action.task,
                        relatedID: action.id
                    )
                )
            }
        }

        if !openQuestionItems(from: snapshot).isEmpty {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:open-question",
                    kind: .openQuestion,
                    severity: .info,
                    title: "열린 질문 남음",
                    detail: "공유문에 열린 질문 또는 follow-up owner를 포함하세요."
                )
            )
        }

        for card in coachCards where card.severity == .warning {
            warnings.append(
                ShareReadinessWarning(
                    id: "readiness:coach:\(card.id)",
                    kind: .unresolvedDecisionCoachCard,
                    severity: .warning,
                    title: card.title,
                    detail: card.minimumDecision,
                    relatedID: card.id
                )
            )
        }

        return warnings.deduplicatedByID()
    }

    public static func actionLedgerItems(from sources: [ActionLedgerMeetingSource]) -> [ActionLedgerItem] {
        sources.flatMap { source in
            source.snapshot.actionItemCandidates
                .filter { $0.status == .confirmed }
                .map { action in
                    ActionLedgerItem(
                        id: "\(source.meetingID):\(action.id)",
                        task: action.task,
                        assignee: action.assignee,
                        deadline: action.deadline,
                        meetingID: source.meetingID,
                        meetingTitle: source.metadata.displayTitle,
                        sourceFileName: source.sourceFileName,
                        evidenceTimestamp: action.evidenceTimestamp,
                        speaker: action.speaker
                    )
                }
        }
        .sorted { lhs, rhs in
            if normalized(lhs.deadline) == normalized(rhs.deadline) {
                return lhs.meetingTitle.localizedStandardCompare(rhs.meetingTitle) == .orderedAscending
            }
            if normalized(lhs.deadline).isEmpty {
                return false
            }
            if normalized(rhs.deadline).isEmpty {
                return true
            }
            return normalized(lhs.deadline) < normalized(rhs.deadline)
        }
    }

    public static func openQuestionCarryOverCandidates(
        current: CarryOverMeetingSource,
        previous: [CarryOverMeetingSource],
        dismissedIDs: Set<String>,
        resolvedIDs: Set<String>
    ) -> [OpenQuestionCarryOverCandidate] {
        previous
            .filter { $0.meetingID != current.meetingID }
            .compactMap { source -> (CarryOverMeetingSource, String)? in
                guard let reason = matchReason(current: current, previous: source) else {
                    return nil
                }
                return (source, reason)
            }
            .flatMap { source, reason in
                openQuestionItems(from: source.snapshot).map { item in
                    OpenQuestionCarryOverCandidate(
                        id: "carry-over:\(source.meetingID):\(stableKey(item.text))",
                        question: item.text,
                        sourceMeetingID: source.meetingID,
                        sourceTitle: source.metadata.displayTitle,
                        sourceFileName: source.sourceFileName,
                        reason: reason,
                        evidence: item.evidence
                    )
                }
            }
            .filter { !dismissedIDs.contains($0.id) && !resolvedIDs.contains($0.id) }
            .deduplicatedByID()
    }

    private static func evidence(from decision: DecisionCandidate) -> [EvidenceReference] {
        guard !normalized(decision.evidenceTimestamp).isEmpty else {
            return []
        }
        return [EvidenceReference(timestamp: decision.evidenceTimestamp, speaker: decision.speaker, excerpt: decision.text)]
    }

    private static func evidence(from action: ActionItemCandidate) -> [EvidenceReference] {
        guard !normalized(action.evidenceTimestamp).isEmpty else {
            return []
        }
        return [EvidenceReference(timestamp: action.evidenceTimestamp, speaker: action.speaker, excerpt: action.task)]
    }

    private static func openQuestionItems(from snapshot: AnalysisSnapshot) -> [MeetingSummaryItem] {
        let summaryQuestions = snapshot.meetingSummary.openQuestions
        let currentQuestions = snapshot.currentIssue.openQuestions.map {
            MeetingSummaryItem(id: "current:\(stableKey($0))", text: $0)
        }
        return (summaryQuestions + currentQuestions).filter { !normalized($0.text).isEmpty }
    }

    private static func hasDecisionCriteria(_ snapshot: AnalysisSnapshot) -> Bool {
        let text = [
            snapshot.meetingSummary.overview,
            snapshot.currentIssue.summary,
            snapshot.risksOrNotes.joined(separator: " "),
            snapshot.decisionCandidates.map(\.text).joined(separator: " ")
        ].joined(separator: " ").lowercased()
        let criteriaTokens = ["기준", "근거", "비용", "영향", "리스크", "우선순위", "criteria", "impact", "risk", "cost"]
        return criteriaTokens.contains { text.contains($0) }
    }

    private static func matchReason(current: CarryOverMeetingSource, previous: CarryOverMeetingSource) -> String? {
        let currentRoom = normalized(current.metadata.room)
        let previousRoom = normalized(previous.metadata.room)
        if !currentRoom.isEmpty && currentRoom == previousRoom {
            return "same room"
        }

        let sharedParticipants = Set(current.metadata.participants.map(normalized))
            .intersection(Set(previous.metadata.participants.map(normalized)))
            .filter { !$0.isEmpty }
        if !sharedParticipants.isEmpty {
            return "shared participant"
        }

        let currentTokens = topicTokens(from: current)
        let previousTokens = topicTokens(from: previous)
        if !currentTokens.intersection(previousTokens).isEmpty {
            return "topic match"
        }

        return nil
    }

    private static func topicTokens(from source: CarryOverMeetingSource) -> Set<String> {
        let text = [
            source.metadata.displayTitle,
            source.snapshot.meetingSummary.overview,
            source.snapshot.currentIssue.summary,
            source.snapshot.topicTimeline.map(\.title).joined(separator: " ")
        ].joined(separator: " ")
        return Set(text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalized)
            .filter { $0.count >= 3 })
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func stableKey(_ value: String) -> String {
        normalized(value)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private extension Array where Element == ShareReadinessWarning {
    func deduplicatedByID() -> [ShareReadinessWarning] {
        var seen: Set<String> = []
        var values: [ShareReadinessWarning] = []
        for item in self where seen.insert(item.id).inserted {
            values.append(item)
        }
        return values
    }
}

private extension Array where Element == OpenQuestionCarryOverCandidate {
    func deduplicatedByID() -> [OpenQuestionCarryOverCandidate] {
        var seen: Set<String> = []
        var values: [OpenQuestionCarryOverCandidate] = []
        for item in self where seen.insert(item.id).inserted {
            values.append(item)
        }
        return values
    }
}

private extension Array where Element == ActionLedgerMeetingSource {
    func deduplicatedByMeetingID() -> [ActionLedgerMeetingSource] {
        var seen: Set<String> = []
        var values: [ActionLedgerMeetingSource] = []
        for item in self where seen.insert(item.meetingID).inserted {
            values.append(item)
        }
        return values
    }
}
