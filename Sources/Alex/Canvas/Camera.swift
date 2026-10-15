import Foundation
import Combine
import CoreGraphics

/// The desk's camera, apart from the store (revision 25). A pan or a pinch
/// is up to 120 changes a second; published on the store, each one rebuilt
/// every view that reads the store — every card, the sidebar, the palette.
/// Only what is drawn in screen space observes this: the world's
/// transform, the grid, the edges, the zoom bar, a selection's handles.
@MainActor
final class Camera: ObservableObject {
    @Published var viewport = Viewport() {
        didSet {
            guard oldValue != viewport else { return }
            Trace.log("  viewport <- \(viewport)")
            moved?(oldValue, viewport)
        }
    }
    /// The store's hook, which turns a move into the two slow-moving
    /// things the world is built from: what is culled and at what detail.
    var moved: ((Viewport, Viewport) -> Void)?

    /// The zoom rounded up to a step of √2, clamped to what a card is ever
    /// drawn at: the resolution a page or a note is rasterised at. Rounded
    /// up, so a raster is only ever shrunk on screen, never blown up.
    nonisolated static func detail(for scale: CGFloat) -> CGFloat {
        let step = CGFloat(2).squareRoot()
        let level = (log(max(scale, Viewport.minScale)) / log(step)).rounded(.up)
        return min(pow(step, level), Viewport.maxScale)
    }

    /// The world rect whose nodes are built: what shows, a half screen round
    /// it, and what showed before the move, so an animated jump has both
    /// ends built. It is recut only when the view leaves it or is lost in
    /// it (zoomed far in), so a pan inside it changes nothing.
    nonisolated static func cull(_ current: CGRect, old: Viewport, new: Viewport, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .infinite }
        let visible = new.visibleWorld(in: size)
        if current.contains(visible), current.width * current.height < 16 * visible.width * visible.height {
            return current
        }
        let margin = max(visible.width, visible.height) / 2
        let before = old.visibleWorld(in: size)
        let span = visible.union(before)
        // A jump from far away keeps only the new view: the old end is a
        // blur under the camera's motion, not worth a thousand cards.
        let keep = span.width * span.height < 9 * visible.width * visible.height ? span : visible
        return keep.insetBy(dx: -margin, dy: -margin)
    }
}
