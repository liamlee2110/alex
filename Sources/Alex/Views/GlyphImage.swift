import SwiftUI
import AppKit

/// An icon (revision 24): a Lucide glyph drawn at a size from `Icon`, in
/// a weight from `Icon.Weight`, in whatever `foregroundStyle` it is given
/// — a template image, the way an SF Symbol took the ink round it.
/// `filled` fills the outline too, for a folder standing as a solid
/// coloured shape in the tree and on a section's label.
struct GlyphImage: View {
    private let name: String
    var size: CGFloat = Icon.control
    var weight: Icon.Weight = .regular
    var filled = false

    init(_ glyph: Glyph, size: CGFloat = Icon.control, weight: Icon.Weight = .regular, filled: Bool = false) {
        self.name = glyph.rawValue
        self.size = size
        self.weight = weight
        self.filled = filled
    }

    /// Any Lucide name, for one that comes from a file: a workspace's
    /// `icon` in its `canvas.config.json`. Nil when the sprite has none.
    init?(named name: String, size: CGFloat = Icon.control) {
        guard LucideSprite.shared.has(name) else { return nil }
        self.name = name
        self.size = size
    }

    var body: some View {
        let box = Icon.box(size)
        if let image = LucideSprite.shared.image(name, box: box, stroke: weight.stroke, filled: filled) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: box, height: box)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: box, height: box)
        }
    }
}

/// Lucide's sprite, read once: every `<symbol>` by id, and each icon made
/// into a standalone SVG the first time it is asked for at a size and a
/// stroke. AppKit draws SVG itself (`_NSSVGImageRep`), so the image stays
/// a vector; it is sized to the square it is shown in before SwiftUI sees
/// it, since SwiftUI rasterises an `NSImage` at its own size and scales
/// that, which blurs a 24-point drawing shown larger.
@MainActor
final class LucideSprite {
    static let shared = LucideSprite()

    private var symbols: [String: String] = [:]
    private var cache: [String: NSImage] = [:]

    private init() {
        guard let url = Self.spriteURL(), let text = try? String(contentsOf: url, encoding: .utf8) else {
            FileHandle.standardError.write(Data("icons: lucide.svg not found in the app's resources\n".utf8))
            return
        }
        let pattern = #"<symbol id="([^"]+)" viewBox="0 0 24 24">(.*?)</symbol>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            symbols[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2))
        }
    }

    func has(_ name: String) -> Bool { symbols[name] != nil }

    func image(_ name: String, box: CGFloat, stroke: CGFloat, filled: Bool) -> NSImage? {
        let key = "\(name) \(box) \(stroke) \(filled)"
        if let hit = cache[key] { return hit }
        guard let body = symbols[name] else { return nil }
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" \
            fill="\(filled ? "black" : "none")" stroke="black" stroke-width="\(stroke)" \
            stroke-linecap="round" stroke-linejoin="round">\(body)</svg>
            """
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.size = NSSize(width: box, height: box)
        image.isTemplate = true
        cache[key] = image
        return image
    }

    /// The resource bundle inside the app, found by hand: SwiftPM's
    /// `Bundle.module` looks beside `Alex.app`, not in its Resources, and
    /// falls back to this machine's build folder, so a released copy
    /// would crash on its first icon.
    private static func spriteURL() -> URL? {
        let inApp = Bundle.main.resourceURL?.appendingPathComponent("Alex_Alex.bundle")
        if let inApp, let bundle = Bundle(url: inApp), let url = bundle.url(forResource: "lucide", withExtension: "svg") {
            return url
        }
        // `swift run` from the checkout: the build folder's own bundle.
        return Bundle.module.url(forResource: "lucide", withExtension: "svg")
    }
}
