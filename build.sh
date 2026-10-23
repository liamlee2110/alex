#!/bin/bash
# Builds Alex.app: a release binary wrapped in a signed bundle with a stable
# bundle id. Adapted from Donna's build.sh.
#
# Ad-hoc signed by default. `SIGN_IDENTITY="Developer ID Application: …"`
# signs it for release with the hardened runtime and a secure timestamp,
# which notarisation needs (revision 68). `VERSION` and `BUILD` default to
# the latest tag and the commit count; the release workflow sets both.
# Sparkle.framework goes in Contents/Frameworks, signed inside out, with
# the appcast's address and the EdDSA public key in Info.plist.
set -euo pipefail
cd "$(dirname "$0")"

APP="Alex.app"
BUNDLE_ID="com.liamlee.alex"
LATEST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"
VERSION="${VERSION:-${LATEST_TAG#v}}"
# CFBundleVersion only rises: the updater compares it, not the version.
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
# The feed address is in every installed copy for good, so it is on Liam's
# own domain, which forwards to the latest GitHub release (revision 68).
FEED_URL="https://liamle.me/alex/appcast.xml"
SPARKLE_KEY="$(cat sparkle_public_key)"

# One slice per triple, then lipo. A single `--arch a --arch b` invocation
# routes through the Xcode build system, which on Swift 6.1 rejects the
# package's language-mode setting. From Swift 6.4 both triples build into
# one products folder, so each slice is copied out before the next build.
SLICES="$(mktemp -d)"
trap 'rm -rf "$SLICES"' EXIT
for ARCH in arm64 x86_64; do
  echo "==> Compiling $ARCH"
  swift build -c release --triple "$ARCH-apple-macosx15.0"
  BIN="$(swift build -c release --triple "$ARCH-apple-macosx15.0" --show-bin-path)"
  mkdir -p "$SLICES/$ARCH"
  cp "$BIN/Alex" "$SLICES/$ARCH/Alex"
  find "$BIN" -maxdepth 1 -type d -name "*.bundle" -exec cp -R {} "$SLICES/$ARCH/" \;
  # Sparkle's framework is universal already; one copy does.
  [ -d "$SLICES/Sparkle.framework" ] || ditto "$BIN/Sparkle.framework" "$SLICES/Sparkle.framework"
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create "$SLICES/arm64/Alex" "$SLICES/x86_64/Alex" -output "$APP/Contents/MacOS/Alex"
lipo -info "$APP/Contents/MacOS/Alex"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The starter vault "New workspace…" copies (revision 31), dot files and
# all: SwiftPM's resources would drop .mcp.json and .gitignore.
cp -R vault-template "$APP/Contents/Resources/vault-template"
find "$SLICES/arm64" -maxdepth 1 -type d -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;
ditto "$SLICES/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
# Alex is not sandboxed, so Sparkle's XPC services are dead weight (its docs).
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Alex</string>
  <key>CFBundleDisplayName</key><string>Alex</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Alex</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>$BUNDLE_ID.canvas-clip</string>
      <key>UTTypeDescription</key><string>Alex canvas clip</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Inside out: Sparkle's helpers, then the framework, then the app.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "==> Signing (ad-hoc)"
  sign() { codesign --force --sign - "$@"; }
else
  echo "==> Signing ($SIGN_IDENTITY)"
  sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }
fi
sign "$SPK/Autoupdate"
sign "$SPK/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --deep "$APP"

echo "==> Built $(pwd)/$APP ($VERSION, build $BUILD)"
