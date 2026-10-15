import SwiftUI

/// The style panel (PLAN.md, revision 39): Excalidraw's properties panel,
/// a card floating at the desk's left while something is selected and at
/// rest. Every way a node can be styled is here and nowhere else — the
/// shape style bar of revision 32 and the node menu's style submenus went
/// into it — so a selection is styled from one place. Each group shows
/// when every selected node takes it (`StyleScope`): colour for anything;
/// outline or filled and solid or dashed for a shape; arrowheads for a
/// line; the face for words on the desk and a note's card; the size for
/// words on the desk and where they sit (revision 47); a picture's corners; the order for anything but a section; and the
/// verbs, duplicate, fold and remove. A cell wears the grey square while
/// the whole selection wears it, and none does where the selection
/// differs. It stands under the sidebar's head row, clear of its card.
struct StylePanel: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        let nodes = store.selection.compactMap { store.document.node($0) }
        let scope = StyleScope(nodes)
        let ids = store.selection
        VStack(alignment: .leading, spacing: Space.m) {
            group("Colour") {
                ForEach(NodeMenu.colours, id: \.0) { name, code in
                    Swatch(name: name, code: code, active: scope.colourShared && scope.colour == code) {
                        store.setColor(ids, code)
                    }
                }
            }
            if scope.fill {
                group("Fill") {
                    cell(.square, "Outline", active: scope.filled == false) { store.setFilled(ids, false) }
                    cell(.paintBucket, "Filled", active: scope.filled == true) { store.setFilled(ids, true) }
                }
            }
            if scope.stroke {
                group("Stroke") {
                    cell(.minus, "Solid", active: scope.dashed == false) { store.setDashed(ids, false) }
                    cell(.squareDashed, "Dashed", active: scope.dashed == true) { store.setDashed(ids, true) }
                }
            }
            if scope.arrowheads {
                group("Arrowheads") {
                    cell(.moveLeft, "Arrowhead at the start", active: scope.fromArrow == true) {
                        store.setLineEnds(ids, from: scope.fromArrow != true)
                    }
                    cell(.moveRight, "Arrowhead at the end", active: scope.toArrow == true) {
                        store.setLineEnds(ids, to: scope.toArrow != true)
                    }
                }
            }
            if scope.font {
                group("Font") {
                    ForEach(FontFamily.allCases, id: \.self) { family in
                        cell(family.glyph, family.title, active: scope.family == family) {
                            store.setFontFamily(ids, family)
                        }
                    }
                }
            }
            if scope.size {
                group("Size") {
                    ForEach(TextSize.allCases, id: \.self) { size in
                        TextCell(text: size.short, label: size.title, active: scope.textSize == size) {
                            store.setFontSize(ids, size)
                        }
                    }
                }
            }
            if scope.align {
                group("Align") {
                    ForEach(TextAlign.allCases, id: \.self) { align in
                        cell(align.glyph, align.title, active: scope.textAlign == align) {
                            store.setTextAlign(ids, align)
                        }
                    }
                }
            }
            if scope.corners {
                group("Corners") {
                    ForEach(CornerSize.allCases, id: \.self) { size in
                        TextCell(text: size.short, label: size.title, active: scope.corner == size) {
                            store.setCorners(ids, size)
                        }
                    }
                }
            }
            if scope.order {
                group("Order") {
                    cell(.sendToBack, "Send to back") { store.sendToBack(ids) }
                    cell(.bringToFront, "Bring to front") { store.bringToFront(ids) }
                }
            }
            group("Actions") {
                if scope.duplicable {
                    cell(.copy, "Duplicate") { store.duplicate(ids) }
                }
                if scope.foldable, !nodes.contains(where: store.isDirectoryNode) {
                    cell(scope.folded == true ? .chevronsUpDown : .chevronsDownUp,
                         scope.folded == true ? "Unfold" : "Fold", shortcut: "⌘⌥↩") { store.toggleFold(ids) }
                }
                cell(.trash, "Remove from canvas", shortcut: "⌘⌫") { store.remove(ids) }
            }
        }
        .padding(Space.m)
        .fixedSize()
        .floatingCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Style")
    }

    /// A group: its name in the supporting ink, then its cells in a row.
    private func group<Cells: View>(_ title: String, @ViewBuilder cells: () -> Cells) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(Typography.label)
                .foregroundStyle(Ink.muted)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Space.xs) { cells() }
        }
    }

    private func cell(_ symbol: Glyph, _ label: String, shortcut: String? = nil, active: Bool = false,
                      action: @escaping () -> Void) -> some View {
        IconButton(symbol: symbol, label: label, shortcut: shortcut, active: active, action: action)
    }
}

/// One of the node colours as a round swatch in a cell: the preset's
/// label hue, or an empty ring for none.
struct Swatch: View {
    let name: String
    let code: String?
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(code == nil ? Color.clear : Hepta.label(code))
                .overlay {
                    if code == nil { Circle().strokeBorder(Ink.faint, lineWidth: 1) }
                }
                .frame(width: Icon.control, height: Icon.control)
                .frame(width: IconButton.Size.regular.side.width, height: IconButton.Size.regular.side.height)
        }
        .buttonStyle(IconButtonStyle(active: active ? .well : nil, radius: Radius.control))
        .tooltip(name, name: name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

/// A cell that says its value in letters rather than a glyph: the sizes
/// and a picture's corners.
private struct TextCell: View {
    let text: String
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Typography.control)
                .foregroundStyle(active ? Ink.primary : Ink.icon)
                .frame(width: IconButton.Size.regular.side.width, height: IconButton.Size.regular.side.height)
        }
        .buttonStyle(IconButtonStyle(active: active ? .well : nil, radius: Radius.control))
        .tooltip(label, name: label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}
