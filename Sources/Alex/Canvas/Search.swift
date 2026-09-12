import Foundation

struct SearchHit: Identifiable, Hashable {
    let path: String
    let title: String
    let kind: VaultEntry.Kind
    var id: String { path }
}

enum SearchIndex {
    /// Every entry whose path or title contains the query, or spells it as a
    /// subsequence; exact matches first, then the shortest.
    @MainActor
    static func search(_ query: String, vault: Vault, store: CanvasStore) -> [SearchHit] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        var scored: [(SearchHit, Int)] = []
        for entry in vault.tree.flatMap(\.flattened) {
            let title = entry.kind == .markdown ? store.preview(for: entry.path).title : entry.name
            let hay = (entry.path + " " + title).lowercased()
            guard let score = score(needle, in: hay) else { continue }
            scored.append((SearchHit(path: entry.path, title: title, kind: entry.kind), score))
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static func score(_ needle: String, in hay: String) -> Int? {
        if needle.isEmpty { return 0 }
        if hay.contains(needle) {
            return 200 + (hay.hasPrefix(needle) ? 40 : 0) - min(hay.count, 120) / 4
        }
        var gaps = 0
        var index = hay.startIndex
        for char in needle {
            guard let found = hay[index...].firstIndex(of: char) else { return nil }
            gaps += hay.distance(from: index, to: found)
            index = hay.index(after: found)
        }
        return 100 - min(gaps, 90)
    }
}

