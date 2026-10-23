import SwiftUI
import AppKit

// The design tokens. Every colour, size, radius and shadow a view uses comes
// from here; no view invents one inline. The law is Donna's (settled with
// Liam, 2026-08-28), carried over whole, and `run-tests.sh` lints it:
//
// 1. **Two weights.** Regular for reading, Medium for identifying. Semibold
//    and up do not exist, in text or in icons. (Bold typed inside a
//    note is content, not chrome.)
// 2. **No italics** in chrome. Emphasis is ink, not slant.
// 3. **The ink ladder carries hierarchy.** primary = the content; muted =
//    supporting fact; faint = structure whispering; hairline = lines only.
// 4. **Two fills.** `Ink.well` is the one recessed surface; `Ink.wellHover`
//    the hover step. No other primary-opacity fills.
// 5. **Four radii.** mark 4, control 6, well and card 8, panel 16, plus
//    capsules. The panel radius is for a surface standing alone over the
//    desk: the welcome card, the sidebar's cards, the detail sheet.
// 6. **Labels are sentence case.** No uppercase, anywhere.
// 7. **Focus is visible.** Owned chrome wears a focus ring when tabbed to.
// 8. **The scale is written down.** Text from `Typography`, spacing from
//    `Space`, corners from `Radius`, shadows from `Elevation`, icon sizes
//    from `Icon`, colours from `Ink`, `Accent` and `Hepta`. Fixed point
//    sizes are a decision: reading distance is the canvas zoom's job.
// 9. **Motion is on the scale too** (settled with Liam, 2026-09-14). Every
//    duration and curve is a `Motion` token. What the pointer is dragging
//    follows it live; what changed without a drag — a fold, an undo, an
//    arrange, the door — moves to where it went. Reduce Motion turns every
//    token into a cut.
// 10. **One icon button.** Anything that is a glyph you can press is an
//    `IconButton`: it carries its hover, its press and the name a screen
//    reader hears. A tooltip is not a name.
// 11. **One menu** (revision 23). Every menu a button opens and every
//    right-click menu is `PopupMenu`, never SwiftUI's menu views,
//    which draw the system's.
// 12. **One icon set** (revision 24). Every icon is Lucide's, a `Glyph`
//    drawn by `GlyphImage` at a size from `Icon` and a weight from
//    `Icon.Weight`; never an SF Symbol.
// 13. **One keycap** (revision 40). A key the user could press is said
//    as a `KeyCap` wherever it is said — a tooltip, a menu row, Settings
//    — one cap per key, ⌘ and 1 apart; never as bare text. The one
//    exception is the palette's cell, which wears its key bare at the
//    corner (Excalidraw's shape): a cap inside a cell is a button in a
//    button.
//
// Alex adds one thing Donna did not have: **paper**. Folders and stickies
// are coloured objects resting on the desk, and their colours come from
// `OKLCH` so the lightness ladder ported from the web original survives
// the move. Everything else is neutral (PLAN.md, revision 13): white
// where something is read or pressed — the sidebar, a card, the sheet,
// the chrome — under it all the desk, white warmed by the faintest trace
// of the logo's butter yellow (revision 60), black type, and one blue for
// what is live: the selection, a link, the caret, the door.
//
// The chrome says three things in three shapes (PLAN.md, revision 18,
// from the dashboards Liam showed): **where you are** is a grey square
// under the row or the glyph (the open canvas, the picked file, a toggle
// that is on); **the tool in hand** is a solid blue square with a white
// glyph (the palette, the open workspace's mark: revision 30, Figma's
// tool in hand); **what to press** is a capsule, solid black for the one
// thing a surface asks of you and outlined for the rest. Blue is kept for
// what is live — and the tool in hand is live, waiting for the desk —
// and is never a wash or a highlight behind a row.

// MARK: - Shape and space

enum Radius {
    static let mark: CGFloat = 4
    static let control: CGFloat = 6
    static let well: CGFloat = 8
    static let card: CGFloat = 8
    /// A surface standing alone over the desk: the
    /// sidebar's card, shown or folded to its head, the detail sheet and
    /// its sub-sheets (revision 21).
    static let panel: CGFloat = 16
}

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// The bundled pictures' sizes (revision 49): the mascot over the welcome
/// card and the small pictures on its two ways in.
enum Art {
    static let hero: CGFloat = 120
    static let choice: CGFloat = 64
}

/// The lines drawn on the desk (revision 15): a shape's outline, its dash,
/// and the arrowhead on a line. In world units, so they zoom with the
/// shape the way a card's chrome does.
enum Stroke {
    static let shape: CGFloat = 2
    static let dash: [CGFloat] = [8, 6]
    static let arrowhead: CGFloat = 12

    /// A stroke's pattern at a width (revision 55): the dash grows with a
    /// bold stroke so it still reads as dashes; a dot is a round cap with
    /// nothing between, three widths apart.
    static func pattern(_ pattern: StrokePattern, width: CGFloat) -> [CGFloat] {
        let scale = max(1, width / shape)
        switch pattern {
        case .solid: return []
        case .dashed: return dash.map { $0 * scale }
        case .dotted: return [0, max(width * 3, 4)]
        }
    }

    /// The style panel's stroke cells draw a short line, this long, with
    /// the pattern scaled down to fit it.
    static let sample: CGFloat = 18
    static let sampleDash: [CGFloat] = [4, 3]
}

