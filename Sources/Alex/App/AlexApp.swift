import SwiftUI

@main
struct AlexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var vault = Vault(arguments: CommandLine.arguments)

    var body: some Scene {
        WindowGroup("Alex") {
            MainWindowView(vault: vault)
                .environmentObject(vault)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open vault…") { VaultPicker.choose(into: vault) }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
