import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The quick sketch's key (revision 59): a short list macOS is not already
/// using. ⌥⌘Space is Finder's search and ⌃⌥Space the input sources out of
/// the box, so a key on either looks registered and never fires (Donna's
/// sharp edge), and ⌥⇧Space is Donna's own capture.
enum SketchKey: String, CaseIterable, Identifiable {
    case controlShiftSpace, controlOptionCommandSpace, shiftCommandSpace, off

    static let standard = SketchKey.controlShiftSpace
    static let defaultsKey = "sketchKey"

    static var chosen: SketchKey {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SketchKey.init(rawValue:)) ?? standard
    }

    var id: String { rawValue }

    /// The keys as `KeyCaps` reads them, one cap each.
    var shortcut: String? {
        switch self {
        case .controlShiftSpace: return "⌃⇧Space"
        case .controlOptionCommandSpace: return "⌃⌥⌘Space"
        case .shiftCommandSpace: return "⇧⌘Space"
        case .off: return nil
        }
    }

    var title: String {
        switch self {
        case .controlShiftSpace: return "Control Shift Space"
        case .controlOptionCommandSpace: return "Control Option Command Space"
        case .shiftCommandSpace: return "Shift Command Space"
        case .off: return "Off"
        }
    }

    fileprivate var modifiers: UInt32? {
        switch self {
        case .controlShiftSpace: return UInt32(controlKey | shiftKey)
        case .controlOptionCommandSpace: return UInt32(controlKey | optionKey | cmdKey)
        case .shiftCommandSpace: return UInt32(shiftKey | cmdKey)
        case .off: return nil
        }
    }
}

/// One key held by the whole Mac. Carbon's `RegisterEventHotKey` is old,
/// but it is the one way to a global key that asks for no Accessibility
/// permission (Donna's `Hotkey`).
@MainActor
final class SketchHotkey: ObservableObject {
    static let shared = SketchHotkey()

    /// 'ALEX'
    private static let signature: OSType = 0x414C_4558

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onFire: (() -> Void)?

    /// The last key asked for did not register: something else holds it.
    /// Said in Settings, or the feature is silently not there.
    @Published private(set) var failed = false

    func apply(_ key: SketchKey) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        failed = false
        guard let modifiers = key.modifiers else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard id.signature == SketchHotkey.signature else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { MainActor.assumeIsolated { SketchHotkey.shared.onFire?() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            failed = true
            ref = nil
            NSLog("Alex: couldn't claim \(key.title) (OSStatus \(status))")
        }
    }

    var isOn: Bool { ref != nil }
}

/// A borderless panel refuses key status, and a desk that cannot be key
/// takes no keys (Donna's sharp edge). ⌘N and ⌘W are the sketch's own,
/// ahead of the menu bar's New note and Close.
final class SketchPanel: NSPanel {
    var onNew: (() -> Void)?
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "n" { onNew?(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "w" { onClose?(); return true }
        return super.performKeyEquivalent(with: event)
    }

    /// No title bar to take ⌘W's Close from.
    override func cancelOperation(_ sender: Any?) { onClose?() }
}

/// The sketch's edges (revision 63). A borderless window has no frame to
/// resize by, and this one's own edges lie in the clear room kept for the
/// card's shadow, where a press falls through to the app behind. So the
/// card's edges are the grips: this view lies under the hosting view,
/// answers the press in a band along them (`SketchFrame.grip`), wears the
/// resize pointer there, and moves the window's edge while it is dragged.
final class SketchEdges: NSView {
    var tabWidth: CGFloat = Shell.sketchTabMin
    private var cursorShown = false

