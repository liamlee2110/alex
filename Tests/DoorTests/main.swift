import Foundation

// Line-buffered, so a trap mid-suite still shows every line before it.
setvbuf(stdout, nil, _IOLBF, 0)

var failures = 0
func check(_ ok: Bool, _ label: String, _ detail: String = "") {
    if ok { print("  ok    \(label)") }
    else { failures += 1; print("  FAIL  \(label) \(detail)") }
}

let fm = FileManager.default
let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("alex-door-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }

@MainActor
func doorTests() {
    let root = scratch.appendingPathComponent("vault")
    try! fm.createDirectory(at: root.appendingPathComponent("artifacts"), withIntermediateDirectories: true)
    try! "# Alpha\n".write(to: root.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
    let defaults = UserDefaults(suiteName: "alex-door-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let canvas = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    let rpc = McpRpc(vault: vault, canvas: canvas)
    var activated = 0
    rpc.activate = { activated += 1 }

    func call(_ method: String, _ params: [String: Any] = [:], id: Any = 1) -> [String: Any]? {
        var message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        message["id"] = id
        let data = rpc.respond(to: try! JSONSerialization.data(withJSONObject: message))
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
    func tool(_ name: String, _ args: [String: Any] = [:]) -> (ok: Bool, text: String, payload: [String: Any]) {
        let reply = call("tools/call", ["name": name, "arguments": args])
        let result = reply?["result"] as? [String: Any] ?? [:]
        let content = (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        let isError = result["isError"] as? Bool ?? true
        let payload = (try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]) ?? [:]
        return (!isError, content, payload)
    }

    print("\n— Protocol —")
    let hello = call("initialize", ["protocolVersion": "2025-06-18"])
    let helloResult = hello?["result"] as? [String: Any]
    check(helloResult?["protocolVersion"] as? String == "2025-06-18", "known version is echoed")
    check((helloResult?["serverInfo"] as? [String: Any])?["name"] as? String == "Alex", "server name")
    check((helloResult?["instructions"] as? String)?.contains("no delete") == true, "instructions carry the rule")
    let unknownVersion = call("initialize", ["protocolVersion": "1999-01-01"])
    check((unknownVersion?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-03-26", "unknown version gets the middle one")
    let notification = rpc.respond(to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
    check(notification == nil, "a notification gets silence")
    let bad = rpc.respond(to: Data("not json".utf8))
    check(bad.flatMap { String(data: $0, encoding: .utf8) }?.contains("-32700") == true, "parse error is -32700")
    check((call("nope")?["error"] as? [String: Any])?["code"] as? Int == -32601, "unknown method is -32601")
    check(call("ping")?["result"] != nil, "ping")
    let names = ((call("tools/list")?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?
        .compactMap { $0["name"] as? String } ?? []
    check(names.sorted() == ["add_card", "connect", "focus", "get_context", "list_files", "read_canvas", "update_card", "write_artifact"],
          "the eight tools, and only those", "got \(names)")
    check(!names.contains("delete_card") && !names.contains("remove_card"), "there is no delete")
    let batchData = rpc.respond(to: Data(#"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"x"}]"#.utf8))
    let batch = batchData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
    check(batch?.count == 1, "a batch answers each request and skips notifications")

    print("\n— get_context —")
    let ctx = tool("get_context")
    check(ctx.ok, "get_context succeeds", ctx.text)
    check(ctx.payload["canvas"] as? String == "vault.canvas", "reports the open canvas", "got \(String(describing: ctx.payload["canvas"]))")
    check((ctx.payload["selection"] as? [Any])?.isEmpty == true, "nothing selected yet")
    let alphaNode = canvas.node(forFile: "alpha.md")!
    canvas.select(alphaNode.id)
    let ctx2 = tool("get_context")
    let selected = (ctx2.payload["selection"] as? [[String: Any]])?.first
    check(selected?["file"] as? String == "alpha.md", "selection carries the file path")

    print("\n— write_artifact —")
    let plot = tool("write_artifact", ["path": "artifacts/C3.1/notes.md", "content": "# Step response\n\nrise time 0.4 s\n"])
    check(plot.ok, "writes a text artifact", plot.text)
    check(fm.fileExists(atPath: root.appendingPathComponent("artifacts/C3.1/notes.md").path), "file exists, directory created")
    check(plot.payload["canvas"] as? String == "vault.canvas", "placed on Home", "got \(String(describing: plot.payload["canvas"]))")
    let plotID = (plot.payload["node"] as? [String: Any])?["id"] as? String ?? ""
    let c31 = Folders.section(for: "artifacts/C3.1", in: canvas.document)
    check(c31 != nil && canvas.document.node(plotID).map { c31!.frame.contains($0.frame) } == true,
          "inside its folder's section, made for it")
    check(!fm.fileExists(atPath: root.appendingPathComponent("artifacts/C3.1/C3.1.canvas").path), "no folder canvas is made")
    let again = tool("write_artifact", ["path": "artifacts/C3.1/notes.md", "content": "x"])
    check(!again.ok && again.text.contains("overwrite"), "refuses to overwrite without the flag")
    let forced = tool("write_artifact", ["path": "artifacts/C3.1/notes.md", "content": "# Replaced\n", "overwrite": true])
    check(forced.ok && (try? String(contentsOf: root.appendingPathComponent("artifacts/C3.1/notes.md"), encoding: .utf8)) == "# Replaced\n", "overwrites with the flag")
    check((forced.payload["node"] as? [String: Any])?["id"] as? String == (plot.payload["node"] as? [String: Any])?["id"] as? String, "rewriting keeps the existing card")
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let binary = tool("write_artifact", ["path": "artifacts/C3.1/plot.png", "base64": png.base64EncodedString(), "canvas": "vault.canvas"])
    check(binary.ok, "writes binary from base64", binary.text)
    check((try? Data(contentsOf: root.appendingPathComponent("artifacts/C3.1/plot.png"))) == png, "bytes intact")
    check(binary.payload["canvas"] as? String == "vault.canvas", "placed on the canvas asked for")
    check(canvas.node(forFile: "artifacts/C3.1/plot.png") != nil, "the open canvas picked up the door's card")
    let escape = tool("write_artifact", ["path": "../outside.md", "content": "x"])
    check(!escape.ok, "a path that leaves the vault is refused")
    check(!fm.fileExists(atPath: scratch.appendingPathComponent("outside.md").path), "and nothing was written")
    let silent = tool("write_artifact", ["path": "quiet.md", "content": "x", "place": false])
    check(silent.ok && silent.payload["node"] == nil, "place: false writes without a card")

    print("\n— add_card, connect, update_card —")
    let note = tool("add_card", ["type": "text", "text": "Remember this", "near": alphaNode.id])
    check(note.ok, "adds a sticky", note.text)
    let noteID = (note.payload["node"] as? [String: Any])?["id"] as? String ?? ""
    let noteNode = canvas.document.node(noteID)
    check(noteNode?.text == "Remember this" && noteNode?.color == "3", "sticky text and default colour on the open canvas")
    check(noteNode.map { !$0.frame.intersects(alphaNode.frame) } == true, "placed beside, not on top")
    let link = tool("add_card", ["type": "link", "url": "https://example.com", "canvas": "artifacts/C3.1"])
    check(link.ok && link.payload["canvas"] as? String == "vault.canvas", "a directory names Home")
    let ghost = tool("add_card", ["type": "file", "file": "nope.md"])
    check(!ghost.ok, "a file card for a missing file is refused")
    let folderCard = tool("add_card", ["type": "file", "file": "artifacts"])
    check(!folderCard.ok && folderCard.text.contains("section"), "a folder card is refused: a folder is a section")
    let quiet = tool("add_card", ["type": "file", "file": "quiet.md"])
    check(quiet.ok && canvas.node(forFile: "quiet.md") != nil, "a file card on Home is placed without coordinates")
    let edge = tool("connect", ["from": alphaNode.id, "to": noteID, "label": "see"])
    check(edge.ok && canvas.document.edges.first?.label == "see", "edge connected on the open canvas")
    let badEdge = tool("connect", ["from": alphaNode.id, "to": "zzz"])
    check(!badEdge.ok, "an edge to a missing node is refused")
    let moved = tool("update_card", ["id": noteID, "x": 900, "y": 900, "color": "5", "text": "Changed"])
    check(moved.ok && canvas.document.node(noteID)?.x == 900 && canvas.document.node(noteID)?.color == "5", "update applies")
    let read = tool("read_canvas")
    check(read.ok && ((read.payload["canvas"] as? [String: Any])?["nodes"] as? [Any])?.count == canvas.document.nodes.count, "read_canvas matches the store")

    print("\n— focus, list_files —")
    let focused = tool("focus", ["canvas": "artifacts/C3.1", "file": "artifacts/C3.1/notes.md"])
    check(focused.ok, "focus finds a file through its folder", focused.text)
    check(canvas.isHome && canvas.focusRequest == canvas.node(forFile: "artifacts/C3.1/notes.md")?.id,
          "the store stays on Home and asks to pan")
    check(activated == 1, "the app was brought forward")
    let missingFocus = tool("focus", ["id": "nope"])
    check(!missingFocus.ok, "focusing a missing node says so")
    let files = tool("list_files", ["glob": "**/*.md"])
    let listed = files.payload["files"] as? [String] ?? []
    check(listed.contains("alpha.md") && listed.contains("artifacts/C3.1/notes.md") && !listed.contains("quiet.canvas"), "glob lists notes at any depth", "got \(listed)")
    let onlyArtifacts = tool("list_files", ["dir": "artifacts"])
    check((onlyArtifacts.payload["files"] as? [String])?.allSatisfy { $0.hasPrefix("artifacts/") } == true, "dir narrows the listing")
    check(VaultPath.matches("artifacts/C3.1/plot.png", glob: "artifacts/**/*.png") && !VaultPath.matches("plot.png", glob: "artifacts/**/*.png"), "glob matching")
}

MainActor.assumeIsolated { doorTests() }

print("")
if failures == 0 { print("✓ door suite passed") } else { print("✗ \(failures) failure(s)") }
exit(failures == 0 ? 0 : 1)
