import Foundation

/// JSON as a value type, so the keys a `.canvas` file carries that Alex does
/// not understand survive a round trip untouched (PLAN.md, D4).
enum JSONValue: Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init?(any: Any) {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else { self = .number(n.doubleValue) }
        } else if let s = any as? String {
            self = .string(s)
        } else if any is NSNull {
            self = .null
        } else if let a = any as? [Any] {
            self = .array(a.compactMap { JSONValue(any: $0) })
        } else if let o = any as? [String: Any] {
            self = .object(o.compactMapValues { JSONValue(any: $0) })
        } else {
            return nil
        }
    }

    /// Back to what `JSONSerialization` writes. Whole numbers go out as
    /// integers, so `x: 320` does not come back as `320.0`.
    var any: Any {
        switch self {
        case .string(let s): return s
        case .number(let d):
            if d == d.rounded(), abs(d) < 1e15 { return NSNumber(value: Int64(d)) }
            return NSNumber(value: d)
        case .bool(let b): return NSNumber(value: b)
        case .null: return NSNull()
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var double: Double? { if case .number(let d) = self { return d }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}
