#!/bin/bash
# Makes a compressed disk image holding the app and an Applications link.
#   scripts/make-dmg.sh "path/to/Sticky Windows.app" out.dmg
set -euo pipefail
APP="$1"; DMG="$2"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Sticky Windows" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
echo "$DMG"
