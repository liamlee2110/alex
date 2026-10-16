import SwiftUI

/// The tool palette (revision 22): a white bar at the foot of the desk,
/// Figma's bottom toolbar in Alex's ink. The tools you hold — Select;
/// Shapes, a menu of the five wearing the one last drawn; Draw, ink by
/// hand that stays in hand stroke after stroke (revision 58); Text, bare words
/// where the desk is next clicked or dragged; Sticky, a note there — then
/// a hairline, then Add, the one verb, a menu of what brings a file in. A cell that opens a menu says
/// so with a chevron. Every cell is one square, 32 on a side, `Space.s`
/// inside a pill at the panel radius, so hover, press and the tool in
/// hand (the solid square, revision 18) are one shape with an even rim.
/// Each cell wears its key at the corner, as Excalidraw's do, and the
/// keys are `ToolKeys`', which Settings can change (revision 40).
/// Tooltips open above, with the key after the name as a cap. It stands
/// at the window's centre, giving way only to the zoom bar and the
/// sidebar's card when the desk narrows (revision 38).
struct ToolPalette: View {
    @ObservedObject var store: CanvasStore
    @ObservedObject private var keys = ToolKeys.shared

    private var drawTool: DrawTool? {
        if case .draw(let tool) = store.tool { return tool }
        return nil
    }

    var body: some View {
        let shape = drawTool ?? store.lastDrawTool
        HStack(spacing: Space.xs) {
            IconButton(symbol: .mousePointer, label: "Select", shortcut: keys.cap(for: .select), size: .tool,
                       active: store.tool == .select, activeStyle: .solid,
                       key: keys.cap(for: .select)) { store.pressTool(.select) }
            IconMenu(symbol: shape.symbol, label: "Shapes", hint: shape.name,
                     shortcut: keys.cap(for: .draw(shape)),
                     size: .tool, disclosure: true, active: drawTool != nil, activeStyle: .solid,
                     key: keys.cap(for: .draw(shape))) {
                for tool in DrawTool.allCases {
                    MenuItem(tool.name, symbol: tool.symbol, shortcut: keys.cap(for: .draw(tool))) {
                        store.pressTool(.draw(tool))
                    }
                }
            }
            IconButton(symbol: .pen, label: "Draw", shortcut: keys.cap(for: .pen), size: .tool,
                       active: store.tool == .pen, activeStyle: .solid,
                       key: keys.cap(for: .pen)) { store.pressTool(.pen) }
            IconButton(symbol: .type, label: "Text", shortcut: keys.cap(for: .text), size: .tool,
                       active: store.tool == .text, activeStyle: .solid,
                       key: keys.cap(for: .text)) { store.pressTool(.text) }
            IconButton(symbol: .stickyNote, label: "Sticky note", shortcut: keys.cap(for: .sticky), size: .tool,
                       active: store.tool == .sticky, activeStyle: .solid,
                       key: keys.cap(for: .sticky)) { store.pressTool(.sticky) }
            BarDivider()
            IconMenu(symbol: .plus, label: "Add", hint: "Add a note, files or a link",
                     size: .tool, disclosure: true) {
                MenuItem("New note", symbol: .fileText, shortcut: "⌘N") { store.newNote() }
                MenuItem("Import files…", symbol: .import_) { importFiles() }
                MenuItem("Add a link…", symbol: .link, shortcut: "⌘L") { store.showLinkPrompt = true }
            }
        }
        .floatingBar()
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        panel.message = "Files from outside the vault are copied into the open folder."
        guard panel.runModal() == .OK else { return }
        let centre = store.viewport.toWorld(CGPoint(x: store.viewSize.width / 2, y: store.viewSize.height / 2))
        store.importFiles(panel.urls, at: centre)
    }
}

/// The quick sketch's palette (revision 59): the palette folded into one
/// small glyph in the desk's bottom right corner, the tool in hand in the
/// muted ink, no pill and no blue square, so the desk keeps its room and
/// the drawing its eye. Its menu is the palette's cells and Add's verbs, each with
/// its key, so the menu teaches what the keys do.
struct ToolCorner: View {
    @ObservedObject var store: CanvasStore
    @ObservedObject private var keys = ToolKeys.shared

    private var symbol: Glyph {
        switch store.tool {
        case .select: return .mousePointer
        case .draw(let tool): return tool.symbol
        case .pen: return .pen
        case .text: return .type
        case .sticky: return .stickyNote
        }
    }

    var body: some View {
        IconMenu(symbol: symbol, label: "Tools", hint: "Tools", shortcut: keys.cap(for: store.tool),
                 size: .small) {
            MenuItem("Select", symbol: .mousePointer, checked: store.tool == .select,
                     shortcut: keys.cap(for: .select)) { store.pressTool(.select) }
            for tool in DrawTool.allCases {
                MenuItem(tool.name, symbol: tool.symbol, checked: store.tool == .draw(tool),
                         shortcut: keys.cap(for: .draw(tool))) { store.pressTool(.draw(tool)) }
            }
            MenuItem("Draw", symbol: .pen, checked: store.tool == .pen,
                     shortcut: keys.cap(for: .pen)) { store.pressTool(.pen) }
            MenuItem("Text", symbol: .type, checked: store.tool == .text,
                     shortcut: keys.cap(for: .text)) { store.pressTool(.text) }
            MenuItem("Sticky note", symbol: .stickyNote, checked: store.tool == .sticky,
                     shortcut: keys.cap(for: .sticky)) { store.pressTool(.sticky) }
            MenuItem.divider
            MenuItem("New note", symbol: .fileText) { store.newNote() }
            MenuItem("Add a link…", symbol: .link) { store.showLinkPrompt = true }
        }
    }
}

