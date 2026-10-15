import Foundation

/// Paths inside a vault are relative, use "/", and can never leave the root.
/// Every path the views or the door hand in goes through here first. Pure
/// Foundation, so the test suite compiles it standalone.
enum VaultPath {
    enum Failure: Error, Equatable, CustomStringConvertible {
        case escapesVault(String)

        var description: String {
            switch self {
            case .escapesVault(let path): return "Path leaves the vault: \(path)"
            }
        }
    }

    /// Drops empty and "." segments, refuses "..". The empty string is the root.
    static func normalise(_ raw: String) throws -> String {
        var parts: [String] = []
        for segment in raw.split(separator: "/", omittingEmptySubsequences: true) {
            if segment == "." { continue }
            if segment == ".." { throw Failure.escapesVault(raw) }
            parts.append(String(segment))
        }
        return parts.joined(separator: "/")
    }

    /// The absolute location of a vault path. A symlink that points outside
    /// the vault is refused too, so `artifacts/evil -> /etc` cannot be read
    /// through the door.
    static func resolve(_ raw: String, in root: URL) throws -> URL {
        let relative = try normalise(raw)
        let url = relative.isEmpty ? root : root.appendingPathComponent(relative)
        let rootPath = realPath(of: root)
        let realPath = realPath(of: url)
        guard realPath == rootPath || realPath.hasPrefix(rootPath + "/") else {
            throw Failure.escapesVault(raw)
        }
        return url
    }

    /// The path with every symlink resolved, whether or not the file
    /// exists yet. Foundation resolves only what is on disk, and folds
    /// `/private/tmp` to `/tmp` only then, so a file about to be created
    /// under such a vault came back under `/private` while its root did
    /// not, and the vault refused its own new file. The deepest ancestor
    /// that exists is resolved and the rest put back on it.
    static func realPath(of url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for part in rest { resolved.appendPathComponent(part) }
        return resolved.path
    }

    static func parent(of relative: String) -> String {
        guard let slash = relative.lastIndex(of: "/") else { return "" }
        return String(relative[..<slash])
    }

    static func name(of relative: String) -> String {
        relative.split(separator: "/").last.map(String.init) ?? ""
    }

    static func join(_ directory: String, _ name: String) -> String {
        directory.isEmpty ? name : directory + "/" + name
    }

    /// Shell globbing over vault paths: `*` and `?` as usual, `**/` for any
    /// depth including none, and a bare `**/x` also matches a top-level x.
    static func matches(_ path: String, glob pattern: String) -> Bool {
        if fnmatch(pattern, path, 0) == 0 { return true }
        let flat = pattern.replacingOccurrences(of: "**/", with: "")
        if fnmatch(flat, path, 0) == 0 { return true }
        return pattern.hasPrefix("**/") && fnmatch(flat, name(of: path), 0) == 0
    }
}
