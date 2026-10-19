import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The desk: a pan-and-zoom viewport over the open canvas. Groups sit under
/// everything, edges are drawn over the world at its scale (revision 62), nodes
/// outside the visible rect are never built. Every edit here is one call
/// into the store, made when the gesture ends, so one drag is one undo.
struct CanvasView: View {
    @ObservedObject var store: CanvasStore
    /// The quick sketch's desk (revision 59): no zoom bar, and the palette
    /// folded to one glyph in the corner (`ToolCorner`).
    var bare = false
    /// Esc with nothing to put down: the quick sketch puts itself away.
    var onIdleEscape: (() -> Void)? = nil
    /// Given, the style panel is not drawn on the desk: whether it would
    /// be is said here, and the quick sketch floats it outside, at the
    /// window's left (revision 59).
    var onStylePanel: ((Bool) -> Void)? = nil
    @EnvironmentObject private var vault: Vault
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focused: Bool

    @State private var pulse: String?
    @State private var drag: (ids: Set<String>, delta: CGSize)?
    /// A resize under way: the grip, how far the pointer has gone and the
    /// zoom it went at. The frame is worked out where it is read, so ⇧
    /// pressed or let go between two moves reshapes it at once (revision 35).
    @State private var resize: (id: String, grip: Grip, translation: CGSize, scale: CGFloat)?
    @State private var marquee: CGRect?
    @State private var connecting: (from: String, side: CanvasSide, to: CGPoint)?
    /// The side of the block selected alone that the pointer is near
    /// (revision 42): the one side whose connector's dot is out.
    @State private var hoveredSide: CanvasSide?
    /// A shape being dragged out with a shape tool, in desk points, as
    /// pressed and pointed; `constrainedDrawing` is what the shape takes.
    @State private var drawing: (start: CGPoint, current: CGPoint)?
    /// The stroke the Draw tool is laying down, in desk points (revision
    /// 58). A reference, so only its preview redraws at each move.
    @State private var pen = PenStroke()
    /// Whether ⇧ is down: a box drawn or resized keeps its proportions
    /// while it is (revision 35). Read off every pointer move and, through
    /// `EventCatcher`, every change of the keys, so a press between moves
    /// counts.
    @State private var shiftHeld = false
    /// ⌥ during a resize: about the centre (revision 53).
    @State private var optionHeld = false
    /// Arrow-key nudges not yet landed: the nodes and how far, shown live
    /// and written as one move once the keys rest (revision 53).
    @State private var nudge: (ids: Set<String>, delta: CGSize)?
    @State private var nudgeLanding: Task<Void, Never>?
    /// The drag under way carries the copies an ⌥-drag left (revision 53).
    @State private var duplicating = false
    /// The blocks the line or arrow being drawn will attach to, ringed
    /// while it is drawn (revision 34).
    @State private var binding: Set<String> = []
    /// The node being written on in place: a sticky, or a note card that
    /// was double-clicked.
    @State private var editingNode: String?
    /// The node a press is down on, so its selection happens once.
    @State private var pressed: String?
    /// That press added its node with ⇧, so its release keeps it.
    @State private var pressAdded = false
    /// When and where the desk was last tapped, to tell a double-click.
    @State private var lastGroundTap: (time: TimeInterval, point: CGPoint)?
    /// The palette's width and the zoom bar's leading edge as laid out,
    /// for placing the palette at the window's centre and no nearer the
    /// zoom bar than its rim (revision 38). The edge is read in the desk's
    /// space, so no sum of insets can drift from where the bar is.
    @State private var paletteWidth: CGFloat = 0
    @State private var zoomEdge: CGFloat = .infinity
    /// `--edit <vault path>` opens one card's editor (or `--edit <node id>`
    /// a sticky's or a text box's), the way `--hover`
    /// holds one card's chrome open: a snapshot has nothing to click with.
    private static let forcedEdit = Launch.value(after: "--edit")
    /// What the camera last did on purpose — a fit, a focus on a node, a
    /// centring on a remembered point — and the viewport it produced. The
    /// desk is often narrow at launch, before the split view settles, and
    /// the panel comes and goes; if the desk resizes and nobody has panned
    /// since, the same thing is redone at the new size.
    private enum Anchor: Equatable {
        case fit
        case node(String)
        case centre(CGPoint)
    }
    @State private var settled: (viewport: Viewport, anchor: Anchor)?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Nothing here reads the camera (revision 25): what moves with
            // it is in a `CameraStage` or a `CameraReader`, and this body
            // runs only when the canvas, the selection or a gesture does.
            let camera = store.camera
            ZStack(alignment: .topLeading) {
                Ink.desk
                CameraReader(camera: camera) { vp in DotGrid(viewport: vp) }
                    .allowsHitTesting(false)
                EventCatcher(
                    accepts: { point in
                        // Read at the time of the wheel, not of the body.
                        let insets = store.deskInsets
                        return !store.showSearch
                            && point.x >= insets.leading
                            && point.x <= size.width - insets.trailing
                    },
                    onScroll: { delta, point, modifiers in
                        if modifiers.contains(.command) {
                            store.viewport.zoom(by: exp(delta.y * 0.01), around: point)
                        } else {
                            store.viewport.pan(by: delta)
                        }
                    },
                    onMagnify: { magnification, point in
                        store.viewport.zoom(by: 1 + magnification, around: point)
                    },
                    onFlags: { flags in
                        if shiftHeld != flags.contains(.shift) { shiftHeld = flags.contains(.shift) }
                    })
                ground()
                    .modifier(ToolCursor(active: store.tool.draws))
                CameraStage(camera: camera, size: size) {
                    world(visible: store.culled, detail: store.detail)
                }
                // Edges follow a drag, a resize or a nudge as it happens
                // (revision 53), not only once it lands.
                let document = liveDocument(store.document), derived = store.derivedEdges()
                CameraReader(camera: camera) { vp in
                    EdgeLayer(document: document, viewport: vp, derived: derived, selected: store.edgeSelection)
                }
                .allowsHitTesting(false)
                if connecting != nil {
                    CameraReader(camera: camera) { vp in pendingEdge(vp: vp) }
                }
                drawingPreview()
                PenPreview(pen: pen, camera: camera)
                if let marquee {
                    Rectangle()
                        .fill(Accent.wash)
                        .overlay(Rectangle().stroke(Accent.text, lineWidth: 1))
                        .frame(width: marquee.width, height: marquee.height)
                        .position(x: marquee.midX, y: marquee.midY)
                        .allowsHitTesting(false)
                }
                // The desk's own chrome keeps clear of what floats over
                // its edges (revision 21): the zoom bar at the bottom
                // right of what is left, and the palette's pill centred
                // at the window's foot as Figma's toolbar is (revision
                // 38), the link prompt growing up out of it. Where the
                // zoom bar or the sidebar's card would meet the palette,
                // the palette gives way, not the centre.
                let insets = store.deskInsets
                if bare {
                    // The quick sketch's palette (revision 59): one small
                    // glyph in the bottom right corner, its menu the rest.
                    VStack(alignment: .trailing, spacing: Space.s) {
                        if store.showLinkPrompt {
                            LinkPrompt(store: store)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                        }
                        ToolCorner(store: store)
                    }
                    .padding(Shell.gutter)
                    .animation(Motion.quick, value: store.showLinkPrompt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else {
                ZStack(alignment: .bottom) {
                    ZoomControls(store: store, camera: camera)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("desk")).minX } action: { zoomEdge = $0 }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, insets.trailing)
                    VStack(spacing: Space.s) {
                        if store.showLinkPrompt {
                            LinkPrompt(store: store)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                        }
                        ToolPalette(store: store)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { paletteWidth = $0 }
                    }
                    .padding(.bottom, Space.l)
                    .animation(Motion.quick, value: store.showLinkPrompt)
                    .offset(x: paletteShift(in: size.width, insets: insets))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(Motion.move, value: insets)
                }
                // The style panel (revision 39): under the sidebar's head
                // row, clear of its card, while something is selected and
                // at rest.
                ZStack(alignment: .topLeading) {
                    if stylePanelShown, onStylePanel == nil {
                        StylePanel(store: store)
                            .padding(.leading, insets.leading + Shell.gutter)
                            // No head row over the quick sketch's desk.
                            .padding(.top, bare ? Shell.gutter : Shell.gutter + Shell.headRow + Shell.gutter)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(Motion.quick, value: stylePanelShown)
                .animation(Motion.move, value: insets)
                if let trouble = store.trouble {
                    Text(trouble)
                        .font(Typography.meta)
                        .foregroundStyle(Ink.muted)
                        .padding(Space.m)
                        .background(RoundedRectangle(cornerRadius: Radius.well).fill(Ink.float))
                        .elevation(.raised)
                        .padding(Space.l)
                        .padding(.leading, insets.leading)
                        .padding(.bottom, CanvasStore.paletteRoom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            // The one hover the connectors answer to (revision 42): read
            // on the desk, so no hit region is added round a block and a
            // press beside it still lands on the desk and on the grips.
            .onContinuousHover(coordinateSpace: .local) { phase in
                let side: CanvasSide?
                switch phase {
                case .active(let point): side = connectorSide(near: point)
                case .ended: side = nil
                }
                if side != hoveredSide { withAnimation(Motion.quick) { hoveredSide = side } }
            }
            .onChange(of: store.selection) { _, _ in hoveredSide = nil }
            .onChange(of: stylePanelShown, initial: true) { _, shown in onStylePanel?(shown) }
            .coordinateSpace(name: "desk")
            .clipped()
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onDeleteCommand { store.removeSelection() }
            // ⌘C and ⌘X take the selection as a clip (revision 48); an
            // editor's words are its own text view's to copy. With nothing
            // to take the commands are off: SwiftUI empties the pasteboard
            // before any copy action runs, so an action that copies nothing
            // still wipes what the user had copied elsewhere.
            .onCopyCommand(perform: canCopy ? { copySelection(); return [] } : nil)
            .onCutCommand(perform: canCopy ? {
                if copySelection() { store.remove(store.selection) }
                return []
            } : nil)
            // ⌘V mid-view: a clip comes back as a copy, a copied file is
            // imported as a drop would be, a picture becomes a PNG beside
            // the canvas, an address a link card.
            .onPasteCommand(of: [.alexClip, .fileURL, .image, .url, .utf8PlainText, .plainText]) { _ in paste() }
            .onExitCommand {
                // Writing in a box: Esc puts the pen down and leaves the
                // box selected, as Excalidraw's does (revision 50).
                if editingNode != nil { return finishEditing() }
                if let onIdleEscape, store.selection.isEmpty, store.edgeSelection.isEmpty, store.tool == .select, drawing == nil {
                    return onIdleEscape()
                }
                store.select(nil)
                store.setTool(.select)
                drawing = nil
                pen.points = []
                binding = []
                editingNode = nil
            }
            // The tools' keys (revision 15), on the desk and never in an
            // editor: one bare letter or digit per tool, `ToolKeys`' since
            // revision 40, so Settings can change them.
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                guard editingNode == nil, press.modifiers.isEmpty,
                      let tool = ToolKeys.shared.tool(for: press.characters) else { return .ignored }
                store.pressTool(tool)
                return .handled
            }
            // ↩ on one selected box writes in it (revision 50), as
            // Excalidraw's Enter does for a text or a shape: what a
            // double-click on it would do, wherever the pointer is.
            .onKeyPress(.return, phases: .down) { press in
                guard editingNode == nil, press.modifiers.isEmpty, store.selection.count == 1,
                      let id = store.selection.first,
                      let node = store.document.nodes.first(where: { $0.id == id }),
                      writable(node) else { return .ignored }
                editingNode = id
                return .handled
            }
            // Arrow keys nudge the selection, ⇧ by five (revision 53).
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                guard editingNode == nil, !store.selection.isEmpty, store.tool == .select,
                      // An arrow key always carries the keypad and function
                      // flags; only ⌘, ⌥ and ⌃ make it another key.
                      press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                nudgeSelection(press.key, large: press.modifiers.contains(.shift))
                return .handled
            }
            // ⇧2 zooms to the selection, Excalidraw's key: on the desk only,
            // never as a menu shortcut, which would take "@" from an editor.
            .onKeyPress(phases: .down) { press in
                guard editingNode == nil, press.modifiers == .shift, !store.selection.isEmpty,
                      press.characters == "@" || press.characters == "2" else { return .ignored }
                zoomToSelection(in: size)
                return .handled
            }
            .dropDestination(for: URL.self) { urls, location in
                store.importFiles(urls, at: store.viewport.toWorld(location))
                return true
            }
            .onChange(of: store.focusRequest) { _, id in focus(id, in: size) }
            .onChange(of: store.findFocus) { _, id in
                guard let id else { return }
                focus(id, in: size, pulse: false)
                store.findFocus = nil
            }
            // A fit asked for once the desk is up is a camera move; the
            // first one is where the desk starts, and starts there.
            .onChange(of: store.wantsFit) { _, wants in if wants { fit(in: size, animated: settled != nil) } }
            .onChange(of: store.restoredCentre) { _, point in if let point { recentre(on: point, in: size) } }
            .onChange(of: store.zoomStep) { _, step in if let step { zoom(step, in: size) } }
            .onChange(of: size) { _, new in
                Trace.log("size -> \(new) wantsFit=\(store.wantsFit) settled=\(String(describing: settled?.viewport)) viewport=\(store.viewport)")
                store.viewSize = new
                resettle(in: new, animated: false)
            }
            // The floating sidebar came or went (revision 21): the desk is
            // the same size, but a fit or a focus nobody has panned away
            // from is redone in what is left of it. A remembered centre
            // stays where it is; the chrome floats over. The sheet coming
            // or going moves nothing (revision 43): a card picked to read
            // stays where it was picked, and the sheet floats over the
            // rest. Only a reveal's card, focused to be read, makes room
            // for the sheet that opens on it.
            .onChange(of: store.deskInsets) { old, new in
                if case .centre = settled?.anchor { return }
                if !store.wantsFit, old.leading == new.leading, old.top == new.top,
                   old.bottom == new.bottom {
                    guard case .node(let id) = settled?.anchor, new.trailing > old.trailing,
                          store.selection == [id] else { return }
                }
                resettle(in: size, animated: settled != nil)
            }
            .onChange(of: store.selection) { _, selection in
                if let node = editingNode, !selection.contains(node) { editingNode = nil }
                if let pending = nudge, pending.ids != carried(selection) { landNudge() }
            }
            .onAppear {
                // The quick sketch takes keys the moment it is up: there is
                // nothing to click first (revision 59).
                if bare { DispatchQueue.main.async { focused = true } }
                store.undoManager = undoManager
                store.viewSize = size
                if store.wantsFit {
                    fit(in: size, animated: false)
                } else if let point = store.restoredCentre {
                    recentre(on: point, in: size)
                }
                focus(store.focusRequest, in: size, animated: false)
                Bench.start(store: store)
            }
        }
    }

    /// Whether ⌘C and ⌘X have anything on the desk to take.
    private var canCopy: Bool { editingNode == nil && !store.selection.isEmpty }

    /// The selection onto the pasteboard: the clip under Alex's own
    /// type, its words as text for any other app, else its cards' files.
    @discardableResult
    private func copySelection() -> Bool {
        guard editingNode == nil, let clip = store.clip(store.selection), let data = clip.data else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: NSPasteboard.PasteboardType(CanvasClip.pasteboardType))
        if let text = clip.plainText { board.setString(text, forType: .string) }
        let files = clip.files.compactMap { store.vault.url(for: $0) }
        if clip.plainText == nil, !files.isEmpty { board.writeObjects(files as [NSURL]) }
        return true
    }

