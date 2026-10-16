# Alex — implementation plan

Draft for Liam's review, 2026-09-13.
Revision 2: SwiftUI, native, macOS only (decided by Liam, 2026-09-13).
Revision 3: named Alex; repo `liamlee2110/alex`, private until M5 (2026-09-13).
Status: M0–M5 built and verified on 2026-09-13; v0.1.0. What each
milestone delivered is in §7. The decisions still open are in §9.
Revision 4 (2026-09-13, asked by Liam): the UI restyled to match
Heptabase's whiteboard, measured from its screenshots — desk #EDECEC,
white cards at radius 8 with no border and a 2pt #207DFF selection,
sections as the label colour at 14% over the desk with a 50% border and a
solid label pill on the top edge, arrows in #404140, a 40pt tool palette at
the left, a zoom bar at the bottom right, the breadcrumb in a transparent
top bar, a white panel with a bordered title row, the editor at 14.5pt with
24/19/16 headings. Titles use Medium where Heptabase uses Semibold, because
the design law (§6) allows two weights. The folder stays Alex's own.
Revision 5 (2026-09-14, asked by Liam): feature parity with Heptabase's
own screenshots, audited one by one — a PDF reader in the panel (zoom,
fit, pages, find), text highlights in seven colours written into the PDF,
"quote onto the desk", `[[wikilinks]]` that open or create notes,
`==highlights==`, a Backlinks list, an Info block (dates, counts, canvases,
tags), a stack of panels with `>>` and `+`, an "Appears in N canvases"
badge, a Journal with a day strip driven by `canvas.config.json`, a
section menu on the label's `•••` and a right-click menu on cards
(colour, panel, Finder, connect, remove), connect and import tools in the
palette, a `•••` menu and a Journal button in the top bar, and the slash
menu's table, maths, date, time and note-link blocks. Left out on purpose:
the AI chat panel (Claude works through the door), Zotero and Readwise,
sharing and accounts; YouTube cards waited for revision 9.
Revision 6 (2026-09-14, asked by Liam): a document on the canvas, audited
against Heptabase's card screenshots — a PDF is a page-shaped card (320 ×
414, near the page's own proportion) showing its first page drawn by PDFKit
at the card's width on the desk's grey, with the file name and the page
count under it; the pointer raises the card's chrome, a chevron that folds
the card to its title row (⌘⌥↩), a button that adds the file to the side
panel (⌥↩), and an arrow that draws a connection. A fold is `x-folded` and
the folded height in the file, so the card stays folded and reads as a
short card in any other JSON Canvas app, with `x-unfolded-height` only as
what to come back to. Heptabase's "open in new tab" has nowhere to go in a
one-window app, and its "show parsed content" and "new chat" are the AI
this app leaves to Claude, so neither is drawn.
Revision 7 (2026-09-14, asked by Liam): the hue turned indigo and the desk
given a dither frame, taken from Flowith's product pages. The accent moves
from #207DFF to #5A5BD6 in light and #4C9AFF to #8F90EE in dark, and the
window is tinted with it, so selection, links, the caret, the active tool
and the system's own default buttons and toggles are one hue instead of the
app's indigo beside the Mac's blue. The desk moves from #EDECEC to #EEEEF4
and #1C1C1E to #1B1B20 — Heptabase's lightness kept, so a white card still
has an edge against it, and only the hue turned. The frame is an
ordered-dither dot field: a Bayer 8x8 threshold on a 6pt lattice with 2.5pt
dots, two dots in three at its densest corner, thinning inward with squared
contours, drawn in two opposite corners of the desk and of the welcome
page. Two corners and not four: a third would box the canvas in, and the
canvas is the point. Heptabase's card, section, folder, highlight and arrow
colours are untouched — the dither is a texture, never a surface, so
nothing is composed on it; where the zoom bar stands, the field steps back
(revision 10).
Revision 8 (2026-09-14, asked by Liam): the sidebar redrawn to the shape of
the reference sidebars Liam showed — a head carrying the vault's name, its
file count and a button that hides the column; a "Canvas" group with Home,
the Journal, find and the number of files not placed yet; then the tree,
where a folder wears the same cardstock colour it has on the desk, a
collapsed one carries its item count, and every open folder draws a spine
down its children, the branch holding the open canvas inked in the accent.
Drawn by hand rather than with `List`, which is what lets the folder and
the branch carry any of that; the arrow keys, Finder's reveal and the
door's lamp survive the move.
Revision 9 (2026-09-14, asked by Liam): link cards that embed. Revision 5
left YouTube cards out; this puts them back, with posts on X and Threads,
Pins, Instagram, Vimeo, TikTok, Spotify and any page, on the `link` node
JSON Canvas already has, so nothing in a vault changes and Obsidian draws
the same card. On the desk a link is a poster: the picture filling the
card with the title, author and provider in a caption band under it, a
post's text where there is no picture, the host and the address until
something answers. The panel embeds the thing itself at 1×, the way a
PDF's reader lives there and not on the desk: YouTube through its player
API in a local wrapper page (the embed page on its own answers "Error 153"
with no referring page), X through its widget, Threads, Pins, reels and
TikToks through their embed pages, Vimeo and Spotify through their
players, everything else as the page. The web view keeps nothing between
sessions, has no script bridge, and sends every click-through and every
new window to the browser. Titles and pictures come from each provider's
oEmbed service, or from the page's Open Graph tags and its oEmbed
discovery link, all without a key (Instagram has no keyless oEmbed and
only embeds); they are cached under Caches and never written into the
canvas, and the fetch is the app's only outbound traffic, so Settings can
turn it off. A link arrives by ⌘L or the palette's link tool, the prompt
filled from the clipboard, by ⌘V over the desk (a copied file or picture
comes first), by an address dragged out
of a browser, or through the door's `add_card`.
Revision 10 (2026-09-14, the interface audit Liam accepted, decisions
A–I): the design law grows two laws and the lint grows three rules.
Motion is on the scale — `Motion.quick` for feedback, `move` for a thing
on screen changing size or place, `camera` for fit and focus, `hinge` for
the folder's 550 ms (D8, unchanged) — and every frame that changes with no
pointer on it (a fold, an undo, an arrange, the door's `update_card`)
moves to where it went; a drag stays live; Reduce Motion turns every
token into a cut. Every glyph you can press is one `IconButton` (four
sizes, hover and press, a name VoiceOver reads; a tooltip is not a name).
Colours, glyph sizes and durations outside Style.swift fail the lint.
Card previews fold a hard-wrapped paragraph into one block, and the editor
no longer puts a paragraph step after every newline: the blank line is the
gap, a heading keeps its step. `Ink.faint` is structure only; text that
has to be read is `muted`. A canvas remembers the world point under the
desk's centre and its scale, not an offset, so it comes back centred in a
window of any size. The frontmatter in the panel is its chips (the
properties row, `title` left out, each cut at the row) with the block
folded under them as text; the body and the block write the one file. The
live panel closes when nothing is selected and no pin holds it; the tray
is a panel of its own. Writing on a card opens the panel's TextKit editor
at the card's sizes with the frontmatter hidden. The Journal strip shows
seven days when the panel is wide enough, else five, else three, so the
chosen day is never the one cut off. The sidebar's Canvas group sits above
the tree, which scrolls alone. The dither steps back from the zoom bar's
corner rather than run under it.
Revision 11 (2026-09-15, asked by Liam): the shell redrawn to the shape of
Donna's own window, from its screenshot. The window is one board of
chestnut, title bar included — the material an earlier pass had already
put under the sidebar alone, with the desk white, the cards on warm paper
and a sky-blue accent (#174753 as ink, #83B4C1 as its wash) where revision
7 had indigo; that revision's dither did not survive the wood — and
everything sits on it. The sidebar is written straight on the wood at the
left, no surface of its own. The desk and the panel stack share one white
sheet, a page at radius 16 inset from the wood by a 12pt gutter at the
right, the bottom and below the title bar strip, so the wood shows slim
on three sides and wide on the fourth. The title bar is transparent: the
traffic lights sit on the wood and the strip still drags the window. The
split view and the window toolbar go with it. The top bar is a row over
the desk at the head of the sheet — the way up, the breadcrumb, the canvas
menu, the Journal and the panel, each an `IconButton` — and the panel
stack is a column inside the sheet, given the width its pins ask for until
it is dragged at its hairline, never narrower than 340 and never leaving
the desk under 320. The sidebar's width is dragged at the gutter; ⌘\ in
the View menu or the button in its head hides it, and a button at the head
of the top bar brings it back. Fit and focus keep their insets, measured
from the sheet. The welcome page is the same wood with a sheet of its
own. The design law's radius line is corrected to what the code has had
since revision 4 — mark 4, control 6, well and card 8 — and grows the
sheet's 16.
Revision 12 (2026-09-15 and 16, asked by Liam): colour. Three palettes
were built on one launch-time switch and set aside in turn — a
Scandinavian room on the chestnut board, Heptabase's own colours on a
grey-washed oak, and a plain white-and-beige page after Radiolab's site —
before revision 13 took the colour with the layout. What survives of the
day: the chestnut tile stays in `Resources/Materials`, unused, because
Liam asked for the asset to be kept; and a launch flag that swaps a
palette is the cheap way to put two looks side by side on one build.
Revision 13 (2026-09-16, asked by Liam): the shell redrawn to the shape of
the web-app mockups Liam showed, and the colour to theirs — white and a
light neutral grey, nothing else. The top bar runs across the whole window
as the window's own toolbar under a transparent title bar, white with a
hairline under it: the vault's glyph and name at its head, the way up and
the breadcrumb (Home, then each directory), the door's chip — blue while
the door serves, grey with the reason when it cannot, the vault's trouble
on the same chip — and the canvas menu, the Journal and the panel at the
right. Down the left, a 64pt rail of squares: Home, the vault's files,
what is not placed yet with its count, the Journal, find, and Settings at
the foot; the active square is white with a hairline. The desk fills the
rest, light grey (#F5F5F6) with a dot grid in world units (24pt, 1.5pt
dots, doubled while a zoom would bring them under 12pt), white cards on
it, and the tool palette laid flat in a white pill across the top. The
vault panel floats over the desk's left edge at radius 16, 280pt wide,
switched at its head between the tree and the files not placed yet (the
tray moves here from the panel stack); the rail or ⌘\ shows and hides
it, and a fit or focus leaves it room the way the palette's pill is left
room. The panel stack stays a column at the desk's right, dragged at its
hairline. The board, the sheet and the two-palette switch of revisions 11
and 12 go; the ink is black (#1B1D21, #6B7078 for the supporting fact),
the lines #E6E6E8, the one blue #1E88E5 for the selection, the active
tool, links, the caret and the door's chip. Heptabase's card, section,
highlight and arrow colours and the folder stocks are untouched.
Revision 14 (2026-09-17, asked by Liam): the Journal of revision 5 goes.
The day strip and its note, the calendar square in the rail, the button
in the top bar, ⌘J, the `journal` key of `canvas.config.json` (read no
more, so a vault that carries one loses nothing) and the `--journal` and
`--day` flags are removed. A day's note is a file like any other, opened
from the tree or ⌘K.
Revision 15 (2026-09-17, asked by Liam): shapes on the desk, and the
palette grouped by purpose rather than one cell per verb. Four cells:
Select; Shapes, whose click opens a menu of rectangle, ellipse, diamond,
line and arrow and whose glyph is the shape last used; Text, which puts a
sticky note where the desk is clicked; and Add, a menu of new note, import
and link. Group and find leave the palette (⌘G, the marquee and the rail
cover them); connect leaves it too, because an arrow drawn from one card to
another is the edge that already exists, while an arrow drawn anywhere
else is a shape. A shape or text tool is modal: pick it, drag on the desk,
and the palette hands back to Select; a click without a drag places the
default size; Escape hands back too. Keys on the desk, never in an
editor: V R O D L A T. A shape is a JSON Canvas `text` node with `x-shape`
(rectangle, ellipse, diamond, line), `x-fill`, `x-dashed`, and for a line
`x-points` as fractions of its frame with `x-fromEnd` and `x-toEnd` in the
edge's own vocabulary, so Obsidian shows a text card in the same place
and nothing is lost (D4, unchanged). The style range keeps to the law: the
six colours as stroke and, filled, as the card stock; outline or filled;
solid or dashed; an arrowhead at either end. Excalidraw's fill patterns and
sloppiness are out, as is a free-draw pen for now, each a project of its
own. Every glyph you can press now carries an app-drawn tooltip in a
floating panel that appears after `Motion.tooltipDelay` on the pointer
resting, never at once, and the native `.help` goes. Open: a tool lock
(draw several without re-picking), shapes through the door's `add_card`.
Revision 16 (2026-09-18, asked by Liam): the rail and the floating vault
panel of revision 13 become one sidebar, the shape of Craft's, Notion's and
Arc's, and the vault becomes one workspace among several. The sidebar is
a white column down the left, dragged at its divider between 220 and 420.
Its head is the toolbar strip itself: the traffic lights, the toggle
beside them (⌘\ still), and a new-note glyph at the sidebar's far edge;
with the sidebar hidden the toggle stays at the head of the top bar and
the vault's mark and name come back beside it. Under the strip, a search
pill that opens ⌘K; then Home and Not placed as small rows, a 13pt glyph
and the count at the row's end; then the tree of revision 8 under the
vault's name and its file count. The tray stays in the panel stack, where
the Not placed row puts it. At the foot, one 24pt square per workspace —
the initial of its name, or the SF Symbol its `canvas.config.json` names
under a top-level `icon` — the open one in the accent wash; a `+` that
opens another folder as a vault; Settings at the far end. A workspace is a
vault: every vault opened joins the foot in the order it first opened and
stays until removed by right-click, which changes nothing on disk. A
switch — a click on a square, ⌥⌘← and →, or two fingers across the
sidebar — slides the page out and the next one in the way Arc's spaces
slide; the direction is published a turn before the vault opens, because
SwiftUI reads a leaving view's transition from its last render. What the
spike settled: content drawn under the toolbar strip takes no clicks, so
the head row is toolbar items, laid to the sidebar's edge by a blank item
sized from its width; a `NavigationSplitView` would have given the strip
for nothing but moved the toggle into the detail column and ignored the
column width it was asked for, so the shell stays hand-built. The desk no
longer keeps room for a panel over its left edge (`deskLeading` goes), and
the rail's 40pt square leaves `IconButton`. "Scandinavian" here is the
layout — one column, small glyphs, few lines, air between groups — not a
palette: revision 13's colours are untouched (revision 12 tried one).
Revision 17 (2026-09-21, asked by Liam): Recents, the list revision 13
left unbuilt, in the sidebar between the nav rows and the tree, as
Notion lists the pages you were just in. A file opened in the panel —
picked on the desk, revealed from the tree, ⌘K, a wikilink or the door —
goes to the head; a folder is a canvas, found in the tree, and does not.
Five rows, a note called by its first heading and anything else by its
name (the ⌘K panel's rule), the file's kind as a faint glyph; a row
reveals the file. Twenty are kept per vault in the app's defaults, the
way the viewport is, and anything that has left the vault is dropped on
the next change. Nothing is written into the vault (D2 is about the
files being the truth of the files; what you looked at last is the
app's memory, like the viewport). No "More" row yet.
Revision 18 (2026-09-21, asked by Liam): the chrome tidied to the shape
of the assistant dashboards Liam showed — a grey rail, a grey chat column,
white pages with a title and its verbs in one head row, cards without
borders, black capsule buttons — read for what makes them clean and
applied to Alex's own surfaces, not copied. What they teach: the chrome
says three things in three shapes, and colour is for data. Where you are
is a grey square — the open canvas's row in the sidebar and the picked
file's, the panel's toggle while the panel stands — no longer the accent
wash; the tool in hand is a solid square, the ink turned inside out, in
the palette, standing a step inside its pill; the open workspace's square
at the foot is solid too. A verb with a name is a capsule, solid for the
one thing a surface asks of you (open the folder, place everything, add
the link) and outlined for the rest, so the system's button shapes leave
the window; a menu's items and Settings' form stay the system's. Blue is
kept for what is live — the selection, links, the caret, the door's chip,
which gains a dot before its word — and is never a highlight in the
chrome; the tree's spine to the open canvas is a step darker instead of
blue. The open canvas is the top bar's title, the title size in the
reading ink and text rather than a disabled button, which AppKit draws
dim. The panel's head becomes the dashboards' column head: what the panel
holds named at the left — a file by its glyph and name with its folder
after it, a link by its site's mark and title, the tray, a sticky, a
shape, a section — and the panel's verbs as plain glyphs at the right
(Finder, keep this one and start another, hide; a pinned panel closes
with ×); the bordered head buttons and the bordered title row of
revision 4 go, and "Saving" whispers at the panel's foot. The panel's
content keeps a page's margin (24pt), the Info and Backlinks heads are a
step up from the body in the supporting ink, the Info rows read at the
body size, the properties chips at the meta size, and the tray lists its
files as rows with the verb at the row's end. Found on the way: Foundation
resolves symlinks only for what exists and folds `/private/tmp` to `/tmp`
only then, so a vault under `/private/tmp` refused its own new files as
leaving the vault; `VaultPath.realPath` resolves the deepest existing
ancestor and puts the rest back, with a test. Left as they were, on
purpose: the folder's cardstock colour in the tree (it is data, the
folder's colour on the desk, and the dashboards colour data too), the
palette's and zoom bar's hairlines, Heptabase's desk and cards, and the
reader's dark bar. Later the same day, two more things Liam pointed at:
a note's card on the desk now draws its note through the panel's own
renderer, read-only, at the card's sizes (revision 10's editing sizes),
so headings, lists, quotes, rules, code, marks and `[[links]]` read on
the desk exactly as they read in the panel, and a table reads as its
source in both; the flattened preview of revision 10 goes for notes and
stays for code and text cards and for search. The renderer's view takes
no clicks and no hover (`passive`), sits in a flipped container that
clips it — an AppKit view is not clipped by a SwiftUI `clipShape` — and
fades into the paper at the card's foot. A comment in the file is left
off the card. And the 40pt band revision 10 held open at every card's
top for the hover chrome, which grew with the zoom and read as a hole,
goes: the chrome is one pill standing on the card's top edge — fold, the
side panel, a connection — with a 6pt sliver inside the card so the
pointer reaches it, and its own hover so it stays up once the pointer has
left the card for it; the words start at the card's padding at any zoom.
A folded card keeps its inline row.

Revision 19 (2026-09-24, the flow audit Liam accepted whole): the
window's four parts each keep one job — the sidebar is where, the top bar
is this canvas, the desk is making, the panel is this file — and what
leaked between them goes home. A file picked in the tree, Recents or ⌘K
that has no card on the open canvas used to do nothing; it now opens in
the live panel as it is (`looseFile`), with one solid capsule, "Place on
canvas", which puts its card where the desk is looking and picks it. What
is not placed is the canvas's business, so the sidebar's row becomes a
capsule in the top bar, "2 not placed", shown only while there is
something to place, and the tray no longer asks about the vault's own
files (`canvas.config.json`, `.mcp.json`, any `.canvas`). The sidebar's
Home row and the grey label over the tree named one canvas twice; they
become one root row, the house glyph and the workspace's name with its
file count, heading the tree, and pressing it is Home. The breadcrumb's
first crumb is the workspace's name rather than "Home", so the bar says
which vault as well as where in it; with the sidebar hidden the mark
stands before it alone. The tree speaks in file names and everything
else in titles: the panel's head names a note by its heading, as its
card and Recents do, with its path after it in the supporting ink. Each
verb is said once on screen: the live panel's `>>` goes (the top bar's
toggle hides the panel), and the `•••` menu keeps the canvas's own verbs
— arrange, place everything, reveal the canvas file — while fit and
actual size stay in the zoom bar and Settings at the foot. The way up
shows only where there is one. The camera keeps your place: a focus
from an overview zooms only to where a card reads (`Viewport.readable`,
75%), not to actual size, and a remembered view showing less than half
of what it could of the canvas (`Viewport.share`) fits instead of coming
back. Arrange lays its blocks in columns read top to bottom, as many as
bring the whole nearest the desk's shape, where it stacked them in one
column that fitted at 14%. The palette stands at the desk's top left,
where the panel opening does not move it. Smaller: the zoom bar reads
fit, minus, the percentage, plus; an empty folder no longer says
"0 items"; a revealed card that is also picked skips the pulse, since
it already wears the selection's ring.

Revision 20 (2026-09-25, asked by Liam): the folder leaves the desk and
a folder becomes a section. Liam's case: a folder on the canvas only
repeated the sidebar's tree, cost the desk's most expensive component,
and on Home stood as ten markers, five of them empty, where the
knowledge inside them should be. D5 is rewritten and D8 retired. Home is
now the only canvas the app makes, and it shows the whole vault: each
directory is a section (a JSON Canvas `group` carrying its path under
`x-folder`), holding its files' cards and, inside it, its subfolders'
sections, all the way down. A folder's section takes the preset colour
nearest its top-level stock, so it and its glyph in the sidebar agree;
the sidebar keeps the stock colours. A file that appears — written by
Claude, dropped in Finder — takes the first free cell of its folder's
section, which grows to hold it and pushes down what is under it; a
folder gets its section with its first file, so an empty folder is not
on Home. Taking a card or a section off Home lists its path under the
canvas's `x-hidden`, so it is not placed again; it waits in the tray,
and placing it brings it back where it belongs. Sections are for
workspace management, not repository discipline, so the section *is*
the folder: a card dragged into another folder's section moves its file
there on disk, one dragged onto Home's floor moves it to the vault's
root, a section dragged into another moves the folder with everything
in it, and renaming a folder's section renames the folder. A name
already taken there refuses the drag and says why; ⌘Z moves the files
back; every other canvas's cards follow the new paths. The folders'
own canvases of the old rule stay on disk as ordinary canvases,
listed in the tree and opened from there; no new one is made, and no
`.canvas` is a card on Home. Pressing a folder in the tree looks at its
section; the breadcrumb is the workspace, then the open canvas when it
is not Home, and ⌘[ goes back to Home. Plain sections, drawn around a
selection or laid out by `arrange`, stay as they were; on Home,
`arrange` lays its groups inside the files' folder section. The door
places a file in its folder's section on Home and refuses a folder card.
A folder card left on another canvas draws as a plain card that opens
the folder's section.

Revision 21 (2026-09-25, asked by Liam): the shell takes Figma's shape,
from two screenshots of its sidebar docked and folded, and then, from a
screenshot of the first build, loses everything drawn above it. No top
bar and no toolbar: the desk runs the window's full height, and all the
window's chrome lives inside the sidebar, the traffic lights included.
The title bar is hidden and its container, where AppKit keeps the
lights, is made as tall as the sidebar's head row and the lights laid in
that row a gutter in (`WindowChrome`); AppKit lays the title bar out again
on a resize and after full screen, so each puts them back. The spike that
settled it: with no toolbar, every point outside the three lights hit-
tests to the app's own content, so the head row's glyphs are ordinary
views (revision 16's toolbar items and measured spacer go), and the blank
of a head row moves the window (`WindowDragGesture`). The head row: the
lights, the sidebar's toggle, Home, then a new note at the far end —
Figma's pair of mode switches stands for Figma's own modes and has
nothing to say here (Home left the head row in revision 37, being the
list's first row). Each surface carries its own collapse glyph and no
other's: the sheet hides from the glyph at its head's far end, and
comes back when a card is picked or with ⌥⌘I. Under it, **Canvases**, Figma's
boards: Home and every other `.canvas` in the vault, the open one on the
grey square, with find (⌘K) and a new canvas (`Untitled canvas.canvas` at
the root, written, then opened) at its head; a canvas is listed there and
no longer in the tree. Under a hairline, **Layers**: the vault's tree of
revision 8, which on Home is the canvas's own layers (each folder a
section, each file a card), with the "N not placed" capsule of revision
19 and the canvas's `•••` at its head. At the foot, small, the workspace:
its mark, its name, a dot for the door's state (blue while it serves,
grey with the reason in its tooltip), and pressing it is the workspace
menu — every workspace, the open one ticked and the others with an ×
at the row's end, make one (revision 31), Settings, and since revision
34 nothing else — so the squares of revision 16 and the door's chip go. The search pill and Recents leave the sidebar (Figma has
neither); ⌘K and its glyph remain, and the store still keeps recents.
⌘\ or the toggle folds the sidebar rather than hiding it: the same
surface floats over the desk's left, the full height less a gutter all
round, and the lights stay where they were (revision 37 keeps only the
floating card and folds it into its head). The palette moves to the
foot of the desk, centred in what the zoom bar leaves, as Figma's
toolbar is (at the window's centre since revision 38). The panel stack becomes the **detail sheet**: it floats over
the desk's right, the full height less a gutter all round, at the panel
radius, sliding in and out from the right and dragged wider at its
leading edge; the desk no longer narrows for it. A pinned panel is a
**sub-sheet** drawn out of the sheet's leading edge, a step shorter at
each end and tucked under it, sliding out from behind; with nothing live
beside the pins, the last pin is the sheet. What floats is told to the
store as the desk's insets (`CanvasStore.deskInsets`), which a fit, a
focus and the desk's own chrome keep clear of; a fit or a focus nobody
has panned away from is redone when the sheet or the folded sidebar
comes or goes (the sheet no longer, since revision 43), and a remembered
centre is left alone. The design law's
panel radius now covers any surface standing alone over the desk.

Revision 22 (2026-09-25, asked by Liam): the palette audited against
Figma's, FigJam's, Miro's and Excalidraw's bars and tightened. Its cells
had two shapes: the tool in hand stood 2pt inside a 32 by 36 cell while
hover filled the whole cell, and the pill's rim was 2pt above and below
but 8pt at the sides, so the solid square all but touched its edge. Now
every cell is a 32-point square and hover, press and the tool in hand are
that one shape at the well radius, `Space.s` inside a 48-point pill at
the panel radius (8 + 8 = 16, so the curves run parallel), which the
design law already asked of a surface standing alone over the desk. A
cell that opens a menu, Shapes and Add, carries a small chevron beside
its glyph, as Figma's flyouts do; Add, the one verb among the tools you
hold, stands past a hairline. Text becomes **Sticky note** with a note's
glyph, since a sticky is what it makes (the key stays T); `Aa` read as
a font control. A tooltip opens above a glyph at the desk's foot rather
than below it, off the window, and names its key after the label in the
supporting ink ("Select  V", "Rectangle  R"). The zoom bar wears the
same pill. A shape's key is not written into the Shapes menu's items:
a bare-key equivalent on a menu item would fire while typing in a note.

Revision 23 (2026-09-25, asked by Liam): every menu is the app's own.
The palette's Shapes and Add, the layers' `•••`, the workspace foot, a
section's label, "Appears in" and every right-click menu were SwiftUI
`Menu`s and `.contextMenu`s, which AppKit draws as system menus in the
system's type and grey. They are now one component, `PopupMenu`: the
slash menu's card (the floating white, a hairline, the raised shadow),
rows in the body type with a glyph or a tick in a leading column, the
grey square under the row the pointer or the arrow keys are on, a
hairline between groups, and submenus opening beside their rows. It
opens under its button, above one at the window's foot (the palette,
the workspace), and at the pointer for a right press; ↑↓ → ← ⏎ and esc
drive it, and a press anywhere else closes it. The menu bar stays the
system's, and so do a text view's Cut, Copy and Paste. `run-tests.sh`
lints `Menu` and `.contextMenu` out of the views. This supersedes
revision 18's "a menu's items stay the system's".

Revision 24 (2026-09-25, asked by Liam): the icons are Lucide's, not SF
Symbols. Liam compared SF, Phosphor, Lucide and Tabler side by side and
chose Lucide: ISC, about two thousand icons, the most actively kept, and
drawn in strokes, so the design law's two weights are one drawing at
two line widths (1.75 and 2.25 in Lucide's 24-unit grid), as SF's
regular and medium are. Phosphor's own Swift package keeps its icons in
an asset catalog, which `swift build` copies without compiling, and its
fill weight turns a plus or a tick into a box. `Resources/Icons/
lucide.svg` is Lucide's sprite, whole (every icon, 516 KB, with its
licence beside it); `Glyph` names the ones the app uses, `GlyphImage`
cuts one out, sets its stroke and draws it as a template image in the
ink round it, sized to its square first so it stays sharp. A folder is
its outline filled. A workspace's `icon` in `canvas.config.json` is now
a Lucide name, since the whole sprite ships. `run-tests.sh` lints SF
Symbols out of the views, and the model suite checks every `Glyph` is in
the sprite.

Revision 25 (2026-09-25, asked by Liam): the desk pans and pinches at
the display's rate. Measured with `--bench` on the learn vault at 120 Hz,
pan ran at 30 fps and zoom at 17 (frames of 32 and 59 ms, the worst
near 400) with 56 nodes on the desk. Three causes, each fixed where it
lived. The viewport was published on `CanvasStore`, which some thirty
views observe, so every scroll event rebuilt every card, the sidebar,
the layers and the palette, and each card asked the disk three times
whether its file was there. The viewport is now `Camera`, its own
object: `CameraStage` moves the finished world as a transform, and only
the grid, the edges, the zoom bar, a selection's handles and a hovered
card's chrome (`CameraReader`) are redrawn with it. The world is built
from two values that change only now and then — the culled rect, recut
when the view leaves it, and the detail, the zoom rounded up to a step
of √2. The vault remembers what a path resolves to and whether it is
there until the next reload or write of its own. And each note card
was a live text view that set its glyphs again at every frame of a
pinch: revision 18's renderer now draws the card into a picture
(`NoteRaster`) at the detail step, the note laid out once and kept, a
few cards per turn of the run loop, the picture scaled meanwhile — how
Figma and Excalidraw keep a zoom smooth. The words, marks and fade are
revision 18's; `PassiveNoteView` goes. After: pan at 120 fps with no
frame over 12 ms, zoom at 90 to 110 fps with none over about 40.

Revision 26 (2026-09-25, asked by Liam): a selection looks like Figma's.
A selected card, shape or group wears a square blue outline one point
wide at every zoom, over its own rounded corners and in place of the
2-point rounded ring it wore, and, selected alone, a small white square
with a blue edge at each of its four corners, one size on screen at every zoom
(`Handle` in `Style.swift`), and no longer the connector's dot at the
middle of each side. The squares are drawn only: the invisible corner
grips over them still do the resizing, and the edges still resize
without anything drawn. The side dots now show on every card while
Connect is in hand, where dragging one onto another card connects the
two as before; a press on one card then another still does the same.

Revision 27 (2026-09-25, asked by Liam): ⌘F finds text on the open
canvas, the way Excalidraw's canvas search does. ⌘K stays the fuzzy
finder over file names; ⌘F is literal, ignores case and accents, and
reads what the desk holds: a card's title and its note's body, a
sticky's or a shape's words, a section's label, a link's address and
its page's title. It opens in the live panel as the tray does (a
selection replaces it; Escape or its close glyph ends it): a field, the
count with the hit you are on ("5 / 22 results") and the chevrons that
step, then every hit under the node it is on, the line round it cut to
a snippet with the match in the identifying weight, the current one on
the grey square. Enter or ↓ steps on, ⇧Enter or ↑ back, round the ends
(⌘G is Group selection, so the Mac's find-next key is not taken). The desk rings every node holding a hit in the highlighter's
yellow and the current one in its orange, Excalidraw's two inks, and
pans to it at a readable zoom without selecting it, since a selection
would take the panel. The words inside a card are not marked: a card is
a picture (revision 25). `CanvasFind` in `Search.swift` is the pure
part, tested; `FindPanel` the view; `--find <query>` opens it for a
snapshot.

Revision 28 (2026-09-25, asked by Liam): a **Text** tool, Figma's T,
beside Sticky note, for words on the desk with no paper under them.
The key T moves to it and Sticky note takes S, as in FigJam. A text box
is a `text` node carrying `x-shape: text`, so Obsidian shows it as a
text card (D4): no outline and no fill, its words from the top-left in
the body type, in ink or in its colour's label hue, with a faint "Text"
while it is empty so it can still be found. A click makes a one-line box
(`ShapeMetrics.defaultTextSize`) with its top-left at the click, ready
to write; a drag makes the dragged box. It has no Filled or Dashed.
Neither a text box nor a sticky has a sheet: both are written on the
desk (`CanvasNode.writtenOnDesk`), so selecting only those leaves the
sheet shut (`CanvasStore.selectionHasPanel`), and their menu has no
"Open in the panel".

Revision 29 (2026-09-26, asked by Liam): select words in a note and a
**format bar** floats over them, Notion's selection toolbar. It is in
every editor that writes: the panel, a card written on in place, a
sticky and a text box. The last two were a plain SwiftUI text field and
drew their words as typed; they are now written in the note editor, at
the desk's body size and, for a text box, in its colour, and drawn at
rest by the card's renderer (`NoteRaster`), so their Markdown shows as
it does on a card. A shape's centred words stay plain. From the left: what the line is, "Text" or "Heading 2" with a
chevron, whose menu turns every line the selection touches into text,
a heading, a list, a checklist or a quote, keeping the words, a list's
nesting and a box's tick; then Bold, Italic, Underline, Strikethrough,
Code, Highlight and Link to a note, each on the grey square while the
selected words wear it. A press is an edit to the Markdown (`**`, `*`,
`__`, `~~`, a backtick, `==`, `[[ ]]`), one undo step: on where the
words are bare, off where they are all inside the mark, which unwraps
the whole span. A mark never takes a line's block syntax or the spaces
at its ends, and a selection over several lines is wrapped line by line,
since no mark crosses a line. `~~strike~~` is new to the editor and
drawn struck through. The keys are Notion's: ⌘B, ⌘I, ⌘U, ⌘⇧X, ⌘E, ⌘⇧H,
and only the editor with the caret answers them. The bar is the popup
menu's card, stands over the first line of the selection (under it when
there is no room above), and goes when the selection empties, on
Escape, a press elsewhere, a scroll or a pinch. An edit across a pasted
image is refused rather than dropping the image. `NoteFormat` is the
pure part, tested, whose patterns the renderer now shares; `FormatBar`
the panel; `--select-text <words>` selects them for a snapshot, and
`--edit` takes a sticky's or a text box's node id as well as a card's path.

Revision 30 (2026-09-28, asked by Liam): the tool in hand turns blue.
Revision 18 drew it as a black square, the ink turned inside out, and it
read as a button rather than a state. It is now Figma's: the one blue,
#1E88E5 in both appearances (the dark mode's lighter blue leaves a white
glyph under 3:1), under a white glyph — the palette's cell and the open
workspace's mark at the sidebar's foot (`Accent.solid`, `Accent.onSolid`).
This narrows revision 18's rule rather than breaking it: blue is still
for what is live, and the tool in hand is live, waiting for the desk; it
is still never a wash or a highlight behind a row, and where you are is
still the grey square. The capsule a surface asks you to press stays
black: it is a verb, not a state. The brand guidelines say the same
(`docs/brand/alex-brand-guidelines.md`, Iconography).

Revision 31 (2026-09-29, asked by Liam): a workspace can be made from
inside Alex, not only picked. The workspace menu's first verb is **New
workspace…** (also under File): a card over the sidebar's foot asks for
a name and nothing else, and the folder goes beside the open workspace
(Documents when none is open, revision 49), said under the field rather than
asked, since Liam chose a name over a save sheet. It starts as a copy of
`vault-template/` — CLAUDE.md, README, `.mcp.json` for the door,
`canvas.config.json`, a welcome note — with Home renamed after the
folder and the notes that name Home following it; `build.sh` copies the
template into the app's resources whole, since SwiftPM's would drop the
dot files. The copy is staged on the same volume and renamed into place
(D2), refuses a name already there in any case, and then switches to
the new workspace. Picking an existing folder stayed beside it as **Add
a folder…** until revision 34 left it to ⌘O. `NewWorkspace` holds it;
the model suite checks it.

Revision 32 (2026-09-29, asked by Liam): a shape is styled from a small
bar over it, not the sheet. Selecting a line opened the whole detail
sheet for three checkboxes and a second copy of words already written on
the desk. A shape is now written on the desk like a sticky and a text box
(`CanvasNode.writtenOnDesk` is every `text` node), so selecting it leaves
the sheet shut, and while it is selected alone and at rest a
`ShapeStyleBar` stood a gap above its box (under it where the desk's
top would cut it), until revision 39 folded it into the style panel: a colour swatch with the node menu's colours, then
Filled (not on a line), Dashed, and a line's arrowhead at the start and
at the end, each on its grey square while the shape wears it — FigJam's
contextual bar, in the format bar's card. It goes while the shape is
written in, moved, resized or drawn past. The node menu keeps the same
verbs. `--select` takes a node's id too, for a snapshot.

Revision 33 (2026-09-29, asked by Liam): the words on the desk take a
size. Markdown has nowhere to say one, so a note keeps its headings and
the size is the node's, as FigJam's is: a sticky, a text box or a shape
writes it under `x-font-size` in points, Obsidian ignores it (D4), and
no key is Medium, the 13-point body every sticky has had. FigJam's four
sizes scaled to that body: Small 11, Medium 13, Large 20, Extra large
32; a number written by hand reads as its nearest (`TextSize`). It is
set from the format bar's size menu, beside "Turn into", while a sticky
or a text box is written in; from a shape's style bar; and from the
node menu's Text size, for a selection of them (the last two folded
into the style panel in revision 39). One undo step, and a
text box's height follows its words so its lines keep their room. The
headings inside grow with the size in a card's proportions. The panel
and a card have no size menu: a note's size is its headings.

