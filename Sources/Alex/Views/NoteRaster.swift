import SwiftUI
import AppKit
import QuartzCore

/// A note's card body drawn once, as a picture (revision 25). The panel's
/// own renderer lays the note out at the card's width, as revision 18 has
/// it, and draws it into a bitmap at the zoom's detail step; the desk then
/// scales pixels rather than asking forty text views to set their glyphs
/// again at every frame of a pinch, the way Figma and Excalidraw keep a
/// zoom smooth. Pictures are drawn a few at a time between frames; a new
/// detail step shows the picture it has, scaled, until the sharper one is
/// drawn, and a note that changed is drawn again at once.
struct NoteRaster: View {
    let markdown: String
    let imageBase: URL?
    let imageStem: String
    /// `Camera.detail`: the zoom rounded up to a step of √2.
    let detail: CGFloat
    /// The prose size: a card's, or the desk's body for a sticky or a
    /// text box (revision 29).
    var base: CGFloat = Typography.cardEditorSize
    /// A text box's colour (a JSON Canvas colour) for the words; nil is ink.
    var tint: String? = nil
    /// The face (revision 36): a card's, a sticky's or a text box's own.
    var family: FontFamily = .handDrawn
    /// Where the words sit across the card (revision 47).
    var alignment: NSTextAlignment = .natural

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var shown: (key: NoteRasterizer.Key, image: NSImage)?

    var body: some View {
        GeometryReader { geo in
            let key = NoteRasterizer.Key(markdown: markdown, imageBase: imageBase, imageStem: imageStem,
                                         width: geo.size.width.rounded(), height: geo.size.height.rounded(),
                                         scale: detail * displayScale, dark: scheme == .dark,
                                         base: base, tint: tint, family: family, alignment: alignment)
            ZStack(alignment: .topLeading) {
                if let shown {
                    Image(nsImage: shown.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: shown.key.width, height: shown.key.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .task(id: key) { await load(key) }
        }
    }

    private func load(_ key: NoteRasterizer.Key) async {
        guard key.width > 0, key.height > 0 else { return }
        if let hit = NoteRasterizer.cached(key) {
            shown = (key, hit)
            return
        }
        guard let shown else {
            // A first sight — a canvas opening, cards coming into view as
            // the desk zooms out — waits its turn: forty at once in one
            // frame is the stutter this is here to take away.
            if let image = await NoteRasterizer.queued(key) { self.shown = (key, image) }
            return
        }
        guard shown.key.sameContent(as: key) else {
            // The note, its size or the appearance changed: the old
            // picture is wrong, not just soft, so it is redrawn at once.
            self.shown = NoteRasterizer.render(key).map { (key, $0) }
            return
        }
        // Zoomed out a step: the sharper picture already shown is still
        // right, only a little larger than it needs to be.
        if shown.key.scale >= key.scale, shown.key.scale <= 2 * key.scale { return }
        if let image = await NoteRasterizer.queued(key) { self.shown = (key, image) }
    }
}

/// Draws and keeps the pictures, a few milliseconds of them per turn of the
/// run loop so a pinch never waits on them.
@MainActor
enum NoteRasterizer {
    struct Key: Hashable {
        let markdown: String
        let imageBase: URL?
        let imageStem: String
        let width: CGFloat
        let height: CGFloat
        /// Pixels per point of the card: the detail step times the screen's.
        let scale: CGFloat
        let dark: Bool
        var base: CGFloat = Typography.cardEditorSize
        var tint: String? = nil
        var family: FontFamily = .handDrawn
        var alignment: NSTextAlignment = .natural

        func sameContent(as other: Key) -> Bool {
            markdown == other.markdown && imageBase == other.imageBase && width == other.width
                && height == other.height && dark == other.dark && base == other.base && tint == other.tint
                && family == other.family && alignment == other.alignment
        }
    }

    private final class Box: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? Box)?.key == key }
    }

