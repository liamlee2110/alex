# Alex — implementation plan

Draft for Liam's review, 2026-09-13.
Revision 2: SwiftUI, native, macOS only (decided by Liam, 2026-09-13).
Revision 3: named Alex; repo `liamlee2110/alex`, private until M5 (2026-09-13).

## 0. One paragraph

A native macOS app that shows a folder of plain files (a *vault*) as a
spatial canvas: directories are cardstock folders with their contents peeking
out, files are paper cards, cards can be grouped and linked, and any card
opens in a side panel. There is no AI inside it. Instead the app opens a
local MCP door so Claude Code, working in the same folder, can read what is
on screen, write artifacts into the vault, place them on a canvas and point
at them. Files are the only truth: the app, git and Claude read and write the
same Markdown, images and `.canvas` files. An OSS user clones a vault
template, builds or downloads the app, opens both, and has the whole thing
with nothing to host and nothing to install but Xcode.

The first vault is `~/workspace/learn`, the robotics learning repo, unchanged.
The app is called Alex.

## 1. What it is for, in Liam's use first

| Need today | What the canvas shows |
|---|---|
| Where am I on ROADMAP.md (v3, nine blocks) | Blocks as groups, 25 course cards coloured by `status`, badges for `level` / `target` / `next_review`, edges drawn from `prerequisites` |
| What did the coach make | `artifacts/C3.1/` is a folder on the map with the plot peeking out of it; click to open |
| What is next | `queue.md` pinned as a card on Home; the README dashboard block as a card |
| What happened | `sessions/` as a strip of dated cards; `errors.md` and `reviews/` as cards |
| Educational resources | `resources/` (new, later) one folder per resource: PDF, notes, links, critiques inside |
| Claude as the coach, step 10 of a session | Writes the session log and artifacts as today, then via the door: places them on the competency's canvas and focuses the app on them |

Out of scope on purpose: chat, summarising, "explain this" buttons, any model
call. Those happen in Claude, which already has the files. This matches the
constitution's principle 1: the app never becomes a place where AI writes the
core.

## 2. Decisions

Recorded in the shape of Donna's DECISIONS.md so the reasons survive.

**D1. The app and the vault are separate repos.** The app is OSS; a vault is
personal (sessions, diagnostics). The app opens any folder as a vault
(`NSOpenPanel`, path remembered in `UserDefaults`). The learn repo is vault
one. Nothing in the learn repo changes for M0 to M2; M3 adds one committed
file (`.mcp.json`).

**D2. Files are the only state.** Every card is a file or a node inside a
`.canvas` file. The app holds nothing in memory that is not on disk within a
second; it watches the vault with FSEvents and re-renders on external change,
including changes by Claude and `git pull`. Writes are atomic (temp file,
rename). No database, no cache that can disagree with the folder.
*Considered:* a search index. Rejected for v1; a vault of a few hundred
files scans in milliseconds and an index is a second truth.

**D3. Stack: SwiftUI, native, macOS 15+, Swift Package, no Xcode project,
no third-party dependencies.** Decided by Liam. Same shape as Donna:
`Package.swift`, `build.sh` assembles and ad-hoc signs the `.app`,
`run-tests.sh` compiles the suites. What this buys: Donna's proven parts
lift straight in (the MCP transport, the TextKit Markdown editor that
renders in place, the window and panel plumbing, the design-law lint, the
`.app` build); PDFKit, QuickLook thumbnails, `Material` frosted glass,
`UndoManager` and `NSOpenPanel` come with the OS; a clone-and-build with
only Xcode. What it costs: the canvas engine (viewport, drag, resize,
marquee, edges, groups) is written from scratch rather than taken from a
library; the React folder component is redrawn, not reused; maths rendering
has no native answer in v1; Windows and Linux are off the table by design.
The one dependency question left open is a LaTeX renderer at M4 (§9).

**D4. Canvas format: JSON Canvas 1.0 (`*.canvas`).** The open spec from
Obsidian: nodes of type `text | file | link | group` with `x y width height
color`, edges with `fromNode toNode fromSide toSide label`. It already has the
Heptabase idea that matters, one file appearing on many canvases, and every
Obsidian user can open the same files. App-specific keys are prefixed `x-`
and ignored by other tools. Decoding follows Donna's hard-won contract:
hand-written `init(from:)`, only `id`, `type`, `x`, `y`, `width`, `height`
required, unknown node types kept as opaque nodes and written back
unchanged, so a canvas from a future build or another app never empties.
*Considered:* a bespoke JSON. Rejected; an OSS vault should not be locked to
this app.

