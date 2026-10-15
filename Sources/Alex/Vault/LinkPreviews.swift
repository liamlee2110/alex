import AppKit
import CryptoKit
import ImageIO

/// Titles and pictures for link cards, fetched once and kept under Caches,
/// the way `Thumbnails` keeps QuickLook's renders. Derived data: the
/// address in the canvas file is the truth, and this whole directory can be
/// thrown away. Fetching is the app's only outbound traffic, so the
/// Settings toggle turns it off; a card then shows its address, and the
/// panel still embeds the page on request.
@MainActor
final class LinkPreviews: ObservableObject {
    static let shared = LinkPreviews()
    static let enabledKey = "fetchLinkPreviews"
    /// A title is asked for again after this long; the old one shows meanwhile.
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    nonisolated static let agent = "Alex/0.1 (macOS; link previews; +https://github.com/liamlee2110/alex)"

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    /// Bumped when a fetch lands, so cards redraw; the dictionaries below
    /// are filled from disk during a view's body and must not publish then.
    @Published private(set) var generation = 0
    private var metas: [String: LinkMeta] = [:]
    private var images: [String: NSImage] = [:]
    private var pending: Set<String> = []
    private var failed: Set<String> = []
    private let directory: URL?

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        directory = caches?.appendingPathComponent("Alex/links", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// What is known about an address: from memory, else from disk, else
    /// nil while a fetch runs. A stale entry shows while it is refreshed.
    func meta(for address: String) -> LinkMeta? {
        let key = Self.key(address)
        let known = metas[key] ?? readMeta(key)
        if let known {
            metas[key] = known
            if Date().timeIntervalSince(known.fetched) > Self.maxAge { refresh(address, key: key) }
            return known
        }
        refresh(address, key: key)
        return nil
    }

    /// The picture named by a title, at the best size the provider keeps.
    func image(for meta: LinkMeta, kind: LinkKind) -> NSImage? {
        guard let thumbnail = meta.thumbnail else { return nil }
        let key = Self.key(thumbnail)
        if let image = images[key] { return image }
        if let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".img")),
           let image = NSImage(data: data) {
            images[key] = image
            return image
        }
        guard enabled, !pending.contains(key), !failed.contains(key) else { return nil }
        pending.insert(key)
        let candidates = LinkMetadata.thumbnailCandidates(for: meta, kind: kind)
        Task.detached(priority: .utility) {
            var found: Data?
            for candidate in candidates {
                if let data = await Self.get(candidate, limit: 8_000_000), Self.decodes(data) {
                    found = data
                    break
                }
            }
            let picked = found
            await MainActor.run {
                self.pending.remove(key)
                if let picked, let image = NSImage(data: picked) {
                    self.images[key] = image
                    self.write(picked, key: key, ext: "img")
                    self.generation += 1
                } else {
                    self.failed.insert(key)
                }
            }
        }
        return nil
    }

    /// The site's own icon, one per host, so every card from the same
    /// place wears the same mark. Found on the host's front page, or at
    /// the addresses sites keep by convention; nil until it has arrived.
    func icon(for address: String) -> NSImage? {
        guard let host = LinkKind.webURL(address)?.host?.lowercased() else { return nil }
        let key = "icon-" + Self.key(host)
        if let image = images[key] { return image }
        if let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".img")),
           let image = NSImage(data: data) {
            images[key] = image
            return image
        }
        guard enabled, !pending.contains(key), !failed.contains(key) else { return nil }
        pending.insert(key)
        Task.detached(priority: .utility) {
            var declared: [URL] = []
            if let front = URL(string: "https://\(host)/"), let data = await Self.get(front, limit: 2_000_000, accept: "text/html") {
                declared = LinkMetadata.parseIcons(String(decoding: data, as: UTF8.self), at: front)
            }
            var found: Data?
            for candidate in LinkMetadata.iconCandidates(declared: declared, host: host).prefix(6) {
                if let data = await Self.get(candidate, limit: 1_000_000), Self.decodes(data) {
                    found = data
                    break
                }
            }
            let picked = found
            await MainActor.run {
                self.pending.remove(key)
                if let picked, let image = NSImage(data: picked) {
                    self.images[key] = image
                    self.write(picked, key: key, ext: "img")
                    self.generation += 1
                } else {
                    self.failed.insert(key)
                }
            }
        }
        return nil
    }

    private func refresh(_ address: String, key: String) {
        guard enabled, !pending.contains(key), !failed.contains(key), let url = LinkKind.webURL(address) else { return }
        pending.insert(key)
        Task.detached(priority: .utility) {
            let meta = await Self.fetch(url)
            await MainActor.run {
                self.pending.remove(key)
                if let meta {
                    self.metas[key] = meta
                    if let data = try? JSONEncoder().encode(meta) { self.write(data, key: key, ext: "json") }
                    self.generation += 1
                } else {
                    self.failed.insert(key)
                }
            }
        }
    }

    // MARK: - The fetch, off the main actor

    /// oEmbed where the provider offers it; the page's own tags where it
    /// does not, or where oEmbed named no title; the page's oEmbed
    /// discovery link when the page has one and nothing better answered.
    nonisolated static func fetch(_ url: URL) async -> LinkMeta? {
        let kind = LinkKind.classify(url)
        var meta: LinkMeta?
        if let endpoint = LinkMetadata.oembedEndpoint(for: url, kind: kind),
           let data = await get(endpoint, limit: 512_000, accept: "application/json") {
            meta = LinkMetadata.parseOEmbed(data)
        }
        let isPost: Bool
        switch kind {
        case .x, .threads: isPost = true
        default: isPost = false
        }
        let wantsPage = meta == nil
            || (meta?.title == nil && meta?.description == nil)
            || (meta?.thumbnail == nil && !isPost)
        if wantsPage, let data = await get(url, limit: 1_500_000, accept: "text/html") {
            let (page, discovered) = LinkMetadata.parseHTML(String(decoding: data, as: UTF8.self), at: url)
            if meta == nil, let discovered, let data = await get(discovered, limit: 512_000, accept: "application/json") {
                meta = LinkMetadata.parseOEmbed(data)
            }
            meta = (meta ?? LinkMeta()).filled(from: page)
        }
        guard var result = meta, !result.isEmpty else { return nil }
        result.provider = result.provider ?? kind.providerName ?? url.host
        result.fetched = Date()
        return result
    }

    nonisolated static func get(_ url: URL, limit: Int, accept: String? = nil) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        guard let (data, response) = try? await previewSession.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= limit else { return nil }
        return data
    }

    nonisolated static func decodes(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    // MARK: - The cache on disk

    private func readMeta(_ key: String) -> LinkMeta? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")) else { return nil }
        return try? JSONDecoder().decode(LinkMeta.self, from: data)
    }

    private func write(_ data: Data, key: String, ext: String) {
        guard let directory else { return }
        try? data.write(to: directory.appendingPathComponent(key + "." + ext), options: .atomic)
    }

    static func key(_ address: String) -> String {
        SHA256.hash(data: Data(address.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// One session for every preview fetch: no cookies kept, no cache of its
/// own, since the app keeps what it wants under Caches itself.
private let previewSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForResource = 20
    config.httpShouldSetCookies = false
    config.urlCache = nil
    return URLSession(configuration: config)
}()
