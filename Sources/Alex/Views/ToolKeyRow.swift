import SwiftUI
import AppKit

/// Settings' Tools section (revision 40): one row per tool the palette
/// holds, its glyph and name on the left and its key on the right as a
/// `KeyCap`. Click the cap and press a key: a letter or a digit, no
/// modifier, since a tool's key is bare on the desk and the menu bar
/// holds the ⌘ ones. Esc keeps the old key, ⌫ clears it (a tool with no
/// key is picked from the palette alone), and a key another tool holds
/// is refused in a sentence under the row, the row still listening, so
/// the next try is one press away. Shaped after Nolisen's recorder and
/// Raycast's hotkey rows, in the sheet's own rows (revision 41).
struct ToolKeysSection: View {
    @ObservedObject private var keys = ToolKeys.shared

    var body: some View {
        SettingsSection("Tools") {
            ForEach(ToolKeys.Tool.allCases, id: \.id) { tool in
                ToolKeyRow(tool: tool)
            }
            HStack(alignment: .top, spacing: Space.m) {
                SettingsNote("A key picks its tool on the desk, never while writing in a note. "
                             + "Click a key to change it: one letter or digit.")
                Spacer(minLength: Space.m)
                Button("Reset to defaults") { keys.reset() }
                    .buttonStyle(.outline)
                    .disabled(keys.isDefault)
                    .padding(.top, Space.xs)
            }
        }
    }
}

struct ToolKeyRow: View {
    let tool: ToolKeys.Tool
    @ObservedObject private var keys = ToolKeys.shared
    @State private var monitor: Any?
    @State private var problem: String?
    @State private var hovering = false

    private var recording: Bool { keys.recording == tool }
    private var cap: String? { keys.cap(for: tool) }
    private static let forced = Launch.value(after: "--record")

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            LabeledContent {
                field
            } label: {
                HStack(spacing: Space.s) {
                    GlyphImage(tool.symbol)
                        .foregroundStyle(Ink.icon)
                        .frame(width: Icon.box(Icon.control))
                    Text(tool.name)
                        .font(Typography.body)
                        .foregroundStyle(Ink.primary)
                }
            }
            if let problem {
                Text(problem)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.xs)
                    .transition(.opacity)
            } else if recording {
                Text("Press a key. Esc keeps \(cap.map { "the \($0)" } ?? "it empty"), ⌫ clears it.")
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.xs)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: problem)
        .animation(Motion.fade, value: recording)
        // Another row started listening: this one lets go.
        .onChange(of: keys.recording) { _, now in if now != tool { stop() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // A snapshot run's window is never key for long; its row
            // keeps listening for the picture.
            if recording, Self.forced == nil { stop() }
        }
        .onAppear {
            // `--record <tool name>`: this row listening, for a snapshot,
            // once the window has settled.
            guard Self.forced == tool.name else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                start()
            }
        }
        .onDisappear { stop() }
        .accessibilityElement(children: .contain)
    }

    /// The cap, or the listening field in its place: the one blue edge
    /// says which row hears the next key.
    private var field: some View {
        Button { recording ? stop() : start() } label: {
            Group {
                if recording {
                    Text("Type a key")
                        .font(Typography.meta)
                        .foregroundStyle(Ink.muted)
                        .padding(.horizontal, Space.s)
                    .frame(minHeight: Shell.keyCap)
                    .background(RoundedRectangle(cornerRadius: Radius.mark).fill(Ink.well))
                    .overlay(RoundedRectangle(cornerRadius: Radius.mark).strokeBorder(Accent.text, lineWidth: 1))
                } else if let cap {
                    KeyCap(cap)
                } else {
                    Text("None")
                        .font(Typography.meta)
                        .foregroundStyle(Ink.faint)
                        .padding(.horizontal, Space.s)
                        .frame(minHeight: Shell.keyCap)
                        .background(RoundedRectangle(cornerRadius: Radius.mark)
                            .strokeBorder(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                }
            }
            .opacity(hovering && !recording ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .accessibilityLabel("\(tool.name) key")
        .accessibilityValue(cap ?? "None")
        .accessibilityHint(recording ? "Press a key. Escape keeps the old one." : "Click to change")
    }

    // MARK: Listening

    private func start() {
        problem = nil
        keys.recording = tool
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil  // nothing else hears a key while a row listens
        }
    }

    private func stop() {
        removeMonitor()
        problem = nil
        if keys.recording == tool { keys.recording = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53 { stop(); return }  // esc
        if event.keyCode == 51 || event.keyCode == 117 { // ⌫, ⌦
            keys.set(nil, for: tool)
            stop()
            return
        }
        guard modifiers.subtracting(.shift).isEmpty,
              let typed = event.charactersIgnoringModifiers?.lowercased().first,
              ToolKeys.accepts(typed) else {
            problem = "A tool's key is one letter or digit, with no modifier."
            return
        }
        if let why = keys.set(typed, for: tool) {
            problem = why
            return
        }
        stop()
    }
}
