import AppKit
import SwiftUI

struct SelectableTranscriptTextView: NSViewRepresentable {
    var text: String
    var documentIdentity: String
    var textIdentity: String
    var revision: Int
    var focusLineID: Int?
    var scrollToBottomToken: Int
    var onSelectionChange: @MainActor @Sendable (String) -> Void
    var onAutoFollowChange: @MainActor @Sendable (Bool) -> Void

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

        if context.coordinator.lastTextIdentity != textIdentity {
            let selectedRange = textView.selectedRange()
            textView.string = text
            context.coordinator.lastTextIdentity = textIdentity
            if documentDidChange {
                context.coordinator.resetLayoutForNewDocument(textView, in: scrollView)
                let emptyRange = NSRange(location: 0, length: 0)
                if textView.selectedRange() != emptyRange {
                    textView.setSelectedRange(emptyRange)
                }
                context.coordinator.emitSelectionChange("")
            } else {
                let textLength = (text as NSString).length
                if NSMaxRange(selectedRange) <= textLength {
                    textView.setSelectedRange(selectedRange)
                }
            }
        } else if documentDidChange {
            context.coordinator.resetLayoutForNewDocument(textView, in: scrollView)
            let emptyRange = NSRange(location: 0, length: 0)
            if textView.selectedRange() != emptyRange {
                textView.setSelectedRange(emptyRange)
            }
            context.coordinator.emitSelectionChange("")
        }

        if context.coordinator.lastScrollToBottomToken != scrollToBottomToken {
            context.coordinator.lastScrollToBottomToken = scrollToBottomToken
            context.coordinator.scrollToBottom(enableAutoFollow: true)
        } else if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            if context.coordinator.isAutoFollowEnabled {
                context.coordinator.scrollToBottom(enableAutoFollow: true)
            }
        }

        if let focusLineID {
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

        init(
            onSelectionChange: @escaping @MainActor @Sendable (String) -> Void,
            onAutoFollowChange: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            self.onSelectionChange = onSelectionChange
            self.onAutoFollowChange = onAutoFollowChange
        }

        deinit {
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
        func resetLayoutForNewDocument(_ textView: NSTextView, in scrollView: NSScrollView) {
            let visibleSize = scrollView.contentSize
            let width = max(visibleSize.width, 1)
            let height = max(visibleSize.height, 1)

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
