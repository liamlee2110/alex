import SwiftUI

/// A shape on the desk (PLAN.md, revision 15): a `text` node with
/// `x-shape`, drawn as its outline in the node's colour, filled with that
/// colour's stock when asked, its text centred inside. A line runs between
/// its two points with an arrowhead at either end when asked. Double-click
/// it, or press ↩ with it selected, and it takes text in place, the way a
/// sticky does; Esc or ⌘↩ puts the pen down (revision 50). An empty
/// outline is pressed on its stroke alone (revision 53).
struct ShapeNodeView: View {
    let node: CanvasNode
    let selected: Bool
    var editing = false
    /// `Camera.detail`, for the picture a text box's words are drawn into.
    var zoom: CGFloat = 1
    var onChange: (String) -> Void = { _ in }
    /// The format bar's size menu (revision 33) and its faces (revision 36).
    var onTextSize: (TextSize) -> Void = { _ in }
    var onFamily: (FontFamily) -> Void = { _ in }
    /// Esc or ⌘↩ in its editor (revision 50).
    var onDone: () -> Void = {}
    /// Its editor opened, and closed with these words: one writing, one
    /// undo step (revision 52).
    var onBegin: () -> Void = {}
    var onEnd: (String) -> Void = { _ in }

    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?

    private var kind: ShapeKind { node.shape ?? .rectangle }
    /// The words' size: the node's own, or the body's (revision 33).
    private var size: CGFloat { CGFloat(node.fontSize ?? Typography.bodySize) }
    /// No colour is ink; a colour is Heptabase's label colour, the one a
    /// section's border wears.
    private var stroke: Color { node.color == nil ? Ink.primary : Hepta.label(node.color) }
    private var fill: Color { node.filled ? Hepta.fill(node.color) : .clear }
    /// Its width and pattern (revision 55).
    private var width: CGFloat { node.strokeLineWidth }
    private var style: StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round,
                    dash: Stroke.pattern(node.strokePattern, width: width))
    }
    /// A rectangle's corners (revision 55): the card's own unless it says.
    private var radius: CGFloat { CGFloat(node.cornerRadius ?? Double(Radius.card)) }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let box = CGRect(origin: .zero, size: geo.size)
                if kind == .line {
                    let points = Self.points(node.linePoints, in: geo.size)
                    Self.polyline(points).stroke(stroke, style: style)
                    // Each head points along the segment it ends.
                    if node.lineToEnd == "arrow" {
                        Self.arrowhead(at: points[points.count - 1], from: points[points.count - 2],
                                       width: width).fill(stroke)
                    }
                    if node.lineFromEnd == "arrow" {
                        Self.arrowhead(at: points[0], from: points[1], width: width).fill(stroke)
                    }
                } else if kind == .freedraw {
                    Path(Freehand.path(Self.points(node.linePoints, in: geo.size))).stroke(stroke, style: style)
                } else if kind == .icon {
                    IconMark(name: node.iconName ?? "", size: geo.size, zoom: zoom)
                        .foregroundStyle(stroke)
                } else if kind != .text {
                    let path = Self.outline(kind, in: box.insetBy(dx: width / 2, dy: width / 2), radius: radius)
                    path.fill(fill)
                    path.stroke(stroke, style: style)
                }
            }
            textBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(HitArea(kind: kind, points: node.linePoints, whole: takesInside,
                              reach: Handle.strokeHit / max(zoom, 0.01), radius: radius))
    }

    /// Where a press takes the shape (revision 53), Excalidraw's rule: a
    /// text box, a filled shape, one with words, one selected or one being
    /// written in is pressed anywhere in its box; an empty outline and a
    /// line only near their stroke, so a box drawn round cards leaves the
    /// cards and the desk inside it pressable.
    private var takesInside: Bool {
        if selected || editing || kind == .text || kind == .icon { return true }
        guard kind != .line, kind != .freedraw else { return false }
        return node.filled || !(node.text ?? "").isEmpty
    }

    /// The box, or the outline stroked `reach` wide: as the shape is drawn,
    /// so an ellipse is hit on its curve and a line along itself.
    struct HitArea: Shape {
        let kind: ShapeKind
        let points: [CGPoint]
        let whole: Bool
        let reach: CGFloat
        var radius: CGFloat = Radius.card

        func path(in rect: CGRect) -> Path {
            if whole { return Path(rect) }
            let outline: Path
            if kind == .line, points.count >= 2 {
                outline = ShapeNodeView.polyline(ShapeNodeView.points(points, in: rect.size))
            } else if kind == .freedraw {
                outline = Path(Freehand.path(ShapeNodeView.points(points, in: rect.size)))
            } else {
                outline = ShapeNodeView.outline(kind, in: rect.insetBy(dx: Stroke.shape / 2, dy: Stroke.shape / 2),
                                                radius: radius)
            }
            return outline.strokedPath(StrokeStyle(lineWidth: reach * 2, lineCap: .round, lineJoin: .round))
        }
    }

    /// A text box's words start at its top-left, as typed; a shape's sit
    /// in its middle.
    private var isText: Bool { kind == .text }
    /// The node's alignment (revision 47): left for a text box, centred
    /// for a shape, unless it says otherwise.
    private var alignment: TextAlignment { node.textAlign.text }
    /// Where the block of words sits: across by the alignment, down at the
    /// top of a text box and the middle of a shape.
    private var placement: Alignment {
        Alignment(horizontal: node.textAlign.horizontal, vertical: isText ? .top : .center)
    }
    private var inset: CGFloat { isText ? Space.xs : Space.m }

    @ViewBuilder
    private var textBody: some View {
        if editing, isText {
            // A text box is written in the note editor, format bar and
            // all (revision 29); a shape's centred words stay plain.
            MarkdownEditor(text: $text, scrollable: true,
                           baseSize: size, headingSizes: Typography.deskHeadings(size),
                           takesFocus: true, ink: node.color == nil ? nil : NSColor(stroke),
                           textSize: TextSize(points: node.fontSize), onTextSize: onTextSize,
                           family: node.fontFamily, onFamily: onFamily,
                           alignment: node.textAlign.ns, onDone: onDone)
                .padding(inset)
                .onAppear {
                    text = node.text ?? ""
                    onBegin()
                }
                .onChange(of: text) { _, new in save(new) }
                .onDisappear {
                    saveTask?.cancel()
                    onEnd(text)
                }
        } else if editing {
            // As tall as its lines and padded as the words are drawn
            // below, so they sit where they are drawn, mid-shape, as
            // Excalidraw's do.
            ShapeTextEditor(text: $text, font: DeskFace.font(node.fontFamily, size: size),
                            color: NSColor(ink), alignment: node.textAlign.ns, onDone: onDone)
                .padding(.horizontal, Space.xs)
                .padding(.vertical, 2)
                .padding(inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement)
                .onAppear {
                    text = node.text ?? ""
                    onBegin()
                }
                .onChange(of: text) { _, new in save(new) }
                .onDisappear {
                    saveTask?.cancel()
                    onEnd(text)
                }
        } else if isText, let held = node.text, !held.isEmpty {
            NoteRaster(markdown: held, imageBase: nil, imageStem: "", detail: zoom,
                       base: size, tint: node.color, family: node.fontFamily,
                       alignment: node.textAlign.ns)
                .padding(inset)
        } else if let held = node.text, !held.isEmpty {
            Text(held)
                .font(Typography.desk(size, node.fontFamily))
                .foregroundStyle(ink)
                .multilineTextAlignment(alignment)
                .padding(.horizontal, isText ? 0 : Space.xs)
                .padding(.vertical, isText ? 0 : 2)
                // On a line the words sit on a scrap of paper over it.
                .background(RoundedRectangle(cornerRadius: Radius.mark)
                    .fill(kind == .line ? Ink.card : .clear))
                .padding(inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement)
        } else if isText {
            // An empty text box has nothing else to be seen by.
            Text("Text")
                .font(Typography.desk(size, node.fontFamily))
                .foregroundStyle(Ink.faint)
                .padding(inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement)
        }
    }

    /// Written a moment after typing stops, and when editing ends.
    private func save(_ new: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            onChange(new)
        }
    }

    /// A text box's words wear its colour the way a shape's outline does.
    private var ink: Color { isText ? stroke : Ink.primary }

    // MARK: - Geometry

    static func outline(_ kind: ShapeKind, in rect: CGRect, radius: CGFloat = Radius.card) -> Path {
        switch kind {
        case .rectangle:
            return Path(roundedRect: rect, cornerRadius: min(radius, min(rect.width, rect.height) / 2))
        case .ellipse:
            return Path(ellipseIn: rect)
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case .line, .text, .freedraw, .icon:
            return Path()
        }
    }

    /// A line's points, fractions of its box, in a box of `size`.
    static func points(_ fractions: [CGPoint], in size: CGSize) -> [CGPoint] {
        fractions.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    /// The edge layer's arrowhead, as a path: a filled triangle whose tip
    /// is at `tip`, pointing away from `tail`.
    static func arrowhead(at tip: CGPoint, from tail: CGPoint, width: CGFloat = Stroke.shape) -> Path {
        // A heavier line takes a larger head (revision 55).
        let size = Stroke.arrowhead * max(1, width / Stroke.shape * 0.75)
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        let len = max(hypot(dx, dy), 0.001)
        let ux = dx / len, uy = dy / len
        let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x - uy * size * 0.5, y: base.y + ux * size * 0.5))
        path.addLine(to: CGPoint(x: base.x + uy * size * 0.5, y: base.y - ux * size * 0.5))
        path.closeSubpath()
        return path
    }
}

