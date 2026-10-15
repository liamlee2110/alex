import Foundation
import CoreGraphics

// A `link` node, read for what its address is: a video, a post, a pin, a
// page. The kind decides the card's shape, where its title and picture
// come from, and what the panel embeds. Nothing in this file touches the
// network or AppKit, so the canvas suite covers it; `LinkPreviews` does the
// fetching and `EmbedWebView` the showing.

/// What a link points at. Every provider here answers for a title and a
/// picture without an API key (checked 2026-09-14) except Instagram, which
/// only embeds.
enum LinkKind: Hashable {
    case youtube(id: String)
    case x(id: String)
    /// The path after the host: `@user/post/CODE` or `t/CODE`.
    case threads(path: String)
    case pinterest(id: String)
    /// `p/CODE`, `reel/CODE` or `tv/CODE`.
    case instagram(path: String)
    case vimeo(id: String)
    case tiktok(id: String)
    /// `track/ID`, `album/ID`, `playlist/ID`, `episode/ID`, `show/ID`.
    case spotify(path: String)
    case web

    /// The address as a web URL, or nil: only http and https are links. A
    /// bare `example.com/page` is given https, since that is what a pasted
    /// address without a scheme means.
    static func webURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" { return url.host == nil ? nil : url }
            if scheme.count > 1 { return nil }
        }
        guard let firstDot = trimmed.firstIndex(of: "."), firstDot != trimmed.startIndex else { return nil }
        let head = trimmed[..<(trimmed.firstIndex(of: "/") ?? trimmed.endIndex)]
        guard head.contains("."), !head.hasSuffix("."), head.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }) else { return nil }
        return URL(string: "https://" + trimmed)
    }

    static func classify(_ address: String) -> LinkKind {
        guard let url = webURL(address) else { return .web }
        return classify(url)
    }

    static func classify(_ url: URL) -> LinkKind {
        var host = (url.host ?? "").lowercased()
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func id(_ s: String?, _ allowed: CharacterSet, _ length: ClosedRange<Int>) -> String? {
            guard let s, length.contains(s.count), s.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
            return s
        }
        let youtubeID = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let digits = CharacterSet.decimalDigits
        let code = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))

        switch host {
        case "youtube.com", "youtube-nocookie.com", "music.youtube.com":
            if parts.first == "watch", let v = id(query.first { $0.name == "v" }?.value, youtubeID, 11...11) { return .youtube(id: v) }
            if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]), let v = id(parts[1], youtubeID, 11...11) { return .youtube(id: v) }
            return .web
        case "youtu.be":
            if let v = id(parts.first, youtubeID, 11...11) { return .youtube(id: v) }
            return .web
        case "x.com", "twitter.com":
            if let i = parts.firstIndex(of: "status"), i + 1 < parts.count, let s = id(parts[i + 1], digits, 1...30) { return .x(id: s) }
            return .web
        case "threads.net", "threads.com":
            if parts.count >= 3, parts[0].hasPrefix("@"), parts[1] == "post", let c = id(parts[2], code, 1...40) {
                return .threads(path: "\(parts[0])/post/\(c)")
            }
            if parts.count >= 2, parts[0] == "t", let c = id(parts[1], code, 1...40) { return .threads(path: "t/\(c)") }
            return .web
        case "pinterest.com", "pinterest.co.uk", "pinterest.fr", "pinterest.de", "pinterest.jp", "pinterest.ca", "pinterest.com.au":
            if parts.count >= 2, parts[0] == "pin", let p = id(parts[1], digits, 1...30) { return .pinterest(id: p) }
            return .web
        case "instagram.com":
            if parts.count >= 2, ["p", "reel", "reels", "tv"].contains(parts[0]), let c = id(parts[1], code, 1...40) {
                return .instagram(path: "\(parts[0] == "reels" ? "reel" : parts[0])/\(c)")
            }
            return .web
        case "vimeo.com":
            if let v = id(parts.first, digits, 1...20) { return .vimeo(id: v) }
            return .web
        case "player.vimeo.com":
            if parts.count >= 2, parts[0] == "video", let v = id(parts[1], digits, 1...20) { return .vimeo(id: v) }
            return .web
        case "tiktok.com":
            if let i = parts.firstIndex(of: "video"), i + 1 < parts.count, let v = id(parts[i + 1], digits, 1...30) { return .tiktok(id: v) }
            return .web
        case "open.spotify.com":
            if parts.count >= 2, ["track", "album", "playlist", "episode", "show", "artist"].contains(parts[0]), let s = id(parts[1], code, 1...40) {
                return .spotify(path: "\(parts[0])/\(s)")
            }
            return .web
        default:
            return .web
        }
    }

    /// The provider's name, for the caption; nil for the open web, where
    /// the site's own name or its host stands in.
    var providerName: String? {
        switch self {
        case .youtube: return "YouTube"
        case .x: return "X"
        case .threads: return "Threads"
        case .pinterest: return "Pinterest"
        case .instagram: return "Instagram"
        case .vimeo: return "Vimeo"
        case .tiktok: return "TikTok"
        case .spotify: return "Spotify"
        case .web: return nil
        }
    }

    /// The icon that marks the card and the panel's title row.
    var symbol: Glyph {
        switch self {
        case .youtube, .vimeo: return .circlePlay
        case .x, .threads: return .messageSquareText
        case .pinterest: return .pin
        case .instagram: return .camera
        case .tiktok, .spotify: return .music
        case .web: return .globe
        }
    }

    /// The shape a new card takes: a video is a 16:9 picture with a caption
    /// under it, a post is a short paragraph, a pin or a reel stands
    /// portrait, a page is a paper card.
    var cardSize: CGSize {
        switch self {
        case .youtube, .vimeo: return CGSize(width: 320, height: 234)
        case .x, .threads: return CGSize(width: 320, height: 220)
        case .pinterest, .instagram, .tiktok: return CGSize(width: 320, height: 380)
        case .spotify, .web: return CGSize(width: 320, height: 200)
        }
    }

    /// The account the address itself names, for a card nothing has answered
    /// for yet: a post on X, Threads or TikTok carries its author in its path.
    func handle(in url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        switch self {
        case .x:
            guard let first = parts.first, first != "i", first.first?.isLetter == true || first.first?.isNumber == true else { return nil }
            return "@" + first
        case .threads(let path):
            let head = path.split(separator: "/").first.map(String.init) ?? ""
            return head.hasPrefix("@") ? head : nil
        case .tiktok:
            return parts.first.flatMap { $0.hasPrefix("@") ? $0 : nil }
        default:
            return nil
        }
    }

    var isVideo: Bool {
        if case .youtube = self { return true }
        if case .vimeo = self { return true }
        return false
    }
}

