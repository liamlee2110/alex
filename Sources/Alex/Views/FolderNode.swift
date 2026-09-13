import SwiftUI

/// The back panel of the folder: tab, strip and bottom lip in one
/// silhouette, transcribed from the web original's SVG (a 200 × 150 box).
struct FolderBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 144))
        p.addLine(to: CGPoint(x: 4, y: 30))
        p.addCurve(to: CGPoint(x: 10, y: 24), control1: CGPoint(x: 4, y: 26), control2: CGPoint(x: 6, y: 24))
        p.addLine(to: CGPoint(x: 20, y: 24))
        p.addCurve(to: CGPoint(x: 28, y: 16), control1: CGPoint(x: 24, y: 24), control2: CGPoint(x: 26, y: 22))
        p.addCurve(to: CGPoint(x: 41, y: 5), control1: CGPoint(x: 30, y: 8), control2: CGPoint(x: 34, y: 5))
        p.addLine(to: CGPoint(x: 98, y: 5))
        p.addCurve(to: CGPoint(x: 111, y: 16), control1: CGPoint(x: 105, y: 5), control2: CGPoint(x: 109, y: 8))
        p.addCurve(to: CGPoint(x: 119, y: 24), control1: CGPoint(x: 113, y: 22), control2: CGPoint(x: 115, y: 24))
        p.addLine(to: CGPoint(x: 190, y: 24))
        p.addCurve(to: CGPoint(x: 196, y: 30), control1: CGPoint(x: 194, y: 24), control2: CGPoint(x: 196, y: 26))
        p.addLine(to: CGPoint(x: 196, y: 144))
        p.addQuadCurve(to: CGPoint(x: 190, y: 150), control: CGPoint(x: 196, y: 150))
        p.addLine(to: CGPoint(x: 10, y: 150))
        p.addQuadCurve(to: CGPoint(x: 4, y: 144), control: CGPoint(x: 4, y: 150))
        p.closeSubpath()
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 200, y: rect.height / 150)
        return p.applying(transform)
    }
}

/// A directory on the canvas: two cardstock panels joined at a bottom fold,
/// the first things inside peeking out of the mouth. On hover the back tilts
/// away, the cover tilts toward, and the peeks rise. Folders counter-scale
/// under zoom so they read as markers from far away and reach full size
/// only up close, capped so the deepest zoom belongs to the cards.
struct FolderNodeView: View {
    let node: CanvasNode
    let name: String
    let count: Int
    let peeks: [VaultEntry]
    let selected: Bool
    let zoom: CGFloat

    @EnvironmentObject private var vault: Vault
    @State private var hovering = false

    private static let peekX: [CGFloat] = [16, 72, 128]
    private static let peekY: [CGFloat] = [24, 18, 24]
    private static let peekRotation: [Double] = [-4, 1.5, 4]
    private static let peekOpenY: [CGFloat] = [-16, -20, -16]

    private var topLevelName: String {
        (node.file ?? "").split(separator: "/").first.map(String.init) ?? name
    }

    private var stock: Int { Stock.index(for: topLevelName) }

    private var hue: Double {
        node.hue ?? Stock.hue(forCanvasColor: node.color) ?? Stock.hues[stock]
    }

    private var chroma: Double {
        if let c = node.extra["x-chroma"]?.double { return c }
        return node.hue == nil && node.color == nil ? Stock.chromas[stock] : 1
    }

