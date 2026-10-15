import SwiftUI
import AppKit

/// A shape's words while they are written (PLAN.md, revision 52): a plain
/// text view with no inset and no padding of its own, so the words sit
/// where the shape draws them and do not jump when writing starts, as
/// Excalidraw's editor sits over its text. It keeps its own undo stack:
/// ⌘Z while writing takes back typing, never a canvas step, and the
/// writing becomes one canvas step when it ends. As tall as its lines,
/// for a shape to centre. Esc or ⌘↩ puts the pen down.
struct ShapeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> ShapeTextView {
        let view = ShapeTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.focusRingType = .none
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.insertionPointColor = AccentNS.text
        view.string = text
        style(view, context.coordinator)
        view.onDone = onDone
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            view.moveToEndOfDocument(nil)
        }
        return view
    }

    func updateNSView(_ view: ShapeTextView, context: Context) {
        view.onDone = onDone
        context.coordinator.text = $text
        if view.string != text { view.string = text }
        style(view, context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ShapeTextView, context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width ?? container.containerSize.width
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let lines = max(layout.usedRect(for: container).height, layout.defaultLineHeight(for: font))
        return CGSize(width: width, height: ceil(lines))
    }

    /// Only when the look changed: an NSTextView forgets its undo when its
    /// storage is edited from outside, and SwiftUI updates the view at every
    /// save while the words are written.
    private func style(_ view: ShapeTextView, _ coordinator: Coordinator) {
        let look = Coordinator.Look(font: font, color: color, alignment: alignment)
        guard coordinator.look != look else { return }
        coordinator.look = look
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                         .paragraphStyle: paragraph]
        view.typingAttributes = attributes
        guard let storage = view.textStorage, storage.length > 0 else { return }
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        struct Look: Equatable {
            var font: NSFont
            var color: NSColor
            var alignment: NSTextAlignment
        }
        /// The look last applied.
        var look: Look?
        /// The writing's own undo, apart from the window's canvas steps.
        private let undo = UndoManager()

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }
    }
}

final class ShapeTextView: NSTextView {
    var onDone: (() -> Void)?

    // SwiftUI's hosting view answers `undo:` with the window's canvas
    // steps before the chain reaches the window, so the editor takes ⌘Z
    // itself, with its own stack (revision 52).
    @objc func undo(_ sender: Any?) { undoManager?.undo() }
    @objc func redo(_ sender: Any?) { undoManager?.redo() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            (item as? NSMenuItem)?.title = undoManager?.undoMenuItemTitle ?? "Undo"
            return undoManager?.canUndo == true
        case #selector(redo(_:)):
            (item as? NSMenuItem)?.title = undoManager?.redoMenuItemTitle ?? "Redo"
            return undoManager?.canRedo == true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || (event.keyCode == 36 && event.modifierFlags.contains(.command)) {
            onDone?()
            return
        }
        super.keyDown(with: event)
    }
}
