# Contributing

Alex is one Swift package. Xcode 16 or later, macOS 15 or later, nothing
else to install.

```bash
./build.sh              # release build, assembled into Alex.app, ad-hoc signed
./run-tests.sh          # the design-law lint and three headless suites
open Alex.app --args --vault ~/some/folder
```

## Before opening a pull request

1. `./run-tests.sh` passes and the release build is warning-free.
2. You launched it. Three real bugs in the app this came from shipped past
   a clean build and a green suite. A change to a view needs a snapshot:
   `./Alex.app/Contents/MacOS/Alex --vault <vault> --select <file> --snapshot out.png`.
3. Any sentence in `README.md`, `PLAN.md` or `CLAUDE.md` your change made
   false is fixed in the same change.

## The rules that shape the code

They are argued in `PLAN.md` (D1–D8). The short version:

- **Files are the only state.** Nothing in memory that is not on disk
  within a second. Every write is atomic. The watcher must not echo our own
  writes. A view never touches the file system; it calls a store.
- **JSON Canvas 1.0, kept to.** Keys Alex adds are `x-` keys. Unknown keys
  and unknown node types survive a round trip untouched.
- **No third-party dependencies.** If you need one, open an issue first and
  say what it replaces.
- **The door never deletes.** Not gated, not hidden: absent.
- **The design law** is the header of `Sources/Alex/Views/Style.swift`, and
  `run-tests.sh` greps for violations. Two weights, no italics in chrome,
  four radii, sentence case, tokens not literals.

## Map

```
Sources/Alex/
  App/      AlexApp, AppModel (owns everything), AppDelegate (snapshots),
            Commands (menus), Launch (dev flags)
  Vault/    VaultPath (safe paths, globs), VaultEntry (listing, tree),
            Vault (the open folder, atomic writes), VaultWatcher (FSEvents),
            Thumbnails (QuickLook)
  Canvas/   JSONValue, CanvasFile (the format), Frontmatter (learn.py's
            rules), Placement (auto-layout, free slots), Viewport,
            CanvasStore (the open canvas, every mutation, undo),
            CardPreview, VaultConfig (views), Search
  Views/    Style (tokens, the law), CanvasView (desk and gestures),
            FolderNode, CardNode, EdgeLayer, CanvasChrome, InspectorView,
            MarkdownEditor (from Donna), Previews, SearchPanel, SettingsView
  Door/     McpServer (transport, from Donna), McpRpc (the eight tools)
Tests/      ModelTests, CanvasTests, DoorTests: plain main.swift harnesses,
            compiled by run-tests.sh, no XCTest
tools/      step-response.swift (a demo artifact), crop-top.swift
```

## Adding things

- **A tool on the door**: a definition in `McpRpc.toolDefinitions`, a
  method, an entry in `tools`, and checks in `Tests/DoorTests`. Tools that
  change a canvas go through `loadCanvas` and `saveCanvas` so the open
  canvas notices. Do not add a tool that deletes.
- **A node kind**: JSON Canvas has four. Anything else is an `x-` key on an
  existing kind, so other tools keep reading the file.
- **A file type in the panel**: a case in `FileInspector.content`; a
  thumbnail already comes from QuickLook.

## Sharp edges

`CLAUDE.md` keeps the list of things that cost real time once. Read it
before touching windows, text views, hosting views, gestures or launch
arguments.
