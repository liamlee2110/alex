import AppKit

@MainActor
enum VaultPicker {
    static func choose(into vault: Vault) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose the folder to open as a vault."
        if panel.runModal() == .OK, let url = panel.url {
            vault.open(url)
        }
    }
}
