import Foundation

/// One thing in the vault, named by its relative path. Pure Foundation.
struct VaultEntry: Identifiable, Hashable {
    enum Kind: String {
        case directory, markdown, canvas, image, pdf, office, html, code, text, other

        static func forExtension(_ ext: String) -> Kind {
            switch ext.lowercased() {
            case "md", "markdown": return .markdown
            case "canvas": return .canvas
            case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "bmp": return .image
            case "pdf": return .pdf
            case "docx", "pptx", "xlsx", "pages", "key", "numbers": return .office
            case "html", "htm": return .html
            case "py", "swift", "js", "ts", "json", "yaml", "yml", "toml", "sh",
                 "c", "cpp", "h", "rs", "jl", "ino", "m": return .code
            case "txt", "csv", "tsv", "log": return .text
            default: return .other
            }
        }

        /// The icon for the sidebar, the tree and a card.
        var symbol: Glyph {
            switch self {
            case .directory: return .folder
            case .markdown: return .fileText
            case .canvas: return .layoutDashboard
            case .image: return .image
            case .pdf: return .bookOpenText
            case .office: return .fileText
            case .html: return .globe
            case .code: return .codeXml
            case .text: return .fileType
            case .other: return .file
            }
        }

        /// Whether the file is worth showing as text.
        var isTextual: Bool {
            switch self {
            case .markdown, .canvas, .html, .code, .text: return true
            case .directory, .image, .pdf, .office, .other: return false
            }
        }
    }

    let path: String
    let isDirectory: Bool

    var id: String { path }
    var name: String { VaultPath.name(of: path) }
    var kind: Kind {
        isDirectory ? .directory : Kind.forExtension((path as NSString).pathExtension)
    }
    /// An office file's shape: pages, slides or sheets (revision 61).
    var officeShape: OfficeDocument.Shape? {
        isDirectory ? nil : OfficeDocument.Shape.forExtension((path as NSString).pathExtension)
    }
    /// The kind's icon, a deck's or a workbook's where the kind is office.
    var symbol: Glyph { officeShape?.symbol ?? kind.symbol }
}

enum VaultListing {
    /// Never shown: anything hidden (which covers `.git` and the vault's own
    /// `.mcp.json`), package caches, Python droppings.
    static func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".") || name == "node_modules" || name == "__pycache__"
    }

    /// One directory level: directories first, then names case-insensitively.
    static func entries(in directory: String, root: URL) throws -> [VaultEntry] {
        let url = try VaultPath.resolve(directory, in: root)
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        var out: [VaultEntry] = []
        for name in names where !isHidden(name) {
            var isDirectory: ObjCBool = false
            let child = url.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory) else {
                continue
            }
            out.append(VaultEntry(path: VaultPath.join(directory, name),
                                  isDirectory: isDirectory.boolValue))
        }
        return out.sorted(by: order)
    }

    static func order(_ a: VaultEntry, _ b: VaultEntry) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// The sidebar's shape: an entry and, for a directory, what it holds. Scanned
/// to a depth cap so a vault that contains something huge stays quick.
struct VaultNode: Identifiable, Hashable {
    let entry: VaultEntry
    var children: [VaultNode]?

    var id: String { entry.path }

    static func scan(_ directory: String, root: URL, depth: Int = 6) throws -> [VaultNode] {
        try VaultListing.entries(in: directory, root: root).map { entry in
            var node = VaultNode(entry: entry, children: nil)
            if entry.isDirectory {
                node.children = depth > 0
                    ? ((try? scan(entry.path, root: root, depth: depth - 1)) ?? [])
                    : []
            }
            return node
        }
    }

    /// Every entry in the tree, depth first.
    var flattened: [VaultEntry] {
        [entry] + (children ?? []).flatMap(\.flattened)
    }
}
