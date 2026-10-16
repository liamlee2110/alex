import Foundation
import CoreGraphics

/// A stroke drawn by hand with the Draw tool (PLAN.md, revision 58, after
/// Excalidraw's freedraw): the pointer's path, thinned to the points that
/// shape it, and the smooth curve drawn through them. Foundation and
/// CoreGraphics only, so the canvas suite can drive it.
enum Freehand {
    /// How far, in screen points, a dropped point may lie from the stroke
    /// that is kept: under half a point, nothing a hand can see.
    static let tolerance: CGFloat = 0.5

    /// The points that shape `points`, Ramer–Douglas–Peucker: every point
    /// within `tolerance` of the line between the two it sits between is
    /// dropped. The first and the last are always kept.
    static func simplified(_ points: [CGPoint], tolerance: CGFloat = tolerance) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(0, points.count - 1)]
        while let (first, last) = spans.popLast() {
            guard last > first + 1 else { continue }
            var farthest = first, distance: CGFloat = 0
            for index in (first + 1)..<last {
                let d = Self.distance(points[index], toSegment: points[first], points[last])
                if d > distance { distance = d; farthest = index }
            }
            if distance > tolerance {
                keep[farthest] = true
                spans.append((first, farthest))
                spans.append((farthest, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// The curve through `points`: a quadratic from each midpoint to the
    /// next with the point between as its control, so the stroke passes
    /// near every point with no corners, from the first to the last. One
    /// point is a dot, the round cap of a line of no length.
    static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for index in 1..<(points.count - 1) {
            let control = points[index], next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2),
                              control: control)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