    /// A card's picture is at most this many pixels: at 400% a card
    /// would be tens of megabytes, and past this it is only softer.
    private static let maxPixels: CGFloat = 4_000_000
    private static let cache: NSCache<Box, NSImage> = {
        let cache = NSCache<Box, NSImage>()
        cache.totalCostLimit = 256 << 20
        return cache
    }()
    /// How long one turn may spend drawing before it yields to a frame.
    private static let budget: CFTimeInterval = 0.004

    static func cached(_ key: Key) -> NSImage? { cache.object(forKey: Box(key)) }

    // MARK: Drawing

    static func render(_ key: Key) -> NSImage? {
        let width = key.width, height = key.height
        let scale = min(key.scale, (maxPixels / (width * height)).squareRoot())
        guard let view = laidOut(key) else { return nil }
        let pixelsWide = Int((width * scale).rounded(.up)), pixelsHigh = Int((height * scale).rounded(.up))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)
        view.cacheDisplay(in: NSRect(x: 0, y: 0, width: width, height: height), to: rep)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        cache.setObject(image, forKey: Box(key), cost: pixelsWide * pixelsHigh * 4)
        return image
    }

    /// The note parsed, styled and laid out at the card's size, kept so a
    /// new detail step only draws it again. Laid out down to the card's
    /// foot and no further: a long roadmap's tail is never on the card.
    private static let views: NSCache<Box, MarkdownTextView> = {
        let cache = NSCache<Box, MarkdownTextView>()
        cache.countLimit = 300
        return cache
    }()

    private static func laidOut(_ key: Key) -> MarkdownTextView? {
        let content = Key(markdown: key.markdown, imageBase: key.imageBase, imageStem: key.imageStem,
                          width: key.width, height: key.height, scale: 0, dark: key.dark,
                          base: key.base, tint: key.tint, family: key.family,
                          alignment: key.alignment)
        if let view = views.object(forKey: Box(content)) { return view }
        let width = key.width, height = key.height
        let view = MarkdownTextView.make()
        view.growsWithContent = false
        view.imageBase = key.imageBase
        view.imageStem = key.imageStem
        view.passive = true
        view.isSelectable = false
        view.isEditable = false
        view.isRichText = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        view.appearance = NSAppearance(named: key.dark ? .darkAqua : .aqua)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        guard let storage = view.textStorage else { return nil }
        storage.setAttributedString(NoteMarkdown.attributed(from: key.markdown, width: width, base: key.imageBase))
        NoteStyle.apply(to: storage, base: key.base, headings: Typography.cardEditorHeadings,
                        ink: key.tint.map { NSColor(Hepta.label($0)) } ?? InkNS.primary,
                        family: key.family, alignment: key.alignment)
        view.noteDidRestyle()
        views.setObject(view, forKey: Box(content))
        return view
    }

    // MARK: The queue

    private struct Job {
        let id: UUID
        let key: Key
        let done: CheckedContinuation<NSImage?, Never>
    }
    private static var jobs: [Job] = []
    private static var scheduled = false

    /// The picture for `key`, drawn when its turn comes; nil if the card
    /// stopped wanting it first (the zoom went on past its step).
    static func queued(_ key: Key) async -> NSImage? {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { done in
                jobs.append(Job(id: id, key: key, done: done))
                schedule()
            }
        } onCancel: {
            Task { @MainActor in
                guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
                jobs.remove(at: index).done.resume(returning: nil)
            }
        }
    }

    private static func schedule() {
        guard !scheduled else { return }
        scheduled = true
        // After, not async: a timer lets the run loop draw a frame first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
            MainActor.assumeIsolated { pump() }
        }
    }

    private static func pump() {
        scheduled = false
        let start = CACurrentMediaTime()
        while !jobs.isEmpty, CACurrentMediaTime() - start < budget {
            let job = jobs.removeFirst()
            job.done.resume(returning: cached(job.key) ?? render(job.key))
        }
        if !jobs.isEmpty { schedule() }
    }
}
