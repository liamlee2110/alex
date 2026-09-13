import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The card editor: Markdown on disk, the rendered note on screen. Ported
// whole from Donna (github.com/liamlee2110/donna, Views/MarkdownEditor.swift)
// with one change: images are files beside the note, referenced relative to
// it, the way Obsidian and GitHub read them.
//
// Storage never changes shape — the file stays plain Markdown, so git diffs
// stay readable and every other tool can still open it. The editor keeps that source in its text storage character for
// character and draws it rendered (settled 2026-09-11): block syntax — `#`,
// `-`, `- [ ]`, `>`, `---`, ``` — is never shown. A heading is just large, a
// typed hyphen is a dot, a `[ ]` is a box you can tick. Inline marks
// (`**`, `*`, `__`, backticks) stay hidden until the caret touches their
// span, then show faint so they can be edited. Hiding is a glyph property,
// not a transformation: what's stored is still exactly what was typed, in
// the same place, which is what keeps undo, selection and serialization
// trivial. Pasted images are the one exception: they live as PNG files next
// to the store and ride the markdown as `![image](name)`, shown inline as
// the actual picture.
//
// Formatting: ⌘B / ⌘I / ⌘U wrap the selection; "/" at the start of an empty
// line opens the block menu; ⌘V with an image on the pasteboard files it.
// ⏎ inside a list carries the marker down to the next line; ⇥ and ⇧⇥ move an
// item in and out a level, one tab each, and the dot changes with the depth.
// ⏎ on an empty item climbs out, then clears the marker at the top. ⌫ at the
// start of a block's words does the same: out a level, then the marker goes
// and the words stay.

// MARK: - Image store

/// Images ride the markdown as `![alt](path)` with the path relative to the
/// note's own directory. A pasted image is written beside the note as PNG;
/// nothing is ever deleted when a reference goes — orphans are cheap and
/// lost context is not.
enum NoteImages {
    static func load(_ ref: String, base: URL?) -> NSImage? {
        guard let base, !ref.contains("://") else { return nil }
        let clean = ref.removingPercentEncoding ?? ref
        return NSImage(contentsOf: base.appendingPathComponent(clean))
    }

    static func save(_ image: NSImage, base: URL?, stem: String) -> String? {
        guard let base,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let name = "\(stem)-\(String(UUID().uuidString.prefix(6)).lowercased()).png"
        guard (try? png.write(to: base.appendingPathComponent(name))) != nil else { return nil }
        return name
    }
}

/// An inline image that remembers which file it is, so the attachment can be
/// serialized back to `![image](name)` losslessly.
final class NoteImageAttachment: NSTextAttachment {
    var filename = ""
}

// MARK: - Markdown <-> storage

/// The editor's text storage matches the markdown character for character,
/// except image references, which become one attachment character each.
/// That one-to-one mapping is what keeps serialization trivial and undo sane.
enum NoteMarkdown {
    static let imagePattern = try! NSRegularExpression(
        pattern: #"!\[[^\]\n]*\]\(([^)\s\n]+)\)"#)

    static func attributed(from markdown: String, width: CGFloat, base: URL?) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let ns = markdown as NSString
        var cursor = 0
        for m in imagePattern.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            // Only a reference that resolves to a real local file collapses
            // into a picture; anything else stays literal text.
            guard let image = NoteImages.load(name, base: base) else { continue }
            out.append(NSAttributedString(string: ns.substring(
                with: NSRange(location: cursor, length: m.range.location - cursor))))
            out.append(attachment(named: name, image: image, width: width))
            cursor = m.range.location + m.range.length
        }
        out.append(NSAttributedString(string: ns.substring(from: cursor)))
        return out
    }

    static func markdown(from storage: NSAttributedString) -> String {
        var out = ""
        let ns = storage.string as NSString
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ns.length)) {
            value, range, _ in
            if let att = value as? NoteImageAttachment {
                out += "![image](\(att.filename))"
            } else {
                out += ns.substring(with: range)
            }
        }
        return out
    }

    static func attachment(named name: String, image: NSImage,
                           width: CGFloat) -> NSAttributedString {
        let att = NoteImageAttachment()
        att.filename = name
        att.image = image
        let maxW = max(120, min(width, 420))
        let size = image.size
        let scale = size.width > maxW ? maxW / size.width : 1
        att.bounds = CGRect(x: 0, y: 0, width: size.width * scale,
                            height: size.height * scale)
        return NSAttributedString(attachment: att)
    }
}

// MARK: - Nesting

/// One level of nesting is one tab. A renderer nests it correctly, the depth
/// is a character count rather than a guess about how wide a space is, and
/// how far a level moves on screen is the paragraph style's business.
fileprivate enum ListIndent {
    static let unit = "\t"
    /// The width to move a line by, in points — a tab stop, not a space count.
    static let step: CGFloat = 18

    /// Tabs count as four columns, which is what a Markdown reader does with
    /// them; spaces typed by hand therefore nest too.
    static func depth(of indent: String) -> Int {
        indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 4
    }
}

// MARK: - Styling

extension NSAttributedString.Key {
    /// The nesting depth of a plain bullet, set on the one character it was
    /// typed as. The layout manager draws the dot for that depth in its
    /// place; the storage keeps the hyphen.
    static let noteBullet = NSAttributedString.Key("alex.noteBullet")
    /// Syntax drawn as nothing — a null glyph, zero width, still in the file.
    static let noteHidden = NSAttributedString.Key("alex.noteHidden")
    /// The inline span (marks included) a hidden mark belongs to, as an
    /// `NSValue` range. The view shows the marks of whichever spans the
    /// caret is touching; every other span keeps them hidden.
    static let noteSpan = NSAttributedString.Key("alex.noteSpan")
    /// A line's block syntax — the marker and the space after it, indent
    /// excluded. The caret never rests inside one; ⌫ at its end removes it.
    static let noteMarker = NSAttributedString.Key("alex.noteMarker")
    /// The `[ ]` of a checklist item, with whether it's ticked. Laid out as
    /// one fixed slot and drawn as a box by the layout manager.
    static let noteCheckbox = NSAttributedString.Key("alex.noteCheckbox")
    /// A paragraph with something drawn behind it: the quote's rail, the
    /// rule's line, the code block's well. Value is a `NoteDecoration`.
    static let noteBlock = NSAttributedString.Key("alex.noteBlock")
    /// A `[[name]]` link's target, on the name's characters.
    static let noteLink = NSAttributedString.Key("alex.noteLink")
}

