import SwiftUI
import AppKit

// The format bar (revision 29): Notion's selection toolbar. Select words in
// a note and a small bar floats over them: what the line is ("Turn into"),
// then the inline marks, each on its grey square while the words wear it.
// Every press is an edit to the Markdown (`NoteFormat`), so it reads the
// same in Obsidian and undoes in one step. The card is the popup menu's:
// the floating white, a hairline, the raised shadow.

/// What the bar shows and what its presses do; the text view fills it.
@MainActor
final class FormatBarModel: ObservableObject {
    @Published var active: Set<NoteFormat.Mark> = []
    @Published var block: NoteFormat.Block = .text
    /// Words on the desk: their size (revision 33); nil in a note, which
    /// has headings instead.
    @Published var size: TextSize?
    /// Their face (revision 36); nil in the panel, whose face is the system's.
    @Published var family: FontFamily?
    var toggle: (NoteFormat.Mark) -> Void = { _ in }
    var resize: (TextSize) -> Void = { _ in }
    var refamily: (FontFamily) -> Void = { _ in }
    var turn: (NoteFormat.Block) -> Void = { _ in }
}

/// The bar's panel: borderless and non-activating like the slash menu's,
/// so a press on it leaves the keyboard with the note, a child of the
/// note's window so it moves with it.
@MainActor
final class FormatBar {
    /// Transparent room round the card for its shadow, as the menu keeps.
    static let margin: CGFloat = Space.m
    /// The gap between the bar and the words it is over.
    static let gap: CGFloat = Space.xs

    /// The bar on screen, if one is: what a snapshot composites in.
    static var showing: NSPanel? { current?.panel.isVisible == true ? current?.panel : nil }
    private static weak var current: FormatBar?

    let model = FormatBarModel()
    private let panel: NSPanel
    private let hosting: NSHostingView<FormatBarView>
    private var monitor: Any?

    init() {
        hosting = NSHostingView(rootView: FormatBarView(model: model))
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shadow is the card's own `Elevation`, not the window's.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }

    /// Over `selection` (screen coordinates), its leading edge at `lead`,
    /// kept inside `room`; under it when there is no room above.
    func show(over selection: NSRect, lead: CGFloat, room: NSRect, in window: NSWindow) {
        let size = hosting.fittingSize
        hosting.setFrameSize(size)
        panel.setContentSize(size)
        let m = Self.margin
        var origin = NSPoint(x: lead - m, y: selection.maxY + Self.gap - m)
        if origin.y + size.height - m > room.maxY {
            origin.y = selection.minY - Self.gap - size.height + m
        }
        origin.x = min(max(origin.x, room.minX - m), room.maxX - size.width + m)
        panel.appearance = window.effectiveAppearance
        panel.setFrameOrigin(origin)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        Self.current = self
        watch()
    }

    func hide() {
        guard panel.isVisible || panel.parent != nil else { return }
        if PopupMenu.shared.isOpen { PopupMenu.shared.close() }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// A scroll or a pinch moves the words out from under the bar: it goes,
    /// and comes back with the next selection.
    private func watch() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            if event.window !== self?.panel { self?.hide() }
            return event
        }
    }
}

struct FormatBarView: View {
    @ObservedObject var model: FormatBarModel

    var body: some View {
        HStack(spacing: 2) {
            turnInto
            if model.size != nil || model.family != nil { textStyle }
            separator
            mark(.bold, .bold, "Bold", "⌘B")
            mark(.italic, .italic, "Italic", "⌘I")
            mark(.underline, .underline, "Underline", "⌘U")
            mark(.strike, .strikethrough, "Strikethrough", "⌘⇧X")
            mark(.code, .code, "Code", "⌘E")
            separator
            mark(.highlight, .highlighter, "Highlight", "⌘⇧H")
            mark(.link, .link, "Link to a note", nil)
        }
        .padding(Space.xs)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .padding(FormatBar.margin)
        // Over the words, so its tooltips go up rather than over them.
        .environment(\.tooltipEdge, .above)
    }