/// What a link card knows about its address once someone has asked: the
/// title, who made it, where it lives, a picture, and for a post its text.
/// Derived data, cached under Caches and never written into the canvas.
struct LinkMeta: Codable, Hashable {
    var title: String?
    var author: String?
    var provider: String?
    var thumbnail: String?
    var description: String?
    var fetched: Date

    init(title: String? = nil, author: String? = nil, provider: String? = nil,
         thumbnail: String? = nil, description: String? = nil, fetched: Date = Date()) {
        self.title = title; self.author = author; self.provider = provider
        self.thumbnail = thumbnail; self.description = description; self.fetched = fetched
    }

    var isEmpty: Bool { title == nil && author == nil && thumbnail == nil && description == nil }

    /// This, with the other's fields filling any gaps.
    func filled(from other: LinkMeta?) -> LinkMeta {
        guard let other else { return self }
        var m = self
        m.title = m.title ?? other.title
        m.author = m.author ?? other.author
        m.provider = m.provider ?? other.provider
        m.thumbnail = m.thumbnail ?? other.thumbnail
        m.description = m.description ?? other.description
        return m
    }
}

/// Where a title comes from and how it is read: oEmbed for the providers
/// that offer it, the page's Open Graph tags otherwise, with the page's
/// own oEmbed discovery link honoured when it has one.
enum LinkMetadata {
    /// The oEmbed endpoint to ask, or nil where the page must be read.
    static func oembedEndpoint(for url: URL, kind: LinkKind) -> URL? {
        let base: String
        switch kind {
        case .youtube: base = "https://www.youtube.com/oembed?format=json&url="
        case .x: base = "https://publish.x.com/oembed?dnt=true&omit_script=true&url="
        case .threads: base = "https://graph.threads.net/v1.0/oembed?url="
        case .pinterest: base = "https://www.pinterest.com/oembed.json?url="
        case .vimeo: base = "https://vimeo.com/api/oembed.json?url="
        case .tiktok: base = "https://www.tiktok.com/oembed?url="
        case .spotify: base = "https://open.spotify.com/oembed?url="
        case .instagram, .web: return nil
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: base + encoded)
    }