enum NoteDecoration: Int {
    case quote = 1, rule, code
}

/// The box where a `[ ]` is — Linear's checklist control, redrawn from
/// Donna's ink (Liam's call, 2026-09-12): a 14pt rounded square with a
/// 1pt edge, filled with the brand hue and ticked in white once checked.
/// A square, not the row's circle, because the circle is a task's status
/// and this is an item inside one: the same shape would promise the same
/// clock, record and price, and a checklist line carries none of them.
enum NoteCheckbox {
    static let side: CGFloat = 14
    /// Linear's corner at Linear's size (4 on 14). Below the radius scale's
    /// floor on purpose: `Radius.mark` is for halos, and a 5pt corner on a
    /// 14pt box reads as a pill.
    static let corner: CGFloat = 4
    /// The width the `[ ]` lays out at: the box plus the gap before the words.
    static let slot: CGFloat = side + 5

    /// Drawn on the pixel grid — the edge is a single hairline, so a
    /// half-point offset would smear it across two.
    static func draw(checked: Bool, in box: NSRect) {
        let rect = NSRect(x: box.minX.rounded(), y: box.minY.rounded(),
                          width: side, height: side)
        if checked {
            AccentNS.text.setFill()
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            let tick = NSBezierPath()
            tick.lineWidth = 1.75
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            tick.move(to: NSPoint(x: rect.minX + 3.5, y: rect.midY + 0.25))
            tick.line(to: NSPoint(x: rect.minX + 6, y: rect.midY + 2.75))
            tick.line(to: NSPoint(x: rect.maxX - 3.5, y: rect.midY - 2.5))
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            InkNS.guide.setStroke()
            let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: corner - 0.5, yRadius: corner - 0.5)
            edge.lineWidth = 1
            edge.stroke()
        }
    }
}

/// One pass over the whole note per edit: cheap at note scale, and stateless —
/// every attribute is derived from the text, never accumulated. The pass only
/// says what each character *is*; whether it's drawn is the view's call.
private enum NoteStyle {
    static let baseSize: CGFloat = 14.5
    static let headingSizes: [CGFloat] = [24, 19, 16]
    /// A fence line is hidden, and shrunk so its height is the well's
    /// padding rather than a blank row inside the block.
    static let fenceSize: CGFloat = 8
    static let quoteIndent: CGFloat = 14
    static let codeIndent: CGFloat = 10

