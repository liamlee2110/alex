import SwiftUI

/// Replaces the generic system panel with the small branded surface. It is
/// deliberately a separate window: About is identity, not a setting.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Alex") { openWindow(id: "about") }
        }
    }
}

struct CanvasStoreKey: FocusedValueKey {
    typealias Value = CanvasStore
}

extension FocusedValues {
    var canvasStore: CanvasStore? {
        get { self[CanvasStoreKey.self] }
        set { self[CanvasStoreKey.self] = newValue }
    }
}

/// The shell's sidebar switch, so the View menu can flip it.
struct SidebarVisibleKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var sidebarVisible: Binding<Bool>? {
        get { self[SidebarVisibleKey.self] }
        set { self[SidebarVisibleKey.self] = newValue }
    }
}

/// The File and Canvas menus. Every verb here is also reachable on the
/// desk itself; the menu is where the shortcuts live.
struct CanvasCommands: Commands {
    @FocusedValue(\.canvasStore) private var store
    @FocusedValue(\.sidebarVisible) private var sidebarVisible

    /// A verb on the selection, unless a box is being written in. The
    /// focused store is a reference the menu does not observe, so this is
    /// checked when the key is pressed, not drawn into `disabled`.
    private func deskAction(_ act: (CanvasStore) -> Void) {
        guard let store, !store.isWriting, !store.selection.isEmpty else { return }
        act(store)
    }

    private func step(_ direction: Int) {
        guard let vault = store?.vault, let next = vault.workspace(stepping: direction) else { return }
        vault.switchWorkspace(to: next)
    }

    var body: some Commands {
        // The system's own sidebar item toggled a split view this window no
        // longer has; these two are the shell's panels.
        CommandGroup(replacing: .sidebar) {
            Button(sidebarVisible?.wrappedValue == false ? "Show the sidebar" : "Hide the sidebar") {
                withAnimation(Motion.move) { sidebarVisible?.wrappedValue.toggle() }
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(sidebarVisible == nil)
            Button(store?.inspectorVisible == true ? "Hide the sheet" : "Show the sheet") {
                store?.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(store == nil)
            Divider()
            // Arc's keys for its spaces: the page slides the way the arrow points.
            Button("Next workspace") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled((store?.vault.workspaces.count ?? 0) < 2)
            Button("Previous workspace") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled((store?.vault.workspaces.count ?? 0) < 2)
        }
        CommandGroup(replacing: .newItem) {
            Button("New note") { store?.newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store == nil)
            Button("New sticky note") { store?.addSticky(at: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store == nil)
            Button("New link…") { store?.showLinkPrompt = true }
                .keyboardShortcut("l", modifiers: .command)
            Button("New workspace…") { store?.showNewWorkspace = true }
                .disabled(store == nil)
                .disabled(store == nil)
        }
        CommandMenu("Canvas") {
            Button("Find in vault…") { store?.showSearch = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(store == nil)
            Button("Find on canvas…") { store?.showFindPanel() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(store == nil)
            Button("Arrange by frontmatter") { store?.arrangeByConfig() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(store == nil)
            Divider()
            Button("Group selection") { store?.groupSelection() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(store == nil)
            Button("Fold or unfold") { if let store { store.toggleFold(store.selection) } }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(store == nil)
            Button("Add to the side panel") { store?.pinLivePanel() }
                .keyboardShortcut(.return, modifiers: .option)
                .disabled(store == nil)
            Button("Remove from canvas") { if let store { store.remove(store.selection) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store == nil)
            // Excalidraw's keys (revision 53), on the desk: a box being
            // written in keeps them from acting. ⌘[ stays Back to Home.
            Button("Duplicate") { deskAction { $0.duplicate($0.selection) } }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store == nil)
            Button("Bring to front") { deskAction { $0.bringToFront($0.selection) } }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(store == nil)
            Button("Send to back") { deskAction { $0.sendToBack($0.selection) } }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(store == nil)
            Button("Place everything not yet placed") { store?.placeAllUnplaced() }
                .disabled(store == nil)
            Divider()
            Button("Zoom in") { store?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(store == nil)
            Button("Zoom out") { store?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(store == nil)
            Button("Actual size") { store?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(store == nil)
            Button("Fit to contents") { store?.fit() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(store == nil)
            Divider()
            Button("Back to Home") { store?.goUp() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(store == nil)
        }
    }
}

/// The app menu's Settings… (⌘,): the sheet over the desk (revision 41),
/// in the place the `Settings` scene's item held. The store's flag rather
/// than a focused value, so ⌘, works on the welcome card too.
struct SettingsCommands: Commands {
    let store: CanvasStore

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { store.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
