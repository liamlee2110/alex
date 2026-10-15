import SwiftUI
import AppKit
import WebKit

/// A link's live view in the panel: the provider's own embed, or the page.
/// The web view keeps nothing between sessions, registers no script
/// message handlers, and hands every click-through and every "open in a
/// new window" to the default browser, so a page can be looked at but can
/// never reach the app or wander off inside the panel.
struct EmbedWebView: NSViewRepresentable {
    let url: URL
    let kind: LinkKind
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.underPageBackgroundColor = .clear
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.loaded != page { load(into: view, coordinator: context.coordinator) }
    }

    private var page: LinkEmbed.Page { LinkEmbed.page(for: url, kind: kind, dark: scheme == .dark) }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        let page = page
        coordinator.loaded = page
        switch page {
        case .html(let html):
            view.loadHTMLString(html, baseURL: LinkEmbed.base)
        case .url(let target):
            var request = URLRequest(url: target)
            // A provider's embed page wants a referring page; the open web
            // gets none, since a made-up referrer is nobody's business.
            if kind != .web { request.setValue(LinkEmbed.base.absoluteString, forHTTPHeaderField: "Referer") }
            view.load(request)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loaded: LinkEmbed.Page?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let url = action.request.url else { return .allow }
            NSWorkspace.shared.open(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, let scheme = url.scheme, scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