/// What a selection wears on the desk (revision 26), in screen points so
/// it stays one size at every zoom: Figma's square blue outline, its four
/// corner squares, white with a blue edge, and the connector's dot on
/// each side, which shows on a block selected alone (revision 34).
enum Handle {
    static let outline: CGFloat = 1
    static let corner: CGFloat = 8
    /// What a resize grip answers (revision 66), centred on what it
    /// stands for, as Figma's do: a square this wide round each corner's
    /// mark, and a band this deep across each edge, half over the desk
    /// and half over the node. Before, a corner's grip began two points
    /// out, so the outer half of the square you aimed at was the desk.
    static let cornerGrip: CGFloat = 16
    static let edgeGrip: CGFloat = 8
    /// The live size a resize shows under its node, this far below it.
    static let readoutGap: CGFloat = Space.s
    /// A connector's dot: the corner square's size, pressed within a
    /// circle `connectorHit` wide (revision 42), which starts where the
    /// edge's resize grip ends.
    static let connector: CGFloat = 8
    static let connectorHit: CGFloat = 12
    /// How far a connector's centre stands out of the card's edge.
    static let connectorStandsOut: CGFloat = 14
    /// How near a side, on screen, the pointer brings its dot out: this
    /// far inside the edge, and this far beyond it (past the dot).
    static let connectorInside: CGFloat = 16
    static let connectorOutside: CGFloat = 24
    /// How near a block, on screen, an arrow's end attaches to it
    /// (revision 34; Excalidraw's is 15 to 30).
    static let bindReach: CGFloat = 16
    /// How near an unfilled shape's outline or a line, on screen, a press
    /// takes it (revision 53; Excalidraw's is about 7): its inside is the
    /// desk's, so a box drawn round cards leaves them pressable.
    static let strokeHit: CGFloat = 7
}

// MARK: - The shell

/// The window's geometry (PLAN.md, revisions 16, 21 and 37): the sidebar
/// a card floating over the desk's left with the traffic lights in its
/// head row, folding into that head alone; the desk filling the window's
/// full height; the detail sheet floating at its right. No toolbar and
/// nothing drawn above any of it.
enum Shell {
    /// The margin every floating thing keeps from the desk's edge.
    static let gutter: CGFloat = Space.m
    /// The icon picker's grid (revision 67): five lines of cells and the
    /// top of a sixth, so it reads as one that scrolls.
    static let iconPickerHeight: CGFloat = 200
    /// The sidebar's card: what it opens at, and how far its edge drags
    /// either way.
    static let sidebar: CGFloat = 280
    static let sidebarMin: CGFloat = 220
    static let sidebarMax: CGFloat = 420
    /// The sidebar's rows: the nav and the tree share one height.
    static let row: CGFloat = 28
    /// The sidebar's head row, which the traffic lights stand in: its
    /// height, a gutter below the window's top.
    static let headRow: CGFloat = 40
    /// Where the close button's leading edge stands, from the window's
    /// left, and the width of the three lights with AppKit's spacing
    /// (measured on macOS 15). `WindowChrome` lays them there.
    static let lightsLeading: CGFloat = gutter + Space.l
    static let lightsWidth: CGFloat = 54
    /// The centre of the head row, from the window's top: the lights' row.
    static let lightsCentre: CGFloat = gutter + headRow / 2
    /// The sidebar folded (revision 37): its head cut to the lights and
    /// the toggle, the one glyph left at the desk's top left.
    static let sidebarFolded: CGFloat = lightsLeading - gutter + lightsWidth + Space.xs
        + IconButton.Size.regular.side.width + Space.s
    /// How far two fingers travel across the sidebar before it turns the
    /// page to the next workspace.
    static let swipe: CGFloat = 80
    /// A sub-sheet stands this much shorter than the sheet at each end,
    /// and tucks this far under its edge, so it reads as drawn out of it.
    static let subsheetInset: CGFloat = Space.xl
    static let subsheetTuck: CGFloat = Radius.panel
    /// The detail sheet: Heptabase's wide panel, and room for each pin.
    static let panelMin: CGFloat = 340
    static let panelMax: CGFloat = 1400
    static func panelWidth(pins: Int) -> CGFloat { 560 + 400 * CGFloat(pins) }
    /// The panel's head row, and the inset its content keeps from the
    /// column's edges (revision 18): a page's margin, wider than a card's.
    static let panelHead: CGFloat = 44
    static let panelInset: CGFloat = Space.xl
    /// A text button's height: between a sidebar row and a palette cell.
    static let button: CGFloat = 30
    /// A `KeyCap`'s square (revision 40): the label's line, a little room.
    static let keyCap: CGFloat = 18
    /// What the desk keeps when the panel is dragged wider.
    static let deskMin: CGFloat = 320
    /// The strip either side of a divider that takes the resize pointer.
    static let handle: CGFloat = 9
    /// The quick sketch (revision 59): the desk it opens at and the least
    /// it is dragged to, and the tab that rises out of its top edge, its
    /// corners the card's and the curve where it meets the edge too.
    static let sketch = CGSize(width: 960, height: 640)
    static let sketchMin = CGSize(width: 480, height: 320)
    static let sketchTab: CGFloat = 34
    /// The tab is what moves the window (revision 64), so it is wide
    /// enough to hold, as Safari's tab is: the name centred, the close
    /// glyph at the leading edge, and either side of the name a shoulder
    /// of blank at least `sketchTabShoulder` wide — two small glyph
    /// buttons, a comfortable hold — however long the name; the tab grows
    /// with the name only to `sketchTabMax`, which the smallest window's
    /// top edge still has room for.
    static let sketchTabMin: CGFloat = 280
    static let sketchTabMax: CGFloat = 420
    static let sketchTabShoulder: CGFloat = 48
    static let sketchTabCorner: CGFloat = Radius.card
    /// Room round the sketch and its style panel, each in a window of
    /// its own, for the card's shadow: one `Elevation`, not the window's.
    static let sketchMargin: CGFloat = Space.xl
}