**D5. A folder on the canvas is a directory in the vault.** A `file` node
whose path is a directory renders as the cardstock folder; opening it
navigates into that directory's own canvas, `<dir>/<dirname>.canvas`
(root: `<vaultname>.canvas`), created on first visit by auto-laying out
what the directory contains. Files that appear later and are not on the
canvas go to an "unplaced" tray with a count badge, unless the door placed
them. *Considered:* canvases anywhere, folders as arbitrary collections.
Kept possible (any `.canvas` file opens), but the directory rule is what
makes "clone and it works" true with zero configuration.

**D6. The MCP door is Donna's door with different tools.** `McpServer.swift`
(the loopback `NWListener`, Streamable HTTP, stateless, Origin check, body
caps, published status) is copied with credit and its port changed to
`127.0.0.1:53276` (spells LEARN on a keypad). A new `McpRpc` carries the
tools in §5 and reads the app's `@MainActor` stores directly, exactly as
Donna's reads `TodoStore`. Off by default, toggled in Settings, with a
status line that says why when it fails. The vault commits a `.mcp.json`
pointing at that URL, so anyone who clones the vault and opens it in Claude
Code is asked once to trust it and is connected. *Considered:* a stdio
server binary. Rejected: `.mcp.json` would need a machine-specific path to
the binary inside the `.app`, and the app must be running anyway for "focus
this card" to mean anything.

**D7. The door reads, adds, updates and focuses. It never deletes.**
Removing a card or file is Liam's click in the app, and git is the undo.
An agent that can delete is the cheapest way to lose a layout. Overwriting
an existing file needs an explicit `overwrite: true`. Paths are relative,
resolved inside the vault, and `..` is refused.

**D8. The folder component is redrawn in SwiftUI from the React original.**
`memory-house.tsx` and its CSS in the liamle repo stay the reference: the
same 200 × 150 back-panel silhouette (the SVG path transcribed into a
SwiftUI `Path`), the same hinge choreography (back tilts away 6°, front
tilts toward 11°, peeks rise out of the mouth, 550 ms on the curve
`(0.16, 1, 0.3, 1)`), the same hue/chroma ladder (OKLCH converted to sRGB
by a ten-line function so the colours match), and the same damped
counter-scale under zoom. The frosted front cover becomes a `Material`
with a tint, which is the native version of `backdrop-filter`. Peeks become
QuickLook thumbnails of the directory's first items, so PDFs, plots, HTML
and code all peek without per-type code.

## 3. Architecture

```
┌─ Alex.app (SwiftUI, Swift 6 toolchain, language mode 5) ─────────────┐
│  App/        AlexApp.swift         @main, window scene, menus           │
│              Windows.swift         main window, panels (from Donna)     │
│  Vault/      Vault.swift           root, scoped paths, atomic writes    │
│              VaultWatcher.swift    FSEvents → changed paths             │
│              Frontmatter.swift     the learn.py parsing rules           │
│              Thumbnails.swift      QLThumbnailGenerator, cached         │
│  Canvas/     CanvasFile.swift      JSON Canvas model + lenient decode   │
│              CanvasStore.swift     @MainActor, one open canvas, undo    │
│              Layout.swift          auto-layout, free-slot placement     │
│  Views/      CanvasView.swift      viewport, gestures, culling          │
│              FolderNode.swift      the cardstock folder                 │
│              CardNode.swift        paper / photo / mono / sticky / link │
│              GroupNode.swift       labelled tinted region               │
│              EdgeLayer.swift       Path-drawn edges with labels         │
│              Panel.swift           Markdown (Donna's editor), PDFKit,   │
│                                    image, WKWebView for .html           │
│              Sidebar.swift Breadcrumb.swift Search.swift Settings.swift │
│              Style.swift           design tokens + the lintable law     │
│  Door/       McpServer.swift       transport (from Donna)               │
│              McpRpc.swift          the eight tools                      │
└──────────────────────────────────────────────────────────────────────┘
        ▲ reads/writes                      ▲ HTTP /mcp
   ~/workspace/learn (vault)          Claude Code (.mcp.json)
```

