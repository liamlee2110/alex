import SwiftUI
import AppKit
import ServiceManagement

/// Settings (revision 41): a card centred over the desk under the ⌘K
/// scrim, the way Heptabase's, Notion's and Figma's settings open over
/// the app rather than in a window of their own — every piece of the
/// chrome is in the window since revision 21, and the system's Settings
/// window was the one surface outside it. One head row, the name and the
/// close glyph; then the sections in the app's own rows: a label at the
/// left, the control at the right, a hairline above each row, a sentence
/// under what needs one. Opened from the workspace menu, from the app
/// menu's Settings… (⌘,) and by `--settings on`; Esc, the glyph or a
/// press on the desk closes it. As tall as its rows, and it scrolls when
/// the window is shorter.
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: CanvasStore
    @ObservedObject var vault: Vault
    @ObservedObject var door: McpServer
    @ObservedObject private var previews = LinkPreviews.shared
    @State private var doorEnabled = UserDefaults.standard.bool(forKey: AppModel.doorKey)
    @State private var wroteRegistration = false
    @State private var showRegistrationSuccess = false
    @State private var registrationError: String?
    @State private var registrationFeedbackTask: Task<Void, Never>?
    /// The sections' height: the card is as tall as they are, and no
    /// taller than the desk lets it be.
    @State private var bodyHeight: CGFloat = 0
    @State private var escape: Any?

    /// The ⌘K panel's width.
    static let width: CGFloat = 560

    init(model: AppModel) {
        self.model = model
        store = model.canvas
        vault = model.vault
        door = model.door
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            Rectangle().fill(Ink.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    workspace
                    ToolKeysSection()
                    QuickSketchSection()
                    links
                    claudeCode
                }
                .padding(.horizontal, Shell.panelInset)
                .padding(.bottom, Shell.panelInset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
            }
            .frame(maxHeight: bodyHeight > 0 ? bodyHeight : nil)
        }
        .font(Typography.body)
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: Radius.panel).fill(Ink.float))
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.lifted)
        .labeledContentStyle(.settingsRow)
        .onExitCommand(perform: close)
        .onAppear {
            // Esc with nothing in the sheet focused would reach the desk;
            // a row listening for a key keeps its own Esc.
            let store = store
            escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let taken = MainActor.assumeIsolated {
                    guard event.keyCode == 53, ToolKeys.shared.recording == nil else { return false }
                    store.showSettings = false
                    return true
                }
                return taken ? nil : event
            }
        }
        .onDisappear {
            registrationFeedbackTask?.cancel()
            if let escape { NSEvent.removeMonitor(escape) }
            escape = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private func close() { store.showSettings = false }

    /// One head row (revision 18): the name, and the glyph that closes it.
    private var head: some View {
        HStack(spacing: Space.xs) {
            Text("Settings")
                .font(Typography.title)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            IconButton(symbol: .x, label: "Close settings", shortcut: "esc") { close() }
        }
        .padding(.leading, Shell.panelInset)
        .padding(.trailing, Space.m)
        .frame(height: Shell.panelHead)
    }

    private var workspace: some View {
        SettingsSection("Workspace") {
            LabeledContent("Folder") {
                HStack(spacing: Space.s) {
                    Text(vault.root?.path ?? "None open")
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(vault.root == nil ? "Open…" : "Change…") { VaultPicker.choose(into: vault) }
                        .buttonStyle(.outline)
                }
            }
        }
    }

    private var links: some View {
        SettingsSection("Links") {
            LabeledContent("Fetch titles and pictures for link cards") {
                SettingsSwitch("Fetch titles and pictures for link cards", isOn: $previews.enabled)
            }
            SettingsNote("The app's only outbound traffic: it asks the site, or its oEmbed service, "
                         + "for a title and a picture, and keeps them in its cache. Off, a card shows "
                         + "its address, and the panel still embeds the page when you open it.")
        }
    }

    private var claudeCode: some View {
        SettingsSection("Claude Code") {
            LabeledContent("Serve this vault to agents on this Mac") {
                SettingsSwitch("Serve this vault to agents on this Mac", isOn: $doorEnabled)
                    .onChange(of: doorEnabled) { _, on in model.setDoor(enabled: on) }
            }
            LabeledContent("Status") {
                Text(statusLine)
                    .foregroundStyle(statusIsTrouble ? Ink.primary : Ink.muted)
            }
            LabeledContent("Endpoint") {
                Text(McpServer.endpoint)
                    .font(Typography.mono)
                    .foregroundStyle(Ink.muted)
                    .textSelection(.enabled)
            }
            SettingsNote("Two ways to connect. A vault that carries its own `.mcp.json` connects "
                         + "anyone who opens it in Claude Code, after one trust prompt; the command "
                         + "registers the door for this Mac only.")
            HStack(spacing: Space.s) {
                Button(model.hasMcpJSON || wroteRegistration ? "Rewrite .mcp.json in the vault" : "Write .mcp.json into the vault") {
                    writeRegistration()
                }
                .buttonStyle(.outline)
                .disabled(vault.root == nil)
                if model.hasMcpJSON || wroteRegistration {
                    Text("Present")
                        .font(Typography.label)
                        .foregroundStyle(Ink.faint)
                }
            }
            .padding(.bottom, Space.s)
            if showRegistrationSuccess {
                HStack(spacing: Space.m) {
                    Image("alex-live-dot", bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection file written")
                            .font(Typography.heading)
                            .foregroundStyle(Ink.primary)
                        Text("Claude Code can connect after you trust this vault.")
                            .font(Typography.meta)
                            .foregroundStyle(Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, Space.s)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
            if let registrationError {
                Text(registrationError)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.s)
                    .accessibilityLabel("Unable to write the connection file. Check that this vault can be edited and try again.")
            }
            LabeledContent {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AppModel.claudeCommand, forType: .string)
                }
                .buttonStyle(.outline)
            } label: {
                Text(AppModel.claudeCommand)
                    .font(Typography.mono)
                    .foregroundStyle(Ink.muted)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func writeRegistration() {
        do {
            try model.writeMcpJSON()
            wroteRegistration = true
            registrationError = nil
            withAnimation(Motion.fade) { showRegistrationSuccess = true }
            AccessibilityNotification.Announcement("Connection file written to the vault.").post()
            registrationFeedbackTask?.cancel()
            registrationFeedbackTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.fade) { showRegistrationSuccess = false }
            }
        } catch {
            registrationFeedbackTask?.cancel()
            withAnimation(Motion.fade) { showRegistrationSuccess = false }
            let message = "Unable to write .mcp.json. Check that this vault can be edited and try again."
            registrationError = message
            AccessibilityNotification.Announcement(message).post()
        }
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

// MARK: - The sheet's parts

/// A part of Settings, headed the way the detail sheet heads a part
/// (revision 18): a step up from the body in the supporting ink, air
/// above it, its rows under it.
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Typography.section)
                .foregroundStyle(Ink.muted)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.s)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// A settings row: the label at the left in the reading ink, the control
/// at the right, a hairline above. `LabeledContent` in the sheet draws
/// this way, so the tool rows (revision 40) keep their shape.
struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            configuration.label
                .font(Typography.body)
                .foregroundStyle(Ink.primary)
            Spacer(minLength: Space.m)
            configuration.content
        }
        .frame(minHeight: Shell.button + Space.s)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }
}