    static let heading = try! NSRegularExpression(pattern: #"^(#{1,3})[ \t]"#)
    static let bullet  = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+])[ \t](\[[ xX]\][ \t])?"#)
    static let ordered = try! NSRegularExpression(pattern: #"^([ \t]*)(\d+\.[ \t])"#)
    static let quote   = try! NSRegularExpression(pattern: #"^>[ \t]?"#)
    static let rule    = try! NSRegularExpression(pattern: #"^[ \t]*(-{3,}|\*{3,})[ \t]*$"#)
    static let fence   = try! NSRegularExpression(pattern: #"^```"#)
    static let code    = try! NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    static let wiki    = try! NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
    static let marked  = try! NSRegularExpression(pattern: #"==([^=\n]+)==(?!=)"#)
    static let bold    = try! NSRegularExpression(pattern: #"\*\*([^*\n]+?)\*\*"#)
    static let under   = try! NSRegularExpression(pattern: #"__([^_\n]+?)__"#)
    static let italicA = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#)
    static let italicB = try! NSRegularExpression(pattern: #"(?<!_)_([^_\n]+?)_(?!_)"#)

    static let ownKeys: [NSAttributedString.Key] = [
        .noteBullet, .noteHidden, .noteSpan, .noteMarker, .noteCheckbox, .noteBlock, .noteLink,
    ]

    static func apply(to storage: NSTextStorage) {
        let all = NSRange(location: 0, length: storage.length)
        let text = storage.string as NSString

        storage.beginEditing()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 6
        // Every tab is one level of nesting, so every tab stop is one step.
        paragraph.tabStops = []
        paragraph.defaultTabInterval = ListIndent.step
        // Reset by key, never by replacing the whole attribute dictionary —
        // image attachments live in that dictionary and must survive the pass.
        storage.removeAttribute(.underlineStyle, range: all)
        storage.removeAttribute(.backgroundColor, range: all)
        for key in ownKeys { storage.removeAttribute(key, range: all) }
        storage.addAttributes([
            .font: NSFont.systemFont(ofSize: baseSize),
            .foregroundColor: InkNS.primary,
            .paragraphStyle: paragraph,
        ], range: all)

        var inFence = false
        // `lineRange` stops before the newline; `enclosing` takes it, which
        // is what lets a block's paragraphs coalesce into one decoration run.
        text.enumerateSubstrings(in: all, options: [.byLines, .substringNotRequired]) {
            _, lineRange, enclosing, _ in
            let line = text.substring(with: lineRange)
            let whole = NSRange(location: 0, length: (line as NSString).length)
            func at(_ r: NSRange) -> NSRange {
                NSRange(location: lineRange.location + r.location, length: r.length)
            }

            if fence.firstMatch(in: line, range: whole) != nil {
                hide(storage, lineRange, marker: true)
                // The closing fence carries the gap to the next paragraph;
                // inside the well the lines sit tight.
                let edge = paragraph.mutableCopy() as! NSMutableParagraphStyle
                edge.lineSpacing = 0
                edge.paragraphSpacing = inFence ? paragraph.paragraphSpacing : 0
                storage.addAttributes([
                    .font: NSFont.systemFont(ofSize: fenceSize),
                    .paragraphStyle: edge,
                    .noteBlock: NoteDecoration.code.rawValue,
                ], range: enclosing)
                inFence.toggle()
                return
            }
            if inFence {
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: InkNS.muted,
                ], range: lineRange)
                let inset = indented(paragraph, by: codeIndent).mutableCopy() as! NSMutableParagraphStyle
                inset.paragraphSpacing = 0
                storage.addAttributes([
                    .paragraphStyle: inset,
                    .noteBlock: NoteDecoration.code.rawValue,
                ], range: enclosing)
                return
            }

            if let m = heading.firstMatch(in: line, range: whole) {
                let level = m.range(at: 1).length
                storage.addAttribute(.font,
                    value: NSFont.systemFont(ofSize: headingSizes[level - 1], weight: .medium),
                    range: lineRange)
                hide(storage, at(m.range), marker: true)
            } else if rule.firstMatch(in: line, range: whole) != nil {
                hide(storage, lineRange, marker: true)
                storage.addAttribute(.noteBlock, value: NoteDecoration.rule.rawValue,
                                     range: enclosing)
            } else if let m = quote.firstMatch(in: line, range: whole) {
                storage.addAttribute(.foregroundColor, value: InkNS.muted, range: lineRange)
                storage.addAttribute(.font,
                    value: italic(NSFont.systemFont(ofSize: baseSize)), range: lineRange)
                hide(storage, at(m.range), marker: true)
                storage.addAttributes([
                    .paragraphStyle: indented(paragraph, by: quoteIndent),
                    .noteBlock: NoteDecoration.quote.rawValue,
                ], range: enclosing)
            } else if let m = bullet.firstMatch(in: line, range: whole) {
                let dash = m.range(at: 2)
                let marker = NSRange(location: dash.location,
                                     length: m.range.length - dash.location)
                storage.addAttributes([.noteMarker: true, .foregroundColor: InkNS.faint],
                                      range: at(marker))
                let box = m.range(at: 3)
                if box.location == NSNotFound {
                    // A plain bullet is drawn as a dot instead of the hyphen
                    // that was typed; the layout manager swaps the glyph.
                    let depth = ListIndent.depth(of: (line as NSString)
                        .substring(with: m.range(at: 1)))
                    storage.addAttributes([.noteBullet: depth,
                                           .foregroundColor: InkNS.muted],
                                          range: at(NSRange(location: dash.location, length: 1)))
                } else {
                    // A checklist item: the hyphen and both spaces vanish,
                    // the `[ ]` lays out as the box's slot, and a ticked
                    // line's words step back to muted — done, not struck.
                    hide(storage, at(NSRange(location: dash.location,
                                             length: box.location - dash.location)))
                    let checked = (line as NSString).character(at: box.location + 1) != 0x20
                    storage.addAttribute(.noteCheckbox, value: checked,
                                         range: at(NSRange(location: box.location, length: 3)))
                    hide(storage, at(NSRange(location: box.location + 3,
                                             length: box.length - 3)))
                    if checked {
                        storage.addAttribute(.foregroundColor, value: InkNS.muted,
                            range: at(NSRange(location: m.range.length,
                                              length: whole.length - m.range.length)))
                    }
                }
            } else if let m = ordered.firstMatch(in: line, range: whole) {
                // The number is already what a reader sees; it stays, in the
                // dot's ink rather than a mark's.
                storage.addAttributes([.noteMarker: true, .foregroundColor: InkNS.muted],
                                      range: at(m.range(at: 2)))
            }

            inline(storage, line: line, at: lineRange.location)
        }
        storage.endEditing()
    }

    /// Syntax that is never drawn. Faint as well, for the one case it does
    /// show: an inline mark whose span the caret is touching.
    private static func hide(_ storage: NSTextStorage, _ range: NSRange, marker: Bool = false) {
        var attrs: [NSAttributedString.Key: Any] = [.noteHidden: true,
                                                    .foregroundColor: InkNS.faint]
        if marker { attrs[.noteMarker] = true }
        storage.addAttributes(attrs, range: range)
    }

    private static func indented(_ base: NSParagraphStyle, by points: CGFloat) -> NSParagraphStyle {
        let p = base.mutableCopy() as! NSMutableParagraphStyle
        p.firstLineHeadIndent = points
        p.headIndent = points
        return p
    }

    /// Inline spans, one line at a time, code first so nothing styles inside
    /// backticks. Each span's marks are hidden and the span is recorded, so
    /// the view can show the marks of the one the caret is in.
    private static func inline(_ storage: NSTextStorage, line: String, at offset: Int) {
        let whole = NSRange(location: 0, length: (line as NSString).length)
        var taken: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }
        func span(_ m: NSTextCheckingResult, marks width: Int) {
            let s = shift(m.range)
            storage.addAttribute(.noteSpan, value: NSValue(range: s), range: s)
            hide(storage, NSRange(location: s.location, length: width))
            hide(storage, NSRange(location: NSMaxRange(s) - width, length: width))
        }

        for m in code.matches(in: line, range: whole) {
            taken.append(m.range)
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .backgroundColor: InkNS.hairline.withAlphaComponent(0.55),
            ], range: shift(m.range))
            span(m, marks: 1)
        }
        // `[[name]]`: the name in the accent, the brackets hidden, the
        // target on the characters so a click can follow it.
        for m in wiki.matches(in: line, range: whole) where free(m.range) {
            taken.append(m.range)
            let name = (line as NSString).substring(with: m.range(at: 1))
            storage.addAttributes([
                .foregroundColor: AccentNS.text,
                .noteLink: name,
            ], range: shift(m.range(at: 1)))
            span(m, marks: 2)
        }
        // `==text==`: Heptabase's highlight, a yellow wash.
        for m in marked.matches(in: line, range: whole) where free(m.range) {
            taken.append(m.range)
            storage.addAttribute(.backgroundColor, value: HighlightNS.yellow, range: shift(m.range(at: 1)))
            span(m, marks: 2)
        }
        for m in bold.matches(in: line, range: whole) where free(m.range) {
            taken.append(m.range)
            retrait(storage, shift(m.range(at: 1)), trait: .boldFontMask)
            span(m, marks: 2)
        }
        for m in under.matches(in: line, range: whole) where free(m.range) {
            taken.append(m.range)
            storage.addAttribute(.underlineStyle,
                value: NSUnderlineStyle.single.rawValue, range: shift(m.range(at: 1)))
            span(m, marks: 2)
        }
        for rx in [italicA, italicB] {
            for m in rx.matches(in: line, range: whole) where free(m.range) {
                taken.append(m.range)
                retrait(storage, shift(m.range(at: 1)), trait: .italicFontMask)
                span(m, marks: 1)
            }
        }
    }

    private static func retrait(_ storage: NSTextStorage, _ range: NSRange,
                                trait: NSFontTraitMask) {
        storage.enumerateAttribute(.font, in: range) { value, r, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font,
                value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: r)
        }
    }

    private static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
}

// MARK: - Layout manager

/// Draws what the syntax means: a box where a `[ ]` is, a rail beside a
/// quote, a hairline for `---`, a well behind a code block. Attributes say
/// where; nothing here reads the text itself.
final class NoteLayoutManager: NSLayoutManager {
    struct Box {
        let range: NSRange
        let checked: Bool
        /// The slot the `[ ]` lays out in, container coordinates — the
        /// click target, not just the box.
        let slot: NSRect
        let baseline: CGFloat
    }

    /// Every checklist box, or those touching `chars`. Needs layout.
    func checkboxes(in chars: NSRange? = nil) -> [Box] {
        guard let storage = textStorage else { return [] }
        let all = NSRange(location: 0, length: storage.length)
        var out: [Box] = []
        storage.enumerateAttribute(.noteCheckbox, in: chars ?? all) { value, hit, _ in
            guard let checked = value as? Bool else { return }
            // A partial redraw can hand back half a box; measure the whole.
            var range = NSRange()
            _ = storage.attribute(.noteCheckbox, at: hit.location,
                                  longestEffectiveRange: &range, in: all)
            guard !out.contains(where: { NSEqualRanges($0.range, range) }) else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let frag = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let loc = location(forGlyphAt: glyphs.location)
            out.append(Box(range: range, checked: checked,
                           slot: NSRect(x: frag.minX + loc.x, y: frag.minY,
                                        width: NoteCheckbox.slot, height: frag.height),
                           baseline: frag.minY + loc.y))
        }
        return out
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for box in checkboxes(in: chars) {
            guard let font = storage.attribute(.font, at: box.range.location,
                                               effectiveRange: nil) as? NSFont
            else { continue }
            // Centred on the cap height, like a symbol beside a word. In a
            // flipped view "up" is smaller y, so the middle sits above the
            // baseline by half a cap.
            let mid = box.baseline - font.capHeight / 2
            NoteCheckbox.draw(checked: box.checked, in: NSRect(
                x: box.slot.minX + origin.x,
                y: mid - NoteCheckbox.side / 2 + origin.y,
                width: NoteCheckbox.side, height: NoteCheckbox.side))
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var drawn: [NSRange] = []
        storage.enumerateAttribute(.noteBlock, in: chars) { value, hit, _ in
            guard let raw = value as? Int, let kind = NoteDecoration(rawValue: raw) else { return }
            // The whole block, not just the part being redrawn, so a well
            // keeps its corners and a rail its ends.
            var run = NSRange()
            _ = storage.attribute(.noteBlock, at: hit.location,
                                  longestEffectiveRange: &run, in: all)
            guard !drawn.contains(where: { NSEqualRanges($0, run) }) else { return }
            drawn.append(run)
            let glyphs = glyphRange(forCharacterRange: run, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            // Fragment rects run the container's width; used rects say how
            // tall the lines really are, without the paragraph gap after.
            var wide = NSRect.null, tall = NSRect.null
            enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, _, _ in
                wide = wide.union(rect)
                tall = tall.union(used)
            }
            guard !wide.isNull, !tall.isNull else { return }
            let rect = NSRect(x: wide.minX + origin.x, y: tall.minY + origin.y,
                              width: wide.width, height: tall.height)
            switch kind {
            case .quote:
                InkNS.guide.setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 2, y: rect.minY + 1,
                                                 width: 2, height: rect.height - 2),
                             xRadius: 1, yRadius: 1).fill()
            case .rule:
                InkNS.hairline.setFill()
                NSRect(x: rect.minX, y: (rect.midY - 0.5).rounded(),
                       width: rect.width, height: 1).fill()
            case .code:
                InkNS.well.setFill()
                NSBezierPath(roundedRect: rect, xRadius: Radius.control,
                             yRadius: Radius.control).fill()
            }
        }
    }
}