Revision 34 (2026-10-05, asked by Liam): the workspace menu is a
switcher and nothing else. It had grown five verbs under the list —
New workspace…, Add a folder…, Reveal in Finder, a Remove from the
list submenu, Settings… — and two of them were the same remove, since
revision 23 already ends every row but the open one with an ×. Liam
called it too many options. Figma's account menu and Notion's and
Slack's workspace menus hold the same three things: the places, one
way to add one, and Settings; what is about one place sits on its row.
So the menu is the workspaces, the open one ticked and the others with
their × (the one remove), a hairline, **New workspace…**, a hairline,
**Settings…**. **Add a folder…** goes: a folder you already have
opens with ⌘O (File › Open vault…), from Settings and from the welcome
card, and the new-workspace prompt says so under its field. **Reveal
in Finder** for the vault's folder moves to the File menu beside Open
vault…, where a document app keeps it; a card's and the sheet's own
Reveal stay where they are.

Revision 35 (2026-10-05, asked by Liam): ⇧ keeps the proportions, as it
does in Figma, FigJam and Excalidraw. A shape dragged out with ⇧ held is
a square of the drag's longer side, grown the way the pointer went, so a
rectangle is a square and an ellipse a circle; a line or an arrow sits
on the nearest step of 15°, its length kept (`Proportion`). A resize
with ⇧ keeps the box's own proportions (`Grip.resizing`): from a corner,
the axis the pointer has moved further along, in the box's proportions,
leads and the other follows, so a straight drag keeps the corner under
the pointer and a drag inward shrinks; from a side, the dragged axis
leads and the other grows about its middle, as Figma's does. The floor
holds on both axes; a folded card's height is the fold's, so ⇧ leaves
it. The key is read on every pointer move and, through `EventCatcher`,
on every change of the modifier keys, so ⇧ pressed or let go between
two moves reshapes the preview at once; to that end a resize keeps the
grip's travel rather than a frame and works the frame out where it is
read. The canvas suite covers the geometry.

