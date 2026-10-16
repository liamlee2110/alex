import SwiftUI

/// ⌘F, find on canvas (revision 27), in the live panel the way
/// Excalidraw's canvas search sits in its sidebar: a field, the count
/// with the hit you are on and the chevrons that step, then every hit,
/// under the node it is on, its words in the identifying weight. Enter
/// steps on, ⇧Enter back, Escape closes. The desk rings every node that
/// holds a hit and looks at the one stepped to, without selecting it.
struct FindPanel: View {
    @ObservedObject var store: CanvasStore
    @ObservedObject private var previews = LinkPreviews.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
                .padding(.horizontal, Shell.panelInset - Space.s)
            count
                .padding(.leading, Shell.panelInset)
                .padding(.trailing, Space.m)
            results
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
        .onChange(of: store.findFocusTick) { _, _ in focused = true }
        .onExitCommand { store.closeFind() }
    }

    private var field: some View {
        HStack(spacing: Space.s) {
            GlyphImage(.search)
                .foregroundStyle(Ink.faint)
            TextField("Find text on canvas", text: $store.findQuery)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .focused($focused)
                .onSubmit { store.stepFind(NSEvent.modifierFlags.contains(.shift) ? -1 : 1) }
                .onKeyPress(.downArrow) { store.stepFind(1); return .handled }
                .onKeyPress(.upArrow) { store.stepFind(-1); return .handled }
            if !store.findQuery.isEmpty {
                IconButton(symbol: .x, label: "Clear", size: .small) {
                    store.findQuery = ""
                    focused = true
                }
            }
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.well))
    }

    @ViewBuilder private var count: some View {
        if !store.findQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: Space.xs) {
                Text(countText)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .monospacedDigit()
                Spacer(minLength: Space.s)
                IconButton(symbol: .chevronUp, label: "Previous result", shortcut: "⇧↩") { store.stepFind(-1) }
                IconButton(symbol: .chevronDown, label: "Next result", shortcut: "↩") { store.stepFind(1) }
            }
            .disabled(store.findHits.isEmpty)
            .frame(height: Shell.row + Space.s)
            .padding(.top, Space.s)
        }
    }

    private var countText: String {
        let total = store.findTotal
        if total == 0 { return "No results" }
        let noun = total == 1 ? "result" : "results"
        let shown = total > store.findHits.count ? " (first \(store.findHits.count) listed)" : ""
        return "\(store.findIndex + 1) / \(total) \(noun)\(shown)"
    }

    private var results: some View {
        let hits = store.findHits
        let groups = grouped(hits)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.node) { group in
                        if let node = store.document.node(group.node) {
                            nodeRow(node)
                        }
                        ForEach(group.hits, id: \.offset) { index, hit in
                            hitRow(hit, index: index)
                                .id(hit.id)
                        }
                    }
                }
                .padding(.horizontal, Shell.panelInset - Space.s)
                .padding(.bottom, Space.xl)
            }
            .onChange(of: store.findIndex) { _, index in
                guard hits.indices.contains(index) else { return }
                withAnimation(Motion.quick) { proxy.scrollTo(hits[index].id, anchor: .center) }
            }
        }
    }

    /// Hits under the node they are on, the nodes in reading order.
    private func grouped(_ hits: [FindHit]) -> [(node: String, hits: [(offset: Int, element: FindHit)])] {
        var out: [(node: String, hits: [(offset: Int, element: FindHit)])] = []
        for (i, hit) in hits.enumerated() {
            if out.last?.node == hit.node {
                out[out.count - 1].hits.append((i, hit))
            } else {
                out.append((hit.node, [(i, hit)]))
            }
        }
        return out
    }

    /// The node a run of hits is on: its glyph and what it is called.
    private func nodeRow(_ node: CanvasNode) -> some View {
        HStack(spacing: Space.s) {
            GlyphImage(symbol(of: node))
                .foregroundStyle(Ink.faint)
                .frame(width: 16)
            Text(name(of: node))
                .font(Typography.label)
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.m)
        .padding(.bottom, Space.xs)
    }

    private func hitRow(_ hit: FindHit, index: Int) -> some View {
        let current = index == store.findIndex
        return Button {
            store.goToFindHit(index)
        } label: {
            snippet(hit)
                .font(Typography.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s)
                .padding(.vertical, 6)
                // Where you are is a grey square (revision 18).
                .background(RoundedRectangle(cornerRadius: Radius.control)
                    .fill(current ? Ink.well : .clear))
                .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
    }

    /// The line round the match, the match itself in the identifying
    /// weight and ink.
    private func snippet(_ hit: FindHit) -> Text {
        let before = String(hit.snippet[..<hit.match.lowerBound])
        let match = String(hit.snippet[hit.match])
        let after = String(hit.snippet[hit.match.upperBound...])
        return Text(before).foregroundColor(Ink.muted)
            + Text(match).fontWeight(.medium).foregroundColor(Ink.primary)
            + Text(after).foregroundColor(Ink.muted)
    }

    private func symbol(of node: CanvasNode) -> Glyph {
        switch node.kind {
        case .file:
            return VaultEntry(path: node.file ?? "", isDirectory: false).symbol
        case .text:
            return node.shape != nil ? ShapeLabel.symbol(of: node) : .stickyNote
        case .group:
            return .squareDashed
        case .link:
            return LinkKind.classify(node.url ?? "").symbol
        case .other:
            return .fileQuestion
        }
    }

    private func name(of node: CanvasNode) -> String {
        switch node.kind {
        case .file:
            return node.file.map(store.displayTitle(for:)) ?? "A file"
        case .text:
            let first = (node.text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let plain = first.trimmingCharacters(in: CharacterSet(charactersIn: "#-*> \t"))
            if !plain.isEmpty { return plain }
            return node.shape != nil ? ShapeLabel.name(of: node) : "Sticky note"
        case .group:
            return node.label?.isEmpty == false ? node.label! : "Section"
        case .link:
            let address = node.url ?? ""
            return previews.meta(for: address)?.title ?? LinkKind.webURL(address)?.host ?? address
        case .other:
            return "A \(node.kind.typeName) node"
        }
    }
}
