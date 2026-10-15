import Foundation

/// A workspace made from inside Alex (PLAN.md, revision 31): a new folder
/// beside the open one, seeded with the starter vault the repository keeps
/// in `vault-template/` and the app carries in its resources. Home is
/// named after the folder, as every vault's is, so the template's
/// `vault-template.canvas` is renamed and the notes that name it follow.
/// The folder is put together in a scratch folder on the same volume and
/// renamed into place, so nobody watching the parent sees half of it (D2).
enum NewWorkspace {
    /// The name the template's own folder has, and so its Home's.
    static let templateName = "vault-template"

    enum Failure: Error, Equatable, CustomStringConvertible {
        case empty
        case badName
        case exists(String)

        var description: String {
            switch self {
            case .empty: return "Give the workspace a name."
            case .badName: return "A name can't contain / or : or start with a dot."
            case .exists(let name): return "“\(name)” is already there."
            }
        }
    }

    /// The name as it will be on disk, or why it cannot be.
    static func validate(_ raw: String, in parent: URL) -> Result<String, Failure> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.empty) }
        guard !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else { return .failure(.badName) }
        let target = parent.appendingPathComponent(name, isDirectory: true)
        // Case-insensitive volumes would call `Notes` and `notes` one folder.
        let taken = (try? FileManager.default.contentsOfDirectory(atPath: parent.path))?
            .contains { $0.caseInsensitiveCompare(name) == .orderedSame } ?? false
        if taken || FileManager.default.fileExists(atPath: target.path) { return .failure(.exists(name)) }
        return .success(name)
    }

    /// Makes `parent/name` from `template` (an empty folder when there is
    /// none) and returns it. Never replaces anything.
    static func create(named raw: String, in parent: URL, template: URL?) throws -> URL {
        let name = try validate(raw, in: parent).get()
        let fm = FileManager.default
        let target = parent.appendingPathComponent(name, isDirectory: true)
        let scratch = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: parent, create: true)
        defer { try? fm.removeItem(at: scratch) }
        let staged = scratch.appendingPathComponent(name, isDirectory: true)

        if let template, fm.fileExists(atPath: template.path) {
            try fm.copyItem(at: template, to: staged)
            let home = staged.appendingPathComponent(templateName + ".canvas")
            if fm.fileExists(atPath: home.path) {
                try fm.moveItem(at: home, to: staged.appendingPathComponent(name + ".canvas"))
            }
            for file in ["CLAUDE.md", "README.md"] {
                let url = staged.appendingPathComponent(file)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let renamed = text.replacingOccurrences(of: templateName + ".canvas", with: name + ".canvas")
                if renamed != text { try renamed.write(to: url, atomically: true, encoding: .utf8) }
            }
        } else {
            try fm.createDirectory(at: staged, withIntermediateDirectories: false)
        }
        // A rename refuses to replace what is there: nothing is lost if
        // another folder of that name appeared meanwhile.
        try fm.moveItem(at: staged, to: target)
        return target
    }

    /// The starter vault the app carries: in `Contents/Resources` for a
    /// built app (build.sh copies it, dot files and all, which SwiftPM's
    /// resources would drop), the checkout's own for `swift run`.
    static func bundledTemplate() -> URL? {
        let fm = FileManager.default
        if let inApp = Bundle.main.resourceURL?.appendingPathComponent(templateName),
           fm.fileExists(atPath: inApp.path) {
            return inApp
        }
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(templateName)
        return fm.fileExists(atPath: checkout.path) ? checkout : nil
    }
}