Revision 36 (2026-10-05, asked by Liam): the desk writes by hand.
Excalidraw's Excalifont (OFL 1.1, by Ján Filípek after Virgil) is
bundled at `Resources/Fonts`, beside its licence: a resource, not code,
so D3 stands. Excalidraw serves it as seven unicode-range pieces, merged
once into one 44 KB WOFF2 with fontTools; CoreText reads WOFF2 itself,
and the app loads it from its own resources without installing it
(`DeskFace`). It is the default face of everything on the desk with
words: stickies, text boxes, shapes, and notes' cards, title and body,
which Liam chose over keeping cards in the system face; the panel's
editor stays the system's, for long reading. Each of those nodes takes
one of Excalidraw's three faces under `x-font-family`: Hand-drawn (no
key), Normal (the system face) and Code (its monospaced one). The face
and revision 33's size share one menu, "Aa", rather than two: in the
format bar while a card, a sticky or a text box is written in (a card
lists faces only), in a shape's style bar, and as the node menu's Font
(the last two folded into the style panel in revision 39).
Excalifont's capitals stand 60 to the system face's 70, so it is drawn
15% larger to read at the same size; it has no bold or italic, so a
note's `**` and `*` thicken its stroke and slant it, as a browser fakes
a missing cut.

Revision 37 (2026-10-05, asked by Liam): the sidebar is one surface,
and it folds into its head. Revision 21 gave it two states, a column
docked at the window's edge and the same surface floating over the
desk; Liam, from a screenshot of the floating one beside Excalidraw's
menu — a card dropped from one button at the canvas's corner, and that
button alone when the menu is shut — chose the floating card as the
sidebar and asked for the other to go. So the sidebar is the card: over
the desk's left, the full height less a gutter all round, dragged wider
at its trailing edge between 220 and 420 (as the sheet is at its
leading edge), the desk running under it. ⌘\ or the toggle no longer
swaps one state for the other: it folds the card into its head row —
the traffic lights and the toggle, nothing else (`Shell.sidebarFolded`)
— which stays where it was at the desk's top left, so the glyph is
under the pointer that pressed it and the rest of the desk is clean.
The new note folds away with the list, having another way (⌘N and the
palette's Add). The card shown is an inset of the desk,
as it was, so a fit keeps clear of it and the palette centres in what
is left; the folded head takes none, as the zoom bar takes none
(`CanvasStore.deskInsets`). "New workspace…" from the File menu
unfolds the sidebar, since its prompt stands over the foot. The View
menu says Hide and Show rather than Fold and Dock, `--sidebar on|off`
means shown or folded, and `Shell.floatingSidebar` goes: `Shell.sidebar`
is the card's width. Later the same day, from a screenshot: Home leaves
the head row, since the list's first row is Home already (revision 19's
one root row) and ⌘[ goes there — one verb per place — so the head is
the lights, the toggle and a new note.

Revision 38 (2026-10-05, asked by Liam): the palette stands at the
window's centre. Revision 21 centred it in what the zoom bar and the
floating chrome left of the desk, which put it left of the middle by
half the zoom bar and moved it whenever the sheet or the sidebar came
or went; Liam asked for the bottom centre, always, as Figma's toolbar
and Excalidraw's are. So its centre is the window's, and it gives way
only when it must: left by just enough to keep clear of the zoom bar
when the sheet narrows the desk, right by just enough to keep clear of
the sidebar's card on a narrow window. The widths are measured as laid
out (`onGeometryChange`), so a wider palette or zoom bar needs no new
constant. The zoom bar stays at the bottom right of what the sheet
leaves, and the link prompt still grows out of the palette.

Revision 39 (2026-10-05, asked by Liam): a **style panel**, Excalidraw's
properties panel — Liam's screenshot of it beside a selected text box
— floating at the desk's left while something is selected and at rest,
so that whatever is picked can be styled from one place. It stands
under the sidebar's head row, clear of the sidebar's card when the
card is shown and under the folded head when it is not, as Excalidraw's
sits under its menu button. Its groups show by what every selected node
takes (`StyleScope` in `Shape.swift`, the node menu's rules of
revisions 5, 15, 32, 33 and 36 gathered, tested): **Colour**, the six
presets and none as round swatches, for anything; **Fill**, outline or
filled, for a shape that is not a line; **Stroke**, solid or dashed, for
any shape (a box drawn dashed, revision 51); **Arrowheads**, start and end, for lines; **Font**, the three
faces of revision 36, for words on the desk and a note's card; **Size**,
S M L XL (revision 33), for words on the desk; **Order**, send to back
and bring to front, for anything but a section, which keeps to its own
layer under the cards — the order is the file's list, so the move is
within it; and **Actions**: duplicate (a sticky, a text box, a shape or
a link copied a step down and right with its `x-` keys, becoming the
selection; a file's card is not copied, a file having one card on a
canvas), fold for a file's card but a picture's (revision 45, which
adds **Corners** for pictures), and remove. A cell wears the grey
square while the whole selection wears it, and none does where the
selection differs; a press applies to the whole selection, arrowheads
to its lines. Excalidraw's opacity and sloppiness are not drawn;
text alignment came in revision 47, stroke width, a dotted stroke, a
rectangle's corners and one-step order in revision 56, which also cut
the colours to four and none. One verb
per place (revision 19): the shape style bar of revision 32 goes, and
the node menu keeps fold, the panel, Finder and remove and loses its
colour, fill, stroke, arrowhead, font and size items; the format bar's
Aa menu stays, being for the words while they are written. The panel
goes while a selected node is written in, moved, resized, drawn past,
connected from or marqueed over, and takes no inset of the desk, as
the zoom bar takes none.

Revision 40 (2026-10-05, asked by Liam): the keys are on the palette,
and Liam's to choose. From Excalidraw's toolbar, each cell wears its
key at the bottom-right corner — bare, small (`Typography.keyMark`), in
the supporting ink, white on the tool in hand, the glyph a point up and
left of centre so the pair reads centred (`ToolCell`); the Shapes cell
wears the shape's key before its chevron. Everywhere else a key is a
`KeyCap`, the design law's thirteenth rule, Raycast's: a small square
at the mark radius on the recessed fill with a hairline edge, the key
in the supporting ink, one cap per key, so a tooltip says "Select [V]"
and the zoom bar's "Fit to contents [⌘][1]", the Shapes menu's rows end
in their keys and the Add menu's in ⌘N and ⌘L — written, not bound,
which keeps revision 22's reason (a bare-key equivalent on a menu item
would fire while typing) and loses its consequence. The keys themselves
are `ToolKeys` (`Canvas/ToolKeys.swift`, Foundation only, tested): one
bare letter or digit per tool, no modifier, V R O D L A T S by default,
kept in UserDefaults under `toolKeys` with only what differs written,
read on the desk and never in an editor (`CanvasView`'s key press asks
it; `CanvasStore.pressTool` does what a cell's press does: Select and a
shape are taken up, Text and Sticky note toggle). Settings grows a
Tools section, Nolisen's recorder row in the system's form: the tool's
glyph and name, its cap at the right; click it and press a key, Esc
keeps the old one, ⌫ clears it (a tool with no key is picked from the
palette alone), a key another tool holds is refused in a sentence under
the row with the row still listening — "V picks Select already" — and
a modifier or punctuation the same way, since the ⌘ keys are the menu
bar's. "Reset to defaults" once anything differs. `--settings on`
snapshots Settings, `--record <tool name>` with its row listening, and
a `--menu` now waits for its glyph's window as `--tip` does.