    init(content: NSView) {
        super.init(frame: .zero)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private func grip(at point: NSPoint) -> Grip? {
        SketchFrame.grip(at: point, in: bounds, margin: Shell.sketchMargin,
                         tab: CGSize(width: tabWidth, height: Shell.sketchTab))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return grip(at: local) != nil ? self : super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The window server hands a press on a clear pixel to the window
    /// behind, so the bands outside the card are filled with the least
    /// ink there is: one part in 255, no colour anyone can see.
    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: Shell.sketchMargin, dy: Shell.sketchMargin)
        let band = card.insetBy(dx: -SketchFrame.outside, dy: -SketchFrame.outside)
        NSColor(white: 0, alpha: 1.0 / 255).setFill()
        let ring = NSBezierPath(rect: band)
        ring.append(NSBezierPath(rect: card).reversed)
        ring.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited,
                                                              .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let grip = grip(at: convert(event.locationInWindow, from: nil))
        if let grip {
            Self.cursor(grip).set()
            cursorShown = true
        } else if cursorShown {
            NSCursor.arrow.set()
            cursorShown = false
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if cursorShown { NSCursor.arrow.set() }
        cursorShown = false
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, let grip = grip(at: convert(event.locationInWindow, from: nil)) else {
            return super.mouseDown(with: event)
        }
        let start = NSEvent.mouseLocation, frame = window.frame
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let now = NSEvent.mouseLocation
            window.setFrame(SketchFrame.resized(frame, grip: grip,
                                                by: CGVector(dx: now.x - start.x, dy: now.y - start.y),
                                                minimum: window.minSize),
                            display: true)
            Self.cursor(grip).set()
            if next.type == .leftMouseUp { break }
        }
    }

    private static func cursor(_ grip: Grip) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch grip {
        case .left: position = .left
        case .right: position = .right
        case .top: position = .top
        case .bottom: position = .bottom
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        }
        return .frameResize(position: position, directions: .all)
    }
}

/// The floating desk (revision 59): brought over whatever is in front by
/// the key, put away by the key again or by Esc with nothing to put down,
/// handing the Mac back to the app that was in front.
@MainActor
final class QuickSketch: NSObject, NSWindowDelegate {
    static let shared = QuickSketch()
    static let frameName = "QuickSketch"

    weak var model: AppModel?
    private var panel: SketchPanel?
    private var previous: NSRunningApplication?
    /// The windows put away while the sketch is up: activating Alex
    /// would bring them over the app that was in front (revision 59).
    private var stowed: [NSWindow] = []
    /// The style panel, floating outside the sketch at its left while
    /// something is selected: a child window, so it moves with it.
    private var styleWindow: NSPanel?
    private var styleShown = false
    private var edges: SketchEdges?
    /// Whether the sketch has a place of its own yet, from this run or
    /// the last: the first time it comes up at the screen's foot.
    private var placedBefore = false

    var isShown: Bool { panel?.isVisible == true }

    func install(model: AppModel) {
        self.model = model
        SketchHotkey.shared.onFire = { [weak self] in self?.toggle() }
        SketchHotkey.shared.apply(SketchKey.chosen)
    }

    func toggle() {
        if isShown, panel?.isKeyWindow == true { hide() } else { show() }
    }

    func show() {
        guard let model else { return }
        let store = model.sketch
        if model.vault.root != nil, !store.isOpen { store.openMostRecent() }
        let panel = existingPanel(model: model)
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previous = front
            // Called from another app: only the sketch comes forward, the
            // window and its chrome stay behind that app.
            stowed = NSApp.windows.filter {
                $0 !== panel && !($0 is NSPanel) && $0.isVisible && !$0.isMiniaturized && $0.isOnActiveSpace
            }
            stowed.forEach { $0.orderOut(nil) }
        }
        place(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        PopupMenu.shared.close()
        setStylePanel(false)
        panel.orderOut(nil)
        if let previous, !previous.isTerminated { previous.activate() }
        // Back where they were, behind the app given back the Mac.
        stowed.forEach { $0.orderBack(nil) }
        stowed = []
        previous = nil
    }