// MARK: - Text view

final class MarkdownTextView: NSTextView, NSLayoutManagerDelegate {
    /// Grows with its content so the page scrolls as one document — no boxed
    /// inner scrollbar unless the host asks for one.
    var growsWithContent = true
    /// Where `![alt](path)` resolves and where pasted images are written:
    /// the note's own directory.
    var imageBase: URL?
    /// The note's file name without extension; pasted images are named after it.
    var imageStem = "image"

    /// The inline spans whose marks are showing: the ones the caret touches.
    private(set) var revealed: [NSRange] = []
    /// True while a click is placing the caret, so a press inside a hidden
    /// marker parks the caret after it instead of reading as a step left.
    private var pointerSelecting = false
    private var hoverArea: NSTrackingArea?

    /// TextKit 1, assembled by hand. Drawing a typed "-" as a bullet, hiding
    /// a "#" and giving a "[ ]" a fixed width are all glyph-level decisions,
    /// which only the old layout manager asks about — and `NSTextView()`
    /// left to itself now picks TextKit 2, where the callbacks never come
    /// and the syntax stays on screen.
    static func make() -> MarkdownTextView {
        let storage = NSTextStorage()
        let layout = NoteLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        // The page's margin is the page's; the text starts at zero.
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = MarkdownTextView(frame: .zero, textContainer: container)
        view.textContainerInset = .zero
        layout.delegate = view
        return view
    }

    // MARK: Glyphs

    /// Where the rendering happens, and why nothing downstream can tell: a
    /// hidden mark becomes a control glyph the delegate below lays out at no
    /// width, the dash keeps its place and its width and only its glyph
    /// changes, the "[" of a checkbox becomes a control glyph with the slot's
    /// width. Selection, undo, serialization all still see what was typed.
    ///
    /// Control glyphs, not null ones: a null glyph is skipped by layout and
    /// so lands in whichever line fragment came before — a hidden "#" at a
    /// paragraph's start would ride the line above, taking the paragraph
    /// spacing with it. A zero-advance control glyph is laid out where it is.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>,
                       font: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = textStorage else { return 0 }
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var newProps = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        var changed = false
        var dots: [Int: CGGlyph] = [:]
        for i in 0 ..< glyphRange.length {
            let c = characterIndexes[i]
            guard c < storage.length else { continue }
            let attrs = storage.attributes(at: c, effectiveRange: nil)
            if let depth = attrs[.noteBullet] as? Int {
                guard let dot = dots[depth % 2] ?? MarkdownTextView.dot(atDepth: depth, in: font)
                else { continue }
                dots[depth % 2] = dot
                newGlyphs[i] = dot
                changed = true
            } else if attrs[.noteCheckbox] != nil {
                newProps[i] = .controlCharacter
                changed = true
            } else if attrs[.noteHidden] != nil {
                if let span = attrs[.noteSpan] as? NSValue,
                   revealed.contains(where: { NSEqualRanges($0, span.rangeValue) }) {
                    continue
                }
                newProps[i] = .controlCharacter
                changed = true
            }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(&newGlyphs, properties: &newProps,
                                characterIndexes: characterIndexes, font: font,
                                forGlyphRange: glyphRange)
        return glyphRange.length
    }

