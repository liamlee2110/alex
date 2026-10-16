import SwiftUI
import AppKit

@main
struct AlexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Alex") {
            MainWindowView(model: model)
                .environmentObject(model.vault)
                .onAppear {
                    delegate.canvas = model.canvas
                    QuickSketch.shared.install(model: model)
                }
                .frame(minWidth: 900, minHeight: 560)
        }
        // The title bar is hidden and there is no toolbar: the lights are
        // laid in the sidebar's head row (`WindowChrome`, revision 21).
        .windowStyle(.hiddenTitleBar)
        .commands {
            AboutCommands()
            CanvasCommands()
            SettingsCommands(store: model.canvas)
            CommandGroup(after: .newItem) {
                Divider()
                Button("Open vault…") { VaultPicker.choose(into: model.vault) }
                    .keyboardShortcut("o", modifiers: .command)
                // The open vault's folder, where a document app keeps it
                // (revision 34): the workspace menu is a switcher only. Not
                // disabled on an empty root: the scene is not rebuilt when
                // the vault opens, so it would stay grey after a first open.
                Button("Reveal in Finder") {
                    if let root = model.vault.root { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                }
            }
        }
        Window("About Alex", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
