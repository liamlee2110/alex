import SwiftUI
import AppKit
import PDFKit
import WebKit

struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

/// A generated HTML artifact, shown in a web view that can read the vault
/// and nothing else, with no bridge back into the app.
struct HTMLPreview: NSViewRepresentable {
    let url: URL
    let root: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.loadFileURL(url, allowingReadAccessTo: root)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.url?.standardizedFileURL != url.standardizedFileURL {
            view.loadFileURL(url, allowingReadAccessTo: root)
        }
    }
}

/// Code and plain text: the system text view in mono, editable.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var editable = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = InkNS.primary
        view.drawsBackground = false
        scroll.drawsBackground = false
        view.isEditable = editable
        view.allowsUndo = true
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.delegate = context.coordinator
        view.string = text
        context.coordinator.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = context.coordinator.view else { return }
        view.isEditable = editable
        if view.string != text { view.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var view: NSTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            text.wrappedValue = view.string
        }
    }
}
