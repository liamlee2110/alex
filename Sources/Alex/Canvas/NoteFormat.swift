import Foundation

/// What the format bar and the editor's keys do to a note (revision 29),
/// as edits to the Markdown source: the file is the truth (D2), so bold is
/// `**`, not a font. Foundation only, so the model suite can type into it.
/// Every edit is one replacement over one range, so it is one undo step.
enum NoteFormat {
    /// One replacement, and where the selection lands after it.
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        let selection: NSRange
    }

    // MARK: Inline marks

    /// The inline marks the editor draws. The patterns are the renderer's
    /// too (`NoteStyle`), so what the bar says is on is what is drawn.
    enum Mark: CaseIterable {
        case bold, italic, underline, strike, code, highlight, link

        /// What wraps the words when the bar adds the mark.
        var open: String {
            switch self {
            case .bold: return "**"
            case .italic: return "*"
            case .underline: return "__"
            case .strike: return "~~"
            case .code: return "`"
            case .highlight: return "=="
            case .link: return "[["
            }
        }

        var close: String { self == .link ? "]]" : open }

        /// Every spelling that reads as the mark; group 1 is the words.
        var patterns: [NSRegularExpression] {
            switch self {
            case .bold: return [NoteFormat.bold]
            case .italic: return [NoteFormat.italicA, NoteFormat.italicB]
            case .underline: return [NoteFormat.under]
            case .strike: return [NoteFormat.strike]
            case .code: return [NoteFormat.code]
            case .highlight: return [NoteFormat.marked]
            case .link: return [NoteFormat.wiki]
            }
        }
    }

    static let code    = try! NSRegularExpression(pattern: #"`([^`\n]+)`"#)
    static let wiki    = try! NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
    static let marked  = try! NSRegularExpression(pattern: #"==([^=\n]+)==(?!=)"#)
    static let bold    = try! NSRegularExpression(pattern: #"\*\*([^*\n]+?)\*\*"#)
    static let under   = try! NSRegularExpression(pattern: #"__([^_\n]+?)__"#)
    static let strike  = try! NSRegularExpression(pattern: #"~~([^~\n]+?)~~"#)
    static let italicA = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#)
    static let italicB = try! NSRegularExpression(pattern: #"(?<!_)_([^_\n]+?)_(?!_)"#)

    /// A line's block syntax, indent included: what a mark never wraps.
    static let blockPrefix = try! NSRegularExpression(
        pattern: #"^[ \t]*(#{1,3}[ \t]+|[-*+][ \t]+(\[[ xX]\][ \t]+)?|\d+[.)][ \t]+|>[ \t]?)?"#)

    /// The marks on across the whole selection: each touched line's words
    /// lie inside a span of the mark.
    static func active(in text: String, selection: NSRange) -> Set<Mark> {
        let ns = text as NSString
        let parts = portions(of: ns, in: selection)
        guard !parts.isEmpty else { return [] }
        return Set(Mark.allCases.filter { mark in
            parts.allSatisfy { enclosing(mark, in: ns, portion: $0) != nil }
        })
    }

    /// Turn `mark` on over the selection, or off where it is already on
    /// everywhere. Off unwraps the whole span the words are in; on wraps
    /// each line's words apart, since no mark crosses a line, and leaves
    /// the block syntax and the spaces at the ends outside. With nothing
    /// selected the marks go in with the caret between them.
    static func toggle(_ mark: Mark, in text: String, selection: NSRange) -> Edit? {
        let ns = text as NSString
        if selection.length == 0 {
            return Edit(range: selection, replacement: mark.open + mark.close,
                        selection: NSRange(location: selection.location + (mark.open as NSString).length,
                                           length: 0))
        }
        let parts = portions(of: ns, in: selection)
        guard !parts.isEmpty else { return nil }
        let spans = parts.map { enclosing(mark, in: ns, portion: $0) }
        let off = spans.allSatisfy { $0 != nil }
        let openLength = (mark.open as NSString).length

        // Each piece: the range it replaces, what goes there, and where
        // its words start and end inside that.
        var pieces: [(range: NSRange, text: String, words: NSRange)] = []
        for (part, span) in zip(parts, spans) {
            if off, let span {
                let words = span.inner
                let wordsText = ns.substring(with: words)
                // The selection keeps its place in the words.
                let start = max(part.location, words.location) - words.location
                let end = min(NSMaxRange(part), NSMaxRange(words)) - words.location
                pieces.append((span.whole, wordsText, NSRange(location: start, length: max(0, end - start))))
            } else if let span {
                // Already marked: left alone, selected as it stands.
                pieces.append((span.whole, ns.substring(with: span.whole),
                               NSRange(location: 0, length: span.whole.length)))
            } else {
                let words = ns.substring(with: part)
                pieces.append((part, mark.open + words + mark.close,
                               NSRange(location: openLength, length: part.length)))
            }
        }

        let whole = NSRange(location: pieces[0].range.location,
                            length: NSMaxRange(pieces[pieces.count - 1].range) - pieces[0].range.location)
        var out = ""
        var cursor = whole.location
        var selStart = 0
        var selEnd = 0
        for (i, piece) in pieces.enumerated() {
            out += ns.substring(with: NSRange(location: cursor, length: piece.range.location - cursor))
            let at = (out as NSString).length
            if i == 0 { selStart = at + piece.words.location }
            if i == pieces.count - 1 { selEnd = at + NSMaxRange(piece.words) }
            out += piece.text
            cursor = NSMaxRange(piece.range)
        }
        return Edit(range: whole, replacement: out,
                    selection: NSRange(location: whole.location + selStart, length: selEnd - selStart))
    }

    /// The selected words on each line the selection touches: past the
    /// line's block syntax, without the spaces at either end, and none
    /// for a line with no words selected.
    static func portions(of ns: NSString, in selection: NSRange) -> [NSRange] {
        guard selection.length > 0, NSMaxRange(selection) <= ns.length else { return [] }
        var parts: [NSRange] = []
        ns.enumerateSubstrings(in: ns.lineRange(for: selection), options: [.byLines, .substringNotRequired]) {
            _, line, _, _ in
            let prefix = blockPrefix.firstMatch(in: ns as String, range: line)?.range.length ?? 0
            var lo = max(selection.location, line.location + prefix)
            var hi = min(NSMaxRange(selection), NSMaxRange(line))
            while lo < hi, isSpace(ns.character(at: lo)) { lo += 1 }
            while hi > lo, isSpace(ns.character(at: hi - 1)) { hi -= 1 }
            if hi > lo { parts.append(NSRange(location: lo, length: hi - lo)) }
        }
        return parts
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

    /// The span of `mark` that holds `portion`, marks included.
    static func enclosing(_ mark: Mark, in ns: NSString, portion: NSRange)
        -> (whole: NSRange, inner: NSRange)? {
        let line = ns.lineRange(for: NSRange(location: portion.location, length: 0))
        for rx in mark.patterns {
            for m in rx.matches(in: ns as String, range: line)
            where m.range.location <= portion.location && NSMaxRange(portion) <= NSMaxRange(m.range) {
                return (m.range, m.range(at: 1))
            }
        }
        return nil
    }

    // MARK: Blocks

    /// What a line is, as Notion's "Turn into" names it.
    enum Block: CaseIterable {
        case text, heading1, heading2, heading3, bulleted, numbered, checklist, quote

        var title: String {
            switch self {
            case .text: return "Text"
            case .heading1: return "Heading 1"
            case .heading2: return "Heading 2"
            case .heading3: return "Heading 3"
            case .bulleted: return "Bulleted list"
            case .numbered: return "Numbered list"
            case .checklist: return "Checklist"
            case .quote: return "Quote"
            }
        }

        var isList: Bool { self == .bulleted || self == .numbered || self == .checklist }
    }

    private static let heading = try! NSRegularExpression(pattern: #"^(#{1,3})[ \t]+"#)
    private static let checkItem = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+][ \t]+\[([ xX])\][ \t]+"#)
    private static let bulletItem = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+][ \t]+"#)
    private static let orderedItem = try! NSRegularExpression(pattern: #"^([ \t]*)\d+[.)][ \t]+"#)
    private static let quoteLine = try! NSRegularExpression(pattern: #"^([ \t]*)>[ \t]?"#)

    /// A line read back: its kind, its indent, how long its syntax is,
    /// and whether a checklist item is ticked.
    struct Line {
        let kind: Block
        let indent: String
        let prefixLength: Int
        let checked: Bool

        init(_ line: String) {
            let ns = line as NSString
            let all = NSRange(location: 0, length: ns.length)
            func indent(_ m: NSTextCheckingResult) -> String {
                m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1))
            }
            if let m = heading.firstMatch(in: line, range: all) {
                kind = [.heading1, .heading2, .heading3][m.range(at: 1).length - 1]
                self.indent = ""; prefixLength = m.range.length; checked = false
            } else if let m = checkItem.firstMatch(in: line, range: all) {
                kind = .checklist; self.indent = indent(m); prefixLength = m.range.length
                checked = ns.substring(with: m.range(at: 2)) != " "
            } else if let m = bulletItem.firstMatch(in: line, range: all) {
                kind = .bulleted; self.indent = indent(m); prefixLength = m.range.length; checked = false
            } else if let m = orderedItem.firstMatch(in: line, range: all) {
                kind = .numbered; self.indent = indent(m); prefixLength = m.range.length; checked = false
            } else if let m = quoteLine.firstMatch(in: line, range: all) {
                kind = .quote; self.indent = ""; prefixLength = m.range.length; checked = false
            } else {
                kind = .text; self.indent = ""; prefixLength = 0; checked = false
            }
        }
    }

    /// The kind of the line `location` is on.
    static func block(in text: String, at location: Int) -> Block {
        let ns = text as NSString
        let r = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        return Line(lineText(ns, r)).kind
    }

    /// Every line the selection touches becomes `kind`, its words kept.
    /// A list keeps its nesting, a numbered list counts from one, a ticked
    /// box stays ticked, and a blank line stays blank. A selection that
    /// ends at the very start of a line does not take that line.
    static func turn(_ text: String, selection: NSRange, into kind: Block) -> Edit {
        let ns = text as NSString
        var sel = selection
        if sel.length > 0, NSMaxRange(sel) <= ns.length,
           ns.character(at: NSMaxRange(sel) - 1) == 0x0A {
            sel.length -= 1
        }
        let block = ns.lineRange(for: sel)
        var lines: [String] = []
        ns.enumerateSubstrings(in: block, options: [.byLines, .substringNotRequired]) { _, r, _, _ in
            lines.append(ns.substring(with: r))
        }
        if lines.isEmpty { lines = [""] }
        var number = 0
        var firstPrefix = 0
        let rewritten: [String] = lines.enumerated().map { i, raw in
            let line = Line(raw)
            let words = (raw as NSString).substring(from: line.prefixLength)
            guard !(words.trimmingCharacters(in: .whitespaces).isEmpty && lines.count > 1) else { return raw }
            let indent = kind.isList && line.kind.isList ? line.indent : ""
            let prefix: String
            switch kind {
            case .text: prefix = ""
            case .heading1: prefix = "# "
            case .heading2: prefix = "## "
            case .heading3: prefix = "### "
            case .bulleted: prefix = "- "
            case .numbered: number += 1; prefix = "\(number). "
            case .checklist: prefix = line.checked ? "- [x] " : "- [ ] "
            case .quote: prefix = "> "
            }
            if i == 0 { firstPrefix = ((indent + prefix) as NSString).length }
            return indent + prefix + words
        }
        // The line break that ends the block stays where it was.
        let body = lineText(ns, block)
        let tail = (ns.substring(with: block) as NSString).substring(from: (body as NSString).length)
        let replacement = rewritten.joined(separator: "\n") + tail
        let length = (rewritten.joined(separator: "\n") as NSString).length
        return Edit(range: block, replacement: replacement,
                    selection: NSRange(location: block.location + firstPrefix,
                                       length: max(0, length - firstPrefix)))
    }

    private static func lineText(_ ns: NSString, _ r: NSRange) -> String {
        var s = ns.substring(with: r)
        while s.hasSuffix("\n") || s.hasSuffix("\r") { s.removeLast() }
        return s
    }
}
