import SwiftUI
import AppKit

/// The shell (PLAN.md, revisions 21 and 37), the shape of Figma's. No top
/// bar and no toolbar: the desk runs the window's full height, and every
/// piece of chrome, the window's own traffic lights included, lives in
/// the sidebar, a card floating over the desk's left, the full height
/// less a gutter all round, dragged wider at its trailing edge. ⌘\ folds
/// it into its head — the lights and the toggle — and the desk is clean.
/// The detail sheet floats over the desk's right the same way and slides
/// in and out.
///
/// The title bar is hidden and its container, where AppKit keeps the
/// lights, is made as tall as the sidebar's head row (`WindowChrome`);
/// the head row's glyphs are ordinary content under it.
struct MainWindowView: View {
    @EnvironmentObject private var vault: Vault
    @ObservedObject var model: AppModel
    @ObservedObject private var store: CanvasStore
    /// `--select <vault path>` preselects a file at launch, for snapshots.
    /// `--select <vault path>`: that file revealed at launch.
    private let launchSelection = Launch.value(after: "--select")
    /// The sidebar: shown or folded to its head (⌘\), remembered between
    /// launches; `--sidebar on|off` sets it for a snapshot without touching
    /// what is remembered. Its width is remembered too, from its edge's
    /// drag.
    @State private var sidebarVisible = Launch.value(after: "--sidebar").map { $0 == "on" }
        ?? (UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true)
    @State private var sidebarWidth: CGFloat = {
        let remembered = UserDefaults.standard.object(forKey: "sidebarWidth") as? CGFloat ?? Shell.sidebar
        return min(max(remembered, Shell.sidebarMin), Shell.sidebarMax)
    }()
    /// The panel stack's width: the ideal for its pins until it is dragged.
    @State private var panelWidth = Shell.panelWidth(pins: 0)

    init(model: AppModel) {
        self.model = model
        store = model.canvas
    }

    /// One brand hue means the system's controls too: a default button and
    /// a toggle take the accent rather than whatever colour the Mac is set
    /// to, so nothing in the window is a second blue.
    var body: some View {
        content.tint(Accent.text)
    }

    private var content: some View {
        ZStack {
            Ink.card.ignoresSafeArea()
            if vault.root == nil {
                VStack(spacing: 0) {
                    Rectangle().fill(Ink.hairline).frame(height: 1)
                    WelcomeView()
                }
                .background(Ink.desk)
            } else {
                shell
            }
        }
        .overlay { settings }
        .onAppear {
            // `--settings on`: the sheet up at launch, for a snapshot.
            if Launch.value(after: "--settings") == "on" { store.showSettings = true }
        }
    }

    /// Settings (revision 41): a sheet centred over everything, the desk
    /// under the ⌘K scrim, which closes it when pressed.
    private var settings: some View {
        ZStack {
            if store.showSettings {
                Ink.scrim
                    .ignoresSafeArea()
                    .onTapGesture { store.showSettings = false }
                    .transition(.opacity)
                SettingsSheet(model: model)
                    .padding(Shell.gutter)
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: store.showSettings)
        // The window's full height, not the hidden title bar's remainder.
        .ignoresSafeArea()
    }

    private var shell: some View {
        desk
        .ignoresSafeArea()
        .background(WindowChrome(leading: Shell.lightsLeading, centreY: Shell.lightsCentre))
        .navigationTitle("")
        .environmentObject(store)
        .focusedSceneValue(\.canvasStore, store)
        .focusedSceneValue(\.sidebarVisible, $sidebarVisible)
        .onChange(of: sidebarVisible) { _, shown in
            if Launch.value(after: "--sidebar") == nil {
                UserDefaults.standard.set(shown, forKey: "sidebarVisible")
            }
        }
        .onChange(of: sidebarWidth) { _, width in
            UserDefaults.standard.set(width, forKey: "sidebarWidth")
        }
        .onChange(of: store.showNewWorkspace) { _, prompt in
            // The prompt stands over the sidebar's foot, so a folded
            // sidebar unfolds for it (File › New workspace…).
            if prompt, !sidebarVisible { withAnimation(Motion.move) { sidebarVisible = true } }
        }
        .onChange(of: store.selection) { _, _ in
            if store.selectionHasPanel {
                store.inspectorVisible = true
                store.closeFind()
            } else {
                store.settlePanel()
            }
        }
        .onChange(of: store.pinnedPanels.count) { _, pins in
            withAnimation(Motion.move) {
                panelWidth = Shell.panelWidth(pins: pins)
            }
        }
        .task {
            // What ⌘F reads of a link beyond its address: its page's
            // title, author and site, as the card shows them.
            store.linkWords = { address in
                guard let meta = LinkPreviews.shared.meta(for: address) else { return [] }
                return [meta.title, meta.author, meta.provider].compactMap { $0 }
            }
            if let path = launchSelection { store.reveal(path) }
            // `--select-all on`: every node selected, so a snapshot shows
            // the style panel without a click (revision 55).
            if Launch.value(after: "--select-all") == "on" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { store.selectAll() }
            }
            // `--arrange <canvas>`: open a canvas and lay it out by its
            // rule, for a scripted check of canvas.config.json.
            if let canvas = Launch.value(after: "--arrange") {
                store.openCanvas(at: canvas)
                store.arrangeByConfig()
            }
            // `--rename <canvas>` and `--canvas-look <canvas>`: a canvas's
            // row as its name field, or its icon and colour picker open,
            // for a snapshot (revision 54).
            if let path = Launch.value(after: "--rename") { store.renaming = path }
            if let path = Launch.value(after: "--canvas-look") { store.lookPicking = path }
            // `--link-prompt on`: the palette's link prompt open, for a snapshot.
            if Launch.value(after: "--link-prompt") == "on" {
                store.showLinkPrompt = true
            }
            // `--find <query>`: find on canvas open on a query, for a snapshot.
            if let query = Launch.value(after: "--find") {
                store.showFindPanel()
                store.findQuery = query
            }
            // `--pin <vault path>`: a pinned panel beside the live one.
            if let pin = Launch.value(after: "--pin") {
                store.pinnedPanels = [.file(pin)]
                store.inspectorVisible = true
            }
            // A launch that revealed a directory selected nothing, and
            // a panel with nothing in it steps out.
            store.settlePanel()
        }
    }

