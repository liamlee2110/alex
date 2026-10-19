import CoreGraphics

/// How an edge runs between its two blocks (revision 62): Excalidraw's
/// three arrow types — a curve leaving each side square to it, a straight
/// line, and an elbow of right angles. Written as `x-route`; a curve, what
/// every edge was before, is written as no key.
enum EdgeRoute: String, CaseIterable {
    case curved, straight, elbow

    var title: String {
        switch self {
        case .curved: return "Curved"
        case .straight: return "Straight"
        case .elbow: return "Elbow"
        }
    }
}

/// An edge's own style (revision 62), under the keys a shape's stroke uses
/// (revision 55), so a line drawn and an edge drawn say it the same way.
/// JSON Canvas's own `color`, `fromEnd` and `toEnd` stay where they are.
extension CanvasEdge {
    var route: EdgeRoute {
        get { extra["x-route"]?.string.flatMap(EdgeRoute.init(rawValue:)) ?? .curved }
        set { extra["x-route"] = newValue == .curved ? nil : .string(newValue.rawValue) }
    }

    var strokeWidth: Double? {
        get { extra["x-stroke-width"]?.double }
        set { extra["x-stroke-width"] = newValue.map { .number($0) } }
    }

    /// The width the line is drawn at, in the desk's points: it shrinks
    /// with the zoom, as the blocks it joins do.
    var strokeLineWidth: CGFloat { CGFloat(strokeWidth ?? StrokeWidth.regular.rawValue) }

    var strokePattern: StrokePattern {
        get { extra["x-stroke-style"]?.string.flatMap(StrokePattern.init(rawValue:)) ?? .solid }
        set { extra["x-stroke-style"] = newValue == .solid ? nil : .string(newValue.rawValue) }
    }

    /// JSON Canvas's defaults: no head at the start, one at the end.
    var arrowAtStart: Bool { fromEnd == "arrow" }
    var arrowAtEnd: Bool { toEnd != "none" }
}

/// An edge's line in the desk's points: a cubic's four points for a
/// curve, the corners for anything else.
struct EdgePath: Equatable {
    var route: EdgeRoute
    var points: [CGPoint]

    var start: CGPoint { points[0] }
    var end: CGPoint { points[points.count - 1] }
    /// The points the arrowheads point away from: a curve's controls, a
    /// line's other end, an elbow's last corner.
    var startTail: CGPoint { points[1] }
    var endTail: CGPoint { points[points.count - 2] }

    /// The line as short straight pieces, for a press to be measured
    /// against: the curve cut in 32.
    var polyline: [CGPoint] {
        guard route == .curved, points.count == 4 else { return points }
        return (0...32).map { EdgePath.cubic(points, CGFloat($0) / 32) }
    }

    /// Where the label sits: halfway along.
    var middle: CGPoint {
        if route == .curved, points.count == 4 { return EdgePath.cubic(points, 0.5) }
        let line = polyline
        let lengths = zip(line, line.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = lengths.reduce(0, +) / 2
        for (i, length) in lengths.enumerated() {
            if left <= length, length > 0 {
                let t = left / length
                return CGPoint(x: line[i].x + (line[i + 1].x - line[i].x) * t,
                               y: line[i].y + (line[i + 1].y - line[i].y) * t)
            }
            left -= length
        }
        return start
    }

    /// How far `p` is from the line.
    func distance(to p: CGPoint) -> CGFloat {
        let line = polyline
        guard line.count > 1 else { return line.first.map { hypot(p.x - $0.x, p.y - $0.y) } ?? .infinity }
        return zip(line, line.dropFirst()).map { EdgePath.distance(p, $0, $1) }.min() ?? .infinity
    }

    static func cubic(_ c: [CGPoint], _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * c[0].x + b * c[1].x + d * c[2].x + e * c[3].x,
                       y: a * c[0].y + b * c[1].y + d * c[2].y + e * c[3].y)
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        let t = length2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }
}

