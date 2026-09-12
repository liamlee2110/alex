import SwiftUI
import PDFKit

/// M0's stand-in for the card panel: a plain preview of whatever the sidebar
/// selects. The canvas replaces the left of this at M1; the panel grows into
/// Donna's editor at M2.
struct DetailView: View {
    @EnvironmentObject private var vault: Vault
    let path: String?

    var body: some View {
        Group {
            if let path, let url = vault.url(for: path) {
                if vault.isDirectory(path) {
                    DirectoryPreview(path: path)
                } else {
                    FilePreview(path: path, url: url, kind: VaultEntry.Kind.forExtension(url.pathExtension))
                        .id("\(path)#\(vault.generation)")
                }
            } else {
                Text("Select a file to preview it.")
                    .font(Typography.body)
                    .foregroundStyle(Ink.faint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DirectoryPreview: View {
    @EnvironmentObject private var vault: Vault
    let path: String

    var body: some View {
        let entries = (vault.root.flatMap { try? VaultListing.entries(in: path, root: $0) }) ?? []
        VStack(spacing: Space.s) {
            Image(systemName: "folder")
                .font(Typography.display)
                .foregroundStyle(Ink.faint)
            Text(VaultPath.name(of: path).isEmpty ? vault.name : VaultPath.name(of: path))
                .font(Typography.title)
            Text("\(entries.count) items")
                .font(Typography.body)
                .foregroundStyle(Ink.muted)
        }
    }
}

private struct FilePreview: View {
    @EnvironmentObject private var vault: Vault
    let path: String
    let url: URL
    let kind: VaultEntry.Kind

    var body: some View {
        switch kind {
        case .image:
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(Space.l)
            } else {
                unreadable
            }
        case .pdf:
            PDFPreview(url: url)
        default:
            if let text = try? vault.readText(path) {
                ScrollView {
                    Text(text)
                        .font(kind == .markdown ? Typography.body : Typography.mono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.l)
                }
            } else {
                unreadable
            }
        }
    }

    private var unreadable: some View {
        Text("Alex can't show this file yet.")
            .font(Typography.body)
            .foregroundStyle(Ink.faint)
    }
}

private struct PDFPreview: NSViewRepresentable {
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
