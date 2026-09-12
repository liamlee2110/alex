#!/bin/bash
# Builds Alex.app: a release binary wrapped in an ad-hoc signed bundle with a
# stable bundle id. Adapted from Donna's build.sh.
set -euo pipefail
cd "$(dirname "$0")"

APP="Alex.app"
BUNDLE_ID="com.liamlee.alex"
VERSION="0.1.0"

# One slice per triple through SwiftPM's native build, then lipo. A single
# `--arch a --arch b` invocation routes through the Xcode build system,
# which on Swift 6.1 rejects the package's language-mode setting.
echo "==> Compiling arm64"
swift build -c release --triple arm64-apple-macosx15.0
ARM_BIN="$(swift build -c release --triple arm64-apple-macosx15.0 --show-bin-path)"
echo "==> Compiling x86_64"
swift build -c release --triple x86_64-apple-macosx15.0
X86_BIN="$(swift build -c release --triple x86_64-apple-macosx15.0 --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM_BIN/Alex" "$X86_BIN/Alex" -output "$APP/Contents/MacOS/Alex"
lipo -info "$APP/Contents/MacOS/Alex"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
find "$ARM_BIN" -maxdepth 1 -type d -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

echo "==> Built $(pwd)/$APP"
