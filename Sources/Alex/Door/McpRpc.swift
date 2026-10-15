import Foundation

/// The door's brain: JSON-RPC in, JSON-RPC out, no networking in it —
/// `McpServer` owns the socket, this owns the meaning, and the test suite
/// calls straight in here. The rules (PLAN.md, D6 and D7): every tool is a
/// thin wrapper over the file format, so Claude could write the files
/// itself; the door adds what files cannot — knowing what the user is
/// looking at, placing without layout maths, and pointing. It reads, adds,
/// updates and focuses. There is no delete: not gated, not hidden, absent.
@MainActor
final class McpRpc {
    static let knownVersions = ["2024-11-05", "2025-03-26", "2025-06-18"]
    static let version = "0.1.0"

    let vault: Vault
    let canvas: CanvasStore
    /// Bring the app forward after a `focus`; set by the app, empty in tests.
    var activate: () -> Void = {}

    init(vault: Vault, canvas: CanvasStore) {
        self.vault = vault
        self.canvas = canvas
    }

    // MARK: - Entry

    /// One HTTP body in, one out. `nil` means the message was a notification
    /// and there is nothing to say, which the transport turns into 202.
    func respond(to body: Data) -> Data? {
        guard let parsed = try? JSONSerialization.jsonObject(with: body) else {
            return Self.encode(Self.errorReply(id: NSNull(), code: -32700, message: "Parse error"))
        }
        if let one = parsed as? [String: Any] {
            return handle(one).map(Self.encode)
        }
        if let many = parsed as? [[String: Any]] {
            let replies = many.compactMap { handle($0) }
            return replies.isEmpty ? nil : Self.encode(replies)
        }
        return Self.encode(Self.errorReply(id: NSNull(), code: -32600, message: "Invalid request"))
    }

