import Foundation
import CryptoKit
import Combine

enum VaultError: Error, CustomStringConvertible {
    case noVault
    case notAFolder(String)

    var description: String {
        switch self {
        case .noVault: return "No vault is open."
        case .notAFolder(let path):
            let name = URL(fileURLWithPath: path).lastPathComponent
            return "Alex couldn’t find the folder “\(name)”. It may have been moved, renamed or deleted."
        }
    }
}

/// The open vault: its root, its tree, and the one way to read and write
/// inside it. Files are the truth (PLAN.md, D2): every write lands on disk
/// before memory changes, and the watcher reloads what anyone else changes.
@MainActor
final class Vault: ObservableObject {
    static let defaultsKey = "vaultPath"
    /// The vaults opened here, in the order they were first opened: the
    /// workspaces the sidebar's foot switches between (PLAN.md, revision
    /// 16). First-opened order rather than most recent, so a square keeps
    /// its place from one switch to the next.
    static let workspacesKey = "vaults"

    @Published private(set) var root: URL?
    @Published private(set) var workspaces: [URL] = []
    /// Each workspace's glyph, the top-level `icon` of its
    /// `canvas.config.json` (a Lucide name), by root path. A workspace
    /// without one is drawn as its name's initial.
    @Published private(set) var workspaceIcons: [String: String] = [:]
    /// Which way along the foot the last switch went: +1 further along,
    /// -1 back. The sidebar slides its page that way, as Arc's spaces do.
    @Published private(set) var switchDirection = 1
    private let defaults: UserDefaults
    @Published private(set) var tree: [VaultNode] = []
    /// A sentence for the UI when something is wrong, nil when nothing is.
    @Published private(set) var trouble: String?
    /// Bumps on every reload so views that cache file contents re-read.
    @Published private(set) var generation = 0
    /// Every write of this process's own, by vault path, once it is on
    /// disk (revision 59). The watcher hides our writes, so a second store
    /// showing the same canvas — the quick sketch's beside the window's —
    /// hears of them here.
    let wrote = PassthroughSubject<String, Never>()

    private var watcher: VaultWatcher?
    private var indexCache: (generation: Int, index: VaultIndex)?

    /// Backlinks and canvas membership, rebuilt lazily after each change.
    func index() -> VaultIndex {
        if let cached = indexCache, cached.generation == generation { return cached.index }
        let built = root.map(VaultIndex.build(root:)) ?? VaultIndex()
        indexCache = (generation, built)
        return built
    }