Revision 41 (2026-10-05, asked by Liam): Settings is a sheet over the
desk. The workspace menu's Settings… did nothing: it sent a bare
`showSettingsWindow:` down the responder chain, and on macOS 15
SwiftUI's own delegate accepts that selector and opens nothing — the
app menu's item fires a private `menuAction:` on a callback object of
its own, which a spike outside the repo showed beside the bare send.
Liam asked why, and for a centred sheet in its place. Heptabase's,
Notion's and Figma's settings open over the app, not in a window of
their own, and since revision 21 every piece of Alex's chrome is in the
window; the system's Settings window was the one surface outside it,
under the system's title bar. So the `Settings` scene goes. **Settings**
is a card centred over the desk under the ⌘K scrim (`SettingsSheet`):
the ⌘K panel's width, the panel radius and the lifted shadow, one head
row — the name at the left, the close glyph at the right (revision 18's
one head row) — and the same four sections, Workspace, Tools, Links,
Claude Code, in the app's own rows now that they are inside the window:
a part's head as the sheet's, the label at the left and the control at
the right, a hairline above each row, a sentence under what needs one,
capsule buttons, the switches small. It is as tall as its rows and
scrolls when the window is shorter. Opened from the workspace menu,
from the app menu's Settings… (⌘,, the app's own item where the scene's
was) and by `--settings on`, which now snapshots the window with the
sheet up, as `--record` does; Esc, the glyph or a press on the desk
closes it. `showSettings` is a store flag beside `showSearch`, so ⌘,
works on the welcome card too.

