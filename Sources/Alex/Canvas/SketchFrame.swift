import Foundation
import CoreGraphics

/// The quick sketch's window as geometry (revision 63): which edge a press
/// takes, the frame a drag on it makes, and where the sketch comes back.
/// Pure, so the canvas suite can hold it; the drag itself is dogfood.
///
/// The window is the card and, round it, `margin` of room for the card's
/// shadow, so its own edges are in empty air. The grips are the card's
/// edges instead: a band `outside` deep into that room and `inside` deep
/// over the desk, the desk's top beside the tab and the tab's top over it.
enum SketchFrame {
    static let outside: CGFloat = 6
    static let inside: CGFloat = 3
    /// How far along an edge from a corner the corner's grip reaches.
    static let corner: CGFloat = 16

    /// The grip under `point`, in the window's own coordinates with y
    /// down, as `Grip` reads them; nil off the edges, and on the tab's
    /// sides, which only stand on the desk.
    static func grip(at point: CGPoint, in bounds: CGRect, margin: CGFloat,
                     tab: CGSize) -> Grip? {
        let card = bounds.insetBy(dx: margin, dy: margin)
        guard card.width > 0, card.height > tab.height else { return nil }
        let deskTop = card.minY + tab.height
        let overTab = abs(point.x - card.midX) <= tab.width / 2
        let top = overTab ? card.minY : deskTop
        let acrossX = point.x >= card.minX - outside && point.x <= card.maxX + outside
        let acrossY = point.y >= deskTop - outside && point.y <= card.maxY + outside
        let left = acrossY && point.x >= card.minX - outside && point.x <= card.minX + inside
        let right = acrossY && point.x >= card.maxX - inside && point.x <= card.maxX + outside
        let upper = acrossX && point.y >= top - outside && point.y <= top + inside
        let lower = acrossX && point.y >= card.maxY - inside && point.y <= card.maxY + outside
        let nearLeft = point.x <= card.minX + corner, nearRight = point.x >= card.maxX - corner
        let nearTop = point.y <= deskTop + corner, nearBottom = point.y >= card.maxY - corner
        if (left && nearTop) || (upper && nearLeft) { return .topLeft }
        if (right && nearTop) || (upper && nearRight) { return .topRight }
        if (left && nearBottom) || (lower && nearLeft) { return .bottomLeft }
        if (right && nearBottom) || (lower && nearRight) { return .bottomRight }
        if left { return .left }
        if right { return .right }
        if upper { return .top }
        if lower { return .bottom }
        return nil
    }

    /// The window's frame, on screen with y up, after `grip` is dragged
    /// `by` that far: the edge opposite stays, and the frame keeps
    /// `minimum`.
    static func resized(_ frame: CGRect, grip: Grip, by translation: CGVector, minimum: CGSize) -> CGRect {
        // `Grip` reads y down: turn the screen over, resize, turn it back.
        let flipped = CGRect(x: frame.minX, y: -frame.maxY, width: frame.width, height: frame.height)
        let out = grip.resizing(flipped, by: CGSize(width: translation.dx, height: -translation.dy),
                                scale: 1, floor: minimum)
        return CGRect(x: out.minX, y: -out.maxY, width: out.width, height: out.height)
    }

    /// Where the sketch comes up: where it was last put, when that is on
    /// the screen the pointer is on, pulled back inside it if it hangs
    /// off; otherwise at that screen's foot, in the middle, a gutter above
    /// the Dock. The size is the one last given, as much of it as fits.
    static func placed(_ last: CGRect?, size: CGSize, on visible: CGRect,
                       margin: CGFloat, gutter: CGFloat) -> CGRect {
        let room = visible.insetBy(dx: gutter - margin, dy: gutter - margin)
        let size = CGSize(width: min(last?.width ?? size.width, room.width),
                          height: min(last?.height ?? size.height, room.height))
        guard let last, visible.contains(CGPoint(x: last.midX, y: last.midY)) else {
            return CGRect(x: visible.midX - size.width / 2, y: room.minY, width: size.width, height: size.height)
        }
        let x = min(max(last.minX, room.minX), room.maxX - size.width)
        let y = min(max(last.maxY - size.height, room.minY), room.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