/// The desk's dot grid: a lattice in world units, drawn in screen space,
/// doubled while a step of zoom would bring the dots closer than `minimum`.
enum Grid {
    static let spacing: CGFloat = 24
    static let dot: CGFloat = 1.5
    static let minimum: CGFloat = 12
}

// MARK: - Typography

enum Typography {
    /// The app's own name and the welcome page.
    static let display = Font.system(size: 34, weight: .medium)
    /// A card's title on the canvas: Heptabase's bold card head, in the
    /// law's heavier weight.
    static let cardTitle = Font.system(size: 15, weight: .medium)
    /// A note's card title in the card's face (revision 36).
    static func cardTitle(_ family: FontFamily) -> Font {
        Font(DeskFace.font(family, size: 15, weight: .medium))
    }
    /// A folder's name on its cover.
    static let folderTitle = Font.system(size: 17, weight: .medium)
    static let figure = Font.system(size: 22, weight: .medium)
    static let title = Font.system(size: 15, weight: .medium)
    static let heading = Font.system(size: 14, weight: .medium)
    /// A section's head inside the panel — Info, Backlinks, Not placed: a
    /// step up from the body in the reading weight and the supporting
    /// ink, so it names a part without competing with the note's own
    /// headings (revision 18).
    static let section = Font.system(size: 15)
    static let bodySize: CGFloat = 13
    static let body = Font.system(size: bodySize)
    /// Words on the desk at a sticky's or a shape's own size (revision 33)
    /// and in its face (revision 36).
    static func desk(_ size: CGFloat, _ family: FontFamily = .normal) -> Font {
        Font(DeskFace.font(family, size: size))
    }
    /// A note's three headings at a desk size, in the card's proportions.
    static func deskHeadings(_ size: CGFloat) -> [CGFloat] {
        cardEditorHeadings.map { ($0 * size / cardEditorSize).rounded() }
    }
    static let proseSize: CGFloat = 12.5
    static let prose = Font.system(size: proseSize)
    static let control = Font.system(size: 13, weight: .medium)
    static let meta = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .medium)
    static let micro = Font.system(size: 11, weight: .medium)
    /// A key on a `KeyCap` (revision 40): the label's size in the
    /// identifying weight, digits one width.
    static let key = Font.system(size: 11, weight: .medium)
    /// The key a palette cell wears at its corner, bare: small enough to
    /// sit beside the glyph without touching it.
    static let keyMark = Font.system(size: 9, weight: .medium)
    /// The section label pill.
    static let sectionLabel = Font.system(size: 13, weight: .medium)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmallSize: CGFloat = 10
    static let monoSmall = Font.system(size: monoSmallSize, weight: .regular, design: .monospaced)
    /// The tiny type on a folder's peeking note. Off the reading scale on
    /// purpose: it is a picture of a note, not a note.
    static let peekTitle = Font.system(size: 7, weight: .medium)
    static let peekLine = Font.system(size: 4.5)

    /// The editor's prose and its three headings, in the panel (14.5, the
    /// size PLAN.md revision 4 measured from Heptabase) and on a card, where
    /// the prose is the preview's and a heading is the card's own title.
    static let editorSize: CGFloat = 14.5
    static let editorHeadings: [CGFloat] = [24, 19, 16]
    static let cardEditorSize: CGFloat = proseSize
    static let cardEditorHeadings: [CGFloat] = [15, 14, 13]

    /// How tall one line is at a point size, measured from the font rather
    /// than guessed, so a view can budget its lines against the room it has.
    static func lineHeight(ofSize size: CGFloat, monospaced: Bool = false) -> CGFloat {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size)
        return ceil(font.ascender - font.descender + font.leading)
    }
}

/// A node's alignment (revision 47) in each framework's words.
extension TextAlign {
    var ns: NSTextAlignment {
        switch self { case .left: return .left; case .center: return .center; case .right: return .right }
    }
    var text: TextAlignment {
        switch self { case .left: return .leading; case .center: return .center; case .right: return .trailing }
    }
    var horizontal: HorizontalAlignment {
        switch self { case .left: return .leading; case .center: return .center; case .right: return .trailing }
    }
    var glyph: Glyph {
        switch self { case .left: return .textAlignStart; case .center: return .textAlignCenter; case .right: return .textAlignEnd }
    }
}

