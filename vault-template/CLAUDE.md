# Notes for Claude

This folder is an Alex vault: a folder of plain files that the Alex app
shows as a spatial canvas. Files are the truth; Alex re-renders whatever
changes on disk.

## Shape

- Markdown notes with frontmatter. Keys named in `canvas.config.json`
  colour, group and connect the cards; keep them accurate.
- `<dirname>.canvas` in each directory is the layout, JSON Canvas 1.0.
  Prefer the door's tools over editing these by hand; if you must edit
  one, keep ids and unknown keys intact.
- Artifacts (plots, data, generated pages) go in a directory next to the
  note they belong to, or in `artifacts/<topic>/`.

## The door

When the `alex` MCP server answers, Alex is open on this vault:

1. `get_context` first: which canvas is open, what is selected, what is
   not yet placed.
2. Write files with `write_artifact`; it creates directories and places a
   card on the file's canvas. Add notes and links with `add_card`,
   relations with `connect`.
3. End with `focus` on the newest thing, so the person sees it.

The door cannot delete. Never work around that by rewriting a canvas
without a node; the person removes things in the app.

When the server does not answer, write the files as usual. Alex shows new
files in its tray the next time it opens the directory.

---

(your own rules here)
