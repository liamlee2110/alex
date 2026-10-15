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
// A vault under /private/tmp: Foundation folds /private away only for a
// path that exists, so a file not yet created compared unequal to its
// own root and was refused as leaving the vault.
let privateVault = URL(fileURLWithPath: "/private/tmp/alex-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: privateVault, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: privateVault) }
check((try? VaultPath.resolve("new.canvas", in: privateVault))?.lastPathComponent == "new.canvas",
      "a new file under a /private/tmp vault resolves")
check(VaultPath.realPath(of: privateVault.appendingPathComponent("a/b.md")).hasPrefix(VaultPath.realPath(of: privateVault) + "/"),
      "a path not yet on disk resolves under its existing root")
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

print("\n— Glyph —")
// Every icon the app names is in the bundled sprite (revision 24): a
// missing one would draw as an empty square, with no error anywhere.
let sprite = (try? String(contentsOfFile: "Sources/Alex/Resources/Icons/lucide.svg", encoding: .utf8)) ?? ""
check(!sprite.isEmpty, "the Lucide sprite is bundled")
let absent = Glyph.allCases.filter { !sprite.contains("<symbol id=\"\($0.rawValue)\" viewBox=\"0 0 24 24\">") }
check(absent.isEmpty, "every Glyph is a symbol in the sprite", "missing \(absent.map(\.rawValue))")

print("\n— NoteFormat —")
// The format bar's edits (revision 29), applied to the source as the editor does.
func edited(_ text: String, _ e: NoteFormat.Edit?) -> (String, String) {
    guard let e else { return (text, "") }
    let out = (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
    return (out, (out as NSString).substring(with: e.selection))
}
func sel(_ text: String, _ words: String) -> NSRange { (text as NSString).range(of: words) }

var src = "The step settled at 0.67, not 1."
var r = edited(src, NoteFormat.toggle(.bold, in: src, selection: sel(src, "settled at 0.67")))
check(r.0 == "The step **settled at 0.67**, not 1." && r.1 == "settled at 0.67", "bold wraps the words, still selected", "got \(r)")
check(NoteFormat.active(in: r.0, selection: sel(r.0, "settled at 0.67")) == [.bold], "bold reads as on")
check(NoteFormat.active(in: r.0, selection: sel(r.0, "at")) == [.bold], "on for words inside the span")
let off = edited(r.0, NoteFormat.toggle(.bold, in: r.0, selection: sel(r.0, "settled at 0.67")))
check(off.0 == src && off.1 == "settled at 0.67", "bold again unwraps", "got \(off)")
src = "a  word  b"
r = edited(src, NoteFormat.toggle(.code, in: src, selection: sel(src, "  word  ")))
check(r.0 == "a  `word`  b", "the spaces at the ends stay outside", "got \(r.0)")
src = "- one\n- two"
r = edited(src, NoteFormat.toggle(.strike, in: src, selection: NSRange(location: 0, length: (src as NSString).length)))
check(r.0 == "- ~~one~~\n- ~~two~~" && r.1 == "one~~\n- ~~two", "each line wrapped apart, past its marker", "got \(r)")
check(NoteFormat.active(in: r.0, selection: NSRange(location: 0, length: (r.0 as NSString).length)) == [.strike],
      "on across both lines")
src = "see plan"
r = edited(src, NoteFormat.toggle(.link, in: src, selection: sel(src, "plan")))
check(r.0 == "see [[plan]]", "a link is [[ ]]", "got \(r.0)")
src = "xy"
let caret = NoteFormat.toggle(.bold, in: src, selection: NSRange(location: 1, length: 0))
check(caret.map { edited(src, $0).0 } == "x****y" && caret?.selection == NSRange(location: 3, length: 0),
      "no selection: the marks go in, the caret between")
check(NoteFormat.toggle(.bold, in: "a   b", selection: NSRange(location: 1, length: 3)) == nil, "only spaces: nothing")

src = "# Title\nbody"
check(NoteFormat.block(in: src, at: 2) == .heading1 && NoteFormat.block(in: src, at: 9) == .text, "reads the line's kind")
r = edited(src, NoteFormat.turn(src, selection: sel(src, "body"), into: .heading2))
check(r.0 == "# Title\n## body" && r.1 == "body", "turn into a heading", "got \(r)")
src = "- one\n\t- [x] two\n\nthree\n"
r = edited(src, NoteFormat.turn(src, selection: NSRange(location: 0, length: (src as NSString).length), into: .numbered))
check(r.0 == "1. one\n\t2. two\n\n3. three\n", "numbered counts, keeps nesting and blanks", "got \(r.0.debugDescription)")
r = edited(src, NoteFormat.turn(src, selection: sel(src, "two"), into: .checklist))
check(r.0 == "- one\n\t- [x] two\n\nthree\n", "a ticked box stays ticked", "got \(r.0.debugDescription)")
r = edited("> quoted", NoteFormat.turn("> quoted", selection: NSRange(location: 3, length: 2), into: .text))
check(r.0 == "quoted", "text drops the syntax", "got \(r.0)")
let two = "a\nb\n"
r = edited(two, NoteFormat.turn(two, selection: NSRange(location: 0, length: 2), into: .quote))
check(r.0 == "> a\nb\n", "a selection ending at a line's start leaves that line", "got \(r.0.debugDescription)")

print("\n— NewWorkspace —")
do {
    let parent = scratch.appendingPathComponent("workspaces")
    try! fm.createDirectory(at: parent.appendingPathComponent("Taken"), withIntermediateDirectories: true)
    let template = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("vault-template")
    check(NewWorkspace.validate("  ", in: parent) == .failure(.empty), "a blank name is refused")
    check(NewWorkspace.validate(".hidden", in: parent) == .failure(.badName)
          && NewWorkspace.validate("a/b", in: parent) == .failure(.badName), "a dot first or a slash is refused")
    check(NewWorkspace.validate("taken", in: parent) == .failure(.exists("taken")), "a folder there, in any case, is refused")
    check(NewWorkspace.validate(" Course ", in: parent) == .success("Course"), "the name is trimmed")

    let made = try? NewWorkspace.create(named: "Course", in: parent, template: template)
    let path = { (p: String) in parent.appendingPathComponent("Course/" + p).path }
    check(made?.lastPathComponent == "Course", "makes the folder beside the others", "got \(String(describing: made))")
    let inside = (try? fm.contentsOfDirectory(atPath: made?.path ?? "")) ?? []
    check(Set(inside) == [".mcp.json", ".gitignore"],
          "only the template's dot files come along: no notes, no canvas (revision 54)", "got \(inside.sorted())")
    check((try? NewWorkspace.create(named: "Course", in: parent, template: template)) == nil, "never makes one twice")
    let bare = try? NewWorkspace.create(named: "Bare", in: parent, template: nil)
    check(bare.map { (try? fm.contentsOfDirectory(atPath: $0.path))?.isEmpty == true } == true, "no template: an empty folder")
    let left = (try? fm.contentsOfDirectory(atPath: parent.path))?.sorted() ?? []
    check(left == ["Bare", "Course", "Taken"], "nothing staged is left behind", "got \(left)")
}

print("")
if failures == 0 { print("✓ model suite passed") } else { print("✗ \(failures) failure(s)") }
exit(failures == 0 ? 0 : 1)
