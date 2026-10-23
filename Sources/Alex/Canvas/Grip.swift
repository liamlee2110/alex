import Foundation
import CoreGraphics

/// A resize grip: which edges of a node's frame it moves, and where it sits
/// relative to that frame. The grips themselves are not drawn — the pointer
/// over an edge is what says the edge resizes, as it is on a window — but
/// a selection wears Figma's square at each corner (revision 26), under the
/// corner grip that answers for it, which is centred on it (revision 66).
///
/// Sides are declared before corners: the two share ground at every corner,
/// later is higher in a `ZStack`, and a corner has to win there or its two
/// axes would come apart under the pointer.
enum Grip: CaseIterable, Hashable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight

    /// What a folded card gets, its height not being the grip's to set.
    static let sides: [Grip] = [.left, .right]
    static let corners: [Grip] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    /// The grips a node selected alone gets (revision 66). A picture, and
    /// an icon (revision 67), is resized by its corners alone, as on
    /// Miro's, FigJam's and Freeform's desks: a side could only stretch it.
    static func grips(for node: CanvasNode) -> [Grip] {
        node.folded ? sides : node.locksProportions ? corners : allCases
    }

    /// Whether a resize keeps the frame's proportions (revisions 35 and
    /// 66): ⇧ locks them, and on a picture or an icon, locked from the start as
    /// Excalidraw's and tldraw's are, ⇧ frees them. A folded card's height
    /// is the fold's, so it never follows.
    static func keepsProportions(_ node: CanvasNode, shift: Bool) -> Bool {
        !node.folded && (node.locksProportions ? !shift : shift)
    }

    var isCorner: Bool {
        switch self {
        case .left, .right, .top, .bottom: return false
        default: return true
        }
    }

    /// Which way out of the frame the grip lies, per axis.
    var normal: CGPoint {
        switch self {
        case .left: return CGPoint(x: -1, y: 0)
        case .right: return CGPoint(x: 1, y: 0)
        case .top: return CGPoint(x: 0, y: -1)
        case .bottom: return CGPoint(x: 0, y: 1)
        case .topLeft: return CGPoint(x: -1, y: -1)
        case .topRight: return CGPoint(x: 1, y: -1)
        case .bottomLeft: return CGPoint(x: -1, y: 1)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        }
    }

    /// A node dragged down to nothing is a node you cannot find again.
    static func floor(for node: CanvasNode) -> CGSize {
        if node.shape != nil {
            return CGSize(width: ShapeMetrics.minimumThickness, height: ShapeMetrics.minimumThickness)
        }
        return CGSize(width: node.kind == .text ? 120 : 160, height: 80)
    }

    /// The frame this grip makes when dragged `by` screen points at `scale`.
    /// The edges the grip does not own do not move, so the edge opposite the
    /// pointer is the anchor — including once the drag has hit the floor,
    /// which is why an origin is worked out from the far edge rather than
    /// from the translation.
    ///
    /// `proportional` (⇧ held, revision 35) keeps the frame's own
    /// proportions, as Figma does. From a corner, the axis the pointer has
    /// moved further along, in the frame's proportions, leads and the other
    /// follows, so a straight drag keeps the corner under the pointer and
    /// a drag inward shrinks. From a side, the dragged axis leads and the
    /// other grows about its middle. The floor holds on both axes.
    ///
    /// `fromCentre` (⌥ held, revision 53, Excalidraw's) moves the opposite
    /// edge as far the other way, so the frame grows and shrinks about its
    /// centre, which stays put.
    func resizing(_ frame: CGRect, by translation: CGSize, scale: CGFloat, floor: CGSize,
                  proportional: Bool = false, fromCentre: Bool = false) -> CGRect {
        let reach: CGFloat = fromCentre ? 2 : 1
        let dx = translation.width / scale * reach, dy = translation.height / scale * reach
        var out = frame
        if normal.x != 0 {
            out.size.width = max(floor.width, frame.width + dx * normal.x)
            out.origin.x = fromCentre ? frame.midX - out.width / 2
                : normal.x > 0 ? frame.minX : frame.maxX - out.width
        }
        if normal.y != 0 {
            out.size.height = max(floor.height, frame.height + dy * normal.y)
            out.origin.y = fromCentre ? frame.midY - out.height / 2
                : normal.y > 0 ? frame.minY : frame.maxY - out.height
        }
        guard proportional, frame.width > 0, frame.height > 0 else { return out }
        // How far the pointer has gone along each axis the grip owns, in
        // the frame's proportions; an axis it does not own cannot lead.
        let alongX = normal.x == 0 ? -1 : abs(dx) / frame.width
        let alongY = normal.y == 0 ? -1 : abs(dy) / frame.height
        var ratio = alongX >= alongY ? out.width / frame.width : out.height / frame.height
        ratio = max(ratio, floor.width / frame.width, floor.height / frame.height)
        let size = CGSize(width: frame.width * ratio, height: frame.height * ratio)
        if fromCentre {
            return CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
        return CGRect(x: normal.x > 0 ? frame.minX : normal.x < 0 ? frame.maxX - size.width : frame.midX - size.width / 2,
                      y: normal.y > 0 ? frame.minY : normal.y < 0 ? frame.maxY - size.height : frame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

extension CanvasSide {
    /// The side of `frame` whose connector the pointer at `point` brings
    /// out (revision 42): a band along each side, `inside` deep on the
    /// frame's side of the edge and `outside` beyond it, kept clear of the
    /// corners, which are the resize grips'. Nil in the middle, at a
    /// corner and farther off. A narrow frame keeps a quarter of its
    /// width at each end for the corners rather than losing the band.
    static func near(_ point: CGPoint, _ frame: CGRect, inside: CGFloat, outside: CGFloat) -> CanvasSide? {
        let corner = max(0, min(inside, frame.width / 4, frame.height / 4))
        let alongX = point.x >= frame.minX + corner && point.x <= frame.maxX - corner
        let alongY = point.y >= frame.minY + corner && point.y <= frame.maxY - corner
        if alongX {
            if point.y >= frame.minY - outside && point.y <= frame.minY + inside { return .top }
            if point.y >= frame.maxY - inside && point.y <= frame.maxY + outside { return .bottom }
        }
        if alongY {
            if point.x >= frame.minX - outside && point.x <= frame.minX + inside { return .left }
            if point.x >= frame.maxX - inside && point.x <= frame.maxX + outside { return .right }
        }
        return nil
    }
}
