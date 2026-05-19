import MeetingRescueCore
import AppKit
import SwiftUI

private enum IntelligenceMode: String, CaseIterable, Identifiable {
    case overview = "요약"
    case timeline = "흐름"
    case candidates = "후보"

    var id: String { rawValue }
}

private enum EditingCandidateKind {
    case decision
    case action
}

private struct EditingCandidate: Equatable {
    var kind: EditingCandidateKind
    var id: String
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showingSettings = false
    @State private var intelligenceMode: IntelligenceMode = .overview
    @State private var editingCandidate: EditingCandidate?
    @State private var decisionDraftText = ""
    @State private var actionDraftAssignee = ""
    @State private var actionDraftTask = ""
    @State private var actionDraftDeadline = ""
    @State private var selectedAnalysisAttempt: AnalysisAttemptLog?
    @State private var isAnalysisDiagnosticsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HSplitView {
                historySidebar
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 360, maxHeight: .infinity)
                transcriptContent
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                intelligenceContent
                    .frame(minWidth: 340, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(minWidth: 1180, minHeight: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.smoothCanvas)
        .tint(Color.smoothAccent)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingOnboarding) {
            OnboardingView()
                .environmentObject(viewModel)
        }
        .sheet(item: $selectedAnalysisAttempt) { attempt in
            AnalysisAttemptDetailView(attempt: attempt)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Meeting Rescue")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.smoothAccent)
                        .textCase(.uppercase)
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

                HStack(spacing: 8) {
                    headerButton("분석", systemImage: "sparkles") {
                        viewModel.triggerManualAnalysis()
                    }
                    .disabled(viewModel.activeTranscriptURL == nil || viewModel.rawTranscript.isEmpty || viewModel.isAnalysisRunning)

                    headerButton("Markdown", systemImage: "square.and.arrow.down") {
                        viewModel.exportCurrentIntelligenceMarkdown()
                    }
                    .disabled(viewModel.analysisState.latestSnapshot == nil)

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
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                        }
                        .menuStyle(.button)
                        .controlSize(.regular)

                        headerButton("Live", systemImage: "dot.radiowaves.left.and.right") {
                            viewModel.stopTestRunAndReturnToLive()
                        }
                    }

                    if viewModel.isHistoryMode || viewModel.liveMeetingUpdated {
                        headerButton("Live", systemImage: "dot.radiowaves.left.and.right") {
                            viewModel.returnToLiveWatch()
                        }
                        .disabled(viewModel.liveActiveTranscriptURL == nil && viewModel.selectedFolderURL == nil)
                    }

                    headerButton("설정", systemImage: "gearshape") {
                        showingSettings = true
                    }

