import Foundation
import CoreGraphics

/// JSON Canvas 1.0 (jsoncanvas.org), the open format Obsidian writes. Alex
/// keeps to the spec and puts anything of its own under `x-` keys, which
/// other tools ignore. Decoding is lenient on purpose: a node needs an id
/// and a type, everything else has a default, and a type Alex does not know
/// stays as an opaque node and is written back unchanged.
enum CanvasSide: String, Hashable {
    case top, right, bottom, left
}

struct CanvasNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case text, file, link, group, other(String)

        init(typeName: String) {
            switch typeName {
            case "text": self = .text
            case "file": self = .file
            case "link": self = .link
            case "group": self = .group
            default: self = .other(typeName)
            }
        }

        var typeName: String {
            switch self {
            case .text: return "text"
            case .file: return "file"
            case .link: return "link"
            case .group: return "group"
            case .other(let t): return t
            }
        }
    }

    var id: String
    var kind: Kind
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var color: String?
    var text: String?
    var file: String?
    var subpath: String?
    var url: String?
    var label: String?
    var background: String?
    var backgroundStyle: String?
    /// Every key the spec does not name, `x-` keys included.
    var extra: [String: JSONValue] = [:]

    static let knownKeys: Set<String> = [
        "id", "type", "x", "y", "width", "height", "color", "text", "file",
        "subpath", "url", "label", "background", "backgroundStyle",
    ]

    init(id: String = CanvasDocument.newID(), kind: Kind, frame: CGRect,
         text: String? = nil, file: String? = nil, url: String? = nil,
         label: String? = nil, color: String? = nil) {
        self.id = id
        self.kind = kind
        x = frame.minX; y = frame.minY; width = frame.width; height = frame.height
        self.text = text; self.file = file; self.url = url; self.label = label; self.color = color
    }

    init?(json: [String: JSONValue]) {
        guard let id = json["id"]?.string, let type = json["type"]?.string else { return nil }
        self.id = id
        kind = Kind(typeName: type)
        x = json["x"]?.double ?? 0
        y = json["y"]?.double ?? 0
        width = json["width"]?.double ?? 320
        height = json["height"]?.double ?? 200
        color = json["color"]?.string
        text = json["text"]?.string
        file = json["file"]?.string
        subpath = json["subpath"]?.string
        url = json["url"]?.string
        label = json["label"]?.string
        background = json["background"]?.string
        backgroundStyle = json["backgroundStyle"]?.string
        extra = json.filter { !Self.knownKeys.contains($0.key) }
    }

    var json: [String: JSONValue] {
        var o = extra
        o["id"] = .string(id)
        o["type"] = .string(kind.typeName)
        o["x"] = .number(x); o["y"] = .number(y)
        o["width"] = .number(width); o["height"] = .number(height)
        if let color { o["color"] = .string(color) }
        if let text { o["text"] = .string(text) }
        if let file { o["file"] = .string(file) }
        if let subpath { o["subpath"] = .string(subpath) }
        if let url { o["url"] = .string(url) }
        if let label { o["label"] = .string(label) }
        if let background { o["background"] = .string(background) }
        if let backgroundStyle { o["backgroundStyle"] = .string(backgroundStyle) }
        return o
    }

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set { x = newValue.minX; y = newValue.minY; width = newValue.width; height = newValue.height }
    }

    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }

    /// Alex's own hue for a folder or sticky, under `x-hue` (degrees).
    var hue: Double? {
        get { extra["x-hue"]?.double }
        set { extra["x-hue"] = newValue.map { .number($0) } }
    }
}

struct CanvasEdge: Identifiable, Hashable {
    var id: String
    var fromNode: String
    var toNode: String
    var fromSide: CanvasSide?
    var toSide: CanvasSide?
    var fromEnd: String?
    var toEnd: String?
    var color: String?
    var label: String?
    var extra: [String: JSONValue] = [:]

    static let knownKeys: Set<String> = [
        "id", "fromNode", "toNode", "fromSide", "toSide", "fromEnd", "toEnd", "color", "label",
    ]

    init(id: String = CanvasDocument.newID(), from: String, to: String, label: String? = nil) {
        self.id = id; fromNode = from; toNode = to; self.label = label
    }

    init?(json: [String: JSONValue]) {
        guard let id = json["id"]?.string,
              let from = json["fromNode"]?.string,
              let to = json["toNode"]?.string else { return nil }
        self.id = id; fromNode = from; toNode = to
        fromSide = json["fromSide"]?.string.flatMap(CanvasSide.init(rawValue:))
        toSide = json["toSide"]?.string.flatMap(CanvasSide.init(rawValue:))
        fromEnd = json["fromEnd"]?.string
        toEnd = json["toEnd"]?.string
        color = json["color"]?.string
        label = json["label"]?.string
        extra = json.filter { !Self.knownKeys.contains($0.key) }
    }

    var json: [String: JSONValue] {
        var o = extra
        o["id"] = .string(id)
        o["fromNode"] = .string(fromNode)
        o["toNode"] = .string(toNode)
        if let fromSide { o["fromSide"] = .string(fromSide.rawValue) }
        if let toSide { o["toSide"] = .string(toSide.rawValue) }
        if let fromEnd { o["fromEnd"] = .string(fromEnd) }
        if let toEnd { o["toEnd"] = .string(toEnd) }
        if let color { o["color"] = .string(color) }
        if let label { o["label"] = .string(label) }
        return o
    }
}

enum CanvasFileError: Error, CustomStringConvertible {
    case notAnObject
    var description: String { "The canvas file is not a JSON object." }
}

struct CanvasDocument: Hashable {
    var nodes: [CanvasNode] = []
    var edges: [CanvasEdge] = []
    var extra: [String: JSONValue] = [:]

    static func decode(_ data: Data) throws -> CanvasDocument {
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let top = raw as? [String: Any], let root = JSONValue(any: top)?.object else {
            throw CanvasFileError.notAnObject
        }
        var doc = CanvasDocument()
        doc.nodes = (root["nodes"]?.array ?? []).compactMap { $0.object.flatMap(CanvasNode.init(json:)) }
        doc.edges = (root["edges"]?.array ?? []).compactMap { $0.object.flatMap(CanvasEdge.init(json:)) }
        doc.extra = root.filter { $0.key != "nodes" && $0.key != "edges" }
        return doc
    }

    /// Pretty-printed with sorted keys, so a git diff of a canvas reads.
    func encode() throws -> Data {
        var o = extra
        o["nodes"] = .array(nodes.map { .object($0.json) })
        o["edges"] = .array(edges.map { .object($0.json) })
        var data = try JSONSerialization.data(withJSONObject: JSONValue.object(o).any,
                                              options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        return data
    }

    /// 16 hex characters, as the spec suggests.
    static func newID() -> String {
        let alphabet = Array("0123456789abcdef")
        return String((0..<16).map { _ in alphabet.randomElement()! })
    }

    func node(_ id: String) -> CanvasNode? { nodes.first { $0.id == id } }

    func index(of id: String) -> Int? { nodes.firstIndex { $0.id == id } }

    mutating func update(_ node: CanvasNode) {
        if let i = index(of: node.id) { nodes[i] = node }
    }

    /// The union of every node's frame; null when the canvas is empty.
    var bounds: CGRect {
        nodes.reduce(CGRect.null) { $0.union($1.frame) }
    }
}
