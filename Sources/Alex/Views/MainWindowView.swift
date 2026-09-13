import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var vault: Vault
    @ObservedObject var model: AppModel
    @ObservedObject private var store: CanvasStore
    /// `--select <vault path>` preselects a file at launch, for snapshots.
    @State private var sidebarSelection: String? = Launch.value(after: "--select")
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
                    .overlay(alignment: .top) {
                        if store.showSearch {
                            ZStack(alignment: .top) {
                                Color.black.opacity(0.08)
                                    .ignoresSafeArea()
                                    .onTapGesture { store.showSearch = false }
                                SearchPanel(store: store)
                                    .padding(.top, 72)
                            }
                        }
                    }
                    .ignoresSafeArea(.container, edges: .top)
                    .inspector(isPresented: $store.inspectorVisible) {
                        InspectorView(store: store)
                            .inspectorColumnWidth(min: 340,
                                                  ideal: 560 + 400 * CGFloat(store.pinnedPanels.count),
                                                  max: 1400)
                    }
                    .toolbar(removing: .title)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    .toolbar {
                        ToolbarItemGroup(placement: .navigation) {
                            Button {
                                store.goUp()
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .disabled(store.directory.isEmpty)
                            .help("Up one folder")
                            BreadcrumbBar(store: store)
                        }
                        ToolbarItemGroup(placement: .primaryAction) {
                            TopBarMenu(store: store)
                            Button {
                                store.showJournal.toggle()
                                if store.showJournal { store.inspectorVisible = true }
                            } label: {
                                Label("Journal", systemImage: "calendar")
                            }
                            .help("The Journal: a note per day")
                            Button {
                                store.inspectorVisible.toggle()
                            } label: {
                                Label("Panel", systemImage: "sidebar.trailing")
                            }
                            .keyboardShortcut("i", modifiers: [.command, .option])
                            .help("Show or hide the panel")
                        }
                    }
            }
            .environmentObject(store)
            .focusedSceneValue(\.canvasStore, store)
            .navigationTitle("")
            .onChange(of: sidebarSelection) { _, path in
                if let path { store.reveal(path) }
            }
            .onChange(of: store.selection) { _, selection in
                if !selection.isEmpty {
                    store.inspectorVisible = true
                    store.showJournal = false
                }
            }
            .task {
                if let path = sidebarSelection { store.reveal(path) }
                // `--arrange <dir>`: open a directory and lay it out by its
                // rule, for a scripted check of canvas.config.json.
                if let dir = Launch.value(after: "--arrange") {
                    store.openDirectory(dir)
                    store.arrangeByConfig()
                }
                // `--journal on`: open the Journal panel, for a scripted check.
                if Launch.value(after: "--journal") == "on" {
                    store.showJournal = true
                    store.inspectorVisible = true
                }
                if let day = Launch.value(after: "--day"), let date = JournalConfig.formatter.date(from: day) {
                    store.journalDate = date
                }
                // `--pin <vault path>`: a pinned panel beside the live one.
                if let pin = Launch.value(after: "--pin") {
                    store.pinnedPanels = [.file(pin)]
                    store.inspectorVisible = true
                }
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
