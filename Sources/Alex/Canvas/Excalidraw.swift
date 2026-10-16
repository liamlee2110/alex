import Foundation
import CoreGraphics

/// A clip copied in Excalidraw (revision 57): ⌘C there puts its elements
/// on the pasteboard as JSON text, `{"type":"excalidraw/clipboard",
/// "elements":[…],"files":{…}}`, and ⌘V on the desk turns them into Alex's
/// own nodes and edges, editable as if drawn here. The pure part is here;
/// writing the pictures and the undo step are `CanvasStore.paste(_:)`.
///
/// What maps: rectangles, ellipses and diamonds are shapes, with their
/// words when a text is bound inside; a free text is a text box; an arrow
/// or line bound at both ends to pasted shapes is a connector, its bound
/// text the label, and any other is a line through its points; a freehand
/// stroke is a stroke drawn by hand (revision 58); a picture is a picture beside the
/// canvas; a frame is a section; an embed is a link card. Colours snap to
/// none and the four, widths and patterns to the style panel's. Angles,
/// opacity, roughness, fill patterns, groups and locks are left behind.
struct ExcalidrawClip {
    /// A picture to write beside the canvas before the clip is placed: the
    /// node it belongs to has no `file` until then.
    struct Picture: Equatable {
        var data: Data
        /// The file's extension, from the picture's MIME type.
        var ext: String
    }

    var nodes: [CanvasNode]
    var edges: [CanvasEdge]
    /// By node id.
    var pictures: [String: Picture]

    /// The two document types that carry elements: a clip, and a whole
    /// `.excalidraw` file's text copied as it is.
    static let types: Set<String> = ["excalidraw/clipboard", "excalidraw"]

    init?(text: String) {
        guard text.contains("excalidraw"),
              let raw = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let top = raw as? [String: Any],
              let type = top["type"] as? String, Self.types.contains(type),
              let list = top["elements"] as? [[String: Any]] else { return nil }
        let files = top["files"] as? [String: Any] ?? [:]
        let elements = list.filter { ($0["isDeleted"] as? Bool) != true && $0["id"] is String }
        var nodes: [CanvasNode] = []
        var edges: [CanvasEdge] = []
        var pictures: [String: Picture] = [:]
        /// Excalidraw's id to the node made from it.
        var made: [String: String] = [:]

        // Shapes, free text, pictures, frames and embeds first, so an
        // arrow can find both its ends whatever the order.
        for e in elements {
            let id = e["id"] as! String
            let type = e["type"] as? String ?? ""
            let frame = Self.frame(e)
            var node: CanvasNode
            switch type {
            case "rectangle", "ellipse", "diamond":
                node = CanvasNode.shape(ShapeKind(rawValue: type)!, frame: frame)
                Self.style(&node, e)
                if type == "rectangle", e["roundness"] is NSNull || e["roundness"] == nil {
                    node.cornerRadius = CornerSize.none.rawValue
                }
            case "text":
                // Words bound to something are that thing's; they come below.
                if let container = e["containerId"] as? String,
                   elements.contains(where: { $0["id"] as? String == container }) { continue }
                node = CanvasNode.shape(.text, frame: frame)
                Self.words(&node, e)
                node.frame = Self.textBox(frame, for: node)
            case "freedraw":
                guard let line = Self.line(e, simplify: true) else { continue }
                node = line
            case "image":
                guard let fileID = e["fileId"] as? String,
                      let entry = files[fileID] as? [String: Any],
                      let picture = Self.picture(entry) else { continue }
                node = CanvasNode(kind: .file, frame: frame)
                pictures[node.id] = picture
            case "frame", "magicframe":
                node = CanvasNode(kind: .group, frame: frame, label: (e["name"] as? String) ?? "Frame")
            case "embeddable":
                guard let link = e["link"] as? String, URL(string: link)?.scheme?.hasPrefix("http") == true else { continue }
                node = CanvasNode(kind: .link, frame: frame, url: link)
            default:
                continue
            }
            made[id] = node.id
            nodes.append(node)
        }

        // Arrows and lines: a connector when both ends hold pasted nodes,
        // else a line where it was drawn.
        var edgeFor: [String: Int] = [:]
        var lineFor: [String: String] = [:]
        for e in elements {
            let id = e["id"] as! String
            let type = e["type"] as? String ?? ""
            guard type == "arrow" || type == "line" else { continue }
            let start = (e["startBinding"] as? [String: Any])?["elementId"] as? String
            let end = (e["endBinding"] as? [String: Any])?["elementId"] as? String
            if let start, let end, start != end, let from = made[start], let to = made[end] {
                var edge = CanvasEdge(from: from, to: to)
                edge.fromSide = Self.side(e["startBinding"])
                edge.toSide = Self.side(e["endBinding"])
                if e["startArrowhead"] is String { edge.fromEnd = "arrow" }
                if !(e["endArrowhead"] is String) { edge.toEnd = "none" }
                edge.color = Self.colour(e["strokeColor"])
                edgeFor[id] = edges.count
                edges.append(edge)
            } else if let line = Self.line(e, simplify: false) {
                lineFor[id] = line.id
                nodes.append(line)
            }
        }

        // Bound words: a shape's own text, a connector's label; on a line,
        // which holds no words, a text box where they stood.
        for e in elements where e["type"] as? String == "text" {
            guard let container = e["containerId"] as? String else { continue }
            let words = Self.text(e)
            if let nodeID = made[container], let i = nodes.firstIndex(where: { $0.id == nodeID }),
               nodes[i].shape != nil {
                Self.words(&nodes[i], e)
            } else if let i = edgeFor[container] {
                edges[i].label = words
            } else if lineFor[container] != nil || made[container] != nil {
                var node = CanvasNode.shape(.text, frame: Self.frame(e))
                Self.words(&node, e)
                nodes.append(node)
            }
        }

        guard !nodes.isEmpty else { return nil }
        self.nodes = nodes
        self.edges = edges
        self.pictures = pictures
    }

