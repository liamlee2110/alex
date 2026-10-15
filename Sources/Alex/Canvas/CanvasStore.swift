import Foundation
import Combine
import CoreGraphics

/// The open canvas: Home, the vault's own, where every folder is a section
/// (D5, revision 20), or any other `.canvas` file; its nodes and edges, the
/// selection and the viewport. Every mutation writes the file first and
/// memory second (D2); the door and the views call the same methods (D6).
@MainActor
final class CanvasStore: ObservableObject {
    let vault: Vault

    @Published private(set) var directory = ""
    @Published private(set) var canvasPath = ""
    @Published private(set) var document = CanvasDocument() {
        // A canvas changed or opened under an open find: its hits again,
        // without moving the camera.
        didSet { if showFind { refreshFind(look: false) } }
    }
    @Published var selection: Set<String> = [] {
        // One file picked is one file open in the panel: what Recents lists.
        didSet {
            if let node = selectedNode, node.kind == .file, let file = node.file { noteRecent(file) }
            if !selection.isEmpty { looseFile = nil }
        }
    }
    /// The files last opened in the panel, newest first (revision 17): the
    /// sidebar's Recents. Remembered per vault, like the viewport, and
    /// pruned of anything that has left the vault.
    @Published private(set) var recents: [String] = []
    static let recentsShown = 5
    static let recentsKept = 20
    /// Pan and zoom live on their own object (revision 25), so a scroll
    /// redraws what is in screen space and nothing that reads the store.
    let camera = Camera()
    var viewport: Viewport {
        get { camera.viewport }
        set { camera.viewport = newValue }
    }
    /// The world rect whose nodes are built, recut only when the view
    /// leaves it (`Camera.cull`).
    @Published private(set) var culled = CGRect.infinite
    /// The zoom in steps of √2 (`Camera.detail`): what a page is drawn at.
    @Published private(set) var detail: CGFloat = 1
    @Published private(set) var unplaced: [VaultEntry] = []
    @Published private(set) var trouble: String?
    @Published private(set) var isOpen = false
    /// A node the canvas should pan to and pulse: set by `reveal` and by the
    /// door's `focus`. The canvas view clears it once done.
    @Published var focusRequest: String?
    /// True when a canvas opened with no remembered viewport: the view, which
    /// knows its size, fits the contents and clears this.
    @Published var wantsFit = false
    /// The world point a remembered viewport was centred on. The store
    /// centres it at once when it knows the desk's size; the view centres
    /// it again whenever the desk changes size, so a canvas remembered in
    /// one window comes back centred in another (decided with Liam,
    /// 2026-09-14).
    @Published var restoredCentre: CGPoint?
    /// A step of zoom asked for by a button or a menu. The view, which
    /// animates the camera, answers it and clears it.
    enum ZoomStep: Equatable { case closer, farther, actualSize }
    @Published var zoomStep: ZoomStep?

    /// What floats over the desk's edges (revision 21): the toolbar strip
    /// across the top, the floating sidebar at the left while the sidebar
    /// is folded, the detail sheet at the right while it stands, and the
    /// palette's pill along the bottom. The shell measures them and sets
    /// this; a fit leaves room for them, and the middle of what they leave
    /// is the desk's visual centre.
    struct Insets: Equatable {
        var top: CGFloat = 0
        var leading: CGFloat = 0
        var bottom: CGFloat = 0
        var trailing: CGFloat = 0
    }
    @Published var deskInsets = Insets()
    /// The height of the bars at the desk's foot, the palette and the zoom
    /// bar: a 32-point cell and `Space.s` round it (revision 22).
    static let barHeight: CGFloat = 48
    /// The palette's pill at the desk's foot and its gutters: the bar,
    /// the gutter under it and a small space over it.
    static let paletteRoom: CGFloat = 72
    /// How far the visual centre sits from the desk's own.
    var deskInset: CGPoint {
        CGPoint(x: (deskInsets.leading - deskInsets.trailing) / 2,
                y: (deskInsets.top - deskInsets.bottom) / 2)
    }
    /// The vault's `canvas.config.json`, reloaded whenever the vault changes.
    @Published private(set) var config = VaultConfig()
    /// The ⌘K panel; the menu sets it, the panel clears it.
    @Published var showSearch = false
    /// ⌘F, find on canvas (revision 27): the live panel lists every place
    /// the query is written on the open canvas, and the desk rings the
    /// nodes that hold one. A selection replaces it, as it does the tray.
    @Published var showFind = false
    @Published var findQuery = "" { didSet { if findQuery != oldValue { refreshFind() } } }
    @Published private(set) var findHits: [FindHit] = []
    /// How many there were, though no more than `CanvasFind.limit` are listed.
    @Published private(set) var findTotal = 0
    /// The hit stepped to, which the desk looks at.
    @Published var findIndex = 0
    /// The nodes holding a hit, which the desk rings.
    @Published private(set) var findNodes: Set<String> = []
    /// Bumped to put the caret back in the find field when ⌘F is pressed
    /// with the panel already up.
    @Published private(set) var findFocusTick = 0
    /// A link's words the store cannot know by itself (its page's title,
    /// fetched by the views): set by the shell.
    var linkWords: (String) -> [String] = { _ in [] }
    /// The palette's "Add a link" prompt, also opened by ⌘L.
    @Published var showLinkPrompt = false
    /// The workspace menu's "New workspace…" prompt, over the sidebar's foot.
    @Published var showNewWorkspace = false
    /// Settings, a sheet centred over the desk (revision 41): the workspace
    /// menu.s, the app menu.s ⌘, and `--settings on`.
    @Published var showSettings = false
    /// A `reveal` asked for before the vault opened, answered once it has.
    private var pendingReveal: String?

    enum Tool: Hashable {
        case select
        /// A text box where the desk is next pressed or dragged.
        case text
        /// A sticky note where the desk is next pressed (revision 15).
        case sticky
        /// A shape where the desk is next dragged.
        case draw(DrawTool)

        /// A tool that makes something from the next press on the desk,
        /// and hands back to Select once it has.
        var draws: Bool {
            switch self {
            case .text, .sticky, .draw: return true
            case .select: return false
            }
        }
    }
    /// The palette's active tool.
    @Published var tool: Tool = .select
    /// The shape drawn last: what the palette's Shapes cell wears.
    @Published var lastDrawTool: DrawTool = .rectangle

    enum PanelTarget: Hashable {
        case file(String)
    }
    /// Panels pinned beside the live one, left to right, like Heptabase's
    /// tab stack. The live panel follows the selection.
    @Published var pinnedPanels: [PanelTarget] = []
    /// A file opened in the live panel that has no card on the open canvas
    /// (revision 19): picked in the tree, Recents or ⌘K while not placed.
    /// The panel shows it with a verb to place it; a selection replaces it.
    @Published var looseFile: String? {
        didSet { if let looseFile { noteRecent(looseFile) } }
    }
    /// Whether the right-hand panel is shown at all.
    @Published var inspectorVisible = Launch.value(after: "--select") != nil

    private var previews: [String: (generation: Int, preview: CardPreview)] = [:]
    private var lastWritten: Data?
    private var openedRoot: URL?
    private var subscriptions: Set<AnyCancellable> = []

