import Foundation

/// What the vault says about itself, read from the files: which notes link
/// to which (`[[name]]`), and which canvases hold which files. Rebuilt on
/// demand after a change; a vault of hundreds of notes indexes in
/// milliseconds, so there is no second store to keep honest.
struct VaultIndex {
    struct Backlink: Hashable {
        let source: String
        let snippet: String
    }

    /// Link target (a note's stem, lowercased) → the notes that link to it.
    var backlinks: [String: [Backlink]] = [:]
    /// Vault path → the canvases that carry a card for it.
    var canvases: [String: [String]] = [:]
    /// Note stem (lowercased) → path, for resolving `[[name]]`.
    var notesByStem: [String: String] = [:]

    static let wikiLink = try! NSRegularExpression(pattern: #"\[\[([^\]\n|#]+)(?:[|#][^\]\n]*)?\]\]"#)

    static func build(root: URL) -> VaultIndex {
        var index = VaultIndex()
        guard let tree = try? VaultNode.scan("", root: root, depth: 8) else { return index }
        let entries = tree.flatMap(\.flattened).filter { !$0.isDirectory }
        for entry in entries where entry.kind == .markdown {
            index.notesByStem[Self.stem(of: entry.path)] = entry.path
        }
        // Home is hidden from listings; the index wants it most of all.
        var canvasPaths = entries.filter { $0.kind == .canvas }.map(\.path)
        let home = VaultListing.homeCanvas(root: root)
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(home).path) {
            canvasPaths.append(home)
        }
        for path in canvasPaths {
            let url = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url), let doc = try? CanvasDocument.decode(data) else { continue }
            for node in doc.nodes {
                guard let file = node.file else { continue }
                index.canvases[file, default: []].append(path)
            }
        }
        for entry in entries {
            let url = root.appendingPathComponent(entry.path)
            switch entry.kind {
            case .markdown:
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let ns = text as NSString
                var seen: Set<String> = []
                for match in Self.wikiLink.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let target = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
                    guard !target.isEmpty, seen.insert(target).inserted else { continue }
                    let line = ns.lineRange(for: match.range)
                    let snippet = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                    index.backlinks[target, default: []].append(Backlink(source: entry.path, snippet: String(snippet.prefix(160))))
                }
            default:
                continue
            }
        }
        return index
    }

    static func stem(of path: String) -> String {
        (VaultPath.name(of: path) as NSString).deletingPathExtension.lowercased()
    }

    /// Notes linking to the note at `path`.
    func backlinks(to path: String) -> [Backlink] {
        backlinks[Self.stem(of: path)] ?? []
    }

    /// Canvases carrying a card for `path`, excluding its own directory's canvas if asked.
    func canvases(for path: String) -> [String] {
        canvases[path] ?? []
    }

    /// The note a `[[name]]` means: by stem, else by exact vault path.
    func resolve(link name: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespaces)
        if let path = notesByStem[clean.lowercased()] { return path }
        if let path = notesByStem[Self.stem(of: clean)] { return path }
        return nil
    }
}