                    headerButton("폴더", systemImage: "folder") {
                        viewModel.chooseFolder()
                    }
                }
            }

            HStack(spacing: 8) {
                statusChip("mode", viewModel.transcriptRunMode.displayText, systemImage: "switch.2")
                if viewModel.isTestRunActive {
                    statusChip(viewModel.testRunPlaybackStatus.displayText, viewModel.testRunProgressText, systemImage: "play.circle")
                    statusChip("speed", viewModel.testRunSpeedText, systemImage: "speedometer")
                }
                if viewModel.liveMeetingUpdated {
                    statusChip("live", "updated", systemImage: "bell.badge")
                }
                statusChip("상태", viewModel.analysisStatus.displayText, systemImage: statusIcon)
                statusChip("provider", providerSummary, systemImage: "cpu")
                statusChip("usage", usageSummaryText, systemImage: "chart.bar.doc.horizontal")
                statusChip("업데이트", viewModel.transcriptUpdatedAt?.formatted(date: .omitted, time: .standard) ?? "-", systemImage: "clock")
                statusChip("lines", "\(viewModel.rawTranscriptLineCount)", systemImage: "text.alignleft")
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 22) {
                metadataRow("일시", viewModel.metadata.dateTime ?? "-")
                metadataRow("참석자", viewModel.metadata.participants.isEmpty ? "-" : viewModel.metadata.participants.joined(separator: ", "))
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
            paneTitle("Meetings", systemImage: "sidebar.left")
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .background(Color.white, in: Capsule())
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
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .background(Color.white, in: Capsule())
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
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        return Color.white
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
        .background(isSelected ? Color.smoothMint : Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            paneTitle("Raw Transcript", systemImage: "doc.text", trailing: "\(viewModel.rawTranscriptLineCount) lines")
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

    private var rawTranscriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                rawTranscriptLineList
                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .background(Color.white)
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

    private var intelligenceContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                paneTitle("Meeting Intelligence", systemImage: "sparkles", compact: true)
                Spacer()
                Picker("view", selection: $intelligenceMode) {
                    ForEach(IntelligenceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            .padding(.trailing, 12)

            Divider().overlay(Color.smoothLine)

            if let snapshot = viewModel.analysisState.latestSnapshot {
                ScrollView {
                    Group {
                        switch intelligenceMode {
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

    private func overview(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            currentIssue(snapshot.currentIssue)
            metricsRow(snapshot)
            usageSummary()
            analysisDiagnostics()
            decisions(snapshot.decisionCandidates, compact: true)
            actionItems(snapshot.actionItemCandidates, compact: true)
            timeline(Array(snapshot.topicTimeline.suffix(4)), full: false)
            notes(Array(snapshot.risksOrNotes.prefix(2)))
        }
    }

    private func currentIssue(_ issue: CurrentIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("현재 이슈", systemImage: "dot.radiowaves.left.and.right")
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            sectionHeader("결정 후보", systemImage: "checkmark.seal")
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
            sectionHeader("액션 후보", systemImage: "arrow.up.forward.circle")
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

    private func decisionEditForm(_ candidate: DecisionCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("결정 문장 편집", systemImage: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothAccent)
            TextEditor(text: $decisionDraftText)
                .font(.callout)
                .frame(minHeight: 72)
                .padding(6)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            "Codex"
        case .claudeCode:
            "Claude"
        case .customCommand:
            "Custom"
        }
        return "\(provider) · \(viewModel.settings.modelPreset.displayName)"
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
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Color.smoothLine, lineWidth: 1))
        .frame(maxWidth: 260, alignment: .leading)
    }

    private func paneTitle(_ text: String, systemImage: String, trailing: String? = nil, compact: Bool = false) -> some View {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 11 : 12)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text("설정")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        dismiss()
                        Task { @MainActor in
                            viewModel.showOnboarding()
                        }
                    } label: {
                        Label("온보딩", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Model preset은 provider 공통 설정입니다. Codex와 Claude Code는 preset을 CLI model/effort로 적용하고, Custom Command에는 환경변수로 전달합니다.")
                    .font(.callout)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Picker("LLM provider", selection: providerBinding) {
                    ForEach(LLMProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Picker("model preset", selection: modelPresetBinding) {
                    ForEach(LLMModelPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Text(viewModel.settings.modelPreset.detail)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("automatic meeting intelligence", isOn: automaticAnalysisBinding)
                Text("끄면 live/test run 중 자동 LLM analysis와 회의 종료 final analysis를 실행하지 않습니다. 수동 `분석`은 계속 사용할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("analysis trigger", selection: analysisTriggerPresetBinding) {
                    ForEach(AnalysisTriggerPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                    .disabled(!viewModel.settings.automaticAnalysisEnabled)
                Text(viewModel.settings.analysisTriggerPreset.detail)
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Stepper("provider timeout: \(viewModel.settings.providerTimeoutSeconds)초", value: timeoutBinding, in: 10...300)
                Text("Test Run도 같은 preset을 사용하되 wait 계산은 transcript 경과 시간 기준입니다. 수동 `분석`과 final analysis는 최소 180초 timeout을 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("custom command", text: customCommandBinding)
                    .disabled(viewModel.settings.selectedProvider != .customCommand)
            }

            pricingReference

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    viewModel.chooseFolder()
                } label: {
                    Label("selected Recordings folder 변경", systemImage: "folder")
                }

                Button(role: .destructive) {
                    viewModel.clearCurrentAnalysisState()
                } label: {
                    Label("현재 meeting analysis state 지우기", systemImage: "eraser")
                }
                .disabled(viewModel.activeTranscriptURL == nil)

                Button(role: .destructive) {
                    viewModel.forgetSelectedFolder()
                } label: {
                    Label("선택 폴더 잊기", systemImage: "xmark.circle")
                }
                .disabled(viewModel.selectedFolderURL == nil)

                Button {
                    dismiss()
                    Task { @MainActor in
                        viewModel.showOnboarding()
                    }
                } label: {
                    Label("onboarding 다시 보기", systemImage: "questionmark.circle")
                }
            }

            HStack {
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(Color.smoothCanvas)
    }

    private var providerBinding: Binding<LLMProviderKind> {
        Binding {
            viewModel.settings.selectedProvider
        } set: { value in
            viewModel.updateProvider(value)
        }
    }

    private var modelPresetBinding: Binding<LLMModelPreset> {
        Binding {
            viewModel.settings.modelPreset
        } set: { value in
            viewModel.updateModelPreset(value)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("가격 reference")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.smoothMuted)
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
        .padding(10)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func priceString(_ value: Double) -> String {
        String(format: "%.2f", value)
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
                .buttonStyle(.bordered)
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
                            .buttonStyle(.borderedProminent)

                            Button {
                                viewModel.chooseFolder()
                            } label: {
                                Label("직접 선택", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered)
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
                        .buttonStyle(.borderedProminent)
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
                .buttonStyle(.borderedProminent)
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
            .background(Color.white.opacity(0.75), in: Capsule())
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
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.smoothLine, lineWidth: 1)
            )
    }
}

private struct AnalysisAttemptDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let attempt: AnalysisAttemptLog

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis 실행 상세")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.smoothInk)
                    Text("\(attempt.reason) · \(attempt.status.rawValue) · \(attempt.modelName)")
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
                            .foregroundStyle(Color.smoothInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.smoothLine, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("상세 화면 닫기")
                }
            }

            HStack(spacing: 8) {
                detailMetric("\(attempt.inputTokens)", "input tokens")
                detailMetric("\(attempt.outputTokens)", "output tokens")
                detailMetric(attempt.elapsedMilliseconds.map { "\($0)ms" } ?? "running", "duration")
                detailMetric(attempt.modelPreset.displayName, "preset")
                detailMetric(attempt.provider.displayName, "provider")
            }

            if let stats = attempt.batchStats {
                HStack(spacing: 8) {
                    detailMetric("\(stats.newDialogueLines)", "new lines")
                    detailMetric("\(stats.newTranscriptCharacters)", "new chars")
                    detailMetric("\(stats.includedDialogueLines)", "included lines")
                    detailMetric("\(stats.includedTranscriptCharacters)", "included chars")
                    detailMetric(stats.triggerReason, "trigger")
                }
            }

            if let message = attempt.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(attempt.status == .failed ? Color.orange : Color.smoothMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.smoothLine, lineWidth: 1)
                    )
            }

            if let trace = attempt.runTrace {
                runTraceView(trace)
            }

            HSplitView {
                detailTextPanel(title: "Prompt", text: attempt.prompt ?? "저장된 prompt가 없습니다. 이 버전 이후 실행부터 기록됩니다.")
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                detailTextPanel(title: "Provider Output", text: attempt.providerOutput ?? "저장된 provider output이 없습니다. 성공한 run은 이 버전 이후 raw JSON output을 기록합니다.")
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 420)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("닫기", systemImage: "xmark")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 920, minHeight: 620)
        .background(Color.smoothCanvas)
    }

    private func runTraceView(_ trace: AnalysisRunTrace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Run Trace")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.smoothAccent)
                Spacer()
                Text("stdout \(trace.outputBytes)B · stderr \(trace.stderrBytes)B · exit \(trace.exitCode.map(String.init) ?? "-")")
                    .font(.caption)
                    .foregroundStyle(Color.smoothMuted)
            }
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
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.smoothLine, lineWidth: 1)
        )
    }

    private func detailTextPanel(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.smoothAccent)
                Spacer()
                Text("\(text.count)자")
                    .font(.caption2)
                    .foregroundStyle(Color.smoothMuted)
            }
            AnalysisAttemptTextView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    Color.white
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

private extension Color {
    static let smoothCanvas = Color(red: 0.965, green: 0.961, blue: 0.937)
    static let smoothInk = Color(red: 0.075, green: 0.078, blue: 0.071)
    static let smoothMuted = Color(red: 0.42, green: 0.43, blue: 0.39)
    static let smoothLine = Color(red: 0.875, green: 0.865, blue: 0.82)
    static let smoothAccent = Color(red: 0.0, green: 0.56, blue: 0.38)
    static let smoothMint = Color(red: 0.84, green: 0.96, blue: 0.88)
    static let smoothSky = Color(red: 0.84, green: 0.91, blue: 0.99)
    static let smoothWarm = Color(red: 1.0, green: 0.91, blue: 0.78)
}
