#!/usr/bin/env bash
# Runs `swift test` for every local package.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
for package in "$root"/src/mac/Packages/*/; do
  echo "==> $(basename "$package")"
  swift test --package-path "$package" --quiet
done