Data flow: views read from two `@MainActor` `ObservableObject`s, `Vault`
(the tree, file contents on demand, thumbnails) and `CanvasStore` (the
open canvas, selection, viewport). Every mutation goes through a store
method that writes the file first and updates memory second. FSEvents
delivers changed paths; the stores reload those paths and nothing else.
Self-writes are suppressed by remembering the hash of what was just
written. The door calls the same store methods the views call and posts a
`focus` request the canvas view answers by panning; nothing the door does
is a special path.

Viewport: pan and pinch are not SwiftUI gestures on macOS, so a local
`NSEvent` monitor for `.scrollWheel` and `.magnify` drives a `Viewport`
value (offset, scale), the mechanism Donna already uses for right-click
menus. The canvas is a `ZStack` under `.scaleEffect` and `.offset`; nodes
outside the visible rect are not built. *Fallback if this stutters:* an
`NSScrollView` with `allowsMagnification` hosting an `NSHostingView`,
decided at M1 by measuring on the learn vault.

## 4. Data model

Vault layout, using the learn repo as it is today:

```
learn/
  learn.canvas                 Home (auto-created on first open)
  competencies/
    competencies.canvas        blocks as groups, cards from *.md
    C0.1.md ...
  artifacts/
    C3.1/
      C3.1.canvas
      pid_step.png  pid.py
  sessions/  reviews/  research/  diagnostics/  templates/
  queue.md  README.md  ROADMAP.md  CONSTITUTION.md  errors.md  ideas.md
  .mcp.json                    added at M3
  canvas.config.json           optional, added at M4
```

Node kinds and how each renders:

| JSON Canvas node | On the canvas | In the panel |
|---|---|---|
| `file` → directory | Cardstock folder, up to 3 peeks, item count | Navigates into the directory canvas |
| `file` → `.md` | Paper card: title, first lines, frontmatter chips | Donna's Markdown editor: rendered in place, editable, checklists, pasted images |
| `file` → image / plot | Photo card | Full size, zoomable |
| `file` → `.py .json .csv ...` | Mono card, first lines | Mono text, read-only in v1 |
| `file` → `.html` | QuickLook thumbnail | `WKWebView` with read access limited to the vault, no script bridge |
| `file` → `.pdf` | Document card, first page | `PDFView` |
| `text` | Sticky note, inline edit | Same |
| `link` | URL card with title | Opens in the default browser |
| `group` | Labelled region, tinted, the "Foundation / GPT / Interviews" bands | — |

Frontmatter: `Frontmatter.swift` parses the same shape `scripts/learn.py`
parses (`key: value`, `[a, b]`, ints, trailing comments) and shows keys as
chips on the card. At M4 `canvas.config.json` maps a glob to a colour key
and an edge key:

```json
{ "views": [ { "match": "competencies/*.md",
               "colorBy": "status", "edgesFrom": "prerequisites" } ] }
```

Card defaults: 320 × 200 (paper), 200 × 150 (folder, the memory-house size),
text 240 × 160. Ids are 16 hex chars, as JSON Canvas recommends.

## 5. The door: MCP contract

Endpoint `http://127.0.0.1:53276/mcp`. Every tool is a thin wrapper over the
file format; Claude can always write the files directly instead, and the
watcher will render them. The door adds three things files cannot: knowing
what Liam is looking at, placing without knowing layout maths, and pointing.

| Tool | Does | Returns |
|---|---|---|
| `get_context` | Vault root, open canvas path, selected nodes with their file paths or text, viewport | JSON |
| `read_canvas {path}` | The JSON Canvas file | nodes, edges |
| `add_card {canvas, type, text\|file\|url, near?, group?, color?, x? y? w? h?}` | Adds a node; without coordinates places it beside `near`, else beside the selection, else in the first free slot | node id |
| `write_artifact {path, content\|base64, canvas?, near?, overwrite?}` | Writes a file inside the vault (`artifacts/C3.1/pid_step.png`), optionally places it | path, node id |
| `connect {canvas, from, to, label?}` | Adds an edge | edge id |
| `update_card {canvas, id, text? color? x? y? w? h?}` | Edits a node | ok |
| `focus {canvas, id?}` | Opens the canvas in the app, pans to the node, pulses it | ok |
| `list_files {dir?, glob?}` | Cheap listing for agents without fs access | paths |

