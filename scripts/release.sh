#!/bin/bash
# Builds a notarized, Sparkle-signed release of Sticky Windows.
#
#   scripts/release.sh 1.0.0 [build-number]
#
# Produces in build/release/:
#   Sticky Windows.app                 Developer ID signed, notarized, stapled
#   StickyWindows-<version>.dmg        notarized and stapled
#   appcast item (printed) and $SITE_DIR/appcast.xml updated
#
# Needs, locally or in CI:
#   - "Developer ID Application" certificate for team F5N4RH3674 in the keychain
#   - notarytool credentials: NOTARY_PROFILE (keychain profile name, default stickywindows-notary) or
#     NOTARY_KEY_ID + NOTARY_ISSUER_ID + NOTARY_KEY_FILE (App Store Connect API key)
#   - Sparkle private key: in the login keychain (generate_keys) or SPARKLE_PRIVATE_KEY_FILE
#   - xcodegen (brew install xcodegen)
set -euo pipefail

VERSION="${1:?usage: release.sh <version> [build]}"
BUILD="${2:-$(date +%Y%m%d%H%M)}"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/aaronfisher/StickyWindows/releases/download/v$VERSION/}"
# Checkout of the public site repo (website + appcast + releases); the appcast is read from and written there.
SITE_DIR="${SITE_DIR:-$ROOT/../sticky-windows}"
NOTARY_PROFILE="${NOTARY_PROFILE:-stickywindows-notary}"
# Full identity, not just the type: a keychain with Developer ID certificates for two teams makes the
# short form ambiguous.
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: The Shirley Company LLC (F5N4RH3674)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/StickyWindows.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Sticky Windows.app"
DMG="$OUT/StickyWindows-$VERSION.dmg"
rm -rf "$OUT"; mkdir -p "$OUT"

# Readable xcodebuild output when xcbeautify is installed; otherwise just the tail.
xcbeautify_or_tail() { if command -v xcbeautify >/dev/null; then xcbeautify; else tail -20; fi; }

notary_args() {
  if [[ -n "${NOTARY_KEY_ID:-}" ]]; then
    echo --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
  else
    echo --keychain-profile "$NOTARY_PROFILE"
  fi
}

echo "== Generating project"
xcodegen generate >/dev/null

echo "== Archiving $VERSION ($BUILD)"
xcodebuild -project StickyWindows.xcodeproj -scheme StickyWindows -configuration Release \
  -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  archive | xcbeautify_or_tail

echo "== Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist scripts/ExportOptions.plist | xcbeautify_or_tail
test -d "$APP"

echo "== Notarizing app"
ditto -c -k --keepParent "$APP" "$OUT/app.zip"
# shellcheck disable=SC2046
xcrun notarytool submit "$OUT/app.zip" $(notary_args) --wait
xcrun stapler staple "$APP"
spctl --assess --type execute -vv "$APP"

echo "== Building disk image"
scripts/make-dmg.sh "$APP" "$DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

echo "== Notarizing disk image"
# shellcheck disable=SC2046
xcrun notarytool submit "$DMG" $(notary_args) --wait
xcrun stapler staple "$DMG"

echo "== Signing for Sparkle"
SPARKLE_BIN="$(find build/DerivedData/SourcePackages/artifacts -type d -path '*sparkle/Sparkle/bin' | head -1)"
SIGN_ARGS=()
[[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]] && SIGN_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
"$SPARKLE_BIN/sign_update" "${SIGN_ARGS[@]}" "$DMG" > "$OUT/sparkle-signature.txt"
cat "$OUT/sparkle-signature.txt"

echo "== Updating appcast"
mkdir -p "$OUT/appcast"
cp "$DMG" "$OUT/appcast/"
[[ -f "$SITE_DIR/appcast.xml" ]] && cp "$SITE_DIR/appcast.xml" "$OUT/appcast/appcast.xml"
"$SPARKLE_BIN/generate_appcast" "${SIGN_ARGS[@]}" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://stickywindows.com/" \
  -o "$OUT/appcast/appcast.xml" "$OUT/appcast"
if [[ -d "$SITE_DIR" ]]; then
  cp "$OUT/appcast/appcast.xml" "$SITE_DIR/appcast.xml"
  # The website shows this under its download button.
  cat > "$SITE_DIR/version.json" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD",
  "date": "$(date -u +%Y-%m-%d)",
  "download": "${DOWNLOAD_PREFIX}StickyWindows-$VERSION.dmg",
  "notes": "https://github.com/aaronfisher/StickyWindows/releases/tag/v$VERSION",
  "minimumSystemVersion": "15.0"
}
JSON
fi

echo "== Done"
echo "  $APP"
echo "  $DMG"
echo "  appcast + version.json: copied to $SITE_DIR if present; commit and push them there"
