import Foundation
import CoreGraphics

/// A shape on the desk (PLAN.md, revision 15): a JSON Canvas `text` node
/// carrying `x-shape`, so Obsidian shows a text card in the same place and
/// nothing in the file is Alex's alone but the `x-` keys (D4). `text` is
/// the Text tool's box: words on the desk with no outline and no paper.
/// `freedraw` is a stroke drawn by hand with the Draw tool (revision 58),
/// Excalidraw's name for it.
enum ShapeKind: String, CaseIterable {
    case rectangle, ellipse, diamond, line, text, freedraw
}

/// What the palette's Shapes menu offers, in its order: the four kinds,
/// with a line that ends in an arrowhead as an entry of its own.
enum DrawTool: String, CaseIterable, Hashable {
    case rectangle, ellipse, diamond, line, arrow

    var kind: ShapeKind {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .diamond: return .diamond
        case .line, .arrow: return .line
        }
    }

    var name: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .diamond: return "Diamond"
        case .line: return "Line"
        case .arrow: return "Arrow"
        }
    }

    var symbol: Glyph {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .circle
        case .diamond: return .diamond
        case .line: return .slash
        case .arrow: return .arrowUpRight
        }
    }

    /// The key that picks it on the desk by default (never in an editor);
    /// `ToolKeys` holds the one in force (revision 40).
    var key: Character {
        switch self {
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .diamond: return "d"
        case .line: return "l"
        case .arrow: return "a"
        }
    }
}

/// FigJam's four text sizes for words on the desk (revision 33), scaled to
/// the desk's 13-point body: Medium is what a sticky has always been.
enum TextSize: Double, CaseIterable {
    case small = 11, medium = 13, large = 20, extraLarge = 32

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }

    /// The style panel's cell (revision 39): Excalidraw's S, M, L, XL.
    var short: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .extraLarge: return "XL"
        }
    }

    /// The preset nearest a size read from a file, which may hold any number.
    init(points: Double?) {
        let p = points ?? TextSize.medium.rawValue
        self = TextSize.allCases.min { abs($0.rawValue - p) < abs($1.rawValue - p) }!
    }
}

/// How round a picture's corners are (revision 45), and a rectangle's
/// (revision 55, Excalidraw's edges), in desk points under `x-radius`:
/// square, the card's own 8 (no key), or rounder.
enum CornerSize: Double, CaseIterable {
    case none = 0, small = 8, medium = 16, large = 32

    var title: String {
        switch self {
        case .none: return "Square corners"
        case .small: return "Small corners"
        case .medium: return "Medium corners"
        case .large: return "Large corners"
        }
    }

    /// The style panel's cell, said as the text sizes are.
    var short: String {
        switch self {
        case .none: return "0"
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    /// The preset nearest a radius read from a file, which may hold any number.
    init(points: Double?) {
        let p = points ?? CornerSize.small.rawValue
        self = CornerSize.allCases.min { abs($0.rawValue - p) < abs($1.rawValue - p) }!
    }
}

/// How heavy a shape's stroke is (revision 55): Excalidraw's thin, bold
/// and extra bold, under `x-stroke-width`; no key is the regular 2.
enum StrokeWidth: Double, CaseIterable {
    case thin = 1, regular = 2, bold = 4

    var title: String {
        switch self {
        case .thin: return "Thin"
        case .regular: return "Regular"
        case .bold: return "Bold"
        }
    }

    /// The preset nearest a width read from a file, which may hold any number.
    init(points: Double?) {
        let p = points ?? StrokeWidth.regular.rawValue
        self = StrokeWidth.allCases.min { abs($0.rawValue - p) < abs($1.rawValue - p) }!
    }
}

/// How a shape's stroke is drawn (revision 55): Excalidraw's solid, dashed
/// and dotted, under `x-stroke-style`. Revision 51's `x-dashed: true` is
/// still read as dashed; a press in the style panel writes the new key.
enum StrokePattern: String, CaseIterable {
    case solid, dashed, dotted

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        }
    }
}

/// Excalidraw's three faces for words on the desk (revision 36): its own
/// hand-drawn Excalifont, bundled, as the default; the system's face; and
/// the system's monospaced one.
enum FontFamily: String, CaseIterable {
    case handDrawn = "hand-drawn", normal, code

    var title: String {
        switch self {
        case .handDrawn: return "Hand-drawn"
        case .normal: return "Normal"
        case .code: return "Code"
        }
    }

    /// The style panel's cell for the face (revision 39): Excalidraw's.
    var glyph: Glyph {
        switch self {
        case .handDrawn: return .pencil
        case .normal: return .type
        case .code: return .codeXml
        }
    }
}

/// Excalidraw's three text alignments (revision 47).
enum TextAlign: String, CaseIterable {
    case left, center, right

