import SwiftUI
import AppKit

/// The sidebar (PLAN.md, revisions 21 and 37), the shape of Figma's: one
/// card floating over the desk's left, the full height less a gutter all
/// round, holding everything the window has for chrome. At its head, the
/// window's own traffic lights (`WindowChrome` lays them there) and the
/// toggle, then a new note at the far end; then the open
/// workspace's page — its canvases (Figma's boards; the vault's tree left
/// in revision 34, the desk and ⌘K being where files are found); and at
/// the foot, small, the workspace itself, whose menu switches workspaces.
/// ⌘\ or the toggle folds the card into its head — the lights and the
/// toggle, nothing else — the way Excalidraw's menu folds into the one
/// button at its canvas's corner, and the glyph stays where it was; the
/// rest of the desk is clean. Nothing is drawn above it, and nothing here
/// is blue (revision 18): where you are is a grey square.
///
/// A workspace is a vault. Switching slides the page out and the next one
/// in the way Arc's spaces slide: from the foot's menu, ⌥⌘← and →, or two
/// fingers across the sidebar.
struct Sidebar: View {
    @EnvironmentObject private var vault: Vault
    @ObservedObject var store: CanvasStore
    @ObservedObject var door: McpServer
    @Binding var shown: Bool

    var body: some View {
        VStack(spacing: 0) {
            SidebarHead(store: store, shown: $shown)
            if shown {
                ZStack {
                    if let root = vault.root {
                        CanvasList(store: store)
                            .id(root.standardizedFileURL.path)
                            .transition(.asymmetric(
                                insertion: .move(edge: vault.switchDirection > 0 ? .trailing : .leading),
                                removal: .move(edge: vault.switchDirection > 0 ? .leading : .trailing)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .animation(Motion.move, value: vault.root)
                .overlay(alignment: .bottom) {
                    if store.showNewWorkspace {
                        NewWorkspacePrompt(store: store)
                            .padding(Space.s)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(Motion.quick, value: store.showNewWorkspace)
                Rectangle().fill(Ink.hairline).frame(height: 1)
                WorkspaceFoot(store: store, door: door)
                    .padding(Space.s)
            }
        }
        .background(SwipeCatcher { step in
            if let next = vault.workspace(stepping: step) { vault.switchWorkspace(to: next) }
        })
        .onAppear { if NewWorkspacePrompt.forced != nil { store.showNewWorkspace = true } }
    }
}

/// The sidebar's head row: room for the traffic lights, which the window
/// lays there, then the toggle; shown, a new note at the far end. Home
/// is not here: the list's first row is Home, and ⌘[ goes there (one
/// verb per place, revision 19). Folded, the row is the whole sidebar
/// (`Shell.sidebarFolded`), so the lights and the toggle never move. The
/// sheet hides from its own head (one collapse glyph per surface).
struct SidebarHead: View {
    @ObservedObject var store: CanvasStore
    @Binding var shown: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            Color.clear.frame(width: Shell.lightsWidth, height: 1)
            IconButton(symbol: .panelLeft,
                       label: shown ? "Hide the sidebar" : "Show the sidebar",
                       shortcut: "⌘\\") {
                withAnimation(Motion.move) { shown.toggle() }
            }
            if shown {
                Spacer(minLength: Space.xs)
                IconButton(symbol: .squarePen, label: "New note", hint: "New note (⌘N)") {
                    store.newNote()
                }
            }
        }
        // The lights stand at one place in the window: the card is a
        // gutter in from its edge.
        .padding(.leading, Shell.lightsLeading - Shell.gutter)
        .padding(.trailing, Space.s)
        .frame(height: Shell.headRow)
        .windowDragArea()
    }
}

extension View {
    /// With no title bar left, the blank of a head row is what moves the
    /// window, as a title bar's would (revision 21); a glyph on it still
    /// takes its own press.
    func windowDragArea() -> some View {
        background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
            .allowsWindowActivationEvents(true)
    }

    /// A surface standing alone over the desk (revision 21): the sidebar's
    /// card and the detail sheet — white at the panel radius, a hairline
    /// and the floating chrome's shadow.
    func floatingCard() -> some View {
        self
            .background(RoundedRectangle(cornerRadius: Radius.panel).fill(Ink.float))
            .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Ink.hairline, lineWidth: 1))
            .elevation(.raised)
    }
}

/// The sidebar's foot: the open workspace, small — its mark, its name, a
/// dot for the door while it has a state — and pressing it is the
/// workspace menu: the workspaces, the way to add one, Settings.
struct WorkspaceFoot: View {
    @EnvironmentObject private var vault: Vault
    @ObservedObject var store: CanvasStore
    @ObservedObject var door: McpServer

    @State private var hovered = false

    var body: some View {
        MenuButton(name: "Workspaces", placement: .above) {
            WorkspaceMenu.items(vault: vault, store: store)
        } label: { open in
            HStack(spacing: Space.s) {
                WorkspaceMark(name: vault.name,
                              icon: vault.root.flatMap { vault.workspaceIcons[$0.path] },
                              open: true)
                Text(vault.name)
                    .font(Typography.control)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                DoorDot(door: door, trouble: vault.trouble ?? store.trouble)
                Spacer(minLength: Space.xs)
                GlyphImage(.chevronsUpDown, size: Icon.mark, weight: .medium)
                    .foregroundStyle(Ink.icon)
            }
            .padding(.horizontal, Space.xs)
            .frame(height: Shell.row + Space.xs)
            .background(RoundedRectangle(cornerRadius: Radius.control)
                .fill(open ? Ink.wellHover : hovered ? Ink.well : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(Motion.quick, value: hovered)
        .tooltip(vault.root?.path ?? vault.name, name: "Workspaces")
        .accessibilityLabel("Workspace \(vault.name)")
    }
}

/// The workspace card's menu: every workspace, the open one ticked, then
/// the verbs on the list and Settings.
@MainActor
/// The workspace menu (revision 34): a switcher, as Figma's account menu
/// and Notion's workspace menu are. The workspaces, the open one ticked
/// and the others with their remove at the row's end; one way to add one;
/// Settings. What is about the open folder — reveal it, open another —
/// is the File menu's.
enum WorkspaceMenu {
    @MenuBuilder
    static func items(vault: Vault, store: CanvasStore) -> [MenuItem] {
        for url in vault.workspaces {
            let isOpen = vault.root.map { Vault.same($0, url) } ?? false
            // The open workspace cannot leave the list; the others show
            // their remove at the row's end under the pointer, the list's
            // one remove. It forgets the folder, never touches it (D7's
            // spirit, the list's verb).
            MenuItem(url.lastPathComponent, checked: isOpen,
                     trailing: isOpen ? nil : .init(symbol: .x, label: "Remove from the list") {
                         vault.forget(url)
                     }) {
                vault.switchWorkspace(to: url)
            }
        }
        MenuItem.divider
        MenuItem("New workspace…") { store.showNewWorkspace = true }
        MenuItem.divider
        MenuItem("Settings…") { store.showSettings = true }
    }
}

/// "New workspace…": a name, and a folder of that name beside the open
/// workspace, seeded from the starter vault and switched to (revision 31).
/// A card over the sidebar's foot, as the link prompt floats over the
/// palette; where it goes is said under the field, not asked, and so is
/// the other way in — ⌘O for a folder you already have — since the
/// menu's one add is this (revision 34).
struct NewWorkspacePrompt: View {
    @EnvironmentObject private var vault: Vault
    @ObservedObject var store: CanvasStore
    @State private var name = ""
    @State private var failure: String?
    @FocusState private var focused: Bool

    /// `--new-workspace <name>`: the prompt open with a name typed, for a
    /// snapshot run.
    nonisolated static let forced = Launch.value(after: "--new-workspace")

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("New workspace")
                .font(Typography.title)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(Typography.body)
                .focused($focused)
                .onSubmit(create)
                .onChange(of: name) { _, _ in failure = nil }
            Text(failure ?? "A folder in \(Self.shown(vault.newWorkspaceParent)), started from the template vault. "
                 + "A folder you already have opens with ⌘O.")
                .font(Typography.meta)
                .foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                Spacer()
                Button("Cancel") { store.showNewWorkspace = false }
                    .buttonStyle(.outline)
                    .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .buttonStyle(.solid)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .onExitCommand { store.showNewWorkspace = false }
        .onAppear {
            if name.isEmpty, let typed = Self.forced { name = typed }
            focused = true
        }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        do {
            try vault.createWorkspace(named: name)
            store.showNewWorkspace = false
        } catch {
            failure = (error as? NewWorkspace.Failure)?.description ?? error.localizedDescription
        }
    }

    /// A folder as a person says it: `~/workspace`, not `/Users/…/workspace`.
    static func shown(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// The door's state as a dot after the workspace's name: blue while it
/// serves, grey when it cannot or the vault is in trouble, the reason in
/// its tooltip; nothing when the door is off and all is well.
struct DoorDot: View {
    @ObservedObject var door: McpServer
    let trouble: String?

    var body: some View {
        if let state {
            Circle()
                .fill(state.live ? Accent.text : Ink.faint)
                .frame(width: Icon.dot, height: Icon.dot)
                .padding(Space.xs)
                .contentShape(Rectangle())
                .tooltip(state.hint, name: state.text)
                .accessibilityLabel(state.text)
        }
    }

    private var state: (text: String, hint: String, live: Bool)? {
        if let trouble { return ("Trouble", trouble, false) }
        switch door.status {
        case .off: return nil
        case .serving: return ("Door open", "Door open: Claude Code can read and place cards through the door", true)
        case .failed(let why): return ("Door not serving", "Door not serving: \(why)", false)
        }
    }
}

/// Figma's boards: every canvas in the vault, the open one on the grey
/// square (no Home since revision 54). At the head, find, a new canvas and
/// the open canvas's own verbs behind `•••` (the "N not placed" capsule of
/// revision 19 left in revision 44). Each row wears its canvas's icon in
/// its colour; a double-click or Rename makes its name a field, its
/// icon and colour are picked under it, and Delete moves its file to the
/// Trash (revision 65).
/// It slides with its workspace.
struct CanvasList: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Space.xs) {
                Text("Canvases")
                    .lineLimit(1)
                    .fixedSize()
                    .font(Typography.control)
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.xs)
                IconButton(symbol: .search, label: "Find in vault",
                           hint: "Find a file or a note (⌘K)", size: .small) {
                    store.showSearch = true
                }
                IconButton(symbol: .plus, label: "New canvas", size: .small) {
                    store.newCanvas()
                }
                CanvasMenu(store: store)
            }
            .padding(.leading, Space.m)
            .padding(.trailing, Space.s)
            .frame(height: Shell.row + Space.s)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(store.canvases, id: \.self) { path in
                        CanvasRow(store: store, path: path)
                        if store.lookPicking == path {
                            CanvasLookPicker(store: store, path: path)
                                .padding(.vertical, Space.xs)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, Space.s)
                .padding(.bottom, Space.s)
                .animation(Motion.quick, value: store.lookPicking)
            }
        }
    }
}

/// The verbs on one canvas: its row's right-click menu, and the open
/// one's under the Canvases `•••`. Delete, last and alone (revision 65),
/// moves the canvas file to the Trash, where Put Back is the undo.
@MainActor
enum CanvasVerbs {
    @MenuBuilder
    static func items(for path: String, store: CanvasStore) -> [MenuItem] {
        MenuItem("Rename") { store.renaming = path }
        MenuItem("Icon and colour…") { store.lookPicking = path }
        MenuItem.divider
        MenuItem("Reveal in Finder") {
            if let url = store.vault.url(for: path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        MenuItem.divider
        MenuItem("Delete") { store.deleteCanvas(path) }
    }
}

/// A canvas's row: its icon in its colour — pressed alone, the icon and
/// colour picker (revision 55) — and its name, or, while it is renamed, its name as a field (Figma's page rename). ↩ or leaving the
/// field renames the file; Esc keeps the name.
struct CanvasRow: View {
    @ObservedObject var store: CanvasStore
    let path: String

    var body: some View {
        let look = store.look(for: path)
        let glyph = look.icon.flatMap(Glyph.init(rawValue:)) ?? VaultEntry.Kind.canvas.symbol
        if store.renaming == path {
            CanvasNameField(store: store, path: path, glyph: glyph, ink: CanvasRow.ink(look))
        } else {
            SidebarRow(symbol: glyph,
                       label: store.canvasName(path),
                       active: path == store.canvasPath,
                       glyphInk: CanvasRow.ink(look),
                       hint: store.canvasName(path),
                       glyphAction: { store.lookPicking = store.lookPicking == path ? nil : path },
                       glyphLabel: "Change icon and colour") {
                store.openCanvas(at: path)
            }
            // A Button's own action fires at once; the double-click
            // beside it renames without holding the single click back.
            .simultaneousGesture(TapGesture(count: 2).onEnded { store.renaming = path })
            .rowMenu { CanvasVerbs.items(for: path, store: store) }
        }
    }

    /// The glyph's ink: the canvas's colour, else a place's ink.
    static func ink(_ look: CanvasStore.CanvasLook) -> Color {
        look.color.map { Hepta.label($0) } ?? Ink.icon
    }
}

/// The row's name as a field, typed name selected whole.
private struct CanvasNameField: View {
    @ObservedObject var store: CanvasStore
    let path: String
    let glyph: Glyph
    let ink: Color

    @State private var name = ""
    @State private var failure: String?
    @State private var done = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                GlyphImage(glyph)
                    .foregroundStyle(ink)
                    .frame(width: 16)
                TextField("Canvas name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Typography.control)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onChange(of: name) { _, _ in failure = nil }
                    .onChange(of: focused) { _, now in if !now { commit() } }
                    .accessibilityLabel("Canvas name")
            }
            .padding(.horizontal, Space.s)
            .frame(height: Shell.row)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Ink.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Accent.text, lineWidth: 1))
            if let failure {
                Text(failure)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.s)
            }
        }
        .onAppear {
            name = store.canvasName(path)
            DispatchQueue.main.async {
                focused = true
                NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSText }?.selectAll(nil)
            }
        }
    }

    private func commit() {
        guard !done, store.renaming == path else { return }
        if let why = store.renameCanvas(path, to: name) {
            // Leaving the field with a name it cannot take keeps the old.
            if focused { failure = why.description; return }
            cancel()
            return
        }
        done = true
        store.renaming = nil
    }

    private func cancel() {
        done = true
        store.renaming = nil
    }
}

