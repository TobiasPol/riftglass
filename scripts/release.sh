#!/usr/bin/env bash
# Builds a Developer-ID-signed, notarized DMG and regenerates appcast.xml for Sparkle.
#
# Prerequisites (one-time, see docs/RELEASING.md):
#   - "Developer ID Application" certificate in the login keychain
#   - xcrun notarytool store-credentials riftglass   (profile name via NOTARY_PROFILE)
#   - Sparkle EdDSA key in the keychain (generate_keys from the Sparkle package)
# Usage: scripts/release.sh 0.2.0
set -euo pipefail
version="${1:?usage: scripts/release.sh <version>}"
profile="${NOTARY_PROFILE:-riftglass}"
team="CQ42H4H5MA"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/release"
derived="$out/DerivedData"
rm -rf "$out/stage" && mkdir -p "$out/stage" "$out/updates"

echo "==> Build $version (Release, Developer ID)"
xcodegen generate --spec "$root/src/mac/project.yml" --quiet
xcodebuild -project "$root/src/mac/Riftglass.xcodeproj" -scheme Riftglass -configuration Release \
  -derivedDataPath "$derived" -quiet build \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$(git -C "$root" rev-list --count HEAD)" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"
app="$derived/Build/Products/Release/Riftglass.app"
codesign --verify --deep --strict --verbose=1 "$app"

echo "==> Notarize app"
ditto -c -k --keepParent "$app" "$out/Riftglass.zip"
xcrun notarytool submit "$out/Riftglass.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"

echo "==> DMG"
dmg="$out/updates/Riftglass-$version.dmg"
cp -R "$app" "$out/stage/" && ln -s /Applications "$out/stage/Applications"
hdiutil create -volname "Riftglass" -srcfolder "$out/stage" -ov -format UDZO "$dmg" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

echo "==> Appcast"
tools="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$tools/generate_appcast" --download-url-prefix "https://github.com/TobiasPol/riftglass/releases/download/v$version/" \
  -o "$root/appcast.xml" "$out/updates"
echo "Done: $dmg – commit appcast.xml, then: gh release create v$version \"$dmg\""
