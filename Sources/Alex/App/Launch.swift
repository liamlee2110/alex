import Foundation

/// Launch arguments, all optional and all for development: `--vault <dir>`,
/// `--select <vault path>`, `--snapshot <png>`, `--snapshot-delay <seconds>`,
/// `--window <w>x<h>` (the content size, for a README-sized snapshot),
/// `--hover <vault path>` (that card's chrome held open, since a snapshot
/// has no pointer), `--sidebar on|off` (the sidebar, without touching
/// what is remembered), `--door on`, `--menu <label>` (that button's menu
/// held open), `--right-click <x>,<y>` (a right press sent through the
/// window, its menu logged), `--copy-paste <x>,<y>` (a click there, then
/// ⌘C and ⌘V), `--select-text <words>` (those words selected
/// in the first editor holding them, so the format bar shows). Every flag takes a value, because AppKit
/// reads `-key value` pairs off the command line as defaults overrides and
/// a bare flag shifts every pair after it — the window never opened until
/// that was found.
enum Launch {
    static func value(after flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}

/// `ALEX_TRACE=1` in the environment prints store and viewport transitions
/// to stderr, for chasing a launch-order bug without a debugger.
enum Trace {
    static let on = ProcessInfo.processInfo.environment["ALEX_TRACE"] == "1"
    static func log(_ message: @autoclosure () -> String) {
        guard on else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}
