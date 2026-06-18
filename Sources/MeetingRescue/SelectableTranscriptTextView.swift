import AppKit
import SwiftUI

struct SelectableTranscriptTextUpdate: Equatable {
    enum Kind: Equatable {
        case fullReplace
        case append
    }

    let sequence: Int
    let kind: Kind
    let text: String

    static let initial = SelectableTranscriptTextUpdate.fullReplace(sequence: 0)

    static func fullReplace(sequence: Int) -> SelectableTranscriptTextUpdate {
        SelectableTranscriptTextUpdate(sequence: sequence, kind: .fullReplace, text: "")
    }

    static func append(sequence: Int, text: String) -> SelectableTranscriptTextUpdate {
        SelectableTranscriptTextUpdate(sequence: sequence, kind: .append, text: text)
    }
}

enum SelectableTranscriptTextStorageMutation: Equatable {
    case unchanged
    case appended
    case replaced
}

enum SelectableTranscriptTextStorageUpdater {
    @MainActor
    static func apply(
        text: String,
        textUpdate: SelectableTranscriptTextUpdate,
        documentDidChange: Bool,
        previousTextIdentity: String,
        newTextIdentity: String,
        textView: NSTextView
    ) -> SelectableTranscriptTextStorageMutation {
        guard previousTextIdentity != newTextIdentity else {
            return .unchanged
        }

        if textUpdate.kind == .append,
           !documentDidChange,
           !previousTextIdentity.isEmpty,
           !textUpdate.text.isEmpty,
           canAppend(text: text, appendedText: textUpdate.text, to: textView) {
            append(textUpdate.text, to: textView)
            return .appended
        }

        replace(text, in: textView)
        return .replaced
    }

    @MainActor
    private static func canAppend(text: String, appendedText: String, to textView: NSTextView) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        let currentLength = textStorage.length
        let appendedLength = (appendedText as NSString).length
        guard appendedLength > 0 else {
            return false
        }

        let fullText = text as NSString
        guard fullText.length == currentLength + appendedLength else {
            return false
        }
        let appendedRange = NSRange(location: currentLength, length: appendedLength)
        return fullText.substring(with: appendedRange) == appendedText
    }

    @MainActor
    private static func append(_ text: String, to textView: NSTextView) {
        guard let textStorage = textView.textStorage else {
            textView.string += text
            return
        }

        let selectedRanges = textView.selectedRanges
        let attributes = defaultAttributes(for: textView)
        textStorage.beginEditing()
        textStorage.append(NSAttributedString(string: text, attributes: attributes))
        textStorage.endEditing()
        restoreSelection(selectedRanges, in: textView)
    }

    @MainActor
    private static func replace(_ text: String, in textView: NSTextView) {
        let selectedRanges = textView.selectedRanges
        textView.string = text
        restoreSelection(selectedRanges, in: textView)
    }

    @MainActor
    private static func defaultAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
        [
            .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: textView.textColor ?? NSColor.labelColor
        ]
    }

    @MainActor
    private static func restoreSelection(_ ranges: [NSValue], in textView: NSTextView) {
        let textLength = (textView.string as NSString).length
        let validRanges = ranges.filter { value in
            let range = value.rangeValue
            return range.location <= textLength && NSMaxRange(range) <= textLength
        }

        if validRanges.isEmpty {
            textView.setSelectedRange(NSRange(location: textLength, length: 0))
        } else {
            textView.setSelectedRanges(validRanges, affinity: .downstream, stillSelecting: false)
        }
    }
}

struct SelectableTranscriptTextView: NSViewRepresentable {
    var text: String
    var documentIdentity: String
    var textIdentity: String
    var textUpdate: SelectableTranscriptTextUpdate
    var revision: Int
    var focusLineID: Int?
    var scrollToBottomToken: Int
    var onSelectionChange: @MainActor @Sendable (String) -> Void
    var onAutoFollowChange: @MainActor @Sendable (Bool) -> Void

