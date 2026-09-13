import SwiftUI

/// The breadcrumb in the top bar: the whiteboard glyph, then the vault and
/// each directory down to the open one, separated by faint slashes.
struct BreadcrumbBar: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        let crumbs = store.crumbs
        HStack(spacing: 6) {
            Image(systemName: "map")
                .font(Typography.control)
                .foregroundStyle(Color(light: "2FA66A", dark: "4CD07F"))
            ForEach(Array(crumbs.enumerated()), id: \.offset) { i, crumb in
                Text("/")
                    .font(Typography.body)
                    .foregroundStyle(Ink.faint)
                let last = i == crumbs.count - 1
                Button {
                    store.openDirectory(crumb.path)
                } label: {
                    Text(crumb.name)
                        .font(Typography.body)
                        .foregroundStyle(last ? Ink.primary : Ink.muted)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(last)
            }
        }
    }
}

/// The vertical tool palette at the left edge: a white rounded strip with
/// one icon per verb, the active tool blue. Heptabase's row: select, card,
/// import, arrow, text, section, and more.
struct ToolPalette: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        VStack(spacing: 4) {
            tool("cursorarrow", "Select", active: store.tool == .select) { store.setTool(.select) }
            tool("doc.text", "New note") { store.newNote() }
            tool("square.and.arrow.down", "Import files…") { importFiles() }
            tool("arrow.up.right", "Connect: click a card, then another", active: store.tool == .connect) {
                store.setTool(store.tool == .connect ? .select : .connect)
            }
            tool("textformat", "New sticky note") { store.addSticky(at: nil) }
            tool("rectangle.dashed", "Group selection") { store.groupSelection() }
            tool("magnifyingglass", "Find in vault") { store.showSearch = true }
        }
        .padding(.vertical, 6)
        .frame(width: 40)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .padding(.leading, 12)
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

    private func tool(_ symbol: String, _ help: String, active: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(active ? Accent.text : Ink.icon)
                .frame(width: 32, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The top bar's right cluster: the canvas menu, the Journal, the panel.
struct TopBarMenu: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        Menu {
            Button("Arrange by frontmatter") { store.arrangeByConfig() }
            Button("Place everything not yet placed") { store.placeAllUnplaced() }
            Divider()
            Button("Fit to contents") { store.fit() }
            Button("Actual size") { store.actualSize() }
            Divider()
            Button("Reveal canvas file in Finder") {
                if let url = store.vault.url(for: store.canvasPath) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .help("Canvas")
    }
}

/// The zoom bar at the bottom right: fit, the percentage, plus, minus.
struct ZoomControls: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        HStack(spacing: 6) {
            control("arrow.down.backward.and.arrow.up.forward", "Fit to contents") {
                withAnimation(.easeOut(duration: 0.3)) { store.fit() }
            }
            Button {
                store.actualSize()
            } label: {
                Text("\(Int((store.viewport.scale * 100).rounded()))%")
                    .font(Typography.control)
                    .foregroundStyle(Ink.icon)
                    .frame(minWidth: 44)
            }
            .buttonStyle(.plain)
            .help("Actual size")
            control("plus", "Zoom in") { store.zoomIn() }
            control("minus", "Zoom out") { store.zoomOut() }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .padding(Space.l)
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Ink.icon)
                .frame(width: 32, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
