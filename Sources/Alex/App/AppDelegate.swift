import AppKit

/// Launch-time hooks. The one that matters for development: `--snapshot <png>`
/// renders the main window to a file once it has settled and quits, so a build
/// can be looked at without a screen or a screen-recording permission.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            let seen = NSApp.windows.map {
                "\($0.className) '\($0.title)' visible=\($0.isVisible) frame=\($0.frame)"
            }.joined(separator: "; ")
            FileHandle.standardError.write(Data("snapshot: no visible window (\(seen))\n".utf8))
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        }
    }
}