/// The palette's link prompt: one field, filled from the clipboard when
/// the clipboard holds an address, so paste-then-return is the whole move.
/// A card floating over the palette rather than a popover: a popover
/// closes the moment the app is not frontmost, which a scripted snapshot
/// never is, and the desk's own chrome already floats this way.
struct LinkPrompt: View {
    @ObservedObject var store: CanvasStore
    @State private var address = ""
    @FocusState private var focused: Bool

    private var valid: Bool { LinkKind.webURL(address) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Add a link")
                .font(Typography.title)
            Text("A YouTube video, a post on X or Threads, a Pin, or any page. The card shows its title and picture; the panel plays or shows it.")
                .font(Typography.meta)
                .foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(Typography.body)
                .focused($focused)
                .onSubmit(add)
            HStack(spacing: Space.s) {
                Spacer()
                Button("Cancel") { store.showLinkPrompt = false }
                    .buttonStyle(.outline)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .buttonStyle(.solid)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(Space.l)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .onExitCommand { store.showLinkPrompt = false }
        .onAppear {
            if address.isEmpty, let held = NSPasteboard.general.string(forType: .string),
               LinkKind.webURL(held) != nil {
                address = held.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            focused = true
        }
    }

    private func add() {
        guard let node = store.addLink(address, at: nil) else { return }
        store.showLinkPrompt = false
        store.focusRequest = node.id
    }
}

/// The layers' `•••`: the canvas's verbs that have no glyph of their
/// own. The zoom bar has fit and actual size, the workspace's menu has
/// Settings (revisions 19 and 21), so they are not said twice on screen.
struct CanvasMenu: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        IconMenu(symbol: .ellipsis, label: "Canvas menu", hint: "Canvas") {
            MenuItem("Rename", enabled: store.isOpen) { store.renaming = store.canvasPath }
            MenuItem("Icon and colour…", enabled: store.isOpen) { store.lookPicking = store.canvasPath }
            MenuItem.divider
            MenuItem("Arrange by frontmatter", enabled: store.isOpen) { store.arrangeByConfig() }
            MenuItem("Place everything not yet placed", enabled: !store.unplaced.isEmpty) {
                store.placeAllUnplaced()
            }
            MenuItem.divider
            MenuItem("Reveal canvas file in Finder", enabled: store.isOpen) {
                if let url = store.vault.url(for: store.canvasPath) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}

/// The zoom bar at the bottom right: fit, then minus, the percentage and
/// plus, farther to the left of closer as on every zoom control.
struct ZoomControls: View {
    let store: CanvasStore
    /// The percentage follows the camera, and nothing else here does.
    @ObservedObject var camera: Camera

    var body: some View {
        let percent = Int((camera.viewport.scale * 100).rounded())
        HStack(spacing: Space.xs) {
            // The fit itself is the view's, animated there (Motion.camera):
            // the store only asks for it.
            IconButton(symbol: .maximize, label: "Fit to contents", shortcut: "⌘1",
                       size: .bar) { store.fit() }
            IconButton(symbol: .minus, label: "Zoom out", shortcut: "⌘-", size: .bar) { store.zoomOut() }
            Button {
                store.actualSize()
            } label: {
                Text("\(percent)%")
                    .font(Typography.control)
                    .monospacedDigit()
                    .foregroundStyle(Ink.icon)
                    .frame(minWidth: 44, minHeight: 32)
            }
            .buttonStyle(IconButtonStyle())
            .tooltip("Actual size", name: "Actual size", shortcut: "⌘0")
            .accessibilityLabel("Actual size, now \(percent) percent")
            IconButton(symbol: .plus, label: "Zoom in", shortcut: "⌘=", size: .bar) { store.zoomIn() }
        }
        .floatingBar()
        .padding(Space.l)
    }
}

/// The hairline between the palette's tools and its verb.
private struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(width: 1, height: Space.xl - Space.xs)
            .padding(.horizontal, Space.xs)
    }
}

extension View {
    /// The bars at the desk's foot, the palette and the zoom bar
    /// (revision 22): 32-point cells `Space.s` inside a pill at the panel
    /// radius, the radius of every surface standing alone over the desk,
    /// so the cells' well-radius corners run parallel to it; tooltips
    /// open above, where there is room.
    func floatingBar() -> some View {
        padding(Space.s)
            .frame(height: CanvasStore.barHeight)
            .background(RoundedRectangle(cornerRadius: Radius.panel).fill(Ink.float))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Ink.hairline, lineWidth: 1))
            .elevation(.raised)
            .environment(\.tooltipEdge, .above)
    }
}
