import Foundation
import Combine

/// The keys that pick the palette's tools (PLAN.md, revision 40). One
/// bare key per tool — a letter or a digit, no modifier, the way every
/// canvas app's tools answer — read on the desk and never in an editor.
/// The defaults are Figma's and Excalidraw's (V R O D L A P T S); Settings
/// lets each be changed or cleared, and the choice lives in UserDefaults
/// under one key, applied at once. A key held by another tool is refused
/// with a sentence rather than swapped, so a press never surprises.
/// Foundation and Combine only, so the canvas suite can drive it.
@MainActor
final class ToolKeys: ObservableObject {
    typealias Tool = CanvasStore.Tool

    static let shared = ToolKeys()
    static let defaultsKey = "toolKeys"

    /// The key per tool; a tool with none is picked from the palette alone.
    @Published private(set) var keys: [Tool: Character]
    /// The tool whose key Settings is listening for, if one is.
    @Published var recording: Tool?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var keys: [Tool: Character] = [:]
        let stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        for tool in Tool.allCases {
            if let saved = stored[tool.id] {
                // Written as "" when cleared, else one key; anything
                // else is not ours and the default stands.
                if saved.isEmpty { continue }
                if let key = saved.first, saved.count == 1, Self.accepts(key) {
                    keys[tool] = key
                } else {
                    keys[tool] = tool.defaultKey
                }
            } else {
                keys[tool] = tool.defaultKey
            }
        }
        self.keys = keys
    }

    /// What a key can be: one letter or one digit on the keyboard.
    static func accepts(_ key: Character) -> Bool {
        key.isASCII && (key.isLetter || key.isNumber)
    }

    func key(for tool: Tool) -> Character? { keys[tool] }

    /// The key as its cap reads, for the cell and a tooltip: "R", "2".
    func cap(for tool: Tool) -> String? { keys[tool].map { String($0).uppercased() } }

    /// The tool a pressed key picks, whatever its case.
    func tool(for key: Character) -> Tool? {
        let pressed = Self.lowered(key)
        return Tool.allCases.first { keys[$0].map(Self.lowered) == pressed }
    }

    /// One character lowered, as a character: `Character(String)` traps
    /// on a case mapping that grows, so the first grapheme is taken.
    private static func lowered(_ key: Character) -> Character {
        key.lowercased().first ?? key
    }

    func tool(for key: String) -> Tool? {
        guard key.count == 1, let first = key.first else { return nil }
        return tool(for: first)
    }

    /// Why `key` cannot be `tool`'s, in a sentence; nil when it can.
    func problem(with key: Character, for tool: Tool) -> String? {
        guard Self.accepts(key) else { return "A tool's key is one letter or digit, with no modifier." }
        if let holder = self.tool(for: key), holder != tool {
            return "\(String(key).uppercased()) picks \(holder.name) already."
        }
        return nil
    }

    /// Give `tool` a key, or none. Returns why it was refused, or nil
    /// once applied and written.
    @discardableResult
    func set(_ key: Character?, for tool: Tool) -> String? {
        if let key {
            if let why = problem(with: key, for: tool) { return why }
            keys[tool] = Self.lowered(key)
        } else {
            keys[tool] = nil
        }
        save()
        return nil
    }

    func reset() {
        keys = Dictionary(uniqueKeysWithValues: Tool.allCases.map { ($0, $0.defaultKey) })
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    var isDefault: Bool { Tool.allCases.allSatisfy { keys[$0] == $0.defaultKey } }

    private func save() {
        var stored: [String: String] = [:]
        for tool in Tool.allCases where keys[tool] != tool.defaultKey {
            stored[tool.id] = keys[tool].map(String.init) ?? ""
        }
        if stored.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(stored, forKey: Self.defaultsKey)
        }
    }

    /// A shortcut as its caps, one per key: "⌘⇧N" is ⌘, ⇧ and N; "V" is
    /// V; "⌘1" is ⌘ and 1. The modifiers are the four Mac glyphs, in the
    /// order they were written.
    static func caps(_ shortcut: String) -> [String] {
        var caps: [String] = []
        var rest = ""
        for character in shortcut {
            if "⌃⌥⇧⌘".contains(character) {
                caps.append(String(character))
            } else {
                rest.append(character)
            }
        }
        if !rest.isEmpty { caps.append(rest) }
        return caps
    }
}

extension CanvasStore.Tool {
    /// Every tool a key can pick, in the palette's order.
    static let allCases: [CanvasStore.Tool] = [
        .select, .draw(.rectangle), .draw(.ellipse), .draw(.diamond), .draw(.line), .draw(.arrow),
        .pen, .text, .sticky,
    ]

    /// What it is written as in UserDefaults.
    var id: String {
        switch self {
        case .select: return "select"
        case .text: return "text"
        case .sticky: return "sticky"
        case .pen: return "pen"
        case .draw(let tool): return tool.rawValue
        }
    }

    var name: String {
        switch self {
        case .select: return "Select"
        case .text: return "Text"
        case .sticky: return "Sticky note"
        case .pen: return "Draw"
        case .draw(let tool): return tool.name
        }
    }

    var symbol: Glyph {
        switch self {
        case .select: return .mousePointer
        case .text: return .type
        case .sticky: return .stickyNote
        case .pen: return .pen
        case .draw(let tool): return tool.symbol
        }
    }

    /// Figma's and Excalidraw's keys (revisions 15 and 22).
    var defaultKey: Character {
        switch self {
        case .select: return "v"
        case .text: return "t"
        case .sticky: return "s"
        case .pen: return "p"
        case .draw(let tool): return tool.key
        }
    }
}
