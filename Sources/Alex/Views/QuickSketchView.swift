import SwiftUI

/// The quick sketch's window (revision 59): a desk and nothing on it, and
/// above it, not on it, a tab rising out of the top edge, centred, the
/// shape of a folder's tab. The tab says which canvas this is and switches
/// it; its blank moves the window. The desk and the tab are one outline,
/// one fill and one hairline, so they read as one sheet of card.
struct QuickSketchView: View {
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault
    let onClose: () -> Void
    let onOpenInWindow: (String) -> Void
    var onStylePanel: ((Bool) -> Void)? = nil
    /// The tab's width, for the window's grips: its top resizes, its
    /// sides do not.
    var onTabWidth: ((CGFloat) -> Void)? = nil
    @State private var tabWidth = Shell.sketchTabMin

    var body: some View {
        let outline = SketchOutline(tabWidth: tabWidth)
        VStack(spacing: 0) {
            tab
            desk
                .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
        }
        // The desk's warm white, with the style panel's hairline and
        // shadow: the two read as one set of chrome (revision 59).
        .background(outline.fill(Ink.desk).elevation(.raised))
        .overlay(outline.stroke(Ink.hairline, lineWidth: 1).allowsHitTesting(false))
        .padding(Shell.sketchMargin)
        .tint(Accent.text)
    }

    @ViewBuilder
    private var desk: some View {
        if vault.root == nil {
            notice("Open a workspace in Alex to sketch in it.")
        } else if store.isOpen {
            CanvasView(store: store, bare: true, onIdleEscape: onClose, onStylePanel: onStylePanel)
                .environmentObject(store)
        } else {
            if let trouble = store.trouble {
                notice(trouble)
            } else {
                notice("Press", key: "⌘N", then: "for a new sketch.")
            }
        }
    }

    private func notice(_ words: String, key: String? = nil, then: String = "") -> some View {
        HStack(spacing: Space.s) {
            Text(words)
            if let key {
                KeyCaps(key)
                Text(then)
            }
        }
        .font(Typography.body)
        .foregroundStyle(Ink.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowDragArea()
    }

    // MARK: - The tab

    /// The close glyph at its leading edge, then the canvas's name, its
    /// menu.
    private var tab: some View {
        HStack(spacing: Space.xs) {
            IconButton(symbol: .x, label: "Close", shortcut: "esc", size: .small) { onClose() }
            canvasButton
        }
        .padding(.horizontal, Space.s)
        .frame(minWidth: Shell.sketchTabMin, maxWidth: Shell.sketchTabMax)
        .fixedSize()
        .frame(height: Shell.sketchTab)
        .windowDragArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tabWidth = $0; onTabWidth?($0) }
        .frame(maxWidth: .infinity)
    }

    private var canvasButton: some View {
        MenuButton(name: "sketch", placement: .below, items: menu) { open in
            HStack(spacing: Space.s) {
                if store.isOpen {
                    GlyphImage(glyph(store.canvasPath))
                        .foregroundStyle(CanvasRow.ink(store.look(for: store.canvasPath)))
                }
                Text(store.isOpen ? store.title : "Quick sketch")
                    .font(Typography.label)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                GlyphImage(.chevronDown, size: Icon.mark, weight: .medium)
                    .foregroundStyle(Ink.muted)
            }
            .padding(.horizontal, Space.s)
            .frame(height: Shell.sketchTab - Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.control)
                .fill(open ? Ink.wellHover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Canvas: \(store.isOpen ? store.title : "none")")
    }

    private func glyph(_ path: String) -> Glyph {
        store.look(for: path).icon.flatMap(Glyph.init(rawValue:)) ?? VaultEntry.Kind.canvas.symbol
    }

    /// The new one, the canvases last changed, and the way to the window.
    @MenuBuilder
    private func menu() -> [MenuItem] {
        MenuItem("New sketch", symbol: .plus, shortcut: "⌘N") { store.newSketch() }
        MenuItem.divider
        for path in store.recentlyChangedCanvases(limit: 8) {
            MenuItem(store.canvasName(path), symbol: glyph(path), checked: path == store.canvasPath) {
                store.openCanvas(at: path)
            }
        }
        if store.isOpen {
            MenuItem.divider
            MenuItem("Open in Alex", symbol: .squareArrowOutUpRight) { onOpenInWindow(store.canvasPath) }
        }
    }
}

/// The window's silhouette: the desk, its corners the panel's, and a tab
/// standing on its top edge in the middle, its top corners the card's and
/// its feet curving into the edge the same amount, as a folder's tab does.
struct SketchOutline: Shape {
    var tabWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let tab = Shell.sketchTab, corner = Radius.panel, round = Shell.sketchTabCorner
        let width = min(tabWidth, rect.width - 2 * (corner + round))
        let left = rect.midX - width / 2, right = rect.midX + width / 2
        let edge = rect.minY + tab
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: edge + corner))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: edge), tangent2End: CGPoint(x: left, y: edge), radius: corner)
        path.addArc(tangent1End: CGPoint(x: left, y: edge), tangent2End: CGPoint(x: left, y: rect.minY), radius: round)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: right, y: rect.minY), radius: round)
        path.addArc(tangent1End: CGPoint(x: right, y: rect.minY), tangent2End: CGPoint(x: right, y: edge), radius: round)
        path.addArc(tangent1End: CGPoint(x: right, y: edge), tangent2End: CGPoint(x: rect.maxX, y: edge), radius: round)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: edge), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: corner)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: corner)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: edge), radius: corner)
        path.closeSubpath()
        return path
    }
}

/// The quick sketch's style panel in its own window (revision 59): the
/// panel with room round it for its card's shadow, telling its size so
/// the window can follow it.
struct FloatingStylePanel: View {
    @ObservedObject var store: CanvasStore
    let onSize: (CGSize) -> Void

    static let margin = Shell.sketchMargin

    var body: some View {
        // No room at the trailing edge beyond the gutter it keeps from
        // the sketch, so its window never lies over the sketch's edge.
        StylePanel(store: store)
            .fixedSize()
            .padding(EdgeInsets(top: Self.margin, leading: Self.margin,
                                bottom: Self.margin, trailing: Shell.gutter))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}
