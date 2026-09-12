import Foundation
import Combine

enum VaultError: Error, CustomStringConvertible {
    case noVault
    case notAFolder(String)

    var description: String {
        switch self {
        case .noVault: return "No vault is open."
        case .notAFolder(let path): return "Not a folder: \(path)"
        }
    }
}

/// The open vault: its root, its tree, and the one way to read and write
/// inside it. Files are the truth (PLAN.md, D2): every write lands on disk
/// before memory changes, and the watcher reloads what anyone else changes.
@MainActor
final class Vault: ObservableObject {
    static let defaultsKey = "vaultPath"

    @Published private(set) var root: URL?
    @Published private(set) var tree: [VaultNode] = []
    /// A sentence for the UI when something is wrong, nil when nothing is.
    @Published private(set) var trouble: String?
    /// Bumps on every reload so views that cache file contents re-read.
    @Published private(set) var generation = 0

    private var watcher: VaultWatcher?
    /// Absolute paths this process wrote recently, so the watcher's echo of
    /// our own write is not mistaken for someone else's change.
    private var recentWrites: [String: Date] = [:]

    /// `--vault <path>` wins over the remembered vault.
    init(arguments: [String] = [], defaults: UserDefaults = .standard) {
        if let path = Launch.value(after: "--vault", in: arguments) {
            open(URL(fileURLWithPath: path))
        } else if let path = defaults.string(forKey: Self.defaultsKey) {
            open(URL(fileURLWithPath: path))
        }
    }

    var name: String { root?.lastPathComponent ?? "Alex" }

    var fileCount: Int {
        tree.flatMap(\.flattened).filter { !$0.isDirectory }.count
    }

    func open(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            trouble = VaultError.notAFolder(url.path).description
            return
        }
        watcher?.stop()
        root = url
        trouble = nil
        UserDefaults.standard.set(url.path, forKey: Self.defaultsKey)
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
    }

    /// Called with absolute paths from the watcher.
    func changed(_ absolutePaths: [String]) {
        let now = Date()
        recentWrites = recentWrites.filter { now.timeIntervalSince($0.value) < 1.0 }
        let foreign = absolutePaths.filter { recentWrites[$0] == nil }
        guard !foreign.isEmpty else { return }
        reload()
    }

    func url(for path: String) -> URL? {
        guard let root else { return nil }
        return try? VaultPath.resolve(path, in: root)
    }

    func isDirectory(_ path: String) -> Bool {
        guard let url = url(for: path) else { return false }
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

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
        recentWrites[url.resolvingSymlinksInPath().path] = Date()
        try data.write(to: url, options: .atomic)
        // Our own writes are hidden from the watcher, so a new file has to
        // reach the tree by hand.
        if isNew { reload() }
    }

    /// The vault-relative path of an absolute URL, or nil if it is outside.
    func relativePath(of url: URL) -> String? {
        guard let root else { return nil }
        let rootPath = root.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        if path == rootPath { return "" }
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    func write(_ text: String, to path: String) throws {
        try write(Data(text.utf8), to: path)
    }

    func exists(_ path: String) -> Bool {
        guard let url = url(for: path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func modificationDate(_ path: String) -> Date? {
        guard let url = url(for: path) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
