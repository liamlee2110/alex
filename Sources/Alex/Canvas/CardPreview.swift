import Foundation

/// What a card shows of a file on the canvas: a title, a few lines, and the
/// frontmatter keys worth a chip.
struct CardPreview: Hashable {
    struct Chip: Hashable {
        let key: String
        let value: String
    }

    var title: String
    var lines: [String]
    var chips: [Chip]
    var frontmatter: Frontmatter

    /// The keys that earn a chip, in the order they are shown. Generic, so a
    /// vault that is not the learn repo still gets something sensible.
    static let chipKeys = [
        "status", "level", "target", "phase", "next_review", "date", "size",
        "minutes", "retrieval", "week", "hours", "prepared",
    ]
    static let maxChips = 4

    @MainActor
    static func make(for path: String, vault: Vault) -> CardPreview {
        let name = VaultPath.name(of: path)
        let stem = (name as NSString).deletingPathExtension
        let kind = VaultEntry.Kind.forExtension((name as NSString).pathExtension)
        guard kind.isTextual, let text = try? vault.readText(path) else {
            return CardPreview(title: stem, lines: [], chips: [], frontmatter: Frontmatter())
        }
        if kind != .markdown {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(10).map { String($0.prefix(120)) }
            return CardPreview(title: name, lines: Array(lines), chips: [], frontmatter: Frontmatter())
        }

        let fm = Frontmatter.parse(text)
        var title = stem
        var sawHeading = false
        var lines: [String] = []
        var inFence = false
        for raw in fm.body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence || line.isEmpty || line.hasPrefix("<!--") || line.hasPrefix("-->") { continue }
            if !sawHeading, line.hasPrefix("# ") {
                title = String(line.dropFirst(2))
                sawHeading = true
                continue
            }
            var shown = line
            while shown.hasPrefix("#") { shown.removeFirst() }
            shown = shown.trimmingCharacters(in: .whitespaces)
            if shown.allSatisfy({ $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }) { continue }
            if shown.hasPrefix("|") {
                shown = shown.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }
            lines.append(String(shown.prefix(140)))
            if lines.count >= 8 { break }
        }
        if !sawHeading, let t = fm["title"]?.display, !t.isEmpty { title = t }

        var chips: [Chip] = []
        for key in chipKeys where chips.count < maxChips {
            if let v = fm[key], !v.isEmpty { chips.append(Chip(key: key, value: v.display)) }
        }
        return CardPreview(title: title, lines: lines, chips: chips, frontmatter: fm)
    }
}
