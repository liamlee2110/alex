import SwiftUI

@main
struct AlexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Alex") {
            MainWindowView(model: model)
                .environmentObject(model.vault)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CanvasCommands()
            CommandGroup(after: .newItem) {
                Divider()
                Button("Open vault…") { VaultPicker.choose(into: model.vault) }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