/// A canvas's icon and colour (revision 54), picked in a card under its
/// row: the colours with Done at their end, then the icons, each in the
/// colour picked, as many to a line as the sidebar is wide. A pick is
/// written to the canvas file at once; Done or Esc closes it.
struct CanvasLookPicker: View {
    @ObservedObject var store: CanvasStore
    let path: String

    // As many icons to a line as fit, the line's slack shared between them,
    // so a wide sidebar takes fewer lines rather than a blank margin.
    private let columns = [GridItem(.adaptive(minimum: IconButton.Size.small.side.width), spacing: Space.xs)]

    var body: some View {
        let look = store.look(for: path)
        let current = look.icon.flatMap(Glyph.init(rawValue:)) ?? VaultEntry.Kind.canvas.symbol
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 0) {
                ForEach(NodeMenu.colours, id: \.0) { name, code in
                    Swatch(name: name, code: code, active: look.color == code) {
                        var next = look
                        next.color = code
                        store.setLook(next, for: path)
                    }
                }
                Spacer(minLength: Space.s)
                Button("Done") { store.lookPicking = nil }
                    .buttonStyle(.outline)
                    .keyboardShortcut(.cancelAction)
            }
            LazyVGrid(columns: columns, spacing: Space.xs) {
                ForEach(Glyph.canvasIcons, id: \.self) { glyph in
                    IconButton(symbol: glyph, label: CanvasLookPicker.name(of: glyph), size: .small,
                               active: glyph == current, ink: CanvasRow.ink(look)) {
                        var next = look
                        next.icon = glyph == VaultEntry.Kind.canvas.symbol ? nil : glyph.rawValue
                        store.setLook(next, for: path)
                    }
                }
            }
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .onExitCommand { store.lookPicking = nil }
    }

    /// An icon as a person says it: `graduation-cap` is "Graduation cap".
    static func name(of glyph: Glyph) -> String {
        if glyph == VaultEntry.Kind.canvas.symbol { return "Default" }
        return IconPrompt.spoken(glyph.rawValue)
    }
}

