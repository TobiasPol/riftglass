# Releasing

## One-time setup
1. **Developer ID Application** certificate in the login keychain (`security find-identity -v -p codesigning`).
2. Notarization credentials, stored once in the keychain (Riftglass never sees the password):
   `xcrun notarytool store-credentials riftglass --apple-id <apple-id> --team-id CQ42H4H5MA`
   (prompts for an app-specific password from appleid.apple.com).
3. Sparkle EdDSA key: created with `generate_keys` from the Sparkle package
   (`build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/`). The private key stays in the keychain;
   the public key is `SUPublicEDKey` in `src/mac/App/Info.plist`. **Back up the private key**
   (`generate_keys -x <file>`), otherwise existing installs can no longer be updated.

## Each release
1. Update `CHANGELOG.md`, make sure `scripts/test.sh` and `scripts/lint.sh` pass.
2. `scripts/release.sh <version>` → signed, notarized, stapled `build/release/updates/Riftglass-<version>.dmg`
   and a regenerated `appcast.xml` (signed with the EdDSA key).
3. Commit `appcast.xml` and `CHANGELOG.md`, tag `v<version>`, push.
4. `gh release create v<version> build/release/updates/Riftglass-<version>.dmg --notes-file …`

The appcast is served from `main` (`SUFeedURL` → raw.githubusercontent.com), so the release asset must be
uploaded before the appcast commit reaches `main`.