/// The faces words on the desk are drawn in (revision 36): Excalidraw's
/// Excalifont, bundled (OFL, `Resources/Fonts`), the system's, and its
/// monospaced one. Excalifont is read from the app's resources once and
/// never installed, so it is Alex's alone.
enum DeskFace {
    static func font(_ family: FontFamily, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch family {
        case .normal: return NSFont.systemFont(ofSize: size, weight: weight)
        case .code: return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .handDrawn:
            return excalifont.flatMap { NSFont(descriptor: $0, size: (size * handScale).rounded()) }
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    /// Excalifont's capitals stand 60 to the system face's 70 at one point
    /// size (measured), so it is drawn this much larger to read at the
    /// same size: Medium beside Medium.
    static let handScale: CGFloat = 1.15

    private static let excalifont: NSFontDescriptor? = {
        guard let url = fontURL(), let data = try? Data(contentsOf: url),
              let found = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let first = found.first else {
            FileHandle.standardError.write(Data("fonts: Excalifont not found in the app's resources\n".utf8))
            return nil
        }
        return first as NSFontDescriptor
    }()

    /// Inside the app's resources first, as `LucideSprite` looks (a released
    /// copy has no build folder for `Bundle.module` to find).
    private static func fontURL() -> URL? {
        let name = "Excalifont-Regular", ext = "woff2"
        let inApp = Bundle.main.resourceURL?.appendingPathComponent("Alex_Alex.bundle")
        if let inApp, let bundle = Bundle(url: inApp) {
            if let url = bundle.url(forResource: name, withExtension: ext)
                ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fonts") { return url }
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fonts")
    }
}

// MARK: - Icons

/// Icon sizes (revision 24). An icon beside text takes the text's size;
/// the rest are the four sizes one is drawn at when it stands alone. The
/// size is the text size the icon sits with, as an SF Symbol's was: the
/// icon's square is `box` of it, Lucide's 24-unit grid drawn a fifth
/// larger than the type so its optical size matches the letters.
enum Icon {
    /// The sidebar's disclosure chevron.
    static let mark: CGFloat = 9
    /// Beside 13pt text, and every small button.
    static let control: CGFloat = 13
    /// The zoom bar.
    static let bar: CGFloat = 15
    /// The tool palette.
    static let tool: CGFloat = 17
    /// Beside 11pt text: a chip, "Appears in".
    static let micro: CGFloat = 11
    /// A card with no picture of its own: an image not yet drawn, a
    /// canvas, a PDF.
    static let hero: CGFloat = 34
    /// The status dot before a chip's text.
    static let dot: CGFloat = 6

    /// The largest picture an icon on the desk is drawn into (revision
    /// 67): past it, zooming in further scales the picture.
    static let deskRaster: CGFloat = 1024

    /// The square an icon of `size` is drawn in.
    static func box(_ size: CGFloat) -> CGFloat { (size * 1.2).rounded() }

    /// The two weights (law 1), as Lucide line widths in its 24-unit
    /// grid: regular for an icon, medium where the text beside it or the
    /// mark it makes is medium (a chevron, a tick). Measured against the
    /// SF Symbols they replace.
    enum Weight {
        case regular, medium

        var stroke: CGFloat { self == .medium ? 2.25 : 1.75 }
    }
}

// MARK: - Motion

/// The four ways anything moves (law 9). `nil` is a cut: what Reduce Motion
/// asks for, and what a `withAnimation(nil)` gives.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Feedback: a press, a hover, a selection ring.
    static var quick: Animation? { reduced ? nil : .easeOut(duration: 0.12) }
    /// A thing already on screen changing size or place: a fold, an undo,
    /// a step of zoom, the sidebar's column.
    static var move: Animation? { reduced ? nil : .easeInOut(duration: 0.22) }
    /// The desk's camera: fit and focus. Starts fast so the pan reads as
    /// an answer, and settles long enough to keep the eye on the card.
    static var camera: Animation? { reduced ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.35) }
    /// The folder's hinge, the choreography D8 pins to the React original.
    static var hinge: Animation? { reduced ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.55) }
    /// Opacity only: a pulse, a crossfade. Kept under Reduce Motion, which
    /// asks for less movement, not for things to blink into being.
    static var fade: Animation { .easeOut(duration: 0.2) }
    /// How long the pointer rests on a glyph before its tooltip shows
    /// (revision 15). Never at once: a label that leaps at every pass of
    /// the pointer is noise.
    static let tooltipDelay: Duration = .milliseconds(600)
}

// MARK: - The icon button

/// Every glyph you can press (law 10). One shape, four sizes; the hover
/// fill, the press and the name a screen reader hears all live here.
struct IconButton: View {
    enum Size {
        /// A card's chrome, the sidebar's foot.
        case small
        /// The panel's head and the reader's toolbar.
        case regular
        /// The zoom bar.
        case bar
        /// The tool palette's cell.
        case tool

        var side: CGSize {
            switch self {
            case .small: return CGSize(width: 24, height: 24)
            case .regular: return CGSize(width: 28, height: 28)
            case .bar: return CGSize(width: 32, height: 32)
            case .tool: return CGSize(width: 32, height: 32)
            }
        }

        /// The cell's corner. The palette's and the zoom bar's cells sit
        /// `Space.s` inside a pill at the panel radius, so theirs is the
        /// well's, and the two curves run parallel (revision 22).
        var radius: CGFloat {
            switch self {
            case .small, .regular: return Radius.control
            case .bar, .tool: return Radius.well
            }
        }

        var glyph: CGFloat {
            switch self {
            case .small, .regular: return Icon.control
            case .bar: return Icon.bar
            case .tool: return Icon.tool
            }
        }
    }

    let symbol: Glyph
    /// The verb: what VoiceOver reads, and the tooltip unless `hint` says more.
    let label: String
    /// A longer tooltip, when the verb alone is not enough.
    var hint: String? = nil
    /// The key that does the same, shown muted after the tooltip.
    var shortcut: String? = nil
    var size: Size = .regular
    /// On: the grey square under the glyph for a place or a toggle, or
    /// the solid square for the tool in hand.
    var active = false
    var activeStyle: ActiveStyle = .well
    /// The panel's bordered variant: paper with a hairline.
    var bordered = false
    var round = false
    /// The glyph's ink when it is not `Ink.icon`: on the reader's dark bar.
    var ink: Color = Ink.icon
    /// The key the cell wears at its corner (revision 40): the palette's
    /// tools, whose bare key picks them on the desk.
    var key: String? = nil
    /// Any of Lucide's icons by name, drawn in `symbol`'s place: the icon
    /// picker's cells (revision 67), whose icons are not all `Glyph`s.
    var lucide: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            ToolCell(symbol: symbol, size: size, key: key, lucide: lucide,
                     ink: active ? activeStyle.ink : enabled ? ink : Ink.faint,
                     keyInk: active ? activeStyle.ink : Ink.muted)
        }
        .buttonStyle(IconButtonStyle(active: active ? activeStyle : nil, bordered: bordered, round: round,
                                     radius: size.radius))
        .tooltip(hint ?? label, name: label, shortcut: shortcut)
        .accessibilityLabel(label)
    }
}

