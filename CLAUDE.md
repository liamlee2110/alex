# Notes for Claude

Read [PLAN.md](PLAN.md) before changing anything: the decisions (D1–D8) and
the reasons behind them live there, and a change that contradicts one needs
the decision rewritten first, not worked around.

## Rules that are easy to break

- **Files are the truth (D2).** Nothing in memory that is not on disk within
  a second. Every write is atomic. The watcher must not echo our own writes.
- **No third-party dependencies (D3).** Ask before adding one; the only
  exception on the table is a maths renderer at M4.
- **The door never deletes (D7).** Not gated, not hidden: absent.
- **The design law** is the header of `Sources/Alex/Views/Style.swift` and
  `run-tests.sh` lints it. Two weights, no italics in chrome, four radii,
  sentence case, one shadow, tokens not literals (colours, glyph sizes and
  motion included), every glyph you can press an `IconButton`, every menu
  a `PopupMenu` (revision 23), every icon a Lucide `Glyph` (revision 24),
  every key said on screen a `KeyCap` (revision 40). The look
  itself follows Heptabase's whiteboard for shape (PLAN.md, revision 4) and
  Figma's sidebar for the shell (revision 21): one white sidebar floating
  over the desk's left holding all the window's chrome — the traffic
  lights and the head row, Canvases, the workspace small at the foot —
  folding into its head row, the lights and the toggle (revision 37); no
  top bar, no toolbar, nothing drawn above anything; the detail sheet floating at the right, full height
  less a gutter, with pins as sub-sheets. The colours are white,
  neutral grey, black type and one blue for what is live, never a
  highlight in the chrome: where you are is a grey square, the tool in
  hand and the workspace's mark a solid blue one (revision 30), a button
  a capsule (revision 18). Heptabase's card and section
  colours are sampled values, not guesses, so change them with a reason.
  `Resources/Materials/chestnut-balanced.png` is unused and kept on
  purpose (revision 12).
- **Donna's sharp edges apply here.** Before touching windows, panels, text
  views, hosting views or drags, read the "Sharp edges" section of
  `~/workspace/donna/ARCHITECTURE.md`. Each cost real time once.

## Verify by running it, not by compiling it

```bash
./build.sh && open Alex.app --args --vault ~/workspace/learn
```

A build can also render its own window (title bar included, since the desk
runs under it) to a file and quit, for looking at a change without a screen:

```bash
mkdir -p snapshots && ./Alex.app/Contents/MacOS/Alex --vault ~/workspace/learn --select queue.md --snapshot snapshots/check.png
```

Run the app in the foreground for a snapshot; a backgrounded process never
gets a window. Crashes land in `~/Library/Logs/DiagnosticReports/Alex-*.ips`.

## Sharp edges found here

- **Foundation folds `/private` away only for a path that exists.**
  `resolvingSymlinksInPath()` on `/private/tmp/v` gives `/tmp/v`, and on
  `/private/tmp/v/new.md`, not yet on disk, gives `/private/tmp/v/new.md`,
  so a vault under `/private/tmp` (a scratchpad) refused its own new files
  as leaving the vault. `VaultPath.realPath` resolves the deepest existing
  ancestor and puts the rest back; compare paths through it.
- **A disabled `.plain` button dims its label.** The breadcrumb's last
  crumb was a disabled button and drew grey; the open canvas is `Text`.
- **A SwiftUI `clipShape` does not clip an AppKit view inside it.** The
  card's read-only text view ran past every card and over its
  neighbours. Cards no longer hold one (revision 25: `NoteRaster` draws
  the note into a picture), but any AppKit view on the desk needs its
  own clipping container.
- **Anything that observes the store is rebuilt at every scroll if the
  camera is on it.** The viewport lives on `Camera`; read it in a body
  only through `CameraStage` or `CameraReader`, and in a gesture's
  closure as `store.viewport` at the time it runs. Measure a change to
  the desk with `--bench pan|zoom|both` (foreground, like a snapshot),
  which prints frame times and quits.
- **`.onHover` is the view's frame, not its overlays.** A toolbar drawn
  above a card is out of the card's hover region; the pill keeps a sliver
  inside the card and carries its own `onHover`, and the card shows it
  while either is true.
- **A gesture goes on before the frame that places it.** A resize grip
  was a strip stretched into place with `.frame(maxWidth: .infinity,
  maxHeight: .infinity, alignment:)` and then given its cursor and its
  `highPriorityGesture`, which answered over the whole node: a press in
  a selected box's middle resized it. Size the hit area, put the cursor
  and the gesture on it, and only then place it.
- **`.contextMenu` around a view with `rotation3DEffect` draws that view
  at the container's origin.** The old folder's back and cover, both
  tilted on a hinge, rendered at the canvas's top-left while their peeks
  and the selection ring stayed put. (The folder left the desk in
  revision 20; the edge stands for anything tilted.)
