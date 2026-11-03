#!/usr/bin/env bash
# One-time setup on a new Mac. Installs nothing without asking.
set -euo pipefail
cd "$(dirname "$0")/.."
missing=()
for tool in xcodegen swiftlint swiftformat pre-commit jq; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
if ((${#missing[@]})); then
  read -r -p "Install ${missing[*]} via Homebrew? [y/N] " answer
  [[ "$answer" == [yY] ]] && brew install "${missing[@]}"
fi
[[ -f .env ]] || cp .env.example .env
pre-commit install
xcodegen generate --spec src/mac/project.yml
echo "Done. Open src/mac/Riftglass.xcodeproj or run scripts/build.sh"
