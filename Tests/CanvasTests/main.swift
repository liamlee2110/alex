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
    .appendingPathComponent("alex-canvas-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }

print("\n— JSONValue —")
let sample = """
{"nodes":[{"id":"a1","type":"text","x":10,"y":20,"width":100,"height":50,"text":"hi","x-hue":95,"color":"3"},
          {"id":"b2","type":"file","x":0,"y":0,"width":320,"height":200,"file":"note.md"},
          {"id":"c3","type":"weird","x":1,"y":2,"width":3,"height":4,"mystery":{"deep":[1,true,null]}},
          {"type":"text","x":0,"y":0,"width":1,"height":1,"text":"no id"}],
 "edges":[{"id":"e1","fromNode":"a1","toNode":"b2","fromSide":"right","label":"leads to"}],
 "x-app":"someone else"}
"""
let doc = try! CanvasDocument.decode(Data(sample.utf8))
check(doc.nodes.count == 3, "a node without an id is skipped, everything else kept", "got \(doc.nodes.count)")
check(doc.nodes[0].hue == 95, "x-hue reads through the extra keys")
check(doc.nodes[2].kind == .other("weird"), "an unknown type stays opaque")
check(doc.edges.first?.fromSide == .right && doc.edges.first?.label == "leads to", "edge fields decode")
check(doc.extra["x-app"]?.string == "someone else", "top-level unknown keys are kept")
let encoded = try! doc.encode()
let again = try! CanvasDocument.decode(encoded)
check(again == doc, "round trip is lossless")
let text = String(decoding: encoded, as: UTF8.self)
check(text.contains("\"mystery\""), "unknown nested keys are written back")
check(text.contains("\"x\" : 10") && !text.contains("10.0"), "whole numbers stay integers")
check(text.hasSuffix("\n"), "file ends with a newline")

print("\n— Frontmatter —")
let fmText = """
---
id: C0.1
name: Orientation primers (3Blue1Brown LA + Calculus)
phase: 0
target: knows
level: none              # none | knows | knows how | shows how
prerequisites: [C0.0, "C0.2", {{prerequisites}}]
traces_to: [D1]
title: "Block 0, session 1 — What is a vector?"
minutes: 45
hours: 1.5
answered: false
next_review:
---

# C0.1 Orientation primers
Body here.
"""
let fmr = Frontmatter.parse(fmText)
check(fmr["id"]?.display == "C0.1", "plain string")
check(fmr["level"]?.display == "none", "trailing comment stripped", "got \(String(describing: fmr["level"]))")
check(fmr["prerequisites"] == .list(["C0.0", "C0.2"]), "list with quotes and placeholder", "got \(String(describing: fmr["prerequisites"]))")
check(fmr["title"]?.display == "Block 0, session 1 — What is a vector?", "quoted string keeps everything")
check(fmr["minutes"] == .int(45) && fmr["hours"] == .double(1.5) && fmr["answered"] == .bool(false), "ints, floats, booleans")
check(fmr["next_review"]?.isEmpty == true, "empty value is empty")
check(fmr.body.hasPrefix("# C0.1"), "body starts after the closing rule", "got \(fmr.body.prefix(12))")
check(Frontmatter.parse("no frontmatter").fields.isEmpty, "no frontmatter means no fields")

@MainActor
func storeTests() {
    print("\n— CanvasStore on a scratch vault —")
    let root = scratch.appendingPathComponent("vault")
    try! fm.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
    try! "# Alpha\n\nfirst".write(to: root.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
    try! "# Inner\n".write(to: root.appendingPathComponent("notes/inner.md"), atomically: true, encoding: .utf8)
    let defaults = UserDefaults(suiteName: "alex-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    // The store opens its directory on the next main-actor turn; pump the loop.
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    check(store.isOpen, "store opened the vault root")
    check(fm.fileExists(atPath: root.appendingPathComponent("vault.canvas").path), "first visit wrote vault.canvas")
    check(store.document.nodes.count == 2, "auto-layout placed the folder and the note", "got \(store.document.nodes.count)")
    check(store.unplaced.isEmpty, "nothing unplaced after auto-layout")
    let folder = store.document.nodes.first { $0.file == "notes" }!
    let alpha = store.document.nodes.first { $0.file == "alpha.md" }!
    check(store.isDirectoryNode(folder) && !store.isDirectoryNode(alpha), "folder and card told apart")
    check(store.peeks(for: "notes").count == 1, "peeks count the directory's files")

    let undo = UndoManager()
    store.undoManager = undo
    // UndoManager groups by run-loop pass; in the app each gesture is its own
    // pass. Here a tick closes the group by hand.
    func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    let before = alpha.frame.origin
    store.move([alpha.id], by: CGSize(width: 100, height: 50))
    tick()
    check(store.document.node(alpha.id)?.x == before.x + 100, "move applies")
    let onDisk = try! CanvasDocument.decode(Data(contentsOf: root.appendingPathComponent("vault.canvas")))
    check(onDisk.node(alpha.id)?.x == before.x + 100, "move is on disk before anything else")
    undo.undo()
    tick()
    check(store.document.node(alpha.id)?.x == before.x, "undo restores the position")
    undo.redo()
    tick()
    check(store.document.node(alpha.id)?.x == before.x + 100, "redo re-applies it")

    let sticky = store.addSticky(at: CGPoint(x: 1000, y: 1000))
    tick()
    check(store.document.node(sticky.id)?.kind == .text && store.selection == [sticky.id], "sticky added and selected")
    store.setText(sticky.id, "hello")
    tick()
    check(store.document.node(sticky.id)?.text == "hello", "sticky text set")
    let edge = store.connect(alpha.id, sticky.id, fromSide: .right)
    tick()
    check(store.document.edges.contains { $0.id == edge.id && $0.fromSide == .right }, "edge connected")
    store.remove([sticky.id])
    tick()
    check(store.document.node(sticky.id) == nil && store.document.edges.isEmpty, "removing a node removes its edges")
    undo.undo()
    tick()
    check(store.document.node(sticky.id) != nil && store.document.edges.count == 1, "undo brings node and edge back")

    store.remove([alpha.id])
    check(store.unplaced.map(\.path) == ["alpha.md"], "a removed file lands in the tray", "got \(store.unplaced.map(\.path))")
    let placed = store.place("alpha.md", near: sticky.id)
    check(!placed.frame.intersects(store.document.node(sticky.id)!.frame), "placing beside a node finds a free slot")
    check(store.unplaced.isEmpty, "placed again, tray empty")

    // `placed` is a new node: removing and placing again is not a move.
    store.selection = [placed.id, sticky.id]
    store.groupSelection()
    let group = store.document.nodes.first { $0.kind == .group }!
    check(store.document.nodes.first?.id == group.id, "group goes first, so it draws behind")
    check(group.frame.contains(store.document.node(sticky.id)!.frame), "group encloses the selection")
    check(store.nodeIDs(inside: group.frame) == [placed.id, sticky.id], "group knows what it holds",
          "got \(store.nodeIDs(inside: group.frame))")
    check(store.hitTest(store.document.node(sticky.id)!.center)?.id == sticky.id, "hit test finds the card over the group")

    store.newNote()
    check(fm.fileExists(atPath: root.appendingPathComponent("Untitled.md").path), "new note file created")
    check(store.node(forFile: "Untitled.md") != nil, "new note placed")
    store.newNote()
    check(fm.fileExists(atPath: root.appendingPathComponent("Untitled 2.md").path), "second new note gets a new name")

    let outside = scratch.appendingPathComponent("outside.md")
    try! "# Outside\n".write(to: outside, atomically: true, encoding: .utf8)
    store.importFiles([outside, root.appendingPathComponent("notes/inner.md")], at: CGPoint(x: 50, y: 50))
    check(fm.fileExists(atPath: root.appendingPathComponent("outside.md").path), "a foreign drop is copied into the open directory")
    check(store.node(forFile: "outside.md") != nil, "and placed where it landed")
    check(store.node(forFile: "notes/inner.md") != nil, "a vault file from another directory is placed by reference")

    store.openDirectory("notes")
    check(store.directory == "notes" && store.canvasPath == "notes/notes.canvas", "opened a subdirectory canvas")
    check(store.crumbs.map(\.name) == ["vault", "notes"], "breadcrumb", "got \(store.crumbs.map(\.name))")
    store.goUp()
    check(store.directory.isEmpty, "went back up")
    check(store.document.nodes.first { $0.kind == .group } != nil, "root canvas reloaded from disk with the group intact")

    print("\n— Layout —")
    let slot = Layout.freeSlot(for: Layout.cardSize, in: store.document, near: nil)
    check(!store.document.nodes.contains { $0.frame.intersects(CGRect(origin: slot, size: Layout.cardSize)) },
          "free slot below everything does not overlap")

}

MainActor.assumeIsolated { storeTests() }

print("")
if failures == 0 { print("✓ canvas suite passed") } else { print("✗ \(failures) failure(s)") }
exit(failures == 0 ? 0 : 1)
