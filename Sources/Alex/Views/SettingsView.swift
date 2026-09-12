import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vault: Vault
    @ObservedObject var door: McpServer
    @State private var doorEnabled = UserDefaults.standard.bool(forKey: AppModel.doorKey)
    @State private var wroteRegistration = false

    init(model: AppModel) {
        self.model = model
        vault = model.vault
        door = model.door
    }

    var body: some View {
        Form {
            Section("Vault") {
                LabeledContent("Folder") {
                    HStack {
                        Text(vault.root?.path ?? "None open")
                            .font(Typography.body)
                            .foregroundStyle(Ink.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change…") { VaultPicker.choose(into: vault) }
                    }
                }
            }
            Section("Claude Code") {
                Toggle("Serve this vault to agents on this Mac", isOn: $doorEnabled)
                    .onChange(of: doorEnabled) { _, on in model.setDoor(enabled: on) }
                LabeledContent("Status") {
                    Text(statusLine)
                        .font(Typography.body)
                        .foregroundStyle(statusIsTrouble ? Ink.primary : Ink.muted)
                }
                LabeledContent("Endpoint") {
                    Text(McpServer.endpoint)
                        .font(Typography.mono)
                        .foregroundStyle(Ink.muted)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Two ways to connect. A vault that carries its own `.mcp.json` connects "
                         + "anyone who opens it in Claude Code, after one trust prompt; the command "
                         + "registers the door for this Mac only.")
                        .font(Typography.meta)
                        .foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(model.hasMcpJSON || wroteRegistration ? "Rewrite .mcp.json in the vault" : "Write .mcp.json into the vault") {
                            try? model.writeMcpJSON()
                            wroteRegistration = true
                        }
                        .disabled(vault.root == nil)
                        if model.hasMcpJSON || wroteRegistration {
                            Text("Present")
                                .font(Typography.label)
                                .foregroundStyle(Ink.faint)
                        }
                    }
                    HStack {
                        Text(AppModel.claudeCommand)
                            .font(Typography.mono)
                            .foregroundStyle(Ink.muted)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AppModel.claudeCommand, forType: .string)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.bottom, Space.l)
    }

    private var statusLine: String {
        switch door.status {
        case .off: return doorEnabled ? "Starting…" : "Off"
        case .serving: return "Serving on port \(McpServer.port)"
        case .failed(let why): return "Not serving: \(why)"
        }
    }

    private var statusIsTrouble: Bool {
        if case .failed = door.status { return true }
        return false
    }
}