    /// An oEmbed reply. A post's oEmbed carries its text only inside the
    /// widget HTML, so the first paragraph of that HTML becomes the
    /// description when the reply names no title.
    static func parseOEmbed(_ data: Data) -> LinkMeta? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func str(_ key: String) -> String? {
            guard let s = object[key] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        var meta = LinkMeta(title: str("title"), author: str("author_name"),
                            provider: str("provider_name"), thumbnail: str("thumbnail_url"))
        if let html = str("html"), let paragraph = firstMatch(in: html, pattern: "<p[^>]*>(.*?)</p>", group: 1) {
            let text = decodeEntities(stripTags(paragraph))
            if !text.isEmpty { meta.description = text }
        }
        return meta.isEmpty ? nil : meta
    }

    /// The page itself: Open Graph and Twitter card tags, the `<title>` as
    /// a fallback, and the oEmbed discovery link if the page has one.
    static func parseHTML(_ html: String, at url: URL) -> (meta: LinkMeta, oembed: URL?) {
        let head = String(html.prefix(200_000))
        var tags: [String: String] = [:]
        for tag in matches(in: head, pattern: "<meta\\b[^>]*>") {
            let attrs = attributes(of: tag)
            guard let content = attrs["content"], !content.isEmpty else { continue }
            let key = (attrs["property"] ?? attrs["name"] ?? "").lowercased()
            if !key.isEmpty, tags[key] == nil { tags[key] = decodeEntities(content) }
        }
        var oembed: URL?
        for tag in matches(in: head, pattern: "<link\\b[^>]*>") {
            let attrs = attributes(of: tag)
            if attrs["type"]?.lowercased() == "application/json+oembed", let href = attrs["href"] {
                oembed = URL(string: decodeEntities(href), relativeTo: url)?.absoluteURL
                break
            }
        }
        var meta = LinkMeta()
        meta.title = tags["og:title"] ?? tags["twitter:title"]
            ?? firstMatch(in: head, pattern: "<title[^>]*>(.*?)</title>", group: 1).map { decodeEntities(stripTags($0)) }
        meta.description = tags["og:description"] ?? tags["twitter:description"] ?? tags["description"]
        meta.provider = tags["og:site_name"]
        meta.author = tags["author"] ?? tags["article:author"]
        if let image = tags["og:image"] ?? tags["og:image:url"] ?? tags["twitter:image"] {
            meta.thumbnail = URL(string: image, relativeTo: url)?.absoluteURL.absoluteString
        }
        for key in ["title", "description", "provider", "author"] {
            switch key {
            case "title": meta.title = clean(meta.title)
            case "description": meta.description = clean(meta.description)
            case "provider": meta.provider = clean(meta.provider)
            default: meta.author = clean(meta.author)
            }
        }
        return (meta, oembed)
    }

    /// Larger pictures than the reply offers, where a provider's CDN keeps
    /// them at a known address: the card is drawn at 640 pixels across.
    static func thumbnailCandidates(for meta: LinkMeta, kind: LinkKind) -> [URL] {
        guard let given = meta.thumbnail, let url = URL(string: given) else { return [] }
        var candidates: [URL] = []
        switch kind {
        case .youtube(let id):
            candidates.append(URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")!)
        case .pinterest:
            if let bigger = URL(string: given.replacingOccurrences(of: "/236x/", with: "/736x/")), bigger != url {
                candidates.append(bigger)
            }
        default:
            break
        }
        candidates.append(url)
        return candidates
    }

    // MARK: - The site's icon

    /// The icons a page declares, best first: touch icons over favicons,
    /// larger over smaller, mask icons left out (they are single-colour
    /// silhouettes). Relative addresses resolve against the page.
    static func parseIcons(_ html: String, at url: URL) -> [URL] {
        var ranked: [(rank: Int, url: URL)] = []
        for tag in matches(in: String(html.prefix(400_000)), pattern: "<link\\b[^>]*>") {
            let attrs = attributes(of: tag)
            let rels = (attrs["rel"] ?? "").lowercased().split(separator: " ").map(String.init)
            guard rels.contains(where: { $0.hasSuffix("icon") }), !rels.contains("mask-icon"),
                  let href = attrs["href"], let icon = URL(string: decodeEntities(href), relativeTo: url)?.absoluteURL else { continue }
            let touch = rels.contains { $0.hasPrefix("apple-touch-icon") }
            let side = (attrs["sizes"] ?? "").split(separator: "x").first.flatMap { Int($0) } ?? 0
            ranked.append((rank: (touch ? 1_000 : 0) + min(side, 999), url: icon))
        }
        var seen: Set<URL> = []
        return ranked.sorted { $0.rank > $1.rank }.map(\.url).filter { seen.insert($0).inserted }
    }

    /// Where to look for a host's icon, in order: what its page declares,
    /// then the two addresses a site keeps by convention. A candidate that
    /// answers with a page instead of a picture is skipped by the fetch.
    static func iconCandidates(declared: [URL], host: String) -> [URL] {
        var candidates = declared
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            if let url = URL(string: "https://\(host)\(path)"), !candidates.contains(url) { candidates.append(url) }
        }
        return candidates
    }

