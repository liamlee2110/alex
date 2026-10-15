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

print("\n— Frontmatter.split —")
let splitSample = "---\nstatus: ready\ntitle: \"x\"\n---\n\n# Head\n\nbody"
let split = Frontmatter.split(splitSample)
check(split.hasBlock && split.yaml == "status: ready\ntitle: \"x\"" && split.gap == "\n\n" && split.body == "# Head\n\nbody",
      "split cuts at the closing fence", "got \(split)")
check(split.replacingBody(with: split.body) == splitSample && split.replacingYAML(with: split.yaml) == splitSample,
      "split joins back byte for byte")
check(split.replacingBody(with: "new") == "---\nstatus: ready\ntitle: \"x\"\n---\n\nnew",
      "a new body goes under the block untouched")
check(split.replacingYAML(with: "status: done") == "---\nstatus: done\n---\n\n# Head\n\nbody",
      "a new block goes over the body untouched")
check(!Frontmatter.split("no block").hasBlock && Frontmatter.split("no block").body == "no block",
      "no block: all body")

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

    print("\n— Workspaces —")
    check(vault.workspaces.map(\.path) == [root.path], "the vault opened is the first workspace", "got \(vault.workspaces)")
    let otherVault = scratch.appendingPathComponent("otherVault")
    try! fm.createDirectory(at: otherVault, withIntermediateDirectories: true)
    try! "{ \"icon\": \"graduationcap\" }".write(to: otherVault.appendingPathComponent("canvas.config.json"), atomically: true, encoding: .utf8)
    check(vault.workspace(stepping: 1) == nil, "one workspace has no neighbour")
    vault.open(otherVault)
    check(vault.workspaces.map(\.path) == [root.path, otherVault.path], "a otherVault vault opened joins the foot after the first", "got \(vault.workspaces)")
    check(vault.workspaceIcons[otherVault.path] == "graduationcap" && vault.workspaceIcons[root.path] == nil,
          "a workspace's icon is read from its canvas.config.json", "got \(vault.workspaceIcons)")
    vault.open(URL(fileURLWithPath: root.path + "/"))
    check(vault.workspaces.count == 2, "opening a workspace again, however spelt, adds nothing", "got \(vault.workspaces)")
    check(vault.workspace(stepping: 1)?.path == otherVault.path && vault.workspace(stepping: -1)?.path == otherVault.path,
          "the neighbour wraps at either end")
    vault.forget(root)
    check(vault.workspaces.count == 2, "the open workspace cannot be forgotten")
    vault.switchWorkspace(to: otherVault)
    check(vault.root?.path == root.path && vault.switchDirection == 1,
          "a switch publishes its direction first and opens on the next turn")
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    check(vault.root?.path == otherVault.path, "and then opens the workspace", "got \(String(describing: vault.root))")
    vault.switchWorkspace(to: root)
    check(vault.switchDirection == -1, "back along the foot is the other direction")
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    vault.forget(otherVault)
    check(vault.workspaces.map(\.path) == [root.path], "a forgotten workspace leaves the foot", "got \(vault.workspaces)")
    check(fm.fileExists(atPath: otherVault.path), "and nothing on disk changes")
    let again = Vault(arguments: [], defaults: defaults)
    check(again.workspaces.map(\.path) == [root.path] && again.root?.path == root.path, "the foot is remembered between launches", "got \(again.workspaces)")
    // Two copies share the defaults: each change is made to the list as
    // stored, not as it was at launch.
    vault.open(otherVault)
    again.forget(otherVault)
    let thirdVault = scratch.appendingPathComponent("third")
    try! fm.createDirectory(at: thirdVault, withIntermediateDirectories: true)
    vault.open(thirdVault)
    check(defaults.stringArray(forKey: Vault.workspacesKey) == [root.path, thirdVault.path],
          "a copy's change keeps another copy's forgetting", "got \(String(describing: defaults.stringArray(forKey: Vault.workspacesKey)))")
    vault.open(root)
    vault.forget(thirdVault)
    let visit = scratch.appendingPathComponent("visit")
    try! fm.createDirectory(at: visit, withIntermediateDirectories: true)
    let visiting = Vault(arguments: ["--vault", visit.path], defaults: defaults)
    check(visiting.root?.path == visit.path && visiting.workspaces.map(\.path) == [root.path, visit.path],
          "a --vault launch shows its vault at the foot", "got \(visiting.workspaces)")
    check(defaults.stringArray(forKey: Vault.workspacesKey) == [root.path] && defaults.string(forKey: Vault.defaultsKey) == root.path,
          "but does not remember it", "got \(String(describing: defaults.stringArray(forKey: Vault.workspacesKey)))")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    check(store.isOpen, "store opened the vault root")
    check(fm.fileExists(atPath: root.appendingPathComponent("vault.canvas").path), "first visit wrote vault.canvas")
    check(store.isHome && store.document.nodes.count == 3, "Home holds the note, the folder's section and its file",
          "got \(store.document.nodes.map { $0.file ?? $0.label ?? "" })")
    check(store.unplaced.isEmpty, "nothing unplaced after auto-layout")
    let folder = Folders.section(for: "notes", in: store.document)!
    let alpha = store.document.nodes.first { $0.file == "alpha.md" }!
    check(folder.frame.contains(store.node(forFile: "notes/inner.md")!.frame), "the folder's file sits in its section")
    check(!folder.frame.intersects(alpha.frame), "and the root's file sits outside it")

    print("\n— Recents —")
    check(store.recents.isEmpty, "a fresh vault has no recents")
    store.select(alpha.id)
    check(store.recents == ["alpha.md"], "a file picked is a recent", "got \(store.recents)")
    store.select(folder.id)
    check(store.recents == ["alpha.md"], "a folder picked is not", "got \(store.recents)")
    store.reveal("notes/inner.md")
    check(store.recents == ["notes/inner.md", "alpha.md"], "a file revealed goes to the head", "got \(store.recents)")
    store.openDirectory("")
    store.select(alpha.id)
    check(store.recents == ["alpha.md", "notes/inner.md"], "picked again, it moves to the head, once", "got \(store.recents)")
    check(store.displayTitle(for: "alpha.md") == "Alpha" && store.displayTitle(for: "notes/x.py") == "x.py",
          "a note is called by its heading, anything else by its name")
    let later = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    check(later.recents == ["alpha.md", "notes/inner.md"], "recents are remembered per vault", "got \(later.recents)")
    try! fm.removeItem(at: root.appendingPathComponent("notes/inner.md"))
    vault.reload()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    check(store.recents == ["alpha.md"], "a file that left the vault leaves recents", "got \(store.recents)")
    try! "# Inner\n".write(to: root.appendingPathComponent("notes/inner.md"), atomically: true, encoding: .utf8)
    vault.reload()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.select(nil)

    print("\n— CardPreview —")
    let hardWrapped = """
    ---
    status: ready
    ---
    # Reflow
    Read this whole file before doing anything in this
    directory. It is the operational form.

    - item one
    - item two
    Second paragraph, one line.
    """
    try! hardWrapped.write(to: root.appendingPathComponent("notes/reflow.md"), atomically: true, encoding: .utf8)
    let reflow = CardPreview.make(for: "notes/reflow.md", vault: vault)
    check(reflow.title == "Reflow", "the first heading is the title", "got \(reflow.title)")
    check(reflow.lines == ["Read this whole file before doing anything in this directory. It is the operational form.",
                           "- item one", "- item two", "Second paragraph, one line."],
          "hard-wrapped lines fold into one paragraph; a blank line, a list item and a heading break it",
          "got \(reflow.lines)")
    check(reflow.hasHeading && reflow.body.hasPrefix("# Reflow\nRead this whole file"),
          "the body keeps its own syntax for the renderer, heading first", "got \(reflow.body.prefix(30))")

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
    check(store.document.nodes.firstIndex { $0.id == group.id }! < store.document.nodes.firstIndex { $0.kind != .group }!,
          "group goes before the cards, so it draws behind")
    check(group.frame.contains(store.document.node(sticky.id)!.frame), "group encloses the selection")
    check(store.nodeIDs(inside: group.frame).isSuperset(of: [placed.id, sticky.id]), "group knows what it holds",
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

    print("\n— A file with no card (revision 19) —")
    store.remove([store.node(forFile: "outside.md")!.id])
    store.select(nil)
    store.reveal("outside.md")
    check(store.looseFile == "outside.md" && store.selection.isEmpty && store.inspectorVisible,
          "revealing a file not on the canvas opens it in the panel", "got \(String(describing: store.looseFile))")
    check(store.livePanelHasContent, "the panel counts a loose file as something to show")
    store.placeLooseFile()
    let outsideCard = store.node(forFile: "outside.md")
    check(outsideCard != nil && store.selection == [outsideCard!.id] && store.looseFile == nil,
          "placing it puts its card on the canvas and picks it")
    try! "{}".write(to: root.appendingPathComponent("canvas.config.json"), atomically: true, encoding: .utf8)
    store.refreshUnplaced()
    check(!store.unplaced.contains { $0.path == "canvas.config.json" }, "the tray leaves the vault's settings out")
    try! FileManager.default.removeItem(at: root.appendingPathComponent("canvas.config.json"))
    store.refreshUnplaced()

    store.openDirectory("notes")
    check(store.isHome && store.focusRequest == Folders.section(for: "notes", in: store.document)?.id,
          "a folder opens as its section on Home")
    store.focusRequest = nil
    check(store.crumbs.map(\.name) == ["vault"], "Home's breadcrumb is the vault", "got \(store.crumbs.map(\.name))")
    try! "{\"nodes\":[],\"edges\":[]}\n".write(to: root.appendingPathComponent("notes/board.canvas"), atomically: true, encoding: .utf8)
    vault.reload()
    store.openCanvas(at: "notes/board.canvas")
    check(!store.isHome && store.crumbs.map(\.name) == ["vault", "board"], "another canvas is a crumb after Home",
          "got \(store.crumbs.map(\.name))")
    store.goUp()
    check(store.isHome, "went back to Home")
    check(store.node(forFile: "notes/board.canvas") == nil, "a canvas file is not a card on Home")
    check(store.canvases == [store.homePath, "notes/board.canvas"], "the canvas list is Home, then every other canvas",
          "got \(store.canvases)")
    let made = store.newCanvas()
    check(made == "Untitled canvas.canvas" && store.canvasPath == made
          && FileManager.default.fileExists(atPath: root.appendingPathComponent(made ?? "-").path),
          "a new canvas is written at the root and opened", "got \(String(describing: made))")
    check(store.canvases.contains("Untitled canvas.canvas"), "and joins the list")
    check(store.newCanvas() == "Untitled canvas 2.canvas", "a second one takes the next free name")
    try? FileManager.default.removeItem(at: root.appendingPathComponent("Untitled canvas.canvas"))
    try? FileManager.default.removeItem(at: root.appendingPathComponent("Untitled canvas 2.canvas"))
    vault.reload()
    store.goUp()

    print("\n— Shapes —")
    let box = store.draw(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 220))!
    tick()
    check(box.kind == .text && box.shape == .rectangle
          && box.frame == CGRect(x: 100, y: 100, width: 200, height: 120),
          "a dragged rectangle takes the dragged box", "got \(box.frame)")
    check(store.selection == [box.id] && store.tool == .select, "the shape is selected and the tool hands back")
    let clicked = store.draw(.ellipse, from: CGPoint(x: 500, y: 500), to: CGPoint(x: 502, y: 501))!
    tick()
    check(clicked.shape == .ellipse && clicked.frame.size == ShapeMetrics.defaultSize
          && clicked.center == CGPoint(x: 500, y: 500),
          "a click without a drag makes the default size, centred on the click", "got \(clicked.frame)")
    let level = store.draw(.arrow, from: CGPoint(x: 0, y: 1000), to: CGPoint(x: 200, y: 1000))!
    tick()
    check(level.shape == .line && level.height == ShapeMetrics.minimumThickness && level.lineToEnd == "arrow",
          "a level arrow gets a box of the minimum thickness and an arrowhead", "got \(level.frame)")
    let ends = level.lineEndpoints
    check(abs(ends.from.x) < 0.01 && abs(ends.from.y - 1000) < 0.01
          && abs(ends.to.x - 200) < 0.01 && abs(ends.to.y - 1000) < 0.01,
          "its ends stay where they were drawn", "got \(ends)")
    store.setTool(.text)
    let words = store.addText(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 41, y: 60))
    tick()
    check(words.kind == .text && words.shape == .text
          && words.frame == CGRect(origin: CGPoint(x: 40, y: 60), size: ShapeMetrics.defaultTextSize)
          && store.tool == .select,
          "a text box clicked in starts at the click, one line tall, and the tool hands back", "got \(words.frame)")
    check(!store.selectionHasPanel && store.panelNode == nil,
          "a selected text box gives the sheet nothing to show")
    let jotted = store.addSticky(at: CGPoint(x: 600, y: 60))
    tick()
    check(!store.selectionHasPanel && store.panelNode == nil,
          "nor does a selected sticky")
    store.selection = [jotted.id, box.id]
    check(!store.selectionHasPanel, "nor does a shape beside it: its style is a bar on the desk")
    let dragged = store.addText(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 100, y: 200))
    tick()
    check(dragged.frame == CGRect(x: 100, y: 200, width: 200, height: 100),
          "a dragged text box takes the dragged box", "got \(dragged.frame)")
    let shapesOnDisk = try! CanvasDocument.decode(Data(contentsOf: root.appendingPathComponent("vault.canvas")))
    check(shapesOnDisk.node(level.id)?.linePoints == level.linePoints
          && shapesOnDisk.node(box.id)?.shape == .rectangle
          && shapesOnDisk.node(box.id)?.kind == .text
          && shapesOnDisk.node(words.id)?.shape == .text,
          "shapes round-trip through the file as text nodes under x- keys")
    store.setFontSize([words.id, jotted.id], .large)
    tick()
    check(store.document.node(words.id)?.fontSize == 20 && store.document.node(jotted.id)?.fontSize == 20
          && store.document.node(words.id)?.height == 40 * 20 / 13,
          "text size goes on a text box and a sticky, and the text box's height follows its words",
          "got \(String(describing: store.document.node(words.id)?.frame))")
    store.setFontSize([words.id], .medium)
    tick()
    check(store.document.node(words.id)?.fontSize == nil
          && abs((store.document.node(words.id)?.height ?? 0) - 40) < 0.001,
          "medium writes no key and gives the height back")
    check(TextSize(points: 19) == .large && TextSize(points: nil) == .medium, "any size reads as its nearest preset")
    check(store.document.node(jotted.id)?.fontFamily == .handDrawn, "words on the desk are hand-drawn by default")
    store.setFontFamily([jotted.id, words.id], .code)
    tick()
    check(store.document.node(jotted.id)?.fontFamily == .code && store.document.node(words.id)?.extra["x-font-family"] == .string("code"),
          "a face is written under x-font-family")
    store.setFontFamily([jotted.id, words.id], .handDrawn)
    tick()
    check(store.document.node(jotted.id)?.extra["x-font-family"] == nil, "hand-drawn writes no key")
    check(store.document.node(jotted.id)?.textAlign == .left && store.document.node(box.id)?.textAlign == .center,
          "a sticky's words start at the left and a shape's are centred")
    store.setTextAlign([jotted.id, box.id], .right)
    tick()
    check(store.document.node(jotted.id)?.extra["x-text-align"] == .string("right")
          && store.document.node(box.id)?.textAlign == .right,
          "an alignment is written under x-text-align")
    store.setTextAlign([jotted.id, box.id], .center)
    tick()
    check(store.document.node(box.id)?.extra["x-text-align"] == nil
          && store.document.node(jotted.id)?.extra["x-text-align"] == .string("center"),
          "a kind's own alignment writes no key")
    check(StyleScope([store.document.node(jotted.id)!, store.document.node(box.id)!]).textAlign == .center,
          "the style panel reads an alignment the selection shares")
    store.setFilled([box.id], true)
    tick()
    store.setDashed([box.id], true)
    tick()
    check(store.document.node(box.id)?.filled == true && store.document.node(box.id)?.dashed == true,
          "filled and dashed are set")
    store.setLineEnds(level.id, from: true, to: false)
    tick()
    check(store.document.node(level.id)?.lineFromEnd == "arrow" && store.document.node(level.id)?.lineToEnd == nil,
          "an arrowhead moves from one end to the other")
    let alphaCentre = store.document.node(placed.id)!.center
    let edgesBefore = store.document.edges.count
    let between = store.draw(.arrow, from: alphaCentre, to: clicked.center)
    tick()
    check(between == nil && store.document.edges.count == edgesBefore + 1,
          "an arrow from one card to another is an edge, not a shape")
    let lineBetween = store.draw(.line, from: alphaCentre, to: clicked.center)
    tick()
    check(lineBetween == nil && store.document.edges.last?.toEnd == "none",
          "a line between two cards is an edge with no arrowhead")
    let nearby = CGPoint(x: clicked.frame.maxX + 10, y: clicked.frame.midY)
    let near = store.draw(.arrow, from: alphaCentre, to: nearby, reach: 16)
    tick()
    check(near == nil && store.document.edges.count == edgesBefore + 3,
          "an arrow ending within reach of a block attaches to it")
    let loose = store.draw(.arrow, from: alphaCentre, to: clicked.center, reach: 16, bind: false)
    tick()
    check(loose != nil && store.document.edges.count == edgesBefore + 3,
          "with binding off, an arrow between two cards stays a shape")
    let onLine = store.draw(.arrow, from: alphaCentre, to: level.center)
    tick()
    check(onLine != nil, "a line is not a block an arrow attaches to")
    store.remove([loose!.id, onLine!.id])
    tick()
    store.remove([box.id, clicked.id, level.id])
    tick()
    check(store.document.edges.count == edgesBefore, "removing the shapes takes their edges with them")

    print("\n— A view that has lost the canvas —")
    let content = CGRect(x: 0, y: 0, width: 400, height: 300)
    check(Viewport().share(of: content, in: CGSize(width: 800, height: 600)) == 1, "a view holding the whole canvas shows all of it")
    check(Viewport(offset: CGPoint(x: -1000, y: 0), scale: 1).share(of: content, in: CGSize(width: 800, height: 600)) == 0,
          "a view past the canvas shows none of it")
    check(Viewport(offset: CGPoint(x: -300, y: 0), scale: 1).share(of: content, in: CGSize(width: 800, height: 600)) < Viewport.lostShare,
          "a view with a quarter of it in sight has lost it")

    print("\n— Viewport memory —")
    store.viewSize = CGSize(width: 1000, height: 800)
    store.viewport = Viewport(offset: CGPoint(x: 100, y: 50), scale: 0.5)
    store.wantsFit = false
    store.openCanvas(at: "notes/board.canvas")
    check(store.wantsFit && store.restoredCentre == nil, "a canvas with no memory asks the view for a fit")
    store.openHome()
    // The desk's visual centre is the view's, moved by what floats over
    // its edges (`deskInsets`, which the window sets; none here), so the
    // remembered point is that, in world units: (500 + inset.x - 100) / 0.5
    // across, (400 + inset.y - 50) / 0.5 down.
    let inset = store.deskInset
    check(store.restoredCentre == CGPoint(x: (500 + inset.x - 100) / 0.5, y: (400 + inset.y - 50) / 0.5),
          "what a canvas remembers is the world point under the desk's centre", "got \(String(describing: store.restoredCentre))")
    check(store.viewport == Viewport(offset: CGPoint(x: 100, y: 50), scale: 0.5),
          "at the same desk size it comes back exactly where it was", "got \(store.viewport)")
    store.openCanvas(at: "notes/board.canvas")
    store.viewSize = CGSize(width: 1400, height: 800)
    store.openHome()
    check(store.viewport == Viewport(offset: CGPoint(x: 300, y: 50), scale: 0.5),
          "at another desk size the same point sits under the desk's centre", "got \(store.viewport)")
    check(store.document.nodes.first { $0.kind == .group } != nil, "root canvas reloaded from disk with the group intact")

    print("\n— canvas.config.json —")
    check(VaultPath.matches("competencies/C0.1.md", glob: "competencies/*.md"), "glob: one level")
    check(!VaultPath.matches("sessions/x.md", glob: "competencies/*.md"), "glob: other directory")
    check(VaultPath.matches("a/b/c.png", glob: "**/*.png") && VaultPath.matches("c.png", glob: "**/*.png"), "glob: any depth")
    let courses = root.appendingPathComponent("courses")
    try! fm.createDirectory(at: courses, withIntermediateDirectories: true)
    try! "---\nid: C0.1\nphase: 0\nstatus: done\nprerequisites: []\n---\n# First\n".write(to: courses.appendingPathComponent("C0.1.md"), atomically: true, encoding: .utf8)
    try! "---\nid: C1.1\nphase: 1\nstatus: in progress\nprerequisites: [C0.1]\n---\n# Second\n".write(to: courses.appendingPathComponent("C1.1.md"), atomically: true, encoding: .utf8)
    try! "---\nid: C1.2\nphase: 1\nstatus: not started\nprerequisites: [C0.1, C1.1]\n---\n# Third\n".write(to: courses.appendingPathComponent("C1.2.md"), atomically: true, encoding: .utf8)
    let config = """
    {"views": [{"match": "courses/*.md", "colorBy": "status",
                "colors": {"done": "4", "in progress": "5", "not started": ""},
                "groupBy": "phase", "groupLabel": "Block {value}", "edgesFrom": "prerequisites"}]}
    """
    try! config.write(to: root.appendingPathComponent("canvas.config.json"), atomically: true, encoding: .utf8)
    store.loadConfig()
    check(store.config.views.count == 1 && store.config.views[0].groupBy == "phase", "config decoded")
    vault.reload()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.openDirectory("courses")
    let first = store.node(forFile: "courses/C0.1.md")!
    let second = store.node(forFile: "courses/C1.1.md")!
    let third = store.node(forFile: "courses/C1.2.md")!
    check(store.tint(for: first)?.color == "4" && store.tint(for: second)?.color == "5", "colorBy maps status to a colour")
    check(store.tint(for: third) == nil, "an empty mapping means no tint")
    let derived = Set(store.derivedEdges())
    check(derived == [CanvasStore.DerivedEdge(from: first.id, to: second.id),
                      CanvasStore.DerivedEdge(from: first.id, to: third.id),
                      CanvasStore.DerivedEdge(from: second.id, to: third.id)],
          "prerequisites become edges from the prerequisite to the course", "got \(derived)")
    check(store.arrangeByConfig(), "arrange finds the rule")
    let groups = store.document.nodes.filter { $0.extra["x-arranged-by"] != nil }.sorted { ($0.label ?? "") < ($1.label ?? "") }
    check(groups.map(\.label) == ["Block 0", "Block 1"], "one labelled group per phase", "got \(groups.map(\.label))")
    let coursesSection = Folders.section(for: "courses", in: store.document)!
    check(groups.allSatisfy { coursesSection.frame.contains($0.frame) }, "on Home, inside the files' folder section, grown to fit",
          "section \(coursesSection.frame) groups \(groups.map(\.frame))")
    check(groups[1].frame.contains(store.document.node(second.id)!.frame) && groups[1].frame.contains(store.document.node(third.id)!.frame), "block 1 holds its two cards")
    check(!store.document.node(second.id)!.frame.intersects(store.document.node(third.id)!.frame), "cards inside a group do not overlap")
    check(store.arrangeByConfig() && store.document.nodes.filter { $0.extra["x-arranged-by"] != nil }.count == 2, "arranging again replaces the groups instead of stacking them")
    let tall = Array(repeating: CGSize(width: 400, height: 300), count: 9)
    let runs = CanvasStore.columnRuns(tall, aspect: 1.6, gap: 60)
    check(runs.count > 1 && runs.flatMap { $0 } == Array(0..<9),
          "nine blocks wrap into columns, still read in order", "got \(runs)")
    check(CanvasStore.columnRuns([CGSize(width: 400, height: 300)], aspect: 1.6, gap: 60) == [[0]], "one block is one column")
    store.openDirectory("")

    print("\n— Index —")
    try! "# Alpha\n\nSee [[Gamma]] and [[beta|the other]].\n".write(to: root.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
    try! "# Gamma\n\nBack to [[Alpha]].\n".write(to: root.appendingPathComponent("notes/gamma.md"), atomically: true, encoding: .utf8)
    vault.reload()
    let index = vault.index()
    check(index.resolve(link: "gamma") == "notes/gamma.md" && index.resolve(link: "ALPHA") == "alpha.md", "links resolve by stem, any case")
    check(index.resolve(link: "nope") == nil, "an unknown link resolves to nothing")
    let gammaLinks = index.backlinks(to: "notes/gamma.md")
    check(gammaLinks.map(\.source) == ["alpha.md"] && gammaLinks.first?.snippet.contains("[[Gamma]]") == true, "backlinks carry the source and the line", "got \(gammaLinks)")
    check(index.backlinks(to: "alpha.md").map(\.source) == ["notes/gamma.md"], "links go both ways")
    check(index.canvases(for: "courses/C0.1.md").contains("vault.canvas"), "the index knows which canvases carry a file", "got \(index.canvases(for: "courses/C0.1.md"))")

    print("\n— Search —")
    check(SearchIndex.score("plan", in: "plan.md plan") ?? -1 > SearchIndex.score("plan", in: "notes/planning-a-trip.md") ?? -1, "a prefix match outranks a later one")
    check(SearchIndex.score("cst", in: "constitution.md") != nil, "subsequence matches")
    check(SearchIndex.score("xyz", in: "constitution.md") == nil, "no match is nil")
    let hits = SearchIndex.search("c1", vault: vault, store: store)
    check(hits.first?.path.hasPrefix("courses/C1") == true, "search finds by path", "got \(hits.map(\.path).prefix(3))")
    check(SearchIndex.search("Second", vault: vault, store: store).first?.path == "courses/C1.1.md", "search finds a note by its title")

    print("\n— Find on canvas —")
    let low = CanvasNode(kind: .text, frame: CGRect(x: 0, y: 400, width: 100, height: 100),
                         text: "# Dear recipient\nThe Recipient title, then recipient name")
    let high = CanvasNode(kind: .group, frame: CGRect(x: 300, y: 0, width: 100, height: 100), label: "Recipient block")
    let left = CanvasNode(kind: .text, frame: CGRect(x: -300, y: 0, width: 100, height: 100), text: "nothing here")
    let found = CanvasFind.hits("RECIPIENT", in: [low, high, left], texts: { [$0.text ?? $0.label ?? ""] })
    check(found.total == 4 && found.hits.count == 4, "every occurrence is a hit, any case", "got \(found.total)")
    check(found.hits.map(\.node) == [high.id, low.id, low.id, low.id], "hits read top to bottom, a node's in its own order")
    check(found.hits[1].snippet == "Dear recipient" && String(found.hits[1].snippet[found.hits[1].match]) == "recipient",
          "a snippet drops markdown's marks and keeps the match's range", "got \(found.hits[1].snippet)")
    check(Set(found.hits.map(\.id)).count == 4, "each hit has its own id")
    let titled = CanvasFind.hits("plan", in: [low], texts: { _ in ["The plan", "# The plan\nno more"] })
    check(titled.total == 1, "a title that is also the note's heading is one hit", "got \(titled.total)")
    let long = String(repeating: "word ", count: 40) + "needle" + String(repeating: " tail", count: 40)
    let cutHit = CanvasFind.hits("needle", in: [low], texts: { _ in [long] }).hits[0]
    check(cutHit.snippet.hasPrefix("…") && cutHit.snippet.hasSuffix("…") && cutHit.snippet.count <= CanvasFind.span + 2,
          "a long line is cut round its match", "got \(cutHit.snippet)")
    check(CanvasFind.hits("  ", in: [low], texts: { [$0.text ?? ""] }).total == 0, "a blank query finds nothing")

    print("\n— Layout —")
    let slot = Placement.freeSlot(for: Placement.cardSize, in: store.document, near: nil)
    check(!store.document.nodes.contains { $0.frame.intersects(CGRect(origin: slot, size: Placement.cardSize)) },
          "free slot below everything does not overlap")
    check(Placement.size(forFile: "papers/inertia.pdf", isDirectory: false) == Placement.documentSize,
          "a document is page-shaped")
    check(Placement.size(forFile: "alpha.md", isDirectory: false) == Placement.cardSize, "a note is a card")
    let mixed = Placement.autoLayout((0..<7).map {
        VaultEntry(path: $0 == 1 ? "paper.pdf" : "note\($0).md", isDirectory: false)
    })
    let overlap = mixed.contains { a in mixed.contains { b in a.id != b.id && a.frame.intersects(b.frame) } }
    check(!overlap, "a page-shaped card does not sit on the row beneath it")

    print("\n— Fold —")
    try! Data().write(to: root.appendingPathComponent("paper.pdf"))
    try! "# Folded too\n".write(to: root.appendingPathComponent("folded.md"), atomically: true, encoding: .utf8)
    vault.reload()
    let paper = store.place("paper.pdf")
    let other = store.place("folded.md")
    tick()
    check(paper.frame.size == Placement.documentSize, "a placed document gets the page shape", "got \(paper.frame.size)")
    store.setFolded([paper.id], true)
    tick()
    let justFolded = store.document.node(paper.id)!
    check(justFolded.folded && justFolded.height == Placement.foldedHeight,
          "folding leaves the title row", "got \(justFolded.height)")
    check(String(decoding: try! store.document.encode(), as: UTF8.self).contains("\"x-folded\" : true"),
          "the fold is in the file, under an x- key")
    undo.undo()
    tick()
    check(store.document.node(paper.id)?.folded == false, "folding is one undo step")
    undo.redo()
    tick()
    store.setFolded([paper.id], false)
    tick()
    let reopened = store.document.node(paper.id)!
    check(!reopened.folded && reopened.height == Placement.documentSize.height,
          "unfolding comes back to the height it had", "got \(reopened.height)")
    check(reopened.unfoldedHeight == nil
          && !String(decoding: try! store.document.encode(), as: UTF8.self).contains("x-folded"),
          "and leaves no keys behind")
    store.setFolded([paper.id], true)
    store.toggleFold([paper.id, other.id])
    tick()
    check(store.document.node(paper.id)!.folded && store.document.node(other.id)!.folded,
          "toggling a mixed selection folds what is still open")
    store.toggleFold([paper.id, other.id])
    tick()
    check(!store.document.node(paper.id)!.folded && !store.document.node(other.id)!.folded,
          "toggling again unfolds both")
    let note = store.addSticky(at: CGPoint(x: 2000, y: 2000))
    store.toggleFold([note.id])
    tick()
    check(store.document.node(note.id)!.height == Placement.textSize.height,
          "a sticky note has no title row to fold to, so it does not fold")
    let sectionHeight = store.document.node(folder.id)!.height
    store.toggleFold([folder.id])
    tick()
    check(store.document.node(folder.id)!.height == sectionHeight, "a folder's section does not fold either")

    // Revision 45: a picture's card is the picture; no fold, no sheet.
    try! Data().write(to: root.appendingPathComponent("photo.png"))
    vault.reload()
    let photo = store.place("photo.png")
    tick()
    let photoHeight = store.document.node(photo.id)!.height
    store.toggleFold([photo.id])
    tick()
    check(store.document.node(photo.id)!.height == photoHeight && !store.document.node(photo.id)!.folded,
          "a picture does not fold")
    check(!StyleScope([store.document.node(photo.id)!]).foldable, "and the style panel offers no fold for it")
    store.select(photo.id)
    check(!store.selectionHasPanel && store.panelNode == nil, "a selected picture gives the sheet nothing to show")
    let pinsBefore = store.pinnedPanels.count
    store.pinLivePanel()
    check(store.pinnedPanels.count == pinsBefore, "nor can it be added to the side panel")
    check(StyleScope([store.document.node(photo.id)!]).corner == .small, "a picture starts at the card's own corners")
    store.setCorners([photo.id], .large)
    tick()
    check(store.document.node(photo.id)!.cornerRadius == 32
          && String(decoding: try! store.document.encode(), as: UTF8.self).contains("\"x-radius\" : 32"),
          "its corners are the reader's, written under an x- key")
    store.setCorners([photo.id], .small)
    tick()
    check(store.document.node(photo.id)!.cornerRadius == nil, "and the card's own leaves no key")
    store.setCorners([note.id], .none)
    tick()
    check(store.document.node(note.id)!.cornerRadius == nil, "a sticky's corners are not a picture's to set")
    store.select(nil)

}