    func handle(_ message: [String: Any]) -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return Self.reply(id: id, result: [
                "protocolVersion": Self.knownVersions.contains(asked) ? asked : "2025-03-26",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "Alex", "version": Self.version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return Self.reply(id: id, result: [:])
        case "tools/list":
            return Self.reply(id: id, result: ["tools": Self.toolDefinitions])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            guard let tool = tools[name] else {
                return Self.errorReply(id: id, code: -32602, message: "Unknown tool: \(name)")
            }
            switch tool(args) {
            case .success(let payload):
                return Self.reply(id: id, result: [
                    "content": [["type": "text", "text": Self.prettyJSON(payload)]],
                    "isError": false,
                ])
            case .failure(let message):
                return Self.reply(id: id, result: [
                    "content": [["type": "text", "text": message]],
                    "isError": true,
                ])
            }
        default:
            return Self.errorReply(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// What the connected agent is told at initialize.
    static let instructions = """
        Alex shows the user's vault (a folder of Markdown, images and .canvas \
        files) as a spatial canvas. Home, the vault's own canvas, shows every \
        folder as a section holding its files' cards, and a file that appears \
        joins its folder's section by itself. Files are the truth and this \
        door is a convenience: you may also write files directly. Call \
        get_context first to see which canvas is open and what is selected. \
        Write artifacts into the vault with write_artifact (its card lands in \
        its folder's section on Home), \
        add notes, links and stickies with add_card, connect cards with \
        connect, then call focus so the user sees what you made. Paths are \
        relative to the vault. Never overwrite without overwrite: true. There \
        is no delete; the user removes things in the app.
        """

    // MARK: - Tools

    enum Outcome {
        case success(Any)
        case failure(String)
    }

    private typealias Tool = (_ args: [String: Any]) -> Outcome

    private lazy var tools: [String: Tool] = [
        "get_context": { [unowned self] in self.getContext($0) },
        "read_canvas": { [unowned self] in self.readCanvas($0) },
        "add_card": { [unowned self] in self.addCard($0) },
        "write_artifact": { [unowned self] in self.writeArtifact($0) },
        "connect": { [unowned self] in self.connect($0) },
        "update_card": { [unowned self] in self.updateCard($0) },
        "focus": { [unowned self] in self.focus($0) },
        "list_files": { [unowned self] in self.listFiles($0) },
    ]

    static let toolDefinitions: [[String: Any]] = [
        [
            "name": "get_context",
            "description": "Where the user is: the vault root, the open directory and canvas, "
                + "the selected cards with their file paths or text, the viewport, and the "
                + "files in the open directory not yet placed. Call this first.",
            "inputSchema": ["type": "object", "properties": [String: Any]()] as [String: Any],
        ],
        [
            "name": "read_canvas",
            "description": "A canvas as JSON Canvas 1.0: nodes and edges. Pass a .canvas path; a "
                + "directory means Home, where each folder is a group with its path under x-folder. "
                + "Omit for the open one.",
            "inputSchema": ["type": "object", "properties": [
                "path": ["type": "string", "description": "Vault-relative .canvas file, or a directory for Home."],
            ]] as [String: Any],
        ],
        [
            "name": "add_card",
            "description": "Add a node to a canvas: type text (a sticky note), file (a vault file; "
                + "a folder is already a section on Home), or link (a URL). Without x and y a file "
                + "on Home goes into its folder's section; anything else is placed beside `near` "
                + "(a node id), else beside the selection, else below everything.",
            "inputSchema": ["type": "object", "properties": [
                "canvas": ["type": "string", "description": "Vault-relative .canvas file; omit for the open canvas."],
                "type": ["type": "string", "enum": ["text", "file", "link"]],
                "text": ["type": "string", "description": "For text: the note, Markdown."],
                "file": ["type": "string", "description": "For file: a vault-relative path."],
                "url": ["type": "string", "description": "For link: the URL."],
                "near": ["type": "string", "description": "A node id to place beside."],
                "color": ["type": "string", "description": "JSON Canvas colour: \"1\"–\"6\" or #rrggbb."],
                "x": ["type": "number"], "y": ["type": "number"],
                "width": ["type": "number"], "height": ["type": "number"],
            ], "required": ["type"]] as [String: Any],
        ],
        [
            "name": "write_artifact",
            "description": "Write a file into the vault (text via `content`, binary via `base64`), "
                + "creating directories as needed, and place it as a card in its folder's section "
                + "on Home (or on `canvas`). Refuses to overwrite unless overwrite is true. Use this "
                + "for plots, notes, data and generated HTML.",
            "inputSchema": ["type": "object", "properties": [
                "path": ["type": "string", "description": "Vault-relative path, e.g. artifacts/C3.1/step_response.png"],
                "content": ["type": "string", "description": "Text content."],
                "base64": ["type": "string", "description": "Binary content, base64."],
                "canvas": ["type": "string", "description": "Canvas to place the card on; default is Home."],
                "near": ["type": "string", "description": "A node id to place beside."],
                "place": ["type": "boolean", "description": "Place a card at all; default true."],
                "overwrite": ["type": "boolean"],
            ], "required": ["path"]] as [String: Any],
        ],
        [
            "name": "connect",
            "description": "Draw an edge between two nodes on a canvas, with an optional label.",
            "inputSchema": ["type": "object", "properties": [
                "canvas": ["type": "string"],
                "from": ["type": "string", "description": "Node id."],
                "to": ["type": "string", "description": "Node id."],
                "label": ["type": "string"],
                "fromSide": ["type": "string", "enum": ["top", "right", "bottom", "left"]],
                "toSide": ["type": "string", "enum": ["top", "right", "bottom", "left"]],
            ], "required": ["from", "to"]] as [String: Any],
        ],
        [
            "name": "update_card",
            "description": "Change a node's text, colour, label, position or size.",
            "inputSchema": ["type": "object", "properties": [
                "canvas": ["type": "string"],
                "id": ["type": "string"],
                "text": ["type": "string"], "color": ["type": "string"], "label": ["type": "string"],
                "x": ["type": "number"], "y": ["type": "number"],
                "width": ["type": "number"], "height": ["type": "number"],
            ], "required": ["id"]] as [String: Any],
        ],
        [
            "name": "focus",
            "description": "Open a canvas in the app and pan to a node so the user sees it. "
                + "Pass a node id, or a file path to find its card.",
            "inputSchema": ["type": "object", "properties": [
                "canvas": ["type": "string"],
                "id": ["type": "string"],
                "file": ["type": "string"],
            ]] as [String: Any],
        ],
        [
            "name": "list_files",
            "description": "Vault-relative paths under a directory, optionally filtered by a glob "
                + "such as artifacts/**/*.png. Hidden files and caches are left out.",
            "inputSchema": ["type": "object", "properties": [
                "dir": ["type": "string"],
                "glob": ["type": "string"],
            ]] as [String: Any],
        ],
    ]

    // MARK: - Canvas plumbing

    enum DoorError: Error, CustomStringConvertible {
        case noVault
        case badPath(String)
        case noNode(String)
        case exists(String)
        case missing(String)
        case folder(String)

        var description: String {
            switch self {
            case .noVault: return "No vault is open in Alex."
            case .badPath(let p): return "Not a canvas or directory in the vault: \(p)"
            case .folder(let p): return "\(p) is a folder, and a folder is a section on Home already. Place its files instead."
            case .noNode(let id): return "No node \(id) on that canvas."
            case .exists(let p): return "\(p) exists; pass overwrite: true to replace it."
            case .missing(let p): return "Missing: \(p)"
            }
        }
    }

    var home: String { CanvasStore.homeCanvas(vault: vault) }

    /// The canvas a tool means: a `.canvas` path, a directory (Home, where
    /// a folder is a section, revision 20), or nothing (the open one, else
    /// Home).
    func canvasPath(from argument: String?) throws -> String {
        guard vault.root != nil else { throw DoorError.noVault }
        guard let argument, !argument.isEmpty else {
            return canvas.isOpen ? canvas.canvasPath : home
        }
        let path = try VaultPath.normalise(argument)
        if path.hasSuffix(".canvas") { return path }
        if path.isEmpty || vault.isDirectory(path) { return home }
        throw DoorError.badPath(argument)
    }

    /// Load a canvas. Home is made on first touch, the way the app makes
    /// it on first visit; any other canvas that is not there is empty.
    func loadCanvas(_ path: String) throws -> CanvasDocument {
        if vault.exists(path), let url = vault.url(for: path) {
            return try CanvasDocument.decode(try Data(contentsOf: url))
        }
        guard path == home else { return CanvasDocument() }
        var doc = CanvasDocument()
        Folders.reconcile(&doc, tree: vault.tree, home: home)
        try vault.write(try doc.encode(), to: path)
        return doc
    }

    /// A file's card on Home, in its folder's section: taken off the
    /// hidden list if it was on it, and placed the way the app places what
    /// appears (with whatever else is waiting).
    private func placeOnHome(_ file: String, in doc: inout CanvasDocument) -> CanvasNode? {
        Folders.unhide(file, in: &doc)
        Folders.reconcile(&doc, tree: vault.tree, home: home)
        return doc.nodes.first { $0.kind == .file && $0.file == file }
    }

    func saveCanvas(_ doc: CanvasDocument, to path: String) throws {
        try vault.write(try doc.encode(), to: path)
        canvas.noticeDoorWrite(to: path)
    }

    private func str(_ args: [String: Any], _ key: String) -> String? {
        guard let s = args[key] as? String, !s.isEmpty else { return nil }
        return s
    }

    private func num(_ args: [String: Any], _ key: String) -> Double? {
        (args[key] as? NSNumber)?.doubleValue
    }

    private func flag(_ args: [String: Any], _ key: String, default value: Bool) -> Bool {
        (args[key] as? Bool) ?? value
    }

    private func nodeSummary(_ node: CanvasNode) -> [String: Any] {
        var o: [String: Any] = [
            "id": node.id, "type": node.kind.typeName,
            "x": node.x, "y": node.y, "width": node.width, "height": node.height,
        ]
        if let file = node.file { o["file"] = file }
        if let text = node.text { o["text"] = String(text.prefix(400)) }
        if let url = node.url { o["url"] = url }
        if let label = node.label { o["label"] = label }
        if let color = node.color { o["color"] = color }
        return o
    }

    private func placement(in doc: CanvasDocument, path: String, args: [String: Any],
                           size: CGSize) -> CGRect {
        if let x = num(args, "x"), let y = num(args, "y") {
            return CGRect(x: x, y: y, width: num(args, "width") ?? size.width,
                          height: num(args, "height") ?? size.height)
        }
        var near: CGRect?
        if let id = str(args, "near"), let n = doc.node(id) { near = n.frame }
        else if path == canvas.canvasPath, let selected = canvas.selectedNode { near = selected.frame }
        let finalSize = CGSize(width: num(args, "width") ?? size.width, height: num(args, "height") ?? size.height)
        return CGRect(origin: Placement.freeSlot(for: finalSize, in: doc, near: near), size: finalSize)
    }

    // MARK: - The eight

    private func getContext(_ args: [String: Any]) -> Outcome {
        guard let root = vault.root else { return .failure(DoorError.noVault.description) }
        let selected = canvas.document.nodes.filter { canvas.selection.contains($0.id) }
        return .success([
            "vault": root.path,
            "directory": canvas.directory,
            "canvas": canvas.isOpen ? canvas.canvasPath : NSNull(),
            "nodeCount": canvas.document.nodes.count,
            "selection": selected.map(nodeSummary),
            "viewport": ["scale": canvas.viewport.scale,
                         "x": canvas.viewport.offset.x, "y": canvas.viewport.offset.y],
            "unplaced": canvas.unplaced.map(\.path),
        ] as [String: Any])
    }

    private func readCanvas(_ args: [String: Any]) -> Outcome {
        do {
            let path = try canvasPath(from: str(args, "path"))
            let doc = try loadCanvas(path)
            var o = doc.extra
            o["nodes"] = .array(doc.nodes.map { .object($0.json) })
            o["edges"] = .array(doc.edges.map { .object($0.json) })
            return .success(["path": path, "canvas": JSONValue.object(o).any] as [String: Any])
        } catch {
            return .failure("\(error)")
        }
    }

    private func addCard(_ args: [String: Any]) -> Outcome {
        guard let type = str(args, "type") else { return .failure("type is required: text, file or link") }
        do {
            let path = try canvasPath(from: str(args, "canvas"))
            var doc = try loadCanvas(path)
            let node: CanvasNode
            switch type {
            case "text":
                let frame = placement(in: doc, path: path, args: args, size: Placement.textSize)
                node = CanvasNode(kind: .text, frame: frame, text: str(args, "text") ?? "",
                                  color: str(args, "color") ?? "3")
            case "file":
                guard let file = str(args, "file") else { return .failure("file is required for a file card") }
                let rel = try VaultPath.normalise(file)
                guard vault.exists(rel) else { return .failure(DoorError.missing(rel).description) }
                guard !vault.isDirectory(rel) else { return .failure(DoorError.folder(rel).description) }
                if path == home, num(args, "x") == nil || num(args, "y") == nil,
                   !doc.nodes.contains(where: { $0.file == rel }), var placed = placeOnHome(rel, in: &doc) {
                    if let color = str(args, "color") { placed.color = color; doc.update(placed) }
                    try saveCanvas(doc, to: path)
                    return .success(["canvas": path, "node": nodeSummary(placed)] as [String: Any])
                }
                let size = Placement.size(forFile: rel, isDirectory: false)
                let frame = placement(in: doc, path: path, args: args, size: size)
                node = CanvasNode(kind: .file, frame: frame, file: rel, color: str(args, "color"))
            case "link":
                guard let url = str(args, "url") else { return .failure("url is required for a link card") }
                let frame = placement(in: doc, path: path, args: args,
                                      size: LinkKind.classify(url).cardSize)
                node = CanvasNode(kind: .link, frame: frame, url: url, color: str(args, "color"))
            default:
                return .failure("type must be text, file or link")
            }
            doc.nodes.append(node)
            try saveCanvas(doc, to: path)
            return .success(["canvas": path, "node": nodeSummary(node)] as [String: Any])
        } catch {
            return .failure("\(error)")
        }
    }

    private func writeArtifact(_ args: [String: Any]) -> Outcome {
        guard let rawPath = str(args, "path") else { return .failure("path is required") }
        let data: Data
        if let content = args["content"] as? String {
            data = Data(content.utf8)
        } else if let b64 = args["base64"] as? String, let decoded = Data(base64Encoded: b64) {
            data = decoded
        } else {
            return .failure("content (text) or base64 (binary) is required")
        }
        do {
            let path = try VaultPath.normalise(rawPath)
            guard !path.isEmpty, !vault.isDirectory(path) else { return .failure(DoorError.badPath(rawPath).description) }
            if vault.exists(path), !flag(args, "overwrite", default: false) {
                return .failure(DoorError.exists(path).description)
            }
            try vault.write(data, to: path)
            var result: [String: Any] = ["path": path, "bytes": data.count]
            if flag(args, "place", default: true) {
                let canvasFile = try str(args, "canvas").map { try canvasPath(from: $0) } ?? home
                var doc = try loadCanvas(canvasFile)
                if let existing = doc.nodes.first(where: { $0.file == path }) {
                    result["canvas"] = canvasFile
                    result["node"] = nodeSummary(existing)
                } else if canvasFile == home, num(args, "x") == nil || num(args, "y") == nil,
                          let node = placeOnHome(path, in: &doc) {
                    try saveCanvas(doc, to: canvasFile)
                    result["canvas"] = canvasFile
                    result["node"] = nodeSummary(node)
                } else {
                    let frame = placement(in: doc, path: canvasFile, args: args, size: Placement.cardSize)
                    let node = CanvasNode(kind: .file, frame: frame, file: path)
                    doc.nodes.append(node)
                    try saveCanvas(doc, to: canvasFile)
                    result["canvas"] = canvasFile
                    result["node"] = nodeSummary(node)
                }
            }
            return .success(result)
        } catch {
            return .failure("\(error)")
        }
    }

    private func connect(_ args: [String: Any]) -> Outcome {
        guard let from = str(args, "from"), let to = str(args, "to") else {
            return .failure("from and to node ids are required")
        }
        do {
            let path = try canvasPath(from: str(args, "canvas"))
            var doc = try loadCanvas(path)
            guard doc.node(from) != nil else { return .failure(DoorError.noNode(from).description) }
            guard doc.node(to) != nil else { return .failure(DoorError.noNode(to).description) }
            var edge = CanvasEdge(from: from, to: to, label: str(args, "label"))
            edge.fromSide = str(args, "fromSide").flatMap(CanvasSide.init(rawValue:))
            edge.toSide = str(args, "toSide").flatMap(CanvasSide.init(rawValue:))
            doc.edges.append(edge)
            try saveCanvas(doc, to: path)
            return .success(["canvas": path, "edge": edge.json.mapValues(\.any)] as [String: Any])
        } catch {
            return .failure("\(error)")
        }
    }

    private func updateCard(_ args: [String: Any]) -> Outcome {
        guard let id = str(args, "id") else { return .failure("id is required") }
        do {
            let path = try canvasPath(from: str(args, "canvas"))
            var doc = try loadCanvas(path)
            guard var node = doc.node(id) else { return .failure(DoorError.noNode(id).description) }
            if let text = args["text"] as? String { node.text = text }
            if let color = str(args, "color") { node.color = color }
            if let label = args["label"] as? String { node.label = label }
            if let x = num(args, "x") { node.x = x }
            if let y = num(args, "y") { node.y = y }
            if let w = num(args, "width") { node.width = max(80, w) }
            if let h = num(args, "height") { node.height = max(60, h) }
            doc.update(node)
            try saveCanvas(doc, to: path)
            return .success(["canvas": path, "node": nodeSummary(node)] as [String: Any])
        } catch {
            return .failure("\(error)")
        }
    }

    private func focus(_ args: [String: Any]) -> Outcome {
        do {
            let path = try canvasPath(from: str(args, "canvas"))
            if path != canvas.canvasPath || !canvas.isOpen {
                if path == home { canvas.openHome() } else { canvas.openCanvas(at: path) }
            }
            var target: CanvasNode?
            if let id = str(args, "id") { target = canvas.document.node(id) }
            else if let file = str(args, "file") { target = canvas.node(forFile: try VaultPath.normalise(file)) }
            if let target {
                canvas.select(target.id)
                canvas.focusRequest = target.id
            } else if str(args, "id") != nil || str(args, "file") != nil {
                return .failure("That node is not on \(path).")
            }
            activate()
            return .success(["canvas": path, "focused": target.map(nodeSummary) ?? NSNull()] as [String: Any])
        } catch {
            return .failure("\(error)")
        }
    }

    private func listFiles(_ args: [String: Any]) -> Outcome {
        guard let root = vault.root else { return .failure(DoorError.noVault.description) }
        do {
            let dir = try VaultPath.normalise(str(args, "dir") ?? "")
            let tree = try VaultNode.scan(dir, root: root, depth: 6)
            var paths = tree.flatMap(\.flattened).map(\.path)
            if let pattern = str(args, "glob") {
                paths = paths.filter { VaultPath.matches($0, glob: pattern) }
            }
            return .success(["dir": dir, "files": paths] as [String: Any])
        } catch {
            return .failure("\(error)")
        }
    }

    // MARK: - JSON-RPC plumbing

    static func reply(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func errorReply(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func encode(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    static func prettyJSON(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.sortedKeys, .prettyPrinted])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
