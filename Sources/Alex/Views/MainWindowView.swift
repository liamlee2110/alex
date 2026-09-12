import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var vault: Vault
    @ObservedObject var model: AppModel
    @ObservedObject private var store: CanvasStore
    /// `--select <vault path>` preselects a file at launch, for snapshots.
    @State private var sidebarSelection: String? = Launch.value(after: "--select")
    @State private var showInspector = Launch.value(after: "--select") != nil
    @State private var columns: NavigationSplitViewVisibility = .all

    init(model: AppModel) {
        self.model = model
        store = model.canvas
    }

    var body: some View {
        if vault.root == nil {
            WelcomeView()
        } else {
            NavigationSplitView(columnVisibility: $columns) {
                SidebarView(selection: $sidebarSelection, door: model.door)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
            } detail: {
                CanvasView(store: store)
                    .inspector(isPresented: $showInspector) {
                        InspectorView(store: store)
                            .inspectorColumnWidth(min: 320, ideal: 460, max: 900)
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .navigation) {
                            Button {
                                store.goUp()
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .disabled(store.directory.isEmpty)
                            .help("Up one folder")
                        }
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button {
                                showInspector.toggle()
                            } label: {
                                Label("Inspector", systemImage: "sidebar.trailing")
                            }
                            .keyboardShortcut("i", modifiers: [.command, .option])
                            .help("Show or hide the panel")
                        }
                    }
            }
            .environmentObject(store)
            .focusedSceneValue(\.canvasStore, store)
            .navigationTitle(store.title)
            .onChange(of: sidebarSelection) { _, path in
                if let path { store.reveal(path) }
            }
            .onChange(of: store.selection) { _, selection in
                if !selection.isEmpty { showInspector = true }
            }
            .task {
                if let path = sidebarSelection { store.reveal(path) }
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var vault: Vault

    var body: some View {
        VStack(spacing: Space.m) {
            Text("Alex")
                .font(Typography.display)
            Text("A canvas over a folder of plain files. Open one to begin.")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
            Button("Open a vault…") { VaultPicker.choose(into: vault) }
                .keyboardShortcut(.defaultAction)
                .padding(.top, Space.s)
            if let trouble = vault.trouble {
                Text(trouble)
                    .font(Typography.label)
                    .foregroundStyle(Ink.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.ground)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var vault: Vault
    @Binding var selection: String?
    @ObservedObject var door: McpServer

    var body: some View {
        List(selection: $selection) {
            OutlineGroup(vault.tree, children: \.children) { node in
                Label(node.entry.name, systemImage: node.entry.kind.symbol)
                    .tag(node.entry.path)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(vault.root?.path ?? "")
                    .font(Typography.label)
                    .foregroundStyle(Ink.faint)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text("\(vault.fileCount) files")
                    .font(Typography.label)
                    .foregroundStyle(Ink.faint)
                switch door.status {
                case .off:
                    EmptyView()
                case .serving:
                    Label("Door open for Claude Code", systemImage: "circle.fill")
                        .font(Typography.label)
                        .foregroundStyle(Ink.muted)
                case .failed(let why):
                    Label("Door not serving: \(why)", systemImage: "exclamationmark.circle")
                        .font(Typography.label)
                        .foregroundStyle(Ink.primary)
                }
                if let trouble = vault.trouble {
                    Text(trouble)
                        .font(Typography.label)
                        .foregroundStyle(Ink.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .background(.bar)
        }
    }
}
