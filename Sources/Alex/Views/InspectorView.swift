import SwiftUI
import AppKit

/// The detail sheet (revision 21): Heptabase's stack of panels, floating
/// over the desk's right as Figma's panels float when its UI is folded.
/// The live panel, following the selection, is the sheet itself: inset
/// from the window's edges at the panel radius, sliding in from the right.
/// A pinned panel is a sub-sheet drawn out of the sheet's leading edge —
/// a step shorter at each end, tucked under it, sliding out from behind
/// it — so what you kept reads as held beside what you are reading. With
/// nothing live beside the pins, the last pin is the sheet.
struct InspectorView: View {
    @ObservedObject var store: CanvasStore

    /// The narrowest a column reads at.
    static let columnMin: CGFloat = 320

    /// The narrowest the stack can be: a column's minimum per column and
    /// the tuck of each sub-sheet. The shell gives the stack at least this
    /// and lets the desk yield, so a pinned page is never cut.
    static func minimumWidth(for store: CanvasStore) -> CGFloat {
        let columns = store.pinnedPanels.count + (showsLive(store) ? 1 : 0)
        return CGFloat(columns) * columnMin
    }

    private enum Sheet: Hashable {
        case pin(CanvasStore.PanelTarget)
        case live
    }

    private var sheets: [Sheet] {
        store.pinnedPanels.map(Sheet.pin) + (showsLive ? [.live] : [])
    }

    var body: some View {
        let sheets = sheets
        HStack(spacing: -Shell.subsheetTuck) {
            ForEach(Array(sheets.enumerated()), id: \.element) { i, sheet in
                let main = i == sheets.count - 1
                column(sheet)
                    // The tucked strip is under the sheet; the page keeps
                    // clear of it.
                    .padding(.trailing, main ? 0 : Shell.subsheetTuck)
                    .frame(minWidth: Self.columnMin + (main ? 0 : Shell.subsheetTuck), maxWidth: .infinity,
                           maxHeight: .infinity)
                    .floatingCard()
                    .padding(.vertical, main ? 0 : Shell.subsheetInset)
                    .zIndex(Double(i))
                    .transition(main ? .move(edge: .trailing)
                                     : .offset(x: Self.columnMin).combined(with: .opacity))
            }
        }
        .animation(Motion.move, value: sheets)
    }

    @ViewBuilder private func column(_ sheet: Sheet) -> some View {
        let main = sheet == sheets.last
        switch sheet {
        case .pin(let target): PanelColumn(store: store, target: target, main: main)
        case .live: PanelColumn(store: store, target: nil, main: main)
        }
    }

    /// The live column stands when it has something to show, or when the
    /// stack has nothing else; beside a pin with nothing selected it steps
    /// out rather than hold a third of the window for a sentence.
    private var showsLive: Bool { Self.showsLive(store) }

    private static func showsLive(_ store: CanvasStore) -> Bool {
        store.pinnedPanels.isEmpty || store.livePanelHasContent
    }
}