    /// The checkbox's "[" is laid out as whitespace of a fixed width — the
    /// slot the box is drawn in — rather than as the bracket it is. Every
    /// other hidden character advances by nothing.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = textStorage, charIndex < storage.length else { return action }
        let attrs = storage.attributes(at: charIndex, effectiveRange: nil)
        if attrs[.noteCheckbox] != nil {
            return (storage.string as NSString).character(at: charIndex) == 0x5B
                ? .whitespace : .zeroAdvancement
        }
        if attrs[.noteHidden] != nil { return .zeroAdvancement }
        return action
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       boundingBoxForControlGlyphAt glyphIndex: Int,
                       for textContainer: NSTextContainer,
                       proposedLineFragment proposedRect: NSRect,
                       glyphPosition: NSPoint,
                       characterIndex charIndex: Int) -> NSRect {
        // Only the "[" is ever whitespace; nothing else asks for a box.
        NSRect(x: glyphPosition.x, y: proposedRect.minY,
               width: NoteCheckbox.slot, height: proposedRect.height)
    }

    /// Filled at the top level, hollow one level in, and alternating from
    /// there — depth you can see without counting indents. A font missing the
    /// character keeps its hyphen rather than drawing a blank.
    private static func dot(atDepth depth: Int, in font: NSFont) -> CGGlyph? {
        var chars = Array((depth % 2 == 0 ? "\u{2022}" : "\u{25E6}").utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count),
              let dot = glyphs.first, dot != 0 else { return nil }
        return dot
    }

    /// After the style pass: every attribute it sets can change what a glyph
    /// is or whether it's drawn, so the lot is regenerated. Cheap at note
    /// scale, and it settles which attribute edits TextKit would regenerate
    /// for on its own, which is not written down anywhere.
    func noteDidRestyle() {
        guard let lm = layoutManager, let storage = textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        revealed = spansTouchingSelection()
        lm.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
        lm.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    // MARK: Reveal

    /// A caret inside or right beside a bold word opens its marks; step away
    /// and they close. Only the spans that changed state are regenerated.
    private func updateReveal() {
        guard let lm = layoutManager, let storage = textStorage else { return }
        let now = spansTouchingSelection()
        guard now != revealed else { return }
        let all = NSRange(location: 0, length: storage.length)
        let stale = revealed
        revealed = now
        for r in stale + now {
            let clipped = NSIntersectionRange(r, all)
            guard clipped.length > 0 else { continue }
            lm.invalidateGlyphs(forCharacterRange: clipped, changeInLength: 0,
                                actualCharacterRange: nil)
            lm.invalidateLayout(forCharacterRange: clipped, actualCharacterRange: nil)
        }
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func spansTouchingSelection() -> [NSRange] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        let sel = selectedRange()
        let lo = max(0, sel.location - 1)
        let hi = min(storage.length, NSMaxRange(sel) + 1)
        guard hi > lo else { return [] }
        var spans: [NSRange] = []
        storage.enumerateAttribute(.noteSpan, in: NSRange(location: lo, length: hi - lo)) {
            value, _, _ in
            if let v = value as? NSValue { spans.append(v.rangeValue) }
        }
        return spans
    }

    // MARK: Markers

    /// The block syntax at the head of the line `index` is on — indent
    /// excluded — or nil for a plain line.
    func blockMarker(containing index: Int) -> NSRange? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let ns = storage.string as NSString
        let line = ns.lineRange(for: NSRange(location: min(index, ns.length), length: 0))
        var i = line.location
        while i < NSMaxRange(line),
              storage.attribute(.noteMarker, at: i, effectiveRange: nil) == nil {
            let ch = ns.character(at: i)
            guard ch == 0x20 || ch == 0x09 else { return nil }
            i += 1
        }
        guard i < NSMaxRange(line) else { return nil }
        var marker = NSRange()
        _ = storage.attribute(.noteMarker, at: i, longestEffectiveRange: &marker, in: line)
        return marker
    }

    /// Every selection change comes through here. A caret can't rest inside
    /// a marker that isn't drawn — it would type into syntax it can't see —
    /// so it lands after the marker; and a step left from there leaves the
    /// line, since there is nothing between the words and the line before.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity,
                                    stillSelecting: Bool) {
        var ranges = ranges
        if ranges.count == 1, let r = ranges.first?.rangeValue, r.length == 0,
           let marker = blockMarker(containing: r.location),
           r.location >= marker.location, r.location < NSMaxRange(marker) {
            let was = selectedRange()
            let end = NSMaxRange(marker)
            let leaving = !pointerSelecting && was.length == 0 && was.location == end
                && marker.location > 0
            let target = leaving ? marker.location - 1 : end
            ranges = [NSValue(range: NSRange(location: target, length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        updateReveal()
    }

    /// ⌫ at the start of a block's words: a nested item climbs a level, like
    /// ⏎ on an empty one; anything else drops its marker and keeps the words.
    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, let marker = blockMarker(containing: sel.location),
           NSMaxRange(marker) == sel.location {
            let ns = string as NSString
            let line = ns.substring(with: ns.lineRange(for: sel))
            if let item = ListItem(line: line), ListIndent.depth(of: item.indent) > 0 {
                shiftLevel(by: -1)
                return
            }
            replace(marker, with: "")
            setSelectedRange(NSRange(location: marker.location, length: 0))
            return
        }
        super.deleteBackward(sender)
    }

    // MARK: Checkboxes

    struct CheckboxHit {
        let range: NSRange
        let checked: Bool
        let hit: NSRect
    }

    /// Every box on the page with its click target, view coordinates.
    func checkboxHits() -> [CheckboxHit] {
        guard let lm = layoutManager as? NoteLayoutManager, let tc = textContainer
        else { return [] }
        lm.ensureLayout(for: tc)
        let origin = textContainerOrigin
        return lm.checkboxes().map {
            CheckboxHit(range: $0.range, checked: $0.checked,
                        hit: $0.slot.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    /// Ticks or unticks by rewriting the one character inside the brackets —
    /// through the undo stack, like any other edit.
    func toggleCheckbox(_ range: NSRange) {
        guard let storage = textStorage, range.location < storage.length,
              let checked = storage.attribute(.noteCheckbox, at: range.location,
                                              effectiveRange: nil) as? Bool
        else { return }
        replace(NSRange(location: range.location + 1, length: 1), with: checked ? " " : "x")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        if checkboxHits().contains(where: { $0.hit.contains(p) }) || link(at: p) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override var intrinsicContentSize: NSSize {
        guard growsWithContent, let lm = layoutManager, let tc = textContainer else {
            return super.intrinsicContentSize
        }
        lm.ensureLayout(for: tc)
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: max(24, lm.usedRect(for: tc).height + 2))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        updateSlashFilter()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    // MARK: Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "b": toggleWrap("**"); return true
            case "i": toggleWrap("*");  return true
            case "u": toggleWrap("__"); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Wrap the selection in a mark, or unwrap it if it's already wrapped —
    /// operating on the source, through the undo stack.
    private func toggleWrap(_ mark: String) {
        let sel = selectedRange()
        let ns = string as NSString
        let markLen = (mark as NSString).length

        // Already wrapped just outside the selection? Strip.
        let before = NSRange(location: sel.location - markLen, length: markLen)
        let after = NSRange(location: sel.location + sel.length, length: markLen)
        if before.location >= 0, after.location + after.length <= ns.length,
           ns.substring(with: before) == mark, ns.substring(with: after) == mark {
            let outer = NSRange(location: before.location,
                                length: sel.length + 2 * markLen)
            replace(outer, with: ns.substring(with: sel))
            setSelectedRange(NSRange(location: before.location, length: sel.length))
            return
        }

        let inner = ns.substring(with: sel)
        if inner.hasPrefix(mark), inner.hasSuffix(mark), inner.count >= 2 * mark.count {
            replace(sel, with: String(inner.dropFirst(mark.count).dropLast(mark.count)))
            setSelectedRange(NSRange(location: sel.location, length: sel.length - 2 * markLen))
        } else {
            replace(sel, with: mark + inner + mark)
            setSelectedRange(NSRange(location: sel.location + markLen, length: sel.length))
        }
    }

    private func replace(_ range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    // MARK: Lists

    /// Return inside a list writes the next marker itself — a bullet, the
    /// following number, an unchecked box, a quote mark — so a list is typed
    /// once, not once per line. Return on an item with nothing in it ends the
    /// list instead of stacking another empty marker. The source is still the
    /// same plain Markdown; this only saves the retyping.
    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        guard sel.length == 0 else { super.insertNewline(sender); return }

        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        var line = ns.substring(with: lineRange)
        while line.hasSuffix("\n") || line.hasSuffix("\r") { line.removeLast() }

        // A caret still inside the marker isn't continuing anything yet.
        guard let item = ListItem(line: line),
              sel.location - lineRange.location >= item.prefixLength else {
            super.insertNewline(sender)
            return
        }

        if item.isEmpty {
            // Nested, an empty item climbs out one level first — Return walks
            // back up the list the same way ⇧⇥ does. Only at the top does it
            // end the list.
            if ListIndent.depth(of: item.indent) > 0 {
                shiftLevel(by: -1)
                return
            }
            replace(NSRange(location: lineRange.location, length: item.prefixLength), with: "")
            setSelectedRange(NSRange(location: lineRange.location, length: 0))
            return
        }
        replace(sel, with: "\n" + item.next)
        setSelectedRange(NSRange(location: sel.location + 1 + (item.next as NSString).length,
                                 length: 0))
    }

    // MARK: Nesting

    /// ⇥ and ⇧⇥ move list items in and out one level. Off a list they do what
    /// they have always done — a tab is still a tab in a paragraph.
    override func insertTab(_ sender: Any?) {
        if !shiftLevel(by: 1) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !shiftLevel(by: -1) { super.insertBacktab(sender) }
    }

    /// Re-indents every list line the selection touches, as one edit, so one
    /// undo puts it all back. False means this wasn't a list and the key
    /// belongs to whoever handles it next.
    @discardableResult
    private func shiftLevel(by delta: Int) -> Bool {
        let sel = selectedRange()
        let ns = string as NSString
        var lines: [NSRange] = []
        ns.enumerateSubstrings(in: ns.lineRange(for: sel),
                               options: [.byLines, .substringNotRequired]) {
            _, r, _, _ in lines.append(r)
        }
        // Every touched line has to be a list item; a mixed selection means
        // the key was meant for the text, not the structure.
        guard !lines.isEmpty,
              lines.allSatisfy({ ListItem(line: ns.substring(with: $0)) != nil })
        else { return false }

        var rewritten: [String] = []
        var shifted = 0          // how much the first line moved, for the caret
        for (i, r) in lines.enumerated() {
            var line = ns.substring(with: r)
            var moved = 0
            if delta > 0 {
                line = ListIndent.unit + line
                moved = (ListIndent.unit as NSString).length
            } else if line.hasPrefix(ListIndent.unit) {
                line.removeFirst()
                moved = -(ListIndent.unit as NSString).length
            } else if line.hasPrefix("    ") {
                line.removeFirst(4)
                moved = -4
            }
            if i == 0 { shifted = moved }
            rewritten.append(line)
        }
        guard rewritten.joined(separator: "\n") != lines.map({ ns.substring(with: $0) })
            .joined(separator: "\n") else { return true }

        let last = lines[lines.count - 1]
        let block = NSRange(location: lines[0].location,
                            length: last.location + last.length - lines[0].location)
        replace(block, with: rewritten.joined(separator: "\n"))

        if sel.length == 0 {
            setSelectedRange(NSRange(location: max(block.location, sel.location + shifted),
                                     length: 0))
        } else {
            let grown = rewritten.joined(separator: "\n") as NSString
            setSelectedRange(NSRange(location: block.location, length: grown.length))
        }
        return true
    }

    // MARK: Slash menu

    // The block menu is the app's own panel, not an NSMenu — same card, same
    // hairline, same ink as every other surface. It filters as you type after
    // the "/", and ↑↓, ⏎, and esc drive it without leaving the keyboard.

    private var slashPanel: NSPanel?
    private var slashModel: SlashModel?
    private var slashStart = 0

    private var slashActive: Bool { slashPanel != nil }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard let s = string as? String, s == "/", !slashActive else { return }
        let caret = selectedRange().location
        let line = (self.string as NSString).lineRange(
            for: NSRange(location: max(0, caret - 1), length: 0))
        // Only a "/" that is the whole line so far opens the menu — a slash
        // mid-sentence is just a slash.
        let lineSoFar = (self.string as NSString)
            .substring(with: NSRange(location: line.location,
                                     length: caret - line.location))
        if lineSoFar.trimmingCharacters(in: .whitespaces) == "/" {
            openSlashMenu(at: caret - 1)
        }
    }

    override func keyDown(with event: NSEvent) {
        if slashActive, let model = slashModel {
            switch event.keyCode {
            case 125: model.move(1);  return   // ↓
            case 126: model.move(-1); return   // ↑
            case 36, 48:                       // ⏎, ⇥
                if model.items.indices.contains(model.highlighted) {
                    commitBlock(model.items[model.highlighted])
                }
                return
            case 53: closeSlashMenu(); return  // esc
            default: break
            }
        }
        super.keyDown(with: event)
    }

    /// Called with a `[[name]]` target when one is clicked.
    var onOpenLink: ((String) -> Void)?

    private func link(at point: NSPoint) -> String? {
        guard let storage = textStorage, storage.length > 0, let lm = layoutManager, let tc = textContainer else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: local, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < lm.numberOfGlyphs else { return nil }
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        guard rect.insetBy(dx: -2, dy: -2).contains(local) else { return nil }
        let index = lm.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        return storage.attribute(.noteLink, at: index, effectiveRange: nil) as? String
    }

    override func mouseDown(with event: NSEvent) {
        closeSlashMenu()
        let p = convert(event.locationInWindow, from: nil)
        if let box = checkboxHits().first(where: { $0.hit.contains(p) }) {
            toggleCheckbox(box.range)
            return
        }
        if event.clickCount == 1, let target = link(at: p), let onOpenLink {
            onOpenLink(target)
            return
        }
        pointerSelecting = true
        defer { pointerSelecting = false }
        super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        closeSlashMenu()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        closeSlashMenu()
        super.viewWillMove(toWindow: newWindow)
    }

    private func openSlashMenu(at start: Int) {
        closeSlashMenu()
        let model = SlashModel()
        model.pick = { [weak self] in self?.commitBlock($0) }

        let hosting = NSHostingView(rootView: SlashMenuView(model: model))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.appearance = effectiveAppearance

        slashPanel = panel
        slashModel = model
        slashStart = start
        window?.addChildWindow(panel, ordered: .above)
        repositionSlashMenu()
    }

    /// Re-filter from whatever sits between the "/" and the caret. Anything
    /// that stops looking like a query — a newline, a deleted slash, a dead
    /// end — closes the menu and leaves the text exactly as typed.
    private func updateSlashFilter() {
        guard slashActive else { return }
        let caret = selectedRange().location
        let ns = string as NSString
        guard caret > slashStart, slashStart < ns.length,
              ns.substring(with: NSRange(location: slashStart, length: 1)) == "/" else {
            closeSlashMenu()
            return
        }
        let query = ns.substring(with: NSRange(location: slashStart + 1,
                                               length: caret - slashStart - 1))
        guard !query.contains("\n"), query.count <= 24,
              slashModel?.filter(query) == true else {
            closeSlashMenu()
            return
        }
        repositionSlashMenu()
    }

    private func repositionSlashMenu() {
        guard let panel = slashPanel, let hosting = panel.contentView else { return }
        // The row list just changed; let SwiftUI lay it out before sizing.
        DispatchQueue.main.async {
            hosting.setFrameSize(hosting.fittingSize)
            panel.setContentSize(hosting.fittingSize)
            // firstRect speaks in screen coordinates already.
            let caret = self.firstRect(
                forCharacterRange: NSRange(location: self.slashStart, length: 1),
                actualRange: nil)
            panel.setFrameTopLeftPoint(NSPoint(x: caret.minX, y: caret.minY - 4))
        }
    }

    private func closeSlashMenu() {
        guard let panel = slashPanel else { return }
        window?.removeChildWindow(panel)
        panel.orderOut(nil)
        slashPanel = nil
        slashModel = nil
    }

    private func commitBlock(_ block: NoteBlock) {
        let caret = selectedRange().location
        let typed = NSRange(location: slashStart, length: max(0, caret - slashStart))
        closeSlashMenu()
        if block.isImage {
            replace(typed, with: "")
            pickImage()
            return
        }
        replace(typed, with: block.snippet)
        if let at = block.caretAt {
            setSelectedRange(NSRange(location: typed.location + at, length: 0))
        }
    }

    // MARK: Images

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        insert(image: image)
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        // A copied file that is an image counts as an image; so does raw
        // image data. Everything else pastes as text, as before.
        if let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first,
           ["png", "jpg", "jpeg", "gif", "tiff", "heic"].contains(url.pathExtension.lowercased()),
           let image = NSImage(contentsOf: url) {
            insert(image: image)
            return
        }
        if board.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = (board.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first {
            insert(image: image)
            return
        }
        super.paste(sender)
    }

    private func insert(image: NSImage) {
        guard let name = NoteImages.save(image, base: imageBase, stem: imageStem) else { return }
        let width = textContainer?.size.width ?? 420
        let att = NoteMarkdown.attachment(named: name, image: image, width: width)
        let sel = selectedRange()
        guard shouldChangeText(in: sel, replacementString: att.string) else { return }
        textStorage?.replaceCharacters(in: sel, with: att)
        didChangeText()
        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
    }
}

// MARK: - List continuation

/// The marker at the head of a line, read back so Return can write the next
/// one. Deliberately generous about what counts as a list — `-`, `*`, `+`,
/// `1.`, `1)`, checkboxes, quotes — since the cost of guessing wrong is one
/// undo, and the cost of not guessing is retyping every line.
fileprivate struct ListItem {
    /// Characters the marker occupies, indent included.
    let prefixLength: Int
    /// What the next line starts with.
    let next: String
    /// Nothing was typed after the marker.
    let isEmpty: Bool
    /// The whitespace the line opens with — how deeply it's nested.
    let indent: String

    private static let bullet = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-*+][ \t])(\[[ xX]\][ \t])?"#)
    private static let ordered = try! NSRegularExpression(
        pattern: #"^([ \t]*)(\d+)([.)][ \t])"#)
    private static let quote = try! NSRegularExpression(
        pattern: #"^([ \t]*)>[ \t]?"#)

    init?(line: String) {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func rest(after r: NSRange) -> Bool {
            ns.substring(from: r.location + r.length)
                .trimmingCharacters(in: .whitespaces).isEmpty
        }

        if let m = ListItem.ordered.firstMatch(in: line, range: whole) {
            let n = Int(ns.substring(with: m.range(at: 2))) ?? 0
            prefixLength = m.range.length
            indent = ns.substring(with: m.range(at: 1))
            next = ns.substring(with: m.range(at: 1))
                + String(n + 1)
                + ns.substring(with: m.range(at: 3))
            isEmpty = rest(after: m.range)
        } else if let m = ListItem.bullet.firstMatch(in: line, range: whole) {
            prefixLength = m.range.length
            indent = ns.substring(with: m.range(at: 1))
            // A ticked box continues as an empty one — the next thing to do,
            // not a copy of the thing already done.
            let box = m.range(at: 3).location == NSNotFound ? "" : "[ ] "
            next = ns.substring(with: m.range(at: 1))
                + ns.substring(with: m.range(at: 2))
                + box
            isEmpty = rest(after: m.range)
        } else if let m = ListItem.quote.firstMatch(in: line, range: whole) {
            prefixLength = m.range.length
            indent = ns.substring(with: m.range(at: 1))
            next = ns.substring(with: m.range(at: 1)) + "> "
            isEmpty = rest(after: m.range)
        } else {
            return nil
        }
    }
}

// MARK: - Slash menu chrome

/// One insertable block. `caretAt` is where the caret lands inside the
/// snippet after insertion; nil means the end.
fileprivate struct NoteBlock: Identifiable {
    let title: String
    let symbol: String
    var snippet: String = ""
    var caretAt: Int? = nil
    var isImage = false
    var id: String { title }

    static let all: [NoteBlock] = [
        NoteBlock(title: "Heading 1", symbol: "textformat.size.larger", snippet: "# "),
        NoteBlock(title: "Heading 2", symbol: "textformat.size", snippet: "## "),
        NoteBlock(title: "Heading 3", symbol: "textformat.size.smaller", snippet: "### "),
        NoteBlock(title: "Bulleted list", symbol: "list.bullet", snippet: "- "),
        NoteBlock(title: "Numbered list", symbol: "list.number", snippet: "1. "),
        NoteBlock(title: "Checklist", symbol: "checklist", snippet: "- [ ] "),
        NoteBlock(title: "Quote", symbol: "text.quote", snippet: "> "),
        NoteBlock(title: "Code block", symbol: "chevron.left.forwardslash.chevron.right",
                  snippet: "```\n\n```", caretAt: 4),
        NoteBlock(title: "Divider", symbol: "minus", snippet: "---\n"),
        NoteBlock(title: "Table", symbol: "tablecells",
                  snippet: "| Column | Column |\n| --- | --- |\n|  |  |\n", caretAt: 2),
        NoteBlock(title: "Math block", symbol: "function", snippet: "$$\n\n$$", caretAt: 3),
        NoteBlock(title: "Inline math", symbol: "x.squareroot", snippet: "$$", caretAt: 1),
        NoteBlock(title: "Highlight", symbol: "highlighter", snippet: "====", caretAt: 2),
        NoteBlock(title: "Link to a note", symbol: "link", snippet: "[[]]", caretAt: 2),
        NoteBlock(title: "Date", symbol: "calendar", snippet: NoteBlock.today()),
        NoteBlock(title: "Now", symbol: "clock", snippet: NoteBlock.now()),
        NoteBlock(title: "Image\u{2026}", symbol: "photo", isImage: true),
    ]

    static func today() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func now() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

fileprivate final class SlashModel: ObservableObject {
    @Published var items: [NoteBlock] = NoteBlock.all
    @Published var highlighted = 0
    var pick: (NoteBlock) -> Void = { _ in }

    /// Narrow the list to the typed query; false means nothing matches and
    /// the menu should go away.
    func filter(_ query: String) -> Bool {
        let q = query.lowercased()
        items = q.isEmpty ? NoteBlock.all
                          : NoteBlock.all.filter { $0.title.lowercased().contains(q) }
        highlighted = 0
        return !items.isEmpty
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        highlighted = (highlighted + delta + items.count) % items.count
    }
}

/// The menu itself, drawn like every other surface in the app: the card, a
/// hairline, ink rows, one soft highlight that the arrow keys and the cursor
/// both drive.
fileprivate struct SlashMenuView: View {
    @ObservedObject var model: SlashModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { i, block in
                Button {
                    model.pick(block)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: block.symbol)
                            .font(Typography.label)
                            .foregroundStyle(i == model.highlighted ? Accent.text : Ink.muted)
                            .frame(width: 16)
                        Text(block.title)
                            .font(Typography.control)
                            .foregroundStyle(Ink.primary)
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: Radius.control)
                        .fill(i == model.highlighted ? Ink.wellHover : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.control))
                }
                .buttonStyle(.plain)
                .onHover { entered in
                    if entered { model.highlighted = i }
                }
            }
        }
        .padding(5)
        .frame(width: 188)
        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.well).strokeBorder(Ink.hairline, lineWidth: 1))
    }
}

