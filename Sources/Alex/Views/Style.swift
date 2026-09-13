import SwiftUI
import AppKit

// The design tokens. Every colour, size, radius and shadow a view uses comes
// from here; no view invents one inline. The law is Donna's (settled with
// Liam, 2026-08-28), carried over whole, and `run-tests.sh` lints it:
//
// 1. **Two weights.** Regular for reading, Medium for identifying. Semibold
//    and up do not exist, in text or in SF symbols. (Bold typed inside a
//    note is content, not chrome.)
// 2. **No italics** in chrome. Emphasis is ink, not slant.
// 3. **The ink ladder carries hierarchy.** primary = the content; muted =
//    supporting fact; faint = structure whispering; hairline = lines only.
// 4. **Two fills.** `Ink.well` is the one recessed surface; `Ink.wellHover`
//    the hover step. No other primary-opacity fills.
// 5. **Four radii.** mark 5, control 7, well 10, card 16, plus capsules.
// 6. **Labels are sentence case.** No uppercase, anywhere.
// 7. **Focus is visible.** Owned chrome wears a focus ring when tabbed to.
// 8. **The scale is written down.** Text from `Typography`, spacing from
//    `Space`, corners from `Radius`, shadows from `Elevation`. Fixed point
//    sizes are a decision: reading distance is the canvas zoom's job.
//
// Alex adds one thing Donna did not have: paper. Folders and stickies are
// coloured objects on a desk, and their colours come from `OKLCH` so the
// lightness ladder ported from the web original survives the move.

// MARK: - Shape and space

enum Radius {
    static let mark: CGFloat = 4
    static let control: CGFloat = 6
    static let well: CGFloat = 8
    static let card: CGFloat = 8
}

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Typography

enum Typography {
    /// The app's own name and the welcome page.
    static let display = Font.system(size: 34, weight: .medium)
    /// A card's title on the canvas: Heptabase's bold card head, in the
    /// law's heavier weight.
    static let cardTitle = Font.system(size: 15, weight: .medium)
    /// A folder's name on its cover.
    static let folderTitle = Font.system(size: 17, weight: .medium)
    static let figure = Font.system(size: 22, weight: .medium)
    static let title = Font.system(size: 15, weight: .medium)
    static let heading = Font.system(size: 14, weight: .medium)
    static let body = Font.system(size: 13)
    static let prose = Font.system(size: 12.5)
    static let control = Font.system(size: 13, weight: .medium)
    static let meta = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .medium)
    static let micro = Font.system(size: 11, weight: .medium)
    /// The section label pill.
    static let sectionLabel = Font.system(size: 13, weight: .medium)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
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
        shadow(color: .black.opacity(e?.opacity ?? 0),
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
/// SwiftUI colours for everything else. Same ladder, one file.
enum InkNS {
    static let primary  = NSColor.dynamic(light: "2E2E2E", dark: "E6E6E6")
    static let muted    = NSColor.dynamic(light: "6B6B6B", dark: "A6A6A6")
    static let faint = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return dark ? NSColor(hex: "A6A6A6") : NSColor(hex: "6B6B6B")
        }
        return dark ? NSColor(hex: "767676") : NSColor(hex: "9B9B9B")
    }
    static let hairline = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return dark ? NSColor(hex: "4A4A4A") : NSColor(hex: "C8C8C8")
        }
        return dark ? NSColor(hex: "3A3A3C") : NSColor(hex: "E3E3E3")
    }
    /// Edges between cards: Heptabase's near-black arrow ink.
    static let guide = NSColor.dynamic(light: "404140", dark: "B4B4B4")
    static let well = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(hex: "E6E6E6").withAlphaComponent(0.06)
            : NSColor(hex: "2E2E2E").withAlphaComponent(0.05)
    }
    static let wellHover = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(hex: "E6E6E6").withAlphaComponent(0.10)
            : NSColor(hex: "2E2E2E").withAlphaComponent(0.08)
    }
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
    /// A card's paper.
    static let card     = Color(light: "FFFFFF", dark: "2A2A2C")
    /// The desk every canvas sits on: Heptabase's whiteboard grey.
    static let ground   = Color(light: "EDECEC", dark: "1C1C1E")
    /// Chrome that floats over the desk: the tool palette, the zoom bar.
    static let float    = Color(light: "FFFFFF", dark: "2C2C2E")
    /// Icon ink in the chrome.
    static let icon     = Color(light: "3C3C3C", dark: "D0D0D0")
}

/// The one brand hue: selection, the active tool, links, the caret.
enum AccentNS {
    static let text = NSColor.dynamic(light: "207DFF", dark: "4C9AFF")
}

enum Accent {
    static let text = Color(nsColor: AccentNS.text)
    static let wash = Color(nsColor: NSColor.dynamic(
        light: NSColor(hex: "207DFF").withAlphaComponent(0.10),
        dark: NSColor(hex: "4C9AFF").withAlphaComponent(0.16)))
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

/// The stocks a folder can be cut from; a directory with no colour of its
/// own takes one by name.
enum Stock {
    static let hues: [Double] = [95, 145, 240, 25, 300, 60, 190, 350]
    static let chromas: [Double] = [2.2, 1.0, 1.2, 1.2, 1.0, 1.6, 1.0, 1.1]

    /// Stable per name, so a directory keeps its colour between launches.
    static func index(for name: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return Int(hash % UInt32(hues.count))
    }

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
