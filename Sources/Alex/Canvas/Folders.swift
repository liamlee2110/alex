import Foundation
import CoreGraphics

/// A folder's section: a JSON Canvas `group` carrying a directory's path
/// under `x-folder`. Home laid the whole vault out this way from revision
/// 20 to 53; since revision 54 there is no Home (D5), and a section left
/// on a canvas is a group that wears its folder's glyph and colour and
/// never moves a file.
enum Folders {
    static let key = "x-folder"

    /// The label pill's height, above a section's top edge.
    static let pill: Double = 24

    static func folder(of node: CanvasNode) -> String? {
        guard node.kind == .group else { return nil }
        return node.extra[key]?.string
    }

    static func section(for dir: String, in doc: CanvasDocument) -> CanvasNode? {
        doc.nodes.first { folder(of: $0) == dir }
    }

    static func area(_ r: CGRect) -> Double { r.width * r.height }

    // MARK: - Colour

    /// The folder stocks (revision 8): a directory with no colour of its
    /// own takes one by its top-level name, the colour its glyph wears in
    /// the sidebar.
    static let stockHues: [Double] = [95, 145, 240, 25, 300, 60, 190, 350]

    /// Stable per name, so a directory keeps its colour between launches.
    static func stockIndex(for name: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return Int(hash % UInt32(stockHues.count))
    }
}

extension CanvasDocument {
    /// Groups draw under cards and take a press only where no card is, the
    /// larger behind the smaller, so a section inside another is on top
    /// of it: a new group goes in before the first smaller one.
    mutating func insertGroup(_ group: CanvasNode) {
        let area = Folders.area(group.frame)
        let at = nodes.firstIndex { $0.kind != .group || Folders.area($0.frame) < area } ?? nodes.count
        nodes.insert(group, at: at)
    }
}
