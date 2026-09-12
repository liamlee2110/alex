import AppKit
import QuickLookThumbnailing

/// QuickLook thumbnails, cached by path and modification date. The OS renders
/// PDFs, images, HTML and code the way Finder does, so a folder's peeks and a
/// photo card need no per-type code.
@MainActor
final class Thumbnails: ObservableObject {
    static let shared = Thumbnails()

    @Published private(set) var images: [String: NSImage] = [:]
    private var pending: Set<String> = []
    private var failed: Set<String> = []

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

    static func key(_ url: URL) -> String {
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return url.path + "#" + String(stamp)
    }
}
