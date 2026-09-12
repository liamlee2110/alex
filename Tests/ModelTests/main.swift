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
    .appendingPathComponent("alex-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }

print("\n— VaultPath —")
check((try? VaultPath.normalise("")) == "", "empty is the root")
check((try? VaultPath.normalise("/a/./b//c/")) == "a/b/c", "collapses slashes and dots",
      "got \(String(describing: try? VaultPath.normalise("/a/./b//c/")))")
check((try? VaultPath.normalise("a/../b")) == nil, "refuses .. in the middle")
check((try? VaultPath.normalise("../x")) == nil, "refuses leading ..")
check(VaultPath.parent(of: "a/b/c.md") == "a/b", "parent of nested")
check(VaultPath.parent(of: "c.md") == "", "parent of top-level is the root")
check(VaultPath.name(of: "a/b/c.md") == "c.md", "name of nested")
check(VaultPath.join("", "x") == "x" && VaultPath.join("a", "x") == "a/x", "join")

// A symlink that escapes the vault must be refused even though the path
// itself has no "..": the door would otherwise read anything on the disk.
let vault = scratch.appendingPathComponent("vault")
try! fm.createDirectory(at: vault.appendingPathComponent("artifacts"), withIntermediateDirectories: true)
let outside = scratch.appendingPathComponent("outside")
try! fm.createDirectory(at: outside, withIntermediateDirectories: true)
try! fm.createSymbolicLink(at: vault.appendingPathComponent("artifacts/evil"), withDestinationURL: outside)
check((try? VaultPath.resolve("artifacts/evil", in: vault)) == nil, "symlink out of the vault is refused")
check((try? VaultPath.resolve("artifacts", in: vault)) != nil, "a real subdirectory resolves")
check((try? VaultPath.resolve("", in: vault)) == vault, "empty resolves to the root")
check((try? VaultPath.resolve("new/not/yet.md", in: vault))?.lastPathComponent == "yet.md",
      "a path that does not exist yet still resolves")

print("\n— VaultEntry.Kind —")
check(VaultEntry.Kind.forExtension("md") == .markdown, "md is markdown")
check(VaultEntry.Kind.forExtension("PNG") == .image, "extension match is case-insensitive")
check(VaultEntry.Kind.forExtension("canvas") == .canvas, "canvas")
check(VaultEntry.Kind.forExtension("xyz") == .other, "unknown is other")
check(VaultEntry(path: "a/b", isDirectory: true).kind == .directory, "directories are directories")
check(VaultEntry(path: "notes/Plan.md", isDirectory: false).name == "Plan.md", "name from path")

print("\n— VaultListing —")
for name in ["zeta.md", "Alpha.md", ".hidden", "beta.png"] {
    fm.createFile(atPath: vault.appendingPathComponent(name).path, contents: Data())
}
try! fm.createDirectory(at: vault.appendingPathComponent("sessions"), withIntermediateDirectories: true)
try! fm.createDirectory(at: vault.appendingPathComponent(".git"), withIntermediateDirectories: true)
try! fm.createDirectory(at: vault.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
let listed = (try? VaultListing.entries(in: "", root: vault)) ?? []
let names = listed.map(\.name)
check(names == ["artifacts", "sessions", "Alpha.md", "beta.png", "zeta.md"],
      "directories first, then case-insensitive names, hidden and caches skipped",
      "got \(names)")
check(listed.first?.isDirectory == true, "first entry is a directory")
check(listed.last?.path == "zeta.md", "paths are relative to the root")

print("\n— VaultNode —")
fm.createFile(atPath: vault.appendingPathComponent("sessions/2026-09-14.md").path, contents: Data())
let tree = (try? VaultNode.scan("", root: vault)) ?? []
let sessions = tree.first { $0.entry.name == "sessions" }
check(sessions?.children?.map(\.entry.path) == ["sessions/2026-09-14.md"], "children carry full relative paths",
      "got \(String(describing: sessions?.children?.map(\.entry.path)))")
check(tree.first { $0.entry.name == "Alpha.md" }?.children == nil, "files have nil children")
let capped = (try? VaultNode.scan("", root: vault, depth: 0)) ?? []
check(capped.first { $0.entry.name == "sessions" }?.children == [], "depth cap leaves directories empty, not nil")
check(tree.flatMap(\.flattened).filter { !$0.isDirectory }.count == 4, "flattened counts every file",
      "got \(tree.flatMap(\.flattened).filter { !$0.isDirectory }.count)")

print("")
if failures == 0 { print("✓ model suite passed") } else { print("✗ \(failures) failure(s)") }
exit(failures == 0 ? 0 : 1)