    var body: some View {
        let open = hovering
        // Damped counter-scale, capped so neighbours in the grid never overlap.
        let counter = min(0.72 * pow(zoom, 0.35), 1.25) / zoom
        let curve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.55)
        ZStack(alignment: .topLeading) {
            FolderBackShape()
                .fill(OKLCH.color(l: 0.865, c: 0.045 * chroma, h: hue))
                .overlay(FolderBackShape()
                    .stroke(OKLCH.color(l: 0.72, c: 0.04 * chroma, h: hue, alpha: 0.5), lineWidth: 0.5))
                .elevation(open ? .lifted : .folder)
                .rotation3DEffect(.degrees(open ? 6 : 0), axis: (x: 1, y: 0, z: 0),
                                  anchor: .bottom, perspective: 0.5)
            ForEach(Array(peeks.prefix(3).enumerated()), id: \.element.path) { i, entry in
                PeekView(entry: entry, url: vault.url(for: entry.path))
                    .frame(width: 62, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(light: "F8F5EF", dark: "3A3C40"), lineWidth: 1.5))
                    .elevation(.raised)
                    .scaleEffect(open ? 1 : 0.94)
                    .rotationEffect(.degrees(Self.peekRotation[i]))
                    .offset(x: Self.peekX[i], y: Self.peekY[i] + (open ? Self.peekOpenY[i] : 6))
            }
            cover(open: open)
        }
        .frame(width: 200, height: 150)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Radius.well)
                    .stroke(Accent.text, lineWidth: 2)
                    .padding(-6)
            }
        }
        .scaleEffect(counter * (selected ? 1.04 : 1))
        .onHover { hovering = $0 }
        .animation(curve, value: hovering)
        .animation(curve, value: selected)
    }

    /// The front cover: the same stock at half strength so the peeks ghost
    /// through, a sheen along the top, a hairline edge. Starts 40 down, so
    /// the back's strip and the mouth show above it.
    private func cover(open: Bool) -> some View {
        RoundedRectangle(cornerRadius: Radius.control)
            .fill(OKLCH.color(l: 0.92, c: 0.042 * chroma, h: hue, alpha: 0.8))
            .overlay(RoundedRectangle(cornerRadius: Radius.control)
                .fill(LinearGradient(
                    colors: [OKLCH.color(l: 0.97, c: 0.02 * chroma, h: hue, alpha: 0.55), .clear],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))))
            .overlay(RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(OKLCH.color(l: 0.72, c: 0.04 * chroma, h: hue, alpha: 0.35), lineWidth: 0.5))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(count == 1 ? "1 item" : "\(count) items")
                        .font(Typography.micro)
                        .foregroundStyle(OKLCH.color(l: 0.44, c: 0.04 * chroma, h: hue))
                    Text(name)
                        .font(Typography.folderTitle)
                        .foregroundStyle(OKLCH.color(l: 0.21, c: 0.03 * chroma, h: hue))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
            }
            .padding(.top, 40)
            .padding(.horizontal, 2)
            .rotation3DEffect(.degrees(open ? -11 : 0), axis: (x: 1, y: 0, z: 0),
                              anchor: .bottom, perspective: 0.5)
    }
}

/// One thing tucked in the folder's mouth: a note as a tiny paper, anything
/// else as the OS's own thumbnail, a directory as a smaller folder.
struct PeekView: View {
    let entry: VaultEntry
    let url: URL?

    @EnvironmentObject private var store: CanvasStore
    @ObservedObject private var thumbnails = Thumbnails.shared

    var body: some View {
        switch entry.kind {
        case .markdown:
            MiniPaper(preview: store.preview(for: entry.path))
        case .directory:
            paper(symbol: "folder")
        default:
            if let url, let image = thumbnails.image(for: url, size: CGSize(width: 62, height: 78)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                paper(symbol: entry.kind.symbol)
            }
        }
    }

    private func paper(symbol: String) -> some View {
        ZStack {
            Ink.card
            Image(systemName: symbol)
                .font(Typography.heading)
                .foregroundStyle(Ink.faint)
        }
    }
}

struct MiniPaper: View {
    let preview: CardPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preview.title)
                .font(Typography.peekTitle)
                .foregroundStyle(Ink.primary)
                .lineLimit(2)
            ForEach(Array(preview.lines.prefix(7).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Typography.peekLine)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.card)
    }
}

extension Typography {
    /// The tiny type on a folder's peeking note. Off the reading scale on
    /// purpose: it is a picture of a note, not a note.
    static let peekTitle = Font.system(size: 7, weight: .medium)
    static let peekLine = Font.system(size: 4.5)
}