Revision 42 (2026-10-05, asked by Liam): a connector's dot comes out
one side at a time. A block selected alone with Select in hand has had
a dot standing off each of its four sides (FigJam's, dragged onto
another block as revision 26 had it), and the four stood at rest, 12
points each, crowding a small sticky's words. Now the desk reads the
pointer once (`onContinuousHover` on the desk itself, so no hit region
is added round the block: a press beside it still lands on the desk and
the edge still resizes) and `CanvasSide.near` (`Canvas/Grip.swift`,
tested) names the side whose band it is in — 16 points inside the edge
to 24 beyond it, on screen at every zoom, the corners left to the resize
grips — and that side alone shows its dot, in at `Motion.quick`; the
side a connection is being dragged from keeps its dot out. The dot is
the corner square's size and weight, 8 points with a 1-point blue edge,
pressed within a 12-point circle that begins where the edge's grip ends,
and the pointer over it is the crosshair the desk draws with, since a
drag from a dot draws an arrow. `Handle` holds the sizes; `ResizeCursor`
is `HoverCursor`, the one pointer a hover changes.

Revision 43 (2026-10-06, asked by Liam): the detail sheet opens for one
card. A marquee or a shift-click over several cards opened it on "4
selected. Pick one to read it here.", a third of the window for a
sentence; now `CanvasStore.selectionHasPanel` is `panelNode != nil`, so
several selected leave the sheet shut, or shut it, and beside pins the
live column steps out. And the sheet coming or going no longer moves the
desk: revision 21 redid a fit or a focus nobody had panned away from in
what the sheet left, so picking a card zoomed the desk out from under the
pointer. The sheet floats over the desk and the camera stays; the folded
sidebar still resettles a fit, a launch's pending fit still clears the
sheet, and a revealed card, focused to be read, still makes room for
the sheet that opens on it.

Revision 44 (2026-10-06, asked by Liam): the "N not placed" capsule and
the tray go. Liam sent the sheet showing the tray — the files taken off
Home, a Place at each row's end, Place everything under them — and asked
for the part to go. What is off the canvas is still in the vault, and
the vault has its ways to it already: ⌘K opens any file, and one with
no card opens in the sheet with **Place on canvas** (revision 19); the
canvas's `•••` and the Canvas menu keep **Place everything not yet
placed**; the canvas's Info still counts what is not placed, and the
door's `get_context` still lists it. So the sidebar's head is find, a
new canvas and `•••`, and the sheet's live column is a file, a card,
find or the canvas — `showTray`, `showTrayPanel`, `toggleTray` and
`TrayInspector` are gone, and with them the drag out of the tray
(Finder still drops onto the desk). Not placed is a count and a verb,
not a place.
The pasted image's name, a capsule over the picture, goes in the same
breath: a picture is a picture, as Heptabase draws its image cards, and
the name is in ⌘K and Finder; a card rendered from `.html` keeps its
name, being otherwise a picture of a page.

Revision 45 (2026-10-06, asked by Liam): a picture's card has no fold
and no detail sheet. Liam sent a pasted image whose pill offered the
fold and the side panel, and whose sheet showed a crop of the same
picture a third of the window wide; the card is the picture, and both
verbs held nothing. So a picture's card raises no pill, its menu has no
Fold, Open in the panel or Add to the side panel, the style panel no
fold, and picking it leaves the sheet shut (`CanvasNode.isImage`,
`CanvasStore.panelNode`); one folded before now still unfolds, and a
picture not on the canvas still opens in the sheet from ⌘K with its
Place verb. In their place the style panel has **Corners** for pictures:
0, S (the card's own 8, no key), M and L, Excalidraw's edges in four
steps, written as `x-radius` in desk points. The design law's four radii
are the chrome's; a picture's corners are the reader's, like its colour.

Revision 46 (2026-10-06, asked by Liam): double-clicking the desk no
longer makes a sticky note. A stray double-click on the ground left a
note behind; the palette's sticky tool and the menu's New sticky note
make one on purpose. A double-click on a note card still writes on it.

Revision 47 (2026-10-06, asked by Liam): the words on the desk sit
left, centred or right, Excalidraw's three. Revision 39 had kept text
alignment out of the style panel as having no place in the file; it
has one now, as size and face do, under `x-text-align` on a sticky, a
text box or a shape (not a line), and Obsidian ignores it (D4). No key
is the kind's own: a sticky's and a text box's words start at the left,
a shape's are centred, as before. The style panel's **Align** group,
after Size, sets it over the whole selection in one undo step, with
the cell on the grey square where the selection shares one. It aligns
the paragraphs (`NoteStyle`'s paragraph style, so the editor, the
card's picture and a shape's plain words agree); a text box's words
stay at its top and a shape's in its middle.

Revision 48 (2026-10-06, asked by Liam): ⌘C, ⌘X and ⌘V on the desk.
Revision 39's duplicate stayed on one canvas and left pictures and
sections out. Now ⌘C over a selection puts a clip on the pasteboard
(`CanvasClip` in `Clipboard.swift`, tested): the selected nodes, what a
selected section holds, and the edges with both ends in it, as a
fragment of JSON Canvas under Alex's own type
`com.liamlee.alex.canvas-clip` (declared in the bundle by `build.sh`),
with the words of its stickies, text boxes, shapes and links as plain
text for other apps, or its cards' files when there are no words. ⌘X
copies, then removes as Delete does. ⌘V of a clip comes before the
pasteboard's files, pictures and addresses and adds a copy in one undo
step, every id new and the edges following, the copy the selection:
back on its own canvas and in view, a step down and right of the last
paste (`ShapeMetrics.duplicateStep`, counting on); on another canvas,
where it was if that is in view; otherwise mid-view. A file has one card
on a canvas, so a file's card comes along only where its file is not
already placed, except a picture, whose bytes are written atomically
beside it as `photo 2.png` (D2) for a card of its own; a folder has one
section, so a pasted section is a plain one unless its folder's section
is gone from Home (a cut), when it comes back as the folder's. While a
card is written in, ⌘C and ⌘V are the editor's.

Revision 49 (2026-10-15, asked by Liam): the welcome page is for someone
who has never heard of a vault. It has no sheet round it: on the grey
stand the mascot (`Resources/Mascot/alex-welcome.png`, its first use),
"Welcome to Alex", one sentence on what the app is, and two white cards
side by side, each a picture and a name — **Start a new workspace**
(the paper stack) and **Open a folder** (the folder tabs). Starting
asks for a name on the same page, "My workspace" typed and selected,
says where the folder goes in words ("your Documents folder"), and
makes it from the starter vault as New workspace… does (revision 31);
with nothing open that is now Documents rather than the home folder,
where someone new to folders looks first. Opening is the picker, as
before. A vault that cannot be found says so by its name, not its
path. The pictures load through `Artwork` from the app's own
resources, as the Lucide sprite does; their sizes are `Art` tokens.
`--welcome new` snapshots the naming step.

Revision 50 (2026-10-15, asked by Liam): ↩ writes in the selected box,
as Excalidraw's Enter does (its `App.tsx` and `textWysiwyg.tsx` read for
the rule). With one shape, text box, sticky or note's card selected, ↩
opens its editor in place, what a double-click on it does; two or more
selected, or a picture, a link, a section, a folder or a canvas, and ↩
does nothing. In the editor Esc or ⌘↩ puts the pen down: the words are
saved, the box stays selected and the desk has the keys again, where Esc
used to empty the selection; a slash menu or the format bar open takes
Esc first. A shape's words being written stay mid-shape, where they are
drawn, instead of rising to its top. `--keys x,y:return,word,escape`
clicks and presses keys for a snapshot.