    @MainActor
    static func configureTextChecking(_ textView: NSTextView) {
        textView.enabledTextCheckingTypes = 0
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectionChange: onSelectionChange,
            onAutoFollowChange: onAutoFollowChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindPanel = true
        Self.configureTextChecking(textView)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.textView = textView
        context.coordinator.observe(scrollView: scrollView)
        context.coordinator.configureTextViewLayout(textView, in: scrollView)
        context.coordinator.lastDocumentIdentity = documentIdentity
        context.coordinator.lastTextIdentity = textIdentity
        context.coordinator.lastRevision = revision
        context.coordinator.lastScrollToBottomToken = scrollToBottomToken
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onAutoFollowChange = onAutoFollowChange
        context.coordinator.observe(scrollView: scrollView)
        context.coordinator.configureTextViewLayout(textView, in: scrollView)

        let documentDidChange = context.coordinator.lastDocumentIdentity != documentIdentity
        if documentDidChange {
            context.coordinator.lastDocumentIdentity = documentIdentity
        }

        let textMutation: SelectableTranscriptTextStorageMutation
        if context.coordinator.lastTextIdentity != textIdentity {
            textMutation = SelectableTranscriptTextStorageUpdater.apply(
                text: text,
                textUpdate: textUpdate,
                documentDidChange: documentDidChange,
                previousTextIdentity: context.coordinator.lastTextIdentity,
                newTextIdentity: textIdentity,
                textView: textView
            )
            context.coordinator.lastTextIdentity = textIdentity
            if documentDidChange {
                context.coordinator.resetLayoutForNewDocument(textView, in: scrollView)
                let emptyRange = NSRange(location: 0, length: 0)
                if textView.selectedRange() != emptyRange {
                    textView.setSelectedRange(emptyRange)
                }
                context.coordinator.emitSelectionChange("")
            }
        } else {
            textMutation = .unchanged
        }

        if documentDidChange && textMutation == .unchanged {
            context.coordinator.resetLayoutForNewDocument(textView, in: scrollView)
            let emptyRange = NSRange(location: 0, length: 0)
            if textView.selectedRange() != emptyRange {
                textView.setSelectedRange(emptyRange)
            }
            context.coordinator.emitSelectionChange("")
        }

        if context.coordinator.lastScrollToBottomToken != scrollToBottomToken {
            context.coordinator.lastScrollToBottomToken = scrollToBottomToken
            context.coordinator.cancelPendingScrollToBottom()
            context.coordinator.scrollToBottom(enableAutoFollow: true)
        } else if documentDidChange {
            context.coordinator.lastRevision = revision
        } else if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            if context.coordinator.isAutoFollowEnabled {
                if textMutation == .appended && focusLineID == nil {
                    context.coordinator.scheduleCoalescedScrollToBottom()
                } else {
                    context.coordinator.cancelPendingScrollToBottom()
                    context.coordinator.scrollToBottom(enableAutoFollow: true)
                }
            }
        }

        if let focusLineID {
            context.coordinator.cancelPendingScrollToBottom()
            context.coordinator.scrollToLine(focusLineID)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var onSelectionChange: @MainActor @Sendable (String) -> Void
        var onAutoFollowChange: @MainActor @Sendable (Bool) -> Void
        var lastDocumentIdentity = ""
        var lastTextIdentity = ""
        var lastRevision = 0
        var lastScrollToBottomToken = 0
        var isAutoFollowEnabled = true
        var isProgrammaticScroll = false
        private weak var observedClipView: NSClipView?
        private var lastFocusedLineID: Int?
        private var pendingScrollToBottomTask: Task<Void, Never>?
        private let appendScrollCoalescingDelayNanoseconds: UInt64 = 80_000_000

        init(
            onSelectionChange: @escaping @MainActor @Sendable (String) -> Void,
            onAutoFollowChange: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            self.onSelectionChange = onSelectionChange
            self.onAutoFollowChange = onAutoFollowChange
        }

        deinit {
            pendingScrollToBottomTask?.cancel()
            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }
        }

