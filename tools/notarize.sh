#!/bin/bash
# Sends an app or a disk image to Apple's notary service, waits, and
# staples the ticket to it so it opens offline (revision 68).
# Usage: tools/notarize.sh Alex.app | Alex-0.2.0.dmg
# Credentials, either:
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID  (an App Store Connect API key; CI)
#   NOTARY_PROFILE                                    (a `notarytool store-credentials` profile; this Mac)
set -euo pipefail

TARGET="$1"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
else
  AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
fi

SUBMIT="$TARGET"
if [ -d "$TARGET" ]; then
  # An app goes up zipped; the ticket is stapled to the app itself.
  SUBMIT="$(mktemp -d)/$(basename "$TARGET").zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi

echo "==> Notarising $(basename "$TARGET")"
OUTPUT="$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --timeout 30m 2>&1)" || true
printf '%s\n' "$OUTPUT"
if ! printf '%s' "$OUTPUT" | grep -q "status: Accepted"; then
  ID="$(printf '%s' "$OUTPUT" | awk '/^  id:/ {print $2; exit}')"
  [ -n "$ID" ] && xcrun notarytool log "$ID" "${AUTH[@]}" || true
  echo "✗ Notarisation failed" >&2
  exit 1
fi

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