    var title: String {
        switch self {
        case .left: return "Align left"
        case .center: return "Align centre"
        case .right: return "Align right"
        }
    }
}

enum ShapeMetrics {
    /// The box a click without a drag makes, centred on the click.
    static let defaultSize = CGSize(width: 160, height: 100)
    /// The line a click without a drag makes, running right from the click.
    static let defaultLineLength: CGFloat = 160
    /// The text box a click without a drag makes, its top-left at the click:
    /// one line of body type and its rim.
    static let defaultTextSize = CGSize(width: 240, height: 40)
    /// The thinnest a shape's box is, in either direction: a level line
    /// still has a box to be selected by and a card to show in another app.
    static let minimumThickness: CGFloat = 24
    /// Under this, in world units, a drag is a click.
    static let dragThreshold: CGFloat = 8
    /// How far down and right a duplicate lands from its original.
    static let duplicateStep: CGFloat = 24
    /// An arrow key's step, and with ⇧ (revision 53, Excalidraw's 1 and 5).
    static let nudge: CGFloat = 1
    static let nudgeLarge: CGFloat = 5
    /// How long after the last arrow key the nudges land as one move: one
    /// write and one undo step for a run of presses, well inside D2's second.
    static let nudgeSettle: Duration = .milliseconds(350)
    /// How far an ⌥-drag goes before it leaves a copy behind
    /// (Excalidraw's `DRAGGING_THRESHOLD`).
    static let duplicateDragThreshold: CGFloat = 10
}

/// What a selection can be styled with (revision 39): each group of the
/// style panel shows when every selected node takes it, and its cells
/// show the value the nodes share, or none while they differ. The rules
/// are the node menu's of revisions 5, 15, 32, 33 and 36, gathered in
/// one place.
struct StyleScope: Equatable {
    var isEmpty: Bool
    /// The first node's colour, and whether every node wears it.
    var colour: String?
    var colourShared: Bool
    /// Outline or filled: a shape that is not a line.
    var fill: Bool
    var filled: Bool?
    /// The stroke's pattern and width: any shape, a line included.
    var stroke: Bool
    var pattern: StrokePattern?
    var width: StrokeWidth?
    /// Solid or dashed, as revision 39 said it: dashed or not.
    var dashed: Bool? { pattern.map { $0 == .dashed } }
    /// Arrowheads: lines only.
    var arrowheads: Bool
    var fromArrow: Bool?
    var toArrow: Bool?
    /// The face: words on the desk but a line's, and a note's card.
    var font: Bool
    var family: FontFamily?
    /// The size: words on the desk but a line's.
    var size: Bool
    var textSize: TextSize?
    /// The alignment: words on the desk but a line's, as the size.
    var align: Bool
    var textAlign: TextAlign?
    /// Order: anything but a section, which keeps to its own layer.
    var order: Bool
    /// Duplicate: a sticky, a text box, a shape or a link; a file has one
    /// card on a canvas.
    var duplicable: Bool
    /// Corners: pictures (revision 45) and rectangles (revision 55).
    var corners: Bool
    var corner: CornerSize?
    /// Fold: files' cards but a picture's (the view leaves a folder's out).
    var foldable: Bool
    var folded: Bool?

    init(_ nodes: [CanvasNode]) {
        isEmpty = nodes.isEmpty
        func all(_ test: (CanvasNode) -> Bool) -> Bool { !nodes.isEmpty && nodes.allSatisfy(test) }
        func shared<T: Equatable>(_ value: (CanvasNode) -> T) -> T? {
            guard let first = nodes.first.map(value), nodes.allSatisfy({ value($0) == first }) else { return nil }
            return first
        }
        colour = nodes.first?.color
        colourShared = all { $0.color == nodes.first?.color }
        fill = all { $0.shape != nil && $0.shape != .text && !$0.isStroke }
        filled = fill ? shared(\.filled) : nil
        stroke = all { $0.shape != nil && $0.shape != .text }
        pattern = stroke ? shared(\.strokePattern) : nil
        width = stroke ? shared { StrokeWidth(points: $0.strokeWidth) } : nil
        arrowheads = all { $0.shape == .line }
        fromArrow = arrowheads ? shared { $0.lineFromEnd == "arrow" } : nil
        toArrow = arrowheads ? shared { $0.lineToEnd == "arrow" } : nil
        font = all { ($0.writtenOnDesk && !$0.isStroke) || ($0.kind == .file && $0.file?.hasSuffix(".md") == true) }
        family = font ? shared(\.fontFamily) : nil
        size = all { $0.writtenOnDesk && !$0.isStroke }
        textSize = size ? shared { TextSize(points: $0.fontSize) } : nil
        align = size
        textAlign = align ? shared(\.textAlign) : nil
        order = all { $0.kind != .group }
        duplicable = all { $0.kind == .text || $0.kind == .link }
        foldable = all { $0.kind == .file && !$0.isImage }
        folded = foldable ? shared(\.folded) : nil
        corners = all { $0.takesCorners }
        corner = corners ? shared { CornerSize(points: $0.cornerRadius) } : nil
    }
}