- **A section that grows can outgrow its parent.** Found in revision 20:
  a folder's section grown past its parent's edge contains the parent's
  centre, so "the smallest section round me" named the child as the
  parent's parent and the two grew each other until the stack ran out.
  `Folders.grow` finds the parent by the frame before the growth.

- **A `scaledToFill` image reports the size it grew to.** As a child of
  the window's root `ZStack`, a square tile laid the whole window out
  square and the content ran off the bottom. Put a filling image in an
  `overlay` on a colour, which has no size of its own.
- **The shell is hand-built: no split view.** The title bar is
  `.hiddenTitleBar` with no toolbar, the whole shell ignores the safe
  area, and `WindowChrome` moves the traffic lights into the sidebar's
  head row. The sidebar's and the panel stack's widths are
  `SplitHandle` drags, not a column API. A `NavigationSplitView` was
  spiked for revision 16 and moved the sidebar's toggle into the detail
  column and ignored `navigationSplitViewColumnWidth`.
- **Content drawn under a toolbar takes no clicks.** The toolbar view
  answers every hit in its strip, even where it draws nothing, which is
  why revision 16 made its head row toolbar items. Revision 21 has no
  toolbar: the title bar is hidden and its container is grown to the
  sidebar's head row (`WindowChrome`), and there only the three lights
  take clicks — `--hit-test x,y;…` logs which view answers a point. With
  no title bar left, a head row's blank is a `WindowDragGesture`.
- **A `GeometryReader` under `.ignoresSafeArea` reports no safe area.**
  Its proxy's `safeAreaInsets.top` read 0 inside a view that ignored the
  top edge; measure from outside, or lay out by constants as the shell
  does now.
- **A leaving view keeps the transition of its last render.** The
  workspace page's slide direction has to be published, and drawn, a turn
  before the vault switches — `Vault.switchWorkspace` does the two steps —
  or the old page leaves the wrong way whenever the direction changes.
- **A bare argument is a file to open.** Launched with a positional path
  (`Spike out.png`), AppKit treats it as a document to open and SwiftUI
  never makes the default window; nothing is logged. Pair every flag with
  a value, as the dev flags do.
- **YouTube's embed page answers "Error 153" in a `WKWebView` that loads it
  directly.** It wants a referring https page. `LinkEmbed` wraps the player
  in a local page under `https://alex.local/`, and the other providers'
  embed pages get that as `Referer`; the open web gets none.
- **Every dev flag takes a value.** AppKit reads `-key value` pairs off the
  command line as defaults overrides. A bare `--door` swallowed the
  `--snapshot` after it and the window never opened, with no error anywhere.
- **`zsh`'s `echo` interprets `\n`.** Piping a JSON reply through `echo "$X"`
  corrupts it; use `printf '%s'`.
- **`UndoManager` groups by run-loop pass.** In a headless test every
  mutation lands in one group unless the loop is pumped between them.
- **A top-level `let` in a test `main.swift` is a global.** Its initialiser is
  a nonisolated context, so touching a main-actor store there is an error;
  put the store tests in a `@MainActor func` and call it through
  `MainActor.assumeIsolated`.
- **`Material` does not sample through `rotation3DEffect`.** The old folder
  cover was a flat translucent stock for that reason.
- **SwiftUI never asks an AppKit view whether a right press is its.**
  A probe over a card that answered `hitTest` only for `rightMouseDown`
  was never consulted: the root `NSHostingView` answers for everything
  it draws. `SecondaryClick` turns the right press into a control-click
  and `.popupMenu` is a high-priority control-tap, so SwiftUI's own hit
  testing picks the frontmost view with a menu. On a canvas node it must
  be the outermost gesture, after the node's taps and drag.
- **A drag cannot be faked.** SwiftUI's drag gestures follow the real
  pointer, not the events: a press, moves and a release made with
  `NSEvent` and handed to `sendEvent`, or posted to the process with
  `CGEvent.postToPid`, spaced over run-loop passes or not, arrive as a
  tap (`--right-click` works because a click is all a menu needs). Moving
  the real pointer takes the HID tap, which takes Accessibility. A
  gesture's geometry goes in the canvas suite (`Grip`, `Proportion`); the
  gesture itself is dogfood.
- **A snapshot run's window is under your pointer.** A test that clicks
  (`--right-click`) late in the run can be beaten by a real hover or
  click and open another canvas, which is then remembered; press early.
- **SwiftPM's `Bundle.module` looks beside `Alex.app`, not inside it.**
  The generated accessor tries `Alex.app/Alex_Alex.bundle`, then this
  machine's `.build` folder, then `fatalError`s, so it works here and
  crashes in a released copy. `LucideSprite.spriteURL` finds the bundle
  in `Contents/Resources` first; do the same for any new resource.
