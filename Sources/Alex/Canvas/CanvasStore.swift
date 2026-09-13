import Foundation
import Combine
import CoreGraphics

/// The open canvas: which directory, its `.canvas` file, the nodes and
/// edges, the selection and the viewport. Every mutation writes the file
/// first and memory second (D2); the door and the views call the same
/// methods (D6).
@MainActor
final class CanvasStore: ObservableObject {
    let vault: Vault

    @Published private(set) var directory = ""
    @Published private(set) var canvasPath = ""
    @Published private(set) var document = CanvasDocument()
    @Published var selection: Set<String> = []
    @Published var viewport = Viewport()
    @Published private(set) var unplaced: [VaultEntry] = []
    @Published private(set) var trouble: String?
    @Published private(set) var isOpen = false
    /// A node the canvas should pan to and pulse: set by `reveal` and by the
    /// door's `focus`. The canvas view clears it once done.
    @Published var focusRequest: String?
    /// True when a canvas opened with no remembered viewport: the view, which
    /// knows its size, fits the contents and clears this.
    @Published var wantsFit = false
    /// The vault's `canvas.config.json`, reloaded whenever the vault changes.
    @Published private(set) var config = VaultConfig()
    /// The ⌘K panel; the menu sets it, the panel clears it.
    @Published var showSearch = false

    private var previews: [String: (generation: Int, preview: CardPreview)] = [:]
    private var peekCache: [String: (generation: Int, entries: [VaultEntry], count: Int)] = [:]
    private var lastWritten: Data?
    private var openedRoot: URL?
    private var subscriptions: Set<AnyCancellable> = []