/// One row of the sidebar's nav: a small glyph, a label, and a count at the
/// far end when there is one. The row you are on — the open canvas, the
/// tray while it is up, the file the panel shows — wears the grey square
/// with its name in the identifying weight; the pointer's row wears the
/// well.
struct SidebarRow: View {
    let symbol: Glyph
    let label: String
    var count: Int = 0
    var active = false
    /// The glyph's ink: `Ink.icon` for a place, `Ink.faint` for a file's
    /// kind, as in the tree.
    var glyphInk: Color = Ink.icon
    var hint: String? = nil
    /// The glyph pressed on its own (revision 55): a canvas's icon opens
    /// its icon and colour picker, as a chat's or a page's icon does in
    /// ChatGPT and Notion. Named by `glyphLabel`.
    var glyphAction: (() -> Void)? = nil
    var glyphLabel = ""
    let action: () -> Void

    @State private var hovered = false

    // A canvas's colour stays on its glyph when it is open.
    private var ink: Color { active && glyphInk == Ink.icon ? Ink.primary : glyphInk }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if glyphAction == nil {
                    GlyphImage(symbol)
                        .foregroundStyle(ink)
                        .frame(width: 16)
                } else {
                    // Room for the glyph's own button, laid over the row.
                    Color.clear.frame(width: 16, height: 1)
                }
                Text(label)
                    .font(active ? Typography.control : Typography.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)
                if count > 0 {
                    Text("\(count)")
                        .font(Typography.micro)
                        .monospacedDigit()
                        .foregroundStyle(Ink.muted)
                }
            }
            .padding(.horizontal, Space.s)
            .frame(height: Shell.row)
            .background(RoundedRectangle(cornerRadius: Radius.control)
                .fill(active ? Ink.wellHover : hovered ? Ink.well : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if let glyphAction {
                IconButton(symbol: symbol, label: glyphLabel, size: .small, ink: ink, action: glyphAction)
                    .padding(.leading, Space.s - (IconButton.Size.small.side.width - 16) / 2)
            }
        }
        .onHover { hovered = $0 }
        .animation(Motion.quick, value: hovered)
        .tooltip(hint ?? label, name: label)
        .accessibilityLabel(label)
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

/// A workspace's mark: its `icon` from `canvas.config.json`, else the
/// initial of its name, on a small square. Solid blue while open, the
/// tool in hand's square (revision 30): the one square that is you.
struct WorkspaceMark: View {
    let name: String
    let icon: String?
    let open: Bool
    var fill: Color? = nil

    var body: some View {
        Group {
            if let icon, let glyph = GlyphImage(named: icon) {
                glyph
            } else {
                // The one letter of a name is its sentence case (law 6).
                Text(String(name.prefix(1)).capitalized)
                    .font(Typography.label)
            }
        }
        .foregroundStyle(open ? Accent.onSolid : Ink.muted)
        .frame(width: IconButton.Size.small.side.width, height: IconButton.Size.small.side.height)
        .background(RoundedRectangle(cornerRadius: Radius.control)
            .fill(fill ?? (open ? Accent.solid : Ink.well)))
        .accessibilityHidden(true)
    }
}

/// Two fingers across the sidebar switch workspaces, the way they switch
/// Arc's spaces. An `NSView` under the sidebar that takes no clicks and
/// watches the wheel events over its bounds through a local monitor (the
/// mechanism `EventCatcher` uses for the desk): a trackpad gesture whose
/// travel is mostly sideways fires once when it has gone `Shell.swipe`,
/// and its sideways events are kept from the tree, which has nothing to
/// do with them. Up-and-down events, and a mouse's wheel, pass through.
struct SwipeCatcher: NSViewRepresentable {
    /// +1 for a swipe leftward (further along the foot), -1 for rightward.
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onSwipe = onSwipe
    }
}

final class SwipeView: NSView {
    var onSwipe: ((Int) -> Void)?
    private var monitor: Any?
    private var travel: CGFloat = 0
    private var fired = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window == window else { return event }
            let p = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(p) else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Only a gesture has phases; a wheel's ticks are not a swipe.
        guard event.phase != [] || event.momentumPhase != [] else { return event }
        if event.phase == .began { travel = 0; fired = false }
        if event.phase == .ended || event.phase == .cancelled { travel = 0 }
        guard event.momentumPhase == [] else { return event }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) else { return event }
        travel += dx
        if !fired, abs(travel) >= Shell.swipe {
            fired = true
            onSwipe?(travel < 0 ? 1 : -1)
        }
        return nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
