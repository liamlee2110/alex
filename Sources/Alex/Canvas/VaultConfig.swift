import Foundation

/// One rule in `canvas.config.json`: which files it covers (a glob), which
/// frontmatter key colours their cards, which key groups them when the
/// canvas is arranged, and which key names their prerequisites.
struct ViewRule: Hashable {
    var match: String
    var colorBy: String?
    /// Value → JSON Canvas colour ("1"–"6" or #rrggbb). Empty means none.
    var colors: [String: String] = [:]
    var groupBy: String?
    /// "Block {value}" and the like; `{value}` is replaced.
    var groupLabel: String?
    var edgesFrom: String?
    /// The frontmatter key another file's `edgesFrom` values point at.
    var idKey = "id"

    init(match: String) {
        self.match = match
    }

    init?(json: [String: JSONValue]) {
        guard let match = json["match"]?.string else { return nil }
        self.match = match
        colorBy = json["colorBy"]?.string
        colors = json["colors"]?.object?.compactMapValues(\.string) ?? [:]
        groupBy = json["groupBy"]?.string
        groupLabel = json["groupLabel"]?.string
        edgesFrom = json["edgesFrom"]?.string
        idKey = json["idKey"]?.string ?? "id"
    }

    func applies(to path: String) -> Bool {
        VaultPath.matches(path, glob: match)
    }

    func label(for value: String) -> String {
        (groupLabel ?? "{value}").replacingOccurrences(of: "{value}", with: value)
    }

    /// The colour for a value: the map's if it has one, a stable preset by
    /// name when there is no map at all, nothing when the map leaves it out.
    func color(for value: String) -> String? {
        if let named = colors[value] { return named.isEmpty ? nil : named }
        return colors.isEmpty ? VaultConfig.presetColor(hashing: value) : nil
    }
}

struct VaultConfig: Hashable {
    static let fileName = "canvas.config.json"
    var views: [ViewRule] = []

    static func decode(_ data: Data) -> VaultConfig {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = JSONValue(any: raw)?.object else { return VaultConfig() }
        var config = VaultConfig()
        config.views = (root["views"]?.array ?? []).compactMap { $0.object.flatMap(ViewRule.init(json:)) }
        return config
    }

    /// The first rule whose glob covers the path.
    func rule(for path: String) -> ViewRule? {
        views.first { $0.applies(to: path) }
    }

    /// A JSON Canvas preset, stable per value, so "in progress" is the same
    /// colour on every card without anyone choosing one.
    static func presetColor(hashing value: String) -> String {
        var hash: UInt32 = 2166136261
        for byte in value.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return String(Int(hash % 6) + 1)
    }
}
