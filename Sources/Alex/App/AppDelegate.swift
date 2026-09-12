import AppKit

/// Launch-time hooks. The one that matters for development: `--snapshot <png>`
/// renders the main window to a file once it has settled and quits, so a build
/// can be looked at without a screen or a screen-recording permission.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let path = Snapshot.requestedPath(CommandLine.arguments) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Snapshot.write(to: path)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Launch arguments, all optional and all for development: `--vault <dir>`,
/// `--select <vault path>`, `--snapshot <png>`.
enum Launch {
    static func value(after flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}

enum Snapshot {
    static func requestedPath(_ arguments: [String]) -> String? {
        Launch.value(after: "--snapshot", in: arguments)
    }

    @MainActor
    static func write(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("snapshot: no visible window\n".utf8))
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
