import Foundation
import CoreGraphics

/// A directory on Home is a section bound to it (PLAN.md, D5, revision
/// 20): a JSON Canvas `group` carrying the directory's path under
/// `x-folder`, holding its files' cards and its subdirectories' sections.
/// Home shows the whole vault this way. A file that appears is placed in
/// its folder's section; a file or folder taken off Home is listed under
/// `x-hidden` and waits in the tray; a card or section dragged into
/// another section moves its file or directory there on disk.
///
/// Pure: the store and the door both call it on a document and a scan of
/// the vault, and neither is needed to test it.
enum Folders {
    static let key = "x-folder"
    static let hiddenKey = "x-hidden"

    /// Inside a section: the sides and foot, and the head, which leaves
    /// room for a nested section's label pill above its top edge.
    static let pad: Double = 30
    static let head: Double = 54
    /// Between sections, across and down (the pill sits in the gap).
    static let gap: Double = 60
    static let pill: Double = 24
    static let cardsPerRow = 4
    static let rootColumns = 5
    /// Where a row of sections wraps: on Home, and inside a section.
    static let rootWrap: Double = 2600
    static let sectionWrap: Double = 1440
    static let minWidth: Double = 360

    // MARK: - Reading a document

    static func folder(of node: CanvasNode) -> String? {
        guard node.kind == .group else { return nil }
        return node.extra[key]?.string
    }

    static func sections(in doc: CanvasDocument) -> [CanvasNode] {
        doc.nodes.filter { folder(of: $0) != nil }
    }

    static func section(for dir: String, in doc: CanvasDocument) -> CanvasNode? {
        doc.nodes.first { folder(of: $0) == dir }
    }

    /// The paths taken off Home: files and folders, kept in the canvas
    /// file so the choice survives a relaunch and reaches git.
    static func hidden(in doc: CanvasDocument) -> [String] {
        (doc.extra[hiddenKey]?.array ?? []).compactMap(\.string)
    }

    static func setHidden(_ paths: [String], in doc: inout CanvasDocument) {
        let clean = Array(Set(paths)).sorted()
        doc.extra[hiddenKey] = clean.isEmpty ? nil : .array(clean.map { .string($0) })
    }