    private func paste() {
        let board = NSPasteboard.general
        if let data = board.data(forType: NSPasteboard.PasteboardType(CanvasClip.pasteboardType)),
           let clip = CanvasClip(data: data) {
            store.paste(clip)
            return
        }
        // A clip from Excalidraw is JSON text (revision 57); its own MIME
        // type stays inside Chromium's private pasteboard blob.
        if let text = board.string(forType: .string), let scene = ExcalidrawClip(text: text) {
            store.paste(scene)
            return
        }
        // A file copied in Finder also offers its name as text, and a picture
        // copied in a browser its address, so the file and the picture come
        // first.
        if let urls = board.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let centre = store.viewport.toWorld(CGPoint(x: store.viewSize.width / 2, y: store.viewSize.height / 2))
            store.importFiles(urls, at: centre)
            if let id = store.selection.first { store.focusRequest = id }
            return
        }
        if let image = (board.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let pixels = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            if let node = store.pasteImage(png: png, pixels: pixels) { store.focusRequest = node.id }
            return
        }
        guard let held = board.string(forType: .URL) ?? board.string(forType: .string) else { return }
        if let node = store.addLink(held, at: nil) {
            store.focusRequest = node.id
            return
        }
        // Any other words, copied out of a box or from anywhere, are a
        // text box, as Excalidraw and FigJam make of pasted text.
        store.pasteText(held, size: pastedTextSize(held))
    }

    /// The box pasted words need: their own width up to a column's, and
    /// as many lines as they wrap to, with the box's inset round them.
    private func pastedTextSize(_ text: String) -> CGSize {
        let font = DeskFace.font(CanvasNode.shape(.text, frame: .zero).fontFamily, size: Typography.bodySize)
        let inset = Space.xs * 2
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: Placement.pastedTextWidth - inset, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let line = Typography.lineHeight(ofSize: Typography.bodySize)
        return CGSize(width: max(ceil(bounds.width) + inset + Space.xs, ShapeMetrics.defaultTextSize.width),
                      height: max(ceil(bounds.height) + inset + line, ShapeMetrics.defaultTextSize.height))
    }

    // MARK: - The ground: deselect, marquee, new sticky

    private func ground() -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("desk"))
                    .onChanged { value in
                        if store.tool.draws {
                            noteDrawing(value)
                            return
                        }
                        marquee = CGRect(x: min(value.startLocation.x, value.location.x),
                                         y: min(value.startLocation.y, value.location.y),
                                         width: abs(value.location.x - value.startLocation.x),
                                         height: abs(value.location.y - value.startLocation.y))
                    }
                    .onEnded { _ in
                        let vp = store.viewport
                        if store.tool == .pen { finishStroke(vp: vp); return }
                        if let current = constrainedDrawing { finishDrawing(current, vp: vp); return }
                        guard let rect = marquee else { return }
                        marquee = nil
                        let world = CGRect(origin: vp.toWorld(rect.origin),
                                           size: CGSize(width: rect.width / vp.scale, height: rect.height / vp.scale))
                        let hits = store.document.nodes
                            .filter { $0.kind != .group && $0.frame.intersects(world) }
                            .map(\.id)
                        let additive = NSEvent.modifierFlags.contains(.shift)
                        store.selection = additive ? store.selection.union(hits) : Set(hits)
                        if !additive { store.edgeSelection = [] }
                        focused = true
                    })
            // A tap, not a press: a second drag gesture on the desk, even a
            // simultaneous one, kept the marquee's and the tap from firing.
            // With no double-tap here to wait for, it answers at release.
            .onTapGesture { point in
                if store.tool.draws {
                    placeByClick(at: store.viewport.toWorld(point))
                    focused = true
                    return
                }
                tapGround(at: point)
            }
    }

    /// A tap on the desk empties the selection, unless ⇧ is held. The
    /// second click of a double-click inside a shape whose inside is the
    /// desk's — an empty outline — writes in it, as a double-click on the
    /// shape itself does (revision 53); Excalidraw finds the container
    /// under a double-click the same way.
    private func tapGround(at point: CGPoint) {
        focused = true
        let world = store.viewport.toWorld(point)
        // Counted here: by the time a tap fires, the app's current event
        // can be a pointer move, whose click count says nothing.
        let now = ProcessInfo.processInfo.systemUptime
        let double = lastGroundTap.map {
            now - $0.time <= NSEvent.doubleClickInterval && hypot(point.x - $0.point.x, point.y - $0.point.y) <= 4
        } ?? false
        lastGroundTap = double ? nil : (now, point)
        if double, let shape = hollowShape(at: world) {
            store.select(shape.id)
            editingNode = shape.id
            return
        }
        store.showLinkPrompt = false
        store.showNewWorkspace = false
        editingNode = nil
        // A press on an edge's line picks it (revision 62), within the
        // reach a drawn line's press has, ⇧ adding it or taking it away.
        let shift = NSEvent.modifierFlags.contains(.shift)
        if let edge = EdgeGeometry.hit(store.document, at: world, reach: Handle.strokeHit / store.viewport.scale) {
            store.selectEdge(edge.id, adding: shift)
            return
        }
        if !shift { store.select(nil) }
    }

    /// The topmost rectangle, ellipse or diamond whose outline holds `world`.
    private func hollowShape(at world: CGPoint) -> CanvasNode? {
        store.document.nodes.reversed().first { node in
            guard let kind = node.shape, kind != .line, kind != .text, node.frame.contains(world) else { return false }
            return ShapeNodeView.outline(kind, in: node.frame).contains(world)
        }
    }

    // MARK: - Drawing (revision 15)

    /// A shape tool pressed without a drag: the default size, where the
    /// desk was clicked; the text tool: a line's box from there; the sticky
    /// tool: a sticky note there. Either is ready to write.
    private func placeByClick(at world: CGPoint) {
        switch store.tool {
        case .draw(let tool):
            store.draw(tool, from: world, to: world)
        case .pen:
            // A click with the pen is a dot, as Excalidraw's is.
            store.drawFreehand([world])
        case .text:
            let node = store.addText(from: world, to: world)
            editingNode = node.id
        case .sticky:
            let node = store.addSticky(at: world)
            editingNode = node.id
            store.setTool(.select)
        default:
            break
        }
    }

    /// A shape tool's drag, wherever it began: the raw points, with ⇧ read
    /// now so the preview is right before the keys next change.
    private func noteDrawing(_ value: DragGesture.Value) {
        if store.tool == .pen {
            if pen.points.isEmpty { pen.points.append(value.startLocation) }
            pen.points.append(value.location)
            return
        }
        shiftHeld = Self.shiftIsDown
        drawing = (value.startLocation, value.location)
        noteBinding()
    }

    /// Whether ⇧ is down, read off the pointer event in hand when there is
    /// one — its flags are the keys as they were when it was made, real or
    /// posted — and off the keyboard otherwise.
    /// Whether ⌥ is down, read as ⇧ is.
    private static var optionIsDown: Bool {
        if let event = NSApp.currentEvent,
           [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
            return event.modifierFlags.contains(.option)
        }
        return NSEvent.modifierFlags.contains(.option)
    }

    private static var shiftIsDown: Bool {
        if let event = NSApp.currentEvent,
           [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
            return event.modifierFlags.contains(.shift)
        }
        return NSEvent.modifierFlags.contains(.shift)
    }

    /// The drag as the shape takes it: as pressed and pointed, or with ⇧
    /// held in proportion (revision 35), the way Figma, FigJam and
    /// Excalidraw do — a line on its nearest 15° step, any other box a
    /// square. A sticky has one size and takes the press alone.
    private var constrainedDrawing: (start: CGPoint, current: CGPoint)? {
        guard let drawing else { return nil }
        guard shiftHeld else { return drawing }
        switch store.tool {
        case .draw(.line), .draw(.arrow):
            return (drawing.start, Proportion.stepped(from: drawing.start, to: drawing.current))
        case .draw, .text:
            return (drawing.start, Proportion.square(from: drawing.start, to: drawing.current))
        default:
            return drawing
        }
    }

    /// The pen lifted: the stroke, in world units, is written as one node.
    private func finishStroke(vp: Viewport) {
        let points = pen.points.map(vp.toWorld)
        pen.points = []
        store.drawFreehand(points)
        focused = true
    }

    private func finishDrawing(_ current: (start: CGPoint, current: CGPoint), vp: Viewport) {
        drawing = nil
        binding = []
        let a = vp.toWorld(current.start), b = vp.toWorld(current.current)
        switch store.tool {
        case .draw(let tool):
            store.draw(tool, from: a, to: b, reach: Handle.bindReach / vp.scale,
                       bind: !NSEvent.modifierFlags.contains(.command))
        case .text:
            let node = store.addText(from: a, to: b)
            editingNode = node.id
        case .sticky:
            let node = store.addSticky(at: a)
            editingNode = node.id
            store.setTool(.select)
        default:
            break
        }
    }

    /// While a line or an arrow is drawn, the blocks its ends will attach
    /// to: both, or none, since an edge needs two (⌘ held: none).
    private func noteBinding() {
        guard let drawing = constrainedDrawing, case .draw(let tool) = store.tool, tool == .line || tool == .arrow,
              !NSEvent.modifierFlags.contains(.command) else {
            if !binding.isEmpty { binding = [] }
            return
        }
        let vp = store.viewport, reach = Handle.bindReach / vp.scale
        var next: Set<String> = []
        if let from = store.bindTarget(vp.toWorld(drawing.start), reach: reach),
           let to = store.bindTarget(vp.toWorld(drawing.current), reach: reach, excluding: [from.id]) {
            next = [from.id, to.id]
        }
        if next != binding { binding = next }
    }

    /// The shape being dragged out, as a dashed outline in the accent.
    private func drawingPreview() -> some View {
        Canvas { context, _ in
            guard let drawing = constrainedDrawing else { return }
            let a = drawing.start, b = drawing.current
            let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                             width: abs(b.x - a.x), height: abs(b.y - a.y))
            let path: Path
            switch store.tool {
            case .draw(.line), .draw(.arrow):
                path = ShapeNodeView.polyline([a, b])
            case .draw(let tool):
                path = ShapeNodeView.outline(tool.kind, in: box)
            case .text:
                path = ShapeNodeView.outline(.rectangle, in: box)
            default:
                return
            }
            context.stroke(path, with: .color(Accent.text),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4]))
        }
        .allowsHitTesting(false)
    }

    // MARK: - The world layer

    /// Built from the store alone: `CameraStage` moves it, and the only
    /// camera it knows is the culled rect and the detail step, which a pan
    /// or a pinch changes only now and then.
    private func world(visible: CGRect, detail: CGFloat) -> some View {
        let nodes = store.document.nodes
        let groups = nodes.filter { $0.kind == .group && $0.frame.intersects(visible) }
        let others = nodes.filter { $0.kind != .group && $0.frame.intersects(visible) }
        return ZStack(alignment: .topLeading) {
            ForEach(groups) { node in
                let frame = liveFrame(node)
                GroupNodeView(node: node, selected: store.selection.contains(node.id))
                    .findRing(store.findNodes.contains(node.id), current: store.findCurrentNode == node.id)
                    .overlay {
                        if store.selection.contains(node.id) {
                            CameraReader(camera: store.camera) { vp in
                                handles(for: node, vp: vp, alone: store.selection.count == 1)
                            }
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .animation(frameMotion, value: frame)
                    .gesture(dragGesture(for: node))
                    .simultaneousGesture(pressGesture(for: node))
                    // Outermost, so a card's own taps and drag do not
                    // take the right press first.
                    .popupMenu { NodeMenu.items(for: node, store: store) }
            }
            ForEach(others) { node in
                let frame = liveFrame(node)
                nodeView(node, zoom: detail)
                    .findRing(store.findNodes.contains(node.id), current: store.findCurrentNode == node.id)
                    .pulseRing(pulse == node.id)
                    .overlay {
                        if binding.contains(node.id) {
                            RoundedRectangle(cornerRadius: Radius.card)
                                .stroke(Accent.text, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .padding(-6)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if store.selection == [node.id], node.kind == .file, let file = node.file {
                            CameraReader(camera: store.camera) { vp in appearsBadge(for: file, vp: vp) }
                        }
                    }
                    .overlay {
                        if store.selection.contains(node.id) {
                            CameraReader(camera: store.camera) { vp in
                                handles(for: node, vp: vp, alone: store.selection.count == 1)
                            }
                        }
                    }
                    .overlay {
                        if showsConnectors(node) {
                            CameraReader(camera: store.camera) { vp in connectors(for: node, vp: vp) }
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .animation(frameMotion, value: frame)
                    .gesture(dragGesture(for: node))
                    .simultaneousGesture(pressGesture(for: node))
                    // Outermost, so a card's own taps and drag do not
                    // take the right press first.
                    .popupMenu { NodeMenu.items(for: node, store: store) }
            }
        }
    }

    /// A frame follows the pointer live while a drag or a resize is on;
    /// a frame that changed with no pointer on it — a fold, an undo, an
    /// arrange, the door's `update_card` — moves to where it went (law 9).
    private var frameMotion: Animation? {
        drag == nil && resize == nil ? Motion.move : nil
    }

    /// The document as the desk shows it mid-gesture: each node in its
    /// live frame. The document itself when nothing is under way.
    private func liveDocument(_ doc: CanvasDocument) -> CanvasDocument {
        guard drag != nil || resize != nil || nudge != nil else { return doc }
        var live = doc
        for i in live.nodes.indices {
            let frame = liveFrame(live.nodes[i])
            if frame != live.nodes[i].frame { live.nodes[i].frame = frame }
        }
        return live
    }

    private func liveFrame(_ node: CanvasNode) -> CGRect {
        var frame = node.frame
        if let drag, drag.ids.contains(node.id) {
            frame = frame.offsetBy(dx: drag.delta.width, dy: drag.delta.height)
        }
        if let nudge, nudge.ids.contains(node.id) {
            frame = frame.offsetBy(dx: nudge.delta.width, dy: nudge.delta.height)
        }
        if let resized = resizedFrame(node) {
            frame = resized
        }
        return frame
    }

    /// The frame a resize under way gives `node`, from the grip's travel at
    /// the zoom it was dragged at, in proportion while ⇧ is down; nil when
    /// the node is not the one being resized. A folded card's height is
    /// the fold's, so ⇧ leaves it alone.
    private func resizedFrame(_ node: CanvasNode) -> CGRect? {
        guard let resize, resize.id == node.id else { return nil }
        return resize.grip.resizing(node.frame, by: resize.translation, scale: resize.scale,
                                    floor: Grip.floor(for: node), proportional: shiftHeld && !node.folded,
                                    fromCentre: optionHeld)
    }

    /// A card for a file that is not there cannot be written on: the editor
    /// would open empty and save that emptiness over nothing.
    private func missingFile(_ path: String) -> Bool { !vault.exists(path) }

    /// What ↩ can write in: a shape, a text box, a sticky, or a note's
    /// card whose file is there — the boxes a double-click writes in.
    private func writable(_ node: CanvasNode) -> Bool {
        switch node.kind {
        case .text:
            return node.takesWords
        case .file:
            guard let path = node.file, !store.isDirectoryNode(node) else { return false }
            return VaultEntry.Kind.forExtension((path as NSString).pathExtension) == .markdown
                && !missingFile(path)
        default:
            return false
        }
    }

    /// Esc or ⌘↩ in a box's editor: the words are saved as the editor
    /// leaves, the box stays selected, and the desk has the keys again.
    private func finishEditing() {
        editingNode = nil
        focused = true
    }

    private func select(_ node: CanvasNode) {
        // A card pressed with a shape tool picked: the card wins, and the
        // tool hands back rather than wait for a press that is not coming.
        if store.tool.draws { store.setTool(.select) }
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
            let kind: VaultEntry.Kind = store.isDirectoryNode(node)
                ? .directory : .forExtension((path as NSString).pathExtension)
            let preview = kind.isTextual
                ? store.preview(for: path)
                : CardPreview(title: VaultPath.name(of: path), lines: [], frontmatter: Frontmatter())
            CardNodeView(node: node, path: path, kind: kind, preview: preview,
                         url: vault.url(for: path), missing: !vault.exists(path), selected: selected,
                         zoom: zoom, tint: store.tint(for: node),
                         editing: editingNode == node.id || Self.forcedEdit == path,
                         store: store, onDone: finishEditing)
                .onTapGesture(count: 2) {
                    if kind == .directory {
                        // A folder card from before revision 20: the
                        // panel lists what it holds.
                        store.reveal(path)
                    } else if kind == .canvas {
                        store.openCanvas(at: path)
                    } else if kind == .markdown, !missingFile(path) {
                        store.select(node.id)
                        editingNode = node.id
                    }
                }
        case .text:
            if node.shape != nil {
                ShapeNodeView(node: node, selected: selected, editing: editingNode == node.id || Self.forcedEdit == node.id, zoom: zoom,
                              onChange: { text in store.setText(node.id, text) },
                              onTextSize: { store.setFontSize([node.id], $0) },
                              onFamily: { store.setFontFamily([node.id], $0) },
                              onDone: finishEditing,
                              onBegin: { store.beginWriting(node.id) },
                              onEnd: { store.endWriting(node.id, $0) })
                        .onTapGesture(count: 2) {
                        guard node.takesWords else { return }
                        store.select(node.id)
                        editingNode = node.id
                    }
            } else {
                StickyNodeView(node: node, selected: selected, editing: editingNode == node.id || Self.forcedEdit == node.id, zoom: zoom,
                               onChange: { text in store.setText(node.id, text) },
                               onTextSize: { store.setFontSize([node.id], $0) },
                               onFamily: { store.setFontFamily([node.id], $0) },
                              onDone: finishEditing,
                              onBegin: { store.beginWriting(node.id) },
                              onEnd: { store.endWriting(node.id, $0) })
                        .onTapGesture(count: 2) {
                        store.select(node.id)
                        editingNode = node.id
                    }
            }
        case .link:
            LinkNodeView(node: node, selected: selected)
        case .group:
            EmptyView()
        case .other:
            UnknownNodeView(node: node, selected: selected)
        }
    }

    /// Heptabase's "Appears in N whiteboards", above the selected card,
    /// listing the other canvases that carry this file.
    @ViewBuilder
    private func appearsBadge(for file: String, vp: Viewport) -> some View {
        let others = vault.index().canvases(for: file).filter { $0 != store.canvasPath }
        if !others.isEmpty {
            MenuButton(name: "Appears in", placement: .below) {
                for canvas in others {
                    MenuItem(VaultPath.parent(of: canvas).isEmpty ? vault.name : VaultPath.parent(of: canvas)) {
                        store.openCanvas(at: canvas)
                        if let node = store.node(forFile: file) { store.select(node.id); store.focusRequest = node.id }
                    }
                }
            } label: { _ in
                HStack(spacing: Space.xs) {
                    GlyphImage(.arrowUpRight, size: Icon.micro, weight: .medium)
                    Text("Appears in \(others.count + 1) canvases")
                }
                    .font(Typography.micro)
                    .foregroundStyle(Accent.text)
                    // Clear of the outline and of the corner square beside it.
                    .padding(.bottom, Space.s)
                    .padding(.trailing, Handle.corner)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .scaleEffect(1 / vp.scale, anchor: .bottomTrailing)
            // Its bottom-trailing corner pinned to the card's top-trailing
            // one: an alignment guide does not reach out of `CameraReader`.
            .frame(width: 0, height: 0, alignment: .bottomTrailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    // MARK: - Gestures

    /// A press selects on the way down, as Excalidraw's pointer-down
    /// does, rather than after a tap has waited out the double-click a
    /// box also answers (revision 51). ⇧ adds an unselected node at the
    /// press and takes a selected one away only on a release that did not
    /// move, so a ⇧-drag carries the whole selection; pressed inside a
    /// selection of several, the selection stays for a drag and narrows
    /// to this one on a release that did not move. With a shape
    /// tool picked the press waits for its release, since a drag from a
    /// card draws from there.
    private func pressGesture(for node: CanvasNode) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("desk"))
            .onChanged { value in
                guard value.translation == .zero, pressed != node.id else { return }
                pressed = node.id
                guard !store.tool.draws else { return }
                if NSEvent.modifierFlags.contains(.shift) {
                    if !store.selection.contains(node.id) {
                        store.selection.insert(node.id)
                        pressAdded = true
                    }
                } else if !store.selection.contains(node.id) {
                    store.select(node.id)
                }
                focused = true
            }
            .onEnded { value in
                let added = pressAdded
                pressed = nil
                pressAdded = false
                let still = hypot(value.translation.width, value.translation.height) < 4
                guard still else { return }
                if store.tool == .pen {
                    store.drawFreehand([store.viewport.toWorld(value.location)])
                } else if store.tool.draws {
                    select(node)
                } else if NSEvent.modifierFlags.contains(.shift) {
                    if !added { store.selection.remove(node.id) }
                } else if store.selection.count > 1 {
                    store.select(node.id)
                }
            }
    }

    private func dragGesture(for node: CanvasNode) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("desk"))
            .onChanged { value in
                // A drag that starts on a card with a shape tool picked
                // draws the shape from there: an arrow between two cards
                // begins on one of them.
                if store.tool.draws {
                    noteDrawing(value)
                    return
                }
                if drag == nil {
                    landNudge()
                    var ids: Set<String> = store.selection.contains(node.id) ? store.selection : [node.id]
                    if !store.selection.contains(node.id) { store.select(node.id) }
                    // ⌥ leaves a copy behind once the drag is plainly one
                    // (Excalidraw's): the copies are what moves, the
                    // originals stay where they were.
                    if Self.optionIsDown {
                        guard hypot(value.translation.width, value.translation.height)
                                >= ShapeMetrics.duplicateDragThreshold else { return }
                        if let copies = store.beginDuplicateDrag(ids) {
                            ids = copies
                            duplicating = true
                        }
                    }
                    drag = (carried(ids), .zero)
                }
                drag?.delta = dragDelta(value.translation)
            }
            .onEnded { value in
                let vp = store.viewport
                if store.tool == .pen { finishStroke(vp: vp); return }
                if let current = constrainedDrawing { finishDrawing(current, vp: vp); return }
                guard let current = drag else { return }
                drag = nil
                let delta = dragDelta(value.translation)
                if duplicating {
                    duplicating = false
                    store.endDuplicateDrag(by: delta)
                } else if abs(delta.width) > 0.5 || abs(delta.height) > 0.5 {
                    store.move(current.ids, by: delta)
                }
            }
    }

    /// A drag's travel on the desk; with ⇧ held, along one axis only, the
    /// one it has gone further on (revision 53, Excalidraw's).
    private func dragDelta(_ translation: CGSize) -> CGSize {
        let scale = store.viewport.scale
        var delta = CGSize(width: translation.width / scale, height: translation.height / scale)
        if Self.shiftIsDown {
            if abs(delta.width) >= abs(delta.height) { delta.height = 0 } else { delta.width = 0 }
        }
        return delta
    }

    /// The nodes a move of `ids` carries: a section takes what it holds.
    private func carried(_ ids: Set<String>) -> Set<String> {
        var all = ids
        for id in ids {
            if let group = store.document.node(id), group.kind == .group {
                all.formUnion(store.nodeIDs(inside: group.frame))
            }
        }
        return all
    }

    // MARK: - Keys on the desk (revision 53)

    /// An arrow key moves the selection a point, five with ⇧; a run of
    /// presses shows at once and lands as one move when the keys rest.
    private func nudgeSelection(_ key: KeyEquivalent, large: Bool) {
        let step = large ? ShapeMetrics.nudgeLarge : ShapeMetrics.nudge
        let by: CGSize
        switch key {
        case .upArrow: by = CGSize(width: 0, height: -step)
        case .downArrow: by = CGSize(width: 0, height: step)
        case .leftArrow: by = CGSize(width: -step, height: 0)
        default: by = CGSize(width: step, height: 0)
        }
        let ids = carried(store.selection)
        if let pending = nudge, pending.ids != ids { landNudge() }
        let delta = nudge?.delta ?? .zero
        nudge = (ids, CGSize(width: delta.width + by.width, height: delta.height + by.height))
        nudgeLanding?.cancel()
        nudgeLanding = Task {
            try? await Task.sleep(for: ShapeMetrics.nudgeSettle)
            guard !Task.isCancelled else { return }
            landNudge()
        }
    }

    /// The nudges so far, written as one move.
    private func landNudge() {
        nudgeLanding?.cancel()
        nudgeLanding = nil
        guard let pending = nudge else { return }
        nudge = nil
        store.move(pending.ids, by: pending.delta)
    }

    /// ⇧2: the selection fills the view (Excalidraw's zoom to selection).
    private func zoomToSelection(in size: CGSize) {
        let frames = store.document.nodes.filter { store.selection.contains($0.id) }.map(\.frame)
        guard let first = frames.first, size.width > 0 else { return }
        let rect = frames.dropFirst().reduce(first) { $0.union($1) }
        var vp = Viewport.fitting(rect, in: open(size))
        vp.offset.x += store.deskInsets.leading
        vp.offset.y += store.deskInsets.top
        withAnimation(Motion.camera) { store.viewport = vp }
        store.wantsFit = false
        settled = (vp, .centre(CGPoint(x: rect.midX, y: rect.midY)))
    }

    /// The style panel stands while something is selected and at rest
    /// (revision 39): not while a selected node is written in, nor while
    /// anything is moved, resized, drawn, connected from or marqueed over.
    private var stylePanelShown: Bool {
        !(store.selection.isEmpty && store.edgeSelection.isEmpty) && store.tool == .select
            && drag == nil && resize == nil && drawing == nil && connecting == nil && marquee == nil
            && editingNode.map { !store.selection.contains($0) } != false
    }

    /// Where the palette stands (revision 38): at the window's centre,
    /// moved left only as far as keeps it clear of the zoom bar, and right
    /// only as far as keeps it clear of the sidebar's card.
    private func paletteShift(in width: CGFloat, insets: CanvasStore.Insets) -> CGFloat {
        let centre = width / 2
        var shift = min(0, zoomEdge - (centre + paletteWidth / 2))
        let leftEdge = insets.leading + Space.l
        shift = max(shift, leftEdge - (centre - paletteWidth / 2))
        return shift
    }

    /// A selected node's furniture, Figma's: a square outline one point
    /// wide at every zoom, over the node's own rounded corners, and when it
    /// is selected alone the grips and a square at each corner, drawn under
    /// the grips so the invisible corner grip over each one is what the
    /// pointer takes. A folded card keeps its two side bands and no
    /// corners, its height being the fold's.
    private func handles(for node: CanvasNode, vp: Viewport, alone: Bool) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(Accent.text, lineWidth: Handle.outline / vp.scale)
                .allowsHitTesting(false)
            if alone {
                if !node.folded { cornerMarks(vp: vp) }
                resizeGrips(for: node, vp: vp)
            }
        }
    }

    private func cornerMarks(vp: Viewport) -> some View {
        ZStack {
            ForEach([Grip.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { corner in
                Rectangle()
                    .fill(Ink.card)
                    .overlay(Rectangle().strokeBorder(Accent.text, lineWidth: 1))
                    .frame(width: Handle.corner, height: Handle.corner)
                    .scaleEffect(1 / vp.scale)
                    .frame(width: Handle.corner / vp.scale, height: Handle.corner / vp.scale)
                    .offset(x: corner.normal.x * Handle.corner / 2 / vp.scale,
                            y: corner.normal.y * Handle.corner / 2 / vp.scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            }
        }
        .allowsHitTesting(false)
    }

    /// A block selected alone and at rest has a connector on each side
    /// (FigJam's): drag its dot onto another block to connect the two. Not
    /// on a section or a line, and not while it is written in.
    private func showsConnectors(_ node: CanvasNode) -> Bool {
        store.tool == .select && store.selection == [node.id] && !node.isStroke
            && editingNode != node.id && drag == nil && resize == nil
    }

    /// Only the side the pointer is near shows its dot (revision 42), and
    /// the side a connection is being dragged from keeps it out.
    private func connectors(for node: CanvasNode, vp: Viewport) -> some View {
        ZStack {
            ForEach([CanvasSide.top, .right, .bottom, .left], id: \.self) { side in
                if hoveredSide == side || (connecting?.from == node.id && connecting?.side == side) {
                    connector(for: node, side: side, vp: vp)
                        .transition(.opacity)
                }
            }
        }
    }

    /// The side of the block selected alone that `point`, on the desk, is
    /// near; nil when no block shows connectors or the pointer is nowhere
    /// near one of its sides. Reads the viewport at the time of the hover,
    /// not of the body, like a gesture does.
    private func connectorSide(near point: CGPoint) -> CanvasSide? {
        guard store.selection.count == 1, let id = store.selection.first,
              let node = store.document.node(id), node.kind != .group, showsConnectors(node)
        else { return nil }
        let vp = store.viewport
        return CanvasSide.near(vp.toWorld(point), node.frame,
                               inside: Handle.connectorInside / vp.scale,
                               outside: Handle.connectorOutside / vp.scale)
    }

    /// Every grip a node gets. A folded card keeps the two side bands,
    /// because its height is the fold's to set and not the grip's.
    private func resizeGrips(for node: CanvasNode, vp: Viewport) -> some View {
        ForEach(node.folded ? Grip.sides : Grip.allCases, id: \.self) { grip in
            resizeGrip(grip, for: node, vp: vp)
        }
    }

    /// One grip, constant on screen whatever the zoom, and drawn as nothing.
    /// A corner is a square of edge where two bands meet and a side is the
    /// run between them, so the one expression sizes all eight. Nothing is
    /// drawn because nothing needs to be: the pointer over an edge is what
    /// says the edge resizes, the way it does on a window.
    private func resizeGrip(_ grip: Grip, for node: CanvasNode, vp: Viewport) -> some View {
        let reach = Self.grip / vp.scale
        // The pointer, the cursor and the gesture belong to the strip alone,
        // so they go on before it is placed: after the full-size frame they
        // would answer anywhere over the node, and a press in its middle
        // resized it instead of moving it.
        return Rectangle()
            .fill(Color.clear)
            .frame(width: grip.normal.x == 0 ? nil : reach,
                   height: grip.normal.y == 0 ? nil : reach)
            .contentShape(Rectangle())
            .hoverCursor(grip.cursor)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("desk"))
                    .onChanged { value in
                        shiftHeld = Self.shiftIsDown
                        optionHeld = Self.optionIsDown
                        resize = (node.id, grip, value.translation, vp.scale)
                    }
                    .onEnded { _ in
                        if let frame = resizedFrame(node) { store.setFrame(node.id, frame) }
                        resize = nil
                    })
            .offset(x: grip.normal.x * Self.gripStandsOut / vp.scale,
                    y: grip.normal.y * Self.gripStandsOut / vp.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: grip.alignment)
    }

    /// How far a grip reaches on screen, and how far out of the node it is
    /// nudged, so two thirds of it lie over the desk rather than over the
    /// card's own content, where a press means something else.
    private static let grip: CGFloat = 12
    private static let gripStandsOut: CGFloat = 2

    private func connector(for node: CanvasNode, side: CanvasSide, vp: Viewport) -> some View {
        let alignment: Alignment
        switch side {
        case .top: alignment = .top
        case .bottom: alignment = .bottom
        case .left: alignment = .leading
        case .right: alignment = .trailing
        }
        let normal = EdgeGeometry.normal(side)
        // The dot is the corner square's size and weight; the press takes
        // a wider circle round it, and the pointer over it is the
        // crosshair the desk draws with, since a drag from here draws.
        return Circle()
            .fill(Ink.card)
            .overlay(Circle().strokeBorder(Accent.text, lineWidth: Handle.outline))
            .frame(width: Handle.connector, height: Handle.connector)
            .frame(width: Handle.connectorHit, height: Handle.connectorHit)
            .scaleEffect(1 / vp.scale)
            .frame(width: Handle.connectorHit / vp.scale, height: Handle.connectorHit / vp.scale)
            .contentShape(Circle())
            .hoverCursor(.crosshair)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("desk"))
                    .onChanged { value in
                        connecting = (node.id, side, value.location)
                        let target = store.bindTarget(vp.toWorld(value.location),
                                                      reach: Handle.bindReach / vp.scale, excluding: [node.id])
                        let next: Set<String> = target.map { [$0.id] } ?? []
                        if next != binding { binding = next }
                    }
                    .onEnded { value in
                        if let target = store.bindTarget(vp.toWorld(value.location),
                                                         reach: Handle.bindReach / vp.scale, excluding: [node.id]) {
                            store.connect(node.id, target.id, fromSide: side)
                        }
                        connecting = nil
                        binding = []
                    })
            // Placed after the gesture, which would otherwise answer over
            // the whole card (see `resizeGrip`).
            .offset(x: normal.x * Handle.connectorStandsOut / vp.scale,
                    y: normal.y * Handle.connectorStandsOut / vp.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
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

    /// What the desk last did on purpose, done again at its new shape: a
    /// resize, or the sidebar coming or going. Only if nobody has panned
    /// since.
    private func resettle(in size: CGSize, animated: Bool) {
        if store.wantsFit {
            fit(in: size, animated: false)
        } else if let settled, settled.viewport == store.viewport {
            switch settled.anchor {
            case .fit: fit(in: size, animated: animated)
            case .node(let id): focus(id, in: size, pulse: false, animated: animated)
            case .centre(let point): recentre(on: point, in: size)
            }
        }
    }

    /// The part of the desk nothing floats over.
    private func open(_ size: CGSize) -> CGSize {
        let i = store.deskInsets
        return CGSize(width: max(size.width - i.leading - i.trailing, 1),
                      height: max(size.height - i.top - i.bottom, 1))
    }

    /// Fit into what the floating chrome leaves of the desk.
    private func fit(in size: CGSize, animated: Bool) {
        Trace.log("fit size=\(size) bounds=\(store.document.bounds) canvas=\(store.canvasPath)")
        guard size.width > 0 else { return }
        var vp = Viewport.fitting(store.document.bounds, in: open(size))
        vp.offset.x += store.deskInsets.leading
        vp.offset.y += store.deskInsets.top
        withAnimation(animated ? Motion.camera : nil) { store.viewport = vp }
        store.wantsFit = false
        settled = (vp, .fit)
    }

    /// A remembered centre, put under the desk's visual centre at this size.
    /// Never animated: it is where the canvas starts, or where it stays
    /// while the desk round it changes shape.
    private func recentre(on point: CGPoint, in size: CGSize) {
        guard size.width > 0 else { return }
        // A reveal opens a canvas and focuses a card in one turn, and the
        // focus lands first: it is the newer intent, and the remembered
        // centre yields to it.
        if let settled, settled.viewport == store.viewport, case .node = settled.anchor {
            store.restoredCentre = nil
            return
        }
        var vp = store.viewport
        vp.center(on: point, in: size)
        vp.offset.x += store.deskInset.x
        vp.offset.y += store.deskInset.y
        store.restoredCentre = nil
        // A remembered view that has lost the canvas — it moved, or was
        // left looking at empty desk — fits instead (revision 19).
        if vp.share(of: store.document.bounds, in: size) < Viewport.lostShare {
            fit(in: size, animated: false)
            return
        }
        store.viewport = vp
        settled = (vp, .centre(point))
    }

    /// A step of zoom about the desk's centre, on the camera's motion.
    private func zoom(_ step: CanvasStore.ZoomStep, in size: CGSize) {
        var vp = store.viewport
        let centre = CGPoint(x: size.width / 2 + store.deskInset.x,
                             y: size.height / 2 + store.deskInset.y)
        switch step {
        case .closer: vp.zoom(by: 1.2, around: centre)
        case .farther: vp.zoom(by: 1 / 1.2, around: centre)
        case .actualSize: vp.zoom(by: 1 / vp.scale, around: centre)
        }
        withAnimation(Motion.move) { store.viewport = vp }
        store.zoomStep = nil
    }

    private func focus(_ id: String?, in size: CGSize, pulse shouldPulse: Bool = true, animated: Bool = true) {
        guard let id, let node = store.document.node(id) else { return }
        store.wantsFit = false
        // A section (a folder picked in the sidebar) is looked at whole,
        // its label pill included, clear of the floating chrome.
        if node.kind == .group {
            var vp = Viewport.fitting(node.frame.insetBy(dx: 0, dy: -Folders.pill / 2)
                                          .offsetBy(dx: 0, dy: -Folders.pill / 2),
                                      in: open(size))
            vp.offset.x += store.deskInsets.leading
            vp.offset.y += store.deskInsets.top
            withAnimation(animated ? Motion.camera : nil) { store.viewport = vp }
            settled = (vp, .node(id))
            store.focusRequest = nil
            return
        }
        var vp = store.viewport
        // From an overview, only as close as a card reads (revision 19);
        // a jump to actual size lost the place you were looking from.
        if vp.scale < Viewport.readable { vp.scale = Viewport.readable }
        // Centre in what the floating chrome leaves.
        vp.center(on: node.center, in: size)
        vp.offset.x += store.deskInset.x
        vp.offset.y += store.deskInset.y
        Trace.log("focus \(id) size=\(size) -> \(vp)")
        withAnimation(animated ? Motion.camera : nil) {
            store.viewport = vp
        }
        settled = (vp, .node(id))
        // A card that is also picked already wears the selection's ring.
        if shouldPulse, !store.selection.contains(id) {
            pulse = id
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                if pulse == id { pulse = nil }
            }
        }
        store.focusRequest = nil
    }
}

private extension Grip {
    /// The pointer an edge wears. `frameResize` is the system's own — the
    /// arrows a window's edge shows, diagonal ones included, which no pair
    /// of `resizeLeftRight` and `resizeUpDown` can spell.
    var cursor: NSCursor {
        switch self {
        case .left: return .frameResize(position: .left, directions: .all)
        case .right: return .frameResize(position: .right, directions: .all)
        case .top: return .frameResize(position: .top, directions: .all)
        case .bottom: return .frameResize(position: .bottom, directions: .all)
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        }
    }

    var alignment: Alignment {
        switch self {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

private extension View {
    /// ⌘F's mark on the desk (revision 27), Excalidraw's two highlighter
    /// inks: yellow round a node that holds a hit, orange round the one
    /// stepped to.
    func findRing(_ on: Bool, current: Bool) -> some View {
        overlay {
            if on {
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Highlight.color(current ? "orange" : "yellow"), lineWidth: current ? 4 : 3)
                    .padding(-6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: on)
        .animation(Motion.fade, value: current)
    }

    func pulseRing(_ on: Bool) -> some View {
        overlay {
            if on {
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Accent.text, lineWidth: 3)
                    .padding(-10)
                    .transition(.opacity)
            }
        }
        .animation(Motion.fade, value: on)
    }
}

/// The world under the camera (revision 25). The content is built by the
/// canvas view and handed in finished; when the camera moves only this
/// body runs, and the content, the same value as before, is not rebuilt:
/// a pan is a new transform on views that are already there.
struct CameraStage<Content: View>: View {
    @ObservedObject var camera: Camera
    let size: CGSize
    let content: Content

    init(camera: Camera, size: CGSize, @ViewBuilder content: () -> Content) {
        self.camera = camera
        self.size = size
        self.content = content()
    }

    var body: some View {
        let vp = camera.viewport
        content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(vp.scale, anchor: .topLeading)
            .offset(x: vp.offset.x, y: vp.offset.y)
    }
}

/// A view drawn in screen space, rebuilt at every move of the camera: the
/// grid, the edges, the selection's handles. Keep what is in it small.
struct CameraReader<Content: View>: View {
    @ObservedObject var camera: Camera
    @ViewBuilder let content: (Viewport) -> Content

    var body: some View { content(camera.viewport) }
}

/// The desk's dot grid: a lattice in world units drawn in screen space, so
/// it pans with the canvas and spreads with a zoom, doubling while a step
/// would bring the dots closer than the grid's minimum.
struct DotGrid: View {
    let viewport: Viewport

    var body: some View {
        Canvas { context, size in draw(in: context, size: size) }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        var spacing: CGFloat = Grid.spacing * viewport.scale
        while spacing < Grid.minimum { spacing *= 2 }
        let ox: CGFloat = viewport.offset.x.truncatingRemainder(dividingBy: spacing)
        let oy: CGFloat = viewport.offset.y.truncatingRemainder(dividingBy: spacing)
        let r: CGFloat = Grid.dot / 2
        var path = Path()
        var x: CGFloat = ox - spacing
        while x < size.width + spacing {
            var y: CGFloat = oy - spacing
            while y < size.height + spacing {
                path.addEllipse(in: CGRect(x: x - r, y: y - r, width: Grid.dot, height: Grid.dot))
                y += spacing
            }
            x += spacing
        }
        context.fill(path, with: .color(Ink.grid))
    }
}

/// The crosshair over the desk while a shape or text tool is picked, on
/// the same push-and-pop discipline as `HoverCursor`: popped when the
/// pointer leaves, when the tool hands back, and when the view goes.
/// The stroke under the pen (revision 58), in desk points as the pointer
/// went. A class, so a move redraws the preview and not the desk.
final class PenStroke: ObservableObject {
    @Published var points: [CGPoint] = []
}

/// The stroke being drawn, in ink at the regular width at this zoom, as
/// it will land: Excalidraw shows the stroke itself, not an outline.
private struct PenPreview: View {
    @ObservedObject var pen: PenStroke
    @ObservedObject var camera: Camera

    var body: some View {
        Canvas { context, _ in
            guard !pen.points.isEmpty else { return }
            let width = CGFloat(StrokeWidth.regular.rawValue) * camera.viewport.scale
            context.stroke(Path(Freehand.path(pen.points)), with: .color(Ink.primary),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

private struct ToolCursor: ViewModifier {
    let active: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    if active, !pushed { NSCursor.crosshair.push(); pushed = true }
                    if !active, pushed { NSCursor.pop(); pushed = false }
                case .ended:
                    if pushed { NSCursor.pop(); pushed = false }
                }
            }
            .onChange(of: active) { _, now in
                if !now, pushed { NSCursor.pop(); pushed = false }
            }
            .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
    }
}

extension UTType {
    /// A clip of the desk (revision 48), `CanvasClip.pasteboardType`.
    static let alexClip = UTType(exportedAs: CanvasClip.pasteboardType, conformingTo: .json)
}
