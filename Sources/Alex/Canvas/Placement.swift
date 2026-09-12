import Foundation
import CoreGraphics

/// Where things go when nobody has placed them yet: the first visit to a
/// directory, and a card the door adds without coordinates.
enum Placement {
    static let folderSize = CGSize(width: 200, height: 150)
    static let cardSize = CGSize(width: 320, height: 200)
    static let textSize = CGSize(width: 240, height: 160)
    static let origin = CGPoint(x: 80, y: 80)
    static let columns = 5
    static let folderGap = CGSize(width: 100, height: 90)
    static let cardGap = CGSize(width: 40, height: 40)

    /// Folders in rows, then files in rows: a grid a hand can rearrange.
    static func autoLayout(_ entries: [VaultEntry]) -> [CanvasNode] {
        var nodes: [CanvasNode] = []
        let folders = entries.filter(\.isDirectory)
        let files = entries.filter { !$0.isDirectory }
        var y = origin.y
        for (i, entry) in folders.enumerated() {
            let col = Double(i % columns), row = Double(i / columns)
            let frame = CGRect(x: origin.x + col * (folderSize.width + folderGap.width),
                               y: y + row * (folderSize.height + folderGap.height),
                               width: folderSize.width, height: folderSize.height)
            nodes.append(CanvasNode(kind: .file, frame: frame, file: entry.path))
        }
        if !folders.isEmpty {
            let rows = Double((folders.count + columns - 1) / columns)
            y += rows * (folderSize.height + folderGap.height) + 40
        }
        for (i, entry) in files.enumerated() {
            let col = Double(i % columns), row = Double(i / columns)
            let frame = CGRect(x: origin.x + col * (cardSize.width + cardGap.width),
                               y: y + row * (cardSize.height + cardGap.height),
                               width: cardSize.width, height: cardSize.height)
            nodes.append(CanvasNode(kind: .file, frame: frame, file: entry.path))
        }
        return nodes
    }

    /// A free spot for a new node: beside `near` (right, below, left, above,
    /// then further right), else under everything on the canvas.
    static func freeSlot(for size: CGSize, in doc: CanvasDocument, near: CGRect?) -> CGPoint {
        let occupied = doc.nodes.filter { $0.kind != .group }.map(\.frame)
        func free(_ origin: CGPoint) -> Bool {
            let r = CGRect(origin: origin, size: size)
            return !occupied.contains { $0.insetBy(dx: -16, dy: -16).intersects(r) }
        }
        if let near {
            let gap: CGFloat = 40
            let candidates = [
                CGPoint(x: near.maxX + gap, y: near.minY),
                CGPoint(x: near.minX, y: near.maxY + gap),
                CGPoint(x: near.minX - size.width - gap, y: near.minY),
                CGPoint(x: near.minX, y: near.minY - size.height - gap),
            ]
            for c in candidates where free(c) { return c }
            var c = CGPoint(x: near.maxX + gap, y: near.minY)
            for _ in 0..<60 {
                c.x += size.width + gap
                if free(c) { return c }
            }
        }
        let bounds = doc.bounds
        return bounds.isNull ? origin : CGPoint(x: origin.x, y: bounds.maxY + 60)
    }
}
