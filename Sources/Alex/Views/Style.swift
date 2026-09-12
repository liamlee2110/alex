import SwiftUI

// The design tokens. Every colour, size and radius a view uses comes from
// here; no view invents one inline. The law is Donna's (settled with Liam,
// 2026-08-28), carried over whole, and `run-tests.sh` lints it:
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
//    `Space`, corners from `Radius`. Fixed point sizes are a decision.

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
    static let l: CGFloat = 20
    static let xl: CGFloat = 32
}

enum Ink {
    static let primary = Color.primary
    static let muted = Color.primary.opacity(0.62)
    static let faint = Color.primary.opacity(0.38)
    static let hairline = Color.primary.opacity(0.12)
    static let well = Color.primary.opacity(0.05)
    static let wellHover = Color.primary.opacity(0.09)
}

enum Typography {
    /// The app's own name and canvas-level titles: the system serif.
    static let display = Font.system(size: 34, weight: .regular, design: .serif)
    static let title = Font.system(size: 17, weight: .medium)
    static let body = Font.system(size: 13, weight: .regular)
    static let label = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
}
