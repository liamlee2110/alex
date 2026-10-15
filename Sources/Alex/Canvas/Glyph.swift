import Foundation

/// The app's icons (PLAN.md, revision 24): Lucide's, by name, cut from
/// the one sprite bundled at `Resources/Icons/lucide.svg` (ISC). Each
/// case is a Lucide name; a place in the app names the icon for what it
/// shows, and `GlyphImage` draws it at a size and a stroke from `Icon`.
/// Foundation only, so the models can say which icon marks them.
enum Glyph: String, CaseIterable, Sendable {
    // The palette, the zoom bar and the shapes.
    case mousePointer = "mouse-pointer-2"
    case rectangle = "rectangle-horizontal"
    case circle
    case diamond
    case slash
    case arrowUpRight = "arrow-up-right"
    case stickyNote = "sticky-note"
    case plus
    case minus
    case maximize = "maximize-2"
    case moveHorizontal = "move-horizontal"
    case zoomIn = "zoom-in"
    case zoomOut = "zoom-out"

    // Chevrons, marks and verbs.
    case chevronDown = "chevron-down"
    case chevronUp = "chevron-up"
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case chevronsUpDown = "chevrons-up-down"
    case ellipsis
    case check
    case x
    case copy
    case trash
    case squareArrowOutUpRight = "square-arrow-out-up-right"
    case import_ = "import"

    // The shell.
    case house
    case panelLeft = "panel-left"
    case panelRight = "panel-right"
    case search
    case squarePen = "square-pen"
    case layoutDashboard = "layout-dashboard"
    case inbox
    case squareDashed = "square-dashed"
    case fileQuestion = "file-question-mark"

    // Files, by kind.
    case folder
    case file
    case fileText = "file-text"
    case fileType = "file-type"
    case bookOpenText = "book-open-text"
    case image
    case globe
    case codeXml = "code-xml"
    case link

    // Link cards, by provider.
    case circlePlay = "circle-play"
    case messageSquareText = "message-square-text"
    case pin
    case camera
    case music

    // The panel's Info rows.
    case clock
    case rotateCcwClock = "rotate-ccw-clock"
    case type
    case hash

    // The editor's blocks.
    case heading1 = "heading-1"
    case heading2 = "heading-2"
    case heading3 = "heading-3"
    case list
    case listOrdered = "list-ordered"
    case listChecks = "list-checks"
    case textQuote = "text-quote"
    case separatorHorizontal = "separator-horizontal"
    case table
    case squareFunction = "square-function"
    case radical
    case highlighter
    case calendar

    // The format bar's marks (revision 29).
    case bold
    case italic
    case underline
    case strikethrough
    case code

    // The style panel (revisions 32 and 39): fill, arrowheads, the
    // faces, the order and the verbs.
    case paintBucket = "paint-bucket"
    case square
    case moveLeft = "move-left"
    case moveRight = "move-right"
    case pencil
    // The style panel's order (revision 55), Excalidraw's four.
    case arrowDown = "arrow-down"
    case arrowUp = "arrow-up"
    case arrowDownToLine = "arrow-down-to-line"
    case arrowUpToLine = "arrow-up-to-line"
    case chevronsDownUp = "chevrons-down-up"

    // Words on the desk: their size (revision 33).
    case aLargeSmall = "a-large-small"

    // Where the words sit (revision 47).
    case textAlignStart = "text-align-start"
    case textAlignCenter = "text-align-center"
    case textAlignEnd = "text-align-end"

    // A canvas's own icon (revision 54), picked in the sidebar: the
    // default first, then subjects. `layoutDashboard`, `calendar`,
    // `music`, `camera`, `codeXml`, `globe` and `folder` are above.
    case star
    case heart
    case flag
    case bookmark
    case lightbulb
    case brain
    case bookOpen = "book-open"
    case graduationCap = "graduation-cap"
    case flaskConical = "flask-conical"
    case rocket
    case target
    case compass
    case map
    case briefcase
    case palette
    case penTool = "pen-tool"
    case cpu
    case bot
    case leaf
    case sparkles
    case coffee
    case users

    /// The icons a canvas can wear, in the picker's order.
    static let canvasIcons: [Glyph] = [
        .layoutDashboard, .star, .heart, .flag, .bookmark, .lightbulb,
        .brain, .bookOpen, .graduationCap, .flaskConical, .rocket, .target,
        .compass, .map, .briefcase, .calendar, .palette, .penTool,
        .codeXml, .cpu, .bot, .globe, .leaf, .sparkles,
        .music, .camera, .coffee, .users, .folder, .fileText,
    ]
}
