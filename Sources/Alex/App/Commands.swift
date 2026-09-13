import SwiftUI

struct CanvasStoreKey: FocusedValueKey {
    typealias Value = CanvasStore
}

extension FocusedValues {
    var canvasStore: CanvasStore? {
        get { self[CanvasStoreKey.self] }
        set { self[CanvasStoreKey.self] = newValue }
    }
}

/// The File and Canvas menus. Every verb here is also reachable on the
/// desk itself; the menu is where the shortcuts live.
struct CanvasCommands: Commands {
    @FocusedValue(\.canvasStore) private var store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New note") { store?.newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store == nil)
            Button("New sticky note") { store?.addSticky(at: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store == nil)
        }
        CommandMenu("Canvas") {
            Button("Find in vault…") { store?.showSearch = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(store == nil)
            Button("Arrange by frontmatter") { store?.arrangeByConfig() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(store == nil)
            Divider()
            Button("Group selection") { store?.groupSelection() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(store == nil)
            Button("Connect tool") { store?.setTool(store?.tool == .connect ? .select : .connect) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store == nil)
            Button("Keep this panel open") { store?.pinLivePanel() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(store == nil)
            Button("Journal") {
                guard let store else { return }
                store.showJournal.toggle()
                if store.showJournal { store.inspectorVisible = true }
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(store == nil)
            Button("Remove from canvas") { if let store { store.remove(store.selection) } }
                .keyboardShortcut(.delete, modifiers: .command)
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
            Button("Up one folder") { store?.goUp() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(store == nil)
        }
    }
}