    // MARK: - The desk

    /// The desk, the window's full height, and what floats over it: the
    /// sidebar's card at its left, the detail sheet at its right, each a
    /// gutter from every edge. The sidebar folds into its head row, the
    /// lights and the toggle, which stays at the desk's top left; the card
    /// is dragged wider at its trailing edge. The sheet keeps the width it
    /// was given for its pins until dragged at its leading edge, and never
    /// leaves the desk less than `Shell.deskMin` — unless its columns
    /// cannot read any narrower, when the desk yields. What floats is told
    /// to the store as the desk's insets, which a fit and the desk's own
    /// chrome keep clear of; the folded head takes none, as the zoom bar
    /// takes none.
    private var desk: some View {
        GeometryReader { geo in
            let sheetWidth = fitted(panelWidth, in: geo.size.width)
            let insets = CanvasStore.Insets(
                top: Shell.gutter,
                leading: sidebarVisible ? sidebarWidth + 2 * Shell.gutter : 0,
                bottom: CanvasStore.paletteRoom,
                trailing: store.inspectorVisible ? sheetWidth + 2 * Shell.gutter : 0)
            ZStack(alignment: .topLeading) {
                if store.isOpen {
                    CanvasView(store: store)
                } else {
                    FirstCanvasView(store: store)
                        .padding(EdgeInsets(top: 0, leading: insets.leading, bottom: 0, trailing: insets.trailing))
                        .background(Ink.desk)
                }
                Sidebar(store: store, door: model.door, shown: $sidebarVisible)
                    .frame(width: sidebarVisible ? sidebarWidth : Shell.sidebarFolded,
                           height: sidebarVisible ? max(geo.size.height - 2 * Shell.gutter, Shell.headRow) : Shell.headRow,
                           alignment: .topLeading)
                    .floatingCard()
                    .overlay(alignment: .trailing) {
                        if sidebarVisible {
                            SplitHandle(line: false) { delta in
                                sidebarWidth = min(max(sidebarWidth + delta, Shell.sidebarMin), Shell.sidebarMax)
                            }
                        }
                    }
                    .padding(Shell.gutter)
                if store.inspectorVisible {
                    InspectorView(store: store)
                        .frame(width: sheetWidth)
                        .overlay(alignment: .leading) {
                            SplitHandle(line: false) { delta in
                                panelWidth = fitted(panelWidth - delta, in: geo.size.width)
                            }
                        }
                        .padding(Shell.gutter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.move, value: store.inspectorVisible)
            .animation(Motion.move, value: sidebarVisible)
            .onChange(of: insets, initial: true) { _, new in store.deskInsets = new }
        }
        .overlay(alignment: .top) {
            if store.showSearch {
                ZStack(alignment: .top) {
                    Ink.scrim
                        .onTapGesture { store.showSearch = false }
                    SearchPanel(store: store)
                        .padding(.top, Space.xl * 3)
                }
            }
        }
    }

    private func fitted(_ width: CGFloat, in deskWidth: CGFloat) -> CGFloat {
        let floor = max(Shell.panelMin, InspectorView.minimumWidth(for: store))
        let room = max(floor, deskWidth - Shell.deskMin - 2 * Shell.gutter)
        return min(max(width, floor), min(Shell.panelMax, room))
    }
}

/// No vault open (revision 49): straight on the grey, no sheet round it,
/// the mascot, a sentence a person who has never heard of a vault can
/// follow, and the two ways in side by side as white cards with pictures — start a new workspace from the starter one, or open a folder
/// already on the Mac. Starting asks only for a name, on the same card.
struct WelcomeView: View {
    @EnvironmentObject private var vault: Vault
    @State private var naming = false
    @State private var name = WelcomeView.suggestedName
    @State private var failure: String?
    @FocusState private var nameFocused: Bool

    static let suggestedName = "My workspace"

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: Space.l) {
            ArtworkImage(art: .welcome, side: Art.hero)
            VStack(spacing: Space.s) {
                Text(naming ? "Name your workspace" : "Welcome to Alex")
                    .font(Typography.display)
                Text(naming
                     ? "It starts empty, ready for your first canvas. You can rename it later."
                     : "Lay out your notes, ideas and files as cards on a desk. Everything is kept as ordinary files on your Mac.")
                    .font(Typography.body)
                    .foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if naming { nameForm } else { choices }
            if let notice = failure ?? (naming ? nil : vault.trouble) {
                Text(notice)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: 520)
        .animation(Motion.move, value: naming)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // `--welcome new`: the naming step up, for a snapshot.
            if Launch.value(after: "--welcome") == "new" { startNaming() }
        }
    }

    private var choices: some View {
        HStack(spacing: Space.m) {
            WelcomeChoice(art: .cards, title: "Start a new workspace",
                          detail: "An empty folder for your canvases and notes.") { startNaming() }
            WelcomeChoice(art: .folders, title: "Open a folder",
                          detail: "Use notes you already have. Your files stay where they are.") {
                VaultPicker.choose(into: vault)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Space.s)
    }

    private var nameForm: some View {
        VStack(spacing: Space.m) {
            TextField("Workspace name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(Typography.body)
                .multilineTextAlignment(.leading)
                .focused($nameFocused)
                .onSubmit(create)
                .onChange(of: name) { _, _ in failure = nil }
            Text("It will be a folder called “\(trimmed.isEmpty ? "…" : trimmed)” in \(place).")
                .font(Typography.meta)
                .foregroundStyle(Ink.muted)
            HStack(spacing: Space.s) {
                Button("Back") { naming = false; failure = nil }
                    .buttonStyle(.outline)
                    .keyboardShortcut(.cancelAction)
                Button("Create workspace") { create() }
                    .buttonStyle(.solid)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .frame(width: 320)
        .padding(.top, Space.s)
    }

    /// Where the folder goes, said the way Finder's sidebar says it.
    private var place: String {
        let parent = vault.newWorkspaceParent.standardizedFileURL
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.standardizedFileURL
        if parent == documents { return "your Documents folder" }
        if parent == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL { return "your home folder" }
        return NewWorkspacePrompt.shown(parent)
    }

    private func startNaming() {
        naming = true
        failure = nil
        DispatchQueue.main.async { nameFocused = true }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        do {
            try vault.createWorkspace(named: name)
        } catch {
            failure = (error as? NewWorkspace.Failure)?.description ?? error.localizedDescription
        }
    }
}

/// One way in on the welcome page: a picture, a name and a sentence on a
/// white card that lifts under the pointer, the whole card the button.
private struct WelcomeChoice: View {
    let art: Artwork
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s) {
                ArtworkImage(art: art, side: Art.choice)
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Ink.primary)
                Text(detail)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Ink.card)
                .elevation(hovering ? .lifted : .card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Ink.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .focusRing(cornerRadius: Radius.card)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// A workspace with no canvas (revision 54): the desk asks for the first
/// one. The mascot holding a blank card, a line on what a canvas is, and
/// the name already typed and selected, so a name and ↩ make it. Nothing
/// else on the desk — no palette, no zoom bar — until there is one.
struct FirstCanvasView: View {
    @ObservedObject var store: CanvasStore
    @State private var name = FirstCanvasView.suggestedName
    @State private var failure: String?
    @FocusState private var focused: Bool

    static let suggestedName = "Untitled canvas"

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: Space.l) {
            ArtworkImage(art: .emptyCanvas, side: Art.hero)
            VStack(spacing: Space.s) {
                Text("Create your first canvas")
                    .font(Typography.display)
                Text("A canvas is a desk for one subject: notes, files, links and shapes laid out side by side.")
                    .font(Typography.body)
                    .foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Space.m) {
                TextField("Canvas name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.body)
                    .multilineTextAlignment(.leading)
                    .focused($focused)
                    .onSubmit(create)
                    .onChange(of: name) { _, _ in failure = nil }
                    .accessibilityLabel("Canvas name")
                Button("Create canvas") { create() }
                    .buttonStyle(.solid)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
                if let failure {
                    Text(failure)
                        .font(Typography.meta)
                        .foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 320)
            .padding(.top, Space.s)
        }
        .multilineTextAlignment(.center)
        .frame(width: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            name = Self.suggestedName
            DispatchQueue.main.async {
                focused = true
                // The suggestion selected whole, so typing replaces it.
                NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSText }?.selectAll(nil)
            }
        }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        switch CanvasStore.validCanvasName(name) {
        case .failure(let why):
            failure = why.description
        case .success:
            if store.newCanvas(named: name) == nil { failure = store.trouble }
        }
    }
}
