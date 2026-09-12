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
        let target = vault.isDirectory(dir) ? dir : ""
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
            document = CanvasDocument(nodes: Layout.autoLayout(directoryEntries()))
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

    // MARK: - Viewport memory

    private var viewportKey: String {
        "viewport:" + (vault.root?.path ?? "") + ":" + canvasPath
    }

    func saveViewport() {
        guard isOpen else { return }
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
    func reveal(_ path: String) {
        if vault.isDirectory(path) { openDirectory(path); return }
        let parent = VaultPath.parent(of: path)
        if parent != directory || !isOpen { openDirectory(parent) }
        if let node = node(forFile: path) {
            select(node.id)
            focusRequest = node.id
        }
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

    // MARK: - Mutations (every one saves)

    func setFrame(_ id: String, _ frame: CGRect) {
        guard var node = document.node(id) else { return }
        node.frame = frame
        document.update(node)
        save()
    }

    func move(_ ids: Set<String>, by delta: CGSize) {
        for id in ids {
            guard var node = document.node(id) else { continue }
            node.x += delta.width
            node.y += delta.height
            document.update(node)
        }
        save()
    }

    @discardableResult
    func add(_ node: CanvasNode) -> CanvasNode {
        document.nodes.append(node)
        save()
        refreshUnplaced()
        return node
    }

    func update(_ node: CanvasNode) {
        document.update(node)
        save()
    }

    func remove(_ ids: Set<String>) {
        document.nodes.removeAll { ids.contains($0.id) }
        document.edges.removeAll { ids.contains($0.fromNode) || ids.contains($0.toNode) }
        selection.subtract(ids)
        save()
        refreshUnplaced()
    }

    @discardableResult
    func connect(_ from: String, _ to: String, label: String? = nil) -> CanvasEdge {
        let edge = CanvasEdge(from: from, to: to, label: label)
        document.edges.append(edge)
        save()
        return edge
    }

    func removeEdge(_ id: String) {
        document.edges.removeAll { $0.id == id }
        save()
    }

    /// Place a vault file on this canvas at a free spot, or at `at`.
    @discardableResult
    func place(_ path: String, at point: CGPoint? = nil, near: String? = nil) -> CanvasNode {
        let isDir = vault.isDirectory(path)
        let size = isDir ? Layout.folderSize : Layout.cardSize
        let origin = point ?? Layout.freeSlot(for: size, in: document,
                                              near: near.flatMap { document.node($0)?.frame }
                                                  ?? selectedNode?.frame)
        let node = CanvasNode(kind: .file, frame: CGRect(origin: origin, size: size), file: path)
        return add(node)
    }
}