/// An icon on the desk (revision 67): Lucide's drawing in the node's
/// colour, as large as the square its box holds, centred. The sprite is
/// asked for it at the size it shows on screen, rounded up to a step, so
/// it stays sharp as the desk zooms without a new picture at every frame
/// of a pinch.
struct IconMark: View {
    let name: String
    let size: CGSize
    let zoom: CGFloat

    var body: some View {
        let side = min(size.width, size.height)
        let step = Icon.box(Icon.control)
        let pixels = min(max((side * zoom / step).rounded(.up) * step, step), Icon.deskRaster)
        if let image = LucideSprite.shared.image(name, box: pixels, stroke: Icon.Weight.regular.stroke, filled: false) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .frame(width: side, height: side)
                .frame(width: size.width, height: size.height)
        }
    }
}

/// A shape's name and glyph, for Find on canvas and anything else that
/// lists it.
enum ShapeLabel {
    /// What a shape is called: a line with an arrowhead at either end is
    /// an arrow.
    static func name(of node: CanvasNode) -> String {
        if node.shape == .line {
            return node.lineToEnd == "arrow" || node.lineFromEnd == "arrow" ? "Arrow" : "Line"
        }
        if node.shape == .freedraw { return "Drawing" }
        if node.shape == .icon { return "Icon" }
        return node.shape.map(\.rawValue.capitalized) ?? "Shape"
    }

    /// The palette's glyph for it.
    static func symbol(of node: CanvasNode) -> Glyph {
        if node.shape == .line, node.lineToEnd == "arrow" || node.lineFromEnd == "arrow" {
            return DrawTool.arrow.symbol
        }
        if node.shape == .text { return .type }
        if node.shape == .freedraw { return .pen }
        if node.shape == .icon { return .shapes }
        return node.shape.flatMap { DrawTool(rawValue: $0.rawValue) }?.symbol ?? DrawTool.rectangle.symbol
    }
}
