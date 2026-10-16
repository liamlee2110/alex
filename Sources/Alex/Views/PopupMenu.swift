import SwiftUI
import AppKit

// The app's own menu (revision 23): every menu a button opens and every
// right-click menu is this panel, never an `NSMenu` — the card of the
// slash menu and the tooltip, a hairline, ink rows, one grey square under
// the row the pointer or the arrow keys are on. The menu bar is the
// system's; a text view's Cut, Copy and Paste stay its own. `run-tests.sh`
// lints SwiftUI's `Menu` and `.contextMenu` out of the views.

/// One row of a menu: a verb, a submenu, or the hairline between groups.
struct MenuItem {
    enum Role {
        case action(@MainActor () -> Void)
        case submenu([MenuItem])
        case divider
    }

    /// A second verb on the row, an `IconButton` at its trailing edge
    /// while the row is lit, the title giving way to it: the workspace
    /// list's remove. The menu stays open and redraws its rows after it.
    struct Trailing {
        var symbol: Glyph
        var label: String
        var action: @MainActor () -> Void
    }

    var title = ""
    var symbol: Glyph? = nil
    var checked = false
    var enabled = true
    var trailing: Trailing? = nil
    /// The key that does the same, said at the row's end as `KeyCaps`
    /// (revision 40) and bound to nothing: a bare key on a menu item
    /// would fire while typing in a note (revision 22), so the desk
    /// reads the tools' keys itself and the menu bar holds the ⌘ ones.
    var shortcut: String? = nil
    var role: Role

    init(_ title: String, symbol: Glyph? = nil, checked: Bool = false, enabled: Bool = true,
         shortcut: String? = nil, trailing: Trailing? = nil, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.symbol = symbol
        self.checked = checked
        self.enabled = enabled
        self.shortcut = shortcut
        self.trailing = trailing
        self.role = .action(action)
    }

    private init(role: Role) { self.role = role }

    static var divider: MenuItem { MenuItem(role: .divider) }

    static func submenu(_ title: String, symbol: Glyph? = nil,
                        @MenuBuilder _ items: () -> [MenuItem]) -> MenuItem {
        var item = MenuItem(role: .submenu(items()))
        item.title = title
        item.symbol = symbol
        return item
    }

    var isDivider: Bool { if case .divider = role { return true } else { return false } }
    var children: [MenuItem]? { if case .submenu(let items) = role { return items } else { return nil } }
    /// What the arrow keys stop on: not a hairline, not a greyed verb.
    var selectable: Bool { !isDivider && enabled }
}

/// Menus read as they did under SwiftUI's `Menu`: rows, `if`, `for`.
@resultBuilder
enum MenuBuilder {
    static func buildExpression(_ item: MenuItem) -> [MenuItem] { [item] }
    static func buildExpression(_ items: [MenuItem]) -> [MenuItem] { items }
    static func buildBlock(_ parts: [MenuItem]...) -> [MenuItem] { parts.flatMap { $0 } }
    static func buildOptional(_ part: [MenuItem]?) -> [MenuItem] { part ?? [] }
    static func buildEither(first: [MenuItem]) -> [MenuItem] { first }
    static func buildEither(second: [MenuItem]) -> [MenuItem] { second }
    static func buildArray(_ parts: [[MenuItem]]) -> [MenuItem] { parts.flatMap { $0 } }
}

/// Where a menu opens against what opened it.
enum MenuPlacement {
    /// Under a button, its leading edges lined up; over it when the
    /// screen has no room below.
    case below
    /// Over a button at the window's foot: the palette, the workspace.
    case above
    /// A right-click: its top-left corner at the pointer.
    case pointer
}

// MARK: - The panel

/// The menu on screen: one panel per level, the submenus beside their
/// rows. The panels never become key, so the window keeps the keyboard
/// and the menu reads it through a local monitor: ↑↓ move, → opens a
/// submenu, ← closes one, ⏎ and space press, esc closes. A press
/// anywhere else closes the menu and is spent doing so, as the system's
/// menus spend it.
@MainActor
final class PopupMenu {
    static let shared = PopupMenu()

    /// Row and hairline heights, fixed so a submenu can be put beside
    /// its row without asking SwiftUI where the row landed.
    static let row: CGFloat = 26
    static let hairline: CGFloat = Space.s + 1
    /// Inside the card, round the rows.
    static let inset: CGFloat = Space.xs
    /// Transparent room round the card for its shadow: the panel draws none.
    static let margin: CGFloat = Space.m
    static let minWidth: CGFloat = 180

