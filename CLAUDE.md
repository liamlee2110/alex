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
  sentence case, one shadow, tokens not literals.  The look itself follows
  Heptabase's whiteboard (PLAN.md, revision 4); its colours are sampled
  values, not guesses, so change them with a reason.
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

- **`.contextMenu` around a view with `rotation3DEffect` draws that view
  at the container's origin.** The folder's back and cover, both tilted
  on a hinge, rendered at the canvas's top-left while their peeks and the
  selection ring stayed put. Cards, stickies and links carry the menu;
  folders do not.

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
- **`Material` does not sample through `rotation3DEffect`.** The folder cover
  is a flat translucent stock for that reason.
- **The type checker gives up on a long `Canvas` closure.** Draw in a method
  with explicit types (see `EdgeLayer`).

## Releasing

Tag `vX.Y.Z` and push the tag. `.github/workflows/release.yml` runs the
suites, builds, zips the app, makes a DMG and publishes a GitHub release.
`docs/*.png` are cropped snapshots (`tools/crop-top.swift`) used by the
README; refresh them when a surface changes.

## Before saying you're done

`./run-tests.sh` passes, the release build is warning-free, you launched it,
and any sentence in PLAN.md or README.md your change made false is fixed in
the same change.
