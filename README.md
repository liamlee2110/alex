# Alex

A native macOS app that shows a folder of plain files as a spatial canvas:
directories are folders with their contents peeking out, files are cards,
cards group and link, and Claude Code can place things on the canvas through
a local MCP door. No AI inside; files are the only truth.

Status: M0, the scaffold. The plan, decisions and milestones are in
[PLAN.md](PLAN.md).

## Build

macOS 15 or later, Xcode 16 or later. No third-party dependencies.

```bash
./build.sh && open Alex.app
```

To open a vault without the picker:

```bash
open Alex.app --args --vault ~/workspace/learn
```

Tests: `./run-tests.sh`.
