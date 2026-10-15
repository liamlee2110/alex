# What to take from Excalidraw — 2026-10-15

Read against Excalidraw at `4c37956` (2026-10-14): `packages/excalidraw`,
`packages/element`, `packages/common`. Three read-only passes (pointer and
selection; text and keys; engine), then the claims acted on below checked
by hand in both trees. Batch A (items 1–4) is built as revisions 51–52; batch B items 5–7 as revision 53.

Excalidraw paths are under `packages/`; Alex paths under `Sources/Alex/`.

## A. Correctness — fix first

1. **Undo puts back the whole document, so it can erase what the door
   wrote.** `registerUndo` keeps `before: CanvasDocument` and undo does
   `store.document = before; store.save()` (Canvas/CanvasStore.swift:828).
   A door write (`noticeDoorWrite`, :406) or an outside edit
   (`outsideChange`, :362) swaps the document without touching the stack,
   so: move a card, Claude adds one through the door, ⌘Z — the move is
   undone *and Claude's card is deleted from disk*.
   Excalidraw records inverse deltas and replays them on the current
   scene; remote updates never enter history (excalidraw/history.ts:117,
   element/src/delta.ts:1390, element/src/store.ts:49).
   **Port:** each undo step holds only the nodes and edges it changed
   (before/after by id) and patches them into whatever `document` is now.
   Cost M.

2. **Each pause while typing is its own undo step and the editors share
   the window's undo stack.** Every 500 ms debounce goes
   `setText` → `update(name: "Edit note")` → `registerUndo`
   (CanvasStore.swift:956, Views/ShapeNode.swift:157). The text views set
   `allowsUndo` (Views/MarkdownEditor.swift:1600) with no
   `undoManager(for:)`, so typing and document snapshots interleave on one
   stack (inferred, not reproduced). Excalidraw updates the element on
   every keystroke without recording and records once on submit
   (excalidraw/components/App.text.ts:269, :339).
   **Port:** the editor keeps its own undo while open; the debounce still
   writes the file (D2) but registers nothing; finishing registers one
   "Edit text" step from the text as it was when editing began. Cost M.
   With it: **an empty text box is removed when editing ends**, and a text
   box that was created and left empty leaves no undo step
   (App.text.ts:301). Cost S.

3. **The watcher's echo filter is a one-second clock.** `Vault.changed`
   drops any path we wrote in the last 1.0 s (Vault/Vault.swift:217), so
   an outside write to the open canvas inside that second is never loaded
   and the next save overwrites it. The store already has the right test
   (`data != lastWritten`, CanvasStore.swift:365); the clock runs first.
   Excalidraw decides change by version, never by time
   (element/src/store.ts:931). **Port:** an event is ours only if the file
   still holds the bytes we last wrote. Cost S.

4. **⇧ on a selected box dropped it at the press** (revision 51's own
   regression), so a ⇧-drag moved it alone. Excalidraw takes it away only
   on a release that did not move (excalidraw/components/App.selectionTool.ts:1316).
   **Fixed in this pass.**

## B. Behaviour — what a press, a drag and a key should do

5. **An empty shape takes clicks over its whole box.** Every shape has
   `.contentShape(Rectangle())` (Views/ShapeNode.swift:60); an unfilled
   box drawn round cards — dashed boxes are the default now — swallows
   every press on the cards inside, and a diagonal arrow takes its whole
   bounding box. Excalidraw hits only the stroke (≈ 7 screen pt) unless
   the shape is filled, holds text or is selected
   (element/src/collision.ts:87; tolerance App.tsx:6073; selected box
   App.tsx:6087). **Port:** a stroked-path content shape for unfilled
   rectangles, ellipses, diamonds and lines; the full box when filled,
   worded or selected. Cost M.

6. **Edges stay behind during a drag or resize.** `EdgeLayer` is given
   `store.document` (Views/CanvasView.swift:101) while the drag lives in
   `@State`; Excalidraw moves bound arrows on every pointer move
   (element/src/dragElements.ts:134). **Port:** give the edge layer the
   live frames. Cost S.

