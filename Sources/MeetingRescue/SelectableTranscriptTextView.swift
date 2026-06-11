import AppKit
import SwiftUI

struct SelectableTranscriptTextView: NSViewRepresentable {
    var text: String
    var textIdentity: String
    var revision: Int
    var focusLineID: Int?
    var onSelectionChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
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
        context.coordinator.textView = textView
        context.coordinator.lastTextIdentity = textIdentity
        context.coordinator.lastRevision = revision
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        context.coordinator.onSelectionChange = onSelectionChange

        if context.coordinator.lastTextIdentity != textIdentity {
            let selectedRange = textView.selectedRange()
            textView.string = text
            context.coordinator.lastTextIdentity = textIdentity
            let textLength = (text as NSString).length
            if NSMaxRange(selectedRange) <= textLength {
                textView.setSelectedRange(selectedRange)
            }
        }

        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            textView.scrollToEndOfDocument(nil)
        }

        if let focusLineID {
            context.coordinator.scrollToLine(focusLineID)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var onSelectionChange: (String) -> Void
        var lastTextIdentity = ""
        var lastRevision = 0
        private var lastFocusedLineID: Int?

        init(onSelectionChange: @escaping (String) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                onSelectionChange("")
                return
            }
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0,
                  let swiftRange = Range(selectedRange, in: textView.string) else {
                onSelectionChange("")
                return
            }
            onSelectionChange(String(textView.string[swiftRange]))
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
    }
}
