import Foundation

/// What a card shows of a file on the canvas: a title, a few blocks of
/// text, and the frontmatter.
struct CardPreview: Hashable {
    var title: String
    /// One entry per block: a paragraph is its lines joined with a space,
    /// the way Markdown reads a single newline; a heading, a list item, a
    /// quote and a table row stand on their own. A file hard-wrapped at
    /// seventy columns therefore wraps to the card, not to the file. What
    /// a code or text card shows, and what search reads.
    var lines: [String]
    /// A note's body as the card draws it (revision 18): the head of the
    /// file after the frontmatter, leading blank lines dropped, bounded by
    /// `maxLines` and `maxLineLength`. The card renders it through the
    /// panel's own renderer, so a note reads on the desk as it reads in
    /// the panel.
    var body: String = ""
    /// The title is the body's own first heading, which the renderer
    /// draws in place; otherwise the card draws the title itself.
    var hasHeading = false
    var frontmatter: Frontmatter

    /// How much of a file a card holds. Not what a card shows: the card
    /// measures that against its own height, and a card dragged taller has
    /// to have something left to fill it with. Bounded, because every open
    /// canvas keeps one of these per file.
    static let maxLines = 60
    static let maxLineLength = 400

    @MainActor
    static func make(for path: String, vault: Vault) -> CardPreview {
        let name = VaultPath.name(of: path)
        let stem = (name as NSString).deletingPathExtension
        let kind = VaultEntry.Kind.forExtension((name as NSString).pathExtension)
        guard kind.isTextual, let text = try? vault.readText(path) else {
            return CardPreview(title: stem, lines: [], frontmatter: Frontmatter())
        }
        if kind != .markdown {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(maxLines).map { String($0.prefix(maxLineLength)) }
            return CardPreview(title: name, lines: Array(lines), frontmatter: Frontmatter())
        }

        let fm = Frontmatter.parse(text)
        var title = stem
        var sawHeading = false
        var lines: [String] = []
        var paragraph: String?
        var inFence = false
        func flush() {
            if let open = paragraph { lines.append(String(open.prefix(maxLineLength))) }
            paragraph = nil
        }
        for raw in fm.body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inFence.toggle(); flush(); continue }
            if inFence || line.hasPrefix("<!--") || line.hasPrefix("-->") { continue }
            if line.isEmpty { flush(); continue }
            if !sawHeading, line.hasPrefix("# ") {
                title = String(line.dropFirst(2))
                sawHeading = true
                flush()
                continue
            }
            let standsAlone = Self.standsAlone(line)
            var shown = line
            while shown.hasPrefix("#") { shown.removeFirst() }
            shown = shown.trimmingCharacters(in: .whitespaces)
            if shown.allSatisfy({ $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }) { flush(); continue }
            if shown.hasPrefix("|") {
                shown = shown.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }
            let words = Self.plain(shown)
            if standsAlone {
                flush()
                lines.append(String(words.prefix(maxLineLength)))
            } else if let open = paragraph {
                paragraph = open + " " + words
            } else {
                paragraph = words
            }
            if lines.count + (paragraph == nil ? 0 : 1) >= maxLines { break }
        }
        flush()
        if !sawHeading, let t = fm["title"]?.display, !t.isEmpty { title = t }
        title = Self.plain(title)

        // The body the renderer gets: the file's own lines, not the
        // flattened ones, so every block keeps its syntax to be drawn from.
        // A comment is for the file's readers, not the card's, and goes.
        var bodyLines: [String] = []
        var inComment = false
        for raw in fm.body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if inComment { if line.contains("-->") { inComment = false }; continue }
            if line.hasPrefix("<!--") { if !line.contains("-->") { inComment = true }; continue }
            if bodyLines.isEmpty, line.isEmpty { continue }
            bodyLines.append(String(raw.prefix(maxLineLength)))
            if bodyLines.count >= maxLines { break }
        }

        return CardPreview(title: title, lines: lines, body: bodyLines.joined(separator: "\n"),
                           hasHeading: sawHeading, frontmatter: fm)
    }

    /// A line that is a block of its own rather than a wrapped piece of the
    /// paragraph above: a heading, a list item, a quote, a table row.
    static func standsAlone(_ line: String) -> Bool {
        if line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("|") { return true }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
        var digits = line[...]
        while let first = digits.first, first.isNumber { digits = digits.dropFirst() }
        return digits.count < line.count && digits.hasPrefix(". ")
    }

    /// The inline marks a card need not show: `==`, `[[ ]]`, `**`, backticks.
    static func plain(_ line: String) -> String {
        var out = line
        for mark in ["==", "[[", "]]", "**", "`", "__"] { out = out.replacingOccurrences(of: mark, with: "") }
        return out
    }
}