    init(vault: Vault) {
        self.vault = vault
        camera.moved = { [weak self] old, new in self?.cameraMoved(from: old, to: new) }
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

    /// Home: the vault's own canvas, `<vaultname>.canvas` at the root.
    static func homeCanvas(vault: Vault) -> String { vault.name + ".canvas" }
    var homePath: String { Self.homeCanvas(vault: vault) }
    var isHome: Bool { canvasPath == homePath }

    var title: String { canvasName(canvasPath) }

    /// Home, then the open canvas if it is another: the floating
    /// sidebar's title (revision 21).
    var crumbs: [(name: String, path: String)] {
        isHome ? [(vault.name, "")] : [(vault.name, ""), (title, canvasPath)]
    }

    /// The vault's canvases, the sidebar's list (revision 21): Home first,
    /// then every other `.canvas` file by its path.
    var canvases: [String] {
        [homePath] + vault.tree.flatMap(\.flattened)
            .filter { !$0.isDirectory && $0.kind == .canvas && $0.path != homePath }
            .map(\.path)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A canvas's name: the vault's for Home, else the file's without
    /// its extension.
    func canvasName(_ path: String) -> String {
        path == homePath ? vault.name : (VaultPath.name(of: path) as NSString).deletingPathExtension
    }

    private var openCanvasKey: String { "openCanvas:" + (vault.root?.path ?? "") }

    private func vaultChanged(_ root: URL?) {
        guard root != openedRoot else { return }
        openedRoot = root
        previews.removeAll()
        loadConfig()
        loadRecents()
        guard root != nil else {
            isOpen = false
            document = CanvasDocument()
            return
        }
        let remembered = UserDefaults.standard.string(forKey: openCanvasKey) ?? ""
        if remembered.hasSuffix(".canvas"), remembered != homePath, vault.exists(remembered) {
            openCanvas(at: remembered)
        } else {
            openHome()
        }
        if let pending = pendingReveal {
            pendingReveal = nil
            reveal(pending)
        }
    }

    /// Home, laid out from the vault on the first visit and brought up to
    /// date with it on every one after.
    func openHome() {
        guard let root = vault.root else { return }
        openedRoot = root
        Trace.log("openHome isOpen=\(isOpen) current=\(canvasPath) wantsFit=\(wantsFit) viewport=\(viewport)")
        // Already here: keep the viewport and the selection.
        if isOpen, isHome { return }
        saveViewport()
        directory = ""
        canvasPath = homePath
        selection = []
        looseFile = nil
        load()
        restore(rememberedViewport())
        isOpen = true
        UserDefaults.standard.set(canvasPath, forKey: openCanvasKey)
    }

    /// A folder is a section on Home (revision 20): Home, looking at it.
    /// The vault's root is Home itself.
    func openDirectory(_ dir: String) {
        let clean = (try? VaultPath.normalise(dir)) ?? ""
        openHome()
        guard !clean.isEmpty else { return }
        if let section = Folders.section(for: clean, in: document) {
            focusRequest = section.id
            wantsFit = false
        }
    }

    /// Any `.canvas` file.
    func openCanvas(at path: String) {
        guard vault.root != nil, vault.url(for: path) != nil else { return }
        if path == homePath { openHome(); return }
        saveViewport()
        directory = VaultPath.parent(of: path)
        canvasPath = path
        selection = []
        looseFile = nil
        load()
        restore(rememberedViewport())
        isOpen = true
        UserDefaults.standard.set(canvasPath, forKey: openCanvasKey)
    }

    /// Back to Home from any other canvas.
    func goUp() {
        guard !isHome else { return }
        openHome()
    }

    // MARK: - File

    private func load() {
        trouble = nil
        var unread = true
        if let url = vault.url(for: canvasPath), FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                document = try CanvasDocument.decode(data)
                lastWritten = data
                unread = false
            } catch {
                trouble = "Couldn't read \(canvasPath): \(error)"
                document = CanvasDocument()
                refreshUnplaced()
                // A Home that cannot be read is not overwritten.
                return
            }
        } else {
            document = CanvasDocument()
        }
        if isHome, reconcileHome() || unread { save() }
        refreshUnplaced()
    }

    /// Home brought up to date with the vault: what has appeared placed in
    /// its folder's section. Not an edit of anyone's, so not an undo.
    @discardableResult
    private func reconcileHome() -> Bool {
        guard isHome else { return false }
        return Folders.reconcile(&document, tree: vault.tree, home: homePath)
    }

    /// What the open canvas's directory holds, minus the canvas itself
    /// and any folder: what another canvas's tray offers.
    func directoryEntries() -> [VaultEntry] {
        guard let root = vault.root else { return [] }
        let all = (try? VaultListing.entries(in: directory, root: root)) ?? []
        return all.filter { $0.path != canvasPath && !$0.isDirectory }
    }

    /// The tray. On Home, what was taken off it (every other file is on
    /// it); on another canvas, its directory's files it does not show.
    func refreshUnplaced() {
        if isHome {
            unplaced = Folders.hidden(in: document).filter(vault.exists).map {
                VaultEntry(path: $0, isDirectory: vault.isDirectory($0))
            }
            return
        }
        let placed = Set(document.nodes.compactMap(\.file))
        unplaced = directoryEntries().filter { !placed.contains($0.path) && !Self.isAppFile($0.path) }
    }

    /// The files that configure the vault or hold its canvases: never a
    /// card waiting to be placed, so the tray does not ask about them.
    static func isAppFile(_ path: String) -> Bool {
        let name = VaultPath.name(of: path)
        return name == VaultConfig.fileName || name == ".mcp.json"
            || (name as NSString).pathExtension == "canvas"
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
        loadConfig()
        if let url = vault.url(for: canvasPath),
           let data = try? Data(contentsOf: url), data != lastWritten,
           let doc = try? CanvasDocument.decode(data) {
            document = doc
            lastWritten = data
            selection = selection.filter { id in doc.nodes.contains { $0.id == id } }
        }
        if isOpen, reconcileHome() { save() }
        refreshUnplaced()
        recents = recents.filter { vault.exists($0) }
        objectWillChange.send()
    }

    // MARK: - Recents

    private var recentsKey: String { "recents:" + (vault.root?.path ?? "") }

    private func loadRecents() {
        recents = (UserDefaults.standard.stringArray(forKey: recentsKey) ?? []).filter { vault.exists($0) }
    }

    /// A file opened in the panel goes to the head of Recents; a folder is
    /// a section on Home, found in the tree, and is not one.
    func noteRecent(_ path: String) {
        guard !path.isEmpty, vault.exists(path), !vault.isDirectory(path) else { return }
        guard recents.first != path else { return }
        recents.removeAll { $0 == path }
        recents.insert(path, at: 0)
        if recents.count > Self.recentsKept { recents.removeLast(recents.count - Self.recentsKept) }
        UserDefaults.standard.set(recents, forKey: recentsKey)
    }

    /// What a file is called where its name is not enough: a note's first
    /// heading, else its file name (the ⌘K panel's rule).
    func displayTitle(for path: String) -> String {
        let entry = VaultEntry(path: path, isDirectory: false)
        return entry.kind == .markdown ? preview(for: path).title : entry.name
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
        refreshUnplaced()
    }

    // MARK: - Viewport memory

    /// What a canvas remembers: the world point under the desk's centre and
    /// the scale, not the offset — an offset is only right at the size it
    /// was saved at, a centre is right at any.
    private var viewportKey: String {
        "viewportCentre:" + (vault.root?.path ?? "") + ":" + canvasPath
    }

    /// A viewport still waiting for its first fit is not worth remembering,
    /// and one measured against no desk cannot be.
    func saveViewport() {
        guard isOpen, !wantsFit, viewSize.width > 0, viewSize.height > 0 else { return }
        let centre = viewport.toWorld(CGPoint(x: viewSize.width / 2 + deskInset.x,
                                              y: viewSize.height / 2 + deskInset.y))
        Trace.log("  saveViewport \(canvasPath) centre=\(centre) scale=\(viewport.scale)")
        UserDefaults.standard.set([centre.x, centre.y, viewport.scale], forKey: viewportKey)
    }

    private func rememberedViewport() -> (centre: CGPoint, scale: CGFloat)? {
        guard let a = UserDefaults.standard.array(forKey: viewportKey) as? [Double],
              a.count == 3, a[2] > 0 else { return nil }
        return (CGPoint(x: a[0], y: a[1]), CGFloat(a[2]))
    }

    /// Nothing remembered: the view fits. Something remembered: the scale
    /// now, and the centre now if the desk's size is known, else when the
    /// view answers `restoredCentre`.
    private func restore(_ memory: (centre: CGPoint, scale: CGFloat)?) {
        guard let memory else {
            viewport = Viewport()
            restoredCentre = nil
            wantsFit = true
            return
        }
        var vp = Viewport(offset: .zero, scale: memory.scale)
        if viewSize.width > 0 {
            vp.center(on: memory.centre, in: viewSize)
            vp.offset.x += deskInset.x
            vp.offset.y += deskInset.y
        }
        viewport = vp
        wantsFit = false
        restoredCentre = memory.centre
    }