Revision 51 (2026-10-15, asked by Liam): a rectangle, an ellipse or a
diamond is drawn dashed, Solid a press away under Stroke; a line, an
arrow and a text box are drawn solid as before. The new shape carries
`x-dashed: true`, and a shape already on disk with no key stays solid,
so no file changes look. And a press selects on the way down, as
Excalidraw's pointer-down does: a tap beside a double-tap had waited out
the double-click interval, about a third of a second, before selecting.
⇧ adds at the press and takes away on a still release, so a ⇧-drag
carries the whole selection; pressed inside a selection of
several, the selection stays for the drag and narrows to that one on a
release that did not move. `--keys x,y,2:` double-clicks.

Revision 52 (2026-10-15, asked by Liam, batch A of
`docs/research/excalidraw-2026-10-15.md`): undo that cannot erase what
someone else wrote, one step per writing, and echoes told by content.
- **Undo by delta.** An undo step held the whole document from before
  the change and put it back, so ⌘Z after the door added a card deleted
  that card from disk. A step now holds a `CanvasDelta`
  (`CanvasDelta.swift`, tested): the nodes and edges the change added,
  changed or took away, by id, with their places, and the order when it
  reordered. Undo applies its inverse to the canvas as it is when ⌘Z is
  pressed and redo the delta again, Excalidraw's `ElementsDelta`; what
  the door or another app wrote since stays. A change that changed
  nothing is no step.
