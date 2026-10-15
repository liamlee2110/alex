import SwiftUI
import AppKit

/// Scroll and pinch are not SwiftUI gestures on macOS. This view sits under
/// the canvas, never takes a click (`hitTest` answers nil), and a local
/// event monitor hands it every wheel and magnify event that lands inside
/// its bounds — the same mechanism Donna uses for right-click menus.
/// `accepts` says which of those points are the desk's own: the sidebar
/// and the detail sheet float over it, and a wheel over them is theirs.
struct EventCatcher: NSViewRepresentable {
    var accepts: (CGPoint) -> Bool = { _ in true }
    var onScroll: (CGPoint, CGPoint, NSEvent.ModifierFlags) -> Void
    var onMagnify: (CGFloat, CGPoint) -> Void
    /// Every change of the modifier keys in the window, wherever the
    /// pointer is and never swallowed: ⇧ pressed between two pointer
    /// moves reshapes a drag at once (revision 35).
    var onFlags: (NSEvent.ModifierFlags) -> Void = { _ in }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.accepts = accepts
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        view.onFlags = onFlags
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.accepts = accepts
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        view.onFlags = onFlags
    }
}

final class CatcherView: NSView {
    var accepts: ((CGPoint) -> Bool)?
    var onScroll: ((CGPoint, CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onMagnify: ((CGFloat, CGPoint) -> Void)?
    var onFlags: ((NSEvent.ModifierFlags) -> Void)?
    private var monitor: Any?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .flagsChanged]) { [weak self] event in
            guard let self, let window = self.window, event.window == window else { return event }
            if event.type == .flagsChanged {
                self.onFlags?(event.modifierFlags)
                return event
            }
            let p = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(p), self.accepts?(p) ?? true else { return event }
            switch event.type {
            case .scrollWheel:
                var dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
                if !event.hasPreciseScrollingDeltas { dx *= 8; dy *= 8 }
                self.onScroll?(CGPoint(x: dx, y: dy), p, event.modifierFlags)
            case .magnify:
                self.onMagnify?(event.magnification, p)
            default:
                break
            }
            return nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
