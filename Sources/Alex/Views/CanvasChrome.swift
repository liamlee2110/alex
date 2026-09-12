import SwiftUI

/// Where you are: the vault, then each directory down to the open one.
struct BreadcrumbBar: View {
    @ObservedObject var store: CanvasStore

    var body: some View {
        let crumbs = store.crumbs
        HStack(spacing: Space.xs) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { i, crumb in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(Typography.micro)
                        .foregroundStyle(Ink.faint)
                }
                let last = i == crumbs.count - 1
                Button {
                    store.openDirectory(crumb.path)
                } label: {
                    Text(crumb.name)
                        .font(last ? Typography.title : Typography.body)
                        .foregroundStyle(last ? Ink.primary : Ink.muted)
                }
                .buttonStyle(.plain)
                .disabled(last)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(Capsule().fill(Ink.float))
        .elevation(.raised)
        .padding(Space.l)
    }
}

struct ZoomControls: View {
    @ObservedObject var store: CanvasStore
    let size: CGSize

    private var centre: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    var body: some View {
        HStack(spacing: 2) {
            control("minus", "Zoom out") { store.viewport.zoom(by: 1 / 1.2, around: centre) }
                .keyboardShortcut("-", modifiers: .command)
            Button {
                withAnimation(.easeOut(duration: 0.3)) {
                    store.viewport = Viewport.fitting(store.document.bounds, in: size)
                }
            } label: {
                Text("\(Int((store.viewport.scale * 100).rounded()))%")
                    .font(Typography.label)
                    .foregroundStyle(Ink.muted)
                    .frame(minWidth: 44)
            }
            .buttonStyle(.plain)
            .help("Fit everything")
            .keyboardShortcut("1", modifiers: .command)
            control("plus", "Zoom in") { store.viewport.zoom(by: 1.2, around: centre) }
                .keyboardShortcut("=", modifiers: .command)
            control("1.circle", "Actual size") {
                var vp = store.viewport
                vp.zoom(by: 1 / vp.scale, around: centre)
                store.viewport = vp
            }
            .keyboardShortcut("0", modifiers: .command)
        }
        .padding(Space.xs)
        .background(Capsule().fill(Ink.float))
        .elevation(.raised)
        .padding(Space.l)
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.control)
                .foregroundStyle(Ink.muted)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
