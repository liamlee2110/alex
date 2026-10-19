import SwiftUI

/// Edges, drawn at the desk's scale (revision 62): a line and its head
/// shrink with the zoom as the blocks they join do, so an overview is one
/// picture made smaller rather than a web of lines heavier than its cards.
/// A line never thins past `minimumWidth`, so it never vanishes. The label
/// and a selection's marks stay one size on screen, as all chrome does.
struct EdgeLayer: View {
    let document: CanvasDocument
    let viewport: Viewport
    /// Edges implied by frontmatter (PLAN.md §4): dashed, never stored.
    var derived: [CanvasStore.DerivedEdge] = []
    /// The edges picked on the desk, which wear the selection's blue.
    var selected: Set<String> = []

    /// The thinnest a line is drawn on screen, however far out.
    static let minimumWidth: CGFloat = 0.5

    var body: some View {
        Canvas { context, _ in
            let byID = Dictionary(document.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for implied in derived {
                guard let a = byID[implied.from], let b = byID[implied.to] else { continue }
                var edge = CanvasEdge(from: implied.from, to: implied.to)
                edge.toEnd = "arrow"
                edge.strokePattern = .dashed
                draw(edge, from: a, to: b, in: &context, implied: true)
            }
            for edge in document.edges {
                guard let a = byID[edge.fromNode], let b = byID[edge.toNode] else { continue }
                draw(edge, from: a, to: b, in: &context)
            }
        }
    }

    private func draw(_ edge: CanvasEdge, from a: CanvasNode, to b: CanvasNode,
                      in context: inout GraphicsContext, implied: Bool = false) {
        let line: EdgePath = EdgeGeometry.path(edge, from: a.frame, to: b.frame)
        let scale: CGFloat = viewport.scale
        let toScreen = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                         tx: viewport.offset.x, ty: viewport.offset.y)
        var path = Path()
        path.move(to: line.start)
        if line.route == .curved, line.points.count == 4 {
            path.addCurve(to: line.end, control1: line.points[1], control2: line.points[2])
        } else {
            path.addLines(line.points)
        }
        let screenPath: Path = path.applying(toScreen)

        let color: Color = edge.color.map { Hepta.label($0) } ?? (implied ? Ink.guide.opacity(0.55) : Ink.guide)
        let width: CGFloat = max(edge.strokeLineWidth * scale, Self.minimumWidth)
        let pattern: StrokePattern = edge.strokePattern
        let dash: [CGFloat] = Stroke.pattern(pattern, width: edge.strokeLineWidth).map { $0 * scale }
        context.stroke(screenPath, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: pattern == .dashed ? .butt : .round,
                                          lineJoin: .round, dash: dash))

        // The head is the drawn line's own (revision 55), at the desk's scale.
        if edge.arrowAtEnd {
            let head = ShapeNodeView.arrowhead(at: line.end, from: line.endTail, width: edge.strokeLineWidth)
            context.fill(head.applying(toScreen), with: .color(color))
        }
        if edge.arrowAtStart {
            let head = ShapeNodeView.arrowhead(at: line.start, from: line.startTail, width: edge.strokeLineWidth)
            context.fill(head.applying(toScreen), with: .color(color))
        }

        let isSelected: Bool = !implied && selected.contains(edge.id)
        if isSelected { selection(screenPath, ends: [line.start, line.end], in: &context) }

        guard let label = edge.label, !label.isEmpty, scale > 0.3 else { return }
        let mid: CGPoint = viewport.toScreen(line.middle)
        let text = context.resolve(Text(label).font(Typography.micro).foregroundStyle(Ink.muted))
        let size: CGSize = text.measure(in: CGSize(width: 240, height: 60))
        let pill = CGRect(x: mid.x - size.width / 2 - 6, y: mid.y - size.height / 2 - 3,
                          width: size.width + 12, height: size.height + 6)
        context.fill(Path(roundedRect: pill, cornerRadius: Radius.mark), with: .color(Ink.card))
        context.draw(text, at: mid, anchor: .center)
    }

    /// A picked edge, Figma's way: the selection's one-point blue along
    /// the line and a connector's dot at each end, one size at every zoom.
    private func selection(_ path: Path, ends: [CGPoint], in context: inout GraphicsContext) {
        context.stroke(path, with: .color(Accent.text),
                       style: StrokeStyle(lineWidth: Handle.outline, lineCap: .round, lineJoin: .round))
        for end in ends {
            let p: CGPoint = viewport.toScreen(end)
            let dot = Path(ellipseIn: CGRect(x: p.x - Handle.connector / 2, y: p.y - Handle.connector / 2,
                                             width: Handle.connector, height: Handle.connector))
            context.fill(dot, with: .color(Ink.card))
            context.stroke(dot, with: .color(Accent.text), lineWidth: Handle.outline)
        }
    }
}