MainActor.assumeIsolated { storeTests() }

/// Revision 20: a folder is a section on Home; a drag moves files.
@MainActor
func folderTests() {
    print("\n— Folders as sections (revision 20) —")
    let root = scratch.appendingPathComponent("folders")
    for dir in ["a/b", "empty", "papers"] {
        try! fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
    }
    for file in ["top.md", "a/one.md", "a/b/two.md", "papers/p.md", "papers/dup.md", "dup.md"] {
        try! "# \(file)\n".write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }
    try! "{}".write(to: root.appendingPathComponent("a/a.canvas"), atomically: true, encoding: .utf8)

    // Pure: the old folder card goes, sections nest, empty folders wait.
    let tree = try! VaultNode.scan("", root: root)
    var old = CanvasDocument(nodes: [CanvasNode(kind: .file, frame: CGRect(x: 0, y: 0, width: 200, height: 150), file: "a")])
    Folders.reconcile(&old, tree: tree, home: "folders.canvas")
    check(!old.nodes.contains { $0.kind == .file && $0.file == "a" }, "a folder card from before is taken off")
    let a = Folders.section(for: "a", in: old), b = Folders.section(for: "a/b", in: old)
    check(a != nil && b != nil && a!.frame.contains(b!.frame), "a subfolder's section sits inside its parent's")
    check(b!.frame.contains(old.nodes.first { $0.file == "a/b/two.md" }!.frame), "and holds its file")
    check(Folders.section(for: "empty", in: old) == nil, "an empty folder has no section yet")
    check(!old.nodes.contains { $0.file == "a/a.canvas" }, "a canvas file is not placed")
    check(old.nodes.firstIndex { $0.id == a!.id }! < old.nodes.firstIndex { $0.id == b!.id }!,
          "the outer section draws first, so the inner one takes its presses")
    check(Folders.colour(for: "a/b") == Folders.colour(for: "a"), "a subfolder wears its top folder's colour")
    var again = old
    check(!Folders.reconcile(&again, tree: tree, home: "folders.canvas"), "a Home already up to date is left alone")

    // Growing pushes along what stands beside and down what sits under.
    var side = CanvasDocument()
    var left = CanvasNode(kind: .group, frame: CGRect(x: 0, y: 0, width: 400, height: 300), label: "left")
    left.extra[Folders.key] = .string("left")
    var right = CanvasNode(kind: .group, frame: CGRect(x: 460, y: 0, width: 400, height: 300), label: "right")
    right.extra[Folders.key] = .string("right")
    let below = CanvasNode(kind: .file, frame: CGRect(x: 0, y: 360, width: 320, height: 200), file: "x.md")
    let inRight = CanvasNode(kind: .file, frame: CGRect(x: 490, y: 54, width: 320, height: 200), file: "right/y.md")
    side.nodes = [left, right, below, inRight]
    Folders.grow(left.id, toContain: CGRect(x: 30, y: 54, width: 700, height: 400), in: &side)
    let grownLeft = side.node(left.id)!.frame
    check(!grownLeft.intersects(side.node(right.id)!.frame), "a section grown wider pushes its neighbour along",
          "left \(grownLeft) right \(side.node(right.id)!.frame)")
    check(!grownLeft.intersects(side.node(below.id)!.frame), "and one grown taller pushes what is under it down")
    check(side.node(right.id)!.frame.contains(side.node(inRight.id)!.frame), "a pushed section takes its cards along")

    let defaults = UserDefaults(suiteName: "alex-folder-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    let undo = UndoManager()
    store.undoManager = undo
    func tick(_ t: Double = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(t)) }
    tick(0.2)
    check(store.isHome && Folders.section(for: "papers", in: store.document) != nil, "the store opens Home with sections")

    // A card dragged into a section moves its file there.
    let top = store.node(forFile: "top.md")!
    let papers = Folders.section(for: "papers", in: store.document)!
    store.move([top.id], by: CGSize(width: papers.center.x - top.center.x, height: papers.center.y - top.center.y))
    tick()
    check(fm.fileExists(atPath: root.appendingPathComponent("papers/top.md").path)
          && !fm.fileExists(atPath: root.appendingPathComponent("top.md").path), "the file moved into the folder")
    check(store.document.node(top.id)?.file == "papers/top.md", "the card follows it")
    undo.undo()
    tick()
    check(fm.fileExists(atPath: root.appendingPathComponent("top.md").path) && store.document.node(top.id)?.file == "top.md",
          "undo moves the file back")
    undo.redo()
    tick()
    check(store.document.node(top.id)?.file == "papers/top.md", "redo moves it again")

    // A name already there refuses the drag.
    let dup = store.node(forFile: "dup.md")!
    let papersNow = Folders.section(for: "papers", in: store.document)!
    store.move([dup.id], by: CGSize(width: papersNow.center.x - dup.center.x, height: papersNow.center.y - dup.center.y))
    tick()
    check(fm.fileExists(atPath: root.appendingPathComponent("dup.md").path) && store.document.node(dup.id)?.x == dup.x,
          "a name already taken refuses the drag", "trouble: \(store.trouble ?? "none")")
    check(store.trouble?.contains("dup.md") == true, "and says why")

    // Out onto Home's floor: back to the vault's root.
    let moved = store.document.node(top.id)!
    store.move([moved.id], by: CGSize(width: 0, height: -(moved.y - (Folders.section(for: "papers", in: store.document)!.y)) - 400))
    tick()
    check(store.document.node(top.id)?.file == "top.md" && fm.fileExists(atPath: root.appendingPathComponent("top.md").path),
          "a card dragged out of every section goes to the root")

    // A section dragged into another moves the folder, with its cards.
    let bSection = Folders.section(for: "a/b", in: store.document)!
    let target = Folders.section(for: "papers", in: store.document)!
    let carried = store.nodeIDs(inside: bSection.frame).union([bSection.id])
    store.move(carried, by: CGSize(width: target.center.x - bSection.center.x, height: target.center.y - bSection.center.y))
    tick()
    check(fm.fileExists(atPath: root.appendingPathComponent("papers/b/two.md").path), "the folder moved into the other")
    check(Folders.section(for: "papers/b", in: store.document) != nil && store.node(forFile: "papers/b/two.md") != nil,
          "its section and its cards follow")

    // A folder's section renamed renames the folder.
    let paperSection = Folders.section(for: "papers", in: store.document)!
    store.setLabel(paperSection.id, "reading")
    tick()
    check(fm.fileExists(atPath: root.appendingPathComponent("reading/b/two.md").path)
          && Folders.section(for: "reading", in: store.document)?.label == "reading"
          && store.node(forFile: "reading/p.md") != nil, "renaming the section renames the folder and every path under it")

    // Taken off Home, a folder waits in the tray, and comes back.
    let reading = Folders.section(for: "reading", in: store.document)!
    store.remove([reading.id])
    tick()
    check(Folders.section(for: "reading", in: store.document) == nil && store.node(forFile: "reading/p.md") == nil,
          "removing a folder's section takes its cards off Home")
    check(store.unplaced.map(\.path) == ["reading"] && fm.fileExists(atPath: root.appendingPathComponent("reading/p.md").path),
          "the folder waits in the tray; nothing on disk changes", "got \(store.unplaced.map(\.path))")
    try! "# Late\n".write(to: root.appendingPathComponent("reading/late.md"), atomically: true, encoding: .utf8)
    vault.reload()
    tick(0.2)
    check(store.node(forFile: "reading/late.md") == nil, "a file appearing in a hidden folder stays off Home")
    store.place("reading")
    tick()
    check(Folders.section(for: "reading", in: store.document) != nil && store.node(forFile: "reading/late.md") != nil
          && store.unplaced.isEmpty, "placing it brings the section back with everything in it")

    // A new file joins its folder's section, which grows to hold it.
    let aSection = Folders.section(for: "a", in: store.document)!
    for i in 0..<6 {
        try! "# New \(i)\n".write(to: root.appendingPathComponent("a/new\(i).md"), atomically: true, encoding: .utf8)
    }
    vault.reload()
    tick(0.2)
    let grown = Folders.section(for: "a", in: store.document)!
    let newCards = (0..<6).compactMap { store.node(forFile: "a/new\($0).md") }
    check(newCards.count == 6 && newCards.allSatisfy { grown.frame.contains($0.frame) }, "new files land inside their folder's section",
          "section \(grown.frame) cards \(newCards.map(\.frame))")
    check(grown.height > aSection.height, "which grows to hold them")
    let others = store.document.nodes.filter { $0.id != grown.id && !grown.frame.contains($0.frame) && !$0.frame.contains(grown.frame) }
    check(!others.contains { $0.frame.intersects(grown.frame) }, "and pushes down what was under it",
          "overlaps: \(others.filter { $0.frame.intersects(grown.frame) }.map { $0.file ?? $0.label ?? "" })")

    // A new note beside a card in a section is written into that folder.
    store.select(newCards[0].id)
    store.newNote()
    check(fm.fileExists(atPath: root.appendingPathComponent("a/Untitled.md").path)
          && grown.frame.union(Folders.section(for: "a", in: store.document)!.frame)
            .contains(store.node(forFile: "a/Untitled.md")!.frame), "a new note joins the selection's folder")
}

