import SwiftUI
import AppKit

/// The desk: a pan-and-zoom viewport over the open canvas. Groups sit under
/// everything, edges are drawn in screen space so they stay crisp, nodes
/// outside the visible rect are never built. Every edit here is one call
/// into the store, made when the gesture ends, so one drag is one undo.
struct CanvasView: View {
    @ObservedObject var store: CanvasStore
    @EnvironmentObject private var vault: Vault
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focused: Bool

    @State private var pulse: String?
    @State private var drag: (ids: Set<String>, delta: CGSize)?
    @State private var resize: (id: String, size: CGSize)?
    @State private var marquee: CGRect?
    @State private var connecting: (from: String, side: CanvasSide, to: CGPoint)?
    @State private var editingSticky: String?
    /// The last fit or focus and the viewport it produced. The desk is often
    /// narrow at launch, before the split view settles; if it resizes and
    /// nobody has panned since, the fit or focus is redone at the new size.
    @State private var settled: (viewport: Viewport, focus: String?)?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let vp = store.viewport
            let visible = vp.visibleWorld(in: size).insetBy(dx: -400, dy: -400)
            ZStack(alignment: .topLeading) {
                Ink.ground
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
                ground(vp: vp)
                world(visible: visible, size: size, vp: vp)
                EdgeLayer(document: store.document, viewport: vp, derived: store.derivedEdges())
                    .allowsHitTesting(false)
                pendingEdge(vp: vp)
                if let marquee {
                    Rectangle()
                        .fill(Accent.wash)
                        .overlay(Rectangle().stroke(Accent.text, lineWidth: 1))
                        .frame(width: marquee.width, height: marquee.height)
                        .position(x: marquee.midX, y: marquee.midY)
                        .allowsHitTesting(false)
                }
                // The desk runs under the top bar; a fade keeps the breadcrumb legible.
                LinearGradient(stops: [.init(color: Ink.ground, location: 0),
                                       .init(color: Ink.ground, location: 0.55),
                                       .init(color: Ink.ground.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 76)
                    .allowsHitTesting(false)
                ToolPalette(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                ZoomControls(store: store)
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
            .coordinateSpace(name: "desk")
            .clipped()
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onDeleteCommand { store.remove(store.selection) }
            .onExitCommand {
                store.select(nil)
                editingSticky = nil
            }
            .dropDestination(for: URL.self) { urls, location in
                store.importFiles(urls, at: vp.toWorld(location))
                return true
            }
            .onChange(of: store.focusRequest) { _, id in focus(id, in: size) }
            .onChange(of: store.wantsFit) { _, wants in if wants { fit(in: size) } }
            .onChange(of: size) { _, new in
                store.viewSize = new
                if store.wantsFit {
                    fit(in: new)
                } else if let settled, settled.viewport == store.viewport {
                    if let id = settled.focus { focus(id, in: new, pulse: false) } else { fit(in: new) }
                }
            }
            .onChange(of: store.selection) { _, selection in
                if let editing = editingSticky, !selection.contains(editing) { editingSticky = nil }
            }
            .onAppear {
                store.undoManager = undoManager
                store.viewSize = size
                if store.wantsFit { fit(in: size) }
                focus(store.focusRequest, in: size)
            }
        }
    }

    // MARK: - The ground: deselect, marquee, new sticky

    private func ground(vp: Viewport) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("desk"))
                    .onChanged { value in
                        marquee = CGRect(x: min(value.startLocation.x, value.location.x),
                                         y: min(value.startLocation.y, value.location.y),
                                         width: abs(value.location.x - value.startLocation.x),
                                         height: abs(value.location.y - value.startLocation.y))
                    }
                    .onEnded { _ in
                        guard let rect = marquee else { return }
                        marquee = nil
                        let world = CGRect(origin: vp.toWorld(rect.origin),
                                           size: CGSize(width: rect.width / vp.scale, height: rect.height / vp.scale))
                        let hits = store.document.nodes
                            .filter { $0.kind != .group && $0.frame.intersects(world) }
                            .map(\.id)
                        let additive = NSEvent.modifierFlags.contains(.shift)
                        store.selection = additive ? store.selection.union(hits) : Set(hits)
                    })
            .onTapGesture(count: 2) { point in
                let node = store.addSticky(at: vp.toWorld(point))
                editingSticky = node.id
            }
            .onTapGesture {
                store.select(nil)
                editingSticky = nil
                focused = true
            }
    }

    // MARK: - The world layer

    private func world(visible: CGRect, size: CGSize, vp: Viewport) -> some View {
        let nodes = store.document.nodes
        let groups = nodes.filter { $0.kind == .group && $0.frame.intersects(visible) }
        let others = nodes.filter { $0.kind != .group && $0.frame.intersects(visible) }
        return ZStack(alignment: .topLeading) {
            ForEach(groups) { node in
                let frame = liveFrame(node)
                GroupNodeView(node: node, selected: store.selection.contains(node.id))
                    .overlay {
                        if store.selection == [node.id] { resizeHandle(for: node, vp: vp) }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .onTapGesture { select(node) }
                    .gesture(dragGesture(for: node, vp: vp))
            }
            ForEach(others) { node in
                let frame = liveFrame(node)
                nodeView(node, zoom: vp.scale)
                    .pulseRing(pulse == node.id)
                    .overlay {
                        if store.selection == [node.id] { handles(for: node, vp: vp) }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .gesture(dragGesture(for: node, vp: vp))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .scaleEffect(vp.scale, anchor: .topLeading)
        .offset(x: vp.offset.x, y: vp.offset.y)
    }

    private func liveFrame(_ node: CanvasNode) -> CGRect {
        var frame = node.frame
        if let drag, drag.ids.contains(node.id) {
            frame = frame.offsetBy(dx: drag.delta.width, dy: drag.delta.height)
        }
        if let resize, resize.id == node.id {
            frame.size = resize.size
        }
        return frame
    }

    private func select(_ node: CanvasNode) {
        if NSEvent.modifierFlags.contains(.shift) {
            if store.selection.contains(node.id) { store.selection.remove(node.id) }
            else { store.selection.insert(node.id) }
        } else {
            store.select(node.id)
        }
        focused = true
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
                    .onTapGesture { select(node) }
            } else {
                let kind = VaultEntry.Kind.forExtension((path as NSString).pathExtension)
                let preview = kind.isTextual
                    ? store.preview(for: path)
                    : CardPreview(title: VaultPath.name(of: path), lines: [], chips: [], frontmatter: Frontmatter())
                CardNodeView(node: node, path: path, kind: kind, preview: preview,
                             url: vault.url(for: path), missing: !vault.exists(path), selected: selected,
                             tint: store.tint(for: node))
                    .onTapGesture(count: 2) { if kind == .canvas { store.openCanvas(at: path) } }
                    .onTapGesture { select(node) }
            }
        case .text:
            StickyNodeView(node: node, selected: selected, editing: editingSticky == node.id,
                           onChange: { text in store.setText(node.id, text) })
                .onTapGesture(count: 2) {
                    store.select(node.id)
                    editingSticky = node.id
                }
                .onTapGesture { select(node) }
        case .link:
            LinkNodeView(node: node, selected: selected)
                .onTapGesture { select(node) }
        case .group:
            EmptyView()
        case .other:
            UnknownNodeView(node: node, selected: selected)
                .onTapGesture { select(node) }
        }
    }

    // MARK: - Gestures

    private func dragGesture(for node: CanvasNode, vp: Viewport) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("desk"))
            .onChanged { value in
                if drag == nil {
                    var ids: Set<String> = store.selection.contains(node.id) ? store.selection : [node.id]
                    if !store.selection.contains(node.id) { store.select(node.id) }
                    for id in ids {
                        if let group = store.document.node(id), group.kind == .group {
                            ids.formUnion(store.nodeIDs(inside: group.frame))
                        }
                    }
                    drag = (ids, .zero)
                }
                drag?.delta = CGSize(width: value.translation.width / vp.scale,
                                     height: value.translation.height / vp.scale)
            }
            .onEnded { value in
                guard let current = drag else { return }
                drag = nil
                let delta = CGSize(width: value.translation.width / vp.scale,
                                   height: value.translation.height / vp.scale)
                if abs(delta.width) > 0.5 || abs(delta.height) > 0.5 {
                    store.move(current.ids, by: delta)
                }
            }
    }

    @ViewBuilder
    private func handles(for node: CanvasNode, vp: Viewport) -> some View {
        ZStack {
            if !store.isDirectoryNode(node) { resizeHandle(for: node, vp: vp) }
            ForEach([CanvasSide.top, .right, .bottom, .left], id: \.self) { side in
                connector(for: node, side: side, vp: vp)
            }
        }
    }

    /// The corner grip, constant on screen whatever the zoom.
    private func resizeHandle(for node: CanvasNode, vp: Viewport) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Ink.card)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Accent.text, lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .scaleEffect(1 / vp.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(x: 6 / vp.scale, y: 6 / vp.scale)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("desk"))
                    .onChanged { value in
                        let minWidth: CGFloat = node.kind == .text ? 120 : 160
                        let width = max(minWidth, node.width + value.translation.width / vp.scale)
                        let height = max(80, node.height + value.translation.height / vp.scale)
                        resize = (node.id, CGSize(width: width, height: height))
                    }
                    .onEnded { _ in
                        if let current = resize {
                            store.setFrame(node.id, CGRect(origin: node.frame.origin, size: current.size))
                        }
                        resize = nil
                    })
    }

    /// A dot on each side; drag one to another card to connect them.
    private func connector(for node: CanvasNode, side: CanvasSide, vp: Viewport) -> some View {
        let alignment: Alignment
        switch side {
        case .top: alignment = .top
        case .bottom: alignment = .bottom
        case .left: alignment = .leading
        case .right: alignment = .trailing
        }
        let normal = EdgeGeometry.normal(side)
        return Circle()
            .fill(Ink.card)
            .overlay(Circle().stroke(Accent.text, lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .scaleEffect(1 / vp.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .offset(x: normal.x * 14 / vp.scale, y: normal.y * 14 / vp.scale)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("desk"))
                    .onChanged { value in connecting = (node.id, side, value.location) }
                    .onEnded { value in
                        if let target = store.hitTest(vp.toWorld(value.location), excluding: [node.id]) {
                            store.connect(node.id, target.id, fromSide: side)
                        }
                        connecting = nil
                    })
    }

    private func pendingEdge(vp: Viewport) -> some View {
        Canvas { context, _ in
            guard let connecting, let node = store.document.node(connecting.from) else { return }
            let start = vp.toScreen(EdgeGeometry.anchor(node.frame, connecting.side))
            var path = Path()
            path.move(to: start)
            path.addLine(to: connecting.to)
            context.stroke(path, with: .color(Accent.text),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4]))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Viewport

    /// Fit below the top bar, which the desk runs under.
    private func fit(in size: CGSize) {
        guard size.width > 0 else { return }
        let bar: CGFloat = 52
        var vp = Viewport.fitting(store.document.bounds, in: CGSize(width: size.width, height: size.height - bar))
        vp.offset.y += bar
        store.viewport = vp
        store.wantsFit = false
        settled = (vp, nil)
    }

    private func focus(_ id: String?, in size: CGSize, pulse shouldPulse: Bool = true) {
        guard let id, let node = store.document.node(id) else { return }
        store.wantsFit = false
        var vp = store.viewport
        if vp.scale < 0.6 { vp.scale = 1 }
        vp.center(on: node.center, in: size)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5)) {
            store.viewport = vp
        }
        settled = (vp, id)
        if shouldPulse {
            pulse = id
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                if pulse == id { pulse = nil }
            }
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