// MARK: - SwiftUI wrapper

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// True boxes the editor in its own scroller; false lets it grow with
    /// the page it sits in.
    var scrollable = false
    /// The note's directory, for images. nil renders image references as text.
    var imageBase: URL? = nil
    var imageStem = "image"
    var editable = true
    /// A `[[name]]` was clicked.
    var onOpenLink: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSView {
        let view = MarkdownTextView.make()
        view.growsWithContent = !scrollable
        view.imageBase = imageBase
        view.imageStem = imageStem
        view.isEditable = editable
        view.onOpenLink = onOpenLink
        view.delegate = context.coordinator
        view.allowsUndo = true
        view.isRichText = true
        view.usesFontPanel = false
        view.importsGraphics = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.insertionPointColor = AccentNS.text
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.view = view
        context.coordinator.push(markdown: text)

        guard scrollable else { return view }
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only replace the storage when the outside world actually changed the
        // note — never mid-typing, when the storage is already the truth.
        guard let view = context.coordinator.view else { return }
        view.imageBase = imageBase
        view.imageStem = imageStem
        view.isEditable = editable
        view.onOpenLink = onOpenLink
        guard NoteMarkdown.markdown(from: view.attributedString()) != text else { return }
        context.coordinator.push(markdown: text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var view: MarkdownTextView?
        private var updating = false

        init(text: Binding<String>) { self.text = text }

        func push(markdown: String) {
            guard let view, let storage = view.textStorage else { return }
            updating = true
            // Before first layout the container width is meaningless; images
            // fall back to their natural cap rather than a sliver.
            let laidOut = view.textContainer?.size.width ?? 0
            let width = laidOut > 50 ? laidOut : 420
            storage.setAttributedString(
                NoteMarkdown.attributed(from: markdown, width: width, base: view.imageBase))
            NoteStyle.apply(to: storage)
            view.noteDidRestyle()
            updating = false
        }

        func textDidChange(_ notification: Notification) {
            guard !updating, let view, let storage = view.textStorage else { return }
            NoteStyle.apply(to: storage)
            view.noteDidRestyle()
            text.wrappedValue = NoteMarkdown.markdown(from: view.attributedString())
        }
    }
}