MainActor.assumeIsolated { folderTests() }

print("\n— Link cards —")
do {
    check(LinkKind.webURL("https://example.com/a b") == nil, "a space is not an address")
    check(LinkKind.webURL("example.com/page")?.absoluteString == "https://example.com/page", "a bare host is given https")
    check(LinkKind.webURL("mailto:someone@example.com") == nil && LinkKind.webURL("file:///tmp/x") == nil, "only http and https are links")
    check(LinkKind.webURL("  https://x.com/jack/status/20\n")?.host == "x.com", "whitespace around an address is trimmed")
    check(LinkKind.webURL("hello") == nil && LinkKind.webURL("") == nil, "a word is not an address")

    check(LinkKind.classify("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s") == .youtube(id: "dQw4w9WgXcQ"), "a YouTube watch page")
    check(LinkKind.classify("https://youtu.be/dQw4w9WgXcQ") == .youtube(id: "dQw4w9WgXcQ"), "a youtu.be short link")
    check(LinkKind.classify("https://www.youtube.com/shorts/dQw4w9WgXcQ") == .youtube(id: "dQw4w9WgXcQ"), "a short")
    check(LinkKind.classify("https://www.youtube.com/@RickAstleyYT") == .web, "a channel page is a page")
    check(LinkKind.classify("https://x.com/jack/status/20") == .x(id: "20")
          && LinkKind.classify("https://twitter.com/jack/status/20?s=1") == .x(id: "20"), "a post on X, by either host")
    check(LinkKind.classify("https://www.threads.net/@zuck/post/CuZsgfWLyiI") == .threads(path: "@zuck/post/CuZsgfWLyiI"), "a Threads post")
    check(LinkKind.classify("https://www.pinterest.com/pin/99360735500167749/") == .pinterest(id: "99360735500167749"), "a Pin")
    check(LinkKind.classify("https://www.instagram.com/reels/C2Q5b7yv1Zz/") == .instagram(path: "reel/C2Q5b7yv1Zz"), "an Instagram reel")
    check(LinkKind.classify("https://vimeo.com/22439234") == .vimeo(id: "22439234"), "a Vimeo video")
    check(LinkKind.classify("https://www.tiktok.com/@scout2015/video/6718335390845095173") == .tiktok(id: "6718335390845095173"), "a TikTok")
    check(LinkKind.classify("https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=x") == .spotify(path: "track/4cOdK2wGLETKBW3PvgPWqT"), "a Spotify track")
    check(LinkKind.classify("https://arxiv.org/abs/1706.03762") == .web, "the open web")
    check(LinkKind.youtube(id: "a").cardSize.height == 234 && LinkKind.web.cardSize == Placement.cardSize,
          "a video card is 16:9 plus its caption; a page is a paper card")

    let video = Data(#"""
    {"title":"Never Gonna Give You Up","author_name":"Rick Astley","type":"video","provider_name":"YouTube",
     "thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg","html":"<iframe src=\"https://www.youtube.com/embed/dQw4w9WgXcQ\"></iframe>"}
    """#.utf8)
    let videoMeta = LinkMetadata.parseOEmbed(video)
    check(videoMeta?.title == "Never Gonna Give You Up" && videoMeta?.author == "Rick Astley"
          && videoMeta?.thumbnail?.hasSuffix("hqdefault.jpg") == true, "an oEmbed reply gives title, author and picture", "got \(String(describing: videoMeta))")
    check(videoMeta?.description == nil, "an iframe carries no text")
    let posters = LinkMetadata.thumbnailCandidates(for: videoMeta!, kind: .youtube(id: "dQw4w9WgXcQ")).map(\.absoluteString)
    check(posters.first == "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg" && posters.last?.hasSuffix("hqdefault.jpg") == true,
          "the larger poster is tried first, the given one last", "got \(posters)")

    let post = Data(#"""
    {"url":"https://x.com/jack/status/20","author_name":"jack","provider_name":"X","type":"rich",
     "html":"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">just setting up my &amp; twttr</p>&mdash; jack (@jack) <a href=\"https://x.com/jack/status/20\">March 21, 2006</a></blockquote>"}
    """#.utf8)
    let postMeta = LinkMetadata.parseOEmbed(post)
    check(postMeta?.title == nil && postMeta?.author == "jack" && postMeta?.description == "just setting up my & twttr",
          "a post's text comes out of its widget HTML, entities decoded", "got \(String(describing: postMeta))")
    check(LinkMetadata.parseOEmbed(Data(#"{"type":"rich","provider_name":"Threads"}"#.utf8)) == nil, "a reply with nothing to show is nothing")
    check(LinkMetadata.parseOEmbed(Data("not json".utf8)) == nil, "garbage is nothing")

    let html = """
    <html><head><title>Fallback &lt;title&gt;</title>
    <meta property="og:title" content="Attention Is All You Need" />
    <meta name="description" content="Plain description">
    <meta property='og:description' content='The dominant &quot;sequence&quot; models'>
    <meta property="og:site_name" content="arXiv.org" />
    <meta property="og:image" content="/static/arxiv-logo-fb.png" />
    <link rel="alternate" type="application/json+oembed" href="https://example.org/wp-json/oembed/1.0/embed?url=https%3A%2F%2Fexample.org%2F" />
    </head><body></body></html>
    """
    let (page, discovered) = LinkMetadata.parseHTML(html, at: URL(string: "https://arxiv.org/abs/1706.03762")!)
    check(page.title == "Attention Is All You Need", "og:title wins over the title tag", "got \(String(describing: page.title))")
    check(page.description == "The dominant \"sequence\" models", "og:description over the plain one; single quotes and entities read", "got \(String(describing: page.description))")
    check(page.provider == "arXiv.org", "the site's own name")
    check(page.thumbnail == "https://arxiv.org/static/arxiv-logo-fb.png", "a relative picture resolves against the page", "got \(String(describing: page.thumbnail))")
    check(discovered?.absoluteString.hasPrefix("https://example.org/wp-json/oembed") == true, "the oEmbed discovery link is found")
    let bare = LinkMetadata.parseHTML("<html><head><title>Only a  title\n</title></head></html>", at: URL(string: "https://a.b/")!)
    check(bare.meta.title == "Only a title" && bare.oembed == nil, "the title tag is the fallback, whitespace folded", "got \(String(describing: bare.meta.title))")
    let merged = LinkMeta(title: "kept").filled(from: LinkMeta(title: "not this", author: "added"))
    check(merged.title == "kept" && merged.author == "added", "filling adds what is missing and keeps what is there")

    let icons = LinkMetadata.parseIcons("""
    <link rel="icon" type="image/png" sizes="32x32" href="/icons/favicon-32x32.png">
    <link rel="shortcut icon" href="/favicon.ico">
    <link rel="mask-icon" href="/icons/safari-pinned-tab.svg" color="#5bbad5">
    <link rel="apple-touch-icon" sizes="180x180" href="/icons/apple-touch-icon.png">
    <link rel="icon" sizes="96x96" href="https://cdn.example.org/favicon_96.png">
    <link rel="stylesheet" href="/style.css">
    """, at: URL(string: "https://arxiv.org/abs/1")!).map(\.absoluteString)
    check(icons == ["https://arxiv.org/icons/apple-touch-icon.png", "https://cdn.example.org/favicon_96.png",
                    "https://arxiv.org/icons/favicon-32x32.png", "https://arxiv.org/favicon.ico"],
          "icons rank touch icons first, then by size; mask icons and stylesheets are not icons", "got \(icons)")
    let fallbacks = LinkMetadata.iconCandidates(declared: [], host: "x.com").map(\.absoluteString)
    check(fallbacks == ["https://x.com/apple-touch-icon.png", "https://x.com/favicon.ico"], "a host that declares nothing is asked at the conventional addresses")
    check(LinkKind.x(id: "20").handle(in: URL(string: "https://x.com/jack/status/20")!) == "@jack"
          && LinkKind.threads(path: "@zuck/post/C").handle(in: URL(string: "https://www.threads.com/@zuck/post/C")!) == "@zuck"
          && LinkKind.x(id: "1").handle(in: URL(string: "https://x.com/i/web/status/1")!) == nil
          && LinkKind.web.handle(in: URL(string: "https://a.b/@c")!) == nil,
          "a post's author is read off its address; a page has no handle")

    if case .html(let wrapper) = LinkEmbed.page(for: URL(string: "https://youtu.be/dQw4w9WgXcQ")!, kind: .youtube(id: "dQw4w9WgXcQ"), dark: false) {
        check(wrapper.contains("youtube-nocookie.com") && wrapper.contains("videoId:'dQw4w9WgXcQ'") && wrapper.contains("iframe_api"),
              "a video is wrapped in a page that carries the player API")
    } else {
        check(false, "a video embed is a wrapper page")
    }
    check(LinkEmbed.base.scheme == "https", "the wrapper's origin is an https page, the referrer the player wants")
    check(LinkEmbed.page(for: URL(string: "https://www.threads.net/@zuck/post/CuZsgfWLyiI")!, kind: .threads(path: "@zuck/post/CuZsgfWLyiI"), dark: false)
          == .url(URL(string: "https://www.threads.com/@zuck/post/CuZsgfWLyiI/embed")!), "a Threads post embeds by its own embed page")
    check(LinkEmbed.page(for: URL(string: "https://www.pinterest.com/pin/9/")!, kind: .pinterest(id: "9"), dark: false)
          == .url(URL(string: "https://assets.pinterest.com/ext/embed.html?id=9")!), "a Pin by its embed page")
    let site = URL(string: "https://arxiv.org/abs/1706.03762")!
    check(LinkEmbed.page(for: site, kind: .web, dark: false) == .url(site), "a page is itself")
    check(LinkMetadata.oembedEndpoint(for: site, kind: .web) == nil, "the open web has no fixed oEmbed endpoint")
    check(LinkMetadata.oembedEndpoint(for: URL(string: "https://x.com/jack/status/20")!, kind: .x(id: "20"))?.absoluteString
          == "https://publish.x.com/oembed?dnt=true&omit_script=true&url=https%3A%2F%2Fx.com%2Fjack%2Fstatus%2F20",
          "the address is percent-encoded into the endpoint")
}

@MainActor func linkStoreTests() {
    print("\n— Link cards in the store —")
    let root = scratch.appendingPathComponent("links")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "alex-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.viewSize = CGSize(width: 1200, height: 800)
    let video = store.addLink("https://youtu.be/dQw4w9WgXcQ", at: nil)
    check(video?.kind == .link && video?.url == "https://youtu.be/dQw4w9WgXcQ", "a link card carries its address")
    check(video?.width == 320 && video?.height == 234, "and takes its kind's size", "got \(String(describing: video?.frame))")
    check(video != nil && store.selection == [video!.id], "the new card is selected")
    check(store.addLink("not a link", at: nil) == nil && store.document.nodes.count == 1, "no card for something that is not an address")
    check(store.addLink("example.com/page", at: CGPoint(x: 10, y: 20))?.url == "https://example.com/page", "a bare host is given https")
    store.importFiles([URL(string: "https://x.com/jack/status/20")!], at: CGPoint(x: 50, y: 60))
    let post = store.document.nodes.first { $0.url == "https://x.com/jack/status/20" }
    check(post != nil && post?.x == 50 && post?.y == 60 && store.trouble == nil,
          "a web address dropped on the desk is a link card where it landed, not a failed copy",
          "got \(String(describing: post)) trouble=\(String(describing: store.trouble))")
    let onDisk = try! CanvasDocument.decode(Data(contentsOf: root.appendingPathComponent("links.canvas")))
    check(onDisk.nodes.filter { $0.kind == .link }.count == 3, "link cards are in the file", "got \(onDisk.nodes.count)")
    store.reveal("https://x.com/jack/status/20")
    check(post != nil && store.selection == [post!.id] && store.focusRequest == post!.id, "reveal finds a link card by its address")
    check(store.selectionHasPanel, "one link card selected gives the sheet something to show")
    store.selection = Set(store.document.nodes.map(\.id))
    check(!store.selectionHasPanel && store.panelNode == nil,
          "several selected give it nothing: the sheet opens for one card")
}

MainActor.assumeIsolated { linkStoreTests() }

@MainActor func pastedImageTests() {
    print("\n— Pasted images —")
    let wide = Placement.size(forImage: CGSize(width: 1600, height: 900))
    check(wide == CGSize(width: 320, height: 180), "a picture's card keeps its shape at a card's width", "got \(wide)")
    check(Placement.size(forImage: CGSize(width: 4000, height: 100)).height == 120, "a strip is kept tall enough to grab")
    check(Placement.size(forImage: CGSize(width: 1170, height: 2532)).height == 640, "a phone screenshot stops at a page")
    check(Placement.size(forImage: .zero) == Placement.cardSize, "a picture with no size gets a card")
    let when = DateComponents(calendar: Calendar.current, year: 2026, month: 9, day: 29, hour: 14, minute: 32).date!
    check(Placement.pastedImageName(at: when) { _ in false } == "Pasted image 2026-09-29 14.32.png", "named for the minute it was pasted")
    check(Placement.pastedImageName(at: when) { $0 == "Pasted image 2026-09-29 14.32.png" } == "Pasted image 2026-09-29 14.32 2.png",
          "and numbered when the minute is taken")

    let root = scratch.appendingPathComponent("pasted")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "alex-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.viewSize = CGSize(width: 1200, height: 800)
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let first = store.pasteImage(png: png, pixels: CGSize(width: 800, height: 600), now: when)
    check(first?.file == "Pasted image 2026-09-29 14.32.png", "a pasted picture is a file card", "got \(String(describing: first?.file))")
    check(first?.width == 320 && first?.height == 240, "in the picture's shape", "got \(String(describing: first?.frame))")
    check(first != nil && store.selection == [first!.id], "and selected")
    check((try? Data(contentsOf: root.appendingPathComponent("Pasted image 2026-09-29 14.32.png"))) == png,
          "the bytes are on disk as they came")
    let second = store.pasteImage(png: png, pixels: CGSize(width: 800, height: 600), now: when)
    check(second?.file == "Pasted image 2026-09-29 14.32 2.png" && second?.id != first?.id,
          "a second paste in the same minute is its own file", "got \(String(describing: second?.file))")
    check(store.document.nodes.filter { $0.file?.hasPrefix("Pasted image") == true }.count == 2, "both are on the canvas")
}

MainActor.assumeIsolated { pastedImageTests() }

print("\n— Resize grips —")
do {
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    let floor = CGSize(width: 160, height: 80)

    let wider = Grip.right.resizing(frame, by: CGSize(width: 50, height: 0), scale: 1, floor: floor)
    check(wider == CGRect(x: 100, y: 100, width: 350, height: 200), "the right edge moves, the left stays", "got \(wider)")

    let left = Grip.left.resizing(frame, by: CGSize(width: -50, height: 0), scale: 1, floor: floor)
    check(left == CGRect(x: 50, y: 100, width: 350, height: 200), "dragging left grows leftward: the far edge is the anchor", "got \(left)")

    let up = Grip.top.resizing(frame, by: CGSize(width: 0, height: -40), scale: 1, floor: floor)
    check(up == CGRect(x: 100, y: 60, width: 300, height: 240), "the top edge moves, the bottom stays", "got \(up)")

    let corner = Grip.topLeft.resizing(frame, by: CGSize(width: -20, height: -30), scale: 1, floor: floor)
    check(corner == CGRect(x: 80, y: 70, width: 320, height: 230), "a corner moves both of its edges", "got \(corner)")

    // Half the zoom, twice the world for the same pointer travel.
    let zoomed = Grip.right.resizing(frame, by: CGSize(width: 50, height: 0), scale: 0.5, floor: floor)
    check(zoomed.width == 400, "the drag is read in screen points and applied in world ones", "got \(zoomed.width)")

    let squashed = Grip.left.resizing(frame, by: CGSize(width: 500, height: 0), scale: 1, floor: floor)
    check(squashed.width == 160, "the floor holds", "got \(squashed.width)")
    check(squashed.maxX == frame.maxX, "and the anchored edge is still where it was", "got \(squashed.maxX)")

    let none = Grip.bottom.resizing(frame, by: CGSize(width: 90, height: 10), scale: 1, floor: floor)
    check(none.width == 300 && none.origin == frame.origin, "an edge grip leaves the other axis alone", "got \(none)")

    check(Grip.allCases.count == 8 && Grip.allCases.filter(\.isCorner).count == 4,
          "four corners and four sides")
    check(Grip.allCases.prefix(4).allSatisfy { !$0.isCorner },
          "the sides are declared first, so a corner wins the ground they share")

    // ⇧ keeps the proportions (revision 35): the axis the pointer has moved
    // further along leads, the other follows, and a side grows about its middle.
    func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01
            && abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
    }
    let held = Grip.right.resizing(frame, by: CGSize(width: 150, height: 0), scale: 1, floor: floor, proportional: true)
    check(near(held, CGRect(x: 100, y: 50, width: 450, height: 300)),
          "a side dragged with ⇧ scales the other axis about its middle", "got \(held)")
    let tall = Grip.top.resizing(frame, by: CGSize(width: 0, height: -100), scale: 1, floor: floor, proportional: true)
    check(near(tall, CGRect(x: 25, y: 0, width: 450, height: 300)),
          "from the top too: the bottom anchors and the width is centred", "got \(tall)")
    let led = Grip.bottomRight.resizing(frame, by: CGSize(width: 60, height: 0), scale: 1, floor: floor, proportional: true)
    check(near(led, CGRect(x: 100, y: 100, width: 360, height: 240)),
          "a corner dragged straight out keeps the corner under the pointer; the height follows", "got \(led)")
    let anchored = Grip.topLeft.resizing(frame, by: CGSize(width: -30, height: -10), scale: 1, floor: floor, proportional: true)
    check(near(anchored, CGRect(x: 70, y: 80, width: 330, height: 220)),
          "the axis moved further along, in the box's proportions, leads; the far corner anchors", "got \(anchored)")
    let inward = Grip.bottomRight.resizing(frame, by: CGSize(width: 0, height: -100), scale: 1, floor: floor, proportional: true)
    check(near(inward, CGRect(x: 100, y: 100, width: 160, height: 160 * 200 / 300.0)),
          "a drag inward shrinks, and the floor holds on both axes in proportion", "got \(inward)")
    let half = Grip.bottomRight.resizing(frame, by: CGSize(width: 30, height: 0), scale: 0.5, floor: floor, proportional: true)
    check(near(half, led), "the travel is read in screen points at the drag's zoom", "got \(half)")
    let free = Grip.bottomRight.resizing(frame, by: CGSize(width: 60, height: 0), scale: 1, floor: floor)
    check(free == CGRect(x: 100, y: 100, width: 360, height: 200), "without ⇧ the other axis is left alone", "got \(free)")
}

print("\n— Connector sides —")
do {
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    func side(_ x: CGFloat, _ y: CGFloat) -> CanvasSide? {
        CanvasSide.near(CGPoint(x: x, y: y), frame, inside: 16, outside: 24)
    }
    check(side(250, 90) == .top && side(250, 110) == .top, "just outside or inside the top edge is the top's")
    check(side(250, 130) == nil, "deeper inside the block is no side's")
    check(side(250, 70) == nil, "and so is farther off than the dot reaches")
    check(side(390, 200) == .right && side(90, 200) == .left && side(250, 310) == .bottom,
          "each side has its band", "got \(String(describing: side(390, 200))) \(String(describing: side(90, 200))) \(String(describing: side(250, 310)))")
    check(side(105, 105) == nil && side(390, 90) == nil, "the corners are the resize grips'")
    check(side(118, 90) == .top, "the band begins where the corner ends")
    let small = CGRect(x: 0, y: 0, width: 20, height: 20)
    check(CanvasSide.near(CGPoint(x: 10, y: -5), small, inside: 16, outside: 24) == .top,
          "a block narrower than two corners keeps a band between them")
    check(CanvasSide.near(CGPoint(x: 2, y: -5), small, inside: 16, outside: 24) == nil,
          "and a quarter of its width at each end for the corners")
}

print("\n— Proportions under ⇧ —")
do {
    func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 }
    let origin = CGPoint(x: 100, y: 100)
    check(near(Proportion.square(from: origin, to: CGPoint(x: 300, y: 220)), CGPoint(x: 300, y: 300)),
          "a square takes the drag's longer side")
    check(near(Proportion.square(from: origin, to: CGPoint(x: 60, y: 110)), CGPoint(x: 60, y: 140)),
          "and grows the way the pointer went, left or up included")
    let level = Proportion.stepped(from: origin, to: CGPoint(x: 300, y: 110))
    check(abs(level.y - 100) < 0.01 && abs(level.x - (100 + hypot(200, 10))) < 0.01,
          "a line a few degrees off level snaps level, its length kept", "got \(level)")
    let plumb = Proportion.stepped(from: origin, to: CGPoint(x: 105, y: -50))
    check(abs(plumb.x - 100) < 0.01 && plumb.y < 100, "one near upright snaps upright", "got \(plumb)")
    let diagonal = Proportion.stepped(from: origin, to: CGPoint(x: 200, y: 195))
    check(abs((diagonal.x - 100) - (diagonal.y - 100)) < 0.01, "near 45° is 45°", "got \(diagonal)")
    let fifteen = Proportion.stepped(from: origin, to: CGPoint(x: 200, y: 130))
    check(abs(atan2(fifteen.y - 100, fifteen.x - 100) - Proportion.angleStep) < 0.0001,
          "the steps are 15°, Figma's and Excalidraw's", "got \(fifteen)")
    check(Proportion.stepped(from: origin, to: origin) == origin, "no drag, no angle to snap")
}

// The camera (revision 25): what is culled and at what detail changes
// only now and then, so a pan does not rebuild the desk.
@MainActor func cameraTests() {
    print("\n— the camera")
    let size = CGSize(width: 1000, height: 600)
    let start = Viewport(offset: .zero, scale: 1)
    let first = Camera.cull(.infinite, old: start, new: start, in: size)
    check(first.contains(start.visibleWorld(in: size)) && first != .infinite,
          "the first cut holds what shows, and a margin", "got \(first)")
    var nudged = start
    nudged.pan(by: CGPoint(x: -40, y: 20))
    check(Camera.cull(first, old: start, new: nudged, in: size) == first,
          "a small pan inside the cut changes nothing")
    var far = start
    far.pan(by: CGPoint(x: -5000, y: 0))
    let moved = Camera.cull(first, old: start, new: far, in: size)
    check(moved != first && moved.contains(far.visibleWorld(in: size)),
          "a pan past the cut recuts round the new view", "got \(moved)")
    var closer = start
    closer.zoom(by: 8, around: CGPoint(x: 500, y: 300))
    check(Camera.cull(first, old: start, new: closer, in: size) != first,
          "zoomed far in, a cut sixteen views wide is recut")
    check(Camera.cull(first, old: start, new: start, in: .zero) == .infinite,
          "with no desk yet, everything is built")

    check(Camera.detail(for: 1) == 1, "actual size is its own step", "got \(Camera.detail(for: 1))")
    check(Camera.detail(for: 0.8) >= 0.8 && Camera.detail(for: 0.8) < 0.8 * 1.415,
          "a zoom rounds up to within a step of √2", "got \(Camera.detail(for: 0.8))")
    check(Camera.detail(for: 0.9) == Camera.detail(for: 0.95),
          "zooms inside one step share it")
    check(Camera.detail(for: 100) == Viewport.maxScale, "and the step stops at the largest zoom")

    // The store follows the camera without being told.
    let store = CanvasStore(vault: Vault())
    store.viewSize = size
    store.viewport = Viewport(offset: .zero, scale: 0.5)
    check(store.detail == Camera.detail(for: 0.5), "the store's detail follows the camera", "got \(store.detail)")
    check(store.culled.contains(store.viewport.visibleWorld(in: size)), "and so does its cut")
}
MainActor.assumeIsolated { cameraTests() }

@MainActor func styleTests() {
    print("\n— Style panel (revision 39) —")
    let root = scratch.appendingPathComponent("style")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "alex-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.viewSize = CGSize(width: 1200, height: 800)
    func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    func node(_ id: String) -> CanvasNode { store.document.node(id)! }
    let box = store.draw(.rectangle, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100))!
    tick()
    let line = store.draw(.arrow, from: CGPoint(x: 0, y: 300), to: CGPoint(x: 200, y: 300))!
    tick()
    check(node(box.id).dashed && !node(line.id).dashed, "a box is drawn dashed, a line solid")
    store.setDashed([box.id], false)
    tick()
    check(node(box.id).extra["x-dashed"] == nil, "a solid box writes no x-dashed")
    let sticky = store.addSticky(at: CGPoint(x: 500, y: 500))
    tick()
    store.setDashed([box.id], true)
    tick()

    let both = StyleScope([node(box.id), node(line.id)])
    check(both.stroke && !both.fill && !both.arrowheads && !both.size && !both.font,
          "a box and a line share stroke alone")
    check(both.dashed == nil, "a dashed box and a solid line agree on nothing")
    check(both.order && both.duplicable && !both.foldable, "both can be ordered and duplicated, not folded")
    let one = StyleScope([node(line.id)])
    check(one.arrowheads && one.fromArrow == false && one.toArrow == true && !one.font && !one.size,
          "a line takes arrowheads and no words")
    let words = StyleScope([node(sticky.id)])
    check(words.font && words.size && words.family == .handDrawn && words.textSize == .medium && !words.stroke,
          "a sticky takes face and size, no stroke")
    check(words.colourShared && words.colour == "3", "a sticky's colour is read")
    check(StyleScope([]).isEmpty && !StyleScope([]).order, "an empty selection takes nothing")

    store.setLineEnds([line.id, box.id], from: true)
    tick()
    check(node(line.id).lineFromEnd == "arrow" && node(box.id).lineFromEnd == nil,
          "arrowheads over a selection touch only its lines")
    let ids = store.document.nodes.map(\.id)
    store.sendToBack([sticky.id])
    tick()
    check(store.document.nodes.first?.id == sticky.id, "send to back puts the node first in the file")
    store.bringToFront([box.id])
    tick()
    check(store.document.nodes.last?.id == box.id && Set(store.document.nodes.map(\.id)) == Set(ids),
          "bring to front puts it last and loses nothing")
    store.duplicate([box.id])
    tick()
    let copy = store.document.nodes.last!
    check(store.document.nodes.count == ids.count + 1 && copy.id != box.id && copy.shape == .rectangle && copy.dashed
          && copy.x == node(box.id).x + Double(ShapeMetrics.duplicateStep) && store.selection == [copy.id],
          "a duplicate is a new node a step away with the style, and is the selection",
          "got \(copy.frame) selection \(store.selection)")
}
MainActor.assumeIsolated { styleTests() }

// The tools' keys (revision 40): one bare key per tool, changed in
// Settings, kept in UserDefaults, refused rather than swapped.
@MainActor func toolKeyTests() {
    print("\n— Tool keys —")
    typealias Tool = CanvasStore.Tool
    let suite = "alex-tool-keys-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let keys = ToolKeys(defaults: defaults)
    check(Tool.allCases.count == 8 && Set(Tool.allCases.map(\.id)).count == 8, "eight tools, each with its own id")
    check(Set(Tool.allCases.map(\.defaultKey)).count == 8, "eight different default keys")
    check(keys.isDefault && keys.cap(for: .select) == "V" && keys.cap(for: .draw(.ellipse)) == "O"
          && keys.cap(for: .sticky) == "S",
          "the defaults are Figma's and Excalidraw's", "got \(keys.keys)")
    check(keys.tool(for: "R") == .draw(.rectangle) && keys.tool(for: "r") == .draw(.rectangle),
          "a key picks its tool whatever its case")
    check(keys.tool(for: "x") == nil && keys.tool(for: "rr") == nil, "an unbound key and a word pick nothing")

    check(keys.set("2", for: .draw(.rectangle)) == nil && keys.cap(for: .draw(.rectangle)) == "2"
          && keys.tool(for: "2") == .draw(.rectangle) && keys.tool(for: "r") == nil,
          "a digit can be a tool's key, and the old key is free", "got \(keys.keys)")
    check(keys.set("R", for: .draw(.diamond)) == nil && keys.key(for: .draw(.diamond)) == "r",
          "a key is kept lower-case whatever was typed")
    check(keys.set("v", for: .text) == "V picks Select already." && keys.cap(for: .text) == "T",
          "a key another tool holds is refused in a sentence, and nothing changes",
          "got \(String(describing: keys.set("v", for: .text)))")
    check(keys.set("v", for: .select) == nil, "a tool may be given the key it has")
    check(keys.problem(with: "-", for: .text) != nil && keys.set("é", for: .text) != nil && keys.cap(for: .text) == "T",
          "punctuation and accented letters are not keys")
    check(!ToolKeys.accepts("⌘") && ToolKeys.accepts("q") && ToolKeys.accepts("0"), "a key is an ASCII letter or digit")
    check(keys.set(nil, for: .sticky) == nil && keys.key(for: .sticky) == nil && keys.tool(for: "s") == nil,
          "a tool can have no key")
    check(!keys.isDefault, "and the set is no longer the default")

    let again = ToolKeys(defaults: defaults)
    check(again.cap(for: .draw(.rectangle)) == "2" && again.cap(for: .draw(.diamond)) == "R"
          && again.key(for: .sticky) == nil && again.cap(for: .select) == "V",
          "the keys come back from UserDefaults, a cleared one cleared, an untouched one its default",
          "got \(again.keys)")
    let stored = defaults.dictionary(forKey: ToolKeys.defaultsKey) as? [String: String]
    check(stored == ["rectangle": "2", "diamond": "r", "sticky": ""],
          "only what differs from the default is written", "got \(String(describing: stored))")

    again.reset()
    check(again.isDefault && defaults.object(forKey: ToolKeys.defaultsKey) == nil,
          "reset puts the defaults back and removes the key")

    defaults.set(["text": "ab", "line": "⌘", "select": ""], forKey: ToolKeys.defaultsKey)
    let odd = ToolKeys(defaults: defaults)
    check(odd.cap(for: .text) == "T" && odd.cap(for: .draw(.line)) == "L" && odd.key(for: .select) == nil,
          "a stored value that is not one key leaves the default; an empty one is cleared", "got \(odd.keys)")
    check(odd.tool(for: "İ") == nil && odd.set("İ", for: .text) != nil && odd.cap(for: .text) == "T",
          "a letter whose lower case grows neither traps nor binds")
    defaults.removeObject(forKey: ToolKeys.defaultsKey)

    check(ToolKeys.caps("V") == ["V"] && ToolKeys.caps("⌘N") == ["⌘", "N"]
          && ToolKeys.caps("⌘⇧N") == ["⌘", "⇧", "N"] && ToolKeys.caps("⌘-") == ["⌘", "-"],
          "a shortcut reads as one cap per key")

    // The press itself: Select and a shape are taken up, Text and Sticky
    // note toggle.
    let store = CanvasStore(vault: Vault())
    store.pressTool(.text)
    check(store.tool == .text, "T takes up Text")
    store.pressTool(.text)
    check(store.tool == .select, "T again puts it down")
    store.pressTool(.draw(.arrow))
    store.pressTool(.draw(.arrow))
    check(store.tool == .draw(.arrow) && store.lastDrawTool == .arrow, "a shape's key pressed twice keeps the shape")
    store.pressTool(.select)
    check(store.tool == .select, "V selects")
}
MainActor.assumeIsolated { toolKeyTests() }

@MainActor func clipTests() {
    print("\n— Copy and paste (revision 48) —")
    check(CanvasClip.copyName(of: "photo.png") { _ in false } == "photo 2.png", "a copied picture is numbered")
    check(CanvasClip.copyName(of: "photo 2.png") { _ in false } == "photo 3.png", "a numbered one counts on")
    check(CanvasClip.copyName(of: "photo.png") { $0 == "photo 2.png" } == "photo 3.png", "past a name taken")

    let root = scratch.appendingPathComponent("clip")
    try! fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    try! png.write(to: root.appendingPathComponent("pic.png"))
    try! "# Note".write(to: root.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
    try! "# A".write(to: root.appendingPathComponent("sub/a.md"), atomically: true, encoding: .utf8)
    let defaults = UserDefaults(suiteName: "alex-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.viewSize = CGSize(width: 1200, height: 800)
    func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }

    let sticky = store.addSticky(at: store.viewport.toWorld(CGPoint(x: 100, y: 100)))
    store.setText(sticky.id, "hello")
    tick()
    let link = store.addLink("https://example.com", at: store.viewport.toWorld(CGPoint(x: 500, y: 100)))!
    tick()
    let edge = store.connect(sticky.id, link.id)
    tick()
    let clip = store.clip([sticky.id, link.id])!
    check(clip.nodes.count == 2 && clip.edges == [edge], "a clip holds the nodes and the edge between them")
    check(clip.plainText == "hello\n\nhttps://example.com", "and their words for another app", "got \(String(describing: clip.plainText))")
    check(CanvasClip(data: clip.data!) == clip, "it goes through the pasteboard as it came")
    let first = store.paste(clip)
    tick()
    let step = Double(ShapeMetrics.duplicateStep)
    let firstSticky = first.first { $0.kind == .text }
    check(first.count == 2 && firstSticky?.text == "hello" && firstSticky?.id != sticky.id
          && firstSticky?.x == sticky.x + step,
          "a paste is a copy a step down and right", "got \(first.map(\.frame))")
    check(store.selection == Set(first.map(\.id)), "and becomes the selection")
    let copiedEdge = store.document.edges.first { first.map(\.id).contains($0.fromNode) }
    check(copiedEdge != nil && copiedEdge?.id != edge.id && first.map(\.id).contains(copiedEdge!.toNode),
          "the edge follows the copies")
    let second = store.paste(clip)
    tick()
    check(second.first { $0.kind == .text }?.x == sticky.x + 2 * step, "a second paste steps on again")
    store.undoManager?.undo()
    tick()

    let section = store.document.nodes.first { Folders.folder(of: $0) == "sub" }
    let inner = store.node(forFile: "sub/a.md")
    check(section != nil && inner != nil, "Home holds the folder's section and its note")
    if let section, let inner {
        let held = store.clip([section.id])!
        check(held.nodes.contains { $0.id == inner.id }, "a section's clip holds what it holds")
        let back = store.paste(held)
        tick()
        check(back.count == 1 && back[0].kind == .group && Folders.folder(of: back[0]) == nil,
              "pasted beside it, the section is a plain one and the note stays single",
              "got \(back.map { ($0.kind, $0.file ?? "") })")
        store.undoManager?.undo()
        tick()
        store.remove([section.id])
        tick()
        let cut = store.paste(held)
        tick()
        check(cut.contains { Folders.folder(of: $0) == "sub" } && cut.contains { $0.file == "sub/a.md" },
              "cut and pasted, the folder's section comes back with its note",
              "got \(cut.map { ($0.kind, $0.file ?? "") })")
    }

    if let picture = store.node(forFile: "pic.png"), let note = store.node(forFile: "note.md") {
        let pasted = store.paste(store.clip([picture.id, note.id])!)
        tick()
        check(pasted.count == 1 && pasted[0].file == "pic 2.png", "a picture is copied to a file of its own, a note is not doubled",
              "got \(pasted.map { $0.file ?? "" })")
        check((try? Data(contentsOf: root.appendingPathComponent("pic 2.png"))) == png, "the copy's bytes are on disk")
    } else {
        check(false, "Home holds the picture and the note")
    }
}

MainActor.assumeIsolated { clipTests() }

@MainActor func undoDeltaTests() {
    print("\n— Undo by delta, writing, echoes (revision 52) —")
    func box(_ id: String, x: CGFloat, text: String = "") -> CanvasNode {
        var node = CanvasNode(kind: .text, frame: CGRect(x: x, y: 0, width: 100, height: 60), text: text)
        node.id = id
        return node
    }
    var a = CanvasDocument()
    a.nodes = [box("n1", x: 0), box("n2", x: 200), box("n3", x: 400)]
    var b = a
    b.nodes[1].x = 250
    b.nodes.remove(at: 0)
    b.nodes.append(box("n4", x: 600))
    let delta = CanvasDelta(from: a, to: b)
    check(Set(delta.nodes.keys) == ["n1", "n2", "n4"] && delta.nodeOrder == nil,
          "a delta names what was added, changed and removed, and no reorder", "got \(delta.nodes.keys.sorted())")
    check(delta.apply(to: a) == b && delta.inverse.apply(to: b) == a, "it goes forward and back")
    var foreign = b
    foreign.nodes.append(box("door", x: 900))
    let undone = delta.inverse.apply(to: foreign)
    check(undone.nodes.map(\.id) == ["n1", "n2", "n3", "door"] && undone.node("n2")?.x == 200,
          "undone on a canvas someone added to since, it keeps their node and puts n1 back where it stood",
          "got \(undone.nodes.map(\.id))")
    var reordered = a
    reordered.nodes = [a.nodes[2], a.nodes[0], a.nodes[1]]
    let order = CanvasDelta(from: a, to: reordered)
    check(order.nodeOrder != nil && order.inverse.apply(to: reordered) == a, "a reorder is undone")
    check(CanvasDelta(from: a, to: a).isEmpty, "no change, no delta")

    let root = scratch.appendingPathComponent("undo")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    try! "# Card".write(to: root.appendingPathComponent("card.md"), atomically: true, encoding: .utf8)
    let defaults = UserDefaults(suiteName: "alex-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.viewSize = CGSize(width: 1200, height: 800)
    let undo = UndoManager()
    store.undoManager = undo
    func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    let canvasURL = root.appendingPathComponent("undo.canvas")

    guard let card = store.node(forFile: "card.md") else { return check(false, "Home holds the card") }
    store.move([card.id], by: CGSize(width: 40, height: 0))
    tick()
    // The door adds a node on disk, as Claude would.
    var onDisk = try! CanvasDocument.decode(Data(contentsOf: canvasURL))
    onDisk.nodes.append(box("fromDoor", x: 2000, text: "from Claude"))
    try! onDisk.encode().write(to: canvasURL, options: .atomic)
    store.noticeDoorWrite(to: "undo.canvas")
    tick()
    undo.undo()
    tick()
    let afterUndo = try! CanvasDocument.decode(Data(contentsOf: canvasURL))
    check(afterUndo.node(card.id)?.x == card.x && afterUndo.node("fromDoor") != nil,
          "⌘Z after a door write takes back the move and keeps the door's node, on disk",
          "got x \(String(describing: afterUndo.node(card.id)?.x)), door \(afterUndo.node("fromDoor") != nil)")
    undo.redo()
    tick()
    check(store.document.node(card.id)?.x == card.x + 40 && store.document.node("fromDoor") != nil, "redo moves it again")

    // One writing, one step: a text box made, written in three pauses, closed.
    while undo.canUndo { undo.undo(); tick() }
    undo.removeAllActions()
    let text = store.addText(from: CGPoint(x: 0, y: 500), to: CGPoint(x: 0, y: 500))
    tick()
    check(!undo.canUndo, "a text box added for writing is no undo step yet")
    store.beginWriting(text.id)
    for words in ["h", "he", "hey"] { store.setText(text.id, words); tick() }
    check(!undo.canUndo, "the pauses while writing are saved, not undo steps")
    check((try! CanvasDocument.decode(Data(contentsOf: canvasURL))).node(text.id)?.text == "hey", "each pause is on disk (D2)")
    store.endWriting(text.id, "hey you")
    tick()
    check(store.document.node(text.id)?.text == "hey you" && undo.canUndo, "the writing ends as one step")
    undo.undo()
    tick()
    check(store.document.node(text.id) == nil && !undo.canUndo, "one ⌘Z takes back the box and its words together")
    undo.redo()
    tick()
    check(store.document.node(text.id)?.text == "hey you", "and redo brings both back")

    // Written again: one step back to what it said.
    store.beginWriting(text.id)
    store.setText(text.id, "hey you two")
    tick()
    store.endWriting(text.id, "hey you two!")
    tick()
    undo.undo()
    tick()
    check(store.document.node(text.id)?.text == "hey you", "writing in an existing box undoes to its old words")

    // Emptied: the box goes; made and left empty: nothing at all.
    store.beginWriting(text.id)
    store.endWriting(text.id, "  ")
    tick()
    check(store.document.node(text.id) == nil, "a text box left empty is taken away")
    undo.undo()
    tick()
    check(store.document.node(text.id)?.text == "hey you", "and ⌘Z brings it back with its words")
    undo.removeAllActions()
    let blank = store.addText(from: CGPoint(x: 0, y: 700), to: CGPoint(x: 0, y: 700))
    tick()
    store.beginWriting(blank.id)
    store.endWriting(blank.id, "")
    tick()
    check(store.document.node(blank.id) == nil && !undo.canUndo, "a text box made and left empty leaves no box and no step")
    let sticky = store.addSticky(at: CGPoint(x: 0, y: 900))
    tick()
    store.beginWriting(sticky.id)
    store.endWriting(sticky.id, "")
    tick()
    check(store.document.node(sticky.id) != nil, "an empty sticky stays: only a text box goes")

    // Echoes judged by what is on disk, not by a clock.
    let generation = vault.generation
    let ours = canvasURL.resolvingSymlinksInPath().path
    store.setText(sticky.id, "ours")
    tick()
    vault.changed([ours])
    check(vault.generation == generation, "the watcher's echo of our own write is ignored")
    var theirs = try! CanvasDocument.decode(Data(contentsOf: canvasURL))
    theirs.nodes.append(box("obsidian", x: 3000, text: "from Obsidian"))
    try! theirs.encode().write(to: canvasURL, options: .atomic)
    vault.changed([ours])
    check(vault.generation == generation + 1, "an outside write a moment after ours is still seen")
}

MainActor.assumeIsolated { undoDeltaTests() }

@MainActor func batchBTests() {
    print("\n— ⌥ resize and ⌥-drag copies (revision 53) —")
    let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
    let floor = CGSize(width: 10, height: 10)
    let wide = Grip.right.resizing(frame, by: CGSize(width: 20, height: 0), scale: 1, floor: floor, fromCentre: true)
    check(wide == CGRect(x: 80, y: 100, width: 240, height: 100), "⌥ on a side grows both sides about the centre", "got \(wide)")
    let corner = Grip.topLeft.resizing(frame, by: CGSize(width: 10, height: 10), scale: 2, floor: floor, fromCentre: true)
    check(corner == CGRect(x: 105, y: 105, width: 190, height: 90), "⌥ on a corner shrinks about the centre, at the drag's zoom", "got \(corner)")
    let both = Grip.bottomRight.resizing(frame, by: CGSize(width: 50, height: 0), scale: 1, floor: floor,
                                        proportional: true, fromCentre: true)
    check(abs(both.midX - frame.midX) < 0.001 && abs(both.midY - frame.midY) < 0.001 && abs(both.width / both.height - 2) < 0.001,
          "⇧⌥ keeps the proportions and the centre", "got \(both)")
    let plain = Grip.right.resizing(frame, by: CGSize(width: 20, height: 0), scale: 1, floor: floor)
    check(plain == CGRect(x: 100, y: 100, width: 220, height: 100), "without ⌥ the far side stays put")

    let root = scratch.appendingPathComponent("batchB")
    try! fm.createDirectory(at: root, withIntermediateDirectories: true)
    let defaults = UserDefaults(suiteName: "alex-tests-\(UUID().uuidString)")!
    let vault = Vault(arguments: [], defaults: defaults)
    vault.open(root)
    let store = CanvasStore(vault: vault)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    store.viewSize = CGSize(width: 1200, height: 800)
    let undo = UndoManager()
    store.undoManager = undo
    func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    let box = store.draw(.rectangle, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100))!
    tick()
    undo.removeAllActions()
    guard let copies = store.beginDuplicateDrag([box.id]), let copy = copies.first else {
        return check(false, "an ⌥-drag copies a shape")
    }
    tick()
    check(store.selection == copies && store.document.node(copy)?.frame == box.frame && !undo.canUndo,
          "the copy lies on the original, is the selection, and is no step yet")
    store.endDuplicateDrag(by: CGSize(width: 300, height: 0))
    tick()
    check(store.document.node(copy)?.x == box.x + 300 && store.document.node(box.id)?.frame == box.frame,
          "the copy moves, the original stays where it was")
    undo.undo()
    tick()
    check(store.document.node(copy) == nil && store.document.nodes.count == 1 && !undo.canUndo,
          "one ⌘Z takes back the copy and its move together")
    check(store.beginDuplicateDrag([]) == nil, "nothing copyable, no copy")
}

MainActor.assumeIsolated { batchBTests() }

print("")
if failures == 0 { print("✓ canvas suite passed") } else { print("✗ \(failures) failure(s)") }
exit(failures == 0 ? 0 : 1)
