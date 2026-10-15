import SwiftUI
import AppKit

/// The window's own chrome brought inside the sidebar (PLAN.md, revision
/// 21): the traffic lights stand in the sidebar's head row, shown or
/// folded to that row (revision 37), rather than in a strip above
/// everything. AppKit puts them in
/// the title bar's container at its own height; this makes the container
/// as tall as the head row's centre needs and lays the three buttons
/// along it from `leading`, keeping AppKit's own spacing. AppKit lays the
/// title bar out again on a resize and after full screen, so each of
/// those puts them back. In full screen the lights are the system's.
struct WindowChrome: NSViewRepresentable {
    /// Where the close button's leading edge goes, from the window's left.
    let leading: CGFloat
    /// The height of the lights' row's centre, from the window's top.
    let centreY: CGFloat

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.leading = leading
        view.centreY = centreY
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.leading = leading
        view.centreY = centreY
        view.place()
    }
}

final class ChromeView: NSView {
    var leading: CGFloat = 0
    var centreY: CGFloat = 0
    private var observers: [NSObjectProtocol] = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                          NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.place() }
            })
        }
        place()
        DispatchQueue.main.async { [weak self] in self?.place() }
        // `--hit-test x,y[;x,y…]`: which view answers a click at each
        // point (from the window's top left), logged once the window has
        // settled. How the head row was proved to take its clicks.
        if let spec = Launch.value(after: "--hit-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.report(spec)
            }
        }
        // `--right-click x,y`: a right press sent through the window at a
        // point (from the window's top left), so a snapshot shows the
        // menu it opens; pair it with `--snapshot-delay 1.7`. Early, before
        // a pointer resting over the window can move anything. How the
        // right-click menus were proved.
        if let spec = Launch.value(after: "--copy-paste") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.copyPaste(spec)
            }
        }
        // Late enough that the desk's opening camera move has settled.
        if let spec = Launch.value(after: "--keys") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.keys(spec)
            }
        }
        if let spec = Launch.value(after: "--right-click") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.rightClick(spec)
            }
        }
    }

    /// `--copy-paste x,y`: a click at a point, then ⌘C and ⌘V through the
    /// window as key presses, the pasteboard's types logged between. How
    /// copy and paste on the desk were proved (revision 48).
    private func copyPaste(_ spec: String) {
        let xy = spec.split(separator: ",").compactMap { Double($0) }
        guard let window, xy.count == 2 else { return }
        let point = NSPoint(x: xy[0], y: window.frame.height - xy[1])
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            NSApp.sendEvent(event)
        }
        // The Edit menu's own items, pressed as a click on them would be:
        // a synthetic ⌘ key beats the menu's validation and does nothing.
        func press(_ key: String, after delay: Double, then: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let edit = NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu
                edit?.update()
                if let i = edit?.items.firstIndex(where: { $0.keyEquivalent == key && $0.isEnabled }) {
                    edit?.performActionForItem(at: i)
                }
                then()
            }
        }
        press("c", after: 0.5) {
            let types = NSPasteboard.general.types?.map(\.rawValue) ?? []
            FileHandle.standardError.write(Data("copy-paste: after ⌘C \(types)\n".utf8))
            press("v", after: 0.5) {
                FileHandle.standardError.write(Data("copy-paste: ⌘V sent\n".utf8))
            }
        }
    }

    /// `--keys x,y[,clicks]:key,key…`: a click at a point, then key presses sent
    /// through the window a beat apart — `return`, `escape`, `cmd-return`, `cmd-z`, `cmd-a`, an arrow
    /// (`left`, `shift-right`…), `shift-2`,
    /// `tab` or a word typed as it stands — each logged with what the desk
    /// is writing in after it. How Enter on a box was proved (revision 50).
    private func keys(_ spec: String) {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        let xy = parts[0].split(separator: ",").compactMap { Double($0) }
        guard let window, xy.count >= 2 else { return }
        let point = NSPoint(x: xy[0], y: window.frame.height - xy[1])
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        FileHandle.standardError.write(Data("keys: window key \(window.isKeyWindow) active \(NSApp.isActive)\n".utf8))
        // A third number is how many clicks: `2` double-clicks.
        for click in 1...max(1, xy.count > 2 ? Int(xy[2]) : 1) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 0, clickCount: click, pressure: 1) else { continue }
                NSApp.sendEvent(event)
            }
        }
        let presses = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
        for (i, press) in presses.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(i + 1)) { [weak window] in
                guard let window else { return }
                // ⌘Z as the window's responder chain takes it: a synthetic
                // ⌘ key does not get past the menu's validation (see
                // `copyPaste`), and the menu's action goes to the key
                // window, which a backgrounded run's window may not be.
                // ⌘A as the Edit menu's Select All sends it, to the key
                // window's responder chain and on to the app's delegate.
                if press == "cmd-a" {
                    let taken = NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                    FileHandle.standardError.write(Data("keys: cmd-a taken \(taken)\n".utf8))
                    return
                }
                if press == "cmd-z" {
                    // On the desk SwiftUI's menu item takes it, to the
                    // window's undo manager: the stack the store records in.
                    var taken = window.firstResponder?.tryToPerform(#selector(ShapeTextView.undo(_:)), with: nil) ?? false
                    if !taken, let undo = window.undoManager, undo.canUndo {
                        undo.undo()
                        taken = true
                    }
                    let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
                    FileHandle.standardError.write(Data("keys: cmd-z taken \(taken) by the chain from \(responder)\n".utf8))
                    return
                }
                let (chars, code, flags): (String, UInt16, NSEvent.ModifierFlags) = switch press {
                case "return": ("\r", 36, [])
                case "cmd-return": ("\r", 36, .command)
                case "escape": ("\u{1b}", 53, [])
                case "tab": ("\t", 48, [])
                case "left": (String(UnicodeScalar(NSLeftArrowFunctionKey)!), 123, [.numericPad, .function])
                case "right": (String(UnicodeScalar(NSRightArrowFunctionKey)!), 124, [.numericPad, .function])
                case "down": (String(UnicodeScalar(NSDownArrowFunctionKey)!), 125, [.numericPad, .function])
                case "up": (String(UnicodeScalar(NSUpArrowFunctionKey)!), 126, [.numericPad, .function])
                case "shift-right": (String(UnicodeScalar(NSRightArrowFunctionKey)!), 124, [.numericPad, .function, .shift])
                case "shift-2": ("@", 19, .shift)
                default: (press, 0, [])
                }
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: window.windowNumber, context: nil,
                                                       characters: chars, charactersIgnoringModifiers: chars,
                                                       isARepeat: false, keyCode: code) else { continue }
                    NSApp.sendEvent(event)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
                    FileHandle.standardError.write(Data("keys: after \(press) first responder \(responder)\n".utf8))
                }
            }
        }
    }

    private func rightClick(_ spec: String) {
        let xy = spec.split(separator: ",").compactMap { Double($0) }
        guard let window, xy.count == 2 else { return }
        let point = NSPoint(x: xy[0], y: window.frame.height - xy[1])
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            NSApp.sendEvent(event)
        }
        // A view that also takes a double click answers a beat later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            FileHandle.standardError.write(Data("right-click \(xy[0]),\(xy[1]): menu \(PopupMenu.shared.titles)\n".utf8))
        }
    }

    func place() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let bar = close.superview, let container = bar.superview else { return }
        let height = (centreY * 2).rounded()
        let frameHeight = window.frame.height
        let wanted = NSRect(x: 0, y: frameHeight - height, width: window.frame.width, height: height)
        if container.frame != wanted { container.frame = wanted }
        if bar.frame != container.bounds { bar.frame = container.bounds }
        let gap = mini.frame.minX - close.frame.minX
        for (i, button) in [close, mini, zoom].enumerated() {
            let origin = NSPoint(x: leading + CGFloat(i) * gap, y: ((height - button.frame.height) / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    private func report(_ spec: String) {
        guard let window, let frame = window.contentView?.superview else { return }
        for pair in spec.split(separator: ";") {
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { continue }
            let point = NSPoint(x: xy[0], y: frame.bounds.height - xy[1])
            var chain: [String] = []
            var view = frame.hitTest(point)
            while let v = view, chain.count < 6 {
                chain.append(String(describing: type(of: v)))
                view = v.superview
            }
            FileHandle.standardError.write(Data("hit-test \(xy[0]),\(xy[1]): \(chain.joined(separator: " < "))\n".utf8))
        }
        if let close = window.standardWindowButton(.closeButton), let zoom = window.standardWindowButton(.zoomButton) {
            FileHandle.standardError.write(Data("lights: close \(close.frame) zoom \(zoom.frame)\n".utf8))
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
