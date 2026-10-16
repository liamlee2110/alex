import Compression
import Foundation

/// A Word, PowerPoint or Excel file, or its iWork twin (revision 61): a
/// page-shaped card like a PDF's, its first page drawn by QuickLook, with
/// its length under it where the file says so cheaply. Pure Foundation.
enum OfficeDocument {
    /// What the file is made of, which sets the card's shape and the word
    /// under it.
    enum Shape: Equatable {
        case pages, slides, sheets

        static func forExtension(_ ext: String) -> Shape? {
            switch ext.lowercased() {
            case "docx", "pages": return .pages
            case "pptx", "key": return .slides
            case "xlsx", "numbers": return .sheets
            default: return nil
            }
        }

        var symbol: Glyph {
            switch self {
            case .pages: return .fileText
            case .slides: return .presentation
            case .sheets: return .sheet
            }
        }

        /// "1 slide", "12 pages", "3 sheets".
        func caption(_ count: Int) -> String {
            let word: String
            switch self {
            case .pages: word = "page"
            case .slides: word = "slide"
            case .sheets: word = "sheet"
            }
            return count == 1 ? "1 \(word)" : "\(count) \(word)s"
        }
    }

    /// How many slides, pages or sheets the file holds, or nil where that
    /// would cost more than reading the zip's table of contents. A deck's
    /// slides and a workbook's sheets are parts of their own in the zip, so
    /// they are counted by name. A Word file's pages exist only once laid
    /// out, and Word writes the count into `docProps/app.xml` when it saves;
    /// a file made by a script (python-docx, which is how Claude makes one)
    /// carries its template's stale `<Pages>1` beside `<Words>0`, so the
    /// count is believed only where the words were counted too. iWork's
    /// files keep their slides in a format Alex does not read: no count.
    static func length(of url: URL) -> Int? {
        let ext = url.pathExtension.lowercased()
        guard ["docx", "pptx", "xlsx"].contains(ext),
              let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let zip = Zip(data) else { return nil }
        switch ext {
        case "pptx": return nonzero(zip.names.filter { isPart($0, "ppt/slides/slide") }.count)
        case "xlsx": return nonzero(zip.names.filter { isPart($0, "xl/worksheets/sheet") }.count)
        default:
            guard let app = zip.contents(of: "docProps/app.xml"),
                  let xml = String(data: app, encoding: .utf8) else { return nil }
            return wordPages(appXML: xml)
        }
    }

    /// `<Pages>` from Word's extended properties, believed only beside a
    /// word count above zero.
    static func wordPages(appXML xml: String) -> Int? {
        guard let words = element("Words", in: xml), words > 0,
              let pages = element("Pages", in: xml) else { return nil }
        return nonzero(pages)
    }

    /// `prefix` then digits then `.xml`: `ppt/slides/slide3.xml`, not the
    /// `_rels` folder beside it.
    static func isPart(_ name: String, _ prefix: String) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(".xml") else { return false }
        let middle = name.dropFirst(prefix.count).dropLast(4)
        return !middle.isEmpty && middle.allSatisfy(\.isASCII) && middle.allSatisfy(\.isNumber)
    }

    private static func element(_ tag: String, in xml: String) -> Int? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return Int(xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces))
    }

    private static func nonzero(_ n: Int) -> Int? { n > 0 ? n : nil }

    /// Just enough of a zip to list its parts and inflate a small one: the
    /// central directory and stored or deflated entries. Zip64 and anything
    /// else answers nil, which only costs a card its count.
    struct Zip {
        struct Entry {
            let name: String
            let method: UInt16
            let compressedSize: Int
            let size: Int
            let localOffset: Int
        }

        let data: Data
        let entries: [Entry]
        var names: [String] { entries.map(\.name) }

        init?(_ data: Data) {
            self.data = data
            let bytes = Bytes(data: data)
            // The end record is the last 22 bytes, or more if it has a comment.
            guard bytes.count >= 22 else { return nil }
            var end = -1
            var i = bytes.count - 22
            let floor = max(0, bytes.count - 22 - 0xFFFF)
            while i >= floor {
                if Self.u32(bytes, i) == 0x0605_4b50 { end = i; break }
                i -= 1
            }
            guard end >= 0 else { return nil }
            let count = Int(Self.u16(bytes, end + 10))
            var at = Int(Self.u32(bytes, end + 16))
            var out: [Entry] = []
            for _ in 0..<count {
                guard at + 46 <= bytes.count, Self.u32(bytes, at) == 0x0201_4b50 else { return nil }
                let nameLength = Int(Self.u16(bytes, at + 28))
                let extra = Int(Self.u16(bytes, at + 30))
                let comment = Int(Self.u16(bytes, at + 32))
                guard at + 46 + nameLength <= bytes.count else { return nil }
                let name = String(decoding: bytes[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
                out.append(Entry(name: name,
                                 method: Self.u16(bytes, at + 10),
                                 compressedSize: Int(Self.u32(bytes, at + 20)),
                                 size: Int(Self.u32(bytes, at + 24)),
                                 localOffset: Int(Self.u32(bytes, at + 42))))
                at += 46 + nameLength + extra + comment
            }
            entries = out
        }

        /// One part's bytes, if it is stored or deflated and small enough
        /// that reading it is cheap.
        func contents(of name: String, limit: Int = 1 << 20) -> Data? {
            guard let entry = entries.first(where: { $0.name == name }),
                  entry.size <= limit, entry.compressedSize <= limit else { return nil }
            let bytes = Bytes(data: data)
            let head = entry.localOffset
            guard head + 30 <= bytes.count, Self.u32(bytes, head) == 0x0403_4b50 else { return nil }
            let start = head + 30 + Int(Self.u16(bytes, head + 26)) + Int(Self.u16(bytes, head + 28))
            guard start + entry.compressedSize <= data.count else { return nil }
            let packed = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))
            switch entry.method {
            case 0: return packed
            case 8: return Self.inflate(packed, size: entry.size)
            default: return nil
            }
        }

        /// Raw deflate, which is what `COMPRESSION_ZLIB` decodes.
        private static func inflate(_ packed: Data, size: Int) -> Data? {
            guard size > 0 else { return Data() }
            var out = [UInt8](repeating: 0, count: size)
            let written = packed.withUnsafeBytes { source -> Int in
                guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(&out, size, base, packed.count, nil, COMPRESSION_ZLIB)
            }
            return written == size ? Data(out) : nil
        }

        /// The file read in place, mapped, never copied whole: a deck can be
        /// tens of megabytes and only its tail is wanted.
        private struct Bytes {
            let data: Data
            var count: Int { data.count }
            subscript(i: Int) -> UInt8 { data[data.startIndex + i] }
            subscript(r: Range<Int>) -> Data { data.subdata(in: (data.startIndex + r.lowerBound)..<(data.startIndex + r.upperBound)) }
        }

        private static func u16(_ b: Bytes, _ i: Int) -> UInt16 {
            UInt16(b[i]) | UInt16(b[i + 1]) << 8
        }

        private static func u32(_ b: Bytes, _ i: Int) -> UInt32 {
            UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        }
    }
}
