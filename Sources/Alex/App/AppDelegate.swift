import AppKit

/// Launch-time hooks. The one that matters for development: `--snapshot <png>`
/// renders the main window to a file once it has settled and quits, so a build
/// can be looked at without a screen or a screen-recording permission.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The window's canvas, for the Edit menu's Select All on the desk.
    weak var canvas: CanvasStore?

    /// ⌘A with nothing that takes text in focus (revision 53): the menu
    /// item's action falls through the responder chain to the delegate,
    /// so a focused editor or field keeps its own Select All, and on the
    /// desk every node is selected. The menu claims ⌘A even while the
    /// item is disabled, so a key handler on the desk never sees it.
    @objc func selectAll(_ sender: Any?) {
        MainActor.assumeIsolated { canvas?.selectAll() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // `--appearance dark|light` forces one appearance, so a snapshot can
        // check both sides of every dynamic colour without touching the
        // machine's own setting. AppKit ignores `-AppleInterfaceStyle`.
        switch Launch.value(after: "--appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        // `--window 900x650` sizes the window's content, so a snapshot for
        // the README comes out at the README's size whatever the window
        // remembered. Once the window exists, before the snapshot settles.
        if let spec = Launch.value(after: "--window") {
            let parts = spec.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }?
                        .setContentSize(NSSize(width: parts[0], height: parts[1]))
                }
            }
        }
        if let path = Snapshot.requestedPath(CommandLine.arguments) {
            let delay = Launch.value(after: "--snapshot-delay").flatMap(Double.init) ?? 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Snapshot.write(to: path)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

enum Snapshot {
    static func requestedPath(_ arguments: [String]) -> String? {
        Launch.value(after: "--snapshot", in: arguments)
    }

    @MainActor
    static func write(to path: String) {
        // The frame view, not the content view: the title bar strip is part
        // of the picture now that the wood runs under it. Settings is a sheet
        // in this window (revision 41), so `--settings on` is in the picture.
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            let seen = NSApp.windows.map {
                "\($0.className) '\($0.title)' visible=\($0.isVisible) frame=\($0.frame)"
            }.joined(separator: "; ")
            FileHandle.standardError.write(Data("snapshot: no visible window (\(seen))\n".utf8))
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        // A tooltip held open by `--tip`, a menu held open by `--menu`, the
        // format bar over `--select-text`:
        // windows of their own, drawn into the picture where they float.
        let floating = [FormatBar.showing].compactMap { $0 } + PopupMenu.shared.showing
            + [TooltipPanel.shared.showing].compactMap { $0 }
        for panel in floating {
            guard let panelView = panel.contentView,
                  let panelRep = panelView.bitmapImageRepForCachingDisplay(in: panelView.bounds) else { continue }
            panelView.cacheDisplay(in: panelView.bounds, to: panelRep)
            let image = NSImage(size: panelView.bounds.size)
            image.addRepresentation(panelRep)
            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = context
                image.draw(in: NSRect(x: panel.frame.minX - window.frame.minX,
                                      y: panel.frame.minY - window.frame.minY,
                                      width: panel.frame.width, height: panel.frame.height))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if Launch.value(after: "--tip") != nil, TooltipPanel.shared.showing == nil {
            FileHandle.standardError.write(Data("snapshot: --tip asked, no tooltip showing\n".utf8))
        }
        if PopupMenu.forced != nil, !PopupMenu.shared.isOpen {
            FileHandle.standardError.write(Data("snapshot: --menu asked, no menu showing\n".utf8))
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        }
    }
}
