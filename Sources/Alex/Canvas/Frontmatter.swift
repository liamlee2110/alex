import Foundation

enum FrontmatterValue: Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case list([String])

    var display: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .list(let l): return l.joined(separator: ", ")
        }
    }

    var isEmpty: Bool {
        switch self {
        case .string(let s): return s.isEmpty
        case .list(let l): return l.isEmpty
        default: return false
        }
    }
}

/// The rules of `scripts/learn.py parse_frontmatter`, reproduced exactly, so
/// the app and the coach read every file the same way: `key: value`,
/// `[a, b]` lists, quoted strings, ints, floats, booleans, `#` comments after
/// an unquoted value, `{{placeholder}}` list items dropped.
struct Frontmatter: Hashable {
    var fields: [String: FrontmatterValue] = [:]
    var order: [String] = []
    var body: String = ""

    subscript(key: String) -> FrontmatterValue? { fields[key] }
    var isEmpty: Bool { fields.isEmpty }

    static func parse(_ text: String) -> Frontmatter {
        var out = Frontmatter()
        guard text.hasPrefix("---") else { out.body = text; return out }
        let rest = text.dropFirst(3)
        guard let close = rest.range(of: "\n---") else { out.body = text; return out }
        let head = String(rest[..<close.lowerBound])
        var body = String(rest[close.upperBound...])
        while body.hasPrefix("\n") { body.removeFirst() }
        out.body = body

        for rawLine in head.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":"),
                  !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var raw = String(line[line.index(after: colon)...])
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("\"") {
                raw = raw.trimmingCharacters(in: .whitespaces)
            } else {
                raw = String(raw.split(separator: "#", maxSplits: 1,
                                       omittingEmptySubsequences: false).first ?? "")
                    .trimmingCharacters(in: .whitespaces)
            }

            let value: FrontmatterValue
            if raw.hasPrefix("["), raw.hasSuffix("]") {
                let inner = raw.dropFirst().dropLast()
                let items = inner.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }.filter { !$0.isEmpty && $0 != "{{\(key)}}" }
                value = .list(items)
            } else if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
                value = .string(String(raw.dropFirst().dropLast()))
            } else if raw.range(of: #"^-?\d+$"#, options: .regularExpression) != nil, let i = Int(raw) {
                value = .int(i)
            } else if raw.range(of: #"^-?\d+\.\d+$"#, options: .regularExpression) != nil, let d = Double(raw) {
                value = .double(d)
            } else if raw.lowercased() == "true" || raw.lowercased() == "false" {
                value = .bool(raw.lowercased() == "true")
            } else {
                value = .string(raw)
            }
            out.fields[key] = value
            if !out.order.contains(key) { out.order.append(key) }
        }
        return out
    }
}
