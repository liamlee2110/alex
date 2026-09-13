import SwiftUI

/// Edges, drawn in screen space so a 1pt line stays 1pt at any zoom.
struct EdgeLayer: View {
    let document: CanvasDocument
    let viewport: Viewport
    /// Edges implied by frontmatter (PLAN.md §4): dashed, never stored.
    var derived: [CanvasStore.DerivedEdge] = []

    var body: some View {
        Canvas { context, _ in
            let byID = Dictionary(document.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for implied in derived {
                guard let a = byID[implied.from], let b = byID[implied.to] else { continue }
                var edge = CanvasEdge(from: implied.from, to: implied.to)
                edge.toEnd = "arrow"
                draw(edge, from: a, to: b, in: &context, dashed: true)
            }
            for edge in document.edges {
                guard let a = byID[edge.fromNode], let b = byID[edge.toNode] else { continue }
                draw(edge, from: a, to: b, in: &context)
            }
        }
    }

    private func draw(_ edge: CanvasEdge, from a: CanvasNode, to b: CanvasNode,
                      in context: inout GraphicsContext, dashed: Bool = false) {
        let sides = EdgeGeometry.sides(from: a.frame, to: b.frame,
                                       fromSide: edge.fromSide, toSide: edge.toSide)
        let p0: CGPoint = viewport.toScreen(EdgeGeometry.anchor(a.frame, sides.from))
        let p3: CGPoint = viewport.toScreen(EdgeGeometry.anchor(b.frame, sides.to))
        let distance: CGFloat = hypot(p3.x - p0.x, p3.y - p0.y)
        let reach: CGFloat = min(max(distance * 0.4, 30), 220)
        let n0: CGPoint = EdgeGeometry.normal(sides.from)
        let n3: CGPoint = EdgeGeometry.normal(sides.to)
        let c1 = CGPoint(x: p0.x + n0.x * reach, y: p0.y + n0.y * reach)
        let c2 = CGPoint(x: p3.x + n3.x * reach, y: p3.y + n3.y * reach)
        var path = Path()
        path.move(to: p0)
        path.addCurve(to: p3, control1: c1, control2: c2)

        let color: Color = edge.color.map { Hepta.label($0) } ?? (dashed ? Ink.guide.opacity(0.55) : Ink.guide)
        let width: CGFloat = 1.5
        let dash: [CGFloat] = dashed ? [6, 5] : []
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))

        let arrowSize: CGFloat = 9
        if edge.toEnd != "none" {
            EdgeGeometry.arrow(at: p3, from: c2, size: arrowSize, in: &context, color: color)
        }
        if edge.fromEnd == "arrow" {
            EdgeGeometry.arrow(at: p0, from: c1, size: arrowSize, in: &context, color: color)
        }
        guard let label = edge.label, !label.isEmpty, viewport.scale > 0.3 else { return }
        let midX: CGFloat = 0.125 * p0.x + 0.375 * c1.x + 0.375 * c2.x + 0.125 * p3.x
        let midY: CGFloat = 0.125 * p0.y + 0.375 * c1.y + 0.375 * c2.y + 0.125 * p3.y
        let mid = CGPoint(x: midX, y: midY)
        let text = context.resolve(Text(label).font(Typography.micro).foregroundStyle(Ink.muted))
        let size: CGSize = text.measure(in: CGSize(width: 240, height: 60))
        let pill = CGRect(x: mid.x - size.width / 2 - 6, y: mid.y - size.height / 2 - 3,
                          width: size.width + 12, height: size.height + 6)
        context.fill(Path(roundedRect: pill, cornerRadius: Radius.mark), with: .color(Ink.card))
        context.draw(text, at: mid, anchor: .center)
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

    static func arrow(at tip: CGPoint, from control: CGPoint, size: CGFloat,
                      in context: inout GraphicsContext, color: Color) {
        let dx = tip.x - control.x, dy = tip.y - control.y
        let len = max(hypot(dx, dy), 0.001)
        let ux = dx / len, uy = dy / len
        let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
        let left = CGPoint(x: base.x - uy * size * 0.5, y: base.y + ux * size * 0.5)
        let right = CGPoint(x: base.x + uy * size * 0.5, y: base.y - ux * size * 0.5)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}
