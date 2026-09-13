import SwiftUI
import AppKit

/// The right-hand side: Heptabase's stack of panels. Pinned panels sit to
/// the left; the live panel on the right follows the selection, or shows
/// the Journal. Each panel has the `>>` and `+` row and a bordered title.
struct InspectorView: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(store.pinnedPanels, id: \.self) { target in
                PanelColumn(store: store, target: target)
                    .frame(minWidth: 320, maxWidth: .infinity)
                Divider()
            }
            PanelColumn(store: store, target: nil)
                .frame(minWidth: 320, maxWidth: .infinity)
        }
        .background(Ink.card)
    }
}

/// One panel: pinned to a target, or live (nil) and following the selection.
struct PanelColumn: View {
    @ObservedObject var store: CanvasStore
    let target: CanvasStore.PanelTarget?

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            if let target {
                PanelButton(symbol: "chevron.right.2", help: "Close this panel") { store.unpin(target) }
            } else {
                PanelButton(symbol: "chevron.right.2", help: "Hide the panel") { store.inspectorVisible = false }
                PanelButton(symbol: "plus", help: "Keep this panel open and start another") { store.pinLivePanel() }
            }
            Spacer()
            if let path = currentPath, let url = store.vault.url(for: path) {
                PanelButton(symbol: "arrow.up.forward.square", help: "Reveal in Finder", round: true) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private var currentPath: String? {
        switch target {
        case .file(let path): return path
        case .journal: return store.journalPath
        case nil:
            if store.showJournal { return store.journalPath }
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
        case .journal:
            JournalView(store: store)
        case nil:
            if store.showJournal {
                JournalView(store: store)
            } else if let node = store.selectedNode {
                NodeInspector(node: node, store: store)
                    .id(node.id)
            } else {
                EmptyInspector(store: store)
            }
        }
    }
}

struct EmptyInspector: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(store.title)
                .font(Typography.title)
            Text("\(store.document.nodes.count) on the canvas · \(store.unplaced.count) not placed")
                .font(Typography.meta)
                .foregroundStyle(Ink.muted)
            if !store.unplaced.isEmpty {
                Text("Not placed yet")
                    .font(Typography.label)
                    .foregroundStyle(Ink.faint)
                    .padding(.top, Space.s)
                Text("Drag one onto the desk, or place it beside the selection.")
                    .font(Typography.meta)
                    .foregroundStyle(Ink.faint)
                ForEach(store.unplaced) { entry in
                    HStack {
                        Label(entry.name, systemImage: entry.kind.symbol)
                            .font(Typography.body)
                            .lineLimit(1)
                        Spacer()
                        Button("Place") { store.place(entry.path) }
                            .font(Typography.control)
                    }
                    .contentShape(Rectangle())
                    .draggable(store.vault.url(for: entry.path) ?? URL(fileURLWithPath: "/"))
                }
            }
            Spacer()
            Text("Select a card to read it here.")
                .font(Typography.meta)
                .foregroundStyle(Ink.faint)
        }
        .padding(Space.l)
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
            TextNodeInspector(node: node, store: store)
        case .link:
            LinkInspector(node: node)
        case .group:
            GroupInspector(node: node, store: store)
        case .other:
            Text("A \(node.kind.typeName) node from another app.")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
                .padding(Space.l)
        }
    }
}

struct FileInspector: View {
    let path: String
    @ObservedObject var store: CanvasStore
    /// Inside the Journal the day heading stands in for the title row.
    var embedded = false
    @EnvironmentObject private var vault: Vault

    @State private var text = ""
    @State private var diskText = ""
    @State private var pendingDisk = ""
    @State private var dirty = false
    @State private var changedOnDisk = false
    @State private var saveTask: Task<Void, Never>?