enum EdgeGeometry {
    static func sides(from a: CGRect, to b: CGRect, fromSide: CanvasSide?, toSide: CanvasSide?)
        -> (from: CanvasSide, to: CanvasSide) {
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        let guessFrom: CanvasSide, guessTo: CanvasSide
        if abs(dx) >= abs(dy) {
            guessFrom = dx > 0 ? .right : .left
            guessTo = dx > 0 ? .left : .right
        } else {
            guessFrom = dy > 0 ? .bottom : .top
            guessTo = dy > 0 ? .top : .bottom
        }
        return (fromSide ?? guessFrom, toSide ?? guessTo)
    }

    static func anchor(_ r: CGRect, _ side: CanvasSide) -> CGPoint {
        switch side {
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        }
    }

    static func normal(_ side: CanvasSide) -> CGPoint {
        switch side {
        case .top: return CGPoint(x: 0, y: -1)
        case .bottom: return CGPoint(x: 0, y: 1)
        case .left: return CGPoint(x: -1, y: 0)
        case .right: return CGPoint(x: 1, y: 0)
        }
    }

    /// The edge's line between the two frames, in the desk's points, so it
    /// is one picture at every zoom (revision 62; it was drawn in screen
    /// points, and at 12% outweighed the blocks it joined).
    static func path(_ edge: CanvasEdge, from a: CGRect, to b: CGRect) -> EdgePath {
        let sides = sides(from: a, to: b, fromSide: edge.fromSide, toSide: edge.toSide)
        let p0 = anchor(a, sides.from), p3 = anchor(b, sides.to)
        switch edge.route {
        case .straight:
            return EdgePath(route: .straight, points: [p0, p3])
        case .elbow:
            let across0 = sides.from == .left || sides.from == .right
            let across3 = sides.to == .left || sides.to == .right
            let corners: [CGPoint]
            switch (across0, across3) {
            case (true, true):
                let x = (p0.x + p3.x) / 2
                corners = [CGPoint(x: x, y: p0.y), CGPoint(x: x, y: p3.y)]
            case (false, false):
                let y = (p0.y + p3.y) / 2
                corners = [CGPoint(x: p0.x, y: y), CGPoint(x: p3.x, y: y)]
            case (true, false):
                corners = [CGPoint(x: p3.x, y: p0.y)]
            case (false, true):
                corners = [CGPoint(x: p0.x, y: p3.y)]
            }
            return EdgePath(route: .elbow, points: [p0] + corners + [p3])
        case .curved:
            let distance = hypot(p3.x - p0.x, p3.y - p0.y)
            let reach = min(max(distance * 0.4, 30), 220)
            let n0 = normal(sides.from), n3 = normal(sides.to)
            return EdgePath(route: .curved, points: [
                p0,
                CGPoint(x: p0.x + n0.x * reach, y: p0.y + n0.y * reach),
                CGPoint(x: p3.x + n3.x * reach, y: p3.y + n3.y * reach),
                p3,
            ])
        }
    }

    /// The topmost edge whose line passes within `reach` of `world`, half
    /// its own width added, as a press on a line is taken (revision 62).
    static func hit(_ document: CanvasDocument, at world: CGPoint, reach: CGFloat) -> CanvasEdge? {
        let frames = Dictionary(document.nodes.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        return document.edges.reversed().first { edge in
            guard let a = frames[edge.fromNode], let b = frames[edge.toNode] else { return false }
            return path(edge, from: a, to: b).distance(to: world) <= reach + edge.strokeLineWidth / 2
        }
    }
}

/// What the style panel offers a selection of edges (revision 62): each
/// value the first edge's, or nil where the edges differ.
struct EdgeScope: Equatable {
    var colour: String?
    var colourShared: Bool
    var width: StrokeWidth?
    var pattern: StrokePattern?
    var route: EdgeRoute?
    var fromArrow: Bool?
    var toArrow: Bool?

    init(_ edges: [CanvasEdge]) {
        func shared<T: Equatable>(_ value: (CanvasEdge) -> T) -> T? {
            guard let first = edges.first.map(value) else { return nil }
            return edges.allSatisfy { value($0) == first } ? first : nil
        }
        let first = edges.first?.color
        colour = first
        colourShared = !edges.isEmpty && edges.allSatisfy { $0.color == first }
        width = shared { StrokeWidth(points: $0.strokeWidth) }
        pattern = shared(\.strokePattern)
        route = shared(\.route)
        fromArrow = shared(\.arrowAtStart)
        toArrow = shared(\.arrowAtEnd)
    }
}