    /// File dates for the Info block.
    func dates(_ path: String) -> (created: Date?, modified: Date?) {
        guard let url = url(for: path),
              let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
            return (nil, nil)
        }
        return (values.creationDate, values.contentModificationDate)
    }
    /// What this process last left at each absolute path it wrote or
    /// moved, so the watcher's echo of our own write is not mistaken for
    /// someone else's change. Judged by what is on disk, not by a clock
    /// (revision 52, Excalidraw's way of telling change by content): an
    /// outside write that lands a moment after ours is still seen.
    private var ownWrites: [String: OwnWrite] = [:]

    enum OwnWrite: Equatable {
        /// We wrote these bytes (their SHA-256).
        case content(SHA256.Digest)
        /// We moved something away from here.
        case absent
        /// We moved something here: a file or a whole folder.
        case present

        /// Whether the path still holds what we left there.
        func matches(_ path: String) -> Bool {
            switch self {
            case .content(let digest):
                guard let data = FileManager.default.contents(atPath: path) else { return false }
                return SHA256.hash(data: data) == digest
            case .absent:
                return !FileManager.default.fileExists(atPath: path)
            case .present:
                return FileManager.default.fileExists(atPath: path)
            }
        }
    }

    /// `--vault <path>` wins over the remembered vault.
    init(arguments: [String] = [], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workspaces = storedWorkspaces()
        // A vault remembered before there were workspaces is the first one.
        if workspaces.isEmpty, let path = defaults.string(forKey: Self.defaultsKey) {
            workspaces = [URL(fileURLWithPath: path)]
        }
        for url in workspaces { refreshIcon(of: url) }
        // A vault named on the command line is a visit, not a workspace: a
        // scratch run must not add itself to the foot or become the vault
        // the next ordinary launch opens.
        if let path = Launch.value(after: "--vault", in: arguments) {
            open(URL(fileURLWithPath: path), remembering: false)
        } else if let path = defaults.string(forKey: Self.defaultsKey) {
            open(URL(fileURLWithPath: path))
        }
    }

    var name: String { root?.lastPathComponent ?? "Alex" }

    var fileCount: Int {
        tree.flatMap(\.flattened).filter { !$0.isDirectory }.count
    }

    func open(_ url: URL, remembering: Bool = true) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            trouble = VaultError.notAFolder(url.path).description
            return
        }
        watcher?.stop()
        root = url
        trouble = nil
        if remembering {
            defaults.set(url.path, forKey: Self.defaultsKey)
            remember(url)
        } else if !workspaces.contains(where: { Self.same($0, url) }) {
            workspaces.append(url)
            refreshIcon(of: url)
        }
        reload()
        watcher = VaultWatcher(root: url) { [weak self] paths in
            Task { @MainActor in self?.changed(paths) }
        }
    }

    func reload() {
        guard let root else { tree = []; return }
        do {
            tree = try VaultNode.scan("", root: root)
            generation += 1
        } catch {
            trouble = error.localizedDescription
        }
        refreshIcon(of: root)
    }

    // MARK: - Workspaces

    /// One path, whatever the URL's spelling: a trailing slash or a `..`
    /// must not make one folder two workspaces.
    static func same(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    /// The foot as stored, less any folder no longer on disk. Read again
    /// before every change: several copies of Alex share the defaults, and
    /// writing back a list read at launch put back what another forgot and
    /// dropped what another added.
    private func storedWorkspaces() -> [URL] {
        (defaults.stringArray(forKey: Self.workspacesKey) ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func storeWorkspaces(_ change: (inout [String]) -> Void) {
        var paths = defaults.stringArray(forKey: Self.workspacesKey) ?? workspaces.map(\.path)
        change(&paths)
        defaults.set(paths, forKey: Self.workspacesKey)
        workspaces = storedWorkspaces()
        if let root, !workspaces.contains(where: { Self.same($0, root) }) { workspaces.append(root) }
    }

    /// A vault opened is a workspace from then on, until it is forgotten.
    private func remember(_ url: URL) {
        storeWorkspaces { paths in
            if !paths.contains(where: { Self.same(URL(fileURLWithPath: $0), url) }) { paths.append(url.path) }
        }
        refreshIcon(of: url)
    }

    /// Takes a workspace off the sidebar's foot. Nothing on disk changes,
    /// and the open vault stays: switch away from it first.
    func forget(_ url: URL) {
        if let root, Self.same(root, url) { return }
        storeWorkspaces { $0.removeAll { Self.same(URL(fileURLWithPath: $0), url) } }
        workspaceIcons[url.path] = nil
    }

    /// Where a new workspace goes: beside the open one, or in Documents
    /// when none is open, where someone new to folders looks first
    /// (revision 49).
    var newWorkspaceParent: URL {
        if let root { return root.deletingLastPathComponent() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documents.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? home
    }

    /// Makes a folder named `name` beside the open workspace from the
    /// starter vault (revision 31), adds it to the foot and switches to it.
    func createWorkspace(named name: String, template: URL? = NewWorkspace.bundledTemplate()) throws {
        let url = try NewWorkspace.create(named: name, in: newWorkspaceParent, template: template)
        if root == nil { open(url) } else { switchWorkspace(to: url) }
    }

    /// The workspace `step` places along the foot from the open one,
    /// wrapping at either end: what ⌥⌘→ and ← and a swipe switch to.
    /// Nil when there is nowhere else to go.
    func workspace(stepping step: Int) -> URL? {
        guard workspaces.count > 1, let root,
              let i = workspaces.firstIndex(where: { Self.same($0, root) }) else { return nil }
        let n = workspaces.count
        return workspaces[((i + step) % n + n) % n]
    }

    /// Opens another workspace. The direction is published first and the
    /// vault opened on the next turn of the loop, so the sidebar has drawn
    /// the page it is about to lose with the right way out before the page
    /// goes: SwiftUI reads a leaving view's transition from its last render.
    func switchWorkspace(to url: URL) {
        guard let root, !Self.same(url, root) else { return }
        let from = workspaces.firstIndex { Self.same($0, root) } ?? 0
        let to = workspaces.firstIndex { Self.same($0, url) } ?? from
        switchDirection = to >= from ? 1 : -1
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.open(url) }
        }
    }

    private func refreshIcon(of url: URL) {
        let file = url.appendingPathComponent(VaultConfig.fileName)
        let icon = (try? Data(contentsOf: file)).flatMap { VaultConfig.decode($0).icon }
        if workspaceIcons[url.path] != icon { workspaceIcons[url.path] = icon }
    }

    /// Called with absolute paths from the watcher.
    func changed(_ absolutePaths: [String]) {
        let foreign = absolutePaths.filter { path in
            guard let own = ownWrites[path], own.matches(path) else {
                // Someone else's now: what we left there is no guide.
                ownWrites[path] = nil
                return true
            }
            return false
        }
        guard !foreign.isEmpty else { return }
        reload()
    }

    /// What a path resolves to and whether it is there, remembered until
    /// the vault changes (revision 25): every card asks all three each time
    /// the desk is built, and each answer was a `stat` or several. The
    /// watcher's reload forgets them, and so does every write of our own,
    /// which the watcher never sees.
    private struct Lookup {
        var url: URL??
        var kind: Bool??  // nil: not asked; .some(nil): absent; .some(isDirectory)
    }
    private var lookups: (generation: Int, root: URL?, paths: [String: Lookup]) = (0, nil, [:])

    private func lookup(_ path: String) -> Lookup {
        if lookups.generation != generation || lookups.root != root { lookups = (generation, root, [:]) }
        return lookups.paths[path] ?? Lookup()
    }

    /// Forget every remembered lookup: a file was written or moved.
    func forgetLookups() { lookups.paths.removeAll() }

    func url(for path: String) -> URL? {
        guard let root else { return nil }
        if let known = lookup(path).url { return known }
        let url = try? VaultPath.resolve(path, in: root)
        lookups.paths[path, default: Lookup()].url = .some(url)
        return url
    }

    /// Whether the path is there, and whether it is a directory.
    private func kind(_ path: String) -> Bool? {
        if let known = lookup(path).kind { return known }
        var kind: Bool?
        if let url = url(for: path) {
            var flag: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) { kind = flag.boolValue }
        }
        lookups.paths[path, default: Lookup()].kind = .some(kind)
        return kind
    }

    func isDirectory(_ path: String) -> Bool { kind(path) == true }

    func readText(_ path: String) throws -> String {
        guard let root else { throw VaultError.noVault }
        return try String(contentsOf: VaultPath.resolve(path, in: root), encoding: .utf8)
    }

    /// Atomic: Foundation writes a temporary file beside the target and renames
    /// it into place, so a reader never sees a half-written file. Parent
    /// directories are created, so the door can write `artifacts/C3.1/x.png`
    /// before anyone has made `C3.1`.
    func write(_ data: Data, to path: String) throws {
        guard let root else { throw VaultError.noVault }
        let url = try VaultPath.resolve(path, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let isNew = !FileManager.default.fileExists(atPath: url.path)
        ownWrites[url.resolvingSymlinksInPath().path] = .content(SHA256.hash(data: data))
        defer { forgetLookups() }
        try data.write(to: url, options: .atomic)
        // Our own writes are hidden from the watcher, so a new file has to
        // reach the tree by hand.
        if isNew { reload() }
        wrote.send(path)
    }

    /// A file or folder renamed inside the vault: what a card or section
    /// dragged into another folder's section does (revision 20). Refuses
    /// to replace anything; makes the destination's folder if it is not
    /// there. A rename is atomic on one volume, and hidden from the
    /// watcher like a write.
    func move(_ from: String, to: String) throws {
        guard let root else { throw VaultError.noVault }
        let source = try VaultPath.resolve(from, in: root)
        let destination = try VaultPath.resolve(to, in: root)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: to])
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        ownWrites[source.resolvingSymlinksInPath().path] = .absent
        ownWrites[VaultPath.realPath(of: destination)] = .present
        defer { forgetLookups() }
        try FileManager.default.moveItem(at: source, to: destination)
        reload()
    }

    /// A file moved to the system Trash (revision 65): the nearest undo
    /// to a delete, Finder's Put Back, where git is the far one (D7).
    /// Nothing in the vault is ever destroyed by the app. Hidden from the
    /// watcher like a move. Returns where the file now is.
    @discardableResult
    func trash(_ path: String) throws -> URL {
        guard let root else { throw VaultError.noVault }
        let source = try VaultPath.resolve(path, in: root)
        ownWrites[source.resolvingSymlinksInPath().path] = .absent
        defer { forgetLookups() }
        var landed: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &landed)
        reload()
        return (landed as URL?) ?? source
    }

    /// The vault-relative path of an absolute URL, or nil if it is outside.
    func relativePath(of url: URL) -> String? {
        guard let root else { return nil }
        let rootPath = VaultPath.realPath(of: root)
        let path = VaultPath.realPath(of: url)
        if path == rootPath { return "" }
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    func write(_ text: String, to path: String) throws {
        try write(Data(text.utf8), to: path)
    }

    func exists(_ path: String) -> Bool { kind(path) != nil }

    func modificationDate(_ path: String) -> Date? {
        guard let url = url(for: path) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