7. **Keys and modifiers Alex lacks**, each S unless marked:
   - arrow keys nudge 1 pt, ⇧ 5 pt, repeats coalesced into one write and
     one undo step (App.tsx:5413);
   - ⌘D duplicate (`store.duplicate` exists, CanvasStore.swift:1500);
   - ⌘A select all;
   - ⌘⌥[ / ⌘⌥] send to back / bring to front (⌘[ stays Back to Home);
   - ⇧2 zoom to selection (the focus code exists);
   - ⇧-drag locks to one axis (App.selectionTool.ts:848);
   - ⌥-drag duplicates past 10 pt (App.selectionTool.ts:772), M;
   - ⌥ on a grip resizes from the centre (element/src/resizeElements.ts:1375);
   - ↩ into an editor selects all its words (wysiwyg/textWysiwyg.tsx:1279).

8. **Arrow binding.** `bindTarget` takes the topmost frame containing the
   point (CanvasStore.swift:1290), so an arrow onto a card inside a box
   drawn later binds to the box; Excalidraw prefers the smaller target the
   point is inside (collision.ts:437). Arrowheads touch the edge;
   Excalidraw stops 5 pt short (element/src/binding.ts:117). Both S.

9. **A press in the gap inside a multi-selection** starts a marquee in
   Alex; in Excalidraw it drags the selection (App.tsx:8165). A hit
   rectangle over the selection's union, under the nodes. Cost M.

10. **Marquee updates the selection live** as the box moves (Alex applies
    it on release, CanvasView.swift:348). Cost S.

11. **Words fit their box.** A text box's height should follow its
    content; a shape should grow to hold its words and never shrink below
    the height it had before the edit (wysiwyg/textWysiwyg.tsx:414,
    element/src/containerCache.ts). Excalidraw's free text also grows in
    width until 800 pt, then wraps (element/src/newElement.ts:549).
    Measure with the TextKit path `NoteRaster` already uses. Cost M.

12. **Grips on tiny nodes**: Excalidraw hides side handles under 40
    screen pt (element/src/transformHandles.ts:216). Cost S.

## C. Performance — measure, then change

Add `--bench drag` and `--bench select` beside pan and zoom first; these
are inferred costs, not measured ones.

13. **Every card observes the whole store.** `CardNodeView` holds
    `@ObservedObject var store` (Views/CardNode.swift:24), so any published
    change — selection, tool, find query, culling — rebuilds every visible
    card; a drag frame re-runs `world()` and `derivedEdges()`. Excalidraw
    keeps three canvases (static, interactive, new element) so a selection
    redraws only handles (components/canvases/StaticCanvas.tsx:108,
    InteractiveCanvas.tsx:276). **Port:** cards take values and closures
    and are `Equatable`; the drag delta moves to a small observable like
    `Camera`, read only by the dragged nodes. Cost M.
14. **Cache keys compare content.** `NoteRasterizer.Key` hashes the whole
    markdown each body run (Views/NoteRaster.swift:35); Excalidraw keys
    caches by element version or identity (element/src/shape.ts:83,
    Scene.ts:303). An in-memory `revision` bumped in `document`'s `didSet`.
    Cost S.
15. **A resize re-rasterises the note every frame** (the raster key holds
    width and height, NoteRaster.swift:35). Keep the old picture during
    the gesture and redraw on release, as Excalidraw freezes caches during
    a zoom (App.tsx:8098). Cost S.
16. **`EdgeLayer` rebuilds its node lookup and strokes every edge on every
    camera frame** with no culling (Views/EdgeLayer.swift:10). Build the
    lookup per revision and skip edges off screen. Cost S.

## Already right, or not for Alex

- **Already have:** Esc / ⌘↩ finish keeping the selection; no typing to
  start an edit; click-away submit; shape words travel with their node
  (Excalidraw needs bound-text bookkeeping for that); constant-size grips;
  writes only on drop; atomic saves; culling with hysteresis (better for
  view building than Excalidraw's exact per-frame cull); √2 raster steps
  with a time budget.
- **Skip:** `version`/`versionNonce` and fractional indices (multiplayer
  merging; JSON Canvas order is array order and Obsidian would drop the
  keys); `throttleRAF` (SwiftUI already coalesces to frames); element
  lock, flip, rotation, multi-node resize; double-click ground for text
  (revision 46); Excalidraw groups (Alex's sections are frames, which is
  right for folders); Tab indent (Alex's Tab is list level).

## Decisions for Liam

1. **A section's floor:** Excalidraw frames take presses only on their
   outline and label, so dragging across a frame's inside is a marquee;
   in Alex the whole floor grabs the section, and on Home, where every
   card sits in a section, a marquee can only start outside them all.
2. **Marquee rule:** Excalidraw selects what the box *contains*; Alex
   selects what it *touches*. Keep touch unless boxes round cards
   over-select.
3. **Object snapping** (corners, centres, equal gaps; ⌘ flips it for a
   gesture, excalidraw/snapping.ts): wanted, and when?
4. **Space-drag pan** for mouse users.
