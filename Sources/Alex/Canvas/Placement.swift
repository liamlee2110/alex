import Foundation
import CoreGraphics

/// Where things go when nobody has placed them yet: a card the door adds
/// without coordinates, the tray's "Place everything". (Home's folders and
/// their files are placed by `Folders`.)
enum Placement {
    static let cardSize = CGSize(width: 320, height: 200)
    /// A document is page-shaped, as Heptabase makes it: a paper lying on a
    /// landscape card is a paper nobody can read. Letter and A4 are both
    /// near 1 : 1.3.
    static let documentSize = CGSize(width: 320, height: 414)
    /// A deck's card (revision 61): a 16 : 9 slide across the page card's
    /// inset width, the same paper above and below it, and the name row.
    static let slideSize = CGSize(width: 320, height: 220)
    static let textSize = CGSize(width: 240, height: 160)
    /// A folded card: one title row, the height written into the file so
    /// another JSON Canvas app draws the same short card.
    static let foldedHeight: Double = 44
    static let origin = CGPoint(x: 80, y: 80)
    static let columns = 5
    static let cardGap = CGSize(width: 40, height: 40)

    /// The card a file gets when nobody has sized it: a document's page
    /// shape, a deck's slide shape, a card otherwise.
    static func size(for entry: VaultEntry) -> CGSize {
        switch entry.kind {
        case .pdf: return documentSize
        case .office: return entry.officeShape == .slides ? slideSize : documentSize
        default: return cardSize
        }
    }

    static func size(forFile path: String, isDirectory: Bool) -> CGSize {
        size(for: VaultEntry(path: path, isDirectory: isDirectory))
    }

    /// A pasted picture's card: a card's width and the picture's own shape,
    /// kept between a strip and a page so a panorama or a phone screenshot
    /// still lands as something you can grab.
    static func size(forImage pixels: CGSize) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return cardSize }
        let width = cardSize.width
        let height = (width * pixels.height / pixels.width).rounded()
        return CGSize(width: width, height: min(max(height, 120), 640))
    }

    /// The file a pasted picture is written to, as Obsidian names it:
    /// `Pasted image 2026-09-29 14.32.png`, then ` 2`, ` 3` while taken.
    static func pastedImageName(at date: Date, ext: String = "png", taken: (String) -> Bool) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH.mm"
        let stem = "Pasted image \(format.string(from: date))"
        var name = "\(stem).\(ext)"
        var i = 2
        while taken(name) {
            name = "\(stem) \(i).\(ext)"
            i += 1
        }
        return name
    }

    /// Files in rows: a grid a hand can rearrange. A row is as tall as the
    /// tallest card in it, so a page-shaped document does not sit on the
    /// row beneath it. A folder has no card; it is a section on Home.
    static func autoLayout(_ entries: [VaultEntry]) -> [CanvasNode] {
        var nodes: [CanvasNode] = []
        let files = entries.filter { !$0.isDirectory }
        var y = origin.y
        var column = 0, rowHeight = 0.0
        for entry in files {
            let size = size(for: entry)
            let frame = CGRect(x: origin.x + Double(column) * (cardSize.width + cardGap.width),
                               y: y, width: size.width, height: size.height)
            nodes.append(CanvasNode(kind: .file, frame: frame, file: entry.path))
            rowHeight = max(rowHeight, size.height)
            column += 1
            if column == columns {
                column = 0
                y += rowHeight + cardGap.height
                rowHeight = 0
            }
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
