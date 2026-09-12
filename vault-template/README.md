# A vault

This folder is an [Alex](https://github.com/liamlee2110/alex) vault: plain
files that Alex shows as a canvas and that Claude Code can work in.

- Notes are Markdown. Frontmatter (`key: value` between `---` lines) shows
  as chips on the card and can colour it, group it and connect it; see
  `canvas.config.json`.
- Each directory gets a `<dirname>.canvas` file the first time Alex opens
  it: the layout, in JSON Canvas 1.0. Commit them; they are the map.
- `.mcp.json` connects Claude Code to Alex's door when Alex is running and
  the door is on (Settings → Claude Code). Claude Code asks once to trust it.
- `CLAUDE.md` tells Claude how this vault is shaped. Add your own rules
  below the line.

Start: copy this folder, `git init`, open it in Alex (⌘O) and in Claude
Code, and write.
