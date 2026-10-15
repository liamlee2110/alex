import Foundation
import CoreGraphics

/// What ⌘C takes off the desk (revision 48): the selected nodes, whatever a
/// selected section holds, and the edges between them, as a fragment of
/// JSON Canvas under Alex's own pasteboard type. ⌘V puts a copy back with
/// new ids, on this canvas or another; the pure part is here, the files and
/// the undo step are `CanvasStore.paste`.
struct CanvasClip: Equatable {
    /// Alex's own pasteboard type, declared in the bundle by `build.sh`;
    /// other apps get the words as text.
    static let pasteboardType = "com.liamlee.alex.canvas-clip"

    var nodes: [CanvasNode]
    var edges: [CanvasEdge]
    /// The canvas it was copied from, so a paste there steps aside.
    var source: String

    init(nodes: [CanvasNode], edges: [CanvasEdge], source: String) {
        self.nodes = nodes; self.edges = edges; self.source = source
    }

    /// The selection with what its sections hold, in the file's order, and
    /// the edges with both ends in it; nil when nothing is selected.
    init?(taking ids: Set<String>, from doc: CanvasDocument, source: String) {
        var taken = ids.filter { doc.node($0) != nil }
        for section in doc.nodes where ids.contains(section.id) && section.kind == .group {
            for inner in doc.nodes where inner.id != section.id && section.frame.contains(inner.frame) {
                taken.insert(inner.id)
            }
        }
        guard !taken.isEmpty else { return nil }
        nodes = doc.nodes.filter { taken.contains($0.id) }
        edges = doc.edges.filter { taken.contains($0.fromNode) && taken.contains($0.toNode) }
        self.source = source
    }

    init?(data: Data) {
        guard let doc = try? CanvasDocument.decode(data), !doc.nodes.isEmpty else { return nil }
        nodes = doc.nodes
        edges = doc.edges.filter { edge in
            doc.nodes.contains { $0.id == edge.fromNode } && doc.nodes.contains { $0.id == edge.toNode }
        }
        source = doc.extra["x-source"]?.string ?? ""
    }

    var data: Data? {
        var doc = CanvasDocument(nodes: nodes, edges: edges)
        doc.extra["x-source"] = .string(source)
        return try? doc.encode()
    }

    var bounds: CGRect { nodes.reduce(CGRect.null) { $0.union($1.frame) } }

    /// For another app: the words of the stickies, text boxes and shapes,
    /// and the links' addresses, a blank line apart.
    var plainText: String? {
        let parts = nodes.compactMap { node -> String? in
            switch node.kind {
            case .text: return node.text.flatMap { $0.isEmpty ? nil : $0 }
            case .link: return node.url
            default: return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// The vault files the clip's cards point at.
    var files: [String] { nodes.compactMap { $0.kind == .file ? $0.file : nil } }

    /// The copy to add, moved by `offset`, every id new and the edges
    /// following. A file has one card on a canvas, so a file's card comes
    /// along only where its file is not on `doc` already, except a
    /// picture, whose bytes `copyFile` writes to a file of their own (nil
    /// leaves the card out); a file gone from the vault is left out. A
    /// folder has one section, so a section keeps its folder only where
    /// `keepsFolder` says the folder's section is gone (a cut on Home).
    func pasted(into doc: CanvasDocument, offset: CGVector,
                exists: (String) -> Bool,
                isImage: (String) -> Bool,
                keepsFolder: (String) -> Bool,
                copyFile: (String) -> String?) -> (nodes: [CanvasNode], edges: [CanvasEdge]) {
        let placed = Set(doc.nodes.compactMap { $0.kind == .file ? $0.file : nil })
        var ids: [String: String] = [:]
        var out: [CanvasNode] = []
        for node in nodes {
            var copy = node
            if node.kind == .file, let file = node.file {
                guard exists(file) else { continue }
                if placed.contains(file) {
                    guard isImage(file), let fresh = copyFile(file) else { continue }
                    copy.file = fresh
                }
            }
            if let folder = Folders.folder(of: node), !keepsFolder(folder) {
                copy.extra[Folders.key] = nil
            }
            copy.id = CanvasDocument.newID()
            copy.x += offset.dx
            copy.y += offset.dy
            ids[node.id] = copy.id
            out.append(copy)
        }
        let links = edges.compactMap { edge -> CanvasEdge? in
            guard let from = ids[edge.fromNode], let to = ids[edge.toNode] else { return nil }
            var copy = edge
            copy.id = CanvasDocument.newID()
            copy.fromNode = from
            copy.toNode = to
            return copy
        }
        return (out, links)
    }

    /// A copied picture's file, beside the original: `photo.png` gives
    /// `photo 2.png`, then ` 3`, and `photo 2.png` gives `photo 3.png`.
    static func copyName(of path: String, taken: (String) -> Bool) -> String {
        let ext = (path as NSString).pathExtension
        var stem = ext.isEmpty ? path : String(path.dropLast(ext.count + 1))
        var i = 2
        if let space = stem.lastIndex(of: " "), let n = Int(stem[stem.index(after: space)...]), n >= 2 {
            stem = String(stem[..<space])
            i = n + 1
        }
        func name(_ i: Int) -> String { ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)" }
        while taken(name(i)) { i += 1 }
        return name(i)
    }
}
