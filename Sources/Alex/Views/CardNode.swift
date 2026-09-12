import SwiftUI
import AppKit

/// A file on the canvas: paper for a note, a photo for an image, a page for
/// a PDF, mono lines for code.
struct CardNodeView: View {
    let node: CanvasNode
    let path: String
    let kind: VaultEntry.Kind
    let preview: CardPreview
    let url: URL?
    let missing: Bool
    let selected: Bool
    /// From the vault's views: the key that colours this card, its value,
    /// and the JSON Canvas colour it maps to.
    var tint: (key: String, value: String, color: String)? = nil

    @ObservedObject private var thumbnails = Thumbnails.shared
    @State private var hovering = false

    private var tintHue: Double? { tint.flatMap { Stock.hue(forCanvasColor: $0.color) } }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tintHue.map { OKLCH.color(l: 0.975, c: 0.02, h: $0) } ?? Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(selected ? Accent.text : Ink.hairline, lineWidth: selected ? 2 : 1))
            .elevation(hovering ? .lifted : .card)
            .opacity(missing ? 0.55 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.18), value: hovering)
    }

    private var stem: String { (VaultPath.name(of: path) as NSString).deletingPathExtension }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .image, .pdf, .html:
            ZStack(alignment: .bottomLeading) {
                if let url, let image = thumbnails.image(for: url, size: CGSize(width: node.width, height: node.height)) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: node.width, height: node.height)
                        .clipped()
                } else {
                    Image(systemName: kind.symbol)
                        .font(Typography.display)
                        .foregroundStyle(Ink.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(VaultPath.name(of: path))
                    .font(Typography.label)
                    .foregroundStyle(Ink.muted)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                    .background(Capsule().fill(Ink.card))
                    .padding(Space.m)
            }
        case .canvas:
            VStack(spacing: Space.s) {
                Image(systemName: kind.symbol)
                    .font(Typography.display)
                    .foregroundStyle(Ink.faint)
                Text(stem)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Ink.primary)
                Text("Canvas")
                    .font(Typography.label)
                    .foregroundStyle(Ink.faint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .code, .text:
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    Image(systemName: kind.symbol)
                    Text(VaultPath.name(of: path))
                }
                .font(Typography.label)
                .foregroundStyle(Ink.muted)
                Text(preview.lines.joined(separator: "\n"))
                    .font(Typography.monoSmall)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(9)
                    .fixedSize(horizontal: false, vertical: true)
                missingLine
            }
            .padding(Space.l)
        default:
            VStack(alignment: .leading, spacing: Space.s) {
                if !preview.chips.isEmpty { chips }
                Text(preview.title)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !preview.lines.isEmpty {
                    Text(preview.lines.joined(separator: "\n"))
                        .font(Typography.prose)
                        .foregroundStyle(Ink.muted)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                missingLine
            }
            .padding(Space.l)
        }
    }

    @ViewBuilder
    private var missingLine: some View {
        if missing {
            Text("Missing file")
                .font(Typography.label)
                .foregroundStyle(Ink.faint)
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(preview.chips, id: \.self) { chip in
                let coloured = tint?.key == chip.key ? tintHue : nil
                Text(chip.value)
                    .font(Typography.micro)
                    .foregroundStyle(coloured.map { OKLCH.color(l: 0.35, c: 0.09, h: $0) } ?? Ink.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(coloured.map { OKLCH.color(l: 0.88, c: 0.09, h: $0) } ?? Ink.well))
                    .help(chip.key)
            }
        }
    }
}

/// A `text` node: a sticky note cut from the stock its colour names. Double-
/// click and it edits in place; the text is saved a moment after typing
/// stops and when editing ends.
struct StickyNodeView: View {
    let node: CanvasNode
    let selected: Bool
    var editing = false
    var onChange: (String) -> Void = { _ in }

    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var hue: Double { node.hue ?? Stock.hue(forCanvasColor: node.color) ?? 95 }
    private var ink: Color { OKLCH.color(l: 0.25, c: 0.03, h: hue) }

    var body: some View {
        Group {
            if editing {
                TextEditor(text: $text)
                    .font(Typography.body)
                    .foregroundStyle(ink)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .focused($focused)
                    .padding(Space.m)
                    .onAppear {
                        text = node.text ?? ""
                        focused = true
                    }
                    .onChange(of: text) { _, new in
                        saveTask?.cancel()
                        saveTask = Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            onChange(new)
                        }
                    }
                    .onDisappear {
                        saveTask?.cancel()
                        onChange(text)
                    }
            } else {
                Text(node.text?.isEmpty == false ? node.text! : "Double-click to write")
                    .font(Typography.body)
                    .foregroundStyle(node.text?.isEmpty == false ? ink : OKLCH.color(l: 0.55, c: 0.03, h: hue))
                    .padding(Space.l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OKLCH.color(l: 0.93, c: 0.07, h: hue))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Radius.control)
            .strokeBorder(selected ? Accent.text : OKLCH.color(l: 0.8, c: 0.06, h: hue), lineWidth: selected ? 2 : 1))
        .elevation(.card)
    }
}

struct LinkNodeView: View {
    let node: CanvasNode
    let selected: Bool

    private var host: String {
        node.url.flatMap(URL.init(string:))?.host ?? node.url ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "globe")
                .font(Typography.title)
                .foregroundStyle(Ink.faint)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(host)
                    .font(Typography.title)
                    .foregroundStyle(Ink.primary)
                Text(node.url ?? "")
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(3)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .strokeBorder(selected ? Accent.text : Ink.hairline, lineWidth: selected ? 2 : 1))
        .elevation(.card)
    }
}

struct UnknownNodeView: View {
    let node: CanvasNode
    let selected: Bool

    var body: some View {
        Text("A \(node.kind.typeName) node from another app. Kept as is.")
            .font(Typography.meta)
            .foregroundStyle(Ink.faint)
            .padding(Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Ink.well)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(selected ? Accent.text : Ink.hairline, lineWidth: 1))
    }
}

/// A labelled region behind other nodes.
struct GroupNodeView: View {
    let node: CanvasNode
    let selected: Bool

    private var hue: Double? { node.hue ?? Stock.hue(forCanvasColor: node.color) }

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card)
            .fill(hue.map { OKLCH.color(l: 0.9, c: 0.05, h: $0, alpha: 0.28) } ?? Ink.well)
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(selected ? Accent.text
                              : (hue.map { OKLCH.color(l: 0.75, c: 0.06, h: $0, alpha: 0.5) } ?? Ink.hairline),
                              lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topLeading) {
                if let label = node.label, !label.isEmpty {
                    Text(label)
                        .font(Typography.label)
                        .foregroundStyle(hue.map { OKLCH.color(l: 0.35, c: 0.08, h: $0) } ?? Ink.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(hue.map { OKLCH.color(l: 0.86, c: 0.08, h: $0) } ?? Ink.card))
                        .padding(10)
                }
            }
    }
}