- **SwiftUI rasterises an `NSImage` at the image's own size.** A 24-point
  SVG drawn in a 48-point frame came out blurry; set the image's `size`
  to the square it will fill before SwiftUI sees it (`LucideSprite`).
- **A tap beside a double-tap waits out the double-click.** SwiftUI holds
  `.onTapGesture` until `onTapGesture(count: 2)` on the same view can no
  longer match, so a box took a third of a second to select. A node
  selects in a simultaneous `DragGesture(minimumDistance: 0)` instead
  (`pressGesture`); keep single taps off anything that also double-taps.
- **SwiftUI's hosting view answers `undo:` before the window does.** A
  text view with its own `UndoManager` (`undoManager(for:)`) still had
  ⌘Z undo the window's canvas steps, because the responder chain meets
  the hosting view first. `ShapeTextView` and `MarkdownTextView`
  implement `undo:`/`redo:` and validate them themselves.
- **An NSTextView forgets its undo when its storage is edited from
  outside.** Restyling the whole storage in `updateNSView`, which SwiftUI
  calls at every save, emptied the editor's undo; restyle only when the
  look changed.
- **A backgrounded run's window is often not key.** Events sent to it
  land, but a menu item's action goes to the key window and misses;
  `--keys … cmd-z` sends `undo:` down the window's own responder chain.
  Such a run also loses its first click to focus now and then: retry.
- **A menu claims its key equivalent even while the item is disabled.**
  ⌘A never reached a key handler on the desk: the Edit menu's Select
  All took it, disabled, and did nothing. Make the item's action resolve
  instead — `AppDelegate.selectAll(_:)` is the end of the chain, so a
  focused field still takes it first. SwiftUI's `onCommand` for
  `selectAll:` never enabled the item.
- **Two drag gestures on one view stop each other.** The desk's marquee
  drag plus a simultaneous zero-distance drag for the press: neither,
  nor the tap, fired. The desk keeps one drag and a tap.
- **`onCopyCommand` empties the pasteboard whatever its action does.**
  ⌘C on an empty desk wiped what another app had copied, though the
  action wrote nothing. Pass `nil` as the action (and to `onCutCommand`)
  while there is nothing to take, so the command is off.
- **`NSApp.currentEvent` at a tap is not the click.** By the time
  `onTapGesture` runs the current event can be a pointer move, whose
  `clickCount` is 0 or 1; the desk counts a double-click itself by time
  and place.
- **Arrow keys carry the keypad and function flags.** A key handler that
  wants "no modifiers but ⇧" must ignore `.numericPad` and `.function`.
- **The type checker gives up on a long `Canvas` closure.** Draw in a method
  with explicit types (see `EdgeLayer`).
- **A snapshot does not draw the YouTube player's play button.** `cacheDisplay`
  draws the wrapper page and the poster but not the player's big play
  button, so a sheet snapshot looks like the embed failed when it is fine;
  judge the player in the live app. The player API also makes its iframe
  640 by 390 unless told a size (`LinkEmbed.page` passes `100%`), which is
  why the sheet once scrolled.

- **A bare `showSettingsWindow:` opens nothing on macOS 15.** The
  workspace menu sent it to the responder chain; SwiftUI's own delegate
  accepts the selector and does nothing, and the app menu's Settings…
  item fires a private `menuAction:` on a callback of its own. Settings
  is a sheet in the window since revision 41, so the `Settings` scene
  is gone; if one ever comes back, open it through the app menu's item
  (`item.action` to `item.target`), as `--settings on` used to.

## The app icon

`AppIcon.png` and `AppIcon.icns` are generated, not drawn: the art is
`docs/logo/alex-app-icon-tile.png`, and
`swift tools/make-icon.swift docs/logo/alex-app-icon-tile.png AppIcon` puts
it on Apple's grid (an 824 squircle on a 1024 canvas, the system shadow).
Full-bleed art sits too big and too square in the Dock.

## Releasing

Tag `vX.Y.Z` and push the tag. `.github/workflows/release.yml` runs the
suites, builds, zips the app, makes a DMG and publishes a GitHub release.
`docs/*.png` are `--window 1100x700` snapshots (panel and reader at
1280x760, roadmap and reader with `--sidebar off`, so the desk has room)
used by the README, the whole frame kept since the strip and the sidebar are
part of the picture
(`tools/crop-top.swift` cuts a desk-only crop when one is wanted); refresh
them when a surface changes.

## Before saying you're done

`./run-tests.sh` passes, the release build is warning-free, you launched it,
and any sentence in PLAN.md or README.md your change made false is fixed in
the same change.
