import SwiftUI
import AppKit

/// A file on the canvas: paper for a note, a photo for an image, a page for
/// a PDF, mono lines for code. The pointer brings up Heptabase's card
/// chrome, and the chevron in it folds the card down to its title row.
struct CardNodeView: View {
    let node: CanvasNode
    let path: String
    let kind: VaultEntry.Kind
    let preview: CardPreview
    let url: URL?
    let missing: Bool
    let selected: Bool
    /// The desk's zoom in steps of √2 (`Camera.detail`), what a page is
    /// drawn at. The chrome, which counter-scales to stay the size of a
    /// button on screen, reads the camera itself while it shows.
    var zoom: CGFloat = 1
    /// From the vault's views: the key that colours this card, its value,
    /// and the JSON Canvas colour it maps to.
    var tint: (key: String, value: String, color: String)? = nil
    /// Double-clicked: the card is being written on rather than read.
    var editing = false
    @ObservedObject var store: CanvasStore
    /// Esc or ⌘↩ in its editor (revision 50).
    var onDone: () -> Void = {}

    @ObservedObject private var thumbnails = Thumbnails.shared
    @State private var hovering = false
    /// The pointer is on the toolbar pill, which stands mostly outside
    /// the card: the pill keeps itself up once the pointer has left the
    /// card for it.
    @State private var hoveringPill = false

    /// `--hover <vault path>` holds one card's chrome open: a snapshot has
    /// no pointer to hover with.
    private static let forcedHover = Launch.value(after: "--hover")

    private var tintHue: Double? { tint.flatMap { Stock.hue(forCanvasColor: $0.color) } }

