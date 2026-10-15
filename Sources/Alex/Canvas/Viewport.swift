import CoreGraphics

/// Where the desk is under the window: screen = world × scale + offset.
struct Viewport: Equatable {
    var offset = CGPoint.zero
    var scale: CGFloat = 1

    static let minScale: CGFloat = 0.12
    static let maxScale: CGFloat = 4
    /// The farthest a focus leaves a card (revision 19): a card's words
    /// still read here, so a focus from an overview zooms this far and no
    /// further, rather than all the way to actual size.
    static let readable: CGFloat = 0.75
    /// Below this share of what it could show, a remembered view has lost
    /// the canvas, and a fit is kinder than putting it back.
    static let lostShare: CGFloat = 0.5

    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y)
    }

    func toWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale)
    }

    func toScreen(_ r: CGRect) -> CGRect {
        CGRect(origin: toScreen(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
    }

    func visibleWorld(in screen: CGSize) -> CGRect {
        CGRect(origin: toWorld(.zero),
               size: CGSize(width: screen.width / scale, height: screen.height / scale))
    }

    /// How much of `content` the view shows, as a share of what it could:
    /// all of it when it is smaller than the view, the view's whole area
    /// when it is larger.
    func share(of content: CGRect, in screen: CGSize) -> CGFloat {
        guard !content.isNull, content.width > 0, content.height > 0, screen.width > 0, screen.height > 0 else { return 1 }
        let visible = visibleWorld(in: screen)
        let shown = visible.intersection(content)
        guard !shown.isNull else { return 0 }
        let room = min(visible.width * visible.height, content.width * content.height)
        return shown.width * shown.height / room
    }

    mutating func pan(by d: CGPoint) {
        offset.x += d.x
        offset.y += d.y
    }

    /// Zoom keeping the world point under `p` (screen) where it is.
    mutating func zoom(by factor: CGFloat, around p: CGPoint) {
        let world = toWorld(p)
        scale = min(max(scale * factor, Self.minScale), Self.maxScale)
        offset = CGPoint(x: p.x - world.x * scale, y: p.y - world.y * scale)
    }

    mutating func center(on world: CGPoint, in screen: CGSize) {
        offset = CGPoint(x: screen.width / 2 - world.x * scale,
                         y: screen.height / 2 - world.y * scale)
    }

    static func fitting(_ rect: CGRect, in screen: CGSize, padding: CGFloat = 80) -> Viewport {
        guard !rect.isNull, rect.width > 0, rect.height > 0, screen.width > 0 else { return Viewport() }
        let s = min((screen.width - 2 * padding) / rect.width,
                    (screen.height - 2 * padding) / rect.height, 1.5)
        let scale = min(max(s, minScale), maxScale)
        var vp = Viewport(offset: .zero, scale: scale)
        vp.center(on: CGPoint(x: rect.midX, y: rect.midY), in: screen)
        return vp
    }
}
