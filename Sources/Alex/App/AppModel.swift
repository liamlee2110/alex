import AppKit
import Combine

/// Everything the app owns, in one place: the vault, the open canvas, the
/// door's brain and its socket. Created once by the App and handed down.
@MainActor
final class AppModel: ObservableObject {
    static let doorKey = "doorEnabled"

    let vault: Vault
    let canvas: CanvasStore
    /// The quick sketch's desk (revision 59), on the same vault.
    let sketch: CanvasStore
    let rpc: McpRpc
    let door: McpServer

    private var subscriptions: Set<AnyCancellable> = []

    init(arguments: [String] = CommandLine.arguments) {
        vault = Vault(arguments: arguments)
        canvas = CanvasStore(vault: vault)
        sketch = CanvasStore(vault: vault, role: .sketch)
        rpc = McpRpc(vault: vault, canvas: canvas)
        door = McpServer(rpc: rpc)
        rpc.activate = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
        }
        // `--door on` forces the door open for a scripted check; otherwise the
        // Settings toggle decides. (A value, not a bare flag: AppKit reads
        // `-key value` pairs off the command line as defaults overrides, and a
        // bare flag shifts every pair after it.)
        let enabled = Launch.value(after: "--door", in: arguments) == "on"
            || UserDefaults.standard.bool(forKey: Self.doorKey)
        door.apply(enabled: enabled)
        door.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &subscriptions)
    }

    /// The sketch's tab's Open in Alex: that canvas in the window, the
    /// window in front.
    func openInWindow(_ path: String) {
        canvas.openCanvas(at: path)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }?
            .makeKeyAndOrderFront(nil)
    }

    func setDoor(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.doorKey)
        door.apply(enabled: enabled)
    }

    /// The vault-side half of the registration: the file Claude Code reads
    /// when the vault is opened as a project.
    static let mcpJSON = """
        {
          "mcpServers": {
            "alex": {
              "type": "http",
              "url": "\(McpServer.endpoint)"
            }
          }
        }

        """

    static let claudeCommand = "claude mcp add --transport http alex \(McpServer.endpoint)"

    func writeMcpJSON() throws {
        try vault.write(Self.mcpJSON, to: ".mcp.json")
    }

    var hasMcpJSON: Bool { vault.exists(".mcp.json") }
}