extension LabeledContentStyle where Self == SettingsRowStyle {
    static var settingsRow: SettingsRowStyle { SettingsRowStyle() }
}

/// A sentence under a row, in the supporting ink.
struct SettingsNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typography.meta)
            .foregroundStyle(Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.s)
    }
}

/// A row's switch: the system's, small, named for a screen reader by the
/// row's label.
struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// The quick sketch (revision 59): the key that brings it from anywhere,
/// and Alex at login, so the key is there from the start.
private struct QuickSketchSection: View {
    @ObservedObject private var hotkey = SketchHotkey.shared
    @State private var key = SketchKey.chosen
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginTrouble: String?

    var body: some View {
        SettingsSection("Quick sketch") {
            LabeledContent("Key from anywhere") {
                MenuButton(name: "sketch-key", items: {
                    for choice in SketchKey.allCases {
                        MenuItem(choice.title, checked: choice == key, shortcut: choice.shortcut) {
                            key = choice
                            UserDefaults.standard.set(choice.rawValue, forKey: SketchKey.defaultsKey)
                            hotkey.apply(choice)
                        }
                    }
                }) { _ in
                    HStack(spacing: Space.s) {
                        if let shortcut = key.shortcut { KeyCaps(shortcut) } else { Text("Off") }
                        GlyphImage(.chevronDown, size: Icon.mark, weight: .medium)
                            .foregroundStyle(Ink.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Key from anywhere: \(key.title)")
            }
            SettingsNote(hotkey.failed
                ? "Another app holds that key, so it does nothing. Pick another."
                : "Brings a bare desk over whatever you are doing, on the canvas it last showed. "
                   + "The same key puts it away. New sketches go in the Sketches folder.")
            LabeledContent("Open Alex at login") {
                SettingsSwitch("Open Alex at login", isOn: $atLogin)
                    .onChange(of: atLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginTrouble = nil
                        } catch {
                            loginTrouble = error.localizedDescription
                        }
                    }
            }
            if let loginTrouble { SettingsNote(loginTrouble) }
        }
    }
}
