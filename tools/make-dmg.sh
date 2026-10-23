#!/bin/bash
# Wraps Alex.app in the disk image people download (revision 68): the app
# at the left, a link to Applications at the right, big icons, nothing
# else. Usage: tools/make-dmg.sh Alex.app Alex-0.2.0.dmg
# Finder lays the window out through AppleScript; where there is no Finder
# to ask (a headless runner), the image still works, just unarranged.
set -euo pipefail

APP="$1"
OUT="$2"
VOLUME="Alex"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/stage"
ditto "$APP" "$WORK/stage/Alex.app"
ln -s /Applications "$WORK/stage/Applications"

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
# Attached where Finder can see it: Finder addresses a disk by its name.
ATTACHED="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | grep Apple_HFS)"
DEVICE="$(printf '%s' "$ATTACHED" | awk '{print $1}')"
MOUNTED="$(printf '%s' "$ATTACHED" | awk -F'\t' '{print $NF}')"
DISK="$(basename "$MOUNTED")"

if osascript <<OSA
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 460}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set position of item "Alex.app" of container window to {140, 150}
    set position of item "Applications" of container window to {400, 150}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
then echo "==> Laid out the window"; else echo "==> No Finder to lay out the window; left as it is"; fi
# The volume's icon is the app's: after the layout, since Finder deletes
# a `.VolumeIcon.icns` it finds while arranging the window.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNTED/.VolumeIcon.icns"
  SetFile -a C "$MOUNTED" 2>/dev/null || true
fi
rm -rf "$MOUNTED/.fseventsd"
sync
hdiutil detach -quiet "$DEVICE" || hdiutil detach -quiet -force "$DEVICE"

rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "==> Made $OUT"