/// A cell's glyph, and the key it wears when it has one: the key at the
/// bottom-right corner in `Typography.keyMark`, and the glyph stepped a
/// point up and left of centre so the pair reads centred (revision 40).
/// Excalidraw's cell, in Alex's ink; nothing when there is no key.
struct ToolCell: View {
    let symbol: Glyph
    let size: IconButton.Size
    var key: String? = nil
    var lucide: String? = nil
    var ink: Color = Ink.icon
    var keyInk: Color = Ink.muted

    var body: some View {
        Group {
            if let lucide, let named = GlyphImage(named: lucide, size: size.glyph) {
                named
            } else {
                GlyphImage(symbol, size: size.glyph)
            }
        }
        .foregroundStyle(ink)
        .offset(x: key == nil ? 0 : -1, y: key == nil ? 0 : -1)
        .frame(width: size.side.width, height: size.side.height)
        .overlay(alignment: .bottomTrailing) {
            if let key {
                Text(key)
                    .font(Typography.keyMark)
                    .monospacedDigit()
                    .foregroundStyle(keyInk)
                    .padding(.trailing, 3)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - The keycap

/// A key the user could press, said as the cap it is on (law 13,
/// revision 40): a small square at the mark radius on the recessed fill
/// with a hairline edge, the key in `Typography.key` in the supporting
/// ink — Raycast's caps, in Alex's grey. `KeyCaps` draws a whole
/// shortcut, one cap per key, ⌘ and N apart.
struct KeyCap: View {
    let key: String
    /// Settings' recorder, listening: the edge in the one blue.
    var live = false

    init(_ key: String, live: Bool = false) {
        self.key = key
        self.live = live
    }

    var body: some View {
        Text(key)
            .font(Typography.key)
            .monospacedDigit()
            .foregroundStyle(Ink.muted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.xs + 1)
            .frame(minWidth: Shell.keyCap, minHeight: Shell.keyCap)
            .background(RoundedRectangle(cornerRadius: Radius.mark).fill(Ink.well))
            .overlay(RoundedRectangle(cornerRadius: Radius.mark)
                .strokeBorder(live ? Accent.text : Ink.hairline, lineWidth: 1))
    }
}

struct KeyCaps: View {
    let shortcut: String

    init(_ shortcut: String) { self.shortcut = shortcut }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(ToolKeys.caps(shortcut).enumerated()), id: \.offset) { KeyCap($0.element) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut)
    }
}

/// How a glyph that is on is drawn (revision 18). `.well` is the grey
/// square that says where you are: the open canvas's row in the sidebar,
/// the panel's toggle while the panel stands. `.solid` is the blue square
/// for the tool in hand, the palette's cell (revision 30).
enum ActiveStyle {
    case well, solid

    var ink: Color { self == .solid ? Accent.onSolid : Ink.primary }
    var fill: Color { self == .solid ? Accent.solid : Ink.wellHover }
}

/// A menu worn as an icon button (law 10): the layers' `•••`, the
/// palette's Shapes and Add. The same sizes, hover, press and tooltip as
/// `IconButton`; what differs is that pressing it opens the app's menu
/// (`PopupMenu`), which a palette cell says with a small chevron beside
/// its glyph, as Figma's flyouts do (revision 22). While the menu stands
/// the cell keeps the hover's grey square.
struct IconMenu: View {
    let symbol: Glyph
    /// The verb: what VoiceOver reads, and the tooltip unless `hint` says more.
    let label: String
    var hint: String? = nil
    var shortcut: String? = nil
    var size: IconButton.Size = .regular
    /// The chevron that says a menu opens: in the palette, where the
    /// cells beside it are plain buttons.
    var disclosure = false
    /// On: as `IconButton`.
    var active = false
    var activeStyle: ActiveStyle = .well
    /// The key the cell wears at its glyph's corner, before the chevron.
    var key: String? = nil
    @MenuBuilder let items: () -> [MenuItem]

    var body: some View {
        MenuButton(name: label, items: items) { open in
            let style: ActiveStyle? = active ? activeStyle : open ? .well : nil
            HStack(spacing: 0) {
                ToolCell(symbol: symbol, size: size, key: key, ink: style?.ink ?? Ink.icon,
                         keyInk: active ? activeStyle.ink : Ink.muted)
                if disclosure {
                    GlyphImage(.chevronDown, size: Icon.mark, weight: .medium)
                        .foregroundStyle(style?.ink ?? Ink.muted)
                        .padding(.leading, 2)
                }
            }
            .frame(width: size.side.width + (disclosure ? Icon.mark + 3 : 0), height: size.side.height)
            .background {
                if let style, !active {
                    RoundedRectangle(cornerRadius: size.radius).fill(style.fill)
                }
            }
        }
        .buttonStyle(IconButtonStyle(active: active ? activeStyle : nil, radius: size.radius))
        .tooltip(hint ?? label, name: label, shortcut: shortcut)
        .accessibilityLabel(label)
    }
}

/// Hover fills the well, a press fills the hover step and scales to 0.96,
/// both on `Motion.quick`; a glyph that is on keeps its active fill under
/// both. A `ButtonStyle` is not a view, so the hover state lives in the
/// body it makes.
struct IconButtonStyle: ButtonStyle {
    var active: ActiveStyle? = nil
    var bordered = false
    var round = false
    var radius: CGFloat = Radius.control

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, active: active, bordered: bordered, round: round,
                       radius: radius)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        let active: ActiveStyle?
        let bordered: Bool
        let round: Bool
        let radius: CGFloat
        @State private var hovering = false

        private var fill: Color {
            if let active { return active.fill }
            if configuration.isPressed { return Ink.wellHover }
            if hovering { return Ink.well }
            return bordered ? Ink.card : .clear
        }

        var body: some View {
            configuration.label
                .background {
                    // Hover, press and the tool in hand are one shape, the
                    // cell itself: the pill's padding is the rim round it.
                    if round {
                        Circle().fill(fill)
                    } else {
                        RoundedRectangle(cornerRadius: radius).fill(fill)
                    }
                }
                .overlay {
                    if bordered {
                        if round {
                            Circle().strokeBorder(Ink.hairline, lineWidth: 1)
                        } else {
                            RoundedRectangle(cornerRadius: radius).strokeBorder(Ink.hairline, lineWidth: 1)
                        }
                    }
                }
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(Motion.quick, value: configuration.isPressed)
                .animation(Motion.quick, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - The text button

/// A verb with a name (revision 18): a capsule, solid for the one thing a
/// surface asks of you — open the folder, place everything, add the link
/// — and outlined for the rest. The system's button shapes stay out of
/// the window: Settings' rows are the app's own since it became a sheet
/// over the desk (revision 41), and a menu is the app's own (`PopupMenu`,
/// revision 23).
struct CapsuleButtonStyle: ButtonStyle {
    var solid = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, solid: solid)
    }

    private struct CapsuleButtonBody: View {
        let configuration: Configuration
        let solid: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typography.control)
                .foregroundStyle(solid ? Ink.onSolid : Ink.primary)
                .lineLimit(1)
                .padding(.horizontal, Space.l)
                .frame(height: Shell.button)
                .background(Capsule().fill(solid ? Ink.solid : hovering ? Ink.well : Ink.card))
                .overlay {
                    if !solid { Capsule().strokeBorder(Ink.hairline, lineWidth: 1) }
                }
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.quick, value: configuration.isPressed)
                .animation(Motion.quick, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    static var solid: CapsuleButtonStyle { CapsuleButtonStyle(solid: true) }
    static var outline: CapsuleButtonStyle { CapsuleButtonStyle() }
}

// MARK: - Elevation

/// The shadow recipes. Applied with `.elevation(_:)`; nil keeps the layout
/// slot with no shadow.
struct Elevation {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    /// A card resting on the desk: white on grey, barely a shadow.
    static let card = Elevation(opacity: 0.04, radius: 2, y: 1)
    /// Floating chrome: the tool palette, the zoom bar, peeks.
    static let raised = Elevation(opacity: 0.10, radius: 8, y: 2)
    static let knob = Elevation(opacity: 0.12, radius: 1.5, y: 0.5)
    /// The folder's back panel.
    static let folder = Elevation(opacity: 0.08, radius: 8, y: 3)
    /// Anything under the pointer or being dragged.
    static let lifted = Elevation(opacity: 0.14, radius: 16, y: 6)
}

extension View {
    func elevation(_ e: Elevation?) -> some View {
        shadow(color: Ink.shadow.opacity(e?.opacity ?? 0),
               radius: e?.radius ?? 0, y: e?.y ?? 0)
    }
}

// MARK: - Focus

private struct FocusRing<S: InsettableShape>: ViewModifier {
    @Environment(\.isFocused) private var focused
    let shape: S

    func body(content: Content) -> some View {
        content.overlay(
            shape.inset(by: -2.5)
                .strokeBorder(Accent.text.opacity(focused ? 0.8 : 0), lineWidth: 2))
    }
}

extension View {
    func focusRing() -> some View {
        modifier(FocusRing(shape: Capsule()))
    }

    func focusRing(cornerRadius: CGFloat) -> some View {
        modifier(FocusRing(shape: RoundedRectangle(cornerRadius: cornerRadius)))
    }
}

// MARK: - Colour plumbing

private extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        assert(hex.count == 6 && Scanner(string: hex).scanHexInt64(&v), "bad hex literal \(hex)")
        Scanner(string: hex).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension NSColor {
    /// One value per appearance, resolved at draw time.
    static func dynamic(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

extension Color {
    init(light: String, dark: String) {
        self.init(nsColor: .dynamic(light: light, dark: dark))
    }
}

// MARK: - Ink

/// Text and structure, as AppKit colours for the TextKit editor and as
/// SwiftUI colours for everything else. Same ladder, one file. Neutral
/// throughout (revision 13): black type on white and light grey.
enum InkNS {
    static let primary  = NSColor.dynamic(light: "1B1D21", dark: "ECECEE")
    static let muted    = NSColor.dynamic(light: "6B7078", dark: "A0A3A9")
    static let faint = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return dark ? NSColor(hex: "A0A3A9") : NSColor(hex: "6B7078")
        }
        return dark ? NSColor(hex: "6F7379") : NSColor(hex: "9CA0A6")
    }
    static let hairline = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return dark ? NSColor(hex: "5A5B5F") : NSColor(hex: "C9CACD")
        }
        return dark ? NSColor(hex: "333336") : NSColor(hex: "E6E6E8")
    }
    /// Edges between cards: Heptabase's near-black arrow ink.
    static let guide = NSColor.dynamic(light: "3A3D42", dark: "B8BABF")
    static let well = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(hex: "ECECEE").withAlphaComponent(0.06)
            : NSColor(hex: "1B1D21").withAlphaComponent(0.05)
    }
    static let wellHover = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(hex: "ECECEE").withAlphaComponent(0.10)
            : NSColor(hex: "1B1D21").withAlphaComponent(0.08)
    }
    /// Ink on the accent or on the reader's dark bar: white in both
    /// appearances, because what it sits on is dark in both.
    static let inverse = NSColor.white
}