/// One panel: pinned to a target, or live (nil) and following the selection.
/// Its head is the dashboards' column head (revision 18): what the panel
/// holds named at the left — a file by its glyph and name with the folder
/// it sits in, a link by its site's mark and title, a sticky, a
/// shape, a section — and the panel's own verbs as plain glyphs at the
/// right: Finder, keep this one and start another, and a pin's close.
/// The sheet hides from the glyph at its head's far end (revision 21). No borders:
/// the head is a row of the page, not a box on it.
struct PanelColumn: View {
    @ObservedObject var store: CanvasStore
    let target: CanvasStore.PanelTarget?
    /// The sheet itself rather than a sub-sheet: it carries the glyph that
    /// hides the whole stack.
    var main = false
    @ObservedObject private var previews = LinkPreviews.shared
    @EnvironmentObject private var vault: Vault

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            head
            Spacer(minLength: Space.s)
            // A file with no card on the open canvas: the one thing the
            // panel asks is to place it (revision 19).
            if target == nil, !store.showFind, store.looseFile != nil {
                Button("Place on canvas") { store.placeLooseFile() }
                    .buttonStyle(.solid)
                    .fixedSize()
            }
            if let path = currentPath, let url = store.vault.url(for: path) {
                IconButton(symbol: .squareArrowOutUpRight, label: "Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            if target == nil, store.showFind {
                IconButton(symbol: .x, label: "Close find", shortcut: "esc") { store.closeFind() }
            }
            if let target {
                IconButton(symbol: .x, label: "Close this panel") { store.unpin(target) }
            } else if currentPath != nil {
                IconButton(symbol: .plus, label: "Keep this panel open and start another") { store.pinLivePanel() }
            }
            // The sheet hides from its own head (revision 21): the one
            // collapse glyph for it, the way the sidebar's is in its own.
            if main {
                IconButton(symbol: .panelRight, label: "Hide the sheet",
                           hint: "Hide the sheet (⌥⌘I)") { store.inspectorVisible = false }
            }
        }
        .padding(.leading, Shell.panelInset)
        .padding(.trailing, Space.m)
        .frame(height: Shell.panelHead)
        .windowDragArea()
    }

    /// What the panel holds, named.
    @ViewBuilder private var head: some View {
        switch target {
        case .file(let path):
            fileHead(path)
        case nil:
            if store.showFind {
                PanelHead(symbol: .search, text: "Find on canvas", detail: store.title)
            } else if let path = store.looseFile {
                fileHead(path)
            } else if let node = store.panelNode {
                nodeHead(node)
            } else {
                PanelHead(symbol: .layoutDashboard, text: store.title)
            }
        }
    }

    /// A file by what it is called on its card and in Recents — a note's
    /// heading — with its path after it where the heading is not the
    /// name, else the folder it sits in (revision 19): the tree speaks in
    /// file names, everything else in titles.
    private func fileHead(_ path: String) -> some View {
        let name = VaultPath.name(of: path)
        let kind: VaultEntry.Kind = vault.isDirectory(path)
            ? .directory : .forExtension((name as NSString).pathExtension)
        let parent = VaultPath.parent(of: path)
        let title = kind == .directory ? name : store.displayTitle(for: path)
        let detail = title != name ? path : parent.isEmpty ? nil : parent
        let symbol = kind == .directory ? kind.symbol : VaultEntry(path: path, isDirectory: false).symbol
        return PanelHead(symbol: symbol, text: title, detail: detail)
    }

    @ViewBuilder private func nodeHead(_ node: CanvasNode) -> some View {
        switch node.kind {
        case .file:
            if let path = node.file { fileHead(path) }
        case .text:
            // Written on the desk, and never here but for its name.
            let live = store.document.node(node.id) ?? node
            PanelHead(symbol: ShapeLabel.symbol(of: live), text: ShapeLabel.name(of: live))
        case .link:
            let address = node.url ?? ""
            let meta = previews.meta(for: address)
            let kind = LinkKind.classify(address)
            let host = LinkKind.webURL(address)?.host
            PanelHead(icon: previews.icon(for: address), symbol: kind.symbol,
                      text: meta?.title ?? meta?.author ?? host ?? address,
                      detail: meta?.provider ?? kind.providerName ?? host)
        case .group:
            PanelHead(symbol: .squareDashed, text: node.label?.isEmpty == false ? node.label! : "Section")
        case .other:
            PanelHead(symbol: .fileQuestion, text: "A \(node.kind.typeName) node")
        }
    }

    private var currentPath: String? {
        switch target {
        case .file(let path): return path
        case nil:
            if store.showFind { return nil }
            if let path = store.looseFile { return path }
            if let node = store.selectedNode, node.kind == .file { return node.file }
            return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch target {
        case .file(let path):
            FileInspector(path: path, store: store)
                .id(path)
        case nil:
            if store.showFind {
                FindPanel(store: store)
            } else if let path = store.looseFile {
                FileInspector(path: path, store: store)
                    .id(path)
            } else if let node = store.panelNode {
                NodeInspector(node: node, store: store)
                    .id(node.id)
            } else {
                EmptyInspector(store: store)
            }
        }
    }
}

