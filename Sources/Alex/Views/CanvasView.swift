import SwiftUI

/// The desk: a pan-and-zoom viewport over the open canvas. Groups sit under
/// everything, edges are drawn in screen space so they stay crisp, and
/// nodes outside the visible rect are never built.
struct CanvasView: View {
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault
    @State private var pulse: String?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let vp = store.viewport
            let visible = vp.visibleWorld(in: size).insetBy(dx: -400, dy: -400)
            let nodes = store.document.nodes
            ZStack(alignment: .topLeading) {
                Ink.ground
                DotGrid(viewport: vp)
                EventCatcher(
                    onScroll: { delta, point, modifiers in
                        if modifiers.contains(.command) {
                            store.viewport.zoom(by: exp(delta.y * 0.01), around: point)
                        } else {
                            store.viewport.pan(by: delta)
                        }
                    },
                    onMagnify: { magnification, point in
                        store.viewport.zoom(by: 1 + magnification, around: point)
                    })
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(nil) }

                ZStack(alignment: .topLeading) {
                    ForEach(nodes.filter { $0.kind == .group && $0.frame.intersects(visible) }) { node in
                        GroupNodeView(node: node, selected: store.selection.contains(node.id))
                            .frame(width: node.width, height: node.height)
                            .position(node.center)
                            .onTapGesture { store.select(node.id) }
                    }
                    ForEach(nodes.filter { $0.kind != .group && $0.frame.intersects(visible) }) { node in
                        nodeView(node, zoom: vp.scale)
                            .pulseRing(pulse == node.id)
                            .frame(width: node.width, height: node.height)
                            .position(node.center)
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(vp.scale, anchor: .topLeading)
                .offset(x: vp.offset.x, y: vp.offset.y)

                EdgeLayer(document: store.document, viewport: vp)
                    .allowsHitTesting(false)

                BreadcrumbBar(store: store)
                ZoomControls(store: store, size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                if let trouble = store.trouble {
                    Text(trouble)
                        .font(Typography.meta)
                        .foregroundStyle(Ink.muted)
                        .padding(Space.m)
                        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
                        .elevation(.raised)
                        .padding(Space.l)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .clipped()
            .onChange(of: store.focusRequest) { _, id in focus(id, in: size) }
            .onChange(of: store.wantsFit) { _, wants in if wants { fit(in: size) } }
            .onAppear {
                if store.wantsFit { fit(in: size) }
                focus(store.focusRequest, in: size)
            }
        }
    }

    @ViewBuilder
    private func nodeView(_ node: CanvasNode, zoom: CGFloat) -> some View {
        let selected = store.selection.contains(node.id)
        switch node.kind {
        case .file:
            let path = node.file ?? ""
            if store.isDirectoryNode(node) {
                let info = store.peeks(for: path)
                FolderNodeView(node: node, name: VaultPath.name(of: path), count: info.count,
                               peeks: info.entries, selected: selected, zoom: zoom)
                    .onTapGesture(count: 2) { store.openDirectory(path) }
                    .onTapGesture { store.select(node.id) }
            } else {
                let kind = VaultEntry.Kind.forExtension((path as NSString).pathExtension)
                let preview = kind.isTextual
                    ? store.preview(for: path)
                    : CardPreview(title: VaultPath.name(of: path), lines: [], chips: [], frontmatter: Frontmatter())
                CardNodeView(node: node, path: path, kind: kind, preview: preview,
                             url: vault.url(for: path), missing: !vault.exists(path), selected: selected)
                    .onTapGesture(count: 2) { if kind == .canvas { store.openCanvas(at: path) } }
                    .onTapGesture { store.select(node.id) }
            }
        case .text:
            StickyNodeView(node: node, selected: selected)
                .onTapGesture { store.select(node.id) }
        case .link:
            LinkNodeView(node: node, selected: selected)
                .onTapGesture { store.select(node.id) }
        case .group:
            EmptyView()
        case .other:
            UnknownNodeView(node: node, selected: selected)
                .onTapGesture { store.select(node.id) }
        }
    }

    private func fit(in size: CGSize) {
        guard size.width > 0 else { return }
        store.viewport = Viewport.fitting(store.document.bounds, in: size)
        store.wantsFit = false
    }

    private func focus(_ id: String?, in size: CGSize) {
        guard let id, let node = store.document.node(id) else { return }
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5)) {
            var vp = store.viewport
            if vp.scale < 0.6 { vp.scale = 1 }
            vp.center(on: node.center, in: size)
            store.viewport = vp
        }
        pulse = id
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if pulse == id { pulse = nil }
        }
        store.focusRequest = nil
    }
}

private extension View {
    func pulseRing(_ on: Bool) -> some View {
        overlay {
            if on {
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Accent.text, lineWidth: 3)
                    .padding(-10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: on)
    }
}

/// A dot every 40 desk units, fading out when the desk is far away.
struct DotGrid: View {
    let viewport: Viewport

    var body: some View {
        Canvas { context, size in
            let step = 40 * viewport.scale
            guard step >= 14 else { return }
            let startX = viewport.offset.x.truncatingRemainder(dividingBy: step)
            let startY = viewport.offset.y.truncatingRemainder(dividingBy: step)
            var path = Path()
            var x = startX
            while x < size.width {
                var y = startY
                while y < size.height {
                    path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    y += step
                }
                x += step
            }
            context.fill(path, with: .color(Ink.hairline))
        }
    }
}