    var body: some View {
        Group {
            if editing {
                VStack(alignment: .leading, spacing: Space.s) {
                    CardEditorBody(path: path, store: store, nodeID: node.id, family: node.fontFamily, onDone: onDone)
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)
                .padding(.bottom, Space.s)
            } else if node.folded {
                if wantsChrome {
                    CameraReader(camera: store.camera) { vp in
                        foldedRow(chrome: Self.chromeFits(vp.scale) ? vp.scale : nil)
                    }
                } else {
                    foldedRow(chrome: nil)
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.map { Hepta.fill($0.color) } ?? Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: kind == .image ? node.cornerRadius.map { CGFloat($0) } ?? Radius.card : Radius.card))
        .overlay(alignment: node.folded ? .leading : .topLeading) {
            if wantsChrome {
                CameraReader(camera: store.camera) { vp in
                    if Self.chromeFits(vp.scale) {
                        if node.folded { leadingChrome(vp.scale) } else { chromePill(vp.scale) }
                    }
                }
            }
        }
        .elevation(hovering ? .lifted : .card)
        .opacity(missing ? 0.55 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }

    private var stem: String { (VaultPath.name(of: path) as NSString).deletingPathExtension }

    /// What the card is called when it has to say so in one line: a note's
    /// heading, a document's file name.
    private var title: String {
        kind.isTextual && !preview.title.isEmpty ? preview.title : VaultPath.name(of: path)
    }

    // MARK: - Folded

    /// What Heptabase leaves when a card folds: the title alone, which steps
    /// aside for the chrome when the pointer arrives. The room it gives is
    /// measured in screen points, because the chrome is.
    private func foldedRow(chrome zoom: CGFloat?) -> some View {
        Text(title)
            .font(Typography.cardTitle(node.fontFamily))
            .foregroundStyle(Ink.primary)
            .lineLimit(1)
            .padding(.leading, zoom.map { 66 / $0 } ?? 14)
            .padding(.trailing, zoom.map { 40 / $0 } ?? 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - The chrome under the pointer

    /// Not when the desk is zoomed so far out that the buttons would cover
    /// the card they belong to.
    private static func chromeFits(_ zoom: CGFloat) -> Bool { zoom >= 0.45 }

    /// The pointer is on the card or its pill; whether the chrome fits at
    /// this zoom is the camera's to say (`chromeFits`).
    /// A picture has none (revision 45): it neither folds nor opens in the
    /// sheet, so a pill would hold nothing. One folded before then keeps
    /// its row's unfold.
    private var wantsChrome: Bool {
        !editing && (kind != .image || node.folded) && (hovering || hoveringPill || Self.forcedHover == path)
    }

    /// Heptabase's card toolbar (revision 18): one pill standing on the
    /// card's top edge while the pointer is on the card — fold, the side
    /// panel, a connection. It stands above the card with a sliver inside
    /// it: the sliver is what the pointer enters before it leaves the card,
    /// and the pill's own hover keeps it up from there, so nothing inside
    /// the card is kept clear for it and the words start at the card's own
    /// padding at any zoom the pill shows at. Revision 10 held a 40pt band
    /// open inside the card instead, which grew with the zoom and read as
    /// a hole at the top of every card; Heptabase's toolbar is outside the
    /// card, and that is why its words never move.
    private func chromePill(_ zoom: CGFloat) -> some View {
        let side = IconButton.Size.small.side.height + 2 * Space.xs
        // Inside the card on screen: under the 14pt padding even at the
        // smallest zoom the pill shows at (6 / 0.45 < 14).
        let sliver: CGFloat = 6
        return HStack(spacing: 2) {
            IconButton(symbol: node.folded ? .chevronRight : .chevronDown,
                       label: node.folded ? "Unfold" : "Fold",
                       hint: node.folded ? "Unfold (⌘⌥↩)" : "Fold (⌘⌥↩)", size: .small) {
                store.toggleFold([node.id])
            }
            IconButton(symbol: .panelRight, label: "Add to the side panel",
                       hint: "Add to the side panel (⌥↩)", size: .small) {
                store.pin(.file(path))
            }
        }
        .padding(Space.xs)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
        .elevation(.raised)
        .onHover { hoveringPill = $0 }
        .scaleEffect(1 / zoom, anchor: .topLeading)
        .offset(x: Space.m / zoom, y: -(side - sliver) / zoom)
    }

    /// The folded row's cluster at its left: fold, and the side panel.
    /// Heptabase's third button there opens the card in a new tab, which
    /// Alex has nowhere to put — one window, one desk — and the two on the
    /// far side of its toolbar are AI, the part Alex leaves to Claude
    /// (PLAN.md §0).
    private func leadingChrome(_ zoom: CGFloat) -> some View {
        HStack(spacing: 2) {
            IconButton(symbol: node.folded ? .chevronRight : .chevronDown,
                       label: node.folded ? "Unfold" : "Fold",
                       hint: node.folded ? "Unfold (⌘⌥↩)" : "Fold (⌘⌥↩)", size: .small) {
                store.toggleFold([node.id])
            }
            if kind != .image {
                IconButton(symbol: .panelRight, label: "Add to the side panel",
                           hint: "Add to the side panel (⌥↩)", size: .small) {
                    store.pin(.file(path))
                }
            }
        }
        .scaleEffect(1 / zoom, anchor: node.folded ? .leading : .topLeading)
        .padding(8 / zoom)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .pdf:
            DocumentBody(url: url, name: VaultPath.name(of: path),
                         screenWidth: node.width * zoom, missing: missing)
        case .image, .html:
            ZStack(alignment: .bottomLeading) {
                if let url, let image = thumbnails.image(for: url, size: CGSize(width: node.width, height: node.height)) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: node.width, height: node.height)
                        .clipped()
                } else {
                    GlyphImage(kind.symbol, size: Icon.hero)
                        .foregroundStyle(Ink.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // A picture is a picture (revision 44): no name over it, as
                // Heptabase draws none. A page rendered from `.html` keeps
                // its name, being otherwise a picture of a page.
                if kind == .html {
                    Text(VaultPath.name(of: path))
                        .font(Typography.label)
                        .foregroundStyle(Ink.muted)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs)
                        .background(Capsule().fill(Ink.card))
                        .padding(Space.m)
                }
            }
        case .canvas:
            VStack(spacing: Space.s) {
                GlyphImage(kind.symbol, size: Icon.hero)
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
                    GlyphImage(kind.symbol)
                    Text(VaultPath.name(of: path))
                }
                .font(Typography.label)
                .foregroundStyle(Ink.muted)
                CardBody(text: preview.lines.joined(separator: "\n"),
                         font: Typography.monoSmall,
                         lineHeight: Typography.lineHeight(ofSize: Typography.monoSmallSize,
                                                           monospaced: true))
                missingLine
            }
            .padding(Space.l)
        default:
            VStack(alignment: .leading, spacing: Space.s) {
                if !preview.hasHeading {
                    Text(preview.title)
                        .font(Typography.cardTitle(node.fontFamily))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !preview.body.isEmpty {
                    // The panel's renderer at the card's sizes, reading
                    // only (revision 18): headings, lists, quotes, rules,
                    // code, marks and links drawn as the panel draws them.
                    // Where the card ends, the words fade into the paper
                    // rather than stop mid-line; over empty paper the fade
                    // is invisible, so it needs no measuring. Drawn once
                    // into a picture the desk scales (revision 25).
                    let paper = tint.map { Hepta.fill($0.color) } ?? Ink.card
                    NoteRaster(markdown: preview.body, imageBase: url?.deletingLastPathComponent(),
                               imageStem: stem, detail: zoom, family: node.fontFamily)
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [paper.opacity(0), paper],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: Space.l)
                                .allowsHitTesting(false)
                        }
                }
                missingLine
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var missingLine: some View {
        if missing {
            Text("Missing file")
                .font(Typography.label)
                .foregroundStyle(Ink.muted)
        }
    }

}

/// A note being written on its own card, in the panel's editor at the
/// card's size: the same rendered Markdown, the frontmatter kept under it
/// untouched, headings at the card's title size so the words stay near
/// where the preview had them (decided with Liam, 2026-09-14). It saves
/// through the same `Vault.write` the panel uses, so a note open on the
/// desk and in the panel at once settles the way it would if someone else
/// had written it.
struct CardEditorBody: View {
    let path: String
    @ObservedObject var store: CanvasStore
    /// The card being written on, and its face (revision 36), so the words
    /// do not change face when the card is opened.
    var nodeID: String? = nil
    var family: FontFamily = .normal
    var onDone: (() -> Void)? = nil

    @State private var text = ""
    @State private var diskText = ""
    @State private var saveTask: Task<Void, Never>?

    private var stem: String { (VaultPath.name(of: path) as NSString).deletingPathExtension }

    /// The body alone; an edit goes back under the block untouched.
    private var bodyBinding: Binding<String> {
        Binding(get: { Frontmatter.split(text).body },
                set: { text = Frontmatter.split(text).replacingBody(with: $0) })
    }

    var body: some View {
        MarkdownEditor(text: bodyBinding, scrollable: true,
                       imageBase: store.vault.url(for: path)?.deletingLastPathComponent(), imageStem: stem,
                       baseSize: Typography.cardEditorSize, headingSizes: Typography.cardEditorHeadings,
                       takesFocus: true,
                       family: family,
                       onFamily: nodeID.map { id in { store.setFontFamily([id], $0) } },
                       onOpenLink: { name in store.openNote(named: name, from: path) },
                       onDone: onDone)
            .onAppear {
                text = (try? store.vault.readText(path)) ?? ""
                diskText = text
            }
            .onChange(of: text) { _, _ in
                // The panel's pause, so the two surfaces write alike.
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    write()
                }
            }
            .onDisappear {
                saveTask?.cancel()
                write()
            }
    }

    private func write() {
        guard text != diskText else { return }
        do {
            try store.vault.write(text, to: path)
            diskText = text
            store.refreshPreview(for: path)
        } catch {
            NSLog("Alex: could not save \(path): \(error)")
        }
    }
}

/// A card's body text: as many lines as the room under the title allows,
/// with an ellipsis where the card ends. A fixed line count left a card that
/// had just been dragged bigger showing exactly what it showed before, which
/// is the one thing the drag was for.
struct CardBody: View {
    let text: String
    let font: Font
    /// One line's height in the body's font, so the budget is a measurement
    /// and not a guess at how tall the font draws.
    let lineHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .foregroundStyle(Ink.primary)
                .lineLimit(max(1, Int(geo.size.height / lineHeight)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A document card: the first page, drawn at the card's width on the grey
/// the desk is made of, cut off where the card ends, with the file's name
/// and its length under it. Fitting a page into a landscape card, which is
/// what a thumbnail does, makes a paper nobody can read.
struct DocumentBody: View {
    let url: URL?
    let name: String
    /// How wide the card is on screen, zoom included, so the page is drawn
    /// at the resolution it is shown at.
    let screenWidth: Double
    /// The paper's margin above the page: the same as at its sides.
    var band: CGFloat = 10
    let missing: Bool

    @ObservedObject private var thumbnails = Thumbnails.shared

    var body: some View {
        let preview = url.flatMap { thumbnails.page(for: $0, width: screenWidth) }
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Ink.ground
                if let preview {
                    page(preview.image)
                } else {
                    GlyphImage(VaultEntry.Kind.pdf.symbol, size: Icon.hero)
                        .foregroundStyle(Ink.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            HStack(spacing: Space.s) {
                Text(name)
                    .font(Typography.label)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Space.s)
                Text(caption(preview))
                    .font(Typography.micro)
                    .foregroundStyle(Ink.muted)
            }
            .padding(.horizontal, Space.m)
            .frame(height: 30)
        }
    }

    /// The page fills the card's width and runs off its bottom edge, so a
    /// card any shape shows the head of the document.
    private func page(_ image: NSImage) -> some View {
        GeometryReader { geo in
            let across = max(geo.size.width, 1)
            let down = across * image.size.height / max(image.size.width, 1)
            Image(nsImage: image)
                .resizable()
                .frame(width: across, height: down)
                .background(Ink.card)
                .overlay(Rectangle().strokeBorder(Ink.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 10)
        .padding(.top, band)
    }

    private func caption(_ preview: Thumbnails.PagePreview?) -> String {
        if missing { return "Missing file" }
        guard let preview else { return "" }
        return preview.pages == 1 ? "1 page" : "\(preview.pages) pages"
    }
}

/// A `text` node: a sticky note cut from the stock its colour names. Double-
/// click and it edits in place; the text is saved a moment after typing
/// stops and when editing ends.
struct StickyNodeView: View {
    let node: CanvasNode
    let selected: Bool
    var editing = false
    /// `Camera.detail`, for the picture its words are drawn into.
    var zoom: CGFloat = 1
    var onChange: (String) -> Void = { _ in }
    /// The format bar's size menu (revision 33) and its faces (revision 36).
    var onTextSize: (TextSize) -> Void = { _ in }
    var onFamily: (FontFamily) -> Void = { _ in }
    /// Esc or ⌘↩ in its editor (revision 50).
    var onDone: () -> Void = {}
    /// Its editor opened, and closed with these words (revision 52).
    var onBegin: () -> Void = {}
    var onEnd: (String) -> Void = { _ in }

    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?

    private var ink: Color { Ink.primary }
    /// The words' size: the sticky's own, or the body's (revision 33).
    private var size: CGFloat { CGFloat(node.fontSize ?? Typography.bodySize) }

    var body: some View {
        Group {
            if editing {
                // The note editor, so the format bar and the note's marks
                // work on a sticky as they do in the panel (revision 29).
                MarkdownEditor(text: $text, scrollable: true,
                               baseSize: size, headingSizes: Typography.deskHeadings(size),
                               takesFocus: true,
                               textSize: TextSize(points: node.fontSize), onTextSize: onTextSize,
                               family: node.fontFamily, onFamily: onFamily,
                               alignment: node.textAlign.ns, onDone: onDone)
                    .padding(14)
                    .onAppear {
                        text = node.text ?? ""
                        onBegin()
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
                        onEnd(text)
                    }
            } else if let held = node.text, !held.isEmpty {
                NoteRaster(markdown: held, imageBase: nil, imageStem: "", detail: zoom,
                           base: size, family: node.fontFamily, alignment: node.textAlign.ns)
                    .padding(14)
            } else {
                Text("Double-click to write")
                    .font(Typography.desk(size, node.fontFamily))
                    .foregroundStyle(Ink.muted)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Hepta.fill(node.color ?? "3"))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .elevation(.card)
    }
}

/// A `link` node: a poster for what the address points at. The picture
/// fills the card with the title, author and provider in a caption band
/// under it, the shape the document card has; a post with no picture shows
/// its text instead; an address nobody has fetched yet, or one that
/// answered nothing, shows its host and itself. The live embed is in the
/// panel at 1×, the way a PDF's reader is: a web view under every card
/// would cost a web process each and put AppKit hit-testing under the zoom.
struct LinkNodeView: View {
    let node: CanvasNode
    let selected: Bool
    @ObservedObject private var previews = LinkPreviews.shared

    private var address: String { node.url ?? "" }
    private var kind: LinkKind { LinkKind.classify(address) }
    private var host: String { LinkKind.webURL(address)?.host ?? address }

    var body: some View {
        let meta = previews.meta(for: address)
        let image = meta.flatMap { previews.image(for: $0, kind: kind) }
        let icon = previews.icon(for: address)
        VStack(spacing: 0) {
            if let image {
                picture(image)
            } else if let text = meta?.description ?? meta?.title {
                excerpt(text, by: meta?.author)
            } else {
                bare(icon)
            }
            caption(meta, icon: icon)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .elevation(.card)
    }

    /// The picture fills the room above the caption, cropped, never letterboxed.
    private func picture(_ image: NSImage) -> some View {
        Ink.ground
            .overlay(Image(nsImage: image).resizable().scaledToFill())
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func excerpt(_ text: String, by author: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let author {
                Text(author)
                    .font(Typography.label)
                    .foregroundStyle(Ink.muted)
            }
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Ink.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    /// Nothing has answered for this address: the account it names where
    /// it names one, else the host, over the address itself.
    private func bare(_ icon: NSImage?) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            LinkMark(icon: icon, symbol: kind.symbol, size: 22)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(LinkKind.webURL(address).flatMap { kind.handle(in: $0) } ?? host)
                    .font(Typography.title)
                    .foregroundStyle(Ink.primary)
                Text(address)
                    .font(Typography.meta)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func caption(_ meta: LinkMeta?, icon: NSImage?) -> some View {
        let provider = meta?.provider ?? kind.providerName ?? host
        let title = meta?.title ?? meta?.author ?? provider
        let byline = [meta?.author, provider].compactMap { $0 }.filter { $0 != title }.joined(separator: " · ")
        return HStack(spacing: Space.s) {
            LinkMark(icon: icon, symbol: kind.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.label)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(byline.isEmpty ? 2 : 1)
                if !byline.isEmpty {
                    Text(byline)
                        .font(Typography.micro)
                        .foregroundStyle(Ink.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }
}

/// The mark that says where a link points: the site's own icon once it has
/// arrived, the kind's symbol until then or where the site has none. One
/// glance tells a video from a post from a page.
struct LinkMark: View {
    let icon: NSImage?
    let symbol: Glyph
    var size: CGFloat = 16

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Radius.mark))
        } else {
            GlyphImage(symbol, size: size * 0.8)
                .foregroundStyle(Ink.muted)
                .frame(width: size, height: size)
        }
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
    }
}

/// A section: the desk tinted with the section's colour inside a thin
/// border of it, and the label as a solid pill sitting on the top edge,
/// dark text on colour, the way Heptabase draws it. The pill's "•••" opens
/// the section's menu: colour, rename, remove. A folder's section
/// (revision 20) carries a folder glyph before its name, since renaming
/// or moving it renames or moves the folder on disk.
struct GroupNodeView: View {
    let node: CanvasNode
    let selected: Bool
    @EnvironmentObject private var store: CanvasStore

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.mark)
            .fill(Hepta.sectionFill(node.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.mark)
                .strokeBorder(Hepta.sectionBorder(node.color), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                MenuButton(name: "Section", placement: .below) {
                    NodeMenu.items(for: node, store: store)
                } label: { _ in
                    HStack(spacing: 8) {
                        if Folders.folder(of: node) != nil {
                            GlyphImage(.folder, filled: true)
                                .foregroundStyle(Hepta.labelText.opacity(0.7))
                                .padding(.trailing, -4)
                        }
                        Text(node.label?.isEmpty == false ? node.label! : "Section")
                            .font(Typography.sectionLabel)
                            .foregroundStyle(Hepta.labelText)
                            .lineLimit(1)
                        Text("•••")
                            .font(Typography.micro)
                            .foregroundStyle(Hepta.labelText.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(Hepta.label(node.color)))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .offset(y: -24)
            }
    }
}

/// The items every node's menu shares: fold, the panel, Finder, remove.
/// Its style — colour, fill, stroke, arrowheads, face, size — is the
/// style panel's, said once (revision 39).
@MainActor
enum NodeMenu {
    /// The colours a node can wear: Obsidian's preset codes, by name.
    static let colours: [(String, String?)] = [("None", nil), ("Red", "1"), ("Orange", "2"), ("Yellow", "3"),
                                                ("Green", "4"), ("Blue", "5"), ("Purple", "6")]

    @MenuBuilder
    static func items(for node: CanvasNode, store: CanvasStore) -> [MenuItem] {
        // The selection when the card is in it, else the card alone.
        let ids: Set<String> = store.selection.contains(node.id) ? store.selection : [node.id]
        if node.kind == .file, !store.isDirectoryNode(node), !node.isImage || node.folded {
            MenuItem(node.folded ? "Unfold" : "Fold") { store.toggleFold(ids) }
        }
        if node.kind == .group {
            MenuItem(Folders.folder(of: node) != nil ? "Rename folder…" : "Rename…") {
                store.select(node.id); store.inspectorVisible = true
            }
        }
        if !node.writtenOnDesk, !node.isImage {
            MenuItem("Open in the panel") { store.select(node.id); store.inspectorVisible = true }
        }
        if node.kind == .file, !node.isImage, let file = node.file {
            MenuItem("Add to the side panel") { store.pin(.file(file)) }
        }
        if let path = node.file ?? Folders.folder(of: node), let url = store.vault.url(for: path) {
            MenuItem("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        MenuItem.divider
        MenuItem("Remove from canvas") { store.remove(ids) }
    }
}
