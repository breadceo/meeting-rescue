import MeetingRescueCore
import AppKit
import SwiftUI

private enum IntelligenceMode: String, CaseIterable, Identifiable {
    case overview = "요약"
    case timeline = "흐름"
    case candidates = "후보"
    case workflow = "워크플로우"
    case context = "컨텍스트"

    var id: String { rawValue }

    var laneID: String {
        switch self {
        case .overview:
            return "overview"
        case .timeline:
            return "timeline"
        case .candidates:
            return "candidates"
        case .workflow:
            return "workflow"
        case .context:
            return "context"
        }
    }

    static var visibleModes: [IntelligenceMode] {
        allCases.filter { MeetingIntelligenceFeatureGate.isVisibleLane($0.laneID) }
    }
}

private enum EditingCandidateKind {
    case decision
    case action
}

private struct EditingCandidate: Equatable {
    var kind: EditingCandidateKind
    var id: String
}

private enum AdaptivePane: CaseIterable, Hashable {
    case meetings
    case intelligence

    var title: String {
        switch self {
        case .meetings:
            return "Meetings"
        case .intelligence:
            return "Intelligence"
        }
    }

    var systemImage: String {
        switch self {
        case .meetings:
            return "sidebar.left"
        case .intelligence:
            return "sparkles"
        }
    }

}

private enum AdaptiveLayoutMode {
    case wide
    case split
    case rawPrimary
    case compactOverlay

    init(width: CGFloat) {
        if width >= 1120 {
            self = .wide
        } else if width >= 1040 {
            self = .split
        } else if width >= 820 {
            self = .rawPrimary
        } else {
            self = .compactOverlay
        }
    }

    var usesOverlayDrawers: Bool {
        switch self {
        case .rawPrimary, .compactOverlay:
            return true
        case .wide, .split:
            return false
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var sparkleUpdater: SparkleUpdater
    @State private var showingSettings = false
    @State private var showingReleaseNotes = false
    @State private var intelligenceMode: IntelligenceMode = .overview
    @State private var editingCandidate: EditingCandidate?
    @State private var decisionDraftText = ""
    @State private var actionDraftAssignee = ""
    @State private var actionDraftTask = ""
    @State private var actionDraftDeadline = ""
    @State private var copiedCandidateID: String?
    @State private var selectedAnalysisAttempt: AnalysisAttemptLog?
    @State private var isAnalysisDiagnosticsExpanded = false
    @State private var isParticipantsPopoverPresented = false
    @State private var manuallyCollapsedPanes: Set<AdaptivePane> = []
    @State private var activeOverlayPane: AdaptivePane?

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { proxy in
                adaptivePaneContent(availableWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(minWidth: 760, minHeight: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.smoothCanvas)
        .tint(Color.smoothAccent)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(sparkleUpdater)
        }
        .sheet(isPresented: $showingReleaseNotes) {
            ReleaseNotesView()
        }
        .sheet(isPresented: $viewModel.isShowingOnboarding) {
            OnboardingView()
                .environmentObject(viewModel)
        }
        .sheet(item: $selectedAnalysisAttempt) { attempt in
            AnalysisAttemptDetailView(attempt: attempt)
        }
        .sheet(
            isPresented: Binding(
                get: { !viewModel.pendingMarkdownReadinessWarnings.isEmpty },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelMarkdownReadinessPreview()
                    }
                }
            )
        ) {
            MarkdownReadinessPreviewSheet(warnings: viewModel.pendingMarkdownReadinessWarnings) {
                viewModel.exportCurrentIntelligenceMarkdownIgnoringReadiness()
            } onCancel: {
                viewModel.cancelMarkdownReadinessPreview()
            }
        }
        .onChange(of: sparkleUpdater.blockingSheetDismissalRequestID) {
            dismissBlockingSheetsForUpdate()
        }
    }