        @MainActor
        func observe(scrollView: NSScrollView) {
            self.scrollView = scrollView
            let clipView = scrollView.contentView
            guard observedClipView !== clipView else {
                return
            }
            if let observedClipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedClipView
                )
            }
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                emitSelectionChange("")
                return
            }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0,
                  let swiftRange = Range(selectedRange, in: textView.string) else {
                emitSelectionChange("")
                return
            }
            emitSelectionChange(String(textView.string[swiftRange]))
        }

        @objc
        @MainActor
        private func clipViewBoundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll,
                  let scrollView,
                  let textView else {
                return
            }
            configureTextViewLayout(textView, in: scrollView)
            setAutoFollowEnabled(isNearBottom(scrollView))
        }

        @MainActor
        func scrollToBottom(enableAutoFollow: Bool) {
            guard let textView,
                  let scrollView else {
                return
            }
            if enableAutoFollow {
                setAutoFollowEnabled(true)
            }
            scrollToVisibleBottom(scrollView, textView: textView)
        }

        @MainActor
        func scheduleCoalescedScrollToBottom() {
            let delay = appendScrollCoalescingDelayNanoseconds
            pendingScrollToBottomTask?.cancel()
            pendingScrollToBottomTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled,
                      let self,
                      self.isAutoFollowEnabled else {
                    return
                }
                self.scrollToBottom(enableAutoFollow: false)
            }
        }

        @MainActor
        func cancelPendingScrollToBottom() {
            pendingScrollToBottomTask?.cancel()
            pendingScrollToBottomTask = nil
        }

        @MainActor
        func resetLayoutForNewDocument(_ textView: NSTextView, in scrollView: NSScrollView) {
            let visibleSize = scrollView.contentSize
            let width = max(visibleSize.width, 1)
            let height = max(visibleSize.height, 1)

            cancelPendingScrollToBottom()
            lastFocusedLineID = nil
            setAutoFollowEnabled(true)
            textView.textContainer?.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = true
            textView.setFrameSize(NSSize(width: width, height: height))
            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticScroll = false
            }
        }

        @MainActor
        func configureTextViewLayout(_ textView: NSTextView, in scrollView: NSScrollView) {
            let visibleSize = scrollView.contentSize
            let width = max(visibleSize.width, textView.bounds.width, 1)
            let height = max(visibleSize.height, textView.bounds.height, 1)

            textView.minSize = NSSize(width: 0, height: height)
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainer?.widthTracksTextView = true
            if textView.frame.width != width || textView.frame.height < height {
                textView.setFrameSize(NSSize(width: width, height: height))
            }
        }

        @MainActor
        private func scrollToVisibleBottom(_ scrollView: NSScrollView, textView: NSTextView) {
            configureTextViewLayout(textView, in: scrollView)

            let visibleSize = scrollView.contentSize
            let visibleHeight = max(visibleSize.height, 1)
            let visibleWidth = max(visibleSize.width, textView.bounds.width, 1)
            let documentHeight = measuredDocumentHeight(textView, minimumHeight: visibleHeight)

            if textView.frame.width != visibleWidth || abs(textView.frame.height - documentHeight) > 0.5 {
                textView.setFrameSize(NSSize(width: visibleWidth, height: documentHeight))
            }

            let targetY = max(0, documentHeight - visibleHeight)
            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.async { [weak self] in
                self?.isProgrammaticScroll = false
            }
        }

        @MainActor
        func scrollToLine(_ lineID: Int) {
            guard lastFocusedLineID != lineID,
                  let textView else {
                return
            }
            let lines = textView.string.components(separatedBy: .newlines)
            guard !lines.isEmpty else {
                return
            }
            lastFocusedLineID = lineID
            let target = max(0, min(lineID, lines.count - 1))
            let location = lines.prefix(target).reduce(0) { offset, line in
                offset + (line as NSString).length + 1
            }
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }

        @MainActor
        private func measuredDocumentHeight(_ textView: NSTextView, minimumHeight: CGFloat) -> CGFloat {
            guard let textContainer = textView.textContainer else {
                return max(minimumHeight, textView.bounds.height)
            }
            textView.layoutManager?.ensureLayout(for: textContainer)
            let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
            let contentHeight = ceil(usedRect.maxY + (textView.textContainerInset.height * 2))
            return max(minimumHeight, contentHeight)
        }

        @MainActor
        private func setAutoFollowEnabled(_ isEnabled: Bool) {
            guard isAutoFollowEnabled != isEnabled else {
                return
            }
            if !isEnabled {
                cancelPendingScrollToBottom()
            }
            isAutoFollowEnabled = isEnabled
            emitAutoFollowChange(isEnabled)
        }

        func emitSelectionChange(_ selectedText: String) {
            let callback = onSelectionChange
            Task { @MainActor in
                callback(selectedText)
            }
        }

        private func emitAutoFollowChange(_ isEnabled: Bool) {
            let callback = onAutoFollowChange
            Task { @MainActor in
                callback(isEnabled)
            }
        }

        @MainActor
        private func isNearBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else {
                return true
            }
            let visibleRect = scrollView.contentView.documentVisibleRect
            let documentHeight = documentView.bounds.height
            guard documentHeight > 0 else {
                return true
            }
            return visibleRect.maxY >= documentHeight - 24
        }
    }
}
