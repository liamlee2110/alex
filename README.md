<h1 align="center">Alex</h1>

<p align="center">
  A native macOS canvas over a folder of plain files, with a door for Claude Code.<br>
  Folders are folders, notes are cards, and the files are the only truth.
</p>

<p align="center">
  <img alt="macOS 15 or later" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white">
  <img alt="Swift 6 toolchain" src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-0A84FF">
  <img alt="No third-party dependencies" src="https://img.shields.io/badge/dependencies-none-2ea44f">
  <img alt="JSON Canvas" src="https://img.shields.io/badge/format-JSON%20Canvas%201.0-6f42c1">
</p>

---

<p align="center"><img src="docs/home.png" width="820" alt="The Home canvas of a vault: coloured folders with notes peeking out, and paper cards"></p>

## What it is

Point Alex at a folder (a *vault*) and it shows the folder as a desk. Each
directory is a cardstock folder with the first things inside peeking out of
its mouth; each file is a card; cards can be moved, grouped, connected and
opened in a side panel. Double-click a folder and you are on that
directory's own canvas. Everything Alex knows is in the folder: the layout
of each canvas is a `.canvas` file in the open
[JSON Canvas](https://jsoncanvas.org) format, notes are Markdown, images are
images. Git, Obsidian, a text editor and Claude read and write the same
files, and Alex re-renders when any of them do.

There is no AI inside Alex. Instead it opens a local
[MCP](https://modelcontextprotocol.io) door so Claude Code, working in the
same folder, can see what is on screen, write files into the vault, place
them on a canvas and point at them. The door reads, adds, updates and
focuses. It never deletes.

Alex was built to run a self-taught robotics programme: the coach (Claude)
writes session logs, plots and notes into the repo, and the canvas shows
where things stand. It is generic enough for any folder of notes.

<p align="center"><img src="docs/roadmap.png" width="820" alt="A directory arranged into labelled groups by a frontmatter key, with dashed prerequisite edges"></p>

## Features

**The desk**

- Pan with two fingers, pinch to zoom, ⌘ + scroll to zoom too. Drag the
  desk to marquee-select, ⇧ to add. Double-click the desk for a sticky note
  that edits in place.
- Cards move by dragging, resize by the corner grip, connect by dragging a
  side dot onto another card. ⌘G groups the selection; dragging a group
  carries what it holds. Every action is one undo step.
- Folders counter-scale under zoom, so they read as markers from far away
  and reach full size up close. Their peeks are the OS's own thumbnails for
  PDFs, images and code, and tiny papers for notes.
- A card's file opens in the panel: Markdown renders in place and edits in
  place (headings without the `#`, lists that behave, checklists you tick,
  pasted images stored beside the note), PDFs in PDFKit, HTML in a web view
  that can read only the vault, code in mono. Notes save themselves a moment
  after you stop typing, and if the file changed on disk while you were
  editing, the panel says so and asks, rather than overwriting either side.

**Views from frontmatter** (`canvas.config.json` in the vault, optional)

- `colorBy`: a frontmatter key whose value tints the card and its chip
  (`status: done` → green, with a value-to-colour map you write).
- `edgesFrom`: a key whose values are ids of other notes; Alex draws dashed
  edges to them. Prerequisites become arrows.
- `groupBy`: a key to arrange a directory into labelled groups
  (⌘⇧A, "Arrange by frontmatter"). Nine course blocks become nine bands.

**Finding things**

- ⌘K finds a file by path or title and pans to its card. The sidebar is the
  plain tree. Files in a directory that are not on its canvas wait in a
  tray in the panel; drag them out or place them with a click.

<p align="center"><img src="docs/cards.png" width="820" alt="Paper cards inside a labelled group, sticky notes in yellow and cyan, a link card, and edges with labels"></p>

## Claude Code and the door

Turn on **Settings → Claude Code → Serve this vault to agents on this Mac**.
Alex listens on `http://127.0.0.1:53276/mcp`, loopback only, and Settings
shows whether it is actually serving. Then either:

- click **Write .mcp.json into the vault**, so anyone who opens the vault in
  Claude Code is asked once to trust the `alex` server and is connected; or
- run `claude mcp add --transport http alex http://127.0.0.1:53276/mcp` to
  register it for this Mac only.

Eight tools, all thin wrappers over the file format:

| Tool | Does |
|---|---|
| `get_context` | The vault root, the open directory and canvas, the selected cards with their file paths or text, the viewport, the unplaced files |
| `read_canvas` | A canvas as JSON Canvas 1.0 |
| `add_card` | A sticky note, a file card or a link, placed beside a node or the selection if no coordinates are given |
| `write_artifact` | A file into the vault (text or base64), directories created, placed as a card on its directory's canvas; refuses to overwrite without `overwrite: true` |
| `connect` | An edge, with an optional label |
| `update_card` | Text, colour, label, position, size |
| `focus` | Opens a canvas in the app and pans to a node |
| `list_files` | Paths under a directory, with a glob |

A session in the robotics vault ends with the coach writing the artifacts
through `write_artifact`, so a new plot lands in the right folder and on
the right canvas, and calling `focus`, so the app pans to it.

<p align="center"><img src="docs/door.png" width="820" alt="A plot written through the door, placed on its directory's canvas and focused"></p>

Everything the door can do, Claude can also do by writing files directly,
because the watcher renders whatever changes. The door adds what files
cannot: knowing what you are looking at, placing without layout maths, and
pointing.

## Install

macOS 15 (Sequoia) or later. Download `Alex.dmg` from the
[releases](https://github.com/liamlee2110/alex/releases), or build from
source with Xcode 16 or later:

```bash
git clone https://github.com/liamlee2110/alex.git
cd alex
./build.sh && open Alex.app
```

The build is a universal binary, ad-hoc signed. A downloaded build shows a
Gatekeeper warning on first open: right-click, Open. Copy `Alex.app` to
`/Applications` to keep it. There are no third-party dependencies.

To open a vault without the picker:

```bash
open Alex.app --args --vault ~/path/to/vault
```

## Starting a vault

Any folder works. [`vault-template/`](vault-template/) is a starter with a
`CLAUDE.md` that tells Claude Code how the vault is shaped, the `.mcp.json`
that connects the door, an example `canvas.config.json`, and one note.
Copy it, `git init`, open it in Alex and in Claude Code.

Alex writes into a vault only these things: a `<dirname>.canvas` file in
each directory you visit (the layout), images pasted into notes (beside the
note), and files you or the door create on purpose. Nothing else. The
`.canvas` files are worth committing: they are the map.

## Keyboard

| | |
|---|---|
| ⌘K | Find in vault |
| ⌘N / ⌘⇧N | New note / new sticky note |
| ⌘G | Group selection |
| ⌘⌫ or ⌫ | Remove from canvas (the file stays) |
| ⌘⇧A | Arrange by frontmatter |
| ⌘= ⌘- ⌘0 ⌘1 | Zoom in, out, actual size, fit |
| ⌘[ | Up one folder |
| ⌘⌥I | Show or hide the panel |
| ⌘O | Open another vault |
| ⌘Z / ⌘⇧Z | Undo / redo |

## How it is built

SwiftUI and AppKit, one Swift package, no Xcode project, no dependencies.
The Markdown editor, the MCP transport, the window plumbing and the design
law come from [Donna](https://github.com/liamlee2110/donna), the same
author's menu bar app. The folder is redrawn from a React original: same
silhouette, same hinge, same colour ladder, converted from OKLCH by hand.
The plan, every decision and its reasons, and the milestones are in
[PLAN.md](PLAN.md); the rules and the sharp edges are in
[CLAUDE.md](CLAUDE.md); how to work on it is in
[CONTRIBUTING.md](CONTRIBUTING.md).

Not yet: LaTeX rendering (maths shows as typed), Windows and Linux (by
design), sync of any kind (git is the sync).

## Licence

MIT. See [LICENSE](LICENSE).