    // MARK: - Reading an element

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// Its box, Excalidraw's x, y, width and height, made positive.
    static func frame(_ e: [String: Any]) -> CGRect {
        CGRect(x: number(e["x"]) ?? 0, y: number(e["y"]) ?? 0,
               width: number(e["width"]) ?? 0, height: number(e["height"]) ?? 0).standardized
    }

    /// Colour, fill, width and pattern, as the style panel holds them. A
    /// filled shape takes its fill's colour, else its stroke's.
    private static func style(_ node: inout CanvasNode, _ e: [String: Any]) {
        let fill = colour(e["backgroundColor"])
        node.filled = isPainted(e["backgroundColor"])
        node.color = node.filled ? (fill ?? colour(e["strokeColor"])) : colour(e["strokeColor"])
        stroke(&node, e)
    }

    private static func stroke(_ node: inout CanvasNode, _ e: [String: Any]) {
        let width = StrokeWidth(points: number(e["strokeWidth"]))
        node.strokeWidth = width == .regular ? nil : width.rawValue
        node.strokePattern = (e["strokeStyle"] as? String).flatMap(StrokePattern.init(rawValue:)) ?? .solid
    }

    private static func text(_ e: [String: Any]) -> String {
        (e["originalText"] as? String) ?? (e["text"] as? String) ?? ""
    }

    private static func align(_ e: [String: Any]) -> TextAlign? {
        (e["textAlign"] as? String).flatMap(TextAlign.init(rawValue:))
    }

    /// Words, their colour, size, face and alignment.
    private static func words(_ node: inout CanvasNode, _ e: [String: Any]) {
        node.text = text(e)
        if node.shape == .text { node.color = colour(e["strokeColor"]) }
        let size = textSize(number(e["fontSize"]))
        node.fontSize = size == .medium ? nil : size.rawValue
        node.fontFamily = family(number(e["fontFamily"]))
        if let align = align(e) { node.textAlign = align }
    }

    /// A text box's frame: Excalidraw's, grown until its words fit in
    /// Alex's face at Alex's size, a line a size and a half deep and a
    /// character at most two thirds of the size wide (a monospaced face's
    /// is six tenths), so nothing wraps or is cut off that did not before.
    static func textBox(_ frame: CGRect, for node: CanvasNode) -> CGRect {
        let size = node.fontSize ?? TextSize.medium.rawValue
        let lines = (node.text ?? "").components(separatedBy: "\n")
        let longest = Double(lines.map(\.count).max() ?? 0)
        let rim = 2 * Double(ShapeMetrics.minimumThickness) / 3
        var box = frame
        box.size.width = max(box.width, longest * size * 0.67 + rim, ShapeMetrics.minimumThickness)
        box.size.height = max(box.height, Double(lines.count) * size * 1.5 + rim, ShapeMetrics.minimumThickness)
        return box
    }

    /// Excalidraw's sizes, 16, 20, 28 and 36, are its S, M, L and XL:
    /// Alex's own four at the same step.
    static func textSize(_ points: Double?) -> TextSize {
        let steps: [(Double, TextSize)] = [(16, .small), (20, .medium), (28, .large), (36, .extraLarge)]
        let p = points ?? 20
        return steps.min { abs($0.0 - p) < abs($1.0 - p) }!.1
    }

    /// Virgil (1) and Excalifont (5) are hand-drawn; Cascadia (3) and
    /// Comic Shanns (8) are code; the rest are the system's face.
    static func family(_ code: Double?) -> FontFamily {
        switch Int(code ?? 5) {
        case 1, 5: return .handDrawn
        case 3, 8: return .code
        default: return .normal
        }
    }