    private final class Level {
        let panel: NSPanel
        let model: MenuModel
        init(panel: NSPanel, model: MenuModel) { self.panel = panel; self.model = model }
    }

    private var levels: [Level] = []
    private weak var parent: NSWindow?
    private var monitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var onClose: (() -> Void)?
    /// The items again, read after a row's trailing verb has run.
    private var reload: (() -> [MenuItem])?
    private var placement: MenuPlacement = .below

    /// The panels on screen, parent first: what a snapshot composites in.
    var showing: [NSPanel] { levels.map(\.panel) }
    var isOpen: Bool { !levels.isEmpty }
    /// The open menu's rows, for a dev run's log.
    var titles: [String] { levels.first?.model.items.map { $0.isDivider ? "—" : $0.title } ?? [] }

    /// `--menu <label>` on the command line: a menu held open for a
    /// snapshot, whatever the app's activity.
    nonisolated static let forced = Launch.value(after: "--menu")

    /// Open `items` against `anchor`, a rect in screen coordinates.
    func open(_ items: [MenuItem], anchor: NSRect, placement: MenuPlacement, in window: NSWindow?,
              reload: (() -> [MenuItem])? = nil, onClose: (() -> Void)? = nil) {
        close()
        guard !items.isEmpty else { return }
        parent = window
        self.onClose = onClose
        self.reload = reload
        self.placement = placement
        let level = makeLevel(items)
        let size = level.panel.frame.size
        let m = Self.margin
        var origin: NSPoint
        switch placement {
        case .pointer:
            origin = NSPoint(x: anchor.minX - m, y: anchor.minY - size.height + m)
        case .below:
            origin = NSPoint(x: anchor.minX - m, y: anchor.minY - Space.xs - size.height + m)
        case .above:
            origin = NSPoint(x: anchor.minX - m, y: anchor.maxY + Space.xs - m)
        }
        if let visible = screen(for: anchor)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX - m), visible.maxX - size.width + m)
            if origin.y + m < visible.minY {
                // No room below: over the button, or up from the pointer.
                origin.y = placement == .pointer ? anchor.minY - m : anchor.maxY + Space.xs - m
            }
            if origin.y + size.height - m > visible.maxY {
                origin.y = visible.maxY - size.height + m
            }
        }
        present(level, at: origin)
        startWatching()
    }

    /// Close every level, and say so to whatever opened it.
    func close() {
        guard !levels.isEmpty else { return }
        closeLevels(from: 0)
        stopWatching()
        let done = onClose
        onClose = nil
        reload = nil
        done?()
    }

    // MARK: Levels

    private func makeLevel(_ items: [MenuItem]) -> Level {
        let model = MenuModel(items: items)
        let depth = levels.count
        model.hover = { [weak self] index in self?.hovered(index, at: depth) }
        model.press = { [weak self] index in self?.pressed(index, at: depth) }
        model.pressTrailing = { [weak self] index in self?.pressedTrailing(index, at: depth) }
        let hosting = NSHostingView(rootView: MenuCard(model: model))
        let size = hosting.fittingSize
        hosting.setFrameSize(size)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shadow is the card's own `Elevation`, not the window's.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting
        if let parent { panel.appearance = parent.effectiveAppearance }
        return Level(panel: panel, model: model)
    }

    private func present(_ level: Level, at origin: NSPoint) {
        level.panel.setFrameOrigin(origin)
        levels.append(level)
        if let parent {
            parent.addChildWindow(level.panel, ordered: .above)
        }
        level.panel.orderFront(nil)
    }

    private func closeLevels(from depth: Int) {
        while levels.count > depth {
            let level = levels.removeLast()
            parent?.removeChildWindow(level.panel)
            level.panel.orderOut(nil)
        }
        if depth > 0, levels.indices.contains(depth - 1) {
            levels[depth - 1].model.openSubmenu = nil
        }
    }

    /// Where row `index` of a level stands on screen, card-relative.
    private func rowTop(_ index: Int, in level: Level) -> CGFloat {
        let above = level.model.items.prefix(index)
            .reduce(CGFloat(0)) { $0 + ($1.isDivider ? Self.hairline : Self.row) }
        return level.panel.frame.maxY - Self.margin - Self.inset - above
    }

    private func openSubmenu(_ index: Int, at depth: Int, highlightFirst: Bool = false) {
        guard levels.indices.contains(depth) else { return }
        let owner = levels[depth]
        guard let children = owner.model.items[index].children, owner.model.items[index].enabled else { return }
        if owner.model.openSubmenu == index, levels.count > depth + 1 {
            if highlightFirst { levels[depth + 1].model.highlightFirst() }
            return
        }
        closeLevels(from: depth + 1)
        owner.model.openSubmenu = index
        let level = makeLevel(children)
        let size = level.panel.frame.size
        let m = Self.margin
        let cardRight = owner.panel.frame.maxX - m
        let top = rowTop(index, in: owner) + Self.inset
        var origin = NSPoint(x: cardRight + 2 - m, y: top + m - size.height)
        if let visible = (owner.panel.screen ?? NSScreen.main)?.visibleFrame {
            if origin.x + size.width - m > visible.maxX {
                // No room at the right: open at the left instead.
                origin.x = owner.panel.frame.minX + m - 2 - size.width + m
            }
            origin.y = max(origin.y, visible.minY - m)
        }
        present(level, at: origin)
        if highlightFirst { level.model.highlightFirst() }
    }

    // MARK: Pointer and keys

    private func hovered(_ index: Int, at depth: Int) {
        guard levels.indices.contains(depth) else { return }
        let model = levels[depth].model
        model.highlighted = index
        if model.items[index].children != nil {
            openSubmenu(index, at: depth)
        } else if model.openSubmenu != nil {
            closeLevels(from: depth + 1)
        }
    }

    private func pressed(_ index: Int, at depth: Int) {
        guard levels.indices.contains(depth) else { return }
        let item = levels[depth].model.items[index]
        guard item.enabled else { return }
        switch item.role {
        case .action(let action):
            close()
            // After the menu is gone, so a verb that runs a modal — an
            // open panel — runs it over a window with nothing floating.
            DispatchQueue.main.async { action() }
        case .submenu:
            openSubmenu(index, at: depth, highlightFirst: true)
        case .divider:
            break
        }
    }

    /// A row's trailing verb: run it, then read the items again and
    /// redraw the top card in place, its edge against the button kept;
    /// with nothing to read them from, or in a submenu, the menu closes.
    private func pressedTrailing(_ index: Int, at depth: Int) {
        guard levels.indices.contains(depth), let trailing = levels[depth].model.items[index].trailing else { return }
        guard depth == 0, let reload else {
            close()
            DispatchQueue.main.async { trailing.action() }
            return
        }
        closeLevels(from: 1)
        trailing.action()
        let items = reload()
        guard !items.isEmpty, let level = levels.first else { close(); return }
        level.model.highlighted = nil
        level.model.items = items
        guard let hosting = level.panel.contentView else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        var frame = level.panel.frame
        // An opening above its button keeps its foot; any other its head.
        if placement != .above { frame.origin.y = frame.maxY - size.height }
        frame.size = size
        level.panel.setFrame(frame, display: true)
    }

    private func key(_ event: NSEvent) -> Bool {
        guard let level = levels.last else { return false }
        let depth = levels.count - 1
        let model = level.model
        switch event.keyCode {
        case 125: model.move(1)                                      // ↓
        case 126: model.move(-1)                                     // ↑
        case 124:                                                    // →
            if let i = model.highlighted, model.items[i].children != nil {
                openSubmenu(i, at: depth, highlightFirst: true)
            }
        case 123:                                                    // ←
            if depth > 0 { closeLevels(from: depth) }
        case 36, 76, 49:                                             // ⏎, enter, space
            if let i = model.highlighted { pressed(i, at: depth) }
        case 53: close()                                             // esc
        default: break
        }
        return true
    }

    /// A press inside a card is the menu's; a press anywhere else,
    /// including the shadow's transparent margin, closes it.
    private func inCard(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        return levels.contains { level in
            level.panel === window
                && NSRect(origin: .zero, size: window.frame.size)
                    .insetBy(dx: Self.margin, dy: Self.margin)
                    .contains(event.locationInWindow)
        }
    }

    private func startWatching() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            guard let self, self.isOpen else { return event }
            switch event.type {
            case .keyDown:
                return self.key(event) ? nil : event
            case .scrollWheel:
                if !self.inCard(event) { self.close() }
                return event
            case .rightMouseDown:
                // Straight on to the next right-click menu.
                if self.inCard(event) { return nil }
                self.close()
                return event
            default:
                if self.inCard(event) { return event }
                self.close()
                return nil
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // A click in another app closes the menu, as the system's
            // close; a menu held for a snapshot stays through one.
            guard Self.forced == nil else { return }
            MainActor.assumeIsolated { self?.close() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            // A snapshot run is never active; its held menu stays.
            guard Self.forced == nil else { return }
            MainActor.assumeIsolated { self?.close() }
        })
        // A snapshot's window settles at `--window` after the menu opens.
        if let parent, Self.forced == nil {
            for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
                observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.close() }
                })
            }
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        monitor = nil
        globalMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func screen(for rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main
    }
}