/// The panel head's name: a glyph — a file's kind, a link's site — the
/// name in the identifying weight, and a supporting fact after it in
/// the supporting ink: the folder a file sits in, a link's provider.
struct PanelHead: View {
    var icon: NSImage? = nil
    let symbol: Glyph
    let text: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: Space.s) {
            if let icon {
                LinkMark(icon: icon, symbol: symbol)
            } else {
                GlyphImage(symbol)
                    .foregroundStyle(Ink.muted)
                    .frame(width: 16)
            }
            Text(text)
                .font(Typography.control)
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            // The file's path is short and says which file; a long
            // heading gives way to it (revision 19).
            if let detail {
                Text(detail)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// More than one card selected, or a moment between selections while a
/// pin keeps the stack open: the canvas's counts and what to do next.
/// The head names the canvas.
struct EmptyInspector: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(store.document.nodes.count) on the canvas · \(store.unplaced.count) not placed")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
            Spacer()
            Text(store.selection.count > 1
                 ? "\(store.selection.count) selected. Pick one to read it here."
                 : "Select a card to read it here.")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
        }
        .padding(.horizontal, Shell.panelInset)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NodeInspector: View {
    let node: CanvasNode
    @ObservedObject var store: CanvasStore

    var body: some View {
        switch node.kind {
        case .file:
            if let path = node.file {
                FileInspector(path: path, store: store)
            }
        case .text:
            // Written on the desk: a sticky, a text box, a shape.
            EmptyView()
        case .link:
            LinkInspector(node: node)
        case .group:
            GroupInspector(node: node, store: store)
        case .other:
            Text("A \(node.kind.typeName) node from another app. Kept as is.")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, Shell.panelInset)
                .padding(.vertical, Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FileInspector: View {
    let path: String
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault

    @State private var text = ""
    @State private var diskText = ""
    @State private var pendingDisk = ""
    @State private var dirty = false
    @State private var changedOnDisk = false
    @State private var saveTask: Task<Void, Never>?
    /// The frontmatter as text, unfolded under its row.
    @State private var showProperties = false

    private var name: String { VaultPath.name(of: path) }
    private var stem: String { (name as NSString).deletingPathExtension }
    private var url: URL? { vault.url(for: path) }
    private var kind: VaultEntry.Kind {
        vault.isDirectory(path) ? .directory : .forExtension((name as NSString).pathExtension)
    }
    private var editable: Bool { kind.isTextual && kind != .canvas }

    var body: some View {
        VStack(spacing: 0) {
            if changedOnDisk { banner }
            content
        }
        // The head names the file (`PanelColumn`); what is left to say
        // here is that a write is on its way, whispered at the foot.
        .overlay(alignment: .bottomTrailing) {
            if dirty {
                Text("Saving")
                    .font(Typography.micro)
                    .foregroundStyle(Ink.faint)
                    .padding(.trailing, Shell.panelInset)
                    .padding(.bottom, Space.s)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: load)
        .onChange(of: vault.generation) { _, _ in checkDisk() }
        .onChange(of: text) { _, _ in scheduleSave() }
        .onDisappear(perform: flush)
    }

    private var banner: some View {
        HStack(spacing: Space.s) {
            Text("Changed on disk while you were editing.")
                .font(Typography.body)
                .foregroundStyle(Ink.primary)
            Spacer()
            Button("Reload") {
                text = pendingDisk
                diskText = pendingDisk
                dirty = false
                changedOnDisk = false
            }
            .buttonStyle(.outline)
            Button("Keep mine") {
                changedOnDisk = false
                write()
            }
            .buttonStyle(.outline)
        }
        .padding(.horizontal, Shell.panelInset)
        .padding(.vertical, Space.s)
        .background(Accent.wash)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .markdown:
            let editorAndInfo = VStack(alignment: .leading, spacing: 0) {
                // The frontmatter is one folded row that opens as text
                // under it (revision 34); the editor gets the body alone,
                // and both write the one file.
                let split = Frontmatter.split(text)
                let fm = Frontmatter.parse(text)
                if split.hasBlock {
                    propertiesRow(fm)
                    if showProperties {
                        PlainTextEditor(text: yamlBinding)
                            .frame(height: propertiesHeight(split.yaml))
                            .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.well))
                            .padding(.horizontal, Shell.panelInset)
                            .padding(.top, Space.s)
                    }
                }
                MarkdownEditor(text: bodyBinding, imageBase: url?.deletingLastPathComponent(), imageStem: stem,
                               onOpenLink: { name in store.openNote(named: name, from: path) })
                    .padding(.horizontal, Shell.panelInset)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.l)
                InfoBlock(path: path, text: text, store: store)
            }
            ScrollView { editorAndInfo }
        case .code, .text, .canvas:
            PlainTextEditor(text: $text, editable: editable)
        case .image:
            if let url, let image = NSImage(contentsOf: url) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.well))
                        .padding(.horizontal, Shell.panelInset)
                        .padding(.vertical, Space.m)
                }
            } else {
                cannotShow
            }
        case .pdf:
            if let url { PDFReader(path: path, url: url, store: store) } else { cannotShow }
        case .html:
            if let url, let root = vault.root { HTMLPreview(url: url, root: root) } else { cannotShow }
        case .directory:
            DirectoryInspector(path: path, store: store)
        case .office, .other:
            cannotShow
        }
    }

    /// The frontmatter folded to one quiet row, "Properties" and how many
    /// keys it holds (revision 34): the heading and the card already say
    /// what matters, so the keys wait until asked for and unfold as text.
    private func propertiesRow(_ fm: Frontmatter) -> some View {
        HStack(spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Text("Properties").foregroundStyle(Ink.muted)
                Text("\(fm.order.count)").foregroundStyle(Ink.muted)
            }
            .font(Typography.meta)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Motion.move) { showProperties.toggle() } }
            Spacer(minLength: 0)
            IconButton(symbol: showProperties ? .chevronUp : .chevronDown,
                       label: showProperties ? "Fold the properties" : "Unfold the properties",
                       size: .small) {
                withAnimation(Motion.move) { showProperties.toggle() }
            }
        }
        .padding(.horizontal, Shell.panelInset)
        .padding(.top, Space.xs)
    }

    private func propertiesHeight(_ yaml: String) -> CGFloat {
        let rows = max(yaml.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return CGFloat(rows) * Typography.lineHeight(ofSize: 12, monospaced: true) + 2 * Space.m
    }

    /// The body alone, put back under the block untouched.
    private var bodyBinding: Binding<String> {
        Binding(get: { Frontmatter.split(text).body },
                set: { text = Frontmatter.split(text).replacingBody(with: $0) })
    }

    /// The block alone, put back over the body untouched.
    private var yamlBinding: Binding<String> {
        Binding(get: { Frontmatter.split(text).yaml },
                set: { text = Frontmatter.split(text).replacingYAML(with: $0) })
    }

    private var cannotShow: some View {
        VStack(spacing: Space.m) {
            Text("Alex can't show this file yet.")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
            if let url {
                Button("Open with the default app") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.outline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Saving

    private func load() {
        guard kind.isTextual else { return }
        text = (try? vault.readText(path)) ?? ""
        diskText = text
    }

    private func scheduleSave() {
        guard editable, text != diskText else { return }
        dirty = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            write()
        }
    }

    private func write() {
        guard editable else { return }
        do {
            try vault.write(text, to: path)
            diskText = text
            dirty = false
            store.refreshPreview(for: path)
        } catch {
            NSLog("Alex: could not save \(path): \(error)")
        }
    }

    private func flush() {
        saveTask?.cancel()
        if dirty { write() }
    }

    /// Someone else wrote the file. Take it if nothing here is unsaved;
    /// otherwise say so and let the person choose. Never overwrite silently.
    private func checkDisk() {
        guard kind.isTextual, let now = try? vault.readText(path), now != diskText else { return }
        if !dirty {
            text = now
            diskText = now
        } else {
            pendingDisk = now
            changedOnDisk = true
        }
    }
}

/// Heptabase's Info block under a note: dates, counts, the canvases it is
/// on, its tags, and the notes that link to it.
struct InfoBlock: View {
    let path: String
    let text: String
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault

    private var words: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var body: some View {
        let index = vault.index()
        let dates = vault.dates(path)
        let canvases = index.canvases(for: path)
        let backlinks = index.backlinks(to: path)
        let tags = Frontmatter.parse(text)["tags"]
        VStack(alignment: .leading, spacing: Space.s) {
            Divider()
            sectionHead("Info")
            row(.clock, "Created", dates.created.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
            row(.rotateCcwClock, "Updated", dates.modified.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
            row(.type, "Count", "\(words) words · \(text.count) characters")
            HStack(alignment: .top, spacing: Space.s) {
                GlyphImage(.layoutDashboard).frame(width: 16).foregroundStyle(Ink.faint)
                Text("Canvases (\(canvases.count))").foregroundStyle(Ink.muted).frame(width: 110, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(canvases, id: \.self) { canvas in
                        Button {
                            store.openCanvas(at: canvas)
                            if let node = store.node(forFile: path) { store.select(node.id); store.focusRequest = node.id }
                        } label: {
                            Text(canvasName(canvas)).foregroundStyle(Ink.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .font(Typography.body)
            row(.hash, "Tags", tags.map(\.display).flatMap { $0.isEmpty ? nil : $0 } ?? "none")
            if !backlinks.isEmpty {
                Divider().padding(.top, Space.m)
                sectionHead("Backlinks (\(backlinks.count))")
                ForEach(backlinks, id: \.self) { link in
                    Button {
                        store.reveal(link.source)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Space.xs) {
                                GlyphImage(.fileText)
                                Text(VaultIndex.stem(of: link.source))
                            }
                                .font(Typography.body)
                                .foregroundStyle(Ink.primary)
                            Text(link.snippet)
                                .font(Typography.meta)
                                .foregroundStyle(Ink.muted)
                                .lineLimit(3)
                        }
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.well))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Shell.panelInset)
        .padding(.bottom, Space.xl)
    }

    private func canvasName(_ canvas: String) -> String {
        let dir = VaultPath.parent(of: canvas)
        return dir.isEmpty ? vault.name : dir
    }

    /// A part's name, the way the dashboards head a section: a step up
    /// from the body, in the supporting ink, air above it.
    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(Typography.section)
            .foregroundStyle(Ink.muted)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ symbol: Glyph, _ label: String, _ value: String) -> some View {
        HStack(spacing: Space.s) {
            GlyphImage(symbol).frame(width: 16).foregroundStyle(Ink.faint)
            Text(label).foregroundStyle(Ink.muted).frame(width: 110, alignment: .leading)
            Text(value).foregroundStyle(Ink.primary)
        }
        .font(Typography.body)
    }
}

struct DirectoryInspector: View {
    let path: String
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault

    var body: some View {
        let entries = vault.root.flatMap { try? VaultListing.entries(in: path, root: $0) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    Text("Nothing in it yet.")
                        .font(Typography.body)
                        .foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Space.l)
                }
                ForEach(entries) { entry in
                    HStack(spacing: Space.s) {
                        GlyphImage(entry.symbol, filled: entry.isDirectory)
                            .foregroundStyle(entry.isDirectory ? Stock.ink(forPath: entry.path) : Ink.faint)
                            .frame(width: 16)
                        Text(entry.name)
                            .font(Typography.body)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                    }
                    .frame(height: Shell.row)
                }
            }
            .padding(.horizontal, Shell.panelInset)
            .padding(.vertical, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A link in the panel: the provider's embed or the page itself, live,
/// under the head that names the site, with the address and the way out
/// to the browser at the foot. A video sits at 16:9 with its title and
/// blurb under it; a post or a page fills the panel.
struct LinkInspector: View {
    let node: CanvasNode
    @ObservedObject private var previews = LinkPreviews.shared

    private var address: String { node.url ?? "" }
    private var url: URL? { LinkKind.webURL(address) }
    private var kind: LinkKind { LinkKind.classify(address) }

    var body: some View {
        let meta = previews.meta(for: address)
        VStack(spacing: 0) {
            if let url {
                if kind.isVideo {
                    EmbedWebView(url: url, kind: kind)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.well))
                        .padding(.horizontal, Shell.panelInset)
                        .padding(.top, Space.xs)
                    ScrollView { details(meta) }
                } else {
                    EmbedWebView(url: url, kind: kind)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Not a web address.")
                    .font(Typography.body)
                    .foregroundStyle(Ink.muted)
                    .padding(.horizontal, Shell.panelInset)
                    .padding(.vertical, Space.m)
                Spacer()
            }
            foot
        }
    }

    private func details(_ meta: LinkMeta?) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let title = meta?.title {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Ink.primary)
            }
            if let author = meta?.author {
                Text(author)
                    .font(Typography.body)
                    .foregroundStyle(Ink.muted)
            }
            if let text = meta?.description {
                Text(text)
                    .font(Typography.body)
                    .foregroundStyle(Ink.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Shell.panelInset)
        .padding(.vertical, Space.l)
    }

    private var foot: some View {
        HStack(spacing: Space.s) {
            Text(address)
                .font(Typography.meta)
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            if let url {
                Button("Open in the browser") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.outline)
            }
        }
        .padding(.horizontal, Shell.panelInset)
        .frame(height: 48)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }
}

struct GroupInspector: View {
    let node: CanvasNode
    @ObservedObject var store: CanvasStore
    @State private var label = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)
                .font(Typography.body)
                .onSubmit { store.setLabel(node.id, label) }
            HStack(spacing: Space.s) {
                ForEach([nil, "1", "2", "3", "4", "5", "6"], id: \.self) { color in
                    Button {
                        store.setColor([node.id], color)
                    } label: {
                        Circle()
                            .fill(Hepta.label(color))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(node.color == color ? Ink.primary : Ink.hairline, lineWidth: node.color == color ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Shell.panelInset)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { label = node.label ?? "" }
    }
}
