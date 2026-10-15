import AppKit
import SwiftUI

/// The pictures the app carries in `Resources/Mascot` (revision 49): the
/// mascot and its small companions, drawn where the app talks to someone
/// rather than where it works. Found inside the app's resources first, as
/// `LucideSprite` finds its sprite: `Bundle.module` looks beside
/// `Alex.app` and would crash a released copy.
enum Artwork: String {
    case welcome = "alex-welcome"
    case cards = "paper-card-stack"
    case folders = "folder-tabs"
    case emptyCanvas = "alex-empty-canvas"

    private static let places = ["", "Mascot", "Mascot/Micro"]
    @MainActor private static var cache: [Artwork: NSImage] = [:]

    @MainActor var image: NSImage? {
        if let cached = Self.cache[self] { return cached }
        guard let url = url, let image = NSImage(contentsOf: url) else { return nil }
        Self.cache[self] = image
        return image
    }

    private var url: URL? {
        let inApp = Bundle.main.resourceURL?.appendingPathComponent("Alex_Alex.bundle")
        let bundles = [inApp.flatMap(Bundle.init(url:)), Bundle.module].compactMap { $0 }
        for bundle in bundles {
            for folder in Self.places {
                if let url = bundle.url(forResource: rawValue, withExtension: "png",
                                        subdirectory: folder.isEmpty ? nil : folder) { return url }
            }
        }
        return nil
    }
}

/// A bundled picture in a square of `side` points, or nothing if the
/// picture is missing, so a broken bundle costs the art and not the page.
struct ArtworkImage: View {
    let art: Artwork
    let side: CGFloat

    var body: some View {
        if let image = art.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }
}