enum Ink {
    static let primary  = Color(nsColor: InkNS.primary)
    static let muted    = Color(nsColor: InkNS.muted)
    static let faint    = Color(nsColor: InkNS.faint)
    static let hairline = Color(nsColor: InkNS.hairline)
    /// Edges between cards and the rail beside a quote.
    static let guide    = Color(nsColor: InkNS.guide)
    static let well     = Color(nsColor: InkNS.well)
    static let wellHover = Color(nsColor: InkNS.wellHover)
    /// White: a card, the sidebar.
    static let card     = Color(light: "FFFFFF", dark: "232326")
    /// The light grey of a card's recess: a page not yet drawn.
    static let ground   = Color(light: "F5F5F6", dark: "151517")
    /// Under everything, the desk (revision 60): white with a trace of the
    /// logo's yellow (#F0D070), barely one part in a hundred, so the
    /// white chrome and cards still stand off it by their hairline and
    /// shadow. The quick sketch's desk and tab are the same.
    static let desk     = Color(light: "FFFEFB", dark: "161615")
    /// Chrome floating over the desk: the tool palette, the zoom bar,
    /// the folded sidebar's cards, the detail sheet.
    static let float    = Color(light: "FFFFFF", dark: "2A2A2E")
    /// Icon ink in the chrome and the sidebar.
    static let icon     = Color(light: "4A4E55", dark: "C8CACF")
    /// Live-canvas marks and the door lamp: the one blue.
    static let live     = Color(light: "1E88E5", dark: "4DA3FF")
    /// Ink on the accent or on the reader's dark bar.
    static let inverse  = Color(nsColor: InkNS.inverse)
    /// The one button a surface asks you to press, and its ink: black on
    /// white, and the reverse in the dark (revision 18). The tool in hand
    /// is `Accent.solid` since revision 30.
    static let solid    = Color(light: "1B1D21", dark: "ECECEE")
    static let onSolid  = Color(light: "FFFFFF", dark: "1B1D21")
    /// The PDF reader's floating toolbar: Heptabase's dark bar, dark in
    /// both appearances, so `inverse` is its ink.
    static let readerBar = Color(light: "2A2D31", dark: "1A1B1E")
    /// What the desk wears under the ⌘K panel.
    static let scrim    = Color(light: "000000", dark: "000000").opacity(0.08)
    /// The paper edge round a folder's peeks.
    static let peekEdge = Color(light: "FFFFFF", dark: "3A3A3E")
    /// The desk's dots.
    static let grid     = Color(nsColor: .dynamic(
        light: NSColor(hex: "1B1D21").withAlphaComponent(0.10),
        dark: NSColor(hex: "ECECEE").withAlphaComponent(0.10)))
    /// What every shadow is cast in.
    static let shadow   = Color(light: "000000", dark: "000000")
}