Instructions sent at `initialize` (the sentence Claude actually reads):
"This vault is the user's learning repo; files are the truth and this door
is a convenience. Write artifacts into the vault with `write_artifact`,
place them on the relevant canvas, then call `focus` so the user sees them.
Never overwrite without `overwrite: true`. There is no delete; the user
removes things in the app."

Security, Donna's load-bearing lines kept verbatim: listener pinned to
loopback with `requiredLocalEndpoint`; a browser `Origin` that is not
localhost gets 403 (DNS rebinding); headers capped at 64 KB, bodies at
1 MB; bind failure published to Settings, never a green toggle over a dead
port. `McpRpc` has no networking in it, so the test suite calls it directly.

Vault side, committed at M3:

```json
{ "mcpServers": { "alex": { "type": "http",
                  "url": "http://127.0.0.1:53276/mcp" } } }
```

Claude Code reads project `.mcp.json` and asks once to trust it. The
claude.ai web connectors need public HTTPS and are not a target.

## 6. What Liam sees

Six inspirations, mapped: (1) sticky notes and paper cards on a soft ground
→ card and text nodes; (2) the sidebar plus grid of folder-grouped notes →
sidebar tree and ⌘K; (3) folder icon studies → the folder node's hue
variable, one stock per phase; (4) folders with contents peeking → the
redrawn memory-house folder with QuickLook thumbnails; (5) Heptabase's
canvas with labelled groups and a right panel → groups and the card panel;
(6) the Mindstorms map, dense linked cards → edges with labels and the panel
that follows selection.

Surfaces:

- **Home** = the vault root canvas. Folders for each directory, cards for
  root files. Breadcrumb `learn`.
