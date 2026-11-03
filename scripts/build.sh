#!/usr/bin/env bash
# Generates the Xcode project and builds the app. Extra args go to xcodebuild, e.g. CODE_SIGNING_ALLOWED=NO.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
xcodegen generate --spec "$root/src/mac/project.yml" --quiet
xcodebuild -project "$root/src/mac/Riftglass.xcodeproj" -scheme Riftglass \
  -configuration "${CONFIGURATION:-Debug}" -derivedDataPath "$root/build/DerivedData" -quiet build "$@"
echo "Built: $root/build/DerivedData/Build/Products/${CONFIGURATION:-Debug}/Riftglass.app"