    @ViewBuilder
    private func adaptivePaneContent(availableWidth: CGFloat) -> some View {
        let mode = AdaptiveLayoutMode(width: availableWidth)
        ZStack {
            adaptivePaneBaseContent(mode: mode, availableWidth: availableWidth)

            if mode.usesOverlayDrawers, let activeOverlayPane {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            self.activeOverlayPane = nil
                        }
                    }
                    .zIndex(1)

                overlayDrawer(activeOverlayPane, availableWidth: availableWidth)
                    .zIndex(2)
            }
        }
    }

    @ViewBuilder
    private func adaptivePaneBaseContent(mode: AdaptiveLayoutMode, availableWidth: CGFloat) -> some View {
        if mode.usesOverlayDrawers {
            VStack(spacing: 10) {
                overlayPaneToggleBar
                transcriptContent
                    .frame(minWidth: transcriptMinimumWidth(for: availableWidth), maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            let collapsedPanes = adaptiveCollapsedPanes(for: mode)
            HStack(spacing: 10) {
                if collapsedPanes.contains(.meetings) {
                    collapsedPaneRail(.meetings)
                        .frame(minWidth: 46, idealWidth: 46, maxWidth: 46, maxHeight: .infinity)
                } else {
                    historySidebar
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 360, maxHeight: .infinity)
                }

                transcriptContent
                    .frame(minWidth: transcriptMinimumWidth(for: availableWidth), maxWidth: .infinity, maxHeight: .infinity)

                if collapsedPanes.contains(.intelligence) {
                    collapsedPaneRail(.intelligence)
                        .frame(minWidth: 46, idealWidth: 46, maxWidth: 46, maxHeight: .infinity)
                } else {
                    intelligenceContent()
                        .frame(minWidth: 330, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func adaptiveCollapsedPanes(for mode: AdaptiveLayoutMode) -> Set<AdaptivePane> {
        var collapsedPanes = manuallyCollapsedPanes
        if mode != .wide {
            collapsedPanes.insert(.meetings)
        }
        return collapsedPanes
    }

    private func transcriptMinimumWidth(for width: CGFloat) -> CGFloat {
        width < 820 ? 300 : 330
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(AppVersion.displayTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.smoothAccent)
                            .textCase(.uppercase)

                        Button {
                            showingReleaseNotes = true
                        } label: {
                            Label("릴리즈 노트", systemImage: "doc.text")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.smoothInk)
                        .background(Color.smoothSurface, in: Capsule())
                        .overlay(Capsule().stroke(Color.smoothLine, lineWidth: 1))
                        .help("릴리즈 노트 보기")

                        if let availableUpdate = sparkleUpdater.availableUpdate {
                            Button {
                                sparkleUpdater.showAvailableUpdate()
                            } label: {
                                Label("업데이트 \(availableUpdate.version)", systemImage: "arrow.down.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.smoothOnAccent)
                            .background(Color.smoothAccent, in: Capsule())
                            .help("다운로드 및 설치 화면 열기")
                        }
                    }
                    Text(viewModel.metadata.displayTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.smoothInk)
                    Text(viewModel.statusMessage)
                        .font(.callout)
                        .foregroundStyle(Color.smoothMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                headerActions
            }

            statusChipRows

            HStack(alignment: .top, spacing: 22) {
                metadataRow("일시", viewModel.metadata.dateTime ?? "-")
                participantMetadataRow(
                    participants: viewModel.metadata.participants,
                    speakers: viewModel.transcriptSpeakers
                )
                metadataRow("파일", viewModel.activeTranscriptURL?.lastPathComponent ?? "-", monospaced: true)
            }
            .font(.callout)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var historySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            paneTitle("Meetings", systemImage: "sidebar.left", collapsePane: .meetings)
            Divider().overlay(Color.smoothLine)

            VStack(alignment: .leading, spacing: 14) {
                liveNowControl
                testRunControl

                Divider().overlay(Color.smoothLine)

                meetingSearchControl
            }
            .padding(12)

            Divider().overlay(Color.smoothLine)

            if viewModel.meetingHistoryItems.isEmpty {
                emptyState(
                    "회의록 없음",
                    systemImage: "doc.text.magnifyingglass",
                    description: "선택한 폴더의 `.txt` 회의록이 이곳에 표시됩니다."
                )
            } else if viewModel.filteredMeetingHistoryItems.isEmpty {
                emptyState(
                    "검색 결과 없음",
                    systemImage: "magnifyingglass",
                    description: "다른 회의 제목, 참석자, 요약 키워드로 검색해 보세요."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.filteredMeetingHistorySearchResults) { result in
                            historyRow(
                                result.item,
                                searchMatch: result.match,
                                anchorTimestamp: result.anchorTimestamp
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .smoothPanel()
    }

    private var liveNowControl: some View {
        Button {
            viewModel.returnToLiveWatch()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.smoothAccent.opacity(0.12))
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.smoothAccent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Live Now")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.smoothInk)

                        if viewModel.liveMeetingUpdated {
                            Image(systemName: "bell.badge.fill")
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                        }
                    }

                    Text(viewModel.liveActiveTranscriptURL?.lastPathComponent ?? "선택한 폴더에 live transcript 없음")
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(liveControlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(viewModel.transcriptRunMode == .liveWatch ? Color.smoothAccent.opacity(0.45) : Color.smoothLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedFolderURL == nil)
    }

    private var testRunControl: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.chooseTestRunFile()
            } label: {
                Label("Test Run", systemImage: "play.rectangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("파일을 선택해 timestamp 순서대로 replay")

            if viewModel.isTestRunActive {
                Text(viewModel.testRunProgressText)
                    .font(.caption2)
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(viewModel.isTestRunActive ? Color.smoothAccent.opacity(0.55) : Color.smoothLine, lineWidth: 1)
        )
    }

    private var meetingSearchControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Search Meetings", systemImage: "magnifyingglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.smoothAccent)

                Spacer(minLength: 0)

                historySortMenu

                Text("\(viewModel.filteredMeetingHistorySearchResults.count)/\(viewModel.meetingHistoryItems.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.smoothMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.smoothSurface, in: Capsule())
                    .overlay(Capsule().stroke(Color.smoothLine, lineWidth: 1))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.smoothAccent)

                TextField("제목, 참석자, 결정, 액션, 원문 검색", text: $viewModel.historySearchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.smoothInk)

                if !viewModel.historySearchText.isEmpty {
                    Button {
                        viewModel.historySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.smoothMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothAccent.opacity(0.55), lineWidth: 1)
            )

            searchIndexProgressView

            historyFilterControls
        }
        .padding(10)
        .background(Color.smoothCanvas.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var searchIndexProgressView: some View {
        if viewModel.searchIndexProgress.isVisible {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "cylinder.split.1x2")
                        .foregroundStyle(Color.smoothAccent)
                    Text(viewModel.searchIndexProgress.displayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.smoothMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                ProgressView(value: viewModel.searchIndexProgress.fraction)
                    .progressViewStyle(.linear)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
        }
    }

    private var historySortMenu: some View {
        Menu {
            ForEach(MeetingHistorySortOrder.allCases, id: \.self) { order in
                Button {
                    viewModel.historySortOrder = order
                } label: {
                    menuCheckLabel(order.displayName, isSelected: viewModel.historySortOrder == order)
                }
            }
        } label: {
            Label(viewModel.historySortOrder.displayName, systemImage: "arrow.up.arrow.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.smoothInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.smoothSurface, in: Capsule())
                .overlay(Capsule().stroke(Color.smoothLine, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("검색 결과 정렬")
    }

    private var historyFilterControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                historyDateFilterMenu
                historyCompletionFilterMenu
                historyCandidateFilterMenu
            }

            HStack(spacing: 6) {
                historyParticipantFilterMenu
                historyRoomFilterMenu

                if viewModel.hasActiveHistoryFilters {
                    Button {
                        viewModel.resetHistoryFilters()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.smoothAccent)
                            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.smoothLine, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("검색 필터 초기화")
                }
            }
        }
    }

    private var historyDateFilterMenu: some View {
        Menu {
            ForEach(MeetingHistoryDateFacet.allCases, id: \.self) { facet in
                Button {
                    viewModel.historyDateFilter = facet
                } label: {
                    menuCheckLabel(facet.displayName, isSelected: viewModel.historyDateFilter == facet)
                }
            }
        } label: {
            filterPill("기간", viewModel.historyDateFilter.displayName, isActive: viewModel.historyDateFilter != .all)
        }
        .menuStyle(.borderlessButton)
    }

    private var historyCompletionFilterMenu: some View {
        Menu {
            ForEach(MeetingHistoryCompletionFacet.allCases, id: \.self) { facet in
                Button {
                    viewModel.historyCompletionFilter = facet
                } label: {
                    menuCheckLabel(facet.displayName, isSelected: viewModel.historyCompletionFilter == facet)
                }
            }
        } label: {
            filterPill("상태", viewModel.historyCompletionFilter.displayName, isActive: viewModel.historyCompletionFilter != .all)
        }
        .menuStyle(.borderlessButton)
    }

    private var historyCandidateFilterMenu: some View {
        Menu {
            ForEach(MeetingHistoryCandidateFacet.allCases, id: \.self) { facet in
                Button {
                    viewModel.historyCandidateFilter = facet
                } label: {
                    menuCheckLabel(facet.displayName, isSelected: viewModel.historyCandidateFilter == facet)
                }
            }
        } label: {
            filterPill("후보", viewModel.historyCandidateFilter.displayName, isActive: viewModel.historyCandidateFilter != .all)
        }
        .menuStyle(.borderlessButton)
    }

    private var historyParticipantFilterMenu: some View {
        Menu {
            Button {
                viewModel.historyParticipantFilter = nil
            } label: {
                menuCheckLabel("전체 참석자", isSelected: viewModel.historyParticipantFilter == nil)
            }
            Divider()
            ForEach(viewModel.historyAvailableParticipants, id: \.self) { participant in
                Button {
                    viewModel.historyParticipantFilter = participant
                } label: {
                    menuCheckLabel(participant, isSelected: viewModel.historyParticipantFilter == participant)
                }
            }
        } label: {
            filterPill("참석자", viewModel.historyParticipantFilter ?? "전체 참석자", isActive: viewModel.historyParticipantFilter != nil)
        }
        .menuStyle(.borderlessButton)
    }

    private var historyRoomFilterMenu: some View {
        Menu {
            Button {
                viewModel.historyRoomFilter = nil
            } label: {
                menuCheckLabel("전체 room", isSelected: viewModel.historyRoomFilter == nil)
            }
            Divider()
            ForEach(viewModel.historyAvailableRooms, id: \.self) { room in
                Button {
                    viewModel.historyRoomFilter = room
                } label: {
                    menuCheckLabel(room, isSelected: viewModel.historyRoomFilter == room)
                }
            }
        } label: {
            filterPill("room", viewModel.historyRoomFilter ?? "전체 room", isActive: viewModel.historyRoomFilter != nil)
        }
        .menuStyle(.borderlessButton)
    }

    private func filterPill(_ label: String, _ value: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isActive ? Color.smoothAccent : Color.smoothMuted)
            Text(value)
                .font(.caption2)
                .foregroundStyle(Color.smoothInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isActive ? Color.smoothAccent.opacity(0.55) : Color.smoothLine, lineWidth: 1)
        )
    }

    private func menuCheckLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var liveControlBackground: Color {
        if viewModel.transcriptRunMode == .liveWatch {
            return Color.smoothMint
        }
        return Color.smoothSurface
    }

    private func historyRow(
        _ item: MeetingHistoryItem,
        searchMatch: MeetingHistorySearchMatch?,
        anchorTimestamp: String?
    ) -> some View {
        let isSelected = viewModel.activeTranscriptURL == item.url
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.hasAnalysis ? "sparkles" : "doc.text")
                    .foregroundStyle(item.hasAnalysis ? Color.smoothAccent : Color.smoothMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.smoothInk)
                        .lineLimit(2)
                    Text(item.subtitle.isEmpty ? item.url.lastPathComponent : item.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    viewModel.startTestRunFromHistory(item)
                } label: {
                    Image(systemName: "play.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.smoothAccent)
                        .frame(width: 24, height: 24)
                        .background(Color.smoothCanvas, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("이 회의록으로 Test Run 시작")
            }

            if let searchMatch {
                VStack(alignment: .leading, spacing: 3) {
                    Label(searchMatch.displayText, systemImage: "text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(Color.smoothAccent)
                        .lineLimit(2)
                    if anchorTimestamp != nil {
                        Label("클릭하면 원문 위치로 이동", systemImage: "arrow.down.forward.circle")
                            .font(.caption2)
                            .foregroundStyle(Color.smoothMuted)
                    }
                }
            } else if let summary = item.summaryPreview, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                miniChip("\(item.topicCount)", "topics")
                miniChip("\(item.decisionCount)", "dec")
                miniChip("\(item.actionCount)", "act")
                if item.isCompleted {
                    miniChip("done", "")
                }
                Spacer(minLength: 0)
                Text(item.modificationDate.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Color.smoothMuted)
            }
        }
        .padding(10)
        .background(isSelected ? Color.smoothMint : Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.smoothAccent.opacity(0.45) : Color.smoothLine, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openHistorySearchResult(item, anchorTimestamp: anchorTimestamp)
        }
    }

    private func miniChip(_ value: String, _ label: String) -> some View {
        Text(label.isEmpty ? value : "\(value) \(label)")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.smoothCanvas, in: Capsule())
            .foregroundStyle(Color.smoothMuted)
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            rawTranscriptHeader
            Divider().overlay(Color.smoothLine)
            Group {
                if viewModel.activeTranscriptURL == nil {
                    emptyState(
                        "transcript 대기 중",
                        systemImage: "doc.text.magnifyingglass",
                        description: "Recordings 폴더를 선택하면 최신 `.txt` 파일을 자동으로 따라갑니다."
                    )
                } else if viewModel.rawTranscript.isEmpty {
                    emptyState(
                        "아직 내용이 없습니다",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        description: "활성 파일에 새 transcript 줄이 추가되면 이곳에 표시됩니다."
                    )
                } else {
                    rawTranscriptScroll
                }
            }
        }
        .smoothPanel()
    }

    private var rawTranscriptHeader: some View {
        HStack(spacing: 10) {
            Label("Raw Transcript", systemImage: "doc.text")
                .font(.headline)
                .foregroundStyle(Color.smoothInk)

            Spacer(minLength: 8)

            Text("\(viewModel.rawTranscriptLineCount) lines")
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)

            if viewModel.shouldShowMomentMarker {
                momentMarkerTranscriptMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var momentMarkerTranscriptMenu: some View {
        Menu {
            momentMarkerMenuItems
        } label: {
            ViewThatFits(in: .horizontal) {
                Label("중요 시점", systemImage: "flag")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "flag")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .foregroundStyle(Color.smoothInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.smoothControl, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .disabled(!viewModel.canAddLiveBookmark)
        .help("현재 transcript 마지막 시점을 중요 시점으로 표시")
    }

    private var rawTranscriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                rawTranscriptLineList
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .background(Color.smoothSurface)
            .onChange(of: viewModel.rawTranscriptRevision) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.transcriptFocusRequest) { _, request in
                guard let request else {
                    return
                }
                proxy.scrollTo(request.lineID, anchor: .center)
            }
        }
    }

    private var rawTranscriptLineList: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.rawTranscriptPreviewLines.indices, id: \.self) { offset in
                TranscriptLineRow(
                    line: viewModel.rawTranscriptPreviewLines[offset],
                    isHighlighted: offset == viewModel.highlightedTranscriptLineID
                )
                .equatable()
                .id(offset)
            }
        }
        .padding(18)
        .textSelection(.enabled)
    }

    private func intelligenceContent(compact: Bool = false, availableWidth: CGFloat? = nil) -> some View {
        let selectedMode = visibleIntelligenceMode
        return VStack(alignment: .leading, spacing: 0) {
            if compact {
                compactIntelligenceHeader(availableWidth: availableWidth)
            } else {
                HStack(spacing: 12) {
                    paneTitle("Meeting Intelligence", systemImage: "sparkles", compact: true, collapsePane: .intelligence)
                    Spacer()
                    intelligenceModeSegmentedControl()
                        .frame(width: 360)
                }
                .padding(.trailing, 12)
            }

            Divider().overlay(Color.smoothLine)

            if let snapshot = viewModel.analysisState.latestSnapshot {
                ScrollView {
                    Group {
                        switch selectedMode {
                        case .overview:
                            overview(snapshot)
                        case .timeline:
                            timeline(snapshot.topicTimeline, full: true)
                        case .candidates:
                            VStack(alignment: .leading, spacing: 12) {
                                decisions(snapshot.decisionCandidates, compact: false)
                                actionItems(snapshot.actionItemCandidates, compact: false)
                                notes(snapshot.risksOrNotes)
                            }
                        case .workflow:
                            workflow(viewModel.personalWorkflowSnapshot)
                        case .context:
                            contextPanel()
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let failureMessage = viewModel.analysisStatus.failureMessage {
                emptyState("analysis 실패", systemImage: "exclamationmark.triangle", description: failureMessage)
            } else {
                emptyState(
                    "analysis 대기 중",
                    systemImage: "sparkles",
                    description: "transcript가 준비되면 주기적으로 회의 흐름과 후보 항목을 갱신합니다."
                )
            }
        }
        .smoothPanel()
    }

    private var visibleIntelligenceMode: IntelligenceMode {
        IntelligenceMode.visibleModes.contains(intelligenceMode) ? intelligenceMode : .overview
    }

    private func compactIntelligenceHeader(availableWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Meeting Intelligence", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Color.smoothInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        activeOverlayPane = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.smoothMuted)
                        .frame(width: 26, height: 26)
                        .background(Color.smoothControl, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Meeting Intelligence 닫기")
            }

            if (availableWidth ?? 420) < 370 {
                intelligenceModeMenu()
            } else {
                intelligenceModeSegmentedControl()
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func intelligenceModeSegmentedControl() -> some View {
        Picker("view", selection: $intelligenceMode) {
            ForEach(IntelligenceMode.visibleModes) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func intelligenceModeMenu() -> some View {
        Menu {
            Picker("view", selection: $intelligenceMode) {
                ForEach(IntelligenceMode.visibleModes) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(visibleIntelligenceMode.rawValue)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.smoothInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.smoothControl, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private func overview(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            currentIssue(snapshot.currentIssue)
            meetingSummary(snapshot.meetingSummary, meetingType: snapshot.meetingType)
            if !viewModel.analysisState.bookmarks.isEmpty {
                importantMoments(viewModel.analysisState.bookmarks)
            }
            metricsRow(snapshot)
            decisions(snapshot.decisionCandidates, compact: true)
            actionItems(snapshot.actionItemCandidates, compact: true)
            timeline(Array(snapshot.topicTimeline.suffix(4)), full: false)
            notes(Array(snapshot.risksOrNotes.prefix(2)))
            usageSummary()
            analysisDiagnostics()
        }
    }

    private func workflow(_ snapshot: PersonalWorkflowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            decisionCoach(snapshot.coachCards)
            shareReadiness(snapshot.readinessWarnings)
            actionLedger(snapshot.actionLedgerItems)
            carryOverQuestions(snapshot.carryOverCandidates)
        }
    }

    private func contextPanel() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            googleCalendarAPIStatusCard()
            calendarMCPStatusCard()
            calendarEventCandidates(viewModel.analysisState.calendarContext.eventCandidates)
            supplementalContextSources(viewModel.analysisState.calendarContext.supplementalSources)
        }
    }

    private func googleCalendarAPIStatusCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                sectionHeader("Google Calendar API", systemImage: "calendar.badge.checkmark")
                Spacer(minLength: 0)
                googleCalendarContextActions
            }
            Text(viewModel.googleCalendarStatusMessage)
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("현재 회의 시간대의 Calendar event를 가져와 meeting identity와 supplemental context로 저장합니다.")
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .smoothCard(tint: Color.smoothAccent)
    }

    private var googleCalendarContextActions: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.connectGoogleCalendar()
            } label: {
                Label(viewModel.isGoogleCalendarConnecting ? "연결 중" : "연결", systemImage: "link")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isGoogleCalendarConnecting)

            Button {
                viewModel.fetchGoogleCalendarAPIContext()
            } label: {
                Label(viewModel.isFetchingGoogleCalendarAPIContext ? "가져오는 중" : "가져오기", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isFetchingGoogleCalendarAPIContext || viewModel.activeTranscriptURL == nil)

            Button {
                viewModel.disconnectGoogleCalendar()
            } label: {
                Label("해제", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption.weight(.semibold))
    }

    private func calendarMCPStatusCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                sectionHeader("Google Calendar MCP", systemImage: "calendar.badge.clock")
                Button {
                    viewModel.fetchGoogleCalendarContext()
                } label: {
                    Label(viewModel.isFetchingCalendarContext ? "가져오는 중" : "가져오기", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isFetchingCalendarContext)
            }
            Text(viewModel.calendarContextStatusMessage)
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let identity = viewModel.analysisState.calendarContext.meetingIdentity {
                Text("Identity: \(identity.seriesKey)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .smoothCard(tint: Color.smoothAccent)
    }

    private func calendarEventCandidates(_ candidates: [CalendarEventCandidate]) -> some View {
        let visibleCandidates = candidates.filter { $0.status != .dismissed }
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Calendar Event Candidates", systemImage: "calendar")
            if visibleCandidates.isEmpty {
                placeholderLine("Google Calendar MCP에서 가져온 후보가 없습니다.")
            }
            ForEach(visibleCandidates) { candidate in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: candidate.status == .accepted ? "checkmark.circle.fill" : "calendar")
                            .foregroundStyle(candidate.status == .accepted ? Color.smoothMint : Color.smoothAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.smoothInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(candidate.startDateText)-\(candidate.endDateText)")
                                .font(.caption)
                                .foregroundStyle(Color.smoothMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            if !candidate.descriptionExcerpt.isEmpty {
                                Text(candidate.descriptionExcerpt)
                                    .font(.caption)
                                    .foregroundStyle(Color.smoothMuted)
                                    .lineLimit(3)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Button {
                            viewModel.acceptCalendarEventCandidate(id: candidate.id)
                        } label: {
                            Label(candidate.status == .accepted ? "사용 중" : "사용", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(candidate.status == .accepted)

                        Button {
                            viewModel.dismissCalendarEventCandidate(id: candidate.id)
                        } label: {
                            Label("숨기기", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(10)
                .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.smoothLine, lineWidth: 1)
                )
            }
        }
        .smoothCard(tint: Color.smoothSky)
    }

    private func supplementalContextSources(_ sources: [SupplementalContextSource]) -> some View {
        let acceptedSources = sources.sortedForPrompt()
        let candidateSources = sources.filter { !$0.isAccepted }
            .sorted { $0.confidence > $1.confidence }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                sectionHeader("Supplemental Context", systemImage: "doc.text.magnifyingglass")
                Button {
                    viewModel.chooseSupplementalContextFile()
                } label: {
                    Label("파일 첨부", systemImage: "paperclip")
                }
                .buttonStyle(.borderless)
            }
            if acceptedSources.isEmpty && candidateSources.isEmpty {
                placeholderLine("Prompt에 주입하거나 확인할 context가 없습니다.")
            }
            ForEach(acceptedSources) { source in
                supplementalContextSourceRow(source, isCandidateOnly: false)
            }
            ForEach(candidateSources) { source in
                supplementalContextSourceRow(source, isCandidateOnly: true)
            }
        }
        .smoothCard()
    }

    private func supplementalContextSourceRow(_ source: SupplementalContextSource, isCandidateOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(source.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isCandidateOnly ? "후보" : "주입")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCandidateOnly ? Color.smoothMuted : Color.smoothMint)
            }
            Text("\(source.sourceName) · priority \(source.priority.rawValue) · confidence \(String(format: "%.2f", source.confidence))")
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(source.excerpt)
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
                .lineLimit(4)
        }
        .padding(10)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func decisionCoach(_ cards: [DecisionCoachCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("결정 코치", systemImage: "lightbulb.max")
            if cards.isEmpty {
                placeholderLine("현재 막힌 논점으로 보이는 항목이 없습니다.")
            }
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: card.severity == .warning ? "exclamationmark.triangle" : "sparkle.magnifyingglass")
                            .foregroundStyle(card.severity == .warning ? Color.orange : Color.smoothAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.smoothInk)
                            Text(card.stuckPoint)
                                .font(.callout)
                                .foregroundStyle(Color.smoothMuted)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("최소 결정: \(card.minimumDecision)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.smoothInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if !card.missingInfo.isEmpty {
                                Text("부족한 정보: \(card.missingInfo.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(Color.smoothMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(card.nextQuestion)
                                .font(.caption)
                                .foregroundStyle(Color.smoothAccent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.smoothLine, lineWidth: 1)
                )
            }
        }
        .smoothCard(tint: Color.smoothMint)
    }

    private func shareReadiness(_ warnings: [ShareReadinessWarning]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("공유 준비도", systemImage: "checklist")
                Spacer()
                Text(warnings.isEmpty ? "공유 가능" : "\(warnings.count)개 경고")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(warnings.isEmpty ? Color.smoothMint : Color.orange)
            }
            if warnings.isEmpty {
                placeholderLine("공유 전 확인할 경고가 없습니다.")
            }
            ForEach(warnings) { warning in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.title)
                            .font(.callout.weight(.semibold))
                        Text(warning.detail)
                            .font(.caption)
                            .foregroundStyle(Color.smoothMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: warning.severity == .warning ? "exclamationmark.circle" : "info.circle")
                        .foregroundStyle(warning.severity == .warning ? Color.orange : Color.smoothAccent)
                }
            }
        }
        .smoothCard(tint: Color.smoothWarm)
    }

    private func actionLedger(_ items: [ActionLedgerItem]) -> some View {
        let visibleItems = Array(items.prefix(12))
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("액션 장부", systemImage: "tray.full")
            if visibleItems.isEmpty {
                placeholderLine("확정된 액션이 아직 없습니다.")
            }
            ForEach(visibleItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(Color.smoothAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.task)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.smoothInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(actionLedgerMetadata(item))
                                .font(.caption)
                                .foregroundStyle(Color.smoothMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 4)
                if item.id != visibleItems.last?.id {
                    Divider().overlay(Color.smoothLine)
                }
            }
        }
        .smoothCard(tint: Color.smoothSky)
    }

    private func carryOverQuestions(_ candidates: [OpenQuestionCarryOverCandidate]) -> some View {
        let recurringCandidates = Array(candidates.filter { $0.category == .recurring }.prefix(8))
        let relatedCandidates = Array(candidates.filter { $0.category == .related }.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionHeader("이어받은 미해결 질문", systemImage: "arrowshape.turn.up.right")
                Button {
                    viewModel.refreshCarryOverQuestions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.canRefreshCarryOverQuestions)
                .help("이어받은 미해결 질문 새로고침")
            }
            if recurringCandidates.isEmpty && relatedCandidates.isEmpty {
                placeholderLine("관련 히스토리에서 이어받을 미해결 질문이 없습니다.")
            }
            if !recurringCandidates.isEmpty {
                carryOverQuestionGroup("반복 회의", candidates: recurringCandidates)
            }
            if !relatedCandidates.isEmpty {
                carryOverQuestionGroup("기타 관련 회의", candidates: relatedCandidates)
            }
        }
        .smoothCard()
    }

    private func carryOverQuestionGroup(_ title: String, candidates: [OpenQuestionCarryOverCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)
            ForEach(candidates) { candidate in
                carryOverQuestionRow(candidate)
            }
        }
    }

    private func carryOverQuestionRow(_ candidate: OpenQuestionCarryOverCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.question)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.smoothInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(candidate.sourceTitle) · \(candidate.reason)")
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
            HStack(spacing: 8) {
                Button {
                    viewModel.resolveCarryOverQuestion(id: candidate.id)
                } label: {
                    Label("해결됨", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderless)

                Button {
                    viewModel.dismissCarryOverQuestion(id: candidate.id)
                } label: {
                    Label("숨기기", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func actionLedgerMetadata(_ item: ActionLedgerItem) -> String {
        [
            item.assignee.map { "@\($0)" },
            item.deadline.map { "기한 \($0)" },
            item.meetingTitle,
            MeetingTimestampFormatter.display(item.evidenceTimestamp, meetingDateTime: nil)
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func currentIssue(_ issue: CurrentIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("현재 논점", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Text(viewModel.analysisStatus.displayText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusTint.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusTint)
            }

            Text(issue.summary.isEmpty ? "-" : issue.summary)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.smoothInk)
                .fixedSize(horizontal: false, vertical: true)

            if !issue.openQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issue.openQuestions.prefix(3), id: \.self) { question in
                        Label(question, systemImage: "questionmark.circle")
                            .font(.callout)
                            .foregroundStyle(Color.smoothMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .smoothCard(tint: Color.smoothMint)
    }

    @ViewBuilder
    private func meetingSummary(_ summary: MeetingSummary, meetingType: MeetingTypePreset) -> some View {
        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("회의 요약", systemImage: "text.badge.checkmark")
                        .font(.headline)
                    Spacer()
                    Text(meetingType.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.smoothAccent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.smoothAccent)
                }

                if !summary.overview.isEmpty {
                    Text(summary.overview)
                        .font(.callout)
                        .foregroundStyle(Color.smoothInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !summary.keyPoints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.keyPoints.prefix(4)) { item in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text)
                                    if let evidence = item.evidence.first {
                                        Text(summaryEvidenceText(evidence))
                                            .font(.caption)
                                            .foregroundStyle(Color.smoothMuted)
                                    }
                                }
                            } icon: {
                                Image(systemName: "checkmark.circle")
                            }
                            .font(.callout)
                        }
                    }
                }

                if !summary.openQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.openQuestions.prefix(3)) { item in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text)
                                    if let evidence = item.evidence.first {
                                        Text(summaryEvidenceText(evidence))
                                            .font(.caption)
                                            .foregroundStyle(Color.smoothMuted)
                                    }
                                }
                            } icon: {
                                Image(systemName: "questionmark.circle")
                            }
                            .font(.callout)
                            .foregroundStyle(Color.smoothMuted)
                        }
                    }
                }
            }
            .smoothCard(tint: Color.smoothAccent)
        }
    }

    private func importantMoments(_ bookmarks: [MeetingBookmark]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("중요 시점", systemImage: "flag")
                    .font(.headline)
                Spacer()
                Text("\(bookmarks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.smoothMuted)
            }

            ForEach(bookmarks.suffix(6)) { bookmark in
                HStack(alignment: .top, spacing: 8) {
                    Text(MeetingTimestampFormatter.display(bookmark.timestamp, meetingDateTime: viewModel.metadata.dateTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.smoothAccent)
                        .frame(width: 58, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bookmark.label ?? "중요 시점")
                            .font(.callout.weight(.semibold))
                        if !bookmark.excerpt.isEmpty {
                            Text(bookmark.excerpt)
                                .font(.caption)
                                .foregroundStyle(Color.smoothMuted)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        viewModel.deleteLiveBookmark(id: bookmark.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("중요 시점 삭제")
                }
            }
        }
        .smoothCard(tint: Color.smoothAccent)
    }

    private func metricsRow(_ snapshot: AnalysisSnapshot) -> some View {
        HStack(spacing: 8) {
            metricCard("\(snapshot.topicTimeline.count)", "topics", "list.bullet.rectangle")
            metricCard("\(visibleDecisions(snapshot.decisionCandidates).count)", "decisions", "checkmark.seal")
            metricCard("\(visibleActions(snapshot.actionItemCandidates).count)", "actions", "person.crop.circle.badge.checkmark")
        }
    }

    private func metricCard(_ value: String, _ label: String, _ systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.smoothAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.weight(.bold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func usageSummary() -> some View {
        let summary = viewModel.analysisState.usageSummary
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("LLM 사용량 추정", systemImage: "chart.bar.doc.horizontal")
            HStack(spacing: 8) {
                metricCard("\(summary.totalInputTokens)", "input tokens", "arrow.down.doc")
                metricCard("\(summary.totalOutputTokens)", "output tokens", "arrow.up.doc")
                metricCard(String(format: "$%.4f", summary.totalEstimatedCostUSD), "estimated", "dollarsign.circle")
            }
            if let latest = summary.latestSample {
                Text("최근 run: \(latest.modelName) · input $\(priceText(latest.inputPricePerMillionUSD))/1M · output $\(priceText(latest.outputPricePerMillionUSD))/1M")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                placeholderLine("아직 성공한 LLM run usage가 없습니다.")
            }
        }
        .smoothCard(tint: Color.smoothMint)
    }

    private func analysisDiagnostics() -> some View {
        let attempts = Array(viewModel.analysisState.attemptLogs.reversed())
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isAnalysisDiagnosticsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isAnalysisDiagnosticsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.smoothMuted)
                        .frame(width: 14)
                    sectionHeader("Analysis 실행 로그", systemImage: "stethoscope")
                    Spacer()
                    if !attempts.isEmpty {
                        Text("\(attempts.count)/40")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.smoothMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.smoothCanvas, in: Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if attempts.isEmpty {
                placeholderLine("아직 analysis 실행 로그가 없습니다.")
            } else if !isAnalysisDiagnosticsExpanded, let latest = attempts.first {
                Button {
                    selectedAnalysisAttempt = latest
                } label: {
                    HStack(spacing: 8) {
                        Text("\(latest.reason) · \(latest.status.rawValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(latest.status == .failed ? Color.orange : Color.smoothInk)
                        Spacer()
                        Text(latest.completedAt?.formatted(date: .omitted, time: .standard) ?? "running")
                            .font(.caption)
                            .foregroundStyle(Color.smoothMuted)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(attemptSummaryLine(latest))
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(2)
            }

            if isAnalysisDiagnosticsExpanded {
                Divider().overlay(Color.smoothLine)
                ForEach(attempts) { attempt in
                    Button {
                        selectedAnalysisAttempt = attempt
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(attempt.reason)
                                    .font(.caption.weight(.semibold))
                                Text(attempt.status.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(attempt.status == .failed ? Color.orange : Color.smoothAccent)
                                Spacer()
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.caption)
                                    .foregroundStyle(Color.smoothMuted)
                                Text(attempt.completedAt?.formatted(date: .omitted, time: .standard) ?? "running")
                                    .font(.caption)
                                    .foregroundStyle(Color.smoothMuted)
                            }
                            Text(attemptSummaryLine(attempt))
                                .font(.caption)
                                .foregroundStyle(Color.smoothMuted)
                                .lineLimit(3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    if attempt.id != attempts.last?.id {
                        Divider().overlay(Color.smoothLine)
                    }
                }
            }
        }
        .smoothCard()
    }

    private func attemptSummaryLine(_ attempt: AnalysisAttemptLog) -> String {
        [
            attempt.executionProviderDisplayName,
            "\(attempt.modelName)",
            "input \(attempt.inputTokens)",
            "output \(attempt.outputTokens)",
            attempt.elapsedMilliseconds.map { "\($0)ms" },
            attempt.batchStats?.compactSummary,
            attempt.message
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func timeline(_ items: [TopicTimelineItem], full: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(full ? "전체 흐름" : "최근 흐름", systemImage: "waveform.path.ecg")
            if items.isEmpty {
                placeholderLine("아직 topic timeline이 없습니다.")
            }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text(timeRange(item))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.smoothAccent)
                        .frame(width: 96, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.smoothInk)
                        Text(item.summary)
                            .font(.callout)
                            .foregroundStyle(Color.smoothMuted)
                            .lineLimit(full ? nil : 2)
                    }
                }
                .padding(.vertical, 6)
                if item.id != items.last?.id {
                    Divider().overlay(Color.smoothLine)
                }
            }
        }
        .smoothCard()
    }

    private func decisions(_ candidates: [DecisionCandidate], compact: Bool) -> some View {
        let candidates = visibleDecisions(candidates)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionHeader("결정 후보", systemImage: "checkmark.seal")
                if !candidates.isEmpty {
                    copySectionButton(
                        title: "전체 복사",
                        copiedID: "decisions-all",
                        help: "결정 후보 전체 복사",
                        action: { copyDecisionCandidates(candidates) }
                    )
                }
            }
            if candidates.isEmpty {
                placeholderLine("아직 반응할 결정 후보가 없습니다.")
            }
            ForEach(compact ? Array(candidates.prefix(3)) : candidates) { candidate in
                decisionCandidateRow(candidate, compact: compact)
            }
        }
        .smoothCard(tint: Color.smoothSky)
    }

    private func actionItems(_ candidates: [ActionItemCandidate], compact: Bool) -> some View {
        let candidates = visibleActions(candidates)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionHeader("액션 후보", systemImage: "arrow.up.forward.circle")
                if !candidates.isEmpty {
                    copySectionButton(
                        title: "전체 복사",
                        copiedID: "actions-all",
                        help: "액션 후보 전체 복사",
                        action: { copyActionCandidates(candidates) }
                    )
                }
            }
            if candidates.isEmpty {
                placeholderLine("아직 반응할 action item 후보가 없습니다.")
            }
            ForEach(compact ? Array(candidates.prefix(3)) : candidates) { candidate in
                actionCandidateRow(candidate, compact: compact)
            }
        }
        .smoothCard(tint: Color.smoothWarm)
    }

    private func notes(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Risks / Notes", systemImage: "exclamationmark.triangle")
            if notes.isEmpty {
                placeholderLine("추가 note가 없습니다.")
            }
            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .smoothCard()
    }

    @ViewBuilder
    private func decisionCandidateRow(_ candidate: DecisionCandidate, compact: Bool) -> some View {
        if editingCandidate == EditingCandidate(kind: .decision, id: candidate.id) {
            decisionEditForm(candidate)
        } else {
            candidateRow(
                text: candidate.text,
                status: candidate.status,
                evidence: evidenceText(candidate.evidenceTimestamp, candidate.speaker),
                isEdited: viewModel.analysisState.decisionCandidateEdits[candidate.id] != nil,
                confirm: { viewModel.confirmDecision(candidate.id) },
                unconfirm: { viewModel.unconfirmDecision(candidate.id) },
                delete: { viewModel.deleteDecision(candidate.id) },
                edit: compact ? nil : { startEditingDecision(candidate) },
                restoreOriginal: compact || viewModel.analysisState.decisionCandidateEdits[candidate.id] == nil ? nil : {
                    viewModel.restoreOriginalDecision(candidate.id)
                    stopEditing()
                }
            )
        }
    }

    @ViewBuilder
    private func actionCandidateRow(_ candidate: ActionItemCandidate, compact: Bool) -> some View {
        if editingCandidate == EditingCandidate(kind: .action, id: candidate.id) {
            actionEditForm(candidate)
        } else {
            candidateRow(
                text: actionText(candidate),
                status: candidate.status,
                evidence: evidenceText(candidate.evidenceTimestamp, candidate.speaker),
                isEdited: viewModel.analysisState.actionItemCandidateEdits[candidate.id] != nil,
                confirm: { viewModel.confirmActionItem(candidate.id) },
                unconfirm: { viewModel.unconfirmActionItem(candidate.id) },
                delete: { viewModel.deleteActionItem(candidate.id) },
                edit: compact ? nil : { startEditingAction(candidate) },
                restoreOriginal: compact || viewModel.analysisState.actionItemCandidateEdits[candidate.id] == nil ? nil : {
                    viewModel.restoreOriginalActionItem(candidate.id)
                    stopEditing()
                }
            )
        }
    }

    private func candidateRow(
        text: String,
        status: CandidateStatus,
        evidence: String,
        isEdited: Bool,
        confirm: @escaping () -> Void,
        unconfirm: @escaping () -> Void,
        delete: @escaping () -> Void,
        edit: (() -> Void)?,
        restoreOriginal: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status == .confirmed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status == .confirmed ? Color.smoothAccent : Color.smoothMuted)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.smoothInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(evidence.isEmpty ? "evidence 없음" : evidence)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                if isEdited {
                    Label("수정됨", systemImage: "pencil")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.smoothAccent)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                if let edit {
                    Button(action: edit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("편집")
                }

                if let restoreOriginal {
                    Button(action: restoreOriginal) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("원문 복원")
                }

                Button {
                    if status == .confirmed {
                        unconfirm()
                    } else {
                        confirm()
                    }
                } label: {
                    Image(systemName: status == .confirmed ? "arrow.uturn.backward" : "checkmark")
                }
                .buttonStyle(.borderless)
                .help(status == .confirmed ? "confirm 취소" : "confirm")

                Button(action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("delete")
            }
        }
        .padding(9)
        .background(Color.smoothCanvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func copySectionButton(title: String, copiedID: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(copiedCandidateID == copiedID ? "복사됨" : title, systemImage: copiedCandidateID == copiedID ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(copiedCandidateID == copiedID ? Color.smoothOnAccent : Color.smoothInk)
        .background(copiedCandidateID == copiedID ? Color.smoothAccent : Color.smoothSurface, in: Capsule())
        .overlay(
            Capsule()
                .stroke(copiedCandidateID == copiedID ? Color.smoothAccent.opacity(0.45) : Color.smoothLine, lineWidth: 1)
        )
        .help(help)
    }

    private func copyDecisionCandidates(_ candidates: [DecisionCandidate]) {
        let text = candidates.map(\.text).joined(separator: "\n")
        copyCandidateText(text, id: "decisions-all")
    }

    private func copyActionCandidates(_ candidates: [ActionItemCandidate]) {
        let text = candidates.map(actionText).joined(separator: "\n")
        copyCandidateText(text, id: "actions-all")
    }

    private func copyCandidateText(_ text: String, id: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        copiedCandidateID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedCandidateID == id {
                copiedCandidateID = nil
            }
        }
    }

    private func decisionEditForm(_ candidate: DecisionCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("결정 문장 편집", systemImage: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothAccent)
            TextEditor(text: $decisionDraftText)
                .font(.callout)
                .frame(minHeight: 72)
                .padding(6)
                .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.smoothLine, lineWidth: 1))
            editFormActions(
                saveDisabled: decisionDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                save: {
                    viewModel.editDecision(candidate.id, text: decisionDraftText)
                    stopEditing()
                },
                cancel: stopEditing,
                restoreOriginal: viewModel.analysisState.decisionCandidateEdits[candidate.id] == nil ? nil : {
                    viewModel.restoreOriginalDecision(candidate.id)
                    stopEditing()
                }
            )
        }
        .padding(9)
        .background(Color.smoothCanvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionEditForm(_ candidate: ActionItemCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("액션 항목 편집", systemImage: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothAccent)
            LabeledContent("담당자") {
                TextField("명시된 담당자가 없으면 비워둠", text: $actionDraftAssignee)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("할 일") {
                TextField("액션 내용을 입력", text: $actionDraftTask)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("기한") {
                TextField("명시된 기한이 없으면 비워둠", text: $actionDraftDeadline)
                    .textFieldStyle(.roundedBorder)
            }
            editFormActions(
                saveDisabled: actionDraftTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                save: {
                    viewModel.editActionItem(
                        candidate.id,
                        assignee: actionDraftAssignee,
                        task: actionDraftTask,
                        deadline: actionDraftDeadline
                    )
                    stopEditing()
                },
                cancel: stopEditing,
                restoreOriginal: viewModel.analysisState.actionItemCandidateEdits[candidate.id] == nil ? nil : {
                    viewModel.restoreOriginalActionItem(candidate.id)
                    stopEditing()
                }
            )
        }
        .padding(9)
        .background(Color.smoothCanvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func editFormActions(
        saveDisabled: Bool,
        save: @escaping () -> Void,
        cancel: @escaping () -> Void,
        restoreOriginal: (() -> Void)?
    ) -> some View {
        HStack(spacing: 8) {
            Button("저장", action: save)
                .disabled(saveDisabled)
            Button("취소", action: cancel)
            if let restoreOriginal {
                Button("원문 복원", action: restoreOriginal)
            }
            Spacer()
        }
        .controlSize(.small)
    }

    private func actionText(_ candidate: ActionItemCandidate) -> String {
        var parts: [String] = []
        if let assignee = candidate.assignee, !assignee.isEmpty {
            parts.append("\(assignee):")
        }
        parts.append(candidate.task)
        if let deadline = candidate.deadline, !deadline.isEmpty {
            parts.append("(\(deadline))")
        }
        return parts.joined(separator: " ")
    }

    private func startEditingDecision(_ candidate: DecisionCandidate) {
        editingCandidate = EditingCandidate(kind: .decision, id: candidate.id)
        decisionDraftText = candidate.text
    }

    private func startEditingAction(_ candidate: ActionItemCandidate) {
        editingCandidate = EditingCandidate(kind: .action, id: candidate.id)
        actionDraftAssignee = candidate.assignee ?? ""
        actionDraftTask = candidate.task
        actionDraftDeadline = candidate.deadline ?? ""
    }

    private func stopEditing() {
        editingCandidate = nil
        decisionDraftText = ""
        actionDraftAssignee = ""
        actionDraftTask = ""
        actionDraftDeadline = ""
    }

    private func evidenceText(_ timestamp: String, _ speaker: String?) -> String {
        [
            MeetingTimestampFormatter.display(timestamp, meetingDateTime: viewModel.metadata.dateTime),
            speaker
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func summaryEvidenceText(_ evidence: EvidenceReference) -> String {
        let timestamp = MeetingTimestampFormatter.display(evidence.timestamp, meetingDateTime: viewModel.metadata.dateTime)
        let speaker = evidence.speaker.map { " · \($0)" } ?? ""
        let excerpt = evidence.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerptText = excerpt.isEmpty ? "" : " · \(excerpt)"
        return "\(timestamp)\(speaker)\(excerptText)"
    }

    private func timeRange(_ item: TopicTimelineItem) -> String {
        MeetingTimestampFormatter.displayRange(
            item.startTimestamp,
            endTimestamp: item.endTimestamp,
            meetingDateTime: viewModel.metadata.dateTime
        )
    }

    private func visibleDecisions(_ candidates: [DecisionCandidate]) -> [DecisionCandidate] {
        candidates.filter { $0.status != .deleted }
    }

    private func visibleActions(_ candidates: [ActionItemCandidate]) -> [ActionItemCandidate] {
        candidates.filter { $0.status != .deleted }
    }

    private var providerSummary: String {
        let provider = switch viewModel.selectedProvider {
        case .codexExec:
            viewModel.settings.codexExecutionMode == .cliExec ? "Codex" : "Codex App Server"
        case .claudeCode:
            "Claude"
        case .customCommand:
            "Custom"
        }
        return "\(provider) · \(viewModel.settings.modelPreset.displayName)"
    }

    private var headerActions: some View {
        ViewThatFits(in: .horizontal) {
            fullHeaderActions
            compactHeaderActions
            iconHeaderActions
        }
    }

    private var fullHeaderActions: some View {
        HStack(spacing: 8) {
            analysisHeaderButton
            issueDraftMenu
            markdownHeaderButton
            testRunHeaderActions
            liveHeaderAction
            settingsHeaderButton
            folderHeaderButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactHeaderActions: some View {
        HStack(spacing: 8) {
            analysisHeaderButton
            compactActionsMenu(label: "더보기", systemImage: "ellipsis.circle")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var iconHeaderActions: some View {
        HStack(spacing: 6) {
            headerIconButton("분석", systemImage: "sparkles") {
                viewModel.triggerManualAnalysis()
            }
            .disabled(viewModel.activeTranscriptURL == nil || viewModel.rawTranscript.isEmpty || viewModel.isAnalysisRunning)
            compactActionsMenu(label: "", systemImage: "ellipsis.circle")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var analysisHeaderButton: some View {
        headerButton("분석", systemImage: "sparkles") {
            viewModel.triggerManualAnalysis()
        }
        .disabled(viewModel.activeTranscriptURL == nil || viewModel.rawTranscript.isEmpty || viewModel.isAnalysisRunning)
    }

    @ViewBuilder
    private var momentMarkerMenuItems: some View {
        Button {
            viewModel.addLiveBookmark()
        } label: {
            Label("지금 표시", systemImage: "flag")
        }

        Button {
            viewModel.addLiveBookmark(label: "결정")
        } label: {
            Label("결정 시점", systemImage: "checkmark.seal")
        }

        Button {
            viewModel.addLiveBookmark(label: "액션")
        } label: {
            Label("액션 시점", systemImage: "person.crop.circle.badge.checkmark")
        }

        Button {
            viewModel.addLiveBookmark(label: "열린 질문")
        } label: {
            Label("미해결 질문", systemImage: "questionmark.circle")
        }
    }

    private var markdownHeaderButton: some View {
        headerButton("Markdown", systemImage: "square.and.arrow.down") {
            viewModel.requestCurrentIntelligenceMarkdownExport()
        }
        .disabled(viewModel.analysisState.latestSnapshot == nil)
    }

    private var settingsHeaderButton: some View {
        headerButton("설정", systemImage: "gearshape") {
            showingSettings = true
        }
    }

    private var folderHeaderButton: some View {
        headerButton("폴더", systemImage: "folder") {
            viewModel.chooseFolder()
        }
    }

    @ViewBuilder
    private var testRunHeaderActions: some View {
        if viewModel.isTestRunActive {
            headerButton(
                viewModel.testRunPlaybackStatus == .paused ? "재개" : "일시정지",
                systemImage: viewModel.testRunPlaybackStatus == .paused ? "play.fill" : "pause.fill"
            ) {
                viewModel.toggleTestRunPause()
            }
            .disabled(!viewModel.canPauseOrResumeTestRun)

            Menu {
                Button("1x") { viewModel.updateTestRunSpeed(1) }
                Button("2x") { viewModel.updateTestRunSpeed(2) }
                Button("4x") { viewModel.updateTestRunSpeed(4) }
                Button("8x") { viewModel.updateTestRunSpeed(8) }
            } label: {
                Label(viewModel.testRunSpeedText, systemImage: "speedometer")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .menuStyle(.button)
            .controlSize(.regular)

            headerButton("Live", systemImage: "dot.radiowaves.left.and.right") {
                viewModel.stopTestRunAndReturnToLive()
            }
        }
    }

    @ViewBuilder
    private var liveHeaderAction: some View {
        if viewModel.isHistoryMode || viewModel.liveMeetingUpdated {
            headerButton("Live", systemImage: "dot.radiowaves.left.and.right") {
                viewModel.returnToLiveWatch()
            }
            .disabled(viewModel.liveActiveTranscriptURL == nil && viewModel.selectedFolderURL == nil)
        }
    }

    private func compactActionsMenu(label: String, systemImage: String) -> some View {
        Menu {
            ForEach(GitHubIssueDraftKind.allCases) { kind in
                Button {
                    viewModel.openGitHubIssueDraft(kind: kind)
                } label: {
                    Label(kind.displayName, systemImage: kind.systemImage)
                }
            }

            Divider()

            Button {
                viewModel.requestCurrentIntelligenceMarkdownExport()
            } label: {
                Label("Markdown", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.analysisState.latestSnapshot == nil)

            if viewModel.isTestRunActive {
                Button {
                    viewModel.toggleTestRunPause()
                } label: {
                    Label(
                        viewModel.testRunPlaybackStatus == .paused ? "재개" : "일시정지",
                        systemImage: viewModel.testRunPlaybackStatus == .paused ? "play.fill" : "pause.fill"
                    )
                }
                .disabled(!viewModel.canPauseOrResumeTestRun)

                Menu("배속") {
                    Button("1x") { viewModel.updateTestRunSpeed(1) }
                    Button("2x") { viewModel.updateTestRunSpeed(2) }
                    Button("4x") { viewModel.updateTestRunSpeed(4) }
                    Button("8x") { viewModel.updateTestRunSpeed(8) }
                }

                Button {
                    viewModel.stopTestRunAndReturnToLive()
                } label: {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }
            }

            if viewModel.isHistoryMode || viewModel.liveMeetingUpdated {
                Button {
                    viewModel.returnToLiveWatch()
                } label: {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(viewModel.liveActiveTranscriptURL == nil && viewModel.selectedFolderURL == nil)
            }

            Divider()

            Button {
                showingSettings = true
            } label: {
                Label("설정", systemImage: "gearshape")
            }

            Button {
                viewModel.chooseFolder()
            } label: {
                Label("폴더", systemImage: "folder")
            }
        } label: {
            if label.isEmpty {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
            } else {
                Label(label, systemImage: systemImage)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .buttonStyle(SmoothActionButtonStyle())
        .menuStyle(.button)
        .controlSize(.regular)
        .help("추가 작업")
    }

    private var usageSummaryText: String {
        let summary = viewModel.analysisState.usageSummary
        guard summary.totalInputTokens + summary.totalOutputTokens > 0 else {
            return "-"
        }
        return "\(summary.totalInputTokens) in / \(summary.totalOutputTokens) out / \(String(format: "$%.4f", summary.totalEstimatedCostUSD))"
    }

    private func priceText(_ value: Double?) -> String {
        guard let value else {
            return "?"
        }
        return String(format: "%.2f", value)
    }

    private var statusIcon: String {
        switch viewModel.analysisStatus {
        case .idle:
            return "circle"
        case .running:
            return "sparkles"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .stale:
            return "clock.badge.exclamationmark"
        }
    }

    private var statusTint: Color {
        switch viewModel.analysisStatus {
        case .idle:
            return Color.smoothMuted
        case .running:
            return Color.smoothAccent
        case .completed:
            return .green
        case .failed:
            return .orange
        case .stale:
            return .yellow
        }
    }

    private func headerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(SmoothActionButtonStyle())
        .controlSize(.regular)
    }

    private func headerIconButton(_ help: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(SmoothActionButtonStyle())
        .controlSize(.regular)
        .help(help)
    }

    private var issueDraftMenu: some View {
        Menu {
            ForEach(GitHubIssueDraftKind.allCases) { kind in
                Button {
                    viewModel.openGitHubIssueDraft(kind: kind)
                } label: {
                    Label(kind.displayName, systemImage: kind.systemImage)
                }
            }
        } label: {
            Label("이슈", systemImage: "exclamationmark.bubble")
                .font(.callout.weight(.semibold))
        }
        .buttonStyle(SmoothActionButtonStyle())
        .menuStyle(.button)
        .controlSize(.regular)
        .help("GitHub issue 작성 화면을 브라우저로 열기")
    }

    private func dismissBlockingSheetsForUpdate() {
        showingSettings = false
        selectedAnalysisAttempt = nil
        if viewModel.isShowingOnboarding {
            viewModel.completeOnboarding()
        }
    }

    private var statusChipRows: some View {
        ViewThatFits(in: .horizontal) {
            statusChipRow(.full)
            statusChipRow(.medium)
            statusChipRow(.compact)
        }
    }

    private enum StatusChipDensity {
        case full
        case medium
        case compact
    }

    @ViewBuilder
    private func statusChipRow(_ density: StatusChipDensity) -> some View {
        HStack(spacing: 8) {
            statusChip("mode", viewModel.transcriptRunMode.displayText, systemImage: "switch.2")
            if viewModel.isTestRunActive {
                statusChip(viewModel.testRunPlaybackStatus.displayText, viewModel.testRunProgressText, systemImage: "play.circle")
            }
            if viewModel.liveMeetingUpdated {
                statusChip("live", "updated", systemImage: "bell.badge")
            }
            statusChip("상태", viewModel.analysisStatus.displayText, systemImage: statusIcon)
            if density != .compact {
                statusChip("다음 분석", viewModel.nextAutomaticAnalysisSummary, systemImage: "timer")
                statusChip("provider", providerSummary, systemImage: "cpu")
            }
            if density == .full {
                if viewModel.isTestRunActive {
                    statusChip("speed", viewModel.testRunSpeedText, systemImage: "speedometer")
                }
                statusChip("usage", usageSummaryText, systemImage: "chart.bar.doc.horizontal")
                statusChip("업데이트", viewModel.transcriptUpdatedAt?.formatted(date: .omitted, time: .standard) ?? "-", systemImage: "clock")
                statusChip("lines", "\(viewModel.rawTranscriptLineCount)", systemImage: "text.alignleft")
            }
        }
    }

    private func statusChip(_ label: String, _ value: String, systemImage: String) -> some View {
        Label {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(Color.smoothMuted)
                Text(value)
                    .foregroundStyle(Color.smoothInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.smoothAccent)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.smoothSurface, in: Capsule())
        .overlay(Capsule().stroke(Color.smoothLine, lineWidth: 1))
        .frame(maxWidth: 260, alignment: .leading)
    }

    private func paneTitle(
        _ text: String,
        systemImage: String,
        trailing: String? = nil,
        compact: Bool = false,
        collapsePane: AdaptivePane? = nil
    ) -> some View {
        HStack {
            Label(text, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.smoothInk)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
            }
            if let collapsePane {
                Button {
                    collapse(collapsePane)
                } label: {
                    Image(systemName: collapsePane == .meetings ? "sidebar.left" : "sidebar.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.smoothMuted)
                        .frame(width: 24, height: 24)
                        .background(Color.smoothControl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("\(collapsePane.title) 접기")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 11 : 12)
    }

    private var overlayPaneToggleBar: some View {
        HStack(spacing: 8) {
            overlayPaneToggle(.meetings)
            overlayPaneToggle(.intelligence)
            Spacer(minLength: 0)
            Text("Raw Transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func overlayPaneToggle(_ pane: AdaptivePane) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                activeOverlayPane = activeOverlayPane == pane ? nil : pane
            }
        } label: {
            Label(pane.title, systemImage: pane.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(activeOverlayPane == pane ? Color.smoothOnAccent : Color.smoothInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    activeOverlayPane == pane ? Color.smoothAccent : Color.smoothControl,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help("\(pane.title) 열기")
    }

    private func overlayDrawer(_ pane: AdaptivePane, availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if pane == .intelligence {
                Spacer(minLength: 0)
            }

            overlayDrawerContent(pane, availableWidth: overlayDrawerWidth(for: availableWidth, pane: pane))
                .frame(
                    minWidth: overlayDrawerWidth(for: availableWidth, pane: pane),
                    idealWidth: overlayDrawerWidth(for: availableWidth, pane: pane),
                    maxWidth: overlayDrawerWidth(for: availableWidth, pane: pane),
                    maxHeight: .infinity
                )
                .transition(.move(edge: pane == .meetings ? .leading : .trailing).combined(with: .opacity))
                .shadow(color: Color.black.opacity(0.16), radius: 18, y: 8)

            if pane == .meetings {
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func overlayDrawerContent(_ pane: AdaptivePane, availableWidth: CGFloat) -> some View {
        switch pane {
        case .meetings:
            historySidebar
        case .intelligence:
            intelligenceContent(compact: true, availableWidth: availableWidth)
        }
    }

    private func overlayDrawerWidth(for availableWidth: CGFloat, pane: AdaptivePane) -> CGFloat {
        let maximumWidth: CGFloat = pane == .intelligence ? 520 : 430
        return min(maximumWidth, max(300, availableWidth - 20))
    }

    private func collapsedPaneRail(_ pane: AdaptivePane) -> some View {
        Button {
            expand(pane)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: pane.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.smoothAccent)
                    .frame(width: 30, height: 30)
                    .background(Color.smoothMint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(pane.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.smoothInk)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 30, height: 82)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
        .help("\(pane.title) 펼치기")
    }

    private func collapse(_ pane: AdaptivePane) {
        withAnimation(.easeInOut(duration: 0.16)) {
            manuallyCollapsedPanes.insert(pane)
            if activeOverlayPane == pane {
                activeOverlayPane = nil
            }
        }
    }

    private func expand(_ pane: AdaptivePane) {
        withAnimation(.easeInOut(duration: 0.16)) {
            _ = manuallyCollapsedPanes.remove(pane)
        }
    }

    private func sectionHeader(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.smoothAccent)
            Text(text)
                .font(.headline)
                .foregroundStyle(Color.smoothInk)
            Spacer()
        }
    }

    private func placeholderLine(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Color.smoothMuted)
            .padding(.vertical, 4)
    }

    private func metadataRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)
            Text(value)
                .fontDesign(monospaced ? .monospaced : .default)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Color.smoothInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func participantMetadataRow(participants: [String], speakers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("참석자")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)

            if participants.isEmpty && speakers.isEmpty {
                Text("-")
                    .foregroundStyle(Color.smoothInk)
            } else {
                Button {
                    isParticipantsPopoverPresented.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text(participantMetadataSummary(participants: participants, speakers: speakers))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.smoothMuted)
                    }
                    .foregroundStyle(Color.smoothInk)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isParticipantsPopoverPresented, arrowEdge: .bottom) {
                    participantsPopover(participants: participants, speakers: speakers)
                }
                .help("발화자와 참석자 전체 목록 보기")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func participantMetadataSummary(participants: [String], speakers: [String]) -> String {
        if !speakers.isEmpty {
            let participantText = participants.isEmpty ? "참석자 없음" : "참석자 \(participants.count)명"
            return "\(peopleSummary(speakers)) 발화 · \(participantText)"
        }
        guard !participants.isEmpty else {
            return "-"
        }
        return peopleSummary(participants)
    }

    private func peopleSummary(_ people: [String]) -> String {
        guard let first = people.first else {
            return "-"
        }
        let remainingCount = people.count - 1
        guard remainingCount > 0 else {
            return first
        }
        return "\(first) 외 \(remainingCount)명"
    }

    private func participantsPopover(participants: [String], speakers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("회의 인원")
                    .font(.headline)
                    .foregroundStyle(Color.smoothInk)
                Spacer()
                Text("발화자 \(speakers.count)명 · 참석자 \(participants.count)명")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.smoothMuted)
            }

            Divider().overlay(Color.smoothLine)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    participantPopoverSection(
                        title: "발화자",
                        count: speakers.count,
                        people: speakers,
                        emptyText: "아직 감지된 발화자가 없습니다."
                    )
                    participantPopoverSection(
                        title: "참석자",
                        count: participants.count,
                        people: participants,
                        emptyText: "회의록 metadata에 참석자 목록이 없습니다."
                    )
                }
            }
            .frame(maxHeight: 340)
        }
        .padding(16)
        .frame(width: 360)
        .background(Color.smoothCanvas)
    }

    private func participantPopoverSection(
        title: String,
        count: Int,
        people: [String],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.smoothAccent)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.smoothMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.smoothSurface, in: Capsule())
                Spacer()
            }

            if people.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                        Label(person, systemImage: "person.crop.circle")
                            .font(.callout)
                            .foregroundStyle(Color.smoothInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func emptyState(_ title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .foregroundStyle(Color.smoothMuted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var sparkleUpdater: SparkleUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var showingReleaseNotes = false
    @State private var selectedSection: SettingsSection = .llm
    @State private var isPricingReferenceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHeader
            settingsSectionPicker

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    selectedSettingsSection
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .buttonStyle(SmoothActionButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 620)
        .background(Color.smoothCanvas)
        .sheet(isPresented: $showingReleaseNotes) {
            ReleaseNotesView()
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("설정")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                Text(settingsSubtitle)
                    .font(.callout)
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                dismiss()
                Task { @MainActor in
                    viewModel.showOnboarding()
                }
            } label: {
                Label("온보딩", systemImage: "questionmark.circle")
            }
            .buttonStyle(SmoothActionButtonStyle())
        }
    }

    private var settingsSubtitle: String {
        switch selectedSection {
        case .llm:
            return "provider, model preset, execution mode를 조정합니다."
        case .analysis:
            return "자동 분석, trigger, timeout, context retrieval을 조정합니다."
        case .app:
            return "폴더, 업데이트, 릴리즈 노트, onboarding을 관리합니다."
        case .danger:
            return "현재 회의 상태나 선택 폴더 저장값을 지웁니다."
        }
    }

    private var settingsSectionPicker: some View {
        Picker("설정 섹션", selection: $selectedSection) {
            ForEach(SettingsSection.allCases) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var selectedSettingsSection: some View {
        switch selectedSection {
        case .llm:
            llmSettings
        case .analysis:
            analysisSettings
        case .app:
            appSettings
        case .danger:
            dangerSettings
        }
    }

    private var llmSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard("Provider", systemImage: "cpu") {
                settingsRow("LLM provider") {
                    Picker("LLM provider", selection: providerBinding) {
                        ForEach(LLMProviderKind.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }

                if viewModel.settings.selectedProvider == .codexExec {
                    settingsRow("Codex execution", detail: viewModel.settings.codexExecutionMode.detail) {
                        Picker("Codex execution", selection: codexExecutionModeBinding) {
                            ForEach(CodexExecutionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }

                    if viewModel.settings.codexExecutionMode == .appServerExperimental {
                        settingsRow("Diagnostics", detail: "Run trace에 app-server event timing을 더 자세히 기록합니다.") {
                            Toggle("app-server diagnostics", isOn: codexAppServerDiagnosticsBinding)
                                .labelsHidden()
                        }
                    }
                }

                settingsRow("Model preset", detail: viewModel.settings.modelPreset.detail) {
                    Picker("model preset", selection: modelPresetBinding) {
                        ForEach(LLMModelPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                settingsRow("Custom command") {
                    TextField("custom command", text: customCommandBinding)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.settings.selectedProvider != .customCommand)
                        .frame(width: 320)
                }
            }

            pricingReference
        }
    }

    private var analysisSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            meetingIntelligenceSettingsCard
            googleCalendarSettingsCard
        }
    }

    private var meetingIntelligenceSettingsCard: some View {
        settingsCard("Meeting Intelligence", systemImage: "sparkles") {
            settingsRow("Automatic analysis", detail: "끄면 live/test run 자동 분석과 회의 종료 final analysis를 실행하지 않습니다.") {
                Toggle("automatic meeting intelligence", isOn: automaticAnalysisBinding)
                    .labelsHidden()
            }

            settingsRow("Analysis trigger", detail: viewModel.settings.analysisTriggerPreset.detail) {
                Picker("analysis trigger", selection: analysisTriggerPresetBinding) {
                    ForEach(AnalysisTriggerPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .disabled(!viewModel.settings.automaticAnalysisEnabled)
                .frame(width: 180)
            }

            settingsRow("Meeting type", detail: viewModel.settings.meetingTypePreset.detail) {
                Picker("meeting type", selection: meetingTypePresetBinding) {
                    ForEach(MeetingTypePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            settingsRow("Provider timeout", detail: "수동 분석과 final analysis는 최소 180초 timeout을 사용합니다.") {
                Stepper("\(viewModel.settings.providerTimeoutSeconds)초", value: timeoutBinding, in: 10...300)
                    .frame(width: 160)
            }

            settingsRow("Live context retrieval", detail: viewModel.settings.liveContextRetrievalMode.detail) {
                Picker("live context retrieval", selection: liveContextRetrievalModeBinding) {
                    ForEach(LiveContextRetrievalMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
        }
    }

    private var googleCalendarSettingsCard: some View {
        settingsCard("Google Calendar", systemImage: "calendar.badge.clock") {
            actionRow("연결 상태", detail: viewModel.googleCalendarStatusMessage) {
                googleCalendarSettingsActions
            }
        }
    }

    private var googleCalendarSettingsActions: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.connectGoogleCalendar()
            } label: {
                Label(viewModel.isGoogleCalendarConnecting ? "연결 중" : "연결", systemImage: "link")
            }
            .buttonStyle(SmoothActionButtonStyle())
            .disabled(viewModel.isGoogleCalendarConnecting)

            Button {
                viewModel.fetchGoogleCalendarAPIContext()
            } label: {
                Label(viewModel.isFetchingGoogleCalendarAPIContext ? "가져오는 중" : "가져오기", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SmoothActionButtonStyle())
            .disabled(viewModel.isFetchingGoogleCalendarAPIContext || viewModel.activeTranscriptURL == nil)

            Button {
                viewModel.disconnectGoogleCalendar()
            } label: {
                Label("해제", systemImage: "xmark.circle")
            }
            .buttonStyle(SmoothActionButtonStyle())
        }
    }

    private var appSettings: some View {
        settingsCard("App", systemImage: "macwindow") {
            actionRow(
                "Recordings folder",
                detail: viewModel.selectedFolderURL?.path(percentEncoded: false) ?? "선택된 폴더 없음"
            ) {
                Button {
                    viewModel.chooseFolder()
                } label: {
                    Label("변경", systemImage: "folder")
                }
                .buttonStyle(SmoothActionButtonStyle())
            }

            actionRow("Update", detail: "Sparkle update feed에서 새 버전을 확인합니다.") {
                Button {
                    dismiss()
                    sparkleUpdater.checkForUpdates()
                } label: {
                    Label("확인", systemImage: "arrow.down.circle")
                }
                .buttonStyle(SmoothActionButtonStyle())
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }

            actionRow("Release notes", detail: "현재 버전과 최신 릴리즈 노트를 앱 안에서 확인합니다.") {
                Button {
                    showingReleaseNotes = true
                } label: {
                    Label("보기", systemImage: "doc.text")
                }
                .buttonStyle(SmoothActionButtonStyle())
            }

            actionRow("Onboarding", detail: "처음 사용 흐름과 주요 버튼 설명을 다시 봅니다.") {
                Button {
                    dismiss()
                    Task { @MainActor in
                        viewModel.showOnboarding()
                    }
                } label: {
                    Label("다시 보기", systemImage: "questionmark.circle")
                }
                .buttonStyle(SmoothActionButtonStyle())
            }
        }
    }

    private var dangerSettings: some View {
        settingsCard("Danger Zone", systemImage: "exclamationmark.triangle") {
            actionRow("Current meeting state", detail: "현재 active meeting의 analysis snapshot, 후보 상태, 실행 로그를 지웁니다.") {
                Button(role: .destructive) {
                    viewModel.clearCurrentAnalysisState()
                } label: {
                    Label("지우기", systemImage: "eraser")
                }
                .buttonStyle(SmoothActionButtonStyle(kind: .destructive))
                .disabled(viewModel.activeTranscriptURL == nil)
            }

            actionRow("Selected folder", detail: "저장된 Recordings folder bookmark를 잊습니다.") {
                Button(role: .destructive) {
                    viewModel.forgetSelectedFolder()
                } label: {
                    Label("잊기", systemImage: "xmark.circle")
                }
                .buttonStyle(SmoothActionButtonStyle(kind: .destructive))
                .disabled(viewModel.selectedFolderURL == nil)
            }
        }
    }

    private func settingsCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.smoothAccent)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.smoothInk)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func settingsRow<Control: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                    .frame(width: 150, alignment: .leading)
                Spacer(minLength: 12)
                control()
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 164)
            }
        }
        .padding(.vertical, 9)
    }

    private func actionRow<Action: View>(_ title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 16)
            action()
        }
        .padding(.vertical, 9)
    }

    private var providerBinding: Binding<LLMProviderKind> {
        Binding {
            viewModel.settings.selectedProvider
        } set: { value in
            viewModel.updateProvider(value)
        }
    }

    private var codexExecutionModeBinding: Binding<CodexExecutionMode> {
        Binding {
            viewModel.settings.codexExecutionMode
        } set: { value in
            viewModel.updateCodexExecutionMode(value)
        }
    }

    private var codexAppServerDiagnosticsBinding: Binding<Bool> {
        Binding {
            viewModel.settings.codexAppServerDiagnosticsEnabled
        } set: { value in
            viewModel.setCodexAppServerDiagnosticsEnabled(value)
        }
    }

    private var modelPresetBinding: Binding<LLMModelPreset> {
        Binding {
            viewModel.settings.modelPreset
        } set: { value in
            viewModel.updateModelPreset(value)
        }
    }

    private var meetingTypePresetBinding: Binding<MeetingTypePreset> {
        Binding {
            viewModel.settings.meetingTypePreset
        } set: { value in
            viewModel.updateMeetingTypePreset(value)
        }
    }

    private var analysisTriggerPresetBinding: Binding<AnalysisTriggerPreset> {
        Binding {
            viewModel.settings.analysisTriggerPreset
        } set: { value in
            viewModel.updateAnalysisTriggerPreset(value)
        }
    }

    private var automaticAnalysisBinding: Binding<Bool> {
        Binding {
            viewModel.settings.automaticAnalysisEnabled
        } set: { value in
            viewModel.setAutomaticAnalysisEnabled(value)
        }
    }

    private var liveContextRetrievalModeBinding: Binding<LiveContextRetrievalMode> {
        Binding {
            viewModel.settings.liveContextRetrievalMode
        } set: { value in
            viewModel.updateLiveContextRetrievalMode(value)
        }
    }

    private var timeoutBinding: Binding<Int> {
        Binding {
            viewModel.settings.providerTimeoutSeconds
        } set: { value in
            viewModel.settings.providerTimeoutSeconds = value
            viewModel.saveSettings()
        }
    }

    private var customCommandBinding: Binding<String> {
        Binding {
            viewModel.settings.customProviderCommand
        } set: { value in
            viewModel.settings.customProviderCommand = value
            viewModel.saveSettings()
        }
    }

    private var pricingReference: some View {
        DisclosureGroup(isExpanded: $isPricingReferenceExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(LLMUsagePricing.referencePrices, id: \.modelName) { price in
                    HStack {
                        Text("\(price.providerLabel) · \(price.modelName)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("in $\(priceString(price.inputPerMillionUSD)) / out $\(priceString(price.outputPerMillionUSD)) per 1M")
                            .fontDesign(.monospaced)
                            .foregroundStyle(Color.smoothMuted)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("가격 reference", systemImage: "dollarsign.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)
        }
        .padding(12)
        .background(Color.smoothSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func priceString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private enum ReleaseNotesSource: String, CaseIterable, Identifiable {
    case current = "현재 버전"
    case latest = "최신"

    var id: String { rawValue }
}

private enum ReleaseNoteBlock: Identifiable {
    case heading(level: Int, text: String)
    case bullet(String)
    case paragraph(String)
    case divider

    var id: String {
        switch self {
        case let .heading(level, text):
            return "heading-\(level)-\(text)"
        case let .bullet(text):
            return "bullet-\(text)"
        case let .paragraph(text):
            return "paragraph-\(text)"
        case .divider:
            return "divider"
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case llm = "LLM"
    case analysis = "Analysis"
    case app = "App"
    case danger = "Danger"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .llm:
            return "cpu"
        case .analysis:
            return "sparkles"
        case .app:
            return "macwindow"
        case .danger:
            return "exclamationmark.triangle"
        }
    }
}

struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSource: ReleaseNotesSource = .current
    @State private var latestReleaseNotes: String?
    @State private var latestLoadMessage: String?
    @State private var isLoadingLatest = false

    private var currentReleaseNotes: String {
        Self.loadBundledReleaseNotes()
    }

    private var displayedReleaseNotes: String {
        switch selectedSource {
        case .current:
            currentReleaseNotes
        case .latest:
            latestReleaseNotes ?? latestLoadMessage ?? "최신 릴리즈 노트를 불러오는 중입니다."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("릴리즈 노트")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.smoothInk)
                    Text(AppVersion.displayTitle)
                        .font(.callout)
                        .foregroundStyle(Color.smoothMuted)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("닫기", systemImage: "xmark")
                }
                .buttonStyle(SmoothActionButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            Picker("릴리즈 노트", selection: $selectedSource) {
                ForEach(ReleaseNotesSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)

            if selectedSource == .latest, isLoadingLatest {
                ProgressView("최신 릴리즈 노트를 확인하는 중")
                    .font(.callout)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(releaseNoteBlocks(displayedReleaseNotes).enumerated()), id: \.offset) { _, block in
                        releaseNoteBlockView(block)
                    }
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
        }
        .padding(24)
        .frame(width: 640, height: 560)
        .background(Color.smoothCanvas)
        .task {
            await loadLatestReleaseNotesIfNeeded()
        }
    }

    @ViewBuilder
    private func releaseNoteBlockView(_ block: ReleaseNoteBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(text)
                .font(level == 1 ? .title3.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(Color.smoothInk)
                .padding(.top, level == 1 ? 0 : 8)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.smoothAccent)
                    .padding(.top, 1)
                Text(inlineMarkdown(text))
                    .font(.body)
                    .foregroundStyle(Color.smoothInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.body)
                .foregroundStyle(Color.smoothInk)
                .fixedSize(horizontal: false, vertical: true)
        case .divider:
            Divider()
                .overlay(Color.smoothLine)
                .padding(.vertical, 4)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func releaseNoteBlocks(_ markdown: String) -> [ReleaseNoteBlock] {
        var blocks: [ReleaseNoteBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let text = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if line == "---" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
                continue
            }

            if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks
    }

    @MainActor
    private func loadLatestReleaseNotesIfNeeded() async {
        guard latestReleaseNotes == nil, latestLoadMessage == nil, !isLoadingLatest else {
            return
        }
        guard let url = Self.latestReleaseNotesURL() else {
            latestLoadMessage = "최신 릴리즈 노트 URL을 찾을 수 없습니다."
            return
        }

        isLoadingLatest = true
        defer { isLoadingLatest = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                latestLoadMessage = """
                # 최신 릴리즈 노트를 아직 찾을 수 없습니다

                GitHub Pages에 `docs/releases/latest.md`가 배포되기 전이면 HTTP \(httpResponse.statusCode)가 표시될 수 있습니다. 아래는 현재 앱에 포함된 릴리즈 노트입니다.

                ---

                \(currentReleaseNotes)
                """
                return
            }
            guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                latestLoadMessage = "최신 릴리즈 노트가 비어 있습니다."
                return
            }
            latestReleaseNotes = text
        } catch {
            latestLoadMessage = """
            # 최신 릴리즈 노트를 불러오지 못했습니다

            \(error.localizedDescription)

            아래는 현재 앱에 포함된 릴리즈 노트입니다.

            ---

            \(currentReleaseNotes)
            """
        }
    }

    private static func loadBundledReleaseNotes() -> String {
        for url in bundledReleaseNotesCandidates() {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        return "# \(AppVersion.displayTitle)\n\n릴리즈 노트를 찾을 수 없습니다."
    }

    private static func bundledReleaseNotesCandidates() -> [URL] {
        let bundledPath = "MeetingRescue_MeetingRescue.bundle/Resources/ReleaseNotes.md"
        return [
            Bundle.main.resourceURL?.appendingPathComponent(bundledPath),
            Bundle.main.bundleURL.appendingPathComponent(bundledPath),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundledPath),
            Bundle.main.resourceURL?.appendingPathComponent("ReleaseNotes.md"),
            Bundle.main.bundleURL.appendingPathComponent("ReleaseNotes.md")
        ].compactMap { $0 }
    }

    private static func latestReleaseNotesURL() -> URL? {
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString) else {
            return URL(string: "https://breadceo.github.io/meeting-rescue/releases/latest.md")
        }
        return feedURL
            .deletingLastPathComponent()
            .appendingPathComponent("releases")
            .appendingPathComponent("latest.md")
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meeting Rescue 시작")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.smoothInk)
                    Text("회의록 폴더, LLM provider, 기본 화면 구조를 한 번만 확인합니다.")
                        .font(.callout)
                        .foregroundStyle(Color.smoothMuted)
                }
                Spacer()
                Button {
                    viewModel.completeOnboarding()
                } label: {
                    Label("닫기", systemImage: "xmark")
                }
                .buttonStyle(SmoothActionButtonStyle())
            }

            VStack(alignment: .leading, spacing: 12) {
                onboardingSectionTitle("1. Recordings folder", systemImage: "folder")
                if let detected = viewModel.detectedSomaRecordingsFolder {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detected.url.path)
                            .font(.callout.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .foregroundStyle(Color.smoothInk)
                        Text(detected.sourceDescription)
                            .font(.caption)
                            .foregroundStyle(Color.smoothMuted)
                        HStack {
                            Button {
                                viewModel.chooseDetectedSomaRecordingsFolder()
                            } label: {
                                Label("감지된 폴더 확인", systemImage: "checkmark.seal")
                            }
                            .buttonStyle(SmoothActionButtonStyle(kind: .primary))

                            Button {
                                viewModel.chooseFolder()
                            } label: {
                                Label("직접 선택", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(SmoothActionButtonStyle())
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Soma 설정에서 `CustomChatLogDirectory`를 찾지 못했습니다.")
                            .font(.callout)
                            .foregroundStyle(Color.smoothMuted)
                        Button {
                            viewModel.chooseFolder()
                        } label: {
                            Label("직접 선택", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(SmoothActionButtonStyle(kind: .primary))
                    }
                }
                if let selectedFolderURL = viewModel.selectedFolderURL {
                    Label(selectedFolderURL.path, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.smoothAccent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .onboardingCard()

            VStack(alignment: .leading, spacing: 12) {
                onboardingSectionTitle("2. LLM provider", systemImage: "cpu")
                HStack(spacing: 10) {
                    providerBadge("Codex", isAvailable: viewModel.providerAvailability.isCodexAvailable)
                    providerBadge("Claude Code", isAvailable: viewModel.providerAvailability.isClaudeCodeAvailable)
                    Spacer()
                }
                Picker("provider", selection: providerBinding) {
                    ForEach(LLMProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Toggle("automatic Meeting Intelligence", isOn: automaticAnalysisBinding)
                if !viewModel.providerAvailability.hasSubscriptionProvider {
                    Text("Codex와 Claude Code를 찾지 못해 자동 Meeting Intelligence를 꺼둔 상태로 시작합니다.")
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                }
            }
            .onboardingCard()

            VStack(alignment: .leading, spacing: 12) {
                onboardingSectionTitle("3. 화면 구조", systemImage: "rectangle.3.group")
                onboardingHelpRow("Meetings", "live meeting, test run, meeting search/history를 다룹니다.", systemImage: "sidebar.left")
                onboardingHelpRow("Raw Transcript", "선택한 회의록 원문을 시간순으로 확인하고 citation 위치로 이동합니다.", systemImage: "doc.text")
                onboardingHelpRow("Meeting Intelligence", "요약, 흐름, 결정 후보, 액션 후보, 실행 로그를 확인합니다.", systemImage: "sparkles")
                Divider().overlay(Color.smoothLine)
                onboardingHelpRow("상단 버튼", "분석, Markdown, 일시정지, Live, 설정, 폴더는 현재 회의의 주요 작업입니다.", systemImage: "slider.horizontal.3")
            }
            .onboardingCard()

            HStack {
                Spacer()
                Button {
                    viewModel.completeOnboarding()
                } label: {
                    Label("시작", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(SmoothActionButtonStyle(kind: .primary))
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Color.smoothCanvas)
    }

    private var providerBinding: Binding<LLMProviderKind> {
        Binding {
            viewModel.settings.selectedProvider
        } set: { value in
            viewModel.updateProvider(value)
        }
    }

    private var automaticAnalysisBinding: Binding<Bool> {
        Binding {
            viewModel.settings.automaticAnalysisEnabled
        } set: { value in
            viewModel.setAutomaticAnalysisEnabled(value)
        }
    }

    private func onboardingSectionTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.smoothAccent)
            Text(text)
                .font(.headline)
                .foregroundStyle(Color.smoothInk)
        }
    }

    private func providerBadge(_ label: String, isAvailable: Bool) -> some View {
        Label(isAvailable ? "\(label) 확인됨" : "\(label) 없음", systemImage: isAvailable ? "checkmark.circle.fill" : "minus.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isAvailable ? Color.smoothAccent : Color.smoothMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.smoothSurface.opacity(0.75), in: Capsule())
    }

    private func onboardingHelpRow(_ title: String, _ description: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.smoothAccent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.smoothInk)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    func onboardingCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.smoothSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
    }
}

private struct AnalysisAttemptDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSummaryExpanded = true
    @State private var isBatchExpanded = true
    @State private var isContextExpanded = true
    @State private var isMessageExpanded = true
    @State private var isTraceExpanded = false
    @State private var isPromptExpanded = true
    @State private var isOutputExpanded = true

    let attempt: AnalysisAttemptLog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .background(Color.smoothCanvas)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    collapsibleSection(
                        title: "Summary",
                        subtitle: "\(attempt.inputTokens) in · \(attempt.outputTokens) out · \(attempt.elapsedMilliseconds.map { "\($0)ms" } ?? "running")",
                        isExpanded: $isSummaryExpanded
                    ) {
                        metricGrid {
                            detailMetric("\(attempt.inputTokens)", "input tokens")
                            detailMetric("\(attempt.outputTokens)", "output tokens")
                            detailMetric(attempt.elapsedMilliseconds.map { "\($0)ms" } ?? "running", "duration")
                            detailMetric(attempt.modelPreset.displayName, "preset")
                            detailMetric(attempt.executionProviderDisplayName, "provider")
                        }
                    }

                    if let stats = attempt.batchStats {
                        collapsibleSection(
                            title: "Batch",
                            subtitle: stats.compactSummary,
                            isExpanded: $isBatchExpanded
                        ) {
                            metricGrid {
                                detailMetric("\(stats.newDialogueLines)", "new lines")
                                detailMetric("\(stats.newTranscriptCharacters)", "new chars")
                                detailMetric("\(stats.includedDialogueLines)", "included lines")
                                detailMetric("\(stats.includedTranscriptCharacters)", "included chars")
                                detailMetric(stats.triggerReason, "trigger")
                            }
                        }
                    }

                    if let contextPlan = attempt.contextPlan {
                        collapsibleSection(
                            title: "Context Plan",
                            subtitle: contextPlanSubtitle(contextPlan),
                            isExpanded: $isContextExpanded
                        ) {
                            contextPlanContent(contextPlan)
                        }
                    }

                    if let message = attempt.message, !message.isEmpty {
                        collapsibleSection(
                            title: "Message",
                            subtitle: message,
                            isExpanded: $isMessageExpanded
                        ) {
                            messageView(message)
                        }
                    }

                    if let trace = attempt.runTrace {
                        collapsibleSection(
                            title: "Run Trace",
                            subtitle: runTraceSubtitle(trace),
                            isExpanded: $isTraceExpanded
                        ) {
                            runTraceContent(trace)
                        }
                    }

                    HSplitView {
                        collapsibleSection(
                            title: "Prompt",
                            subtitle: "\(attempt.prompt?.count ?? 0)자",
                            isExpanded: $isPromptExpanded
                        ) {
                            detailTextPanel(text: attempt.prompt ?? "저장된 prompt가 없습니다. 이 버전 이후 실행부터 기록됩니다.")
                                .frame(minHeight: 340, maxHeight: .infinity)
                        }
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                        collapsibleSection(
                            title: "Provider Output",
                            subtitle: "\(attempt.providerOutput?.count ?? 0)자",
                            isExpanded: $isOutputExpanded
                        ) {
                            detailTextPanel(text: attempt.providerOutput ?? "저장된 provider output이 없습니다. 성공한 run은 이 버전 이후 raw JSON output을 기록합니다.")
                                .frame(minHeight: 340, maxHeight: .infinity)
                        }
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(minHeight: 380)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Color.smoothCanvas)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Analysis 실행 상세")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.smoothInk)
                Text("\(attempt.reason) · \(attempt.status.rawValue) · \(attempt.executionProviderDisplayName) · \(attempt.modelName)")
                    .font(.callout)
                    .foregroundStyle(Color.smoothMuted)
            }
            Spacer()
            HStack(spacing: 8) {
                Text(attempt.completedAt?.formatted(date: .numeric, time: .standard) ?? "running")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.smoothCanvas, in: Capsule())

                Button {
                    dismiss()
                } label: {
                    Label("닫기", systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(SmoothActionButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("상세 화면 닫기")
            }
        }
    }

    private func collapsibleSection<Content: View>(
        title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
                .padding(.top, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.smoothAccent)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .padding(10)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func metricGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
            alignment: .leading,
            spacing: 8,
            content: content
        )
    }

    private func runTraceContent(_ trace: AnalysisRunTrace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(trace.providerExecutable) \(trace.argumentsSummary)")
                .font(.caption.monospaced())
                .foregroundStyle(Color.smoothMuted)
                .lineLimit(2)
                .truncationMode(.middle)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(trace.events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("+\(event.startedAtMilliseconds)ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.smoothMuted)
                            .frame(width: 74, alignment: .trailing)
                        Text(event.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.smoothInk)
                        Text(event.durationMilliseconds.map { "\($0)ms" } ?? "")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.smoothAccent)
                        if let detail = event.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(Color.smoothMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func runTraceSubtitle(_ trace: AnalysisRunTrace) -> String {
        let process = trace.events.first(where: { $0.name == "app-server process" })?.detail
        let thread = trace.events.first(where: { $0.name == "thread/start" })?.detail?.split(separator: " ").first.map(String.init)
        let firstDelta = trace.events.first(where: { $0.name == "first delta latency" })?.durationMilliseconds
        return [
            process.map { "process \($0)" },
            thread.map { "thread \($0)" },
            firstDelta.map { "first delta \($0)ms" },
            "stdout \(trace.outputBytes)B",
            "stderr \(trace.stderrBytes)B",
            "exit \(trace.exitCode.map(String.init) ?? "-")"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func detailMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.smoothInk)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.smoothMuted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func contextPlanContent(_ plan: AnalysisContextPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metricGrid {
                detailMetric(plan.retrievalMode.displayName, "retrieval mode")
                detailMetric("\(plan.retrievalTopK)", "retrieval topK")
                detailMetric("\(plan.retrievalLatencyMilliseconds)ms", "retrieval latency")
                detailMetric("\(plan.retrievedChunks.count)", "retrieved chunks")
                detailMetric("\(plan.estimatedPromptTokens)", "est prompt tokens")
                detailMetric("\(plan.speakingParticipantCount)/\(plan.metadataParticipantCount)", "speakers")
                detailMetric("\(plan.omittedParticipantCount)", "omitted people")
                detailMetric("\(plan.newDialogueLines)", "new lines")
                detailMetric("\(plan.newTranscriptCharacters)", "new chars")
                detailMetric("\(plan.recentContextCharacters)", "recent chars")
            }

            if !plan.retrievedChunks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Retrieved Chunks")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.smoothAccent)
                    ForEach(plan.retrievedChunks) { chunk in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(chunk.timeRange.isEmpty ? chunk.id : chunk.timeRange)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(Color.smoothAccent)
                                Text("score \(String(format: "%.3f", chunk.score))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.smoothMuted)
                                Text("\(chunk.text.count)자")
                                    .font(.caption)
                                    .foregroundStyle(Color.smoothMuted)
                                Spacer(minLength: 0)
                            }
                            Text(chunk.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(Color.smoothInk)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.smoothCanvas.opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.smoothLine.opacity(0.8), lineWidth: 1)
                        )
                    }
                }
            } else {
                Text("retrieval mode가 Off이거나 score threshold를 넘은 관련 chunk가 없어 prompt에 추가된 과거 맥락이 없습니다.")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Raw Context Plan")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.smoothAccent)
                detailTextPanel(text: contextPlanDebugText(plan))
                    .frame(height: 180)
            }
        }
    }

    private func contextPlanSubtitle(_ plan: AnalysisContextPlan) -> String {
        "\(plan.retrievalMode.displayName) · top \(plan.retrievalTopK) · \(plan.retrievedChunks.count) chunks · \(plan.retrievalLatencyMilliseconds)ms · est \(plan.estimatedPromptTokens) tokens"
    }

    private func contextPlanDebugText(_ plan: AnalysisContextPlan) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(plan),
              let text = String(data: data, encoding: .utf8) else {
            return plan.compactSummary
        }
        return text
    }

    private func messageView(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(attempt.status == .failed ? Color.orange : Color.smoothMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailTextPanel(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AnalysisAttemptTextView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
        }
    }
}

private struct AnalysisAttemptTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        context.coordinator.renderedText = nil
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }
        guard context.coordinator.renderedText != text else {
            return
        }
        textView.string = text
        context.coordinator.renderedText = text
    }

    final class Coordinator {
        var renderedText: String?
    }
}

private struct MarkdownReadinessPreviewSheet: View {
    let warnings: [ShareReadinessWarning]
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("공유 준비도")
                        .font(.headline)
                    Text("공유 전에 확인할 항목이 있습니다.")
                        .font(.caption)
                        .foregroundStyle(Color.smoothMuted)
                }
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(warnings) { warning in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.title)
                                    .font(.callout.weight(.semibold))
                                Text(warning.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.smoothMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: warning.severity == .warning ? "exclamationmark.circle" : "info.circle")
                                .foregroundStyle(warning.severity == .warning ? Color.orange : Color.smoothAccent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.smoothLine, lineWidth: 1)
                        )
                    }
                }
            }
            .frame(maxHeight: 320)

            HStack {
                Spacer()
                Button("취소") {
                    onCancel()
                }
                Button("계속 저장") {
                    onContinue()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Color.smoothCanvas)
    }
}

private struct TranscriptLineRow: View, Equatable {
    let line: String
    let isHighlighted: Bool

    var body: some View {
        Group {
            if isHighlighted {
                baseLine
                    .background(
                        Color.smoothAccent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
            } else {
                baseLine
            }
        }
    }

    private var baseLine: some View {
        Text(line)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(Color.smoothInk)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func smoothPanel() -> some View {
        self
            .background(Color.smoothSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func smoothCard(tint: Color = Color.smoothCanvas) -> some View {
        self
            .padding(14)
            .background {
                ZStack(alignment: .leading) {
                    Color.smoothSurface
                    Rectangle()
                        .fill(tint)
                        .frame(width: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
    }
}

private struct SmoothActionButtonStyle: ButtonStyle {
    enum Kind {
        case secondary
        case primary
        case destructive
    }

    @Environment(\.isEnabled) private var isEnabled

    let kind: Kind

    init(kind: Kind = .secondary) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.48))
            .background(background.opacity(backgroundOpacity(configuration: configuration)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(stroke.opacity(isEnabled ? 1 : 0.55), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var horizontalPadding: CGFloat {
        kind == .primary ? 12 : 10
    }

    private var verticalPadding: CGFloat {
        kind == .primary ? 7 : 6
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            return Color.smoothOnAccent
        case .secondary:
            return Color.smoothInk
        case .destructive:
            return Color.smoothDestructive
        }
    }

    private var background: Color {
        switch kind {
        case .primary:
            return Color.smoothAccent
        case .secondary:
            return Color.smoothControl
        case .destructive:
            return Color.smoothDestructive.opacity(0.12)
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary:
            return Color.smoothAccent
        case .secondary:
            return Color.smoothLine
        case .destructive:
            return Color.smoothDestructive.opacity(0.35)
        }
    }

    private func backgroundOpacity(configuration: Configuration) -> Double {
        guard isEnabled else { return 0.48 }
        return configuration.isPressed ? 0.72 : 1
    }
}

private extension NSAppearance {
    var smoothUsesDarkPalette: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension Color {
    static let smoothCanvas = smoothDynamic(
        light: smoothRGB(0.965, 0.961, 0.937),
        dark: smoothRGB(0.092, 0.096, 0.086)
    )
    static let smoothSurface = smoothDynamic(
        light: smoothRGB(1.0, 1.0, 1.0),
        dark: smoothRGB(0.145, 0.151, 0.136)
    )
    static let smoothControl = smoothDynamic(
        light: smoothRGB(0.948, 0.945, 0.918),
        dark: smoothRGB(0.195, 0.204, 0.183)
    )
    static let smoothInk = smoothDynamic(
        light: smoothRGB(0.075, 0.078, 0.071),
        dark: smoothRGB(0.925, 0.929, 0.888)
    )
    static let smoothMuted = smoothDynamic(
        light: smoothRGB(0.42, 0.43, 0.39),
        dark: smoothRGB(0.66, 0.68, 0.61)
    )
    static let smoothLine = smoothDynamic(
        light: smoothRGB(0.875, 0.865, 0.82),
        dark: smoothRGB(0.292, 0.302, 0.265)
    )
    static let smoothAccent = smoothDynamic(
        light: smoothRGB(0.0, 0.56, 0.38),
        dark: smoothRGB(0.28, 0.82, 0.61)
    )
    static let smoothOnAccent = smoothDynamic(
        light: smoothRGB(1.0, 1.0, 1.0),
        dark: smoothRGB(0.055, 0.078, 0.064)
    )
    static let smoothDestructive = smoothDynamic(
        light: smoothRGB(0.78, 0.16, 0.13),
        dark: smoothRGB(1.0, 0.46, 0.38)
    )
    static let smoothMint = smoothDynamic(
        light: smoothRGB(0.84, 0.96, 0.88),
        dark: smoothRGB(0.118, 0.265, 0.195)
    )
    static let smoothSky = smoothDynamic(
        light: smoothRGB(0.84, 0.91, 0.99),
        dark: smoothRGB(0.128, 0.206, 0.326)
    )
    static let smoothWarm = smoothDynamic(
        light: smoothRGB(1.0, 0.91, 0.78),
        dark: smoothRGB(0.34, 0.245, 0.125)
    )

    private static func smoothDynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.smoothUsesDarkPalette ? dark : light
        })
    }

    private static func smoothRGB(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}