    // MARK: - Selection

    var selectedNode: CanvasNode? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return document.node(id)
    }

    /// The selected node the live panel shows: a sticky or a text box is
    /// written on the desk and has nothing for a sheet to add (revision 28),
    /// nor has a picture, which its card shows whole (revision 45).
    var panelNode: CanvasNode? {
        guard let node = selectedNode, !node.writtenOnDesk, !node.isImage else { return nil }
        return node
    }

    /// Whether the selection gives the live panel something to show: one
    /// node, and not a sticky or a text box. Several selected are a group
    /// to move or style on the desk, and the sheet stays out of the way.
    var selectionHasPanel: Bool { panelNode != nil }

    func select(_ id: String?) {
        selection = id.map { [$0] } ?? []
    }

    func node(forFile path: String) -> CanvasNode? {
        document.nodes.first { $0.kind == .file && $0.file == path }
    }

    /// The sidebar or search picked a vault path: select its card on the
    /// open canvas, else on Home, and ask the canvas to pan there. A
    /// folder is its section on Home.
    func reveal(_ rawPath: String) {
        // Asked before the vault has opened (`--select` at launch races the
        // first open): kept, and done when it has.
        guard isOpen || vault.root == nil else {
            pendingReveal = rawPath
            return
        }
        // A web address names a link card on the open canvas (`--select`
        // for a snapshot; nothing in the sidebar is a link).
        if rawPath.hasPrefix("http") {
            if let node = document.nodes.first(where: { $0.kind == .link && $0.url == rawPath }) {
                select(node.id)
                focusRequest = node.id
                wantsFit = false
            }
            return
        }
        // So does a node's id on it: a shape or a sticky, for a snapshot.
        if let node = document.node(rawPath) {
            select(node.id)
            focusRequest = node.id
            wantsFit = false
            return
        }
        let path = (try? VaultPath.normalise(rawPath)) ?? rawPath
        if vault.isDirectory(path) {
            openDirectory(path)
            // A folder with no section (empty, or taken off Home) shows in
            // the panel, with the verb to put it back if it was.
            if Folders.section(for: path, in: document) == nil {
                selection = []
                looseFile = path
                inspectorVisible = true
            }
            return
        }
        if !isOpen || (!isHome && node(forFile: path) == nil) { openHome() }
        if let node = node(forFile: path) {
            select(node.id)
            focusRequest = node.id
            // Panning to the card is the point; a fit would zoom it away.
            wantsFit = false
        } else {
            // Not on this canvas: the panel shows it anyway, with a verb to
            // place it, rather than the pick doing nothing (revision 19).
            selection = []
            looseFile = path
            inspectorVisible = true
        }
    }

    /// The loose file put on the canvas where the desk is looking, then
    /// picked, so the panel goes on showing it as its card. On Home it goes
    /// into its folder's section, the one place it can be.
    func placeLooseFile() {
        guard let path = looseFile else { return }
        if isHome {
            looseFile = nil
            let node = place(path)
            if node.kind == .file { select(node.id) }
            focusRequest = node.id
            return
        }
        let size = Placement.size(forFile: path, isDirectory: vault.isDirectory(path))
        let centre = viewport.toWorld(CGPoint(x: viewSize.width / 2 + deskInset.x,
                                              y: viewSize.height / 2 + deskInset.y))
        let origin = Placement.freeSlot(for: size, in: document,
                                        near: CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                                                     width: size.width, height: size.height))
        let node = place(path, at: origin)
        select(node.id)
        focusRequest = node.id
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
    /// replaced; anything the rule does not cover is left where it is. On
    /// Home the groups go inside the files' folder section, what else it
    /// holds moves under them, and the section grows to fit.
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
        // Each block's size first, then the blocks in columns, read down
        // one column and on to the next, as many columns as bring the
        // whole nearest the desk's shape (revision 19): one tall stack
        // fitted at a scale nobody can read.
        let blocks: [(value: String, nodes: [CanvasNode], size: CGSize)] = order.map { value in
            let nodes = (buckets[value] ?? []).sorted {
                ($0.file ?? "").localizedStandardCompare($1.file ?? "") == .orderedAscending
            }
            let rows = (nodes.count + columns - 1) / columns
            let width = CGFloat(min(nodes.count, columns)) * (card.width + gap.width) - gap.width + 2 * pad
            let height = CGFloat(rows) * (card.height + gap.height) - gap.height + 2 * pad + labelRoom
            return (value, nodes, CGSize(width: max(width, 400), height: height))
        }
        let aspect = viewSize.width > 0 && viewSize.height > 0 ? viewSize.width / viewSize.height : 1.6
        let runs = Self.columnRuns(blocks.map(\.size), aspect: aspect, gap: 60)
        let dirs = Set(matching.map { VaultPath.parent(of: $0.file ?? "") })
        let holder = isHome && dirs.count == 1 ? Folders.section(for: dirs.first!, in: document) : nil
        let start = holder.map { CGPoint(x: $0.x + Folders.pad, y: $0.y + Folders.head) } ?? Placement.origin
        mutate("Arrange by \(key)") { doc in
            doc.nodes.removeAll { $0.kind == .group && $0.extra["x-arranged-by"]?.string == key }
            let arranged = Set(matching.map(\.id))
            let others = holder.map { Folders.contents(of: $0, in: doc).filter { !arranged.contains($0.id) } } ?? []
            var placed = CGRect.null
            var x = start.x
            for run in runs {
                var y = start.y
                for index in run {
                    let block = blocks[index]
                    var group = CanvasNode(kind: .group,
                                           frame: CGRect(origin: CGPoint(x: x, y: y), size: block.size),
                                           label: rule.label(for: block.value))
                    group.color = rule.color(for: block.value) ?? String((index % 6) + 1)
                    group.extra["x-arranged-by"] = .string(key)
                    placed = placed.union(group.frame)
                    doc.insertGroup(group)
                    for (j, node) in block.nodes.enumerated() {
                        var moved = node
                        moved.x = x + pad + CGFloat(j % columns) * (card.width + gap.width)
                        moved.y = y + labelRoom + pad + CGFloat(j / columns) * (card.height + gap.height)
                        doc.update(moved)
                    }
                    y += block.size.height + 60
                }
                x += (run.map { blocks[$0].size.width }.max() ?? 0) + 60
            }
            guard let holder, !placed.isNull else { return }
            // The rest of the section, kept as it was, under the groups.
            let rest = others.reduce(CGRect.null) { $0.union($1.frame) }
            if !rest.isNull {
                let dx = start.x - rest.minX
                let dy = placed.maxY + Folders.gap + Folders.pill - rest.minY
                let ids = Set(others.map(\.id))
                for i in doc.nodes.indices where ids.contains(doc.nodes[i].id) {
                    doc.nodes[i].x += dx
                    doc.nodes[i].y += dy
                }
                placed = placed.union(rest.offsetBy(dx: dx, dy: dy))
            }
            let made = Set(doc.nodes.filter { $0.extra["x-arranged-by"]?.string == key }.map(\.id))
            Folders.grow(holder.id, toContain: placed, holding: made.union(arranged).union(others.map(\.id)), in: &doc)
        }
        if let holder, let grown = document.node(holder.id) {
            focusRequest = grown.id
        } else {
            wantsFit = true
        }
        return true
    }

    /// Blocks in order, cut into runs read top to bottom, one run per
    /// column: the count of columns whose whole comes nearest `aspect`,
    /// each run closed once it passes an even share of the height.
    static func columnRuns(_ sizes: [CGSize], aspect: CGFloat, gap: CGFloat) -> [[Int]] {
        guard !sizes.isEmpty else { return [] }
        let total = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(sizes.count - 1)
        func runs(_ count: Int) -> [[Int]] {
            let share = total / CGFloat(count)
            var out: [[Int]] = [[]]
            var height: CGFloat = 0
            for (i, size) in sizes.enumerated() {
                if !out[out.count - 1].isEmpty, height + size.height / 2 > share, out.count < count {
                    out.append([])
                    height = 0
                }
                out[out.count - 1].append(i)
                height += size.height + gap
            }
            return out
        }
        func shape(_ runs: [[Int]]) -> CGFloat {
            let width = runs.map { run in run.map { sizes[$0].width }.max() ?? 0 }.reduce(0, +)
                + gap * CGFloat(runs.count - 1)
            let height = runs.map { run in run.map { sizes[$0].height + gap }.reduce(0, +) - gap }.max() ?? 1
            return width / max(height, 1)
        }
        var best = runs(1)
        for count in stride(from: 2, through: sizes.count, by: 1) {
            let candidate = runs(count)
            if abs(log(shape(candidate) / aspect)) < abs(log(shape(best) / aspect)) { best = candidate }
        }
        return best
    }

    // MARK: - Previews and peeks

    /// After a write of this process's own. The watcher is told to ignore
    /// what we write (Vault.ownWrites), so the generation does not move
    /// and the card would go on showing what its file used to say.
    func refreshPreview(for path: String) {
        objectWillChange.send()
        previews[path] = nil
    }

    func preview(for path: String) -> CardPreview {
        if let hit = previews[path], hit.generation == vault.generation { return hit.preview }
        let p = CardPreview.make(for: path, vault: vault)
        previews[path] = (vault.generation, p)
        return p
    }

    /// A card naming a directory: a folder card from before revision 20,
    /// still on a canvas other than Home. Drawn as a plain card that opens
    /// the folder's section.
    func isDirectoryNode(_ node: CanvasNode) -> Bool {
        node.kind == .file && node.file.map(vault.isDirectory) == true
    }

    // MARK: - Mutations (every one saves, every one undoes)

    /// The window's undo manager, handed in by the canvas view.
    weak var undoManager: UndoManager?
    /// The canvas view's size, so "zoom in" and "new sticky" from a menu
    /// know where the middle is.
    var viewSize = CGSize.zero {
        didSet { if viewSize != oldValue { culled = .infinite; cameraMoved(from: viewport, to: viewport) } }
    }

    /// Published only when they change, which a pan inside the culled
    /// rect never does.
    private func cameraMoved(from old: Viewport, to new: Viewport) {
        let level = Camera.detail(for: new.scale)
        if level != detail { detail = level }
        let cut = Camera.cull(culled, old: old, new: new, in: viewSize)
        if cut != culled { culled = cut }
    }

    private func mutate(_ name: String, _ body: (inout CanvasDocument) -> Void) {
        var next = document
        body(&next)
        commit(name, next)
    }

    /// A new document, saved, with an undo that takes back what changed
    /// and puts back any file or folder the change renamed on disk.
    private func commit(_ name: String, _ next: CanvasDocument, renames: [Folders.Rename] = [],
                        undoable: Bool = true) {
        let before = document
        document = next
        save()
        refreshUnplaced()
        if undoable { registerUndo(name, CanvasDelta(from: before, to: next), renames: renames) }
    }

    /// The undo of `delta`: its inverse applied to the canvas as it is when
    /// ⌘Z is pressed, not the document from before it (revision 52), so
    /// what the door or another app wrote since stays. Its redo is the
    /// delta again, on the canvas as it is then.
    private func registerUndo(_ name: String, _ delta: CanvasDelta, renames: [Folders.Rename] = []) {
        guard let undoManager, !delta.isEmpty || !renames.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { store in
            let back = renames.reversed().map { Folders.Rename(from: $0.to, to: $0.from) }
            guard store.performRenames(back) else { return }
            let undone = delta.inverse.apply(to: store.document)
            store.document = undone
            store.save()
            store.refreshUnplaced()
            store.selection = store.selection.filter { id in undone.nodes.contains { $0.id == id } }
            store.registerUndo(name, delta.inverse, renames: back)
        }
        undoManager.setActionName(name)
    }

    /// Renames on disk, in order, all or none: a failure puts back the ones
    /// done and says why. Other canvases, Recents and the panels follow
    /// the paths; the open canvas is the caller's to update.
    @discardableResult
    func performRenames(_ renames: [Folders.Rename]) -> Bool {
        var done: [Folders.Rename] = []
        for rename in renames {
            do {
                try vault.move(rename.from, to: rename.to)
                done.append(rename)
            } catch {
                for undo in done.reversed() { try? vault.move(undo.to, to: undo.from) }
                trouble = "Couldn't move \(rename.from) to \(rename.to): \(error.localizedDescription)"
                return false
            }
        }
        guard !renames.isEmpty else { return true }
        retargetOtherCanvases(renames)
        for rename in renames {
            recents = recents.map { Folders.retarget($0, rename.from, rename.to) ?? $0 }
            pinnedPanels = pinnedPanels.map { target in
                guard case .file(let path) = target else { return target }
                return .file(Folders.retarget(path, rename.from, rename.to) ?? path)
            }
            looseFile = looseFile.map { Folders.retarget($0, rename.from, rename.to) ?? $0 }
        }
        UserDefaults.standard.set(recents, forKey: recentsKey)
        previews.removeAll()
        return true
    }

    /// Every canvas in the vault but the open one, its cards pointed at
    /// the files' new paths, so a move on Home does not strand them.
    private func retargetOtherCanvases(_ renames: [Folders.Rename]) {
        let canvases = vault.tree.flatMap(\.flattened).filter { $0.kind == .canvas }.map(\.path)
            + (isHome ? [] : [homePath])
        for path in canvases where path != canvasPath {
            guard let url = vault.url(for: path), let data = try? Data(contentsOf: url),
                  var doc = try? CanvasDocument.decode(data) else { continue }
            let before = doc
            for rename in renames { Folders.apply(rename, to: &doc) }
            if doc != before, let out = try? doc.encode() { try? vault.write(out, to: path) }
        }
    }

    func setFrame(_ id: String, _ frame: CGRect) {
        mutate("Resize") { doc in
            guard var node = doc.node(id) else { return }
            node.frame = frame
            doc.update(node)
        }
    }

    /// On Home a card or section that lands in another folder's section,
    /// or on Home's floor, takes its file or folder there on disk
    /// (revision 20). A name already taken there refuses the whole drag.
    func move(_ ids: Set<String>, by delta: CGSize) {
        var next = document
        for id in ids {
            guard var node = next.node(id) else { continue }
            node.x += delta.width
            node.y += delta.height
            next.update(node)
        }
        guard isHome else { commit("Move", next); return }
        switch Folders.relocations(after: ids, in: next, exists: vault.exists) {
        case .failure(let error):
            trouble = error.description
        case .success(let (moved, renames)):
            guard performRenames(renames) else { return }
            if !renames.isEmpty { trouble = nil }
            commit(renames.isEmpty ? "Move" : "Move to folder", moved, renames: renames)
        }
    }

    @discardableResult
    func add(_ node: CanvasNode, name: String = "Add") -> CanvasNode {
        mutate(name) { doc in
            if node.kind == .group { doc.insertGroup(node) } else { doc.nodes.append(node) }
        }
        return node
    }

    func update(_ node: CanvasNode, name: String = "Edit") {
        mutate(name) { $0.update(node) }
    }

    /// A section's name. A folder's section renames its folder on disk,
    /// if the name is free and a name at all.
    func setLabel(_ id: String, _ label: String) {
        guard var node = document.node(id), node.label != label else { return }
        guard isHome, let dir = Folders.folder(of: node) else {
            node.label = label
            update(node, name: "Rename")
            return
        }
        let name = label.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."), name != VaultPath.name(of: dir) else {
            if !name.isEmpty, name != VaultPath.name(of: dir) { trouble = "A folder can't be called \(name)." }
            return
        }
        let target = VaultPath.join(VaultPath.parent(of: dir), name)
        guard !vault.exists(target) else {
            trouble = Folders.RelocationError.taken(target).description
            return
        }
        let rename = Folders.Rename(from: dir, to: target)
        guard performRenames([rename]) else { return }
        var next = document
        Folders.apply(rename, to: &next)
        commit("Rename folder", next, renames: [rename])
    }

    func setText(_ id: String, _ text: String) {
        guard var node = document.node(id), node.text != text else { return }
        node.text = text
        // Mid-writing the words are saved (D2) but not yet an undo step:
        // the step is the whole writing, made when it ends.
        if writing[id] != nil {
            var next = document
            next.update(node)
            commit("Edit text", next, undoable: false)
            return
        }
        update(node, name: "Edit text")
    }

    // MARK: - Writing in a box (revision 52)

    /// What each box being written in was when the writing began; nil
    /// inside for a text box made for this writing and not yet an undo
    /// step. One writing is one undo step, as Excalidraw's text editor
    /// records once on submit.
    private var writing: [String: CanvasNode?] = [:] {
        didSet { if isWriting != !writing.isEmpty { isWriting = !writing.isEmpty } }
    }
    /// A box is being written in: the menu's desk keys (⌘D, ⌘⌥[ and ⌘⌥])
    /// stand aside for the editor.
    @Published private(set) var isWriting = false
    /// Text boxes added and not yet recorded: their step is the writing.
    private var unrecorded: Set<String> = []

    /// A box's editor opened.
    func beginWriting(_ id: String) {
        guard writing[id] == nil, let node = document.node(id) else { return }
        writing[id] = unrecorded.remove(id) != nil ? .some(nil) : .some(node)
    }

    /// A box's editor closed with these words: saved, and one undo step
    /// from what the box was when writing began. A text box left empty is
    /// taken away, Excalidraw's rule; one made for this writing and left
    /// empty leaves nothing behind, not even a step.
    func endWriting(_ id: String, _ text: String) {
        guard let entry = writing.removeValue(forKey: id) else { return setText(id, text) }
        guard var node = document.node(id) else { return }
        node.text = text
        let empty = node.shape == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var next = document
        if empty {
            next.nodes.removeAll { $0.id == id }
            next.edges.removeAll { $0.fromNode == id || $0.toNode == id }
            selection.remove(id)
        } else {
            next.update(node)
        }
        var start = document
        if let before = entry { start.update(before) } else { start.nodes.removeAll { $0.id == id } }
        if next != document { commit("Edit text", next, undoable: false) }
        let name = entry == nil ? "Add text" : empty ? "Delete text" : "Edit text"
        registerUndo(name, CanvasDelta(from: start, to: next))
    }

    /// Heptabase's fold: a card collapses to its title row. Folding writes
    /// the folded height into the file and remembers the old one, so the
    /// card comes back the size it was and any other JSON Canvas app sees
    /// the short card it is now. Only a file's card folds: a sticky note is
    /// its own text, a folder is a shape, not a title row, and a picture
    /// is nothing without itself (revision 45); one folded before then
    /// still unfolds.
    func toggleFold(_ ids: Set<String>) {
        let fold = !ids.allSatisfy { document.node($0)?.folded == true }
        setFolded(ids, fold)
    }

    func setFolded(_ ids: Set<String>, _ folded: Bool) {
        let changing = ids.filter { id in
            guard let node = document.node(id) else { return false }
            return node.kind == .file && !isDirectoryNode(node) && node.folded != folded
                && !(folded && node.isImage)
        }
        guard !changing.isEmpty else { return }
        mutate(folded ? "Fold" : "Unfold") { doc in
            for id in changing {
                guard var node = doc.node(id) else { continue }
                if folded {
                    node.unfoldedHeight = node.height
                    node.height = Placement.foldedHeight
                } else {
                    node.height = node.unfoldedHeight ?? Placement.cardSize.height
                    node.unfoldedHeight = nil
                }
                node.folded = folded
                doc.update(node)
            }
        }
    }

    /// Off the canvas, not off the disk: the file stays and is counted as
    /// not placed (revision 44). On Home the file, or the folder with everything
    /// in it, is listed as taken off, so it is not placed again.
    func remove(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        mutate("Remove") { doc in
            var gone = ids
            if isHome {
                for node in doc.nodes where ids.contains(node.id) {
                    if let dir = Folders.folder(of: node) {
                        Folders.hide(dir, in: &doc)
                        for inner in doc.nodes {
                            let path = Folders.folder(of: inner) ?? inner.file ?? ""
                            if path.hasPrefix(dir + "/") { gone.insert(inner.id) }
                        }
                    } else if node.kind == .file, let file = node.file {
                        Folders.hide(file, in: &doc)
                    }
                }
            }
            doc.nodes.removeAll { gone.contains($0.id) }
            doc.edges.removeAll { gone.contains($0.fromNode) || gone.contains($0.toNode) }
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
    /// On Home, with no point, a file goes into its folder's section and a
    /// folder comes back as its section; either way it is no longer hidden.
    @discardableResult
    func place(_ path: String, at point: CGPoint? = nil, near: String? = nil, size given: CGSize? = nil) -> CanvasNode {
        if isHome {
            var next = document
            Folders.unhide(path, in: &next)
            if let point, !vault.isDirectory(path) {
                let size = given ?? Placement.size(forFile: path, isDirectory: false)
                next.nodes.append(CanvasNode(kind: .file, frame: CGRect(origin: point, size: size), file: path))
            }
            Folders.reconcile(&next, tree: vault.tree, home: homePath)
            commit("Place", next)
            let placed = vault.isDirectory(path) ? Folders.section(for: path, in: document) : node(forFile: path)
            return placed ?? CanvasNode(kind: .file, frame: .zero, file: path)
        }
        let size = given ?? Placement.size(forFile: path, isDirectory: vault.isDirectory(path))
        let anchor = near.flatMap { document.node($0)?.frame } ?? selectedNode?.frame
        let origin = point ?? Placement.freeSlot(for: size, in: document, near: anchor)
        let node = CanvasNode(kind: .file, frame: CGRect(origin: origin, size: size), file: path)
        return add(node, name: "Place")
    }

    func placeAllUnplaced() {
        let entries = unplaced
        guard !entries.isEmpty else { return }
        if isHome {
            var next = document
            Folders.setHidden([], in: &next)
            Folders.reconcile(&next, tree: vault.tree, home: homePath)
            commit("Place all", next)
            return
        }
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

    /// A text box (the Text tool): the dragged box, or without a drag the
    /// default size with its top-left where the desk was pressed. Hands
    /// back to Select.
    @discardableResult
    func addText(from a: CGPoint, to b: CGPoint) -> CanvasNode {
        defer { setTool(.select) }
        let dragged = hypot(b.x - a.x, b.y - a.y) >= ShapeMetrics.dragThreshold
        let frame = dragged
            ? CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                     width: max(abs(b.x - a.x), ShapeMetrics.minimumThickness),
                     height: max(abs(b.y - a.y), ShapeMetrics.minimumThickness))
            : CGRect(origin: a, size: ShapeMetrics.defaultTextSize)
        let node = CanvasNode.shape(.text, frame: frame)
        // Its undo step is the writing that follows (revision 52).
        var next = document
        next.nodes.append(node)
        commit("Add text", next, undoable: false)
        unrecorded.insert(node.id)
        select(node.id)
        return node
    }

    /// A link card for a web address. At a point, that point is its
    /// top-left, the way a dropped file lands; without one it takes a free
    /// spot beside the middle of the view. Not a web address, no card.
    @discardableResult
    func addLink(_ address: String, at world: CGPoint?) -> CanvasNode? {
        guard let url = LinkKind.webURL(address) else { return nil }
        let size = LinkKind.classify(url).cardSize
        let origin: CGPoint
        if let world {
            origin = world
        } else {
            let centre = viewport.toWorld(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
            origin = Placement.freeSlot(for: size, in: document,
                                        near: CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                                                     width: size.width, height: size.height))
        }
        let node = CanvasNode(kind: .link, frame: CGRect(origin: origin, size: size), url: url.absoluteString)
        add(node, name: "Add link")
        select(node.id)
        return node
    }

    /// A picture off the clipboard (⌘V on the desk): written as a PNG
    /// beside the canvas — on Home into the folder section under the
    /// view's centre — and placed there as a photo card in its own shape.
    /// The bytes are a file like any other (D2); the canvas only points.
    @discardableResult
    func pasteImage(png: Data, pixels: CGSize, now: Date = Date()) -> CanvasNode? {
        let size = Placement.size(forImage: pixels)
        let centre = viewport.toWorld(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        let slot = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                          width: size.width, height: size.height)
        let dir = isHome ? Folders.directory(at: centre, in: document) : directory
        let name = Placement.pastedImageName(at: now) { vault.exists(VaultPath.join(dir, $0)) }
        let path = VaultPath.join(dir, name)
        do {
            try vault.write(png, to: path)
        } catch {
            trouble = "Couldn't save the pasted image: \(error)"
            return nil
        }
        let origin = isHome ? slot.origin : Placement.freeSlot(for: size, in: document, near: slot)
        let node = place(path, at: origin, size: size)
        select(node.id)
        return node
    }

    /// The folder a new file belongs in: on Home, the folder of the
    /// section the selection is in (or is); elsewhere, the canvas's own.
    var folderForNew: String {
        guard isHome else { return directory }
        guard let node = selectedNode else { return "" }
        if let dir = Folders.folder(of: node) { return dir }
        return Folders.container(of: node, in: document).flatMap(Folders.folder(of:)) ?? ""
    }

    /// A new Markdown file, placed and selected: on Home in the folder
    /// section beside the selection.
    func newNote() {
        let dir = folderForNew
        var name = "Untitled.md"
        var i = 2
        while vault.exists(VaultPath.join(dir, name)) {
            name = "Untitled \(i).md"
            i += 1
        }
        let path = VaultPath.join(dir, name)
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

    /// A new, empty canvas at the vault's root, opened (revision 21): the
    /// sidebar's `+` beside Canvases. Written before it is shown (D2).
    @discardableResult
    func newCanvas() -> String? {
        guard vault.root != nil else { return nil }
        var name = "Untitled canvas.canvas"
        var i = 2
        while vault.exists(name) {
            name = "Untitled canvas \(i).canvas"
            i += 1
        }
        do {
            try vault.write(try CanvasDocument().encode(), to: name)
        } catch {
            trouble = "Couldn't create \(name): \(error)"
            return nil
        }
        vault.reload()
        openCanvas(at: name)
        return name
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

    // MARK: - Shapes (revision 15)

    /// A press on the desk with a shape tool, from `a` to `b` in world
    /// units. A rectangle, ellipse or diamond takes the dragged box, or the
    /// default size centred on a click. A line or arrow whose two ends both
    /// land on cards is the edge that already exists and makes no node;
    /// anywhere else it is a shape. Either way the tool hands back to Select.
    @discardableResult
    /// A line or an arrow whose two ends land on two blocks, or within
    /// `reach` of them, is an edge between them (revision 34, after
    /// Excalidraw and FigJam): it follows them when they move, meeting each
    /// at the side that faces the other. `bind` false (⌘ held) keeps it a
    /// shape wherever it lands.
    func draw(_ tool: DrawTool, from a: CGPoint, to b: CGPoint,
              reach: CGFloat = 0, bind: Bool = true) -> CanvasNode? {
        defer { setTool(.select) }
        let dragged = hypot(b.x - a.x, b.y - a.y) >= ShapeMetrics.dragThreshold
        switch tool {
        case .line, .arrow:
            if dragged, bind, let from = bindTarget(a, reach: reach),
               let to = bindTarget(b, reach: reach, excluding: [from.id]) {
                var edge = CanvasEdge(from: from.id, to: to.id)
                if tool == .line { edge.toEnd = "none" }
                mutate(tool == .arrow ? "Draw arrow" : "Draw line") { $0.edges.append(edge) }
                return nil
            }
            let end = dragged ? b : CGPoint(x: a.x + ShapeMetrics.defaultLineLength, y: a.y)
            let node = CanvasNode.line(from: a, to: end, arrow: tool == .arrow)
            add(node, name: tool == .arrow ? "Draw arrow" : "Draw line")
            select(node.id)
            return node
        case .rectangle, .ellipse, .diamond:
            let frame: CGRect
            if dragged {
                frame = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                               width: max(abs(b.x - a.x), ShapeMetrics.minimumThickness),
                               height: max(abs(b.y - a.y), ShapeMetrics.minimumThickness))
            } else {
                frame = CGRect(origin: CGPoint(x: a.x - ShapeMetrics.defaultSize.width / 2,
                                               y: a.y - ShapeMetrics.defaultSize.height / 2),
                               size: ShapeMetrics.defaultSize)
            }
            // A box is drawn dashed, Solid a press away in the style panel
            // (revision 51); a shape already on disk keeps its own stroke.
            var node = CanvasNode.shape(tool.kind, frame: frame)
            node.dashed = true
            add(node, name: "Draw \(tool.name.lowercased())")
            select(node.id)
            return node
        }
    }

    /// The block an arrow's end at `world` attaches to: the topmost card,
    /// sticky or shape within `reach` of the point. A section does not
    /// count, since an arrow drawn across a section's floor is a shape and
    /// not an edge from the section, and nor does a line, which is itself
    /// something drawn between blocks.
    func bindTarget(_ world: CGPoint, reach: CGFloat = 0, excluding: Set<String> = []) -> CanvasNode? {
        document.nodes.reversed().first { node in
            node.kind != .group && node.shape != .line && !excluding.contains(node.id)
                && node.frame.insetBy(dx: -reach, dy: -reach).contains(world)
        }
    }

    func setFilled(_ ids: Set<String>, _ filled: Bool) {
        setShape(ids, name: filled ? "Fill" : "Outline") { $0.filled = filled }
    }

    func setDashed(_ ids: Set<String>, _ dashed: Bool) {
        setShape(ids, name: dashed ? "Dash" : "Solid line") { $0.dashed = dashed }
    }

    /// An arrowhead on, or off, either end of a line.
    func setLineEnds(_ id: String, from: Bool? = nil, to: Bool? = nil) {
        setLineEnds([id], from: from, to: to)
    }

    /// The same for every line in a selection (revision 39).
    func setLineEnds(_ ids: Set<String>, from: Bool? = nil, to: Bool? = nil) {
        setShape(ids, name: "Arrowheads") { node in
            guard node.shape == .line else { return }
            if let from { node.lineFromEnd = from ? "arrow" : nil }
            if let to { node.lineToEnd = to ? "arrow" : nil }
        }
    }

    private func setShape(_ ids: Set<String>, name: String, _ change: @escaping (inout CanvasNode) -> Void) {
        guard !ids.isEmpty else { return }
        mutate(name) { doc in
            for id in ids {
                guard var node = doc.node(id), node.shape != nil else { continue }
                change(&node)
                doc.update(node)
            }
        }
    }

    /// Ids of the nodes whose frames sit inside `frame`, sections nested in
    /// it included: what a group drags along with it.
    func nodeIDs(inside frame: CGRect) -> Set<String> {
        Set(document.nodes.filter { $0.frame != frame && frame.contains($0.frame) }.map(\.id))
    }

    /// The topmost node under a desk point, groups last.
    func hitTest(_ world: CGPoint, excluding: Set<String> = []) -> CanvasNode? {
        let cards: [CanvasNode] = document.nodes.filter { $0.kind != .group }.reversed()
        let groups: [CanvasNode] = document.nodes.filter { $0.kind == .group }.reversed()
        return (cards + groups).first { !excluding.contains($0.id) && $0.frame.contains(world) }
    }

    /// Files dropped on the desk: a vault file is placed where it landed; a
    /// file from elsewhere is copied in first, on Home into the folder
    /// whose section it landed in; a web address, dragged out of a
    /// browser, becomes a link card.
    func importFiles(_ urls: [URL], at world: CGPoint) {
        var point = world
        for url in urls {
            if !url.isFileURL {
                if addLink(url.absoluteString, at: point) != nil {
                    point.x += 40
                    point.y += 40
                }
                continue
            }
            var path: String
            let dir = isHome ? Folders.directory(at: point, in: document) : directory
            if let inside = vault.relativePath(of: url) {
                path = inside
            } else {
                var name = url.lastPathComponent
                var i = 2
                while vault.exists(VaultPath.join(dir, name)) {
                    let stem = (url.lastPathComponent as NSString).deletingPathExtension
                    let ext = url.pathExtension
                    name = ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)"
                    i += 1
                }
                path = VaultPath.join(dir, name)
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

    // MARK: - Tools and panels

    func setTool(_ next: Tool) {
        tool = next
        if case .draw(let drawn) = next { lastDrawTool = drawn }
    }

    /// A tool's cell or key pressed: Select and a shape are taken up;
    /// Text and Sticky note, pressed while in hand, are put down.
    func pressTool(_ pressed: Tool) {
        switch pressed {
        case .text, .sticky: setTool(tool == pressed ? .select : pressed)
        case .select, .draw: setTool(pressed)
        }
    }

    /// The words' size on stickies, text boxes and shapes (revision 33),
    /// one undo step. Medium is written as no key. A text box grows or
    /// shrinks with its words, so its lines keep the room they had.
    func setFontSize(_ ids: Set<String>, _ size: TextSize) {
        guard !ids.isEmpty else { return }
        mutate("Text size") { doc in
            for id in ids {
                guard var node = doc.node(id), node.writtenOnDesk else { continue }
                let was = TextSize(points: node.fontSize).rawValue
                node.fontSize = size == .medium ? nil : size.rawValue
                if node.shape == .text {
                    node.height = max(Double(ShapeMetrics.minimumThickness), node.height * size.rawValue / was)
                }
                doc.update(node)
            }
        }
    }

    /// How round pictures' corners are (revision 45), one undo step; the
    /// card's own radius leaves no key.
    func setCorners(_ ids: Set<String>, _ size: CornerSize) {
        guard !ids.isEmpty else { return }
        mutate("Corners") { doc in
            for id in ids {
                guard var node = doc.node(id), node.isImage else { continue }
                node.cornerRadius = size == .small ? nil : size.rawValue
                doc.update(node)
            }
        }
    }

    /// The face of the words on stickies, text boxes, shapes and notes'
    /// cards (revision 36), one undo step.
    /// Where the words sit on stickies, text boxes and shapes (revision
    /// 47), one undo step; the kind's own alignment is written as no key.
    func setTextAlign(_ ids: Set<String>, _ align: TextAlign) {
        guard !ids.isEmpty else { return }
        mutate("Text alignment") { doc in
            for id in ids {
                guard var node = doc.node(id), node.writtenOnDesk, node.shape != .line else { continue }
                node.textAlign = align
                doc.update(node)
            }
        }
    }

    func setFontFamily(_ ids: Set<String>, _ family: FontFamily) {
        guard !ids.isEmpty else { return }
        mutate("Font") { doc in
            for id in ids {
                guard var node = doc.node(id), node.kind == .text || node.kind == .file else { continue }
                node.fontFamily = family
                doc.update(node)
            }
        }
    }

    func setColor(_ ids: Set<String>, _ color: String?) {
        guard !ids.isEmpty else { return }
        mutate("Colour") { doc in
            for id in ids {
                guard var node = doc.node(id) else { continue }
                node.color = color
                doc.update(node)
            }
        }
    }

    // MARK: - Order and copies (revision 39)

    /// The selection drawn over everything else: its nodes moved to the
    /// end of the file's list, in the order they had. A section keeps to
    /// its own layer under the cards and is left where it is.
    func bringToFront(_ ids: Set<String>) { reorder(ids, name: "Bring to front", toFront: true) }

    /// The selection drawn under everything else: its nodes moved to the
    /// head of the list.
    func sendToBack(_ ids: Set<String>) { reorder(ids, name: "Send to back", toFront: false) }

    private func reorder(_ ids: Set<String>, name: String, toFront: Bool) {
        let moving = ids.filter { document.node($0)?.kind != .group }
        guard !moving.isEmpty else { return }
        mutate(name) { doc in
            let picked = doc.nodes.filter { moving.contains($0.id) }
            doc.nodes.removeAll { moving.contains($0.id) }
            if toFront { doc.nodes.append(contentsOf: picked) } else { doc.nodes.insert(contentsOf: picked, at: 0) }
        }
    }

    /// Copies of the selected stickies, text boxes, shapes and links, a
    /// step down and right with everything under their `x-` keys, which
    /// become the selection; one undo step. A file's card is not copied,
    /// a file having one card on a canvas, and no edge follows.
    func duplicate(_ ids: Set<String>) {
        let step = Double(ShapeMetrics.duplicateStep)
        let copies = copies(of: ids, offset: CGSize(width: step, height: step))
        guard !copies.isEmpty else { return }
        mutate("Duplicate") { doc in doc.nodes.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }

    /// The copyable nodes among `ids`, new ids, moved by `offset`.
    private func copies(of ids: Set<String>, offset: CGSize) -> [CanvasNode] {
        document.nodes.filter { ids.contains($0.id) && ($0.kind == .text || $0.kind == .link) }.map { node in
            var copy = node
            copy.id = CanvasDocument.newID()
            copy.x += offset.width
            copy.y += offset.height
            return copy
        }
    }

    /// Every node on the canvas (⌘A on the desk, revision 53).
    func selectAll() {
        guard !isWriting else { return }
        selection = Set(document.nodes.map(\.id))
    }

    /// The canvas before an ⌥-drag's copies, and the copies it moves.
    private var duplicateDrag: (before: CanvasDocument, ids: Set<String>)?

    /// An ⌥-drag has gone far enough (revision 53, Excalidraw's): copies
    /// of what it carries are laid where the originals are and become the
    /// selection the drag moves, the originals left behind. Saved, but the
    /// undo step waits for the drag's end, so a copy and its move are one.
    /// Nil when nothing is copyable (a file has one card on a canvas).
    func beginDuplicateDrag(_ ids: Set<String>) -> Set<String>? {
        let made = copies(of: ids, offset: .zero)
        guard !made.isEmpty else { return nil }
        let before = document
        var next = document
        next.nodes.append(contentsOf: made)
        commit("Duplicate", next, undoable: false)
        let copied = Set(made.map(\.id))
        duplicateDrag = (before, copied)
        selection = copied
        return copied
    }

    /// The ⌥-drag let go: its copies moved by `delta`, the copying and the
    /// move one undo step.
    func endDuplicateDrag(by delta: CGSize) {
        guard let (before, ids) = duplicateDrag else { return }
        duplicateDrag = nil
        var next = document
        for id in ids {
            guard var node = next.node(id) else { continue }
            node.x += delta.width
            node.y += delta.height
            next.update(node)
        }
        if next != document { commit("Duplicate", next, undoable: false) }
        registerUndo("Duplicate", CanvasDelta(from: before, to: next))
    }

    /// What ⌘C takes (revision 48): the selection, what its sections
    /// hold and the edges between; the view puts it on the pasteboard.
    func clip(_ ids: Set<String>) -> CanvasClip? {
        pasteRun = nil
        return CanvasClip(taking: ids, from: document, source: canvasPath)
    }

    /// The last clip pasted here and how many times, so each ⌘V of it
    /// lands a step further down and right, as a duplicate does.
    private var pasteRun: (clip: CanvasClip, count: Int)?

    /// ⌘V of a clip, in one undo step, the copy becoming the selection.
    /// Back on the canvas it came from and in view, it lands a step down
    /// and right of the last; on another canvas where it was, if that is
    /// in view; else in the middle of the view. A picture already here is
    /// copied to a file of its own beside it (D2); `CanvasClip.pasted`
    /// says what else comes along.
    @discardableResult
    func paste(_ clip: CanvasClip) -> [CanvasNode] {
        let bounds = clip.bounds
        guard !bounds.isNull else { return [] }
        let visible = viewport.visibleWorld(in: viewSize)
        var offset = CGVector.zero
        if clip.source == canvasPath, bounds.intersects(visible) {
            let count = pasteRun?.clip == clip ? pasteRun!.count + 1 : 1
            pasteRun = (clip, count)
            let step = Double(ShapeMetrics.duplicateStep) * Double(count)
            offset = CGVector(dx: step, dy: step)
        } else if !bounds.intersects(visible) {
            offset = CGVector(dx: visible.midX - bounds.midX, dy: visible.midY - bounds.midY)
        }
        let sections = Set(Folders.sections(in: document).compactMap(Folders.folder(of:)))
        let (nodes, edges) = clip.pasted(
            into: document, offset: offset,
            exists: { vault.exists($0) },
            isImage: { VaultEntry.Kind.forExtension(($0 as NSString).pathExtension) == .image },
            keepsFolder: { isHome && vault.isDirectory($0) && !sections.contains($0) },
            copyFile: { copyImage($0) })
        guard !nodes.isEmpty else { return [] }
        var next = document
        for node in nodes {
            if node.kind == .group { next.insertGroup(node) } else { next.nodes.append(node) }
        }
        next.edges.append(contentsOf: edges)
        if isHome {
            for node in nodes {
                if let path = Folders.folder(of: node) ?? node.file { Folders.unhide(path, in: &next) }
            }
            Folders.reconcile(&next, tree: vault.tree, home: homePath)
        }
        commit("Paste", next)
        selection = Set(nodes.map(\.id)).filter { document.node($0) != nil }
        return nodes
    }

    /// A picture's bytes written to a new file beside it, atomically.
    private func copyImage(_ path: String) -> String? {
        guard let url = vault.url(for: path), let data = try? Data(contentsOf: url) else { return nil }
        let dir = VaultPath.parent(of: path)
        let name = CanvasClip.copyName(of: VaultPath.name(of: path)) { vault.exists(VaultPath.join(dir, $0)) }
        let fresh = VaultPath.join(dir, name)
        do {
            try vault.write(data, to: fresh)
        } catch {
            trouble = "Couldn't copy \(VaultPath.name(of: path)): \(error)"
            return nil
        }
        return fresh
    }

    /// Heptabase's "add to side panel": the target joins the stack on the
    /// right and stays there while the live panel goes on following the
    /// selection.
    func pin(_ target: PanelTarget) {
        if !pinnedPanels.contains(target) { pinnedPanels.append(target) }
        inspectorVisible = true
    }

    func pinLivePanel() {
        if let node = selectedNode, node.kind == .file, !node.isImage, let file = node.file {
            pin(.file(file))
            select(nil)
        } else if let file = looseFile {
            pin(.file(file))
            looseFile = nil
        }
    }

    func unpin(_ target: PanelTarget) {
        pinnedPanels.removeAll { $0 == target }
        settlePanel()
    }

    /// The live panel has something to show: find, a loose file or a
    /// selection holding more than stickies and text boxes.
    var livePanelHasContent: Bool { showFind || looseFile != nil || selectionHasPanel }

    /// The panel stands while something is in it, the live column or a pin,
    /// and steps out when nothing is (decided with Liam, 2026-09-14): a
    /// third of the window is too much to hold for a sentence.
    func settlePanel() {
        if !livePanelHasContent && pinnedPanels.isEmpty { inspectorVisible = false }
    }

    // MARK: - Find on canvas

    /// ⌘F: the find panel up in the live column, or its field back in
    /// focus if it is up already.
    func showFindPanel() {
        if !showFind {
            looseFile = nil
            showFind = true
            refreshFind()
        }
        inspectorVisible = true
        findFocusTick += 1
    }

    func closeFind() {
        guard showFind else { return }
        showFind = false
        findNodes = []
        settlePanel()
    }

    /// The words a node carries, as ⌘F reads them: a card's title and its
    /// note's text, a sticky's or a shape's words, a section's label, a
    /// link's address and whatever the views know of its page.
    func findTexts(of node: CanvasNode) -> [String] {
        switch node.kind {
        case .text:
            return [node.text ?? ""]
        case .group:
            return [node.label ?? ""]
        case .link:
            return linkWords(node.url ?? "") + [node.url ?? ""]
        case .file:
            guard let path = node.file else { return [] }
            let entry = VaultEntry(path: path, isDirectory: false)
            var texts = [displayTitle(for: path)]
            if entry.kind.isTextual, let text = try? vault.readText(path) {
                texts.append(Frontmatter.parse(text).body)
            } else {
                texts.append(entry.name)
            }
            return texts
        case .other:
            return [node.text ?? node.label ?? ""]
        }
    }

    /// The hits again, for a new query or a changed canvas; the hit stepped
    /// to stays where it can, and the desk looks at it.
    func refreshFind(look: Bool = true) {
        guard showFind else { return }
        let result = CanvasFind.hits(findQuery, in: document.nodes, texts: findTexts(of:))
        let previous = findHits.indices.contains(findIndex) ? findHits[findIndex].id : nil
        findHits = result.hits
        findTotal = result.total
        findNodes = Set(result.hits.map(\.node))
        findIndex = previous.flatMap { id in findHits.firstIndex { $0.id == id } } ?? 0
        if look { lookAtFindHit() }
    }

    /// Enter and the chevrons: the next hit, or the one before, round the
    /// ends.
    func stepFind(_ direction: Int) {
        guard !findHits.isEmpty else { return }
        findIndex = (findIndex + direction + findHits.count) % findHits.count
        lookAtFindHit()
    }

    func goToFindHit(_ index: Int) {
        guard findHits.indices.contains(index) else { return }
        findIndex = index
        lookAtFindHit()
    }

    /// The node the stepped-to hit is on, panned to without selecting it:
    /// a selection would take the panel.
    var findCurrentNode: String? {
        findHits.indices.contains(findIndex) ? findHits[findIndex].node : nil
    }

    private func lookAtFindHit() {
        guard let id = findCurrentNode else { return }
        wantsFit = false
        findFocus = id
    }

    /// Asks the canvas to pan to a node quietly, with no pulse: the find
    /// ring already marks it. The canvas view clears it.
    @Published var findFocus: String?

    /// `[[name]]` clicked: open the note it names, creating it beside `from`
    /// when there is none, the way a wiki does.
    func openNote(named name: String, from: String?) {
        if let path = vault.index().resolve(link: name) {
            reveal(path)
            return
        }
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let dir = from.map(VaultPath.parent(of:)) ?? directory
        let path = VaultPath.join(dir, clean + ".md")
        do {
            try vault.write("# \(clean)\n\n", to: path)
        } catch {
            trouble = "Couldn't create \(path): \(error)"
            return
        }
        if isHome || dir == directory { place(path) }
        reveal(path)
    }

    /// A quotation from a source file, as a sticky on the open canvas beside
    /// the source's card if it is here.
    @discardableResult
    func quote(_ text: String, from source: String, page: Int?) -> CanvasNode {
        let cite = page.map { "[[\(VaultPath.name(of: source))]] p. \($0)" } ?? "[[\(VaultPath.name(of: source))]]"
        let body = "> " + text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "\n> ") + "\n\n— " + cite
        let size = CGSize(width: 320, height: 200)
        let near = node(forFile: source)?.frame ?? selectedNode?.frame
        let origin = Placement.freeSlot(for: size, in: document, near: near)
        let node = CanvasNode(kind: .text, frame: CGRect(origin: origin, size: size), text: body, color: "3")
        add(node, name: "Quote")
        select(node.id)
        focusRequest = node.id
        return node
    }

    // MARK: - Zoom from a menu or the zoom bar

    /// Each is a request the canvas view answers with the camera's own
    /// motion (law 9); the store has no animation to give it.
    func zoomIn() { zoomStep = .closer }
    func zoomOut() { zoomStep = .farther }
    func actualSize() { zoomStep = .actualSize }
    func fit() { wantsFit = true }
}
