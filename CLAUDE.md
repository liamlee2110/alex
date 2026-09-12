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
  sentence case, one shadow, tokens not literals.
- **Donna's sharp edges apply here.** Before touching windows, panels, text
  views, hosting views or drags, read the "Sharp edges" section of
  `~/workspace/donna/ARCHITECTURE.md`. Each cost real time once.

## Verify by running it, not by compiling it

```bash
./build.sh && open Alex.app --args --vault ~/workspace/learn
```

A build can also render its own window to a file and quit, for looking at a
change without a screen:

```bash
mkdir -p snapshots && ./Alex.app/Contents/MacOS/Alex --vault ~/workspace/learn --snapshot snapshots/m0.png
```

Crashes land in `~/Library/Logs/DiagnosticReports/Alex-*.ips`.

## Before saying you're done

`./run-tests.sh` passes, the release build is warning-free, you launched it,
and any sentence in PLAN.md or README.md your change made false is fixed in
the same change.