/// The one brand hue: a clear blue for what is live — the selection, the
/// active tool, links, the caret, the door's chip.
enum AccentNS {
    static let text = NSColor.dynamic(light: "1E88E5", dark: "4DA3FF")
}

enum Accent {
    static let text = Color(nsColor: AccentNS.text)
    /// The wash under a selected row, a marquee, and behind the door's chip.
    static let wash = Color(nsColor: NSColor.dynamic(
        light: NSColor(hex: "1E88E5").withAlphaComponent(0.12),
        dark: NSColor(hex: "4DA3FF").withAlphaComponent(0.20)))
    /// The tool in hand and the open workspace's mark (revision 30):
    /// Figma's blue square under a white glyph. The light blue in both
    /// appearances, since the dark one's lighter blue leaves a white
    /// glyph under 3:1.
    static let solid = Color(light: "1E88E5", dark: "1E88E5")
    static let onSolid = Color(nsColor: InkNS.inverse)
}

// MARK: - Paper colours

/// OKLCH, converted by hand, so the folder's cardstock ladder from the web
/// original (`oklch(86.5% 0.045 145)` and friends) means the same colour
/// here. Lightness 0–1, chroma about 0–0.3, hue in degrees.
enum OKLCH {
    static func color(l: Double, c: Double, h: Double, alpha: Double = 1) -> Color {
        let (r, g, b) = srgb(l: l, c: c, h: h)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    static func nsColor(l: Double, c: Double, h: Double, alpha: Double = 1) -> NSColor {
        let (r, g, b) = srgb(l: l, c: c, h: h)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    static func srgb(l: Double, c: Double, h: Double) -> (Double, Double, Double) {
        let rad = h * .pi / 180
        let a = c * cos(rad), b = c * sin(rad)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bl = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        return (gamma(r), gamma(g), gamma(bl))
    }

    private static func gamma(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}

/// Heptabase's whiteboard palette, sampled from its screenshots: the solid
/// label and border colour of a section, and the pastel a card is filled
/// with. JSON Canvas colours "1"–"6" are red, orange, yellow, green, cyan,
/// purple; nil is grey.
enum Hepta {
    static func label(_ color: String?) -> Color {
        switch color {
        case "1": return Color(light: "F9786C", dark: "F9786C")
        case "2": return Color(light: "F5A04A", dark: "F5A04A")
        case "3": return Color(light: "F7CF4E", dark: "F7CF4E")
        case "4": return Color(light: "30D667", dark: "30D667")
        case "5": return Color(light: "5BA4DA", dark: "5BA4DA")
        case "6": return Color(light: "B08CF0", dark: "B08CF0")
        default:  return Color(light: "9C9C9C", dark: "8A8A8A")
        }
    }

    /// A card cut from coloured stock.
    static func fill(_ color: String?) -> Color {
        switch color {
        case "1": return Color(light: "F6C8C2", dark: "6A3A36")
        case "2": return Color(light: "F7D0B2", dark: "6B4A2E")
        case "3": return Color(light: "F8E8B0", dark: "6B5E2E")
        case "4": return Color(light: "C9EBCF", dark: "2F5A3A")
        case "5": return Color(light: "BED5E3", dark: "2F4A5A")
        case "6": return Color(light: "DDD2F2", dark: "4A3A6A")
        default:  return Color(light: "FFFFFF", dark: "2A2A2C")
        }
    }

    /// Section fill and border: the label colour over the desk.
    static func sectionFill(_ color: String?) -> Color { label(color).opacity(0.14) }
    static func sectionBorder(_ color: String?) -> Color { label(color).opacity(0.5) }
    /// The label's text: dark on every colour, as Heptabase draws it.
    static let labelText = Color(light: "2E2E2E", dark: "1E1E1E")
}

/// Heptabase's highlighter row: yellow, red, orange, green, blue, purple,
/// pink. Used on PDF highlights and `==marked==` text.
enum Highlight {
    static let names = ["yellow", "red", "orange", "green", "blue", "purple", "pink"]
    static func color(_ name: String) -> Color { Color(nsColor: HighlightNS.color(name)) }
}

enum HighlightNS {
    static let yellow = NSColor(srgbRed: 0.98, green: 0.90, blue: 0.45, alpha: 0.55)
    static func color(_ name: String) -> NSColor {
        switch name {
        case "red": return NSColor(srgbRed: 0.97, green: 0.47, blue: 0.42, alpha: 0.6)
        case "orange": return NSColor(srgbRed: 0.98, green: 0.63, blue: 0.29, alpha: 0.6)
        case "green": return NSColor(srgbRed: 0.19, green: 0.84, blue: 0.40, alpha: 0.55)
        case "blue": return NSColor(srgbRed: 0.36, green: 0.64, blue: 0.85, alpha: 0.6)
        case "purple": return NSColor(srgbRed: 0.69, green: 0.55, blue: 0.94, alpha: 0.6)
        case "pink": return NSColor(srgbRed: 0.95, green: 0.42, blue: 0.71, alpha: 0.6)
        default: return yellow
        }
    }
}

/// The stocks a folder is cut from, by its top-level name (the hues live
/// with `Folders`, which colours a folder's section from the same one).
enum Stock {
    static let hues = Folders.stockHues
    static let chromas: [Double] = [2.2, 1.0, 1.2, 1.2, 1.0, 1.6, 1.0, 1.1]

    /// The same cardstock, inked down to read as a 13pt glyph in the
    /// sidebar: one lightness for white, one for dark, both at 3.9:1 or
    /// better. A folder takes its top-level directory's stock, which is
    /// its section's first colour on Home; a section recoloured there
    /// keeps its stock colour here, where the tree is about where a thing
    /// lives rather than how it was painted.
    static func ink(forPath path: String) -> Color {
        let top = path.split(separator: "/").first.map(String.init) ?? path
        let i = index(for: top)
        // Capped: the cardstock's widest chroma is a gold, and at glyph
        // lightness an uncapped one goes muddy.
        return Color(nsColor: .dynamic(
            light: OKLCH.nsColor(l: 0.58, c: min(0.085 * chromas[i], 0.115), h: hues[i]),
            dark: OKLCH.nsColor(l: 0.80, c: min(0.070 * chromas[i], 0.095), h: hues[i])))
    }

    /// Stable per name, so a directory keeps its colour between launches.
    static func index(for name: String) -> Int { Folders.stockIndex(for: name) }

    /// JSON Canvas preset colours: 1 red, 2 orange, 3 yellow, 4 green,
    /// 5 cyan, 6 purple. A hex colour is honoured as its hue.
    static func hue(forCanvasColor color: String?) -> Double? {
        switch color {
        case "1": return 25
        case "2": return 60
        case "3": return 95
        case "4": return 145
        case "5": return 200
        case "6": return 300
        case let hex? where hex.hasPrefix("#") && hex.count == 7:
            return hueOfHex(String(hex.dropFirst()))
        default: return nil
        }
    }

    private static func hueOfHex(_ hex: String) -> Double? {
        var v: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&v) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        guard mx > mn else { return nil }
        var h: Double
        if mx == r { h = (g - b) / (mx - mn) }
        else if mx == g { h = 2 + (b - r) / (mx - mn) }
        else { h = 4 + (r - g) / (mx - mn) }
        h *= 60
        if h < 0 { h += 360 }
        return h
    }
}