@MainActor
private final class MenuModel: ObservableObject {
    @Published var items: [MenuItem]
    @Published var highlighted: Int?
    @Published var openSubmenu: Int?
    var hover: (Int) -> Void = { _ in }
    var press: (Int) -> Void = { _ in }
    var pressTrailing: (Int) -> Void = { _ in }

    init(items: [MenuItem]) { self.items = items }

    func move(_ delta: Int) {
        let stops = items.indices.filter { items[$0].selectable }
        guard !stops.isEmpty else { return }
        guard let current = highlighted, let at = stops.firstIndex(of: current) else {
            highlighted = delta > 0 ? stops.first : stops.last
            return
        }
        highlighted = stops[(at + delta + stops.count) % stops.count]
    }

    func highlightFirst() { highlighted = items.indices.first { items[$0].selectable } }
}

// MARK: - The card

/// The menu drawn like every other surface: the floating white, a
/// hairline, the raised shadow; a leading column for a glyph or a tick
/// when any row has one, a chevron after a row that opens a submenu.
private struct MenuCard: View {
    @ObservedObject var model: MenuModel

    private var hasLead: Bool { model.items.contains { $0.symbol != nil || $0.checked } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                if item.isDivider {
                    Rectangle()
                        .fill(Ink.hairline)
                        .frame(height: 1)
                        .padding(.horizontal, Space.s)
                        .frame(height: PopupMenu.hairline)
                } else {
                    row(item, index)
                }
            }
        }
        .padding(PopupMenu.inset)
        .frame(minWidth: PopupMenu.minWidth)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .padding(PopupMenu.margin)
    }

    private func row(_ item: MenuItem, _ index: Int) -> some View {
        let lit = item.enabled && (model.highlighted == index || model.openSubmenu == index)
        // The row's width is set by its title in full, hover or not, so the
        // card never grows under the pointer; what is drawn lies over it,
        // and a lit row's trailing verb takes its room from the title.
        return rowContent(item, trailing: false)
            .hidden()
            .padding(.horizontal, Space.s)
            .frame(height: PopupMenu.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                rowContent(item, trailing: lit && item.trailing != nil, index: index)
                    .padding(.leading, Space.s)
                    .padding(.trailing, lit && item.trailing != nil ? 1 : Space.s)
            }
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(lit ? Ink.wellHover : .clear))
        .opacity(item.enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onHover { inside in if inside { model.hover(index) } }
        .onTapGesture { model.press(index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.checked ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            if let trailing = item.trailing {
                Button(trailing.label) { model.pressTrailing(index) }
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ item: MenuItem, trailing: Bool, index: Int = 0) -> some View {
        HStack(spacing: Space.s) {
            if hasLead {
                // The column holds its width on a row with nothing in it,
                // so every title starts on one line.
                Color.clear
                    .frame(width: Icon.control + 3, height: PopupMenu.row)
                    .overlay {
                        if item.checked {
                            GlyphImage(.check, weight: .medium)
                        } else if let symbol = item.symbol {
                            GlyphImage(symbol)
                        }
                    }
                    .foregroundStyle(Ink.icon)
            }
            Text(item.title)
                .font(Typography.body)
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: trailing ? Space.xs : Space.l)
            if trailing, let verb = item.trailing {
                IconButton(symbol: verb.symbol, label: verb.label, size: .small) {
                    model.pressTrailing(index)
                }
            } else if let shortcut = item.shortcut {
                KeyCaps(shortcut)
            } else if item.children != nil {
                GlyphImage(.chevronRight, size: Icon.mark, weight: .medium)
                    .foregroundStyle(Ink.muted)
            }
        }
    }
}

// MARK: - Opening one

/// Where a view is on screen: a probe behind it that answers `hitTest`
/// with nil, so it never sits between SwiftUI and the view's own hover
/// and press.
private struct MenuAnchor: NSViewRepresentable {
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

    func updateNSView(_ nsView: Probe, context: Context) { box.view = nsView }
}

/// A button that opens the app's menu: the label is anything, the items
/// are built when it is pressed, so they read the state of that moment.
/// `name` is what `--menu` matches to hold it open for a snapshot.
struct MenuButton<Label: View>: View {
    var name: String
    var placement: MenuPlacement? = nil
    @MenuBuilder let items: () -> [MenuItem]
    @ViewBuilder let label: (_ open: Bool) -> Label

    @Environment(\.tooltipEdge) private var edge
    @State private var box = MenuAnchor.Box()
    @State private var open = false

    var body: some View {
        Button {
            show()
        } label: {
            label(open)
        }
        .background(MenuAnchor(box: box))
        .onAppear {
            guard PopupMenu.forced == name else { return }
            Task {
                // Held open for a snapshot, once the glyph has a window:
                // a cold launch on a big vault can take longer than a
                // fixed wait, as the tooltip's `--tip` learnt.
                try? await Task.sleep(for: .milliseconds(700))
                var tries = 0
                while box.screenRect == nil, tries < 30 {
                    try? await Task.sleep(for: .milliseconds(100))
                    tries += 1
                }
                show()
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    private func show() {
        guard let rect = box.screenRect else { return }
        TooltipPanel.shared.cancel("menu opened")
        open = true
        PopupMenu.shared.open(items(), anchor: rect, placement: placement ?? (edge == .above ? .above : .below),
                              in: box.view?.window, reload: items) { open = false }
    }
}

/// A right-click menu. SwiftUI does not ask an AppKit view behind or
/// over it whether a right press is its, so the press is made a control-
/// click, the Mac's other way of asking for a menu, and SwiftUI's own hit
/// testing takes it to the frontmost view that has a menu: a card, not
/// the card under the sidebar. Ahead of the view's own taps, so a right
/// press on a tree row does not open the row.
private struct PopupContextMenu: ViewModifier {
    let items: () -> [MenuItem]

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(SpatialTapGesture().modifiers(.control).onEnded { _ in open() })
            .onAppear { SecondaryClick.install() }
    }

    private func open() {
        guard let window = SecondaryClick.lastWindow ?? NSApp.keyWindow else { return }
        let point = SecondaryClick.lastPoint ?? NSEvent.mouseLocation
        TooltipPanel.shared.cancel("menu opened")
        PopupMenu.shared.open(items(), anchor: NSRect(origin: point, size: .zero),
                              placement: .pointer, in: window)
    }
}

/// The right press made a control-click, app-wide, once. AppKit already
/// treats the two alike — a text view or a web view answers either with
/// its own menu — so nothing that is not ours sees a difference.
@MainActor
enum SecondaryClick {
    private static var monitor: Any?
    /// Where the last right press was, on screen, and its window: where
    /// the menu it asked for opens.
    static var lastPoint: NSPoint?
    static weak var lastWindow: NSWindow?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { event in
            // A menu's or a tooltip's panel is not asked; the quick
            // sketch's desk is (revision 59).
            guard let window = event.window, !(window is NSPanel) || window is SketchPanel else { return event }
            if event.type == .rightMouseDown {
                lastPoint = window.convertPoint(toScreen: event.locationInWindow)
                lastWindow = window
            }
            let type: NSEvent.EventType = event.type == .rightMouseDown ? .leftMouseDown : .leftMouseUp
            return NSEvent.mouseEvent(with: type, location: event.locationInWindow,
                                      modifierFlags: event.modifierFlags.union(.control),
                                      timestamp: event.timestamp, windowNumber: event.windowNumber,
                                      context: nil, eventNumber: event.eventNumber,
                                      clickCount: event.clickCount, pressure: event.pressure) ?? event
        }
    }
}

extension View {
    /// The app's right-click menu, in place of SwiftUI's `.contextMenu`.
    func popupMenu(@MenuBuilder _ items: @escaping () -> [MenuItem]) -> some View {
        modifier(PopupContextMenu(items: items))
    }
}