- **One writing, one step.** Every pause while writing in a shape, a
  text box or a sticky had been an undo step. The pauses still save the
  file (D2), but the step is the writing: from what the box was when
  its editor opened to what it is when it closes, as Excalidraw records
  once on submit. A text box made for writing joins that step, so one
  ⌘Z takes back the box and its words. A text box left empty when
  writing ends is taken away (Excalidraw's rule); one made and left
  empty leaves nothing, not even a step. A shape or a sticky left empty
  stays. Each editor keeps its own undo while open, so ⌘Z there takes
  back typing and never a canvas step: a shape's words are written in
  `ShapeTextEditor`, a plain text view with no inset that sits exactly
  over the words it replaces, in place of SwiftUI's `TextEditor`.
- **Echoes by content.** The watcher took any event on a path Alex
  wrote in the last second for Alex's own, so an outside write inside
  that second was never read and the next save overwrote it. A path now
  remembers what Alex left there (the bytes' SHA-256, or that something
  was moved away or in), and an event is Alex's only while the disk
  still matches — the hash §8 asked for.
`--keys … cmd-z` undoes through the window, as ⌘Z would.

Revision 53 (2026-10-15, asked by Liam, batch B of
`docs/research/excalidraw-2026-10-15.md`): Excalidraw's hit testing,
live edges and keys.
- **An empty outline takes a press on its stroke.** A shape answered
  over its whole box (`contentShape(Rectangle())`), so a box drawn round
  cards — dashed by default since revision 51 — took every press meant
  for them. Now a text box, a filled shape, a shape with words, a
  selected one and one being written in are pressed anywhere in their
  box; an empty rectangle, ellipse or diamond, and every line, only
  within `Handle.strokeHit` (7 screen points) of its stroke, the shape
  stroked as drawn (`ShapeNodeView.HitArea`). Excalidraw's
  `shouldTestInside`. The inside is the desk's: a double-click there
  writes in the shape, the container found under the click as
  Excalidraw's double-click does. The desk tells a double-click itself,
  by time and place, and empties the selection on a tap's release.
- **Edges follow as it happens.** The edge layer drew from the stored
  document, so connections stayed behind a drag or a resize and jumped
  on release; it now draws from each node's live frame.
- **Keys.** ←→↑↓ nudge the selection a point, five with ⇧, shown at once
  and landed as one move, one write and one undo step once the keys rest
  for `ShapeMetrics.nudgeSettle`; ⌘A selects every node on the desk (the
  Edit menu's Select All falls through to the app's delegate when no
  field has focus); ⌘D duplicates; ⌘⌥] and ⌘⌥[ bring to front and send
  to back (⌘[ stays Back to Home); ⇧2 zooms to the selection, a desk key
  and never a menu shortcut, which would take "@" from an editor. The
  menu's verbs do nothing while a box is written in.
- **Modifiers on a gesture.** ⇧ while dragging moves along the axis the
  pointer has gone further on; ⌥ once a drag passes 10 points leaves a
  copy behind and drags the copy, the copying and the move one undo step
  (a file's card is not copied: one card per file per canvas); ⌥ on a
  grip resizes about the centre (`Grip.resizing(fromCentre:)`, tested).
`--keys` clicks at two seconds, once the opening camera has settled, and
takes `cmd-a`, the arrows and `shift-2`.
Revision 54 (2026-10-15, asked by Liam): no Home; the person makes
every canvas, names it and marks it.
- **No Home** (D5 rewritten). `<vaultname>.canvas` is no longer made,
  laid out or kept up to date; a vault that has one keeps it as an
  ordinary canvas, listed by its name. Sections are groups and never move
  a file; ⌘[ "Back to Home" is gone. A file reached from ⌘K that is on no
  card of the open canvas shows in the panel with its verb to place it,
  as a loose file did.
- **The first canvas.** A workspace with no canvas opens on an empty
  desk: the mascot holding a blank card (`alex-empty-canvas.png`), "Create
  your first canvas", one sentence, and the name field already typed
  ("Untitled canvas") and selected, so a name and ↩ make it. The palette,
  the zoom bar and the style panel stay away until there is a desk.
  The vault opens on the canvas it last showed, else the first in the
  list, else this page.
- **Nothing to read at the start.** A new workspace is an empty folder
  with `.mcp.json` and `.gitignore`: no README, no notes, no canvas.
  `vault-template/` in the repository keeps its `CLAUDE.md` and README
  for whoever clones it.
- **Rename.** A canvas's name is its file's. Double-click its row, or
  Rename in its right-click menu or the Canvases `•••`, and the name is
  edited in the row; ↩ renames the file on disk, refusing a name taken
  or one with / or :, Esc keeps it. A new canvas starts in that field.
  What the app remembers for a canvas (viewport, the canvas last open)
  follows it.
- **Icon and colour.** The row's glyph is the canvas's: its right-click
  menu and the `•••` open a picker under the row — seven colours (none
  and Heptabase's six label colours) and a grid of Lucide icons — and
  the choice is `x-icon` and `x-color` at the canvas file's top level,
  so it travels with the file and other JSON Canvas apps ignore it (D4).
  The glyph wears the colour; with none it is the ink of any row.
Revision 55 (2026-10-15, asked by Liam): the icon is pressed where it
is. A canvas row's glyph is its own `IconButton`, laid over the row's
leading edge: a press opens (or closes) that canvas's icon and colour
picker without opening the canvas, as a chat's or a page's icon does in
ChatGPT and Notion; the rest of the row opens the canvas as before. The
row's tooltip is the canvas's name rather than its file's path.

Revision 56 (2026-10-15, asked by Liam, with Excalidraw's properties
panel beside Alex's): fewer colours, and the rest of Excalidraw's panel
that a JSON Canvas file can hold under `x-` keys (D4).
- **Colour: none and four.** Red, yellow, green and blue, as Excalidraw
  offers four and none; orange and purple left the style panel and the
  canvas icon picker of revision 54, which share `NodeMenu.colours`. A
  file that says "2" or "6" is still drawn in it.
- **Stroke width**: thin, regular and bold (Excalidraw's 1, 2 and 4),
  under `x-stroke-width`, regular written as no key; a bold line's
  arrowhead grows with it. **Stroke style**: solid, dashed and dotted,
  under `x-stroke-style`; revision 51's `x-dashed: true` is still read
  as dashed, and a press writes the new key in its place. Both are for
  any shape, a line included, and their cells are short lines drawn at
  the width and pattern, as the colours are swatches, not icons.
- **Corners for rectangles.** Excalidraw's edges: the Corners group of
  revision 45 now shows for rectangles too, under the same `x-radius`
  (0, the card's own 8 as no key, 16, 32).
- **Order, a step at a time.** Send to back, send backward, bring
  forward, bring to front, with Excalidraw's arrows; ⌘[ and ⌘] (free
  since revision 54 took Back to Home away) move a step, ⌘⌥[ and ⌘⌥]
  all the way. A step swaps each run of selected nodes with the one node
  past it in the file's list; sections keep their places
  (`CanvasStore.stepped`, tested).
- Not taken: opacity (a slider is a new control for little), sloppiness
  (no hand-drawn renderer), separate stroke and background colours (one
  colour paints both, Heptabase's look), vertical text alignment,
  arrowhead kinds and the element link.
`--select-all on` selects every node a second in, so a snapshot shows
the panel without a click.

Revision 57 (2026-10-16, asked by Liam): paste from Excalidraw. ⌘C in
excalidraw.com or its desktop app puts the selection on the pasteboard
as JSON text, `{"type":"excalidraw/clipboard","elements":[…],"files":{…}}`
(its own `application/vnd.excalidraw.clipboard+json` stays inside
Chromium's private pasteboard blob on macOS, so the plain text is what
Alex reads). ⌘V on the desk took it for a web address and dropped it;
now, after Alex's own clip and before files, pictures and addresses, it
becomes Alex's nodes (`ExcalidrawClip` in `Excalidraw.swift`, tested on
two clips taken from excalidraw.com's own copy):
- **Shapes**: rectangles, ellipses and diamonds, where they were drawn,
  a rectangle with no roundness square-cornered (`x-radius` 0). Words
  bound inside are the shape's own.
- **Words**: free text is a text box. Excalidraw's sizes 16, 20, 28 and
  36 are Alex's S, M, L and XL; Virgil and Excalifont are hand-drawn,
  Cascadia and Comic Shanns code, the rest the system's face; the
  alignment comes along.
- **Arrows and lines**: one bound at both ends to pasted elements is a
  connector, its side taken from the binding's `fixedPoint`, its heads
  and bound words (the label) kept; any other is a line through every
  point it has. A line now holds two or more points under `x-points`,
  drawn as a polyline with each head along its last segment.
- **Freehand**: a stroke drawn by hand (revision 58's `freedraw`), its
  points thinned to those a point apart.
- **Pictures**: the clip's `files` carry each picture as a data URL; the
  bytes are written beside the canvas as `Pasted image <date>.<ext>`
  (D2) and placed as a picture card. **Frames** are sections, named;
  **embeds** are link cards.
- **Style**: a colour snaps by hue to red, yellow, green or blue
  (orange is yellow, violet and cyan blue, pink red); black, white and
  greys are none. A filled shape takes its fill's colour, else its
  stroke's. Stroke widths 1, 2 and 4 and solid, dashed and dotted are
  the style panel's own.
- **Placed** as a clip from another canvas: in the middle of the view,
  one undo step, the selection. Excalidraw's coordinates mean nothing
  on this desk.
- Not taken: rotation (Alex's nodes have none), opacity, roughness,
  fill patterns (hachure and cross-hatch are a plain fill), arrowhead
  kinds (any head is an arrow), a connector's width, pattern and bends,
  groups, locks, element links and iframes. Copying the
  other way, Alex to Excalidraw, is not done.
`--keys x,y:cmd-v` presses Paste with whatever the pasteboard holds, so
a snapshot proves a paste; a run whose window is not key misses it, so
retry.

Revision 58 (2026-10-16, asked by Liam, with Excalidraw's pen beside
Alex's palette): drawing by hand. A **Draw** cell after Shapes, key P,
Excalidraw's freedraw: a drag on the desk, or from a card, lays ink
along the pointer, and the pen stays in hand stroke after stroke until
P, V, Esc or another tool puts it down; a click is a dot. The stroke is
shown as it will land, in ink at the regular width.
- **On disk**: a JSON Canvas `text` node with `x-shape: freedraw`, its
  points under `x-points` as fractions of its box, the line's key of
  revision 57, so a resize stretches the stroke and Obsidian shows an
  empty text card in its place (D4). The pointer's points are thinned
  to those more than half a screen point off the path
  (Ramer–Douglas–Peucker, `Freehand.simplified`) and drawn as a smooth
  curve through their midpoints (`Freehand.path`). One stroke, one node,
  one undo step, not selected, so the next stroke follows at once.
- **Style**: colour, stroke width and pattern, as a line's; no fill, no
  words (a double-click and ↩ pass it by), no arrowheads, no connector
  sides, and an arrow does not bind to it. Pressed along its stroke
  alone, as a line is (revision 53).
- Not taken: Excalidraw's pressure (a pointer has none; its simulated
  taper is a renderer of its own) and opacity, declined in revision 56.

Revision 59 (2026-10-16, asked by Liam, after ChatGPT's popover): a
quick sketch from anywhere. A key held by the whole Mac, ⌃⇧Space unless
Settings picks another, brings a floating window over whatever is in
front, on every Space and over full-screen apps, at the foot of the
screen the pointer is on, in the middle, a gutter above the Dock, at the
size it was last given: a desk with the least on it. No sidebar, no zoom
bar, no sheet; the style panel outside it, floating
a gutter clear of its left edge, level with the desk's top, while
something is selected — a child window, so it moves with the sketch,
and inside the desk's left only when the screen has no room there; and the palette folded into one small
muted glyph in the bottom right corner, no pill and no blue, wearing
the tool in hand, its menu every tool
with its key, then New note and Add a link (`ToolCorner`), so the room
goes to the drawing and the keys stay the quick way (revision 40's tool
keys, ⌘Z, ⌘= and ⌘-, ⌘D, ⇧2). It reopens the last canvas it showed, and the first time the
canvas last changed — it never makes one on its own, unless the vault
has none; ⌘N in it starts a fresh one,
`Sketches/Sketch <date> <time>.canvas`, an ordinary canvas the sidebar
lists like any other (D5 says why that is the person's). Above the
desk, not on it, a tab rises out of the window's top edge, centred, the
shape of a folder's tab: a close glyph, then the canvas's icon and
name and a chevron, its `PopupMenu` the new one and the canvases last
changed, newest first.
The tab's blank moves the window for as long as it is up; its edges
resize it, and the size is remembered. Esc with nothing to put down, or the key again, puts the
window away and gives the Mac back to the app that was in front; there
is nothing to save (D2). Called from another app, only the sketch comes
forward: Alex's own window is put away while it is up and put back
behind that app after, since activating Alex would raise it, its
sidebar and palette with it, over what the person was doing. The key is Carbon's `RegisterEventHotKey`,
which needs no Accessibility permission (Donna's `Hotkey`); ⌥⌘Space is
Finder's search and ⌃⌥Space the input sources, so neither is offered,
and ⌥⇧Space is Donna's. A key that does not register says so in
Settings. While the key is on, closing the main window no longer quits
Alex, so the key keeps working; Settings can also open Alex at login
(`SMAppService`, off until asked). Two stores may show one canvas — the
window's and the sketch's — so a write of either reaches the other
through the vault (`Vault.wrote`), not only the watcher,
which hides our own writes.

Revision 60 (2026-10-16, asked by Liam, looking at the quick sketch
over a white app): the desk is white with the faintest trace of the
logo's butter yellow (#F0D070), barely one part in a hundred —
`Ink.desk`, #FFFEFB (dark #161615); #FEFCF6 was tried first and read
as yellow — in the window and in the quick
sketch, whose tab shares it. The light grey of revision 13 (#F5F5F6)
read as grey once the sketch floated over other apps, and the logo's
yellow is the one colour the brand already owns. The white chrome and
cards still stand off it by their hairline and their one shadow;
`Ink.ground` stays for a card's recess, a page not yet drawn. The quick
sketch now draws its own card and shadow, the style panel's
(`Elevation.raised`), in place of the window's, so the two read as one
set of chrome, and the style panel's window ends at the sketch's edge.
Revision 61 (2026-10-16, asked by Liam, for the launch film's desk): a
Word, PowerPoint or Excel file, and Pages, Keynote and Numbers, is a
document card like a PDF's (revision 6) instead of a titled card — the
first page or slide drawn by QuickLook at the card's width, on the same
grey, with the name and the length under it. QuickLook, because nothing
else on the Mac lays out an Office file and it is the system's own
renderer (D3: no dependency); the box asked for is twice as tall as it is
wide, so a page and a slide both come back at the card's width, in the
PDF card's resolution steps. A deck's card is slide-shaped (320 × 220: a
16 : 9 slide inside the page card's margins, and the name row); a page or
a sheet keeps the page card. The length is said only where it is cheap
and true: a deck's slides and a workbook's sheets are counted from the
names in the zip's table of contents; a Word file's pages from the
`<Pages>` Word writes into `docProps/app.xml` when it saves, believed
only beside a nonzero `<Words>`, since a file made by a script carries
its template's `1`; iWork files say nothing. The panel still offers
"Open with the default app" for these: a reader there is a later change.

## 0. One paragraph

A native macOS app that shows a folder of plain files (a *vault*) as a
spatial canvas: directories are labelled sections holding their files
(revision 20), files are paper cards, cards can be grouped and linked, and
any card but a picture opens in a side panel (revision 45). There is no AI inside it. Instead the app opens a
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
| What did the coach make | the plot's card placed on the open canvas by the door; click to open |
| What is next | `queue.md` as a card on the canvas Liam keeps for it; the README dashboard block as a card |
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
Icons are art, not code (revision 24): Lucide's sprite (ISC) ships as a
resource, one SVG file that AppKit draws itself, with no package and
nothing compiled in; any other bundled art needs the same case made.

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

**D5. The person makes every canvas; there is no Home** (rewritten in
revision 54). Every `.canvas` file is one the person made or brought;
the app makes none of its own and none is special. A workspace with no
canvas opens on an empty desk that asks for the first one's name. A file
is on a canvas where it was placed — a new note, a paste, a drop, the
door — and ⌘K finds every file, placed or not. A group is a group: a
section never moves a file on disk. A canvas's name is its file's name,
and renaming it renames the file; its icon and colour are `x-icon` and
`x-color` at the file's top level (D4's `x-` keys). Any `.canvas` file
opens. The quick sketch's ⌘N (revision 59) is the person making a
canvas, named by the time it was made rather than asked for, because
the point of the key is to draw before thinking of a name; it goes in
`Sketches/` so the time-named ones keep together, and it is renamed
like any other. *Considered:* Home, `<vaultname>.canvas` at the root, laying out
the whole vault with each directory a section whose drag moved files
(revisions 20–53): it made a canvas nobody asked for, filled it with
files the person had not chosen, and named it after the workspace, so
the list's first row read as a second workspace. A vault that has one
keeps it as an ordinary canvas. *Considered before that:* the folder as
a cardstock marker that opened the directory's own canvas (revisions
1–19).

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
*Retired in revision 20*, with the folder on the desk; kept for the record.
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
│              CanvasDelta.swift     an undo step as the change alone     │
│              Layout.swift          auto-layout, free-slot placement     │
│  Views/      CanvasView.swift      viewport, gestures, culling          │
│              Folders.swift         an old folder section, read only     │
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
menus. The value lives on `Camera`, apart from the store, and only views
drawn in screen space observe it (revision 25). The canvas is a `ZStack`
under `.scaleEffect` and `.offset`, built once and moved by the camera;
nodes outside the culled rect are not built, and a note's card is a
picture drawn at the zoom's detail step. `--bench pan|zoom|both` measures
it. *Fallback if this stutters:* an `NSScrollView` with
`allowsMagnification` hosting an `NSHostingView`.

## 4. Data model

Vault layout, using the learn repo as it is today:

```
learn/
  learn.canvas                 the old Home, an ordinary canvas now
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
| `group` with `x-folder` | A section with a folder glyph in its label, holding the folder's cards and subfolders' sections (revision 20) | The section's name and colour; renaming renames the folder |
| `file` → `.md` | Paper card: title, first lines, frontmatter chips; double-click writes on the card itself, in the file's own markdown | Donna's Markdown editor: rendered in place, editable, checklists, pasted images |
| `file` → image / plot | Photo card; a picture pasted over the desk is written beside the canvas as `Pasted image <date> <time>.png` and placed mid-view in its own shape — the bytes are a file, the canvas only points (D2); no fold and no pill, its corners 0/S/M/L from the style panel (revision 45) | Full size, zoomable, for a picture not on the canvas; a placed one keeps the sheet shut (revision 45) |
| `file` → `.py .json .csv ...` | Mono card, first lines | Mono text, read-only in v1 |
| `file` → `.html` | QuickLook thumbnail | `WKWebView` with read access limited to the vault, no script bridge |
| `file` → `.pdf` | Page-shaped card: the first page at the card's width, the name and the page count under it | `PDFView` |
| `file` → `.docx .pptx .xlsx .pages .key .numbers` | The PDF's card, the first page or slide drawn by QuickLook; a deck's card slide-shaped; the slide, page or sheet count where the zip says it cheaply (revision 61) | "Open with the default app" |
| `text` | Sticky note, or bare words (`x-shape: text`), inline edit | — (written on the desk) |
| `link` | Poster card: the page's picture and title, or a post's text, from oEmbed or Open Graph | The video, post or page embedded live; a click-through opens the browser |
| `group` | Labelled region, tinted, the "Foundation / GPT / Interviews" bands | — |

Frontmatter: `Frontmatter.swift` parses the same shape `scripts/learn.py`
parses (`key: value`, `[a, b]`, ints, trailing comments) and shows keys as
chips on the card. At M4 `canvas.config.json` maps a glob to a colour key
and an edge key:

```json
{ "views": [ { "match": "competencies/*.md",
               "colorBy": "status", "edgesFrom": "prerequisites" } ] }
```

Card defaults: 320 × 200 (paper), 320 × 414 (a document), text 240 × 160;
a folder's section is as big as its contents, four cards to a row, and
grows. Ids are 16 hex chars, as JSON Canvas recommends.

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
| `write_artifact {path, content\|base64, canvas?, near?, overwrite?}` | Writes a file inside the vault (`artifacts/C3.1/pid_step.png`) and places it on the open canvas or `canvas`; with neither it is written and not placed (revision 54) | path, node id |
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

- **A canvas** = any `.canvas` file, made by the person and opened from
  the Canvases list or a card; there is no Home (revision 54). A
  workspace with none opens on the first-canvas page: the mascot, a
  name already typed and selected, and Create canvas.
- **Card panel** on the right, the floating sheet of revision 21, dragged
  wider or narrower at its leading edge, follows selection and closes
  when nothing is selected unless a pin holds it (revision 10). Its head
  names what it holds — a file's glyph, name and folder; a link's site —
  with the panel's verbs as plain glyphs at the right, and the content
  keeps a page's margin (revision 18). A note's card on the desk is the
  same rendering at the card's sizes, cut and faded where the card ends,
  with the card's toolbar a pill on its top edge under the pointer
  (revision 18); ⌘E toggles
  edit; ⌘S saves; a banner if the file changed on disk while editing (no
  silent clobber, no silent overwrite).
- **Sidebar and workspaces** (revisions 16, 21 and 37, Figma's shape):
  a white card floating over the desk's left, the full height less a
  gutter, holding all the window's chrome: a head row with the traffic
  lights, the toggle and a new note; then Canvases, every `.canvas`
  wearing its icon in its colour, the open one on a grey square,
  renamed in its row (double-click, or Rename in its right-click menu),
  with find, a new canvas and the canvas's `•••` at its head (the "N not placed"
  capsule left in revision 44); and at the
  foot, small, the workspace, whose menu switches workspaces, makes a
  new one from the template vault (revision 31) and holds Settings. No
  file tree: the desk is where files are, and ⌘K finds any of them. A
  workspace is a vault; the menu, ⌥⌘← and →, or two fingers across the
  sidebar slide to the next. ⌘\ or the toggle folds the card into its
  head — the lights and the toggle — at the desk's top left, and the
  desk is clean; its trailing edge drags it wider.
- **Detail sheet** (revision 21): the card panel floating over the
  desk's right, full height less a gutter, sliding in; pins are sub-sheets drawn out of its
  leading edge.
- **Palette and shapes** (revisions 15, 22 and 28): five cells by purpose —
  Select, Shapes (a menu of rectangle, ellipse, diamond, line and arrow,
  wearing the one last drawn), Text (words with no paper, T), Sticky note
  (a sticky where the desk is next clicked, S) and, past a hairline, Add (new note, import, link); a
  menu's cell wears a chevron, the tool in hand a solid blue square
  (revisions 18 and 30), every cell one 32-point square in a 48-point pill at
  the panel radius. A shape tool is dragged out on the desk
  (⇧ in proportion, revision 35) or clicked for the default size, then hands back to Select; an arrow
  from card to card is an edge. Outline or filled, solid or dashed, the
  six colours, an arrowhead at either end of a line; keys V R O D L A T S
  on the desk by default, each cell wearing its own at the corner and
  Settings changing them (revision 40), styled from the style panel (revision 39), never a
  sheet. Stored as `text` nodes under `x-` keys (D4). Every pressable
  glyph has an app-drawn tooltip after `Motion.tooltipDelay`. The
  palette's pill stands at the window's foot, centred (revision 38).
- **Style panel** (revision 39): Excalidraw's properties panel, a card
  floating at the desk's left under the sidebar's head row while
  something is selected: colour, fill, stroke, arrowheads, font, size,
  order and the verbs, each group shown when every selected node takes
  it and each cell on the grey square while the whole selection wears
  it. The one place a node is styled; the node menu keeps its verbs.
- **⌘K**: fuzzy search over file names and first lines, in a `KeyablePanel`
  like Donna's capture box; jump focuses the card.
- **⌘F**: find text on the open canvas in the live panel, every hit
  listed and stepped through, the nodes ringed on the desk (revision 27).
- **Settings** (⌘,): a sheet centred over the desk (revision 41) — vault
  path, the tools' keys (revision 40), link previews on/off, door on/off
  with the `claude mcp add` line to copy.

Folder section (revision 20, replacing the cardstock folder node): a
section like any other — the colour at 14% over the desk inside a 50%
border, the label a solid pill on the top edge — with a folder glyph
before the folder's name. Since revision 54 none is made; one left on
an old Home is a group that never moves a file.

Interactions in v1: pan (two-finger scroll, or drag the ground), pinch
zoom, marquee select, drag to move (never moving a file, revision 54), any edge or corner to resize, ⌫
removes from the canvas (never deletes the file; a file is deleted only
from the tray with confirmation), the sticky tool or ⌘⇧N makes a sticky
note (double-click ground did until revision 46), ↩ writes in the one
selected box and Esc or ⌘↩ finishes (revision 50), drag a file from the tray or from Finder onto the canvas to place it,
drag from a card edge to connect, ⌘L, ⌘V or a dropped address for a link
card, ⌘Z undo through `UndoManager` across layout edits, each step the
change alone so it never undoes someone else's (revision 52).

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
| M1 | Read-only canvas | **Done 2026-09-13.** Home with folders and cards on a pan/zoom viewport; open `competencies/`; click C0.1 and read it rendered in the ported editor; a card re-renders when its file changes outside the app. The `NSEvent` monitor viewport works; the folder cover is a flat translucent stock rather than a `Material`, which does not sample through a 3D rotation. The editor already saves, so most of M2's panel work landed here. | 2 days |
| M2 | Editing | **Done 2026-09-13.** Drag to move (a group carries what it holds), any edge or corner to resize (the pointer over an edge is what says the edge resizes, as on a window, and the opposite edge anchors; revision 26 draws a square at each corner of the selection; ⇧ keeps the proportions, revision 35), double-click a note card to write on it in place, marquee with ⇧ to add, ⌘G groups the selection, drag a side dot onto another card to connect (the dot of the side the pointer nears, on a card selected alone, since revision 42), double-click the desk for a sticky that edits in place, ⌘N for a new note, the tray drags onto the desk and Finder drops copy in, every mutation one undo step. The store side is covered by a headless suite; the gestures themselves are verified by hand in dogfood. `competencies.canvas` as the roadmap map lands with M4's frontmatter groups and edges. | 2½ days |
| M3 | The door | **Done 2026-09-13.** Donna's transport ported with the port changed; eight tools; Settings toggle with a status line, the `claude mcp add` line and a button that writes `.mcp.json` into the vault; `.mcp.json` written into the learn vault. Driven over HTTP the way Claude Code does it: `write_artifact` with a step-response PNG created `artifacts/C3.1/` and its canvas, `add_card` and `connect` put an explanation beside it, `focus` opened the canvas and panned to the plot. Origin check answers 403, GET answers 405. A headless suite covers the protocol and every tool, including the refusals. | 1 day |
| M4 | Progress layer | **Done 2026-09-13.** `canvas.config.json` views: `colorBy` tints a card and its chip by a frontmatter value, `edgesFrom` draws dashed prerequisite edges between cards by id, `groupBy` arranges a directory into labelled groups (⌘⇧A). The learn vault's `competencies.canvas` is now the roadmap map: nine blocks, prerequisites as arrows. ⌘K finds a file by path or title and reveals its card. The panel shows a note's frontmatter as chips above the editor. The README card carries the dashboard block. Maths stays raw `$…$` until Liam decides §9. | 1 day |
| M5 | OSS | **Done 2026-09-13.** README with cropped snapshots, MIT licence, CONTRIBUTING, `vault-template/` (README, CLAUDE.md starter, `.mcp.json`, `canvas.config.json`, one note), CI on push and a release workflow that builds, zips, makes a DMG and publishes on a `v*` tag; v0.1.0 tagged. The repo stays private until Liam flips it (§9). | 1 day |

After M3 the learn repo's CLAUDE.md §4 step 10 gained one clause: if the
door answers, write the session's artifacts through it and focus the
newest. That is the whole coach-side change, and it is the dogfood. The
learn vault also carries `.mcp.json`, `canvas.config.json` (status colours,
prerequisite edges, blocks as groups), `learn.canvas` and
`competencies/competencies.canvas`, all committed.

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
  event; suppressed by hash (revision 52; a one-second clock until then),
  tested, because the failure is a card that flickers, an editor that
  loses the caret, or an outside write overwritten.
- **Concurrent edits.** Liam editing `C0.1.md` in the panel while the coach
  rewrites it at step 10. Rule: the panel shows a "changed on disk" banner
  with reload and keep; the app never writes over a newer file silently.
- **HTML artifacts.** `WKWebView` loads the file with read access limited to
  the vault directory and registers no script message handlers, so a
  generated page cannot reach the app.
- **Embedded links.** The panel's web view for a link card loads other
  people's pages. The HTML-artifact rules apply and then some: a
  non-persistent data store, no script message handlers, every link click
  and every new window handed to the default browser. YouTube's embed page
  answers "Error 153" unless a referring https page sent it, so the player
  is wrapped in a local page (revision 9). Title fetches are the app's only
  outbound traffic, and Settings turns them off.
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
