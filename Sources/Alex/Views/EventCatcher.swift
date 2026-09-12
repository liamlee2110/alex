import SwiftUI
import AppKit

/// Scroll and pinch are not SwiftUI gestures on macOS. This view sits under
/// the canvas, never takes a click (`hitTest` answers nil), and a local
/// event monitor hands it every wheel and magnify event that lands inside
/// its bounds — the same mechanism Donna uses for right-click menus.
struct EventCatcher: NSViewRepresentable {
    var onScroll: (CGPoint, CGPoint, NSEvent.ModifierFlags) -> Void
    var onMagnify: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }
}

final class CatcherView: NSView {
    var onScroll: ((CGPoint, CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onMagnify: ((CGFloat, CGPoint) -> Void)?
    private var monitor: Any?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self, let window = self.window, event.window == window else { return event }
            let p = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(p) else { return event }
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
