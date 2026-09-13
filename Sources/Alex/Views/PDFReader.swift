import SwiftUI
import PDFKit
import AppKit

/// The reader's state, shared between the PDFKit view and the SwiftUI
/// chrome around it.
@MainActor
final class PDFReaderModel: ObservableObject {
    @Published var page = 1
    @Published var pageCount = 1
    @Published var hasSelection = false
    @Published var selectionHasHighlight = false
    @Published var query = ""

    weak var view: PDFView?
    private var hits: [PDFSelection] = []
    private var hitIndex = 0
    private var lastQuery = ""

    func attach(_ view: PDFView) {
        self.view = view
        refresh()
    }

    func refresh() {
        guard let view, let doc = view.document else { return }
        pageCount = max(doc.pageCount, 1)
        if let current = view.currentPage { page = doc.index(for: current) + 1 }
        let selection = view.currentSelection
        hasSelection = !(selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        selectionHasHighlight = selection.map { !highlights(under: $0).isEmpty } ?? false
    }

    func zoom(by factor: CGFloat) {
        guard let view else { return }
        view.autoScales = false
        view.scaleFactor = min(max(view.scaleFactor * factor, 0.25), 6)
    }

    func fitWidth() { view?.autoScales = true }

    func go(by delta: Int) {
        guard let view, let doc = view.document else { return }
        let target = min(max(page - 1 + delta, 0), doc.pageCount - 1)
        if let next = doc.page(at: target) { view.go(to: next) }
        refresh()
    }

    func find(forward: Bool) {
        guard let view, let doc = view.document else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if q != lastQuery {
            hits = doc.findString(q, withOptions: .caseInsensitive)
            hitIndex = 0
            lastQuery = q
        } else if !hits.isEmpty {
            hitIndex = (hitIndex + (forward ? 1 : hits.count - 1)) % hits.count
        }
        guard hits.indices.contains(hitIndex) else { return }
        let hit = hits[hitIndex]
        view.setCurrentSelection(hit, animate: true)
        view.scrollSelectionToVisible(nil)
        refresh()
    }

    var selectedText: String? { view?.currentSelection?.string }

    var selectedPage: Int? {
        guard let view, let doc = view.document, let first = view.currentSelection?.pages.first else { return nil }
        return doc.index(for: first) + 1
    }

    func highlights(under selection: PDFSelection) -> [(PDFPage, PDFAnnotation)] {
        var out: [(PDFPage, PDFAnnotation)] = []
        for page in selection.pages {
            let bounds = selection.bounds(for: page)
            for annotation in page.annotations
            where annotation.type == "Highlight" && annotation.bounds.intersects(bounds) {
                out.append((page, annotation))
            }
        }
        return out
    }

    /// A highlight over the selection, one annotation per line, in the
    /// PDF itself. Returns the bytes to write back.
    func highlight(_ colorName: String) -> Data? {
        guard let view, let doc = view.document, let selection = view.currentSelection else { return nil }
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 1, bounds.height > 1 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = HighlightNS.color(colorName).withAlphaComponent(1)
                page.addAnnotation(annotation)
            }
        }
        view.clearSelection()
        refresh()
        return doc.dataRepresentation()
    }

    func removeHighlights() -> Data? {
        guard let view, let doc = view.document, let selection = view.currentSelection else { return nil }
        for (page, annotation) in highlights(under: selection) { page.removeAnnotation(annotation) }
        view.clearSelection()
        refresh()
        return doc.dataRepresentation()
    }
}

/// Heptabase's PDF reader: the document, a dark toolbar for zoom, page and
/// find, and on selecting text a row with the highlighter colours, copy,
/// and a button that quotes the selection onto the desk. Highlights are
/// written into the PDF file, so Preview and git see them too.
struct PDFReader: View {
    let path: String
    let url: URL
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault
    @StateObject private var model = PDFReaderModel()

