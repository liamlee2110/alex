import SwiftUI

/// The style panel (PLAN.md, revision 39): Excalidraw's properties panel,
/// a card floating at the desk's left while something is selected and at
/// rest. Every way a node can be styled is here and nowhere else — the
/// shape style bar of revision 32 and the node menu's style submenus went
/// into it — so a selection is styled from one place. Each group shows
/// when every selected node takes it (`StyleScope`): colour for anything,
/// none and four (revision 55); outline or filled for a shape; the
/// stroke's width and pattern for any shape (revision 55); arrowheads for
/// a line; the face for words on the desk and a note's card; the size for
/// words on the desk and where they sit (revision 47); the corners of a
/// picture and a rectangle; the order, a step or all the way, for
/// anything but a section; and the verbs, duplicate, fold and remove. A cell wears the grey square while
/// the whole selection wears it, and none does where the selection
/// differs. It stands under the sidebar's head row, clear of its card.
/// Picked edges have a set of their own (revision 62).
struct StylePanel: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if store.edgeSelection.isEmpty { nodeGroups } else { edgeGroups }
        }
        .padding(Space.m)
        .fixedSize()
        .floatingCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Style")
    }

    /// Picked edges (revision 62), Excalidraw's arrow properties: the
    /// colour, the stroke's width and pattern, the route and the heads.
    @ViewBuilder private var edgeGroups: some View {
        let ids = store.edgeSelection
        let scope = EdgeScope(store.document.edges.filter { ids.contains($0.id) })
        group("Colour") {
            ForEach(NodeMenu.colours, id: \.0) { name, code in
                Swatch(name: name, code: code, active: scope.colourShared && scope.colour == code) {
                    store.setEdgeColor(ids, code)
                }
            }
        }
        group("Stroke width") {
            ForEach(StrokeWidth.allCases, id: \.self) { width in
                StrokeCell(width: CGFloat(width.rawValue), pattern: .solid, label: width.title,
                           active: scope.width == width) {
                    store.setEdgeStrokeWidth(ids, width)
                }
            }
        }
        group("Stroke style") {
            ForEach(StrokePattern.allCases, id: \.self) { pattern in
                StrokeCell(width: Stroke.shape, pattern: pattern, label: pattern.title,
                           active: scope.pattern == pattern) {
                    store.setEdgeStrokePattern(ids, pattern)
                }
            }
        }
        group("Line") {
            ForEach(EdgeRoute.allCases, id: \.self) { route in
                cell(route.glyph, route.title, active: scope.route == route) { store.setEdgeRoute(ids, route) }
            }
        }
        group("Arrowheads") {
            cell(.moveLeft, "Arrowhead at the start", active: scope.fromArrow == true) {
                store.setEdgeEnds(ids, from: scope.fromArrow != true)
            }
            cell(.moveRight, "Arrowhead at the end", active: scope.toArrow == true) {
                store.setEdgeEnds(ids, to: scope.toArrow != true)
            }
        }
        group("Actions") {
            cell(.trash, "Remove", shortcut: "⌘⌫") { store.removeEdges(ids) }
        }
    }

    @ViewBuilder private var nodeGroups: some View {
        let nodes = store.selection.compactMap { store.document.node($0) }
        let scope = StyleScope(nodes)
        let ids = store.selection
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
            group("Stroke width") {
                ForEach(StrokeWidth.allCases, id: \.self) { width in
                    StrokeCell(width: CGFloat(width.rawValue), pattern: .solid, label: width.title,
                               active: scope.width == width) {
                        store.setStrokeWidth(ids, width)
                    }
                }
            }
            group("Stroke style") {
                ForEach(StrokePattern.allCases, id: \.self) { pattern in
                    StrokeCell(width: Stroke.shape, pattern: pattern, label: pattern.title,
                               active: scope.pattern == pattern) {
                        store.setStrokePattern(ids, pattern)
                    }
                }
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
                cell(.arrowDownToLine, "Send to back", shortcut: "⌘⌥[") { store.sendToBack(ids) }
                cell(.arrowDown, "Send backward", shortcut: "⌘[") { store.sendBackward(ids) }
                cell(.arrowUp, "Bring forward", shortcut: "⌘]") { store.bringForward(ids) }
                cell(.arrowUpToLine, "Bring to front", shortcut: "⌘⌥]") { store.bringToFront(ids) }
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

/// A stroke's width or pattern as a short line drawn at it (revision 55),
/// as Excalidraw's cells show theirs: a sample, like a colour's swatch,
/// rather than an icon.
private struct StrokeCell: View {
    let width: CGFloat
    let pattern: StrokePattern
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Canvas { context, size in
                var line = Path()
                line.move(to: CGPoint(x: (size.width - Stroke.sample) / 2, y: size.height / 2))
                line.addLine(to: CGPoint(x: (size.width + Stroke.sample) / 2, y: size.height / 2))
                let dash: [CGFloat] = pattern == .dashed ? Stroke.sampleDash : Stroke.pattern(pattern, width: width)
                context.stroke(line, with: .color(active ? Ink.primary : Ink.icon),
                               style: StrokeStyle(lineWidth: width, lineCap: pattern == .dashed ? .butt : .round,
                                                  dash: dash))
            }
            .frame(width: IconButton.Size.regular.side.width, height: IconButton.Size.regular.side.height)
        }
        .buttonStyle(IconButtonStyle(active: active ? .well : nil, radius: Radius.control))
        .tooltip(label, name: label)
        .accessibilityLabel(label)
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

extension EdgeRoute {
    var glyph: Glyph {
        switch self {
        case .curved: return .spline
        case .straight: return .slash
        case .elbow: return .cornerDownRight
        }
    }
}
