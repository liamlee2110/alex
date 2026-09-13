import SwiftUI
import AppKit

/// The right-hand panel: whatever is selected, in full. A note opens in the
/// editor and saves itself; a file the app cannot edit is shown as the OS
/// shows it.
struct InspectorView: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        Group {
            if let node = store.selectedNode {
                NodeInspector(node: node, store: store)
                    .id(node.id)
            } else {
                EmptyInspector(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.card)
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
            header
            if changedOnDisk { banner }
            content
        }
        .onAppear(perform: load)
        .onChange(of: vault.generation) { _, _ in checkDisk() }
        .onChange(of: text) { _, _ in scheduleSave() }
        .onDisappear(perform: flush)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                PanelButton(symbol: "chevron.right.2", help: "Close the panel") { store.select(nil) }
                Spacer()
                if dirty {
                    Text("Saving")
                        .font(Typography.micro)
                        .foregroundStyle(Ink.faint)
                }
                if let url {
                    PanelButton(symbol: "arrow.up.forward.square", help: "Reveal in Finder", round: true) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            HStack(spacing: Space.s) {
                Image(systemName: kind.symbol)
                    .foregroundStyle(Ink.muted)
                Text(name)
                    .font(Typography.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Spacer()
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
        }
        .padding(Space.l)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let fm = Frontmatter.parse(text)
                    if !fm.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(fm.order, id: \.self) { key in
                                if let value = fm[key], !value.isEmpty {
                                    HStack(spacing: 4) {
                                        Text(key)
                                            .foregroundStyle(Ink.faint)
                                        Text(value.display)
                                            .foregroundStyle(Ink.muted)
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
                    MarkdownEditor(text: $text, imageBase: url?.deletingLastPathComponent(), imageStem: stem)
                        .padding(Space.l)
                }
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
            if let url { PDFPreview(url: url) } else { cannotShow }
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
                MarkdownEditor(text: $text)
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
            Text("Group")
                .font(Typography.title)
            TextField("Label", text: $label)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard var latest = store.document.node(node.id) else { return }
                    latest.label = label
                    store.update(latest)
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