    var body: some View {
        VStack(spacing: 0) {
            if model.hasSelection { selectionBar }
            ZStack(alignment: .bottom) {
                PDFKitView(url: url, model: model)
                toolbar
                    .padding(.bottom, Space.l)
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: Space.s) {
            Button {
                if let text = model.selectedText {
                    store.quote(text, from: path, page: model.selectedPage)
                }
            } label: {
                Label("Quote onto the desk", systemImage: "rectangle.3.group")
            }
            .help("A card on the desk, quoting this, linked back here")
            Button {
                if let text = model.selectedText {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
            Divider().frame(height: 18)
            ForEach(Highlight.names, id: \.self) { name in
                Button {
                    if let data = model.highlight(name) { save(data) }
                } label: {
                    Circle()
                        .fill(Highlight.color(name).opacity(1))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Highlight in \(name)")
            }
            Spacer()
            if model.selectionHasHighlight {
                Button {
                    if let data = model.removeHighlights() { save(data) }
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove the highlight")
            }
        }
        .font(Typography.control)
        .padding(.horizontal, Space.m)
        .frame(height: 40)
        .background(Ink.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            tool("plus.magnifyingglass", "Zoom in") { model.zoom(by: 1.25) }
            tool("minus.magnifyingglass", "Zoom out") { model.zoom(by: 0.8) }
            tool("arrow.left.and.right", "Fit width") { model.fitWidth() }
            Divider().frame(height: 16).overlay(Color.white.opacity(0.3))
            tool("chevron.left", "Previous page") { model.go(by: -1) }
            Text("\(model.page) / \(model.pageCount)")
                .font(Typography.control)
                .foregroundStyle(.white)
                .fixedSize()
                .frame(minWidth: 44)
            tool("chevron.right", "Next page") { model.go(by: 1) }
            Divider().frame(height: 16).overlay(Color.white.opacity(0.3))
            TextField("Find", text: $model.query)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(.white)
                .frame(minWidth: 50, idealWidth: 90, maxWidth: 110)
                .onSubmit { model.find(forward: true) }
            tool("magnifyingglass", "Find next") { model.find(forward: true) }
        }
        .padding(.horizontal, Space.s)
        .frame(height: 40)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 440)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Color(light: "2E2E2E", dark: "3A3A3C")))
        .elevation(.raised)
    }

    private func tool(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.control)
                .foregroundStyle(.white)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func save(_ data: Data) {
        do { try vault.write(data, to: path) } catch { NSLog("Alex: could not save PDF \(path): \(error)") }
    }
}

/// A PDFView that fits its first page to its width the first time it has a
/// width: a document loaded before layout is otherwise fitted to nothing
/// and shows a corner of a page at an absurd scale.
final class FittingPDFView: PDFView {
    private var fitted = false

    override func layout() {
        super.layout()
        guard !fitted, bounds.width > 50, let document, let first = document.page(at: 0) else { return }
        fitted = true
        autoScales = true
        scaleFactor = scaleFactorForSizeToFit
        // The scroll view settles after this layout pass; jump once it has.
        DispatchQueue.main.async { [weak self] in
            self?.go(to: first)
            self?.goToFirstPage(nil)
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    let model: PDFReaderModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = FittingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.minScaleFactor = 0.2
        view.maxScaleFactor = 6
        view.document = PDFDocument(url: url)
        let center = NotificationCenter.default
        let model = self.model
        context.coordinator.tokens = [
            center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { _ in
                Task { @MainActor in model.refresh() }
            },
            center.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { _ in
                Task { @MainActor in model.refresh() }
            },
        ]
        DispatchQueue.main.async { model.attach(view) }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL?.standardizedFileURL != url.standardizedFileURL {
            view.document = PDFDocument(url: url)
            DispatchQueue.main.async { model.refresh() }
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        for token in coordinator.tokens { NotificationCenter.default.removeObserver(token) }
    }

    final class Coordinator {
        var tokens: [NSObjectProtocol] = []
    }
}
