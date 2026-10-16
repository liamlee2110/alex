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
        panel.orderOut(nil)
        if let previous, !previous.isTerminated { previous.activate() }
        // Back where they were, behind the app given back the Mac.
        stowed.forEach { $0.orderBack(nil) }
        stowed = []
        previous = nil
    }

    private func existingPanel(model: AppModel) -> SketchPanel {
        if let panel { return panel }
        let size = NSSize(width: Shell.sketch.width, height: Shell.sketch.height + Shell.sketchTab)
        let panel = SketchPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: Shell.sketchMin.width, height: Shell.sketchMin.height + Shell.sketchTab)
        panel.delegate = self
        panel.onNew = { [weak model] in model?.sketch.newSketch() }
        panel.onClose = { [weak self] in self?.hide() }
        let root = QuickSketchView(store: model.sketch,
                                   onClose: { [weak self] in self?.hide() },
                                   onOpenInWindow: { [weak self, weak model] path in
                                       self?.hide()
                                       model?.openInWindow(path)
                                   })
            .environmentObject(model.vault)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrameUsingName(Self.frameName)
        panel.setFrameAutosaveName(Self.frameName)
        self.panel = panel
        return panel
    }

    /// Every time it comes up: at the foot of the screen the pointer is
    /// on, in the middle, a gutter above the Dock, at the size it was
    /// last given.
    private func place(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = NSSize(width: min(panel.frame.width, visible.width - 2 * Shell.gutter),
                          height: min(panel.frame.height, visible.height - 2 * Shell.gutter))
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + Shell.gutter,
                              width: size.width, height: size.height), display: true)
    }

    func windowDidResize(_ notification: Notification) { panel?.invalidateShadow() }

    /// `--sketch on`: the sketch up at launch, its picture taken with the
    /// snapshot (a window of its own).
    var snapshotWindow: NSWindow? { isShown ? panel : nil }
}