    private var name: String { VaultPath.name(of: path) }
    private var stem: String { (name as NSString).deletingPathExtension }
    private var url: URL? { vault.url(for: path) }
    private var kind: VaultEntry.Kind {
        vault.isDirectory(path) ? .directory : .forExtension((name as NSString).pathExtension)
    }
    private var editable: Bool { kind.isTextual && kind != .canvas }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { titleRow }
            if changedOnDisk { banner }
            content
        }
        .onAppear(perform: load)
        .onChange(of: vault.generation) { _, _ in checkDisk() }
        .onChange(of: text) { _, _ in scheduleSave() }
        .onDisappear(perform: flush)
    }

    private var titleRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: kind.symbol)
                .foregroundStyle(Ink.muted)
            Text(name)
                .font(Typography.body)
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
            Spacer()
            if dirty {
                Text("Saving")
                    .font(Typography.micro)
                    .foregroundStyle(Ink.faint)
            }
            Text(VaultPath.parent(of: path))
                .font(Typography.meta)
                .foregroundStyle(Ink.faint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Space.m)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.m)
    }

    private var banner: some View {
        HStack(spacing: Space.s) {
            Text("Changed on disk while you were editing.")
                .font(Typography.meta)
                .foregroundStyle(Ink.primary)
            Spacer()
            Button("Reload") {
                text = pendingDisk
                diskText = pendingDisk
                dirty = false
                changedOnDisk = false
            }
            Button("Keep mine") {
                changedOnDisk = false
                write()
            }
        }
        .font(Typography.control)
        .padding(Space.m)
        .background(Accent.wash)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .markdown:
            let editorAndInfo = VStack(alignment: .leading, spacing: 0) {
                let fm = Frontmatter.parse(text)
                if !fm.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(fm.order, id: \.self) { key in
                            if let value = fm[key], !value.isEmpty {
                                HStack(spacing: 4) {
                                    Text(key).foregroundStyle(Ink.faint)
                                    Text(value.display).foregroundStyle(Ink.muted)
                                }
                                .font(Typography.micro)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Ink.well))
                            }
                        }
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.m)
                }
                MarkdownEditor(text: $text, imageBase: url?.deletingLastPathComponent(), imageStem: stem,
                               onOpenLink: { name in store.openNote(named: name, from: path) })
                    .padding(Space.l)
                InfoBlock(path: path, text: text, store: store)
            }
            if embedded {
                editorAndInfo
            } else {
                ScrollView { editorAndInfo }
            }
        case .code, .text, .canvas:
            PlainTextEditor(text: $text, editable: editable)
        case .image:
            if let url, let image = NSImage(contentsOf: url) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(Space.l)
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
        case .other:
            cannotShow
        }
    }

    private var cannotShow: some View {
        VStack(spacing: Space.s) {
            Text("Alex can't show this file yet.")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
            if let url {
                Button("Open with the default app") { NSWorkspace.shared.open(url) }
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
            Label("Info", systemImage: "info.circle")
                .font(Typography.label)
                .foregroundStyle(Ink.muted)
                .padding(.top, Space.s)
            row("clock", "Created", dates.created.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
            row("clock.arrow.circlepath", "Updated", dates.modified.map { $0.formatted(.relative(presentation: .named)) } ?? "—")
            row("textformat", "Count", "\(words) words · \(text.count) characters")
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: "rectangle.3.group").frame(width: 16).foregroundStyle(Ink.faint)
                Text("Canvases (\(canvases.count))").foregroundStyle(Ink.faint).frame(width: 110, alignment: .leading)
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
            .font(Typography.meta)
            row("number", "Tags", tags.map(\.display).flatMap { $0.isEmpty ? nil : $0 } ?? "none")
            if !backlinks.isEmpty {
                Divider().padding(.top, Space.s)
                Label("Backlinks (\(backlinks.count))", systemImage: "arrow.turn.up.left")
                    .font(Typography.label)
                    .foregroundStyle(Ink.muted)
                    .padding(.top, Space.s)
                ForEach(backlinks, id: \.self) { link in
                    Button {
                        store.reveal(link.source)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(VaultIndex.stem(of: link.source), systemImage: "doc.text")
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
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.xl)
    }

    private func canvasName(_ canvas: String) -> String {
        let dir = VaultPath.parent(of: canvas)
        return dir.isEmpty ? vault.name : dir
    }

    private func row(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol).frame(width: 16).foregroundStyle(Ink.faint)
            Text(label).foregroundStyle(Ink.faint).frame(width: 110, alignment: .leading)
            Text(value).foregroundStyle(Ink.primary)
        }
        .font(Typography.meta)
    }
}

struct DirectoryInspector: View {
    let path: String
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault

    var body: some View {
        let entries = vault.root.flatMap { try? VaultListing.entries(in: path, root: $0) } ?? []
        VStack(alignment: .leading, spacing: Space.m) {
            Button {
                store.openDirectory(path)
            } label: {
                Label("Open this folder", systemImage: "arrow.right.circle")
            }
            .keyboardShortcut(.defaultAction)
            ForEach(entries) { entry in
                Label(entry.name, systemImage: entry.kind.symbol)
                    .font(Typography.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TextNodeInspector: View {
    let node: CanvasNode
    @ObservedObject var store: CanvasStore
    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sticky note")
                .font(Typography.title)
                .padding(Space.l)
            Divider()
            ScrollView {
                MarkdownEditor(text: $text, onOpenLink: { name in store.openNote(named: name, from: nil) })
                    .padding(Space.l)
            }
        }
        .onAppear { text = node.text ?? "" }
        .onChange(of: text) { _, new in
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, var latest = store.document.node(node.id), latest.text != new else { return }
                latest.text = new
                store.update(latest)
            }
        }
    }
}

struct LinkInspector: View {
    let node: CanvasNode

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Link")
                .font(Typography.title)
            Text(node.url ?? "")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
                .textSelection(.enabled)
            if let url = node.url.flatMap(URL.init(string:)) {
                Button("Open in the browser") { NSWorkspace.shared.open(url) }
            }
            Spacer()
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GroupInspector: View {
    let node: CanvasNode
    @ObservedObject var store: CanvasStore
    @State private var label = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Section")
                .font(Typography.title)
            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)
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
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { label = node.label ?? "" }
    }
}

/// The panel's small bordered buttons, square or round.
struct PanelButton: View {
    let symbol: String
    let help: String
    var round = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.control)
                .foregroundStyle(Ink.icon)
                .frame(width: 28, height: 28)
                .background {
                    if round {
                        Circle().fill(Ink.card)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.control).fill(Ink.card)
                    }
                }
                .overlay {
                    if round {
                        Circle().strokeBorder(Ink.hairline, lineWidth: 1)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Ink.hairline, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
