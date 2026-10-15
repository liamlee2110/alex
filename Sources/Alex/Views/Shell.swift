import SwiftUI
import AppKit

// The shell's own pieces (PLAN.md, revisions 16 and 21): the divider you
// can drag, and the pointer over it.

/// A divider you can drag: the hairline between the sidebar and the desk,
/// or, with no line, the detail sheet's leading edge. Nothing is drawn for
/// the grab itself — the pointer is what says the edge moves, as on a
/// window and on a card's edge — and the strip that takes it is wider than
/// the line, on both sides.
struct SplitHandle: View {
    /// The hairline; off where the edge is a floating surface's own.
    var line = true
    /// Called with how far the pointer moved since the last call.
    let onDrag: (CGFloat) -> Void

    @State private var last: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(line ? Ink.hairline : .clear)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: Shell.handle)
                    .contentShape(Rectangle())
                    .hoverCursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                onDrag(value.translation.width - last)
                                last = value.translation.width
                            }
                            .onEnded { _ in last = 0 })
            }
            // The strip reaches over both neighbours; later siblings would
            // otherwise sit above its far half.
            .zIndex(1)
    }
}

/// The pointer over a grip, which is the only thing that says the grip is
/// there, and over a connector's dot. Popped when the view goes as well as
/// when the pointer leaves: the grips go with the selection, and a cursor
/// pushed by a view that has vanished is a resize arrow that never turns
/// back into an arrow.
struct HoverCursor: ViewModifier {
    let cursor: NSCursor

    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed { cursor.push(); pushed = true }
                if !inside, pushed { NSCursor.pop(); pushed = false }
            }
            .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
    }
}

extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursor(cursor: cursor))
    }
}