/// ⇧ while a shape is dragged out (revision 35), as in Figma, FigJam and
/// Excalidraw: the box keeps its proportions, so a rectangle is a square
/// and an ellipse a circle, and a line sits on the nearest step of 15°.
/// Each takes the drag's two points and answers the end point to use in
/// the pointer's place; the start stays where it was pressed.
enum Proportion {
    /// The square of the drag's longer side, grown the way the pointer
    /// went, so the pointer's own corner is the one that tracks it.
    static func square(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let side = max(abs(b.x - a.x), abs(b.y - a.y))
        return CGPoint(x: a.x + (b.x < a.x ? -side : side),
                       y: a.y + (b.y < a.y ? -side : side))
    }

    /// A line's angle step under ⇧: Figma's and Excalidraw's 15°.
    static let angleStep: CGFloat = .pi / 12

    /// The drag's end turned onto the nearest step of `angleStep` round
    /// its start, its length kept.
    static func stepped(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return b }
        let angle = (atan2(b.y - a.y, b.x - a.x) / angleStep).rounded() * angleStep
        return CGPoint(x: a.x + length * cos(angle), y: a.y + length * sin(angle))
    }
}

extension CanvasNode {
    /// Which shape this `text` node is, under `x-shape`; nil is a sticky.
    var shape: ShapeKind? {
        get { extra["x-shape"]?.string.flatMap(ShapeKind.init(rawValue:)) }
        set { extra["x-shape"] = newValue.map { .string($0.rawValue) } }
    }

    /// A sticky note, a text box or a shape: words written on the desk
    /// itself, with nothing for a sheet to add (revision 28); its style
    /// is the style panel's (revision 39).
    var writtenOnDesk: Bool { kind == .text }

    /// A line or a stroke drawn by hand: a path through points, pressed
    /// along itself, never filled and with no side to connect from.
    var isStroke: Bool { shape == .line || shape == .freedraw }

    /// What a double-click or ↩ writes in: words on the desk, but not on
    /// a stroke drawn by hand, which is only ink (revision 58).
    var takesWords: Bool { writtenOnDesk && shape != .freedraw }

    /// A picture's card: the picture is the whole of it, so it neither
    /// folds to a title row nor opens in the detail sheet (revision 45).
    var isImage: Bool {
        kind == .file && file.map { VaultEntry.Kind.forExtension(($0 as NSString).pathExtension) == .image } == true
    }

    /// The size of words written on the desk (revision 33), in points under
    /// `x-font-size`, the body size when the key is missing. A sticky, a
    /// text box or a shape; Markdown has nowhere to say it.
    var fontSize: Double? {
        get { extra["x-font-size"]?.double }
        set { extra["x-font-size"] = newValue.map { .number($0) } }
    }

    /// A picture's corner radius in desk points (revision 45), under
    /// `x-radius`; no key is the card's own.
    var cornerRadius: Double? {
        get { extra["x-radius"]?.double }
        set { extra["x-radius"] = newValue.map { .number($0) } }
    }

    /// The face its words are drawn in (revision 36), under `x-font-family`:
    /// a sticky, a text box, a shape or a note's card. No key is hand-drawn.
    var fontFamily: FontFamily {
        get { extra["x-font-family"]?.string.flatMap(FontFamily.init(rawValue:)) ?? .handDrawn }
        set { extra["x-font-family"] = newValue == .handDrawn ? nil : .string(newValue.rawValue) }
    }

    /// Where its words sit across the box (revision 47), under
    /// `x-text-align`. No key is the kind's own: a sticky's and a text
    /// box's words start at the left, a shape's are centred.
    var textAlign: TextAlign {
        get { extra["x-text-align"]?.string.flatMap(TextAlign.init(rawValue:)) ?? defaultTextAlign }
        set { extra["x-text-align"] = newValue == defaultTextAlign ? nil : .string(newValue.rawValue) }
    }

    var defaultTextAlign: TextAlign {
        shape == nil || shape == .text ? .left : .center
    }

    /// Filled with its colour's stock, under `x-fill`; off is outline only.
    var filled: Bool {
        get { extra["x-fill"]?.bool ?? false }
        set { extra["x-fill"] = newValue ? .bool(true) : nil }
    }