    private func existingPanel(model: AppModel) -> SketchPanel {
        if let panel { return panel }
        let size = NSSize(width: Shell.sketch.width + 2 * Shell.sketchMargin,
                          height: Shell.sketch.height + Shell.sketchTab + 2 * Shell.sketchMargin)
        let panel = SketchPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The card draws its own shadow, the style panel's.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: Shell.sketchMin.width + 2 * Shell.sketchMargin,
                               height: Shell.sketchMin.height + Shell.sketchTab + 2 * Shell.sketchMargin)
        panel.delegate = self
        panel.onNew = { [weak model] in model?.sketch.newSketch() }
        panel.onClose = { [weak self] in self?.hide() }
        let root = QuickSketchView(store: model.sketch,
                                   onClose: { [weak self] in self?.hide() },
                                   onOpenInWindow: { [weak self, weak model] path in
                                       self?.hide()
                                       model?.openInWindow(path)
                                   },
                                   onStylePanel: { [weak self] shown in self?.setStylePanel(shown) },
                                   onTabWidth: { [weak self] width in self?.edges?.tabWidth = width })
            .environmentObject(model.vault)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let edges = SketchEdges(content: hosting)
        self.edges = edges
        panel.contentView = edges
        panel.acceptsMouseMovedEvents = true
        placedBefore = panel.setFrameUsingName(Self.frameName)
        panel.setFrameAutosaveName(Self.frameName)
        self.panel = panel
        return panel
    }

    /// Where it was last put, on the screen the pointer is on, at the
    /// size it was last given (revision 63); the first time, or on
    /// another screen, at the foot of that one (`SketchFrame.placed`).
    private func place(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = SketchFrame.placed(placedBefore ? panel.frame : nil, size: panel.frame.size, on: visible,
                                       margin: Shell.sketchMargin, gutter: Shell.gutter)
        panel.setFrame(frame, display: true)
        placedBefore = true
    }

    func windowDidResize(_ notification: Notification) {
        panel?.invalidateShadow()
        placeStylePanel()
    }

    func windowDidMove(_ notification: Notification) { placeStylePanel() }

    // MARK: - The style panel, outside

    private func setStylePanel(_ shown: Bool) {
        styleShown = shown
        guard let panel, let model else { return }
        guard shown, panel.isVisible else {
            styleWindow?.orderOut(nil)
            return
        }
        let style = styleWindow ?? makeStyleWindow(store: model.sketch)
        style.appearance = panel.effectiveAppearance
        if style.parent !== panel { panel.addChildWindow(style, ordered: .above) }
        placeStylePanel()
        style.orderFront(nil)
    }

    private func makeStyleWindow(store: CanvasStore) -> NSPanel {
        let style = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        style.isOpaque = false
        style.backgroundColor = .clear
        // The shadow is the card's own `Elevation`, not the window's.
        style.hasShadow = false
        style.isReleasedWhenClosed = false
        style.hidesOnDeactivate = false
        style.animationBehavior = .none
        style.level = .floating
        style.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: FloatingStylePanel(store: store) { [weak self] _ in
            DispatchQueue.main.async { self?.placeStylePanel() }
        })
        style.contentView = hosting
        styleWindow = style
        return style
    }

    /// Its top level with the desk's, a gutter clear of the sketch's left
    /// edge; inside the desk's left when the screen has no room there.
    private func placeStylePanel() {
        guard styleShown, let panel, let style = styleWindow, let hosting = style.contentView else { return }
        let size = hosting.fittingSize
        let m = FloatingStylePanel.margin
        // The sketch's own card, inside its window's shadow room.
        let card = panel.frame.insetBy(dx: Shell.sketchMargin, dy: Shell.sketchMargin)
        let top = card.maxY - Shell.sketchTab + m
        // Its window ends at the sketch's card: the panel a gutter short.
        var x = card.minX - size.width
        if let visible = panel.screen?.visibleFrame, x + m < visible.minX {
            x = card.minX + Shell.gutter - m
        }
        style.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// `--sketch on`: the sketch up at launch, its picture taken with the
    /// snapshot (a window of its own).
    var snapshotWindow: NSWindow? { isShown ? panel : nil }

    /// The sketch and its floating style panel in one picture, for a
    /// snapshot: the panel stands outside the sketch's frame.
    func snapshot() -> NSBitmapImageRep? {
        guard let panel, isShown else { return nil }
        let windows = [panel] + [styleWindow].compactMap { $0 }.filter(\.isVisible)
        let bounds = windows.map(\.frame).reduce(panel.frame) { $0.union($1) }
        let scale = panel.backingScaleFactor
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                         pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for window in windows {
            guard let view = window.contentView,
                  let part = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: part)
            part.draw(in: NSRect(x: window.frame.minX - bounds.minX, y: window.frame.minY - bounds.minY,
                                 width: window.frame.width, height: window.frame.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