    /// What the line is, as a text button with the menu's chevron.
    private var turnInto: some View {
        MenuButton(name: "Turn into", placement: .below) {
            for kind in NoteFormat.Block.allCases {
                MenuItem(kind.title, symbol: kind.glyph, checked: kind == model.block) { model.turn(kind) }
            }
        } label: { open in
            HStack(spacing: Space.xs) {
                Text(model.block.title)
                    .font(Typography.control)
                    .foregroundStyle(Ink.primary)
                GlyphImage(.chevronDown, size: Icon.mark, weight: .medium)
                    .foregroundStyle(Ink.muted)
            }
            .padding(.horizontal, Space.s)
            .frame(height: IconButton.Size.regular.side.height)
            .background {
                if open { RoundedRectangle(cornerRadius: Radius.control).fill(Ink.wellHover) }
            }
        }
        .buttonStyle(IconButtonStyle(radius: Radius.control))
        .tooltip("Turn into", name: "Turn into")
        .accessibilityLabel("Turn into, \(model.block.title)")
    }

    /// The face and size of the words: a card's face, a sticky's or a
    /// text box's face and size.
    private var textStyle: some View {
        TextStyleMenu(family: model.family, size: model.size,
                      pickFamily: { model.refamily($0) }, pickSize: { model.resize($0) })
    }

    private var separator: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(width: 1, height: Icon.box(Icon.control))
            .padding(.horizontal, 2)
    }

    private func mark(_ mark: NoteFormat.Mark, _ symbol: Glyph, _ label: String,
                      _ shortcut: String?) -> some View {
        IconButton(symbol: symbol, label: label, shortcut: shortcut,
                   active: model.active.contains(mark)) { model.toggle(mark) }
    }
}

/// The face and size of words on the desk in one menu: Excalidraw's three
/// faces (revision 36), a hairline, FigJam's four sizes (revision 33). In
/// the format bar while a card, a sticky or a text box is written in (a
/// card has no size: its headings are its sizes), and in a shape's style
/// bar. One menu rather than two, so the bar keeps one control per job.
struct TextStyleMenu: View {
    let family: FontFamily?
    let size: TextSize?
    let pickFamily: (FontFamily) -> Void
    let pickSize: (TextSize) -> Void

    private var summary: String {
        [family?.title, size?.title].compactMap { $0 }.joined(separator: ", ").lowercased()
    }

    var body: some View {
        MenuButton(name: "Text style", placement: .below) {
            if let family {
                for option in FontFamily.allCases {
                    MenuItem(option.title, checked: option == family) { pickFamily(option) }
                }
            }
            if family != nil, size != nil { MenuItem.divider }
            if let size {
                for option in TextSize.allCases {
                    MenuItem(option.title, checked: option == size) { pickSize(option) }
                }
            }
        } label: { open in
            HStack(spacing: 2) {
                GlyphImage(.aLargeSmall)
                    .foregroundStyle(Ink.icon)
                GlyphImage(.chevronDown, size: Icon.mark, weight: .medium)
                    .foregroundStyle(Ink.muted)
            }
            .padding(.horizontal, Space.s)
            .frame(height: IconButton.Size.regular.side.height)
            .background {
                if open { RoundedRectangle(cornerRadius: Radius.control).fill(Ink.wellHover) }
            }
        }
        .buttonStyle(IconButtonStyle(radius: Radius.control))
        .tooltip("Text style, \(summary)", name: "Text style")
        .accessibilityLabel("Text style, \(summary)")
    }
}

extension NoteFormat.Block {
    /// The slash menu's icon for the same block.
    var glyph: Glyph {
        switch self {
        case .text: return .type
        case .heading1: return .heading1
        case .heading2: return .heading2
        case .heading3: return .heading3
        case .bulleted: return .list
        case .numbered: return .listOrdered
        case .checklist: return .listChecks
        case .quote: return .textQuote
        }
    }
}
