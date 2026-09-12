import Foundation

/// Launch arguments, all optional and all for development: `--vault <dir>`,
/// `--select <vault path>`, `--snapshot <png>`, `--snapshot-delay <seconds>`,
/// `--door on`. Every flag takes a value, because AppKit reads `-key value`
/// pairs off the command line as defaults overrides and a bare flag shifts
/// every pair after it — the window never opened until that was found.
enum Launch {
    static func value(after flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}