    // MARK: - Text helpers

    static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
                               ("&#x27;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
                               ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        for m in matches(in: out, pattern: "&#(x?[0-9a-fA-F]+);") {
            let body = m.dropFirst(2).dropLast()
            let value = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) {
                out = out.replacingOccurrences(of: m, with: String(Character(scalar)))
            }
        }
        return out
    }

    /// Whitespace folded, nothing at the ends, nil when nothing is left.
    static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let folded = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folded.isEmpty ? nil : folded
    }

    /// `name="value"`, `name='value'` and `name=value` pairs of one tag.
    static func attributes(of tag: String) -> [String: String] {
        var attrs: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))") else { return attrs }
        let ns = tag as NSString
        for m in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            for group in 2...4 where m.range(at: group).location != NSNotFound {
                attrs[name] = ns.substring(with: m.range(at: group))
                break
            }
        }
        return attrs
    }

    static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }
}

/// What the panel loads for a link: a provider's own embed, or the page.
/// YouTube needs a referring page or it answers "Error 153", so the player
/// is wrapped in a local page under `base`; the same page carries the
/// IFrame API, which is how a later "quote at 1:23" would read the clock.
enum LinkEmbed {
    enum Page: Equatable {
        case html(String)
        case url(URL)
    }

    /// The origin the wrapper pages claim. Not a real host: the providers
    /// only want a referrer that is an https page.
    static let base = URL(string: "https://alex.local/")!

    static func page(for url: URL, kind: LinkKind, dark: Bool) -> Page {
        switch kind {
        case .youtube(let id):
            // The player API swaps the placeholder for an iframe of its own
            // default size, 640 by 390, unless told one; sizing only the
            // placeholder left the iframe that big and the sheet scrolling
            // to show the rest. The iframe keeps the id, so one rule fills
            // both, and the page itself never scrolls.
            return .html("""
                <!doctype html><html><head><meta name="viewport" content="width=device-width">
                <style>html,body{margin:0;height:100%;overflow:hidden;background:\(dark ? "#1B1B20" : "#000")}#p{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
                <body><div id="p"></div>
                <script src="https://www.youtube.com/iframe_api"></script>
                <script>var player;function onYouTubeIframeAPIReady(){player=new YT.Player('p',{width:'100%',height:'100%',host:'https://www.youtube-nocookie.com',videoId:'\(id)',playerVars:{playsinline:1,rel:0}})}</script>
                </body></html>
                """)
        case .x(let id):
            return .html("""
                <!doctype html><html><head><meta name="viewport" content="width=device-width">
                <style>html,body{margin:0;background:transparent}</style></head>
                <body><blockquote class="twitter-tweet" data-dnt="true" data-theme="\(dark ? "dark" : "light")"><a href="https://x.com/i/status/\(id)"></a></blockquote>
                <script async src="https://platform.x.com/widgets.js" charset="utf-8"></script>
                </body></html>
                """)
        case .threads(let path):
            return .url(URL(string: "https://www.threads.com/\(path)/embed")!)
        case .pinterest(let id):
            return .url(URL(string: "https://assets.pinterest.com/ext/embed.html?id=\(id)")!)
        case .instagram(let path):
            return .url(URL(string: "https://www.instagram.com/\(path)/embed/")!)
        case .vimeo(let id):
            return .url(URL(string: "https://player.vimeo.com/video/\(id)?dnt=1")!)
        case .tiktok(let id):
            return .url(URL(string: "https://www.tiktok.com/embed/v2/\(id)")!)
        case .spotify(let path):
            return .url(URL(string: "https://open.spotify.com/embed/\(path)?theme=\(dark ? "0" : "1")")!)
        case .web:
            return .url(url)
        }
    }
}
