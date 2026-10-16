import AppKit
import PDFKit
import QuickLookThumbnailing

/// QuickLook thumbnails, cached by path and modification date. The OS renders
/// PDFs, images, HTML and code the way Finder does, so a folder's peeks and a
/// photo card need no per-type code.
@MainActor
final class Thumbnails: ObservableObject {
    static let shared = Thumbnails()

    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var pages: [String: PagePreview] = [:]
    private var pending: Set<String> = []
    private var failed: Set<String> = []

    /// A document's first page and how many pages (slides, sheets) it
    /// has, where that is known.
    struct PagePreview: Hashable {
        let image: NSImage
        let count: Int?
    }

    func image(for url: URL, size: CGSize) -> NSImage? {
        let key = Self.key(url)
        if let image = images[key] { return image }
        guard !pending.contains(key), !failed.contains(key) else { return nil }
        pending.insert(key)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            let image = rep?.nsImage
            Task { @MainActor in
                self.pending.remove(key)
                if let image { self.images[key] = image } else { self.failed.insert(key) }
            }
        }
        return nil
    }

    /// A PDF's first page, drawn by PDFKit at the width the card takes on
    /// screen. QuickLook sizes a file's thumbnail once, for whoever asks
    /// first, which is right for a folder's peek and far too coarse for a
    /// card that shows the page itself. `width` is in points; the render is
    /// in pixels, rounded to a step so a pinch does not redraw every frame
    /// and capped so a zoomed-in page cannot cost tens of megabytes. An
    /// office file's first page comes from QuickLook, asked for at that
    /// width (revision 61), since nothing else on the Mac lays one out.
    func page(for url: URL, width: CGFloat) -> PagePreview? {
        let step: CGFloat = 320
        let pixels = width * (NSScreen.main?.backingScaleFactor ?? 2)
        let bucket = min(max((pixels / step).rounded(.up) * step, step * 2), step * 4)
        let key = Self.key(url) + "@\(Int(bucket))"
        if let ready = pages[key] { return ready }
        guard !pending.contains(key), !failed.contains(key) else { return nil }
        pending.insert(key)
        let office = OfficeDocument.Shape.forExtension(url.pathExtension) != nil
        Task.detached(priority: .userInitiated) {
            let rendered = office
                ? await Self.lookFirstPage(of: url, width: bucket)
                : Self.renderFirstPage(of: url, width: bucket)
            await MainActor.run {
                self.pending.remove(key)
                if let rendered { self.pages[key] = rendered } else { self.failed.insert(key) }
            }
        }
        return nil
    }

    private nonisolated static func renderFirstPage(of url: URL, width: CGFloat) -> PagePreview? {
        guard let document = PDFDocument(url: url), let first = document.page(at: 0) else { return nil }
        let bounds = first.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let size = CGSize(width: width, height: (width * bounds.height / bounds.width).rounded())
        return PagePreview(image: first.thumbnail(of: size, for: .mediaBox),
                           count: max(document.pageCount, 1))
    }

    /// QuickLook's first page or slide at `width` pixels. The box is twice
    /// as tall as it is wide so a portrait page and a landscape slide both
    /// come back as wide as asked; the count is read from the zip.
    private nonisolated static func lookFirstPage(of url: URL, width: CGFloat) async -> PagePreview? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: width, height: width * 2),
                                                   scale: 1, representationTypes: .thumbnail)
        let image: NSImage? = await withCheckedContinuation { done in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                done.resume(returning: rep?.nsImage)
            }
        }
        guard let image, image.size.width > 1, image.size.height > 1 else { return nil }
        return PagePreview(image: image, count: OfficeDocument.length(of: url))
    }

    static func key(_ url: URL) -> String {
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return url.path + "#" + String(stamp)
    }
}