    /// The stroke's pattern (revision 55), under `x-stroke-style`, or
    /// revision 51's `x-dashed`; no key is solid. Writing it clears the old key.
    var strokePattern: StrokePattern {
        get {
            if let raw = extra["x-stroke-style"]?.string, let pattern = StrokePattern(rawValue: raw) { return pattern }
            return extra["x-dashed"]?.bool == true ? .dashed : .solid
        }
        set {
            extra["x-dashed"] = nil
            extra["x-stroke-style"] = newValue == .solid ? nil : .string(newValue.rawValue)
        }
    }

    /// A dashed outline: the pattern, said as revision 51 did.
    var dashed: Bool {
        get { strokePattern == .dashed }
        set { strokePattern = newValue ? .dashed : .solid }
    }

    /// The stroke's width in desk points (revision 55), under
    /// `x-stroke-width`; no key is `StrokeWidth.regular`.
    var strokeWidth: Double? {
        get { extra["x-stroke-width"]?.double }
        set { extra["x-stroke-width"] = newValue.map { .number($0) } }
    }

    /// The width the stroke is drawn at.
    var strokeLineWidth: CGFloat { CGFloat(strokeWidth ?? StrokeWidth.regular.rawValue) }

    /// A picture's card or a rectangle: what the Corners group rounds.
    var takesCorners: Bool { isImage || shape == .rectangle }

    /// A line's points as fractions of its frame, under `x-points`, so a
    /// resize stretches the line with its box: its two ends, or more for a
    /// line that bends or a stroke drawn by hand (revision 57, from
    /// Excalidraw). Left to right across the middle when the key is missing.
    var linePoints: [CGPoint] {
        get {
            let read = (extra["x-points"]?.array ?? []).compactMap { point -> CGPoint? in
                guard let pair = point.array, pair.count == 2,
                      let x = pair[0].double, let y = pair[1].double else { return nil }
                return CGPoint(x: x, y: y)
            }
            return read.count >= 2 ? read : [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)]
        }
        set {
            extra["x-points"] = .array(newValue.map { .array([.number($0.x), .number($0.y)]) })
        }
    }

    /// The line's ends, in the edge's own words (`none` or `arrow`), under
    /// `x-fromEnd` and `x-toEnd`. A line has none; an arrow has one at `to`.
    var lineFromEnd: String? {
        get { extra["x-fromEnd"]?.string }
        set { extra["x-fromEnd"] = newValue.map { .string($0) } }
    }

    var lineToEnd: String? {
        get { extra["x-toEnd"]?.string }
        set { extra["x-toEnd"] = newValue.map { .string($0) } }
    }

    /// The line's ends in world units.
    var lineEndpoints: (from: CGPoint, to: CGPoint) {
        let p = linePoints
        return (CGPoint(x: x + p[0].x * width, y: y + p[0].y * height),
                CGPoint(x: x + p[p.count - 1].x * width, y: y + p[p.count - 1].y * height))
    }

    /// A rectangle, ellipse or diamond filling `frame`.
    static func shape(_ kind: ShapeKind, frame: CGRect, color: String? = nil) -> CanvasNode {
        var node = CanvasNode(kind: .text, frame: frame, text: "", color: color)
        node.shape = kind
        return node
    }

    /// A line from `a` to `b`, its box the two points' bounds widened to
    /// `ShapeMetrics.minimumThickness` where it would be thinner, the points kept
    /// where they were as fractions of that box.
    static func line(from a: CGPoint, to b: CGPoint, arrow: Bool, color: String? = nil) -> CanvasNode {
        var node = line(through: [a, b], color: color)
        if arrow { node.lineToEnd = "arrow" }
        return node
    }

    /// A stroke drawn by hand through `points` (revision 58): boxed as a
    /// line is, its points fractions of the box. One point is a dot.
    static func freehand(through points: [CGPoint], color: String? = nil) -> CanvasNode {
        var node = line(through: points.count == 1 ? [points[0], points[0]] : points, color: color)
        node.shape = .freedraw
        return node
    }

    /// A line through `points`, two or more, boxed as `line(from:to:)` is.
    static func line(through points: [CGPoint], color: String? = nil) -> CanvasNode {
        var box = points.dropFirst().reduce(CGRect(origin: points[0], size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        if box.width < ShapeMetrics.minimumThickness {
            box = box.insetBy(dx: -(ShapeMetrics.minimumThickness - box.width) / 2, dy: 0)
        }
        if box.height < ShapeMetrics.minimumThickness {
            box = box.insetBy(dx: 0, dy: -(ShapeMetrics.minimumThickness - box.height) / 2)
        }
        var node = CanvasNode(kind: .text, frame: box, text: "", color: color)
        node.shape = .line
        // Four places are a hundredth of a point on a box of a hundred.
        func fraction(_ v: CGFloat) -> CGFloat { (v * 10_000).rounded() / 10_000 }
        node.linePoints = points.map {
            CGPoint(x: fraction(($0.x - box.minX) / box.width), y: fraction(($0.y - box.minY) / box.height))
        }
        return node
    }
}