    init(vault: Vault) {
        self.vault = vault
        vault.$root
            .sink { [weak self] root in
                Task { @MainActor in self?.vaultChanged(root) }
            }
            .store(in: &subscriptions)
        vault.$generation
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.outsideChange() }
            }
            .store(in: &subscriptions)
    }

    // MARK: - Where

    var title: String { directory.isEmpty ? vault.name : VaultPath.name(of: directory) }

    /// Root first, then each directory on the way down.
    var crumbs: [(name: String, path: String)] {
        var out = [(vault.name, "")]
        var path = ""
        for part in directory.split(separator: "/") {
            path = VaultPath.join(path, String(part))
            out.append((String(part), path))
        }
        return out
    }

    static func canvasFile(for directory: String, vault: Vault) -> String {
        let name = directory.isEmpty ? vault.name : VaultPath.name(of: directory)
        return VaultPath.join(directory, name + ".canvas")
    }

    private func vaultChanged(_ root: URL?) {
        guard root != openedRoot else { return }
        openedRoot = root
        previews.removeAll()
        peekCache.removeAll()
        loadConfig()
        guard let root else {
            isOpen = false
            document = CanvasDocument()
            return
        }
        let remembered = UserDefaults.standard.string(forKey: "openDirectory:" + root.path) ?? ""
        openDirectory(remembered)
    }

    func openDirectory(_ dir: String) {
        guard let root = vault.root else { return }
        openedRoot = root
        let clean = (try? VaultPath.normalise(dir)) ?? ""
        let target = vault.isDirectory(clean) ? clean : ""
        // Already here: keep the viewport and the selection.
        if isOpen, target == directory, canvasPath == Self.canvasFile(for: target, vault: vault) { return }
        saveViewport()
        directory = target
        canvasPath = Self.canvasFile(for: target, vault: vault)
        selection = []
        load(createIfMissing: true)
        if let restored = restoredViewport() { viewport = restored } else { viewport = Viewport(); wantsFit = true }
        isOpen = true
        UserDefaults.standard.set(target, forKey: "openDirectory:" + root.path)
    }

    /// Any `.canvas` file, not only a directory's own.
    func openCanvas(at path: String) {
        guard vault.root != nil, vault.url(for: path) != nil else { return }
        saveViewport()
        directory = VaultPath.parent(of: path)
        canvasPath = path
        selection = []
        load(createIfMissing: false)
        if let restored = restoredViewport() { viewport = restored } else { viewport = Viewport(); wantsFit = true }
        isOpen = true
    }

    func goUp() {
        guard !directory.isEmpty else { return }
        openDirectory(VaultPath.parent(of: directory))
    }

    // MARK: - File

    private func load(createIfMissing: Bool) {
        trouble = nil
        if let url = vault.url(for: canvasPath), FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                document = try CanvasDocument.decode(data)
                lastWritten = data
            } catch {
                trouble = "Couldn't read \(canvasPath): \(error)"
                document = CanvasDocument()
            }
        } else if createIfMissing {
            document = CanvasDocument(nodes: Placement.autoLayout(directoryEntries()))
            save()
        } else {
            document = CanvasDocument()
        }
        refreshUnplaced()
    }

    /// What the open directory holds, minus its own canvas file.
    func directoryEntries() -> [VaultEntry] {
        guard let root = vault.root else { return [] }
        let all = (try? VaultListing.entries(in: directory, root: root)) ?? []
        return all.filter { $0.path != canvasPath }
    }

    func refreshUnplaced() {
        let placed = Set(document.nodes.compactMap(\.file))
        unplaced = directoryEntries().filter { !placed.contains($0.path) }
    }

    func save() {
        do {
            let data = try document.encode()
            lastWritten = data
            try vault.write(data, to: canvasPath)
        } catch {
            trouble = "Couldn't save \(canvasPath): \(error)"
        }
    }

    /// Something outside the app changed the vault: re-read the canvas if
    /// it is not what we last wrote, and forget every cached preview.
    private func outsideChange() {
        previews.removeAll()
        peekCache.removeAll()
        loadConfig()
        if let url = vault.url(for: canvasPath),
           let data = try? Data(contentsOf: url), data != lastWritten,
           let doc = try? CanvasDocument.decode(data) {
            document = doc
            lastWritten = data
            selection = selection.filter { id in doc.nodes.contains { $0.id == id } }
        }
        refreshUnplaced()
        objectWillChange.send()
    }

    /// The door wrote a canvas through the vault (a self-write the watcher
    /// hides): if it is the open one, take it from disk, keeping selection
    /// and viewport; either way the tray may have changed.
    func noticeDoorWrite(to path: String) {
        if path == canvasPath, let url = vault.url(for: path),
           let data = try? Data(contentsOf: url), let doc = try? CanvasDocument.decode(data) {
            document = doc
            lastWritten = data
            selection = selection.filter { id in doc.nodes.contains { $0.id == id } }
        }
        previews.removeAll()
        peekCache.removeAll()
        refreshUnplaced()
    }

    // MARK: - Viewport memory

    private var viewportKey: String {
        "viewport:" + (vault.root?.path ?? "") + ":" + canvasPath
    }

    /// A viewport still waiting for its first fit is not worth remembering.
    func saveViewport() {
        guard isOpen, !wantsFit else { return }
        UserDefaults.standard.set([viewport.offset.x, viewport.offset.y, viewport.scale],
                                  forKey: viewportKey)
    }

    private func restoredViewport() -> Viewport? {
        guard let a = UserDefaults.standard.array(forKey: viewportKey) as? [Double], a.count == 3 else {
            return nil
        }
        return Viewport(offset: CGPoint(x: a[0], y: a[1]), scale: a[2])
    }

    // MARK: - Selection

    var selectedNode: CanvasNode? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return document.node(id)
    }

    func select(_ id: String?) {
        selection = id.map { [$0] } ?? []
    }

    func node(forFile path: String) -> CanvasNode? {
        document.nodes.first { $0.kind == .file && $0.file == path }
    }

    /// The sidebar or search picked a vault path: open the directory that
    /// holds it, select its node, ask the canvas to pan there.
    func reveal(_ rawPath: String) {
        let path = (try? VaultPath.normalise(rawPath)) ?? rawPath
        if vault.isDirectory(path) { openDirectory(path); return }
        let parent = VaultPath.parent(of: path)
        if parent != directory || !isOpen { openDirectory(parent) }
        if let node = node(forFile: path) {
            select(node.id)
            focusRequest = node.id
            // Panning to the card is the point; a fit would zoom it away.
            wantsFit = false
        }
    }

    // MARK: - The vault's views (canvas.config.json)

    func loadConfig() {
        if let url = vault.url(for: VaultConfig.fileName), let data = try? Data(contentsOf: url) {
            config = VaultConfig.decode(data)
        } else {
            config = VaultConfig()
        }
        derivedCache = nil
    }

    /// The rule covering a file card, if any.
    func rule(for node: CanvasNode) -> ViewRule? {
        guard node.kind == .file, let file = node.file, !isDirectoryNode(node) else { return nil }
        return config.rule(for: file)
    }

    /// The card's colour under its rule: the `colorBy` key's value, mapped.
    func tint(for node: CanvasNode) -> (key: String, value: String, color: String)? {
        guard let rule = rule(for: node), let key = rule.colorBy, let file = node.file,
              VaultEntry.Kind.forExtension((file as NSString).pathExtension) == .markdown,
              let value = preview(for: file).frontmatter[key]?.display, !value.isEmpty,
              let color = rule.color(for: value) else { return nil }
        return (key, value, color)
    }

    struct DerivedEdge: Hashable {
        let from: String
        let to: String
    }

    private var derivedCache: (generation: Int, document: CanvasDocument, edges: [DerivedEdge])?

    /// Edges the frontmatter implies: a card whose `edgesFrom` key lists
    /// ids points at the cards whose `idKey` (or file stem) carries them.
    /// Drawn dashed, never stored.
    func derivedEdges() -> [DerivedEdge] {
        if let cached = derivedCache, cached.generation == vault.generation, cached.document == document {
            return cached.edges
        }
        var byID: [String: String] = [:]
        var sources: [(node: CanvasNode, values: [String])] = []
        for node in document.nodes {
            guard let rule = rule(for: node), let file = node.file,
                  VaultEntry.Kind.forExtension((file as NSString).pathExtension) == .markdown else { continue }
            let fm = preview(for: file).frontmatter
            let stem = (VaultPath.name(of: file) as NSString).deletingPathExtension
            byID[stem] = node.id
            if let id = fm[rule.idKey]?.display, !id.isEmpty { byID[id] = node.id }
            if let key = rule.edgesFrom, let value = fm[key] {
                let values: [String]
                switch value {
                case .list(let list): values = list
                default: values = value.display.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }
                sources.append((node, values.filter { !$0.isEmpty }))
            }
        }
        var edges: [DerivedEdge] = []
        for source in sources {
            for value in source.values {
                if let target = byID[value], target != source.node.id {
                    edges.append(DerivedEdge(from: target, to: source.node.id))
                }
            }
        }
        derivedCache = (vault.generation, document, edges)
        return edges
    }

    /// Lay the canvas out by the first rule with a `groupBy` that covers
    /// files here: one labelled group per value, cards in rows inside,
    /// groups stacked. Groups from an earlier arrange by the same key are
    /// replaced; anything the rule does not cover is left where it is.
    @discardableResult
    func arrangeByConfig() -> Bool {
        let cards = document.nodes.filter { $0.kind == .file && !isDirectoryNode($0) }
        guard let rule = config.views.first(where: { rule in
            rule.groupBy != nil && cards.contains { rule.applies(to: $0.file ?? "") }
        }), let key = rule.groupBy else {
            trouble = "No view in \(VaultConfig.fileName) groups the files on this canvas."
            return false
        }
        let matching = cards.filter { rule.applies(to: $0.file ?? "") }
        var buckets: [String: [CanvasNode]] = [:]
        for node in matching {
            let value = preview(for: node.file ?? "").frontmatter[key]?.display ?? ""
            buckets[value.isEmpty ? "other" : value, default: []].append(node)
        }
        let order = buckets.keys.sorted { a, b in
            if let x = Double(a), let y = Double(b) { return x < y }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        let columns = 4
        let card = Placement.cardSize, gap = Placement.cardGap
        let pad: CGFloat = 30, labelRoom: CGFloat = 46
        mutate("Arrange by \(key)") { doc in
            doc.nodes.removeAll { $0.kind == .group && $0.extra["x-arranged-by"]?.string == key }
            var y = Placement.origin.y
            for (i, value) in order.enumerated() {
                let nodes = (buckets[value] ?? []).sorted {
                    ($0.file ?? "").localizedStandardCompare($1.file ?? "") == .orderedAscending
                }
                let rows = (nodes.count + columns - 1) / columns
                let width = CGFloat(min(nodes.count, columns)) * (card.width + gap.width) - gap.width + 2 * pad
                let height = CGFloat(rows) * (card.height + gap.height) - gap.height + 2 * pad + labelRoom
                var group = CanvasNode(kind: .group,
                                       frame: CGRect(x: Placement.origin.x, y: y, width: max(width, 400), height: height),
                                       label: rule.label(for: value))
                group.color = rule.color(for: value) ?? String((i % 6) + 1)
                group.extra["x-arranged-by"] = .string(key)
                // Groups first so they draw behind, in block order.
                doc.nodes.insert(group, at: i)
                for (j, node) in nodes.enumerated() {
                    var moved = node
                    moved.x = Placement.origin.x + pad + CGFloat(j % columns) * (card.width + gap.width)
                    moved.y = y + labelRoom + pad + CGFloat(j / columns) * (card.height + gap.height)
                    doc.update(moved)
                }
                y += height + 60
            }
        }
        wantsFit = true
        return true
    }

    // MARK: - Previews and peeks

    func preview(for path: String) -> CardPreview {
        if let hit = previews[path], hit.generation == vault.generation { return hit.preview }
        let p = CardPreview.make(for: path, vault: vault)
        previews[path] = (vault.generation, p)
        return p
    }

    /// The first few things inside a directory, for the folder's mouth, and
    /// how many there are. Files first, images and notes preferred.
    func peeks(for dir: String) -> (entries: [VaultEntry], count: Int) {
        if let hit = peekCache[dir], hit.generation == vault.generation { return (hit.entries, hit.count) }
        guard let root = vault.root else { return ([], 0) }
        let own = Self.canvasFile(for: dir, vault: vault)
        let all = ((try? VaultListing.entries(in: dir, root: root)) ?? []).filter { $0.path != own }
        let rank: (VaultEntry) -> Int = { e in
            switch e.kind {
            case .image: return 0
            case .markdown: return 1
            case .pdf, .html: return 2
            case .directory: return 4
            default: return 3
            }
        }
        let picked = Array(all.sorted { rank($0) < rank($1) }.prefix(3))
        peekCache[dir] = (vault.generation, picked, all.count)
        return (picked, all.count)
    }

    func isDirectoryNode(_ node: CanvasNode) -> Bool {
        node.kind == .file && node.file.map(vault.isDirectory) == true
    }

    // MARK: - Mutations (every one saves, every one undoes)

    /// The window's undo manager, handed in by the canvas view.
    weak var undoManager: UndoManager?
    /// The canvas view's size, so "zoom in" and "new sticky" from a menu
    /// know where the middle is.
    var viewSize = CGSize.zero

    private func mutate(_ name: String, _ body: (inout CanvasDocument) -> Void) {
        let before = document
        body(&document)
        save()
        refreshUnplaced()
        registerUndo(name, before: before)
    }

    private func registerUndo(_ name: String, before: CanvasDocument) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            let current = store.document
            store.document = before
            store.save()
            store.refreshUnplaced()
            store.selection = store.selection.filter { id in before.nodes.contains { $0.id == id } }
            store.registerUndo(name, before: current)
        }
        undoManager.setActionName(name)
    }

    func setFrame(_ id: String, _ frame: CGRect) {
        mutate("Resize") { doc in
            guard var node = doc.node(id) else { return }
            node.frame = frame
            doc.update(node)
        }
    }

    func move(_ ids: Set<String>, by delta: CGSize) {
        mutate("Move") { doc in
            for id in ids {
                guard var node = doc.node(id) else { continue }
                node.x += delta.width
                node.y += delta.height
                doc.update(node)
            }
        }
    }

    @discardableResult
    func add(_ node: CanvasNode, name: String = "Add") -> CanvasNode {
        mutate(name) { doc in
            if node.kind == .group { doc.nodes.insert(node, at: 0) } else { doc.nodes.append(node) }
        }
        return node
    }

    func update(_ node: CanvasNode, name: String = "Edit") {
        mutate(name) { $0.update(node) }
    }

    func setText(_ id: String, _ text: String) {
        guard var node = document.node(id), node.text != text else { return }
        node.text = text
        update(node, name: "Edit note")
    }

    /// Off the canvas, not off the disk: the file stays and goes back to
    /// the unplaced tray.
    func remove(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        mutate("Remove") { doc in
            doc.nodes.removeAll { ids.contains($0.id) }
            doc.edges.removeAll { ids.contains($0.fromNode) || ids.contains($0.toNode) }
        }
        selection.subtract(ids)
    }

    @discardableResult
    func connect(_ from: String, _ to: String, fromSide: CanvasSide? = nil,
                 toSide: CanvasSide? = nil, label: String? = nil) -> CanvasEdge {
        var edge = CanvasEdge(from: from, to: to, label: label)
        edge.fromSide = fromSide
        edge.toSide = toSide
        mutate("Connect") { $0.edges.append(edge) }
        return edge
    }

    func removeEdge(_ id: String) {
        mutate("Remove edge") { $0.edges.removeAll { $0.id == id } }
    }

    /// Place a vault file on this canvas at a point, or at a free spot
    /// beside `near`, else beside the selection, else below everything.
    @discardableResult
    func place(_ path: String, at point: CGPoint? = nil, near: String? = nil) -> CanvasNode {
        let isDir = vault.isDirectory(path)
        let size = isDir ? Placement.folderSize : Placement.cardSize
        let anchor = near.flatMap { document.node($0)?.frame } ?? selectedNode?.frame
        let origin = point ?? Placement.freeSlot(for: size, in: document, near: anchor)
        let node = CanvasNode(kind: .file, frame: CGRect(origin: origin, size: size), file: path)
        return add(node, name: "Place")
    }

    func placeAllUnplaced() {
        let entries = unplaced
        guard !entries.isEmpty else { return }
        mutate("Place all") { doc in
            var start = doc.bounds.isNull ? Placement.origin : CGPoint(x: Placement.origin.x, y: doc.bounds.maxY + 60)
            for node in Placement.autoLayout(entries) {
                var placed = node
                placed.x += start.x - Placement.origin.x
                placed.y += start.y - Placement.origin.y
                doc.nodes.append(placed)
            }
            start.y += 1
        }
    }

    /// A sticky note. Without a point it lands in the middle of the view.
    @discardableResult
    func addSticky(at world: CGPoint?) -> CanvasNode {
        let size = Placement.textSize
        let origin: CGPoint
        if let world {
            origin = CGPoint(x: world.x - size.width / 2, y: world.y - size.height / 2)
        } else {
            let centre = viewport.toWorld(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
            origin = Placement.freeSlot(for: size, in: document,
                                     near: CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                                                  width: size.width, height: size.height))
        }
        let node = CanvasNode(kind: .text, frame: CGRect(origin: origin, size: size), text: "", color: "3")
        add(node, name: "Add sticky note")
        select(node.id)
        return node
    }

    /// A new Markdown file in the open directory, placed and selected.
    func newNote() {
        var name = "Untitled.md"
        var i = 2
        while vault.exists(VaultPath.join(directory, name)) {
            name = "Untitled \(i).md"
            i += 1
        }
        let path = VaultPath.join(directory, name)
        do {
            try vault.write("# Untitled\n\n", to: path)
        } catch {
            trouble = "Couldn't create \(path): \(error)"
            return
        }
        let node = place(path)
        select(node.id)
        focusRequest = node.id
    }

    /// A group around the selection, labelled, drawn behind it.
    func groupSelection() {
        let ids = selection
        let frames = document.nodes.filter { ids.contains($0.id) }.map(\.frame)
        guard !frames.isEmpty else { return }
        let b = frames.reduce(CGRect.null) { $0.union($1) }
        let frame = CGRect(x: b.minX - 30, y: b.minY - 56, width: b.width + 60, height: b.height + 86)
        let group = CanvasNode(kind: .group, frame: frame, label: "Group")
        add(group, name: "Group")
        select(group.id)
    }

    /// Ids of the non-group nodes whose frames sit inside `frame`: what a
    /// group drags along with it.
    func nodeIDs(inside frame: CGRect) -> Set<String> {
        Set(document.nodes.filter { $0.kind != .group && frame.contains($0.frame) }.map(\.id))
    }

    /// The topmost node under a desk point, groups last.
    func hitTest(_ world: CGPoint, excluding: Set<String> = []) -> CanvasNode? {
        let cards: [CanvasNode] = document.nodes.filter { $0.kind != .group }.reversed()
        let groups: [CanvasNode] = document.nodes.filter { $0.kind == .group }.reversed()
        return (cards + groups).first { !excluding.contains($0.id) && $0.frame.contains(world) }
    }

    /// Files dropped on the desk: a vault file is placed where it landed; a
    /// file from elsewhere is copied into the open directory first.
    func importFiles(_ urls: [URL], at world: CGPoint) {
        var point = world
        for url in urls {
            var path: String
            if let inside = vault.relativePath(of: url) {
                path = inside
            } else {
                var name = url.lastPathComponent
                var i = 2
                while vault.exists(VaultPath.join(directory, name)) {
                    let stem = (url.lastPathComponent as NSString).deletingPathExtension
                    let ext = url.pathExtension
                    name = ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)"
                    i += 1
                }
                path = VaultPath.join(directory, name)
                guard let dest = vault.url(for: path) else { continue }
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    vault.reload()
                } catch {
                    trouble = "Couldn't copy \(url.lastPathComponent): \(error)"
                    continue
                }
            }
            if let existing = node(forFile: path) {
                select(existing.id)
            } else {
                let node = place(path, at: point)
                select(node.id)
            }
            point.x += 40
            point.y += 40
        }
    }

    // MARK: - Zoom from a menu

    private var viewCentre: CGPoint { CGPoint(x: viewSize.width / 2, y: viewSize.height / 2) }

    func zoomIn() { viewport.zoom(by: 1.2, around: viewCentre) }
    func zoomOut() { viewport.zoom(by: 1 / 1.2, around: viewCentre) }
    func actualSize() { viewport.zoom(by: 1 / viewport.scale, around: viewCentre) }
    func fit() { wantsFit = true }
}