    /// A line through the element's points, which Excalidraw keeps
    /// relative to its x and y; a freehand stroke's hundreds of points
    /// are thinned to those a point or more apart and drawn by hand.
    private static func line(_ e: [String: Any], simplify: Bool) -> CanvasNode? {
        let origin = CGPoint(x: number(e["x"]) ?? 0, y: number(e["y"]) ?? 0)
        var points: [CGPoint] = (e["points"] as? [[Any]] ?? []).compactMap { pair in
            guard pair.count >= 2, let x = number(pair[0]), let y = number(pair[1]) else { return nil }
            return CGPoint(x: origin.x + x, y: origin.y + y)
        }
        if simplify {
            var kept: [CGPoint] = []
            for p in points where kept.last.map({ hypot(p.x - $0.x, p.y - $0.y) >= 1 }) ?? true { kept.append(p) }
            if let last = points.last, kept.count == 1 || kept.last != last { kept.append(last) }
            points = kept
        }
        guard !points.isEmpty else { return nil }
        // A stroke by hand is the Draw tool's (revision 58): ink, no heads.
        if simplify {
            var node = CanvasNode.freehand(through: points, color: colour(e["strokeColor"]))
            stroke(&node, e)
            return node
        }
        guard points.count >= 2 else { return nil }
        var node = CanvasNode.line(through: points, color: colour(e["strokeColor"]))
        stroke(&node, e)
        if e["startArrowhead"] is String { node.lineFromEnd = "arrow" }
        if e["endArrowhead"] is String { node.lineToEnd = "arrow" }
        return node
    }

    /// Which side of its element an arrow's end holds: from the binding's
    /// `fixedPoint`, a fraction of the element's box, the nearest side;
    /// nil, so the desk chooses, for a binding that has none.
    static func side(_ binding: Any?) -> CanvasSide? {
        guard let point = (binding as? [String: Any])?["fixedPoint"] as? [Any], point.count == 2,
              let fx = number(point[0]), let fy = number(point[1]) else { return nil }
        let reach: [(Double, CanvasSide)] = [(fx, .left), (1 - fx, .right), (fy, .top), (1 - fy, .bottom)]
        return reach.min { $0.0 < $1.0 }!.1
    }

    private static func picture(_ entry: [String: Any]) -> Picture? {
        guard let url = entry["dataURL"] as? String, let comma = url.firstIndex(of: ","),
              url.hasPrefix("data:"), url[..<comma].hasSuffix(";base64"),
              let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
        let mime = (entry["mimeType"] as? String) ?? String(url.dropFirst(5).prefix { $0 != ";" })
        let ext: String
        switch mime {
        case "image/jpeg": ext = "jpg"
        case "image/gif": ext = "gif"
        case "image/webp": ext = "webp"
        case "image/svg+xml": ext = "svg"
        case "image/png": ext = "png"
        default: return nil
        }
        return Picture(data: data, ext: ext)
    }

    // MARK: - Colour

    /// An Excalidraw colour, `#rrggbb` or `#rgb`, snapped to Alex's four
    /// (revision 56) by hue: red, yellow (orange's nearest), green and
    /// blue (cyan's, violet's). Black, white and greys are none, the ink.
    static func colour(_ value: Any?) -> String? {
        guard let rgb = rgb(value) else { return nil }
        let hi = max(rgb.r, rgb.g, rgb.b), lo = min(rgb.r, rgb.g, rgb.b)
        let chroma = hi - lo
        guard chroma >= 0.08 else { return nil }
        var hue: Double
        if hi == rgb.r { hue = 60 * ((rgb.g - rgb.b) / chroma) }
        else if hi == rgb.g { hue = 60 * ((rgb.b - rgb.r) / chroma + 2) }
        else { hue = 60 * ((rgb.r - rgb.g) / chroma + 4) }
        if hue < 0 { hue += 360 }
        let anchors: [(Double, String)] = [(0, "1"), (50, "3"), (130, "4"), (215, "5"), (360, "1")]
        return anchors.min { abs($0.0 - hue) < abs($1.0 - hue) }!.1
    }

    /// Painted: anything but `transparent` (or a colour with no alpha).
    private static func isPainted(_ value: Any?) -> Bool {
        guard let s = value as? String else { return false }
        return s != "transparent" && !(s.count == 9 && s.hasSuffix("00")) && rgb(s) != nil
    }

    private static func rgb(_ value: Any?) -> (r: Double, g: Double, b: Double)? {
        guard var s = value as? String, s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 || s.count == 4 { s = String(s.prefix(3).flatMap { [$0, $0] }) }
        guard s.count >= 6, let n = UInt32(s.prefix(6), radix: 16) else { return nil }
        return (Double((n >> 16) & 0xff) / 255, Double((n >> 8) & 0xff) / 255, Double(n & 0xff) / 255)
    }
}
