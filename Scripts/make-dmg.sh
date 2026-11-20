#!/bin/zsh
# Builds dist/Swoosh-<version>.dmg: the app plus an Applications shortcut to drag onto.
#
#   Scripts/make-dmg.sh               test, build, package
#   NOTARY_PROFILE=name Scripts/make-dmg.sh
#       also notarize and staple (needs a "Developer ID Application" certificate
#       and a profile saved with `xcrun notarytool store-credentials name`)
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh "$@"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/Swoosh-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R build/Swoosh.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Swoosh $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

IDENTITY="${SWOOSH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

shasum -a 256 "$DMG"
echo "Created $DMG"
