import SwiftUI
import AppKit

/// The tooltip (law 10; PLAN.md, revision 15): one floating panel the app
/// draws, shown under whichever glyph the pointer has rested on for
/// `Motion.tooltipDelay`, never at once. A borderless, non-activating
/// panel so it floats over the window's toolbar and the desk alike; it
/// never becomes key and takes no clicks (Donna's sharp edges), and it
/// goes the moment the pointer leaves or presses.
@MainActor
final class TooltipPanel {
    static let shared = TooltipPanel()

    private var panel: NSPanel?
    private var pending: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    /// The tooltip on screen, if one is: what a snapshot composites in.
    var showing: NSPanel? { panel?.isVisible == true ? panel : nil }

    private init() {
        // The app going behind another takes the pointer with it. A
        // tooltip held open for a snapshot stays, whatever the app's
        // activity: a headless run resigns before the picture is taken.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard !Self.tracing else { return }
            MainActor.assumeIsolated { self?.cancel("app resigned active") }
        }
    }

    /// The pointer came to rest: wait, then show `text` under the glyph.
    /// `atOnce` skips the wait, for a snapshot (`--tip <label>`), and
    /// instead waits for the glyph to have a window at all.
    func schedule(_ text: String, shortcut: String? = nil, edge: TooltipEdge = .below, atOnce: Bool = false,
                  anchor: @escaping @MainActor () -> NSRect?) {
        pending?.cancel()
        pending = Task { [weak self] in
            if !atOnce { try? await Task.sleep(for: Motion.tooltipDelay) }
            var rect = anchor()
            var tries = 0
            while atOnce, rect == nil, tries < 20, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                rect = anchor()
                tries += 1
            }
            guard !Task.isCancelled, let rect else {
                if atOnce { FileHandle.standardError.write(Data("tooltip: no window for '\(text)'\n".utf8)) }
                return
            }
            self?.show(text, shortcut: shortcut, edge: edge, at: rect)
        }
    }

    /// The pointer left, or pressed: whatever was waiting or showing goes.
    func cancel(_ reason: String = "") {
        if Self.tracing, panel?.isVisible == true {
            FileHandle.standardError.write(Data("tooltip: cancelled (\(reason))\n".utf8))
        }
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
    }

    /// `--tip` on the command line: say what happens, for a snapshot run.
    nonisolated static let tracing = Launch.value(after: "--tip") != nil

    private func show(_ text: String, shortcut: String?, edge: TooltipEdge, at anchor: NSRect) {
        let hosting = NSHostingView(rootView: TooltipView(text: text, shortcut: shortcut, edge: edge))
        let size = hosting.fittingSize
        hosting.setFrameSize(size)
        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        panel.setContentSize(size)
        // Centred on the glyph, a small space off the edge it was asked
        // for, kept on its screen: a tooltip at the window's edge steps
        // in, not off, and one with no room on its side takes the other.
        let below = anchor.minY - size.height
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: edge == .above ? anchor.maxY : below)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            if origin.y < visible.minY { origin.y = anchor.maxY }
            if origin.y + size.height > visible.maxY { origin.y = below }
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        if Self.tracing {
            FileHandle.standardError.write(Data("tooltip: ordered front visible=\(panel.isVisible) active=\(NSApp.isActive) frame=\(panel.frame)\n".utf8))
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shadow is the content's own `Elevation`, not the window's.
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        // Not hidden by the app deactivating, which a headless snapshot
        // never activates for; `didResignActive` cancels it instead.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }
}

/// Which side of its glyph a tooltip opens on: below, unless the glyph
/// stands at the window's foot, as the palette and the zoom bar do.
enum TooltipEdge { case below, above }

extension EnvironmentValues {
    @Entry var tooltipEdge: TooltipEdge = .below
}

/// The tooltip itself: a label on paper with a hairline, raised, and the
/// key that does the same after it as a `KeyCap` (law 13, revision 40),
/// as Raycast's "Select  [V]". The outer padding is room for the shadow,
/// since the panel draws none, with the small space on the glyph's side.
struct TooltipView: View {
    let text: String
    var shortcut: String? = nil
    var edge: TooltipEdge = .below

    var body: some View {
        HStack(spacing: Space.s) {
            Text(text)
                .foregroundStyle(Ink.primary)
            if let shortcut {
                KeyCaps(shortcut)
            }
        }
        .font(Typography.label)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs + 1)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .padding(Space.m)
        .padding(edge == .above ? .bottom : .top, Space.xs)
    }
}

/// Where a glyph is on screen, asked at the moment the tooltip shows. A
/// probe view behind the glyph that answers `hitTest` with nil, so it
/// never sits between SwiftUI and the glyph's own hover and press.
private struct TooltipAnchor: NSViewRepresentable {
    @MainActor final class Box {
        weak var view: NSView?
        var screenRect: NSRect? {
            guard let view, let window = view.window else { return nil }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
    }

    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    let box: Box

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        box.view = probe
        return probe
    }

    func updateNSView(_ nsView: Probe, context: Context) {}
}

private struct TooltipModifier: ViewModifier {
    let text: String
    /// The glyph's name, what `--tip <name>` matches for a snapshot.
    let name: String
    let shortcut: String?
    @Environment(\.tooltipEdge) private var edge
    @State private var box = TooltipAnchor.Box()
    private static let forced = Launch.value(after: "--tip")

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchor(box: box))
            .onHover { inside in
                if inside {
                    TooltipPanel.shared.schedule(text, shortcut: shortcut, edge: edge) { [box] in box.screenRect }
                } else {
                    TooltipPanel.shared.cancel("pointer left")
                }
            }
            .simultaneousGesture(TapGesture().onEnded { TooltipPanel.shared.cancel("pressed") })
            .onAppear {
                // Held open for a snapshot, once the window has settled at
                // the size `--window` asked for.
                if Self.forced == name {
                    FileHandle.standardError.write(Data("tooltip: forced for '\(name)'\n".utf8))
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        TooltipPanel.shared.schedule(text, shortcut: shortcut, edge: edge, atOnce: true) { [box] in
                            box.screenRect
                        }
                    }
                }
            }
            .onDisappear { TooltipPanel.shared.cancel("glyph went") }
    }
}

extension View {
    /// The app's tooltip for a glyph: `text` after the pointer rests,
    /// `name` being the glyph's label for `--tip`, and `shortcut` the key
    /// that does the same.
    func tooltip(_ text: String, name: String, shortcut: String? = nil) -> some View {
        modifier(TooltipModifier(text: text, name: name, shortcut: shortcut))
    }
}
