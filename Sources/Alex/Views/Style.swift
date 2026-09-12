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
    static let mark: CGFloat = 5
    static let control: CGFloat = 7
    static let well: CGFloat = 10
    static let card: CGFloat = 16
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
    /// The app's own name and the welcome page: the system serif.
    static let display = Font.system(size: 34, weight: .regular, design: .serif)
    /// A card's or folder's title on the canvas.
    static let cardTitle = Font.system(size: 19, weight: .regular, design: .serif)
    static let figure = Font.system(size: 22, weight: .medium)
    static let title = Font.system(size: 17, weight: .medium)
    static let heading = Font.system(size: 14, weight: .medium)
    static let body = Font.system(size: 13)
    static let prose = Font.system(size: 12.5)
    static let control = Font.system(size: 12, weight: .medium)
    static let meta = Font.system(size: 11)
    static let label = Font.system(size: 11, weight: .medium)
    static let micro = Font.system(size: 10.5, weight: .medium)
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

    /// A card resting on the desk.
    static let card = Elevation(opacity: 0.07, radius: 10, y: 2)
    /// Small raised pieces: pills, floating panels, peeks.
    static let raised = Elevation(opacity: 0.08, radius: 4, y: 1)
    static let knob = Elevation(opacity: 0.12, radius: 1.5, y: 0.5)
    /// The folder's back panel.
    static let folder = Elevation(opacity: 0.10, radius: 9, y: 4)
    /// Anything under the pointer or being dragged.
    static let lifted = Elevation(opacity: 0.16, radius: 18, y: 8)
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
    static let primary  = NSColor.dynamic(light: "1F2328", dark: "E8EAED")
    static let muted    = NSColor.dynamic(light: "5F6B76", dark: "9BA5AE")
    static let faint = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return dark ? NSColor(hex: "9BA5AE") : NSColor(hex: "5F6B76")
        }
        return dark ? NSColor(hex: "6B757E") : NSColor(hex: "98A3AC")
    }
    static let hairline = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return dark ? NSColor(hex: "3A434B") : NSColor(hex: "C9D1D8")
        }
        return dark ? NSColor(hex: "2B3238") : NSColor(hex: "E3E8EC")
    }
    static let guide = NSColor.dynamic(light: "C9D1D8", dark: "3A434B")
    static let well = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(hex: "E8EAED").withAlphaComponent(0.05)
            : NSColor(hex: "1F2328").withAlphaComponent(0.045)
    }
    static let wellHover = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(hex: "E8EAED").withAlphaComponent(0.09)
            : NSColor(hex: "1F2328").withAlphaComponent(0.08)
    }
}

enum Ink {
    static let primary  = Color(nsColor: InkNS.primary)
    static let muted    = Color(nsColor: InkNS.muted)
    static let faint    = Color(nsColor: InkNS.faint)
    static let hairline = Color(nsColor: InkNS.hairline)
    /// Edges between cards and the rail beside a quote: a step past
    /// hairline, opaque, because a 1pt line carries structure.
    static let guide    = Color(nsColor: InkNS.guide)
    static let well     = Color(nsColor: InkNS.well)
    static let wellHover = Color(nsColor: InkNS.wellHover)
    /// A card's paper.
    static let card     = Color(light: "FFFFFF", dark: "26282B")
    /// The desk every canvas sits on.
    static let ground   = Color(light: "F4F1EA", dark: "18191B")
    /// Chrome that floats over the desk: breadcrumb, zoom pills.
    static let float    = Color(light: "FFFFFF", dark: "2C2E31")
}

/// The one brand hue: selection, links, the caret, focus.
enum AccentNS {
    static let text = NSColor.dynamic(light: "0F6CBD", dark: "6FB6FF")
}

enum Accent {
    static let text = Color(nsColor: AccentNS.text)
    static let wash = Color(nsColor: NSColor.dynamic(
        light: NSColor(hex: "0F6CBD").withAlphaComponent(0.10),
        dark: NSColor(hex: "6FB6FF").withAlphaComponent(0.16)))
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

/// The stocks a folder or sticky can be cut from. JSON Canvas colours "1"–"6"
/// map onto these; a directory with no colour of its own takes one by name.
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
