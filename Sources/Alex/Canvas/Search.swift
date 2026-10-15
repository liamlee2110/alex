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
            let title = store.displayTitle(for: entry.path)
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


/// One place the words of ⌘F are written on the open canvas (revision 27):
/// the node they are on, and the line round them, cut to a snippet with
/// the match's range in it.
struct FindHit: Identifiable, Hashable {
    let node: String
    let snippet: String
    let match: Range<String.Index>
    /// The hit's place among its node's hits, which makes its id.
    let ordinal: Int
    var id: String { node + "#" + String(ordinal) }
}

/// ⌘F, find on canvas (revision 27): every place the query is written
/// on the open canvas's nodes, the way Excalidraw's canvas search lists
/// them — top to bottom, then left to right, a node's own hits in the
/// order its text reads. Case and diacritics are ignored; the query is
/// literal, not fuzzy (⌘K is the fuzzy one, over names).
enum CanvasFind {
    /// No more than this many hits are listed; the count says when there
    /// were more.
    static let limit = 500
    /// Characters kept before a match in its snippet.
    static let lead = 24
    /// Characters kept in a snippet altogether.
    static let span = 90

    /// The nodes in reading order: a section before what lies in it,
    /// since it starts higher up.
    static func readingOrder(_ nodes: [CanvasNode]) -> [CanvasNode] {
        nodes.sorted { a, b in
            if abs(a.y - b.y) > 1 { return a.y < b.y }
            return a.x < b.x
        }
    }

    /// `texts` gives a node's searchable strings: a sticky's words, a
    /// section's label, a note's title and body, a link's address and
    /// title. The first string is also where a hit on its name is.
    static func hits(_ query: String, in nodes: [CanvasNode],
                     texts: (CanvasNode) -> [String]) -> (hits: [FindHit], total: Int) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return ([], 0) }
        var hits: [FindHit] = []
        var total = 0
        for node in readingOrder(nodes) {
            var ordinal = 0
            var seenLines = Set<String>()
            for text in texts(node) {
                for line in text.split(whereSeparator: \.isNewline) {
                    let line = String(line)
                    var from = line.startIndex
                    while let found = line.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                                                 range: from..<line.endIndex) {
                        from = found.upperBound
                        // A title is usually its note's first heading too:
                        // one hit, not two.
                        let marks = line.prefix { "#->*+ \t".contains($0) }.count
                        let key = String(line.dropFirst(marks)) + "@"
                            + String(line.distance(from: line.startIndex, to: found.lowerBound) - marks)
                        guard seenLines.insert(key).inserted else { continue }
                        total += 1
                        if hits.count < limit {
                            let (snippet, match) = cut(line, around: found)
                            hits.append(FindHit(node: node.id, snippet: snippet, match: match, ordinal: ordinal))
                        }
                        ordinal += 1
                    }
                }
            }
        }
        return (hits, total)
    }

    /// The line round a match, trimmed of markdown's leading marks and
    /// cut to `span` characters with an ellipsis where it was cut.
    static func cut(_ line: String, around found: Range<String.Index>) -> (String, Range<String.Index>) {
        var start = line.startIndex
        // `# `, `- `, `> ` and the like say nothing in a snippet.
        while start < found.lowerBound, "#->*+ \t".contains(line[start]) { start = line.index(after: start) }
        var prefix = ""
        if line.distance(from: start, to: found.lowerBound) > lead {
            start = line.index(found.lowerBound, offsetBy: -lead)
            // Start on a word.
            if let space = line[start..<found.lowerBound].firstIndex(of: " "), space < found.lowerBound {
                start = line.index(after: space)
            }
            prefix = "…"
        }
        let end = line.index(start, offsetBy: span, limitedBy: line.endIndex) ?? line.endIndex
        let stop = max(end, found.upperBound)
        let suffix = stop < line.endIndex ? "…" : ""
        let snippet = prefix + line[start..<stop] + suffix
        let lower = snippet.index(snippet.startIndex,
                                  offsetBy: prefix.count + line.distance(from: start, to: found.lowerBound))
        let upper = snippet.index(lower, offsetBy: line.distance(from: found.lowerBound, to: found.upperBound))
        return (snippet, lower..<upper)
    }
}
