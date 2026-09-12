import Foundation

/// Launch arguments, all optional and all for development: `--vault <dir>`,
/// `--select <vault path>`, `--snapshot <png>`.
enum Launch {
    static func value(after flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}