- **Folder canvas** = a directory. Breadcrumb `learn / artifacts / C3.1`.
  Back with ⌘[ or clicking a crumb. Entering plays the fan-out, then the
  peeks fly to their card positions on the new canvas with
  `matchedGeometryEffect`; leaving reverses it.
- **Card panel** on the right, resizable, follows selection; ⌘E toggles
  edit; ⌘S saves; a banner if the file changed on disk while editing (no
  silent clobber, no silent overwrite).
- **Sidebar** (⌘\ to hide): vault tree, recent, unplaced tray, door status.
- **⌘K**: fuzzy search over file names and first lines, in a `KeyablePanel`
  like Donna's capture box; jump focuses the card.
- **Settings**: vault path, door on/off with the `claude mcp add` line to
  copy, appearance.

Folder node: 200 × 150, back panel `Path` with tab, `Material` front cover
tinted from the node hue, three peeks lifting on `.onHover` with
`rotation3DEffect` about the bottom hinge, the directory name and item
count on the cover, hue from `x-hue` (default per top-level directory),
damped counter-scale so folders read as markers when zoomed out
(`0.68 × zoom^0.4`, capped 1.45). Peeks are `QLThumbnailGenerator` images
cached by path and modification date.

Interactions in v1: pan (two-finger scroll, or drag the ground), pinch
zoom, marquee select, drag to move, corner to resize, ⌫ removes from the
canvas (never deletes the file; a file is deleted only from the tray with
confirmation), double-click ground creates a sticky note, drag a file from
the tray or from Finder onto the canvas to place it, drag from a card edge
to connect, ⌘Z undo through `UndoManager` across layout edits.

Type: the system serif (New York) for card titles via `.design(.serif)`,
the system sans for UI, the system mono for code. No bundled fonts; Gelica
from the liamle repo is licensed and does not ship. Donna's design law
(no semibold, no italics in chrome, one radius scale, one shadow) carries
over with its lint.

## 7. Milestones

Estimates are Claude build time in focused sessions; Liam's part is a short
dogfood pass and the decisions in §9. Each milestone ends with something to
open, not a report. Verification is Donna's rule: launch it, do not just
compile it.

| # | Milestone | Liam sees | Est. |
|---|---|---|---|
| M0 | Scaffold | **Done 2026-09-13.** Package, `build.sh`, `run-tests.sh` with the design-law lint, window opens, picks `~/workspace/learn`, sidebar lists it and reloads on outside changes, plain preview of the selected file, `--snapshot` renders the window to a PNG. | ½ day |
| M1 | Read-only canvas | Home with folders and cards on a pan/zoom viewport; open `competencies/`; click C0.1 and read it rendered; edit `queue.md` in Claude and watch the card update. Viewport approach measured and settled. | 2 days |
| M2 | Editing | Move, resize, marquee, groups, edges, sticky notes, Markdown edit in the panel, tray, undo; `competencies.canvas` committed as the roadmap map. | 2½ days |
| M3 | The door | Door on; `.mcp.json` in the vault; from Claude Code: "plot a P step response, save it under artifacts/C3.1 and show me" ends with the app panning to the new plot. | 1 day |
| M4 | Progress layer | Colour by `status`, badges, prerequisite edges from frontmatter, ⌘K, dashboard card, `canvas.config.json`, maths rendering decision (§9). | 1 day |
| M5 | OSS | README with screenshots, MIT licence, CONTRIBUTING, `vault-template/` (CLAUDE.md starter, `.mcp.json`, one canvas), GitHub Actions on a macOS runner building the `.app` and a `.dmg` per tag, v0.1.0. | 1 day |

After M3 the learn repo's CLAUDE.md §4 step 10 gains one clause: "if the
door is open, place the session's artifacts on the competency canvas and
focus them". That is the whole coach-side change, and it is the dogfood.

## 8. Risks and sharp edges, known before starting

- **Donna's sharp-edges list is required reading** before M0:
  `NSHostingController` sizing, `NSHomeDirectory()` ignoring `$HOME` in
  tests, TextKit 2 never asking about glyphs, borderless panels needing
  `canBecomeKey`, `.draggable` losing to `isMovableByWindowBackground`.
  Each cost real time once; none should cost it twice.
- **Scroll and magnify are not SwiftUI gestures.** The `NSEvent` monitor
  approach is proven in Donna for clicks, not yet for wheel events at 120 Hz;
  M1 measures it and keeps the `NSScrollView` fallback ready.
- **Hundreds of hosted views under `scaleEffect`.** Mitigations in order:
  cull nodes outside the viewport, render peeks and card previews as cached
  images, `drawingGroup()` on static layers. Measure at M1 with the learn
  vault, then with a synthetic 500-node canvas.
- **Text editing inside a scaled canvas.** Sticky notes edit inline; every
  other card edits in the panel at 1× so the caret never blurs.
- **Self-echo from FSEvents.** A write by the app comes back as a change
  event; suppressed by hash, tested at M1, because the failure is a card
  that flickers or an editor that loses the caret.
- **Concurrent edits.** Liam editing `C0.1.md` in the panel while the coach
  rewrites it at step 10. Rule: the panel shows a "changed on disk" banner
  with reload and keep; the app never writes over a newer file silently.
- **HTML artifacts.** `WKWebView` loads the file with read access limited to
  the vault directory and registers no script message handlers, so a
  generated page cannot reach the app.
- **Maths.** Sessions carry LaTeX in specs. Native rendering means either a
  third-party package (SwiftMath) or a `WKWebView` read view with a bundled
  KaTeX. Neither is in v1; raw `$...$` shows until M4 decides.
- **The door only helps Claude Code.** Fine for the target user; documented.
- **Port collision.** Loud in Settings, fixable there; same as Donna.
- **Ad-hoc signing.** Gatekeeper warns on a downloaded `.dmg` from someone
  else's build; the README says build from source or right-click Open.
  Notarisation needs a paid developer account and is a later decision.

## 9. Decisions Liam owns

Answer in this file or in chat.

1. **Canvas-per-directory convention** `<dir>/<dirname>.canvas` (D5).
2. **No delete over the door** (D7).
3. **Dependency policy.** Zero third-party like Donna, with one exception
   allowed at M4 for maths, or none and maths waits. My take: allow the one.
4. **Going public.** The repo is private while dogfooding; M5 flips it.
5. **Settled:** name (Alex), repo (`liamlee2110/alex`, MIT), stack (SwiftUI,
   native, macOS only), fonts (system serif, nothing bundled).

## 10. One-time setup

Nothing to install. Xcode 26.3 and the Swift 6 toolchain are present;
`swift build` and `codesign` are all `build.sh` needs.