    static func isHidden(_ path: String, in hidden: [String]) -> Bool {
        hidden.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func hide(_ path: String, in doc: inout CanvasDocument) {
        setHidden(hidden(in: doc) + [path], in: &doc)
    }

    /// A path shown again, and anything under it.
    static func unhide(_ path: String, in doc: inout CanvasDocument) {
        setHidden(hidden(in: doc).filter { $0 != path && !$0.hasPrefix(path + "/") }, in: &doc)
    }

    /// The smallest folder section around a point, or nil for Home's own
    /// floor. `excluding` leaves out a section being dragged and whatever
    /// it holds.
    static func section(at point: CGPoint, in doc: CanvasDocument,
                        excluding: Set<String> = []) -> CanvasNode? {
        sections(in: doc)
            .filter { !excluding.contains($0.id) && $0.frame.contains(point) }
            .min { area($0.frame) < area($1.frame) }
    }

    /// The directory a point on Home belongs to: "" outside every section.
    static func directory(at point: CGPoint, in doc: CanvasDocument) -> String {
        section(at: point, in: doc).flatMap(folder(of:)) ?? ""
    }

    /// The folder section a node sits in: the smallest one round its
    /// centre that is not the node itself or inside it.
    static func container(of node: CanvasNode, in doc: CanvasDocument) -> CanvasNode? {
        sections(in: doc)
            .filter { $0.id != node.id && $0.frame.contains(node.center) && !node.frame.contains($0.frame) }
            .min { area($0.frame) < area($1.frame) }
    }

    static func area(_ r: CGRect) -> Double { r.width * r.height }

    // MARK: - Renames

    struct Rename: Hashable {
        var from: String
        var to: String
    }

    /// `path` after `from` became `to`, or nil if it is not under `from`.
    static func retarget(_ path: String, _ from: String, _ to: String) -> String? {
        if path == from { return to }
        if path.hasPrefix(from + "/") { return to + path.dropFirst(from.count) }
        return nil
    }

    /// Every path in a document that `rename` moves, moved: the cards'
    /// files, the sections' folders and labels, the hidden list.
    static func apply(_ rename: Rename, to doc: inout CanvasDocument) {
        for i in doc.nodes.indices {
            if let file = doc.nodes[i].file, let moved = retarget(file, rename.from, rename.to) {
                doc.nodes[i].file = moved
            }
            if let dir = folder(of: doc.nodes[i]), let moved = retarget(dir, rename.from, rename.to) {
                doc.nodes[i].extra[key] = .string(moved)
                if dir == rename.from { doc.nodes[i].label = VaultPath.name(of: moved) }
            }
        }
        let hidden = hidden(in: doc)
        if !hidden.isEmpty {
            setHidden(hidden.map { retarget($0, rename.from, rename.to) ?? $0 }, in: &doc)
        }
    }

    enum RelocationError: Error, Equatable, CustomStringConvertible {
        case taken(String)

        var description: String {
            switch self {
            case .taken(let path):
                let parent = VaultPath.parent(of: path)
                return "\(parent.isEmpty ? "The vault" : parent) already has something called \(VaultPath.name(of: path))."
            }
        }
    }

    /// What a drag on Home asks of the disk: each moved card's file and
    /// each moved section's folder, if it now sits in another folder's
    /// section (or on Home's floor), goes there. Sections first, outer
    /// before inner, so what a section carries along follows its folder
    /// and is then already where it belongs. The document comes back with
    /// every path updated; nothing on disk is touched here.
    static func relocations(after moving: Set<String>, in doc: CanvasDocument,
                            exists: (String) -> Bool) -> Result<(CanvasDocument, [Rename]), RelocationError> {
        var doc = doc
        var renames: [Rename] = []
        var claimed: Set<String> = []
        let moved = doc.nodes.filter { moving.contains($0.id) }
        let order = moved.filter { folder(of: $0) != nil }.sorted { area($0.frame) > area($1.frame) }
            + moved.filter { $0.kind == .file && $0.file != nil }
        for original in order {
            guard let node = doc.node(original.id) else { continue }
            let current = folder(of: node) ?? node.file ?? ""
            guard !current.isEmpty else { continue }
            let parent = container(of: node, in: doc).flatMap(folder(of:)) ?? ""
            let target = VaultPath.join(parent, VaultPath.name(of: current))
            guard target != current else { continue }
            // A folder cannot go inside itself.
            guard !target.hasPrefix(current + "/") else { continue }
            if exists(target) || claimed.contains(target) { return .failure(.taken(target)) }
            claimed.insert(target)
            let rename = Rename(from: current, to: target)
            renames.append(rename)
            apply(rename, to: &doc)
        }
        return .success((doc, renames))
    }

    // MARK: - Bringing Home up to date with the vault

    /// What Home leaves out: the vault's settings, and canvases, Home
    /// among them. A canvas is a map, not a thing on one; the folders'
    /// own canvases from before revision 20 stay in the sidebar, where
    /// they open as ever.
    static func isExcluded(_ path: String, home: String) -> Bool {
        path == home || VaultPath.name(of: path) == "canvas.config.json"
            || (path as NSString).pathExtension == "canvas"
    }

    /// Every file and folder of the vault that is not on Home and not
    /// hidden is put there: a file in its folder's section, a folder as a
    /// section inside its parent's, made the first time it has something
    /// to hold. Old folder cards (a `file` node naming a directory, before
    /// revision 20) are taken off, since the section replaces them.
    /// Returns whether anything changed.
    @discardableResult
    static func reconcile(_ doc: inout CanvasDocument, tree: [VaultNode], home: String) -> Bool {
        let before = doc
        let directories = Set(tree.flatMap(\.flattened).filter(\.isDirectory).map(\.path))
        let folderCards = Set(doc.nodes.filter { $0.kind == .file && directories.contains($0.file ?? "") }.map(\.id))
        if !folderCards.isEmpty {
            doc.nodes.removeAll { folderCards.contains($0.id) }
            doc.edges.removeAll { folderCards.contains($0.fromNode) || folderCards.contains($0.toNode) }
        }
        var context = Context(hidden: hidden(in: doc), home: home,
                              placed: Set(doc.nodes.compactMap(\.file)))
        fill("", children: tree, doc: &doc, context: &context)
        return doc != before
    }

    private struct Context {
        let hidden: [String]
        let home: String
        var placed: Set<String>

        func wants(_ entry: VaultEntry) -> Bool {
            !placed.contains(entry.path) && !isHidden(entry.path, in: hidden)
                && !isExcluded(entry.path, home: home)
        }
    }

    /// One folder's files and subfolders brought onto Home, then each
    /// subfolder that already has a section, in turn.
    private static func fill(_ dir: String, children: [VaultNode], doc: inout CanvasDocument,
                             context: inout Context) {
        guard dir.isEmpty || section(for: dir, in: doc) != nil else { return }
        for node in children where !node.entry.isDirectory && context.wants(node.entry) {
            placeFile(node.entry, in: dir, doc: &doc)
            context.placed.insert(node.entry.path)
        }
        var fresh: [Block] = []
        for node in children where node.entry.isDirectory && !isHidden(node.entry.path, in: context.hidden) {
            if section(for: node.entry.path, in: doc) != nil {
                fill(node.entry.path, children: node.children ?? [], doc: &doc, context: &context)
            } else if let block = block(for: node, context: &context) {
                fresh.append(block)
            }
        }
        if !fresh.isEmpty { placeBlocks(fresh, in: dir, doc: &doc) }
    }

    // MARK: - A new section, laid out before it is placed

    /// A folder's new section, its contents at offsets from its top-left.
    private struct Block {
        let dir: String
        var size: CGSize
        var files: [(path: String, frame: CGRect)]
        var sections: [(block: Block, origin: CGPoint)]
    }

    /// Files in rows of up to four, each row as tall as its tallest card;
    /// subfolders' sections in rows under them. Nil when there is nothing
    /// to hold: an empty folder waits until something lands in it.
    private static func block(for node: VaultNode, context: inout Context) -> Block? {
        let dir = node.entry.path
        let children = node.children ?? []
        let files = children.filter { !$0.entry.isDirectory && context.wants($0.entry) }.map(\.entry)
        for file in files { context.placed.insert(file.path) }
        var subs: [Block] = []
        for child in children where child.entry.isDirectory && !isHidden(child.entry.path, in: context.hidden) {
            if let sub = block(for: child, context: &context) { subs.append(sub) }
        }
        guard !files.isEmpty || !subs.isEmpty else { return nil }
        var placedFiles: [(String, CGRect)] = []
        var y = head, x = pad, rowHeight = 0.0, width = 0.0
        for (i, file) in files.enumerated() {
            let size = Placement.size(for: file)
            if i > 0, i % cardsPerRow == 0 {
                y += rowHeight + Placement.cardGap.height
                x = pad
                rowHeight = 0
            }
            placedFiles.append((file.path, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + Placement.cardGap.width
            width = max(width, x - Placement.cardGap.width - pad)
            rowHeight = max(rowHeight, size.height)
        }
        if !files.isEmpty { y += rowHeight }
        var placedSubs: [(Block, CGPoint)] = []
        if !subs.isEmpty {
            if !files.isEmpty { y += gap + pill }
            let flow = flowLayout(subs.map(\.size), wrap: max(width, sectionWrap))
            for (sub, offset) in zip(subs, flow.offsets) {
                placedSubs.append((sub, CGPoint(x: pad + offset.x, y: y + offset.y)))
            }
            width = max(width, flow.size.width)
            y += flow.size.height
        }
        return Block(dir: dir, size: CGSize(width: max(width + 2 * pad, minWidth), height: y + pad),
                     files: placedFiles, sections: placedSubs)
    }

    /// Sizes in rows, left to right, wrapping past `wrap`; each row as
    /// tall as its tallest, with room between rows for the next row's
    /// label pills.
    static func flowLayout(_ sizes: [CGSize], wrap: Double) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x = 0.0, y = 0.0, rowHeight = 0.0, width = 0.0
        for size in sizes {
            if x > 0, x + size.width > wrap {
                y += rowHeight + gap + pill
                x = 0
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            width = max(width, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + gap
        }
        return (offsets, CGSize(width: width, height: y + rowHeight))
    }

    /// The nodes a block becomes, sections before what they hold.
    private static func materialise(_ block: Block, at origin: CGPoint, into doc: inout CanvasDocument) {
        var section = CanvasNode(kind: .group, frame: CGRect(origin: origin, size: block.size),
                                 label: VaultPath.name(of: block.dir), color: colour(for: block.dir))
        section.extra[key] = .string(block.dir)
        doc.insertGroup(section)
        for file in block.files {
            doc.nodes.append(CanvasNode(kind: .file, frame: file.frame.offsetBy(dx: origin.x, dy: origin.y),
                                        file: file.path))
        }
        for sub in block.sections {
            materialise(sub.block, at: CGPoint(x: origin.x + sub.origin.x, y: origin.y + sub.origin.y), into: &doc)
        }
    }

    // MARK: - Placing into Home or a section

    /// New sections for one folder's subfolders: under everything on
    /// Home, or in a new row at the foot of the parent's section, which
    /// grows to hold them.
    private static func placeBlocks(_ blocks: [Block], in dir: String, doc: inout CanvasDocument) {
        let container = dir.isEmpty ? nil : section(for: dir, in: doc)
        let wrap = container.map { max($0.width - 2 * pad, sectionWrap) } ?? rootWrap
        let flow = flowLayout(blocks.map(\.size), wrap: wrap)
        let origin: CGPoint
        if let container {
            let inside = contents(of: container, in: doc)
            let floor = inside.map { $0.frame.maxY }.max().map { $0 + gap + pill } ?? container.y + head
            origin = CGPoint(x: container.x + pad, y: floor)
        } else {
            let bounds = doc.bounds
            origin = bounds.isNull ? Placement.origin
                : CGPoint(x: Placement.origin.x, y: bounds.maxY + gap + pill)
        }
        let before = Set(doc.nodes.map(\.id))
        for (block, offset) in zip(blocks, flow.offsets) {
            materialise(block, at: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y), into: &doc)
        }
        if let container {
            let made = Set(doc.nodes.map(\.id)).subtracting(before)
            grow(container.id, toContain: CGRect(origin: origin, size: flow.size), holding: made, in: &doc)
        }
    }

    /// One new file's card: the first free cell of its folder's grid, or
    /// a new row at the grid's foot (the section grows); on Home's floor,
    /// the first free cell of a five-wide grid from the top-left.
    private static func placeFile(_ entry: VaultEntry, in dir: String, doc: inout CanvasDocument) {
        let size = Placement.size(for: entry)
        let step = Placement.cardSize.width + Placement.cardGap.width
        let container = dir.isEmpty ? nil : section(for: dir, in: doc)
        let obstacles: [CGRect]
        let left: Double, top: Double, columns: Int, floor: Double
        if let container {
            obstacles = contents(of: container, in: doc).map { obstacle($0) }
            left = container.x + pad
            top = container.y + head
            columns = max(1, Int((container.width - 2 * pad + Placement.cardGap.width) / step))
            floor = container.frame.maxY - pad
        } else {
            obstacles = doc.nodes.filter { $0.kind != .group || folder(of: $0) != nil }.map { obstacle($0) }
            left = Placement.origin.x
            top = Placement.origin.y
            columns = rootColumns
            floor = doc.bounds.isNull ? top : doc.bounds.maxY
        }
        func free(_ r: CGRect) -> Bool {
            !obstacles.contains { $0.insetBy(dx: -16, dy: -16).intersects(r) }
        }
        var y = top
        while y + size.height <= floor {
            for c in 0..<columns {
                let r = CGRect(origin: CGPoint(x: left + Double(c) * step, y: y), size: size)
                if free(r) {
                    doc.nodes.append(CanvasNode(kind: .file, frame: r, file: entry.path))
                    return
                }
            }
            y += 20
        }
        // No free cell: a new row under everything there, a card's gap
        // below a card, a section's gap below a section.
        var y0 = top
        if let lowest = obstacles.map(\.maxY).max() {
            y0 = max(top, lowest + (container == nil ? gap + pill : Placement.cardGap.height))
        }
        let frame = CGRect(origin: CGPoint(x: left, y: y0), size: size)
        let card = CanvasNode(kind: .file, frame: frame, file: entry.path)
        doc.nodes.append(card)
        if let container { grow(container.id, toContain: frame, holding: [card.id], in: &doc) }
    }

    /// A node's frame with its label pill, for a section.
    private static func obstacle(_ node: CanvasNode) -> CGRect {
        node.kind == .group ? CGRect(x: node.x, y: node.y - pill, width: node.width, height: node.height + pill)
            : node.frame
    }

    /// What a section holds: the nodes inside its frame, not itself.
    static func contents(of section: CanvasNode, in doc: CanvasDocument) -> [CanvasNode] {
        doc.nodes.filter { $0.id != section.id && section.frame.contains($0.frame) }
    }

    /// A section made big enough for `rect` and its padding. Wider pushes
    /// along what stands beside it, taller pushes down what sits under it
    /// (not `holding`, what it grew for), each pushed thing taking what it
    /// holds along, and its own section grows in turn, so nothing ends up
    /// under something else.
    static func grow(_ id: String, toContain rect: CGRect, holding: Set<String> = [],
                     in doc: inout CanvasDocument) {
        guard var section = doc.node(id) else { return }
        let old = section.frame
        // The section round it before it grew: once grown, it may reach
        // past its parent's edge and would pass for the parent's parent.
        let parent = sections(in: doc).filter { $0.id != id && $0.frame.contains(old) }
            .min { area($0.frame) < area($1.frame) }
        let wider = rect.maxX + pad - old.maxX
        let taller = rect.maxY + pad - old.maxY
        guard wider > 0.5 || taller > 0.5 else { return }
        if wider > 0.5 { section.width += wider }
        if taller > 0.5 { section.height += taller }
        doc.update(section)
        let grown = section.frame
        // Never pushed: the section, what it held, what it grew for, and
        // the sections round it.
        var staying = holding.union([id])
        for n in doc.nodes where old.contains(n.frame) || n.frame.contains(old) { staying.insert(n.id) }
        // Beside it, level with where it now reaches: along by as much.
        // Under it, within where it now reaches: down by as much. A node
        // pushed takes everything inside it along, by its own amount.
        var shift: [String: CGSize] = [:]
        for n in doc.nodes where !staying.contains(n.id) {
            let beside = wider > 0.5 && n.x >= old.maxX - 0.5
                && n.frame.maxY > grown.minY - pill && n.y < grown.maxY
            let under = taller > 0.5 && n.y >= old.maxY - 0.5
                && n.frame.maxX > grown.minX && n.x < grown.maxX
            if beside || under {
                shift[n.id] = CGSize(width: beside ? wider : 0, height: under ? taller : 0)
            }
        }
        let pushedGroups = doc.nodes.filter { $0.kind == .group && shift[$0.id] != nil }
            .sorted { area($0.frame) < area($1.frame) }
        for group in pushedGroups {
            for n in doc.nodes where n.id != group.id && group.frame.contains(n.frame) && !staying.contains(n.id) {
                shift[n.id] = shift[group.id]
            }
        }
        var inParent: [CGRect] = [grown]
        var moved = staying
        for i in doc.nodes.indices {
            guard let d = shift[doc.nodes[i].id] else { continue }
            let wasInParent = parent.map { $0.frame.contains(doc.nodes[i].frame) } ?? false
            doc.nodes[i].x += d.width
            doc.nodes[i].y += d.height
            moved.insert(doc.nodes[i].id)
            if wasInParent { inParent.append(doc.nodes[i].frame) }
        }
        if let parent {
            grow(parent.id, toContain: inParent.reduce(CGRect.null) { $0.union($1) }, holding: moved, in: &doc)
        }
    }

    // MARK: - Colour

    /// The folder stocks (revision 8): a directory with no colour of its
    /// own takes one by its top-level name, the colour its glyph wears in
    /// the sidebar.
    static let stockHues: [Double] = [95, 145, 240, 25, 300, 60, 190, 350]

    /// Stable per name, so a directory keeps its colour between launches.
    static func stockIndex(for name: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return Int(hash % UInt32(stockHues.count))
    }

    /// A new section's JSON Canvas colour: the preset nearest its folder's
    /// stock, so the section and the sidebar's glyph agree.
    static func colour(for dir: String) -> String {
        let top = dir.split(separator: "/").first.map(String.init) ?? dir
        let hue = stockHues[stockIndex(for: top)]
        let presets: [(String, Double)] = [("1", 25), ("2", 60), ("3", 95), ("4", 145), ("5", 200), ("6", 300)]
        func distance(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }
        return presets.min { distance($0.1, hue) < distance($1.1, hue) }!.0
    }
}

extension CanvasDocument {
    /// Groups draw under cards and take a press only where no card is, the
    /// larger behind the smaller, so a section inside another is on top
    /// of it: a new group goes in before the first smaller one.
    mutating func insertGroup(_ group: CanvasNode) {
        let area = Folders.area(group.frame)
        let at = nodes.firstIndex { $0.kind != .group || Folders.area($0.frame) < area } ?? nodes.count
        nodes.insert(group, at: at)
    }
}
