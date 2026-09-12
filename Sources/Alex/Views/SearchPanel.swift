import SwiftUI

/// ⌘K: find a file by name or title and jump to its card.
struct SearchPanel: View {
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var results: [SearchHit] {
        Array(SearchIndex.search(query, vault: vault, store: store).prefix(12))
    }

    var body: some View {
        let hits = results
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Ink.faint)
                TextField("Find a file or a note", text: $query)
                    .textFieldStyle(.plain)
                    .font(Typography.title)
                    .focused($focused)
                    .onSubmit { open(hits) }
            }
            .padding(Space.l)
            Divider()
            if hits.isEmpty {
                Text("Nothing matches.")
                    .font(Typography.meta)
                    .foregroundStyle(Ink.faint)
                    .padding(Space.l)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                        Button {
                            highlighted = i
                            open(hits)
                        } label: {
                            HStack(spacing: Space.m) {
                                Image(systemName: hit.kind.symbol)
                                    .foregroundStyle(i == highlighted ? Accent.text : Ink.muted)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.title)
                                        .font(Typography.body)
                                        .foregroundStyle(Ink.primary)
                                        .lineLimit(1)
                                    Text(hit.path)
                                        .font(Typography.meta)
                                        .foregroundStyle(Ink.faint)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: Radius.control)
                                .fill(i == highlighted ? Ink.wellHover : .clear))
                            .contentShape(RoundedRectangle(cornerRadius: Radius.control))
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlighted = i } }
                    }
                }
                .padding(Space.s)
            }
        }
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.lifted)
        .onAppear {
            query = ""
            highlighted = 0
            focused = true
        }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(hits.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onExitCommand { store.showSearch = false }
    }

    private func open(_ hits: [SearchHit]) {
        guard hits.indices.contains(highlighted) else { return }
        store.showSearch = false
        store.reveal(hits[highlighted].path)
    }
}
