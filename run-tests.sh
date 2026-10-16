#!/bin/bash
# Runs every suite in Tests/. No Xcode project and no XCTest target, the same
# reasoning as Donna's: standalone harnesses compiled with swiftc are simpler,
# and the view suite (from M1) will need a real bundle anyway.
set -uo pipefail
cd "$(dirname "$0")"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
FAILED=0

run() {  # run <name> <binary> [args...]
  local name="$1"; shift
  echo ""
  echo "═══ $name ═══"
  if "$@"; then :; else FAILED=1; fi
}

# The design law (Style.swift header) has teeth: prose rules decay, linted
# rules don't. Each check greps for a banned pattern in the UI sources.
design_law() {
  local ok=0
  UI=$(find Sources/Alex/Views Sources/Alex/App -name '*.swift')
  lint() {  # lint <rule name> <pattern> [exclude-file-substring]
    local hits
    hits=$(grep -n "$2" $UI | { [ -n "${3:-}" ] && grep -v "$3" || cat; })
    if [ -n "$hits" ]; then
      echo "  ✗ $1"; echo "$hits" | sed 's/^/      /'; ok=1
    else
      echo "  ok    $1"
    fi
  }
  lint "no semibold or heavier (law 1)" "semibold\|weight: \.bold\|weight: \.heavy"
  lint "no italics in chrome (law 2)" "\.italic()"
  lint "no raw primary-opacity fills (law 4)" "Color.primary.opacity(0\.0" "Style.swift"
  lint "no off-scale radii (law 5)" "cornerRadius: \(5\|6\|7\|8\|9\|10\|11\|12\|14\|16\))"
  lint "no uppercase labels (law 6)" "\.uppercased()"
  lint "no ad-hoc shadows (law 8)" "\.shadow(color:" "Style.swift"
  lint "no colour literals (law 8)" "Color(light:\|Color\.white\|Color\.black\|(\.white)\|(\.black)\|NSColor\.white\|NSColor\.black\|Color(srgbRed\|NSColor(srgbRed\|NSColor(hex" "Style.swift"
  lint "no ad-hoc glyph or text sizes (law 8)" "\.system(size:" "Style.swift"
  lint "no inline motion (law 9)" "duration: [0-9]\|\.easeOut(\|\.easeInOut(\|\.easeIn(\|\.timingCurve(\|\.spring(\|\.bouncy\|\.snappy" "Style.swift"
  lint "no system menus: PopupMenu, not Menu or .contextMenu (revision 23)" "[^A-Za-z]Menu *[({]\|\.contextMenu\|\.menuStyle(" "PopupMenu.swift"
  lint "no system icons: Glyph, not SF Symbols (revision 24)" "systemName:\|systemImage:\|systemSymbolName\|Icon\.font("
  return $ok
}

run "Design law" design_law

# Pure Foundation files only: nothing here may import SwiftUI or AppKit.
MODELS=(Sources/Alex/Vault/VaultPath.swift Sources/Alex/Vault/VaultEntry.swift Sources/Alex/Vault/OfficeDocument.swift Sources/Alex/Vault/NewWorkspace.swift Sources/Alex/Canvas/Glyph.swift
        Sources/Alex/Canvas/NoteFormat.swift)
# The canvas suite adds the stores: Foundation, Combine and CoreServices, still no AppKit.
CANVAS=("${MODELS[@]}" Sources/Alex/Vault/Vault.swift Sources/Alex/Vault/VaultWatcher.swift Sources/Alex/Vault/VaultIndex.swift
        Sources/Alex/Canvas/JSONValue.swift Sources/Alex/Canvas/CanvasFile.swift
        Sources/Alex/Canvas/Frontmatter.swift Sources/Alex/Canvas/Placement.swift
        Sources/Alex/Canvas/Viewport.swift Sources/Alex/Canvas/Camera.swift Sources/Alex/Canvas/CardPreview.swift
        Sources/Alex/Canvas/Grip.swift Sources/Alex/Canvas/LinkCard.swift
        Sources/Alex/Canvas/Shape.swift Sources/Alex/Canvas/Folders.swift
        Sources/Alex/Canvas/CanvasStore.swift Sources/Alex/Canvas/CanvasDelta.swift Sources/Alex/Canvas/VaultConfig.swift
        Sources/Alex/Canvas/Search.swift Sources/Alex/Canvas/ToolKeys.swift Sources/Alex/Canvas/Clipboard.swift Sources/Alex/Canvas/Excalidraw.swift
        Sources/Alex/Canvas/Freehand.swift
        Sources/Alex/App/Launch.swift)

echo ""
echo "==> Compiling suites"
swiftc -O -o "$SCRATCH/model" "${MODELS[@]}" Tests/ModelTests/main.swift || exit 1
swiftc -O -o "$SCRATCH/canvas" "${CANVAS[@]}" Tests/CanvasTests/main.swift || exit 1
swiftc -O -o "$SCRATCH/door" "${CANVAS[@]}" Sources/Alex/Door/McpRpc.swift Tests/DoorTests/main.swift || exit 1

run "Model logic" "$SCRATCH/model"
run "Canvas store" "$SCRATCH/canvas"
run "The door"     "$SCRATCH/door"

echo ""
if [ "$FAILED" -eq 0 ]; then echo "✓ All suites passed"; else echo "✗ Failures above"; fi
exit "$FAILED"
